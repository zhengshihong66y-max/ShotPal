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
    nonisolated static func downloadVideo(
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
        let ytdlp = usableYTDLPURL()
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

        // 1. yt-dlp（YouTube / Bilibili / 抖音完美，Instagram / 小红书公开内容也能用）
        if rawURL == nil, let ytdlp,
           !Task.isCancelled {
            let isYouTubeSource = isYouTubeURL(sourceURL)
            // 配置了 cookies.txt 时优先带 cookie 请求;被风控的出口 IP 上匿名尝试必然失败,
            // 先跑完匿名再退 cookie 会让每次下载都白等一轮重试。
            let cookieFileURL = isYouTubeSource ? configuredYouTubeCookieFileURL() : nil
            let didStartCookieAccess = cookieFileURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if didStartCookieAccess {
                    cookieFileURL?.stopAccessingSecurityScopedResource()
                }
            }
            let attempts = ytdlpYouTubeCookieFileArgumentAttempts(cookieFileURL: cookieFileURL)
                + ytdlpArgumentAttempts(for: sourceURL)
            var sawYouTubeLoginVerification = false
            for attempt in attempts {
                do {
                    let result = try await runYTDLPOnce(
                        executableURL: ytdlp,
                        sourceURL: sourceURL,
                        destinationDirectory: destinationDirectory,
                        extraArguments: attempt.arguments,
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
                    if let failure = error as? YTDLPDownloaderFailure {
                        authorName = authorName ?? failure.authorName
                    }
                    if isYouTubeSource, isYouTubeBotVerificationFailure(error.localizedDescription) {
                        sawYouTubeLoginVerification = true
                    }
                    ytdlpFailure = error
                }
            }

            if rawURL == nil,
               sawYouTubeLoginVerification,
               cookieFileURL == nil,
               let ytdlpFailure {
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
            }
        }

        // 3. 用户自定义 API
        if rawURL == nil,
           instagramCarouselItemIndex(from: sourceURL) == nil,
           !endpoint.isEmpty,
           let result = try? await importViaConfiguredAPI(
               sourceURL: sourceURL,
               endpoint: endpoint,
               destinationDirectory: destinationDirectory,
               progressCallback: progressCallback
           ) {
            rawURL = result
            sourceTitle = sourceTitle ?? Self.sourceTitle(from: [], fileName: result.lastPathComponent)
        }

        // 4. cobalt.tools 兜底（对 Instagram / YouTube 有效，需要服务可用）
        if rawURL == nil,
           let result = try? await importViaCobalt(
               sourceURL: sourceURL,
               destinationDirectory: destinationDirectory,
               progressCallback: progressCallback
           ) {
            rawURL = result
            sourceTitle = sourceTitle ?? Self.sourceTitle(from: [], fileName: result.lastPathComponent)
        }

        guard let downloadedURL = rawURL else {
            if isYouTubeURL(sourceURL), let ytdlpFailure {
                throw ytdlpFailure
            }
            if isBilibiliSource {
                if let ytdlpFailure {
                    throw ytdlpFailure
                }
                if ytdlp == nil {
                    throw RemoteImportError.downloaderFailed("Bilibili 下载需要 yt-dlp，请先在设置里运行 yt-dlp 自检。")
                }
            }
            if platform == "小红书", let xiaohongshuNativeFailure {
                throw xiaohongshuNativeFailure
            }
            throw RemoteImportError.downloaderFailed("所有下载方式均失败，请确认链接是否可公开访问")
        }

        // 后处理：VP9 / AV1 在 MP4 容器中不被 macOS AVFoundation 支持，转码为 H.264
        finalizingCallback?(1)
        let finalURL = await transcodeToH264IfNeeded(downloadedURL, progressCallback: transcodingCallback) ?? downloadedURL
        finalizingCallback?(1)
        return DownloadedVideoResult(
            url: finalURL,
            authorName: authorName,
            sourceTitle: sourceTitle ?? Self.sourceTitle(from: [], fileName: finalURL.lastPathComponent)
        )
    }

}
