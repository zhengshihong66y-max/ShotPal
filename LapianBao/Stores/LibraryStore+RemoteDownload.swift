//
//  LibraryStore+RemoteDownload.swift
//  LapianBao
//
//  Split from LibraryStore.swift.
//

import AppKit
import AVFoundation
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

extension LibraryStore {
    @concurrent nonisolated static func downloadVideo(
        from sourceURL: URL,
        into libraryURL: URL,
        platform: String,
        endpoint: String,
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil,
        transcodingCallback: (@Sendable (Double?) -> Void)? = nil,
        finalizingCallback: (@Sendable (Double) -> Void)? = nil,
        processCallback: (@Sendable (Process?) -> Void)? = nil
    ) async throws -> DownloadedVideoResult {
        let destinationDirectory = mediaFolder(in: libraryURL, named: videoFolderName)

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        var rawURL: URL?
        var authorName: String?
        var sourceTitle: String?

        var ytdlpFailure: Error?
        var xiaohongshuNativeFailure: Error?
        var routeFailures: [String] = []
        let ytdlp = await readyYTDLPURL()
        try Task.checkCancellation()
        if ytdlp == nil { routeFailures.append(YTDLPRuntime.unavailableMessage) }
        let isBilibiliSource = platform == "Bilibili" || isBilibiliURL(sourceURL)

        // Instagram 图文轮播里可能有多段视频：先按轮播顺序打包成一个视频再入库。
        if rawURL == nil, platform == "Instagram",
           let ytdlp,
           !Task.isCancelled,
           let result = try await downloadInstagramCarouselBundleIfNeeded(
               executableURL: ytdlp,
               sourceURL: sourceURL,
               destinationDirectory: destinationDirectory,
               progressCallback: progressCallback,
               processCallback: processCallback
           ) {
            rawURL = result.url
            authorName = result.authorName
            sourceTitle = result.sourceTitle
        }

        // 1. yt-dlp；平台可用性仍受网络、登录和上游接口变化影响。
        if rawURL == nil, let ytdlp,
           !Task.isCancelled {
            let isYouTubeSource = isYouTubeURL(sourceURL)
            // 配置了 cookies.txt 时优先带 cookie 请求;被风控的出口 IP 上匿名尝试必然失败,
            // 先跑完匿名再退 cookie 会让每次下载都白等一轮重试。
            let cookieFileURL = usesBrowserCookieJar(for: sourceURL)
                ? configuredBrowserCookieFileURL()
                : nil
            let didStartCookieAccess = cookieFileURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if didStartCookieAccess {
                    cookieFileURL?.stopAccessingSecurityScopedResource()
                }
            }
            let cookieAttempts = isYouTubeSource
                ? ytdlpYouTubeCookieFileArgumentAttempts(cookieFileURL: cookieFileURL)
                : ytdlpBrowserCookieFileArgumentAttempts(
                    cookieFileURL: cookieFileURL,
                    sourceURL: sourceURL
                )
            let attempts = cookieAttempts + ytdlpArgumentAttempts(for: sourceURL)
            var authenticationRetry = YTDLPAuthenticationRetryState()
            var sawYouTubeLoginVerification = false
            // YouTube 走免探测快速启动:单进程一次解析直接开下,命名与进度
            // 信息由下载进程自己的打印行提供;其他平台保持原有探测行为。
            let usesFastStart = isYouTubeURL(sourceURL)
                && instagramCarouselItemIndex(from: sourceURL) == nil
            for attempt in attempts {
                if isYouTubeSource, !authenticationRetry.allows(arguments: attempt.arguments) { continue }
                do {
                    let result = try await runYTDLPOnce(
                        executableURL: ytdlp,
                        sourceURL: sourceURL,
                        destinationDirectory: destinationDirectory,
                        extraArguments: attempt.arguments,
                        skipVideoInfoProbe: usesFastStart,
                        progressCallback: progressCallback,
                        processCallback: processCallback
                    )
                    rawURL = result.url
                    authorName = result.authorName
                    sourceTitle = result.sourceTitle
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try Task.checkCancellation()
                    routeFailures.append(downloadRouteFailure(route: "yt-dlp \(attempt.label)", error: error))
                    if let failure = error as? YTDLPDownloaderFailure {
                        authorName = authorName ?? failure.authorName
                    }
                    if isYouTubeSource, isYouTubeBotVerificationFailure(error.localizedDescription) {
                        sawYouTubeLoginVerification = true
                        authenticationRetry.recordFailure(error.localizedDescription, arguments: attempt.arguments)
                        ytdlpFailure = error
                        // Exhaust the remaining authenticated clients/routes before refreshing cookies.
                        continue
                    }
                    ytdlpFailure = error
                }
            }

            if rawURL == nil, let verificationFailure = authenticationRetry.verificationFailure {
                throw YTDLPDownloaderFailure(message: verificationFailure, authorName: authorName)
            }
            if rawURL == nil, sawYouTubeLoginVerification, cookieFileURL == nil, let ytdlpFailure {
                throw ytdlpFailure
            }
            if rawURL == nil, let ytdlpFailure, isHardYouTubeYTDLPFailure(ytdlpFailure) {
                throw ytdlpFailure
            }
        }

