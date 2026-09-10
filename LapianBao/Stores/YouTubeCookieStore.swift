//
//  YouTubeCookieStore.swift
//  LapianBao
//
//  设置页 "浏览器 cookies" 的一键配置/更新:由用户手动授权从 Chrome
//  导出会话,供 YouTube、小红书、Bilibili、抖音遇到平台风控时使用。
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
    // Export locally through the bundled yt-dlp API. No unrelated web page has to
    // load, and decryption warnings must not be silenced by --no-warnings.
    nonisolated static let cookieExportScript = """
    import os, sys
    os.umask(0o077)
    sys.path.insert(0, sys.argv[1])
    from yt_dlp import YoutubeDL
    with YoutubeDL({'cookiesfrombrowser': (sys.argv[2],),
                    'cookiefile': sys.argv[3], 'cachedir': False,
                    'quiet': True}) as ydl:
        ydl.cookiejar
    """
    // 首次运行会弹钥匙串授权("访问 Chrome Safe Storage"),给用户留足确认时间。
    nonisolated static let refreshTimeout: TimeInterval = 240
    nonisolated static let autoRefreshCooldown: TimeInterval = 15 * 60

    var hasReadableCookieFile: Bool {
        guard let path = configuredFilePath, !path.isEmpty else { return false }
        return FileManager.default.isReadableFile(atPath: path)
    }

    var statusDetail: String {
        Self.statusDetail(phase: refreshPhase, path: configuredFilePath,
                          fileAvailable: hasReadableCookieFile)
    }

    nonisolated static func statusDetail(phase: RefreshPhase, path: String?, fileAvailable: Bool) -> String {
        switch phase {
        case .running: return L10n.text("正在读取 Chrome；如弹出钥匙串授权，请点允许")
        case .failed(let message):
            return (fileAvailable ? L10n.text("上次文件已保留；本次同步失败：") : L10n.text("未同步 cookies：")) + message
        case .idle, .succeeded:
            if fileAvailable {
                let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "cookies.txt"
                return L10n.text("\(name) · 文件已保存，平台登录有效性未验证")
            }
            return path == nil ? L10n.text("未配置（可选）；公开链接可能无需 cookies") : L10n.text("cookies 文件不可读取，请重新同步")
        }
    }

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
        refreshPhase = .running
        guard let ytdlp = await LibraryStore.readyYTDLPURL() else {
            refreshPhase = .failed(YTDLPRuntime.unavailableMessage)
            return
        }
        guard let exportURL = Self.managedCookieFileURL() else {
            refreshPhase = .failed(L10n.text("无法定位 Application Support 目录"))
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
            .appendingPathComponent("browser-cookies.txt")
    }

    nonisolated static func runRefresh(ytdlp: URL, exportURL: URL) -> RefreshOutcome {
        let directoryURL = exportURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        // 先导出到临时文件并验证,成功才原子替换,避免把正在使用的旧 cookie 冲坏。
        let tempURL = directoryURL.appendingPathComponent(exportURL.lastPathComponent + ".refresh")
        try? FileManager.default.removeItem(at: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = ExternalProcessRunner.run(
            executableURL: YTDLPRuntime.pythonURL,
            arguments: ["-I", "-B", "-c", cookieExportScript, ytdlp.path, browserSourceName, tempURL.path],
            environment: YTDLPRuntime.environment,
            qualityOfService: .utility,
            timeout: refreshTimeout
        )

        if result.succeeded, let filteredCookies = filteredBrowserCookieContents(at: tempURL) {
            do {
                try filteredCookies.write(to: tempURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)
                if FileManager.default.fileExists(atPath: exportURL.path) {
                    _ = try FileManager.default.replaceItemAt(exportURL, withItemAt: tempURL, options: .usingNewMetadataOnly)
                } else {
                    try FileManager.default.moveItem(at: tempURL, to: exportURL)
                }
                return .success
            } catch {
                return .failure(L10n.text("写入 cookies 文件失败:\(error.localizedDescription)"))
            }
        }
        return .failure(refreshFailureMessage(result))
    }

    nonisolated static func filteredBrowserCookieContents(at fileURL: URL) -> String? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let allowedDomains = [
            "youtube.com", "googlevideo.com",
            "xiaohongshu.com", "xhslink.com",
            "bilibili.com", "b23.tv",
            "douyin.com", "iesdouyin.com",
            "tiktok.com"
        ]
        var outputLines = ["# Netscape HTTP Cookie File", "# Filtered by LapianBao to supported platform domains."]
        var keptCookieCount = 0

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let fieldsLine: String
            if line.hasPrefix("#HttpOnly_") {
                fieldsLine = String(line.dropFirst("#HttpOnly_".count))
            } else if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            } else {
                fieldsLine = line
            }

            let fields = fieldsLine.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 7, !fields[6].isEmpty,
                  let expires = Double(fields[4]), expires.isFinite,
                  expires == 0 || expires > Date().timeIntervalSince1970
            else { continue }
            let domain = String(fields[0]).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard allowedDomains.contains(where: { domain == $0 || domain.hasSuffix(".\($0)") }) else {
                continue
            }
            outputLines.append(line)
            keptCookieCount += 1
        }

        guard keptCookieCount > 0 else { return nil }
        return outputLines.joined(separator: "\n") + "\n"
    }

    nonisolated static func hasExportedBrowserCookies(at fileURL: URL) -> Bool {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
        return contents.split(whereSeparator: \.isNewline).contains { rawLine in
            var line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#HttpOnly_") {
                line.removeFirst("#HttpOnly_".count)
            } else if line.hasPrefix("#") {
                return false
            }
            return !line.isEmpty && line.split(separator: "\t").count >= 7
        }
    }

    nonisolated static func refreshFailureMessage(_ result: ExternalProcessRunner.Result) -> String {
        if result.didTimeOut {
            return L10n.text("读取超时:如果系统弹出了钥匙串授权,请点\"允许\"后再试一次")
        }

        let errorText = result.errorText
        let lowercased = errorText.lowercased()
        if lowercased.contains("keychain") || lowercased.contains("decrypt") || lowercased.contains("keyring") {
            return L10n.text("Chrome cookies 解密失败；请允许 Chrome Safe Storage 钥匙串访问后重试")
        }
        if lowercased.contains("could not find") && lowercased.contains("cookies") {
            return L10n.text("未找到 Chrome 的 cookie 数据，请确认 Chrome 已安装并至少打开过一个目标平台")
        }
        if lowercased.contains("sign in to confirm") || lowercased.contains("not a bot") {
            return L10n.text("Chrome 会话读取失败，请先在 Chrome 打开目标平台后再重试")
        }
        if result.succeeded {
            return L10n.text("未找到受支持平台的有效 cookies；请先在 Chrome 打开并登录目标平台")
        }

        let lastLine = errorText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return lastLine ?? L10n.text("配置失败,请重试")
    }
}
