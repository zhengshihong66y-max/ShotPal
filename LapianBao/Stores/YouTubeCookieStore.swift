//
//  YouTubeCookieStore.swift
//  LapianBao
//
//  设置页 "YouTube cookies" 的一键配置/更新:从 Chrome 读取 cookie、
//  用公开视频验证能通过 YouTube 登录验证,成功才写入配置。
//  触发方式仅两种:设置页按钮手动点击;或用户已启用 cookie 方案后,
//  下载遇到 YouTube 登录验证失败时按冷却自动更新一次并重试。
//  这是全仓库唯一允许使用 --cookies-from-browser 的地方,
//  不做任何自动的账号状态识别或收藏列表读取。
//

import Combine
import Foundation

@MainActor
final class YouTubeCookieStore: ObservableObject {
    enum RefreshPhase: Equatable {
        case idle
        case running
        case succeeded(Date)
        case failed(String)
    }

    nonisolated enum RefreshOutcome: Sendable {
        case success
        case failure(String)
    }

    @Published var refreshPhase: RefreshPhase = .idle
    @Published var configuredFilePath: String? = AppSettings.youtubeCookieFilePath

    private var refreshTask: Task<Void, Never>?
    private var lastAutoRefreshAttemptAt: Date?

    nonisolated static let browserSourceName = "chrome"
    nonisolated static let validationVideoURL = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
    // 首次运行会弹钥匙串授权("访问 Chrome Safe Storage"),给用户留足确认时间。
    nonisolated static let refreshTimeout: TimeInterval = 240
    nonisolated static let autoRefreshCooldown: TimeInterval = 15 * 60

    var isRefreshing: Bool {
        refreshPhase == .running
    }

    func refreshFromBrowser() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.performRefresh()
            self?.refreshTask = nil
        }
    }

    /// 下载遇到 YouTube 登录验证失败时的自动更新:仅当用户已启用 cookie 方案时
    /// 生效,带冷却避免反复读取浏览器。返回是否拿到了新的可用 cookie。
    func refreshAfterBotCheckIfNeeded() async -> Bool {
        guard configuredFilePath != nil else { return false }
        if refreshTask == nil {
            if let lastAutoRefreshAttemptAt,
               Date().timeIntervalSince(lastAutoRefreshAttemptAt) < Self.autoRefreshCooldown {
                return false
            }
            lastAutoRefreshAttemptAt = Date()
            refreshTask = Task { [weak self] in
                await self?.performRefresh()
                self?.refreshTask = nil
            }
        }
        await refreshTask?.value
        if case .succeeded = refreshPhase { return true }
        return false
    }

    private func performRefresh() async {
        guard let ytdlp = LibraryStore.usableYTDLPURL() else {
            refreshPhase = .failed("未找到可用的 yt-dlp,请先完成上方的下载器自检")
            return
        }
        guard let exportURL = Self.managedCookieFileURL() else {
            refreshPhase = .failed("无法定位 Application Support 目录")
            return
        }

        refreshPhase = .running
        let outcome = await Task.detached(priority: .userInitiated) {
            Self.runRefresh(ytdlp: ytdlp, exportURL: exportURL)
        }.value
        switch outcome {
        case .success:
            AppSettings.youtubeCookieFilePath = exportURL.path
            AppSettings.youtubeCookieFileBookmark = nil
            configuredFilePath = exportURL.path
            refreshPhase = .succeeded(Date())
        case .failure(let message):
            refreshPhase = .failed(message)
        }
    }

    nonisolated static func managedCookieFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LapianBao", isDirectory: true)
            .appendingPathComponent("youtube-cookies.txt")
    }

    nonisolated static func runRefresh(ytdlp: URL, exportURL: URL) -> RefreshOutcome {
        let directoryURL = exportURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        // 先导出到临时文件并验证,成功才原子替换,避免把正在使用的旧 cookie 冲坏。
        let tempURL = directoryURL.appendingPathComponent(exportURL.lastPathComponent + ".refresh")
        try? FileManager.default.removeItem(at: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var attemptExtraArguments: [[String]] = [[]]
        if let proxyURL = LibraryStore.currentYTDLPProxyURLs().first {
            attemptExtraArguments.append(["--proxy", proxyURL])
        }

        var lastFailure = "未知错误"
        for extraArguments in attemptExtraArguments {
            let result = ExternalProcessRunner.run(
                executableURL: ytdlp,
                arguments: [
                    "--cookies-from-browser", browserSourceName,
                    "--cookies", tempURL.path,
                    "--socket-timeout", "20",
                    "--retries", "1",
                    "--extractor-retries", "1",
                    "--print", "title",
                    "--no-warnings"
                ] + extraArguments + [validationVideoURL],
                environment: LibraryStore.downloaderProcessEnvironment(),
                timeout: refreshTimeout
            )

            if result.succeeded, FileManager.default.fileExists(atPath: tempURL.path) {
                do {
                    if FileManager.default.fileExists(atPath: exportURL.path) {
                        _ = try FileManager.default.replaceItemAt(exportURL, withItemAt: tempURL)
                    } else {
                        try FileManager.default.moveItem(at: tempURL, to: exportURL)
                    }
                    return .success
                } catch {
                    return .failure("写入 cookies 文件失败:\(error.localizedDescription)")
                }
            }
            lastFailure = refreshFailureMessage(result)
        }
        return .failure(lastFailure)
    }

    nonisolated static func refreshFailureMessage(_ result: ExternalProcessRunner.Result) -> String {
        if result.didTimeOut {
            return "读取超时:如果系统弹出了钥匙串授权,请点\"允许\"后再试一次"
        }

        let errorText = result.errorText
        let lowercased = errorText.lowercased()
        if lowercased.contains("could not find") && lowercased.contains("cookies") {
            return "未找到 Chrome 的 cookie 数据,请确认 Chrome 已安装并打开过 youtube.com"
        }
        if lowercased.contains("sign in to confirm") || lowercased.contains("not a bot") {
            return "Chrome 里的 YouTube 会话未通过验证,请先在 Chrome 打开并登录 youtube.com 再重试"
        }
        if lowercased.contains("unable to download") || lowercased.contains("timed out") {
            return "网络验证失败,请确认代理可用后重试"
        }

        let lastLine = errorText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return lastLine ?? "配置失败,请重试"
    }
}