        // 2. 小红书：原生页面解析（yt-dlp 对需要登录的内容失效时接手）
        if rawURL == nil, platform == "小红书" {
            do {
                let result = try await downloadXiaoHongShuNative(
                    from: sourceURL,
                    destinationDirectory: destinationDirectory,
                    progressCallback: progressCallback
                )
                rawURL = result.url
                authorName = authorName ?? result.authorName
                sourceTitle = sourceTitle ?? result.sourceTitle
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                xiaohongshuNativeFailure = error
                routeFailures.append(downloadRouteFailure(route: L10n.text("小红书页面解析"), error: error))
            }
        }

        // 3. 用户自定义 API
        if rawURL == nil,
           instagramCarouselItemIndex(from: sourceURL) == nil,
           !endpoint.isEmpty {
            do {
                let result = try await importViaConfiguredAPI(
                    sourceURL: sourceURL, endpoint: endpoint,
                    destinationDirectory: destinationDirectory, progressCallback: progressCallback
                )
                rawURL = result
                sourceTitle = sourceTitle ?? Self.sourceTitle(from: [], fileName: result.lastPathComponent)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                routeFailures.append(downloadRouteFailure(route: L10n.text("自定义 API"), error: error))
            }
        }
        // Public Cobalt requires service authorization; never attempt an unauthenticated fallback.
        try Task.checkCancellation()

        guard let downloadedURL = rawURL else {
            if isYouTubeURL(sourceURL), let ytdlpFailure {
                throw ytdlpFailure
            }
            if isBilibiliSource {
                if let ytdlpFailure {
                    throw ytdlpFailure
                }
                if ytdlp == nil {
                    throw RemoteImportError.downloaderFailed(L10n.text("Bilibili 下载需要 yt-dlp，请先在设置里运行 yt-dlp 自检。"))
                }
            }
            if platform == "小红书", let xiaohongshuNativeFailure {
                throw xiaohongshuNativeFailure
            }
            throw RemoteImportError.downloaderFailed(routeFailures.isEmpty
                ? L10n.text("没有可用的下载途径；请查看下载器自检或配置已授权的自定义 API。")
                : routeFailures.suffix(5).joined(separator: "\n"))
        }

        // 后处理：VP9 / AV1 在 MP4 容器中不被 macOS AVFoundation 支持，转码为 H.264。
        // 收尾信号只在转码结束后发一次:转码前抢发 finalizing(1) 会让进度条
        // 先假装 100% 再被转码进度拽回去。
        let finalURL = await transcodeToH264IfNeeded(downloadedURL, progressCallback: transcodingCallback) ?? downloadedURL
        finalizingCallback?(1)
        return DownloadedVideoResult(
            url: finalURL,
            authorName: authorName,
            sourceTitle: sourceTitle ?? Self.sourceTitle(from: [], fileName: finalURL.lastPathComponent)
        )
    }

    nonisolated static func downloadRouteFailure(route: String, error: Error) -> String {
        let text = error.localizedDescription
        let lower = text.lowercased()
        let category: String
        if lower.contains("sign in") || lower.contains("login") || lower.contains("cookie") || text.contains("登录") {
            category = L10n.text("登录/会话验证")
        } else if lower.contains("unsupported url") {
            category = L10n.text("不支持的链接")
        } else if lower.contains("timed out") || lower.contains("timeout") || text.contains("超时") {
            category = L10n.text("网络超时")
        } else if lower.contains("403") || lower.contains("429") || lower.contains("forbidden") {
            category = L10n.text("平台拒绝请求")
        } else { category = L10n.text("解析/下载失败") }
        // Never echo signed media URLs or proxy credentials in a route summary.
        let redacted = text.replacingOccurrences(of: #"https?://[^\s\"'<>]+"#, with: "[URL]", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)(authorization|cookie|token|password)\s*[:=]\s*[^\s]+"#, with: "$1=[redacted]", options: .regularExpression)
        return "\(route) · \(category)：\(singleLineRepairMessage(redacted))"
    }

}
