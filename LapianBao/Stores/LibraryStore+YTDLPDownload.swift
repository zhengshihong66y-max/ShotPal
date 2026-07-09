//
//  LibraryStore+YTDLPDownload.swift
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
    nonisolated static func runYTDLPOnce(
        executableURL: URL,
        sourceURL: URL,
        destinationDirectory: URL,
        extraArguments: [String] = [],
        prefetchedVideoInfo: YTDLPVideoInfo? = nil,
        skipVideoInfoProbe: Bool = false,
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil,
        processCallback: (@Sendable (Process?) -> Void)? = nil
    ) async throws -> DownloadedVideoResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            defer { processCallback?(nil) }
            process.executableURL = executableURL

            // 确保 yt-dlp 能找到 ffmpeg（App 启动时 PATH 不完整）
            let env = downloaderProcessEnvironment()
            process.environment = env

            progressCallback?(nil, nil)
            let selectedPlaylistItemIndex = instagramCarouselItemIndex(from: sourceURL)
            let downloaderSourceURL = ytdlpSourceURL(for: sourceURL)

            // 换尝试重试时复用已成功的探测结果,避免每次尝试都重跑一遍元数据探测
            let videoInfo: YTDLPVideoInfo?
            if let prefetchedVideoInfo {
                videoInfo = prefetchedVideoInfo
            } else if skipVideoInfoProbe {
                videoInfo = nil
            } else {
                videoInfo = fetchYTDLPVideoInfo(
                    executableURL: executableURL,
                    sourceURL: sourceURL,
                    environment: env,
                    extraArguments: extraArguments
                )
            }
            let authorName = normalizedSourceAuthorName(videoInfo?.bestUploader ?? "")
            let sourceTitle = screenedSourceTitle(
                rawTitle: videoInfo?.title,
                description: videoInfo?.description,
                sourceURL: sourceURL
            )
            // 免探测快速启动:没有预取元数据时不再单独探测,直接开下;
            // 部件数/字节权重由下载进程的 before_dl 打印行补齐,
            // 文件先落到唯一临时名,下载完成后按 after_move 打印的标题重命名。
            let usesDeferredNaming = videoInfo == nil
                && skipVideoInfoProbe
                && selectedPlaylistItemIndex == nil
            let expectedPartCount = videoInfo?.expectedDownloadPartCount ?? 1
            let expectedPartByteCounts = videoInfo?.expectedDownloadPartByteCounts ?? []
            let progressTracker = YTDLPProgressTracker(
                expectedPartCount: expectedPartCount,
                downloadCompletionProgress: 0.96,
                postProcessingProgress: 0.98,
                expectedPartByteCounts: expectedPartByteCounts,
                allowsEstimatedMultipartProgress: false,
                reportsPostProcessingProgress: true
            )
            let baseOutputURL: URL
            if usesDeferredNaming {
                // 临时名按源 URL 派生保持稳定,暂停/继续时 yt-dlp 才能续传同名 .part 文件
                baseOutputURL = destinationDirectory
                    .appendingPathComponent("lapianbao-dl-\(stableImportStemDigest(for: sourceURL)).mp4")
            } else {
                baseOutputURL = cleanedImportVideoURL(
                    in: destinationDirectory,
                    sourceURL: sourceURL,
                    rawTitle: videoInfo?.title,
                    description: videoInfo?.description,
                    uploader: videoInfo?.bestUploader,
                    preferredExtension: "mp4"
                )
            }
            let outputURL = selectedPlaylistItemIndex.map {
                uniqueImportVideoURL(
                    in: destinationDirectory,
                    stem: "\(baseOutputURL.deletingPathExtension().lastPathComponent) 分段 \($0)",
                    preferredExtension: "mp4"
                )
            } ?? baseOutputURL
            let outputTemplate = "\(outputURL.deletingPathExtension().lastPathComponent).%(ext)s"

            var arguments = ytdlpPlaylistSelectionArguments(for: sourceURL) + [
                "--progress",   // 非 TTY 环境也强制输出进度
                "--newline",    // 每次进度更新输出新行，便于实时解析
                "--no-colors",  // 去掉 ANSI 转义码，方便文本解析
                "--progress-template", "download:lapianbao-progress downloaded=%(progress.downloaded_bytes)s total=%(progress.total_bytes)s total_estimate=%(progress.total_bytes_estimate)s speed=%(progress.speed)s",
                "--user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            ]
            arguments += ytdlpDownloadNetworkArguments(isYouTube: isYouTubeURL(downloaderSourceURL))
            if let ffmpegDirectoryPath = localFFmpegDirectoryPath() {
                arguments += ["--ffmpeg-location", ffmpegDirectoryPath]
            }
            arguments += ytdlpFormatSelectionArguments()
            if isBilibiliURL(sourceURL) {
                arguments += ytdlpBilibiliHTTPHeaderArguments()
            }
            arguments += extraArguments
            arguments += [
                "--paths", destinationDirectory.path,
                "-o", outputTemplate,
                "--print", "after_move:filepath"
            ]
            if usesDeferredNaming {
                arguments += [
                    "--print", "before_dl:\(Self.ytdlpPartsMarkerPrefix)%(requested_formats)j",
                    "--print", "after_move:\(Self.ytdlpTitleMarkerPrefix)%(title)s",
                    "--print", "after_move:\(Self.ytdlpUploaderMarkerPrefix)%(uploader)s"
                ]
            }
            arguments.append(downloaderSourceURL.absoluteString)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let startedAt = Date()
            let outputCollector = PipeLineCollector()
            let errorCollector = PipeLineCollector()
            let namingBox = YTDLPDeferredNamingBox()
            let handleProgressLines: @Sendable ([String]) -> Void = { lines in
                for line in lines {
                    if usesDeferredNaming,
                       consumeYTDLPDeferredNamingLine(line, into: namingBox, progressTracker: progressTracker) {
                        continue
                    }
                    if let update = progressTracker.update(from: line) {
                        progressCallback?(update.progress, update.speed)
                    }
                }
            }

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                handleProgressLines(outputCollector.append(handle.availableData))
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                handleProgressLines(errorCollector.append(handle.availableData))
            }

            do {
                try process.run()
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                throw YTDLPDownloaderFailure(
                    message: ytdlpLaunchFailureMessage(error, executableURL: executableURL),
                    authorName: authorName
                )
            }
            processCallback?(process)
            process.waitUntilExit()

            // nil 掉 handler（内部会等当前 handler 执行完毕），再排空剩余数据
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            handleProgressLines(outputCollector.finish(with: outputPipe.fileHandleForReading.readDataToEndOfFile()))
            handleProgressLines(errorCollector.finish(with: errorPipe.fileHandleForReading.readDataToEndOfFile()))

            let output = String(
                data: outputCollector.data,
                encoding: .utf8
            ) ?? ""
            let errorOutput = String(data: errorCollector.data, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw YTDLPDownloaderFailure(
                    message: userFacingYTDLPFailureMessage(errorOutput, sourceURL: sourceURL),
                    authorName: authorName
                )
            }

            guard let downloadedURL = downloadedVideoFileURL(
                fromYTDLPOutput: output,
                destinationDirectory: destinationDirectory,
                expectedOutputURL: outputURL,
                startedAt: startedAt
            ) else {
                throw YTDLPDownloaderFailure(
                    message: userFacingYTDLPFailureMessage(
                        [errorOutput, output].joined(separator: "\n"),
                        sourceURL: sourceURL,
                        fallback: "yt-dlp 下载完成，但找不到输出视频文件"
                    ),
                    authorName: authorName
                )
            }

            guard usesDeferredNaming else {
                return DownloadedVideoResult(
                    url: downloadedURL,
                    authorName: authorName,
                    sourceTitle: sourceTitle
                )
            }

            // 快速启动路径:用下载进程打印的标题/作者补齐命名与来源信息
            let printedTitle = namingBox.title
            let printedUploader = namingBox.uploader
            let resolvedExtension = downloadedURL.pathExtension.isEmpty ? "mp4" : downloadedURL.pathExtension
            let targetURL = cleanedImportVideoURL(
                in: destinationDirectory,
                sourceURL: sourceURL,
                rawTitle: printedTitle,
                description: nil,
                uploader: printedUploader,
                preferredExtension: resolvedExtension
            )
            var finalURL = downloadedURL
            if targetURL != downloadedURL {
                do {
                    try FileManager.default.moveItem(at: downloadedURL, to: targetURL)
                    finalURL = targetURL
                } catch {
                    // 重命名失败不影响导入,保留临时名文件
                }
            }
            return DownloadedVideoResult(
                url: finalURL,
                authorName: normalizedSourceAuthorName(printedUploader ?? ""),
                sourceTitle: screenedSourceTitle(
                    rawTitle: printedTitle,
                    description: nil,
                    sourceURL: sourceURL
                )
            )
        }.value
    }

    /// FNV-1a 稳定摘要:同一源 URL 跨启动生成相同的临时文件名(Swift hashValue 不稳定)
    nonisolated static func stableImportStemDigest(for sourceURL: URL) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in Array(sourceURL.absoluteString.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash))
    }

    nonisolated static let ytdlpPartsMarkerPrefix = "lapianbao-parts "
    nonisolated static let ytdlpTitleMarkerPrefix = "lapianbao-title "
    nonisolated static let ytdlpUploaderMarkerPrefix = "lapianbao-uploader "

    nonisolated final class YTDLPDeferredNamingBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storedTitle: String?
        private var storedUploader: String?

        var title: String? {
            lock.lock()
            defer { lock.unlock() }
            return storedTitle
        }

        var uploader: String? {
            lock.lock()
            defer { lock.unlock() }
            return storedUploader
        }

        func setTitle(_ value: String?) {
            lock.lock()
            defer { lock.unlock() }
            storedTitle = value
        }

        func setUploader(_ value: String?) {
            lock.lock()
            defer { lock.unlock() }
            storedUploader = value
        }
    }

    /// 处理快速启动路径的标记行;命中标记时返回 true,调用方跳过后续进度解析。
    nonisolated static func consumeYTDLPDeferredNamingLine(
        _ line: String,
        into box: YTDLPDeferredNamingBox,
        progressTracker: YTDLPProgressTracker
    ) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(ytdlpPartsMarkerPrefix) {
            let payload = String(trimmed.dropFirst(ytdlpPartsMarkerPrefix.count))
            if let partInfo = parseYTDLPRequestedFormatsPartInfo(payload) {
                progressTracker.noteExpectedParts(count: partInfo.count, byteCounts: partInfo.byteCounts)
            }
            return true
        }
        if trimmed.hasPrefix(ytdlpTitleMarkerPrefix) {
            let payload = String(trimmed.dropFirst(ytdlpTitleMarkerPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            box.setTitle(payload.isEmpty || payload == "NA" ? nil : payload)
            return true
        }
        if trimmed.hasPrefix(ytdlpUploaderMarkerPrefix) {
            let payload = String(trimmed.dropFirst(ytdlpUploaderMarkerPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            box.setUploader(payload.isEmpty || payload == "NA" ? nil : payload)
            return true
        }
        return false
    }

    /// 解析 before_dl 打印的 %(requested_formats)j:返回部件数,以及在
    /// 每个部件都有已知大小时的字节权重(缺任一大小则不提供权重)。
    nonisolated static func parseYTDLPRequestedFormatsPartInfo(
        _ json: String
    ) -> (count: Int, byteCounts: [Double])? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "NA", trimmed != "null", trimmed != "None" else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !array.isEmpty
        else { return nil }

        let byteCounts = array.map { item -> Double in
            if let size = item["filesize"] as? Double, size > 0 {
                return size
            }
            if let size = item["filesize_approx"] as? Double, size > 0 {
                return size
            }
            return 0
        }
        let usableByteCounts = byteCounts.allSatisfy { $0 > 0 } ? byteCounts : []
        return (array.count, usableByteCounts)
    }

    nonisolated struct InstagramCarouselBundlePlan {
        let baseURL: URL
        let itemLinks: [String]
        let info: YTDLPVideoInfo
        let extraArguments: [String]
    }

    nonisolated static func instagramCarouselBundlePlan(
        executableURL: URL,
        sourceURL: URL
    ) -> InstagramCarouselBundlePlan? {
        guard let content = instagramContentParts(from: sourceURL),
              content.type == "p",
              let baseURL = instagramBaseContentURL(from: sourceURL)
        else { return nil }

        for attempt in ytdlpArgumentAttempts(for: baseURL) {
            guard let info = fetchYTDLPInstagramPlaylistInfo(
                executableURL: executableURL,
                sourceURL: baseURL,
                extraArguments: attempt.arguments
            ) else { continue }

            let itemLinks = instagramPostVideoItemLinks(from: info, baseURL: baseURL)
            guard itemLinks.count > 1 else { continue }
            return InstagramCarouselBundlePlan(
                baseURL: baseURL,
                itemLinks: itemLinks,
                info: info,
                extraArguments: attempt.arguments
            )
        }

        return nil
    }

    nonisolated static func downloadInstagramCarouselBundleIfNeeded(
        executableURL: URL,
        sourceURL: URL,
        destinationDirectory: URL,
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil,
        processCallback: (@Sendable (Process?) -> Void)? = nil
    ) async throws -> DownloadedVideoResult? {
        guard let plan = instagramCarouselBundlePlan(
            executableURL: executableURL,
            sourceURL: sourceURL
        ) else { return nil }

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("lapianbao-ig-carousel-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let authorName = normalizedSourceAuthorName(plan.info.bestUploader ?? "")
        let sourceTitle = screenedSourceTitle(
            rawTitle: plan.info.title,
            description: plan.info.description,
            sourceURL: plan.baseURL
        )
        let itemCount = plan.itemLinks.count
        let downloadCompletionProgress = 0.88
        var downloadedPartURLs: [URL] = []

        for (offset, itemLink) in plan.itemLinks.enumerated() {
            try Task.checkCancellation()
            guard let itemURL = URL(string: itemLink) else {
                throw RemoteImportError.invalidAPIResponse
            }
            let itemProgressCallback: @Sendable (Double?, String?) -> Void = { progress, speed in
                guard let progress else {
                    progressCallback?(nil, speed)
                    return
                }
                let mappedProgress = (Double(offset) + Self.normalizedProgress(progress)) / Double(itemCount) * downloadCompletionProgress
                progressCallback?(mappedProgress, speed)
            }
            let result = try await runYTDLPOnce(
                executableURL: executableURL,
                sourceURL: itemURL,
                destinationDirectory: temporaryDirectory,
                extraArguments: plan.extraArguments,
                progressCallback: itemProgressCallback,
                processCallback: processCallback
            )
            downloadedPartURLs.append(result.url)
        }

        try Task.checkCancellation()
        let outputURL = cleanedImportVideoURL(
            in: destinationDirectory,
            sourceURL: plan.baseURL,
            rawTitle: plan.info.title,
            description: plan.info.description,
            uploader: plan.info.bestUploader,
            preferredExtension: "mp4"
        )
        progressCallback?(0.92, nil)
        let bundledURL = try await concatenateVideosWithFFmpeg(
            downloadedPartURLs,
            outputURL: outputURL
        )
        progressCallback?(0.98, nil)

        return DownloadedVideoResult(
            url: bundledURL,
            authorName: authorName,
            sourceTitle: sourceTitle
        )
    }

    nonisolated static func downloaderProcessEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        return env
    }

    nonisolated static func fetchYTDLPVideoInfo(
        executableURL: URL,
        sourceURL: URL,
        environment: [String: String],
        extraArguments: [String] = []
    ) -> YTDLPVideoInfo? {
        let process = Process()
        process.executableURL = executableURL
        process.environment = environment
        let downloaderSourceURL = ytdlpSourceURL(for: sourceURL)
        var arguments = ytdlpPlaylistSelectionArguments(for: sourceURL) + [
            "--skip-download",
            "--dump-single-json",
            "--no-warnings",
        ]
        arguments += ytdlpProbeNetworkArguments(isYouTube: isYouTubeURL(downloaderSourceURL))
        arguments += ytdlpFormatSelectionArguments()
        if isBilibiliURL(sourceURL) {
            arguments += ytdlpBilibiliHTTPHeaderArguments()
        }
        arguments += extraArguments
        arguments += [
            downloaderSourceURL.absoluteString
        ]
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputCollector = PipeDataCollector()
        let errorCollector = PipeDataCollector()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputCollector.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorCollector.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 35) == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
        guard process.terminationStatus == 0 else { return nil }
        return try? JSONDecoder().decode(YTDLPVideoInfo.self, from: outputCollector.data)
    }

    nonisolated struct YTDLPArgumentAttempt: Sendable {
        var label: String = ""
        var arguments: [String]
    }

    nonisolated static func ytdlpArgumentAttempts(for sourceURL: URL) -> [YTDLPArgumentAttempt] {
        if isYouTubeURL(sourceURL) {
            return ytdlpYouTubeArgumentAttempts()
        }
        if isInstagramURL(sourceURL) {
            var attempts = [YTDLPArgumentAttempt(label: "本地解析", arguments: [])]
            for proxyURL in currentYTDLPProxyURLs() {
                let proxyArguments = ["--proxy", proxyURL]
                let label = ytdlpProxyAttemptLabel(for: proxyURL)
                attempts.append(YTDLPArgumentAttempt(label: label, arguments: proxyArguments))
            }
            return uniqueYTDLPArgumentAttempts(attempts)
        }
        if isBilibiliURL(sourceURL) {
            return ytdlpBilibiliArgumentAttempts()
        }
        return [YTDLPArgumentAttempt(arguments: [])]
    }

    nonisolated static func ytdlpBilibiliHTTPHeaderArguments() -> [String] {
        [
            "--referer", "https://www.bilibili.com/",
            "--add-header", "Origin:https://www.bilibili.com"
        ]
    }

    nonisolated static func ytdlpBilibiliArgumentAttempts() -> [YTDLPArgumentAttempt] {
        let dashArguments = ["--extractor-args", "bilibili:prefer_multi_flv=False"]
        let multiFLVArguments = ["--extractor-args", "bilibili:prefer_multi_flv=True"]
        var attempts = [
            YTDLPArgumentAttempt(label: "Bilibili DASH", arguments: dashArguments),
            YTDLPArgumentAttempt(label: "Bilibili 单文件 MP4", arguments: dashArguments + ["-f", "b[ext=mp4]/b"]),
            YTDLPArgumentAttempt(label: "Bilibili 兼容格式", arguments: dashArguments + ["-f", "b"]),
            YTDLPArgumentAttempt(label: "Bilibili multi-FLV", arguments: multiFLVArguments + ["-f", "b"])
        ]

        for proxyURL in currentYTDLPProxyURLs() {
            let proxyArguments = ["--proxy", proxyURL]
            let label = ytdlpProxyAttemptLabel(for: proxyURL)
            attempts.append(YTDLPArgumentAttempt(label: "\(label) Bilibili DASH", arguments: proxyArguments + dashArguments))
            attempts.append(YTDLPArgumentAttempt(label: "\(label) Bilibili 兼容格式", arguments: proxyArguments + dashArguments + ["-f", "b"]))
        }
        return uniqueYTDLPArgumentAttempts(attempts)
    }

    nonisolated static func ytdlpYouTubeArgumentAttempts() -> [YTDLPArgumentAttempt] {
        let clientArguments = ytdlpYouTubeClientArguments()
        var attempts = [YTDLPArgumentAttempt(label: "本地解析", arguments: [])]

        for proxyURL in currentYTDLPProxyURLs() {
            let proxyArguments = ["--proxy", proxyURL]
            let label = ytdlpProxyAttemptLabel(for: proxyURL)
            attempts.append(YTDLPArgumentAttempt(label: label, arguments: proxyArguments))
            attempts.append(YTDLPArgumentAttempt(label: "\(label)备用客户端", arguments: proxyArguments + clientArguments))
        }

        attempts.append(YTDLPArgumentAttempt(label: "备用客户端", arguments: clientArguments))
        attempts.append(YTDLPArgumentAttempt(label: "远程组件", arguments: ["--remote-components", "ejs:github"] + clientArguments))
        return uniqueYTDLPArgumentAttempts(attempts)
    }

    nonisolated static func ytdlpYouTubeCookieFileArgumentAttempts(cookieFileURL: URL?) -> [YTDLPArgumentAttempt] {
        guard let cookieFileURL,
              FileManager.default.fileExists(atPath: cookieFileURL.path)
        else { return [] }

        let clientArguments = ytdlpYouTubeClientArguments()
        // 每次调用使用一次性副本:yt-dlp 退出时会回写轮换后的 cookie,
        // 并发的视频/歌曲/探测进程共用同一份文件会互相覆盖并导致会话失效。
        let workingCookieURL = throwawayCookieCopyURL(of: cookieFileURL) ?? cookieFileURL
        let cookieArguments = ["--cookies", workingCookieURL.path]
        var attempts: [YTDLPArgumentAttempt] = []

        // 第一发用单一 web_safari 客户端并跳过 HLS/DASH 清单:请求数最少,
        // 慢代理下解析从约 15 秒缩到 6 秒;不适用的视频(直播等)由后续
        // 多客户端、不带 skip 的尝试兜底。
        attempts.append(YTDLPArgumentAttempt(
            label: "cookies.txt",
            arguments: cookieArguments + ["--extractor-args", "youtube:player_client=web_safari;skip=hls,dash"]
        ))
        attempts.append(YTDLPArgumentAttempt(label: "cookies.txt备用客户端", arguments: cookieArguments + clientArguments))

        for proxyURL in currentYTDLPProxyURLs() {
            let proxyArguments = ["--proxy", proxyURL]
            let proxyLabel = ytdlpProxyAttemptLabel(for: proxyURL)
            attempts.append(YTDLPArgumentAttempt(label: "\(proxyLabel) cookies.txt", arguments: proxyArguments + cookieArguments))
            attempts.append(YTDLPArgumentAttempt(label: "\(proxyLabel) cookies.txt备用客户端", arguments: proxyArguments + cookieArguments + clientArguments))
        }

        return uniqueYTDLPArgumentAttempts(attempts)
    }

    nonisolated static func configuredYouTubeCookieFileURL() -> URL? {
        guard let url = AppSettings.resolvedYouTubeCookieFileURL(),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    nonisolated static func throwawayCookieCopyURL(of cookieFileURL: URL) -> URL? {
        let copyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lapianbao-cookies-\(UUID().uuidString).txt")
        do {
            try FileManager.default.copyItem(at: cookieFileURL, to: copyURL)
            return copyURL
        } catch {
            return nil
        }
    }

    nonisolated static func ytdlpYouTubeSelfCheckArgumentAttempts() -> [YTDLPArgumentAttempt] {
        let proxyURLs = currentYTDLPProxyURLs()
        let clientArguments = ytdlpYouTubeClientArguments()
        var attempts: [YTDLPArgumentAttempt] = []

        if let proxyURL = proxyURLs.first {
            let proxyArguments = ["--proxy", proxyURL]
            let proxyLabel = ytdlpProxyAttemptLabel(for: proxyURL)
            attempts.append(YTDLPArgumentAttempt(label: proxyLabel, arguments: proxyArguments))
            attempts.append(YTDLPArgumentAttempt(label: "\(proxyLabel)备用客户端", arguments: proxyArguments + clientArguments))
        } else {
            attempts.append(YTDLPArgumentAttempt(label: "备用客户端", arguments: clientArguments))
        }

        attempts.append(YTDLPArgumentAttempt(label: "本地解析", arguments: []))
        return Array(uniqueYTDLPArgumentAttempts(attempts).prefix(4))
    }

    nonisolated static func uniqueYTDLPArgumentAttempts(_ attempts: [YTDLPArgumentAttempt]) -> [YTDLPArgumentAttempt] {
        var seen = Set<String>()
        return attempts.compactMap { attempt in
            let key = attempt.arguments.joined(separator: "\u{1f}")
            guard seen.insert(key).inserted else { return nil }
            return attempt
        }
    }

    nonisolated static func ytdlpYouTubeClientArguments() -> [String] {
        ["--extractor-args", "youtube:player_client=web_safari,mweb,android_vr"]
    }

    nonisolated static func currentYTDLPProxyURLs() -> [String] {
        var candidates: [String] = []
        candidates += systemProxyURLsForYTDLP()
        candidates += environmentProxyURLsForYTDLP()
        if isLocalProxyURLReachable("http://127.0.0.1:1082") {
            candidates.append("http://127.0.0.1:1082")
        }

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let normalized = normalizedProxyURL(candidate)
            guard !normalized.isEmpty,
                  isLocalProxyURLReachable(normalized),
                  seen.insert(normalized).inserted
            else { return nil }
            return normalized
        }
    }

    nonisolated static func systemProxyURLsForYTDLP() -> [String] {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return []
        }

        var proxies: [String] = []
        appendProxyURL(
            from: settings,
            enableKey: "HTTPEnable",
            hostKey: "HTTPProxy",
            portKey: "HTTPPort",
            scheme: "http",
            to: &proxies
        )
        appendProxyURL(
            from: settings,
            enableKey: "HTTPSEnable",
            hostKey: "HTTPSProxy",
            portKey: "HTTPSPort",
            scheme: "http",
            to: &proxies
        )
        appendProxyURL(
            from: settings,
            enableKey: "SOCKSEnable",
            hostKey: "SOCKSProxy",
            portKey: "SOCKSPort",
            scheme: "socks5",
            to: &proxies
        )
        return proxies
    }

    nonisolated static func environmentProxyURLsForYTDLP() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        return [
            "HTTPS_PROXY",
            "https_proxy",
            "HTTP_PROXY",
            "http_proxy",
            "ALL_PROXY",
            "all_proxy"
        ].compactMap { environment[$0] }
    }

    nonisolated static func appendProxyURL(
        from settings: [String: Any],
        enableKey: String,
        hostKey: String,
        portKey: String,
        scheme: String,
        to proxies: inout [String]
    ) {
        guard boolProxyValue(settings[enableKey]),
              let host = settings[hostKey] as? String,
              let port = intProxyValue(settings[portKey]),
              let proxyURL = proxyURLString(scheme: scheme, host: host, port: port)
        else { return }
        proxies.append(proxyURL)
    }

    nonisolated static func boolProxyValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return value == "1" || value.lowercased() == "true" }
        return false
    }

    nonisolated static func intProxyValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    nonisolated static func proxyURLString(scheme: String, host: String, port: Int) -> String? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, port > 0 else { return nil }
        let formattedHost = trimmedHost.contains(":") && !trimmedHost.hasPrefix("[")
            ? "[\(trimmedHost)]"
            : trimmedHost
        return "\(scheme)://\(formattedHost):\(port)"
    }

    nonisolated static func normalizedProxyURL(_ candidate: String) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://") { return trimmed }
        return "http://\(trimmed)"
    }

    nonisolated static func ytdlpProxyAttemptLabel(for proxyURL: String) -> String {
        guard let components = URLComponents(string: proxyURL),
              let host = components.host,
              let port = components.port
        else { return "系统代理" }
        if isLoopbackProxyHost(host) {
            return "本机代理 \(port)"
        }
        return "系统代理 \(host):\(port)"
    }

    nonisolated static func isLocalProxyURLReachable(_ proxyURL: String) -> Bool {
        guard let components = URLComponents(string: proxyURL),
              let host = components.host,
              let port = components.port
        else { return false }
        guard isLoopbackProxyHost(host) else { return true }
        return isLoopbackTCPPortOpen(host: host, port: port)
    }

    nonisolated static func isLoopbackProxyHost(_ host: String) -> Bool {
        let lowered = host.lowercased()
        return lowered == "localhost"
            || lowered == "127.0.0.1"
            || lowered == "::1"
            || lowered.hasPrefix("127.")
    }

    nonisolated static func isLoopbackTCPPortOpen(host: String, port: Int) -> Bool {
        let address = host == "localhost" ? "127.0.0.1" : host
        guard !address.contains(":") else { return true }

        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return false }
        defer { close(socketDescriptor) }

        var socketAddress = sockaddr_in()
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = in_port_t(port).bigEndian
        guard inet_pton(AF_INET, address, &socketAddress.sin_addr) == 1 else { return false }

        let result = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketPointer in
                connect(socketDescriptor, socketPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    nonisolated static func ytdlpProbeNetworkArguments(isYouTube: Bool) -> [String] {
        var arguments = [
            "--socket-timeout", "15",
            "--retries", "1",
            "--extractor-retries", "1"
        ]
        if isYouTube {
            arguments += ["--sleep-requests", "0.35"]
        }
        return arguments
    }

    nonisolated static func ytdlpDownloadNetworkArguments(isYouTube: Bool) -> [String] {
        var arguments = [
            "--socket-timeout", "25",
            "--retries", "5",
            "--fragment-retries", "8",
            "--extractor-retries", "2",
            "--retry-sleep", "http:linear=1::1",
            "--retry-sleep", "fragment:exp=1:8",
            // DASH/HLS 分片并发下载;单连接走代理时串行分片是吞吐瓶颈
            "--concurrent-fragments", "8"
        ]
        if isYouTube {
            // cookie 方案下已是认证会话,缩短请求间隔以加快下载前的解析阶段
            arguments += ["--sleep-requests", "0.3"]
        }
        return arguments
    }

    nonisolated static func isHardYouTubeYTDLPFailure(_ error: Error) -> Bool {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lowercased = message.lowercased()
        return lowercased.contains("video unavailable")
            || lowercased.contains("private video")
            || lowercased.contains("this video is unavailable")
            || lowercased.contains("not available in your country")
            || isYouTubeBotVerificationFailure(message)
    }

    nonisolated static func userFacingYTDLPFailureMessage(
        _ message: String,
        sourceURL: URL,
        fallback: String = "yt-dlp 下载失败"
    ) -> String {
        let concise = conciseYTDLPError(message, fallback: fallback)
        if isBilibiliURL(sourceURL), isBilibiliPreconditionFailure(concise) {
            return "Bilibili 返回 412 风控：已使用公开 Origin/Referer 请求头，仍失败时请确认链接可公开访问、代理出口稳定，或稍后重试。"
        }

        guard isYouTubeURL(sourceURL),
              isYouTubeBotVerificationFailure(concise)
        else { return concise }

        if configuredYouTubeCookieFileURL() == nil {
            return "YouTube 要求登录验证：请在设置里选择从浏览器导出的 cookies.txt，或换公开链接、配置可用代理后重试。"
        }
        return "YouTube 要求登录验证：已配置 cookies.txt，拉片宝会用它重试；仍失败时，请重新导出 cookies.txt 或换公开链接。"
    }

    nonisolated static func isYouTubeBotVerificationFailure(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return (lowercased.contains("sign in to confirm")
            && lowercased.contains("not a bot"))
            || lowercased.contains("youtube 要求登录验证")
            || (lowercased.contains("youtube") && lowercased.contains("登录验证"))
    }

    nonisolated static func isBilibiliPreconditionFailure(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("http error 412")
            || lowercased.contains("precondition failed")
    }

    nonisolated static func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtube.com" || host == "www.youtube.com"
            || host == "m.youtube.com" || host == "youtu.be"
            || host == "music.youtube.com"
    }

    nonisolated static func isInstagramURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
            || host == "instagr.am" || host.hasSuffix(".instagr.am")
    }

    nonisolated static func isBilibiliURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("bilibili.com") || host == "b23.tv"
    }

    nonisolated static func remoteImportCandidateMetadata(for sourceURL: URL) async -> RemoteImportCandidateMetadata {
        if platformName(for: sourceURL) == "小红书" {
            if let nativeMetadata = await xiaohongshuRemoteImportCandidateMetadataIfNeeded(for: sourceURL),
               nativeMetadata.hasAnyValue {
                return nativeMetadata
            }
            return await ytdlpRemoteImportCandidateMetadata(for: sourceURL)
        }

        // YouTube 用轻量接口(oEmbed + 固定缩略图地址)拿标题/作者/封面:
        // 单个请求、不受风控影响,也不再和正式下载并行抢代理带宽。
        if isYouTubeURL(sourceURL) {
            if let lightweight = await youtubeLightweightCandidateMetadata(for: sourceURL),
               lightweight.hasAnyValue {
                return lightweight
            }
            return await ytdlpRemoteImportCandidateMetadata(for: sourceURL)
        }

        async let ytdlpMetadata = ytdlpRemoteImportCandidateMetadata(for: sourceURL)
        async let nativeMetadata = xiaohongshuRemoteImportCandidateMetadataIfNeeded(for: sourceURL)

        let ytdlp = await ytdlpMetadata
        let native = await nativeMetadata
        return RemoteImportCandidateMetadata(
            title: ytdlp.title ?? native?.title,
            authorName: ytdlp.authorName ?? native?.authorName,
            thumbnailData: ytdlp.thumbnailData ?? native?.thumbnailData
        )
    }

    nonisolated static func youtubeLightweightCandidateMetadata(for sourceURL: URL) async -> RemoteImportCandidateMetadata? {
        guard let videoID = youTubeVideoID(from: sourceURL) else { return nil }

        var title: String?
        var authorName: String?
        if var components = URLComponents(string: "https://www.youtube.com/oembed") {
            components.queryItems = [
                URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoID)"),
                URLQueryItem(name: "format", value: "json")
            ]
            if let oembedURL = components.url {
                var request = URLRequest(url: oembedURL)
                request.timeoutInterval = 10
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   let httpResponse = response as? HTTPURLResponse,
                   (200..<300).contains(httpResponse.statusCode),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    title = screenedSourceTitle(
                        rawTitle: object["title"] as? String,
                        description: nil,
                        sourceURL: sourceURL
                    )
                    authorName = normalizedSourceAuthorName(object["author_name"] as? String ?? "")
                }
            }
        }

        var thumbnailData: Data?
        if let thumbnailURL = URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg") {
            thumbnailData = await fetchRemoteImageData(from: thumbnailURL)
        }

        let metadata = RemoteImportCandidateMetadata(
            title: title,
            authorName: authorName,
            thumbnailData: thumbnailData
        )
        return metadata.hasAnyValue ? metadata : nil
    }

    nonisolated static func ytdlpRemoteImportCandidateMetadata(for sourceURL: URL) async -> RemoteImportCandidateMetadata {
        if isBilibiliURL(sourceURL),
           let metadata = await ytdlpPrintedRemoteImportCandidateMetadata(for: sourceURL) {
            return metadata
        }

        guard let ytdlp = localYTDLPURL() else {
            return RemoteImportCandidateMetadata()
        }

        let environment = downloaderProcessEnvironment()
        // 与正式下载一致:配置了 cookies.txt 时探测也 cookie 优先,
        // 否则在被风控的出口上标题和封面要等匿名尝试全部失败才出现。
        let cookieFileURL = isYouTubeURL(sourceURL) ? configuredYouTubeCookieFileURL() : nil
        let probeAttempts = ytdlpYouTubeCookieFileArgumentAttempts(cookieFileURL: cookieFileURL)
            + ytdlpArgumentAttempts(for: sourceURL)
        let info = probeAttempts
            .lazy
            .compactMap { attempt in
                fetchYTDLPVideoInfo(
                    executableURL: ytdlp,
                    sourceURL: sourceURL,
                    environment: environment,
                    extraArguments: attempt.arguments
                )
            }
            .first

        let title = screenedSourceTitle(
            rawTitle: info?.title,
            description: info?.description,
            sourceURL: sourceURL
        )
        let authorName = normalizedSourceAuthorName(info?.bestUploader ?? "")

        let thumbnailData: Data?
        if let thumbnailURL = info?.bestThumbnailURL {
            thumbnailData = await fetchRemoteImageData(from: thumbnailURL)
        } else {
            thumbnailData = await remoteThumbnailData(for: sourceURL)
        }

        return RemoteImportCandidateMetadata(
            title: title,
            authorName: authorName,
            thumbnailData: thumbnailData
        )
    }

    nonisolated static func ytdlpPrintedRemoteImportCandidateMetadata(for sourceURL: URL) async -> RemoteImportCandidateMetadata? {
        guard let ytdlp = localYTDLPURL() else { return nil }

        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = ytdlp
            process.environment = downloaderProcessEnvironment()
            let downloaderSourceURL = ytdlpSourceURL(for: sourceURL)
            var arguments = ytdlpPlaylistSelectionArguments(for: sourceURL) + [
                "--skip-download",
                "--no-warnings",
                "--print", "title",
                "--print", "uploader",
                "--print", "thumbnail",
            ]
            arguments += ytdlpProbeNetworkArguments(isYouTube: isYouTubeURL(downloaderSourceURL))
            if isBilibiliURL(sourceURL) {
                arguments += ytdlpBilibiliHTTPHeaderArguments()
            }
            arguments += ytdlpArgumentAttempts(for: sourceURL).first?.arguments ?? []
            arguments += [
                downloaderSourceURL.absoluteString
            ]
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let outputCollector = PipeDataCollector()
            let errorCollector = PipeDataCollector()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                outputCollector.append(handle.availableData)
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                errorCollector.append(handle.availableData)
            }

            do {
                try process.run()
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                return nil
            }

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + 20) == .timedOut {
                if process.isRunning {
                    process.terminate()
                }
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                return nil
            }

            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
            errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
            guard process.terminationStatus == 0 else { return nil }

            let lines = (String(data: outputCollector.data, encoding: .utf8) ?? "")
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { $0 == "NA" ? "" : $0 }
            let title = screenedSourceTitle(
                rawTitle: lines.indices.contains(0) ? lines[0] : nil,
                description: nil,
                sourceURL: sourceURL
            )
            let authorName = normalizedSourceAuthorName(lines.indices.contains(1) ? lines[1] : "")

            let thumbnailData: Data?
            if lines.indices.contains(2),
               let thumbnailURL = URL(string: lines[2]) {
                thumbnailData = await fetchRemoteImageData(from: thumbnailURL)
            } else {
                thumbnailData = nil
            }

            return RemoteImportCandidateMetadata(
                title: title,
                authorName: authorName,
                thumbnailData: thumbnailData
            )
        }.value
    }

    nonisolated static func xiaohongshuRemoteImportCandidateMetadataIfNeeded(
        for sourceURL: URL
    ) async -> RemoteImportCandidateMetadata? {
        guard platformName(for: sourceURL) == "小红书" else { return nil }
        return await Self.xiaohongshuRemoteImportCandidateMetadata(for: sourceURL)
    }

    nonisolated static func remoteThumbnailData(for sourceURL: URL) async -> Data? {
        guard let ytdlp = localYTDLPURL() else { return nil }

        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = ytdlp
            process.environment = downloaderProcessEnvironment()
            let downloaderSourceURL = ytdlpSourceURL(for: sourceURL)
            var arguments = ytdlpPlaylistSelectionArguments(for: sourceURL) + [
                "--skip-download",
                "--print", "thumbnail",
                "--no-warnings",
            ]
            arguments += ytdlpProbeNetworkArguments(isYouTube: isYouTubeURL(downloaderSourceURL))
            if isBilibiliURL(sourceURL) {
                arguments += ytdlpBilibiliHTTPHeaderArguments()
            }
            arguments += ytdlpArgumentAttempts(for: sourceURL).first?.arguments ?? []
            arguments += [
                downloaderSourceURL.absoluteString
            ]
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let outputCollector = PipeDataCollector()
            let errorCollector = PipeDataCollector()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                outputCollector.append(handle.availableData)
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                errorCollector.append(handle.availableData)
            }

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                return nil
            }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
            errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

            guard process.terminationStatus == 0 else { return nil }

            let output = String(data: outputCollector.data, encoding: .utf8) ?? ""
            guard
                let thumbnail = output
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") }),
                let thumbnailURL = URL(string: thumbnail)
            else { return nil }

            return await fetchRemoteImageData(from: thumbnailURL)
        }.value
    }

    nonisolated static func downloadedVideoFileURL(
        fromYTDLPOutput output: String,
        destinationDirectory: URL,
        expectedOutputURL: URL?,
        startedAt: Date
    ) -> URL? {
        let fm = FileManager.default
        let videoExtensions = Set(supportedVideoExtensions.map { $0.lowercased() })

        func isUsableVideoFile(_ url: URL) -> Bool {
            guard videoExtensions.contains(url.pathExtension.lowercased()),
                  fm.fileExists(atPath: url.path)
            else { return false }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }

        for line in output.components(separatedBy: .newlines).reversed() {
            guard let candidate = ytdlpPrintedFileURL(
                from: line,
                destinationDirectory: destinationDirectory
            ) else { continue }
            if isUsableVideoFile(candidate) {
                return candidate
            }
        }

        if let expectedOutputURL, isUsableVideoFile(expectedOutputURL) {
            return expectedOutputURL
        }

        let urls = (try? fm.contentsOfDirectory(
            at: destinationDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter(isUsableVideoFile)
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true,
                      let modifiedAt = values?.contentModificationDate,
                      modifiedAt >= startedAt.addingTimeInterval(-2)
                else { return nil }
                return (url, modifiedAt)
            }
            .sorted { $0.1 > $1.1 }
            .first?
            .0
    }

    nonisolated static func ytdlpPrintedFileURL(from line: String, destinationDirectory: URL) -> URL? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("[")
        else { return nil }

        if let fileURL = URL(string: trimmed),
           fileURL.isFileURL {
            return fileURL.standardizedFileURL
        }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }
        return destinationDirectory
            .appendingPathComponent(trimmed)
            .standardizedFileURL
    }

    nonisolated static func fetchRemoteImageData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard data.count <= 12_000_000 else { return nil }
            if let httpResponse = response as? HTTPURLResponse {
                guard (200..<300).contains(httpResponse.statusCode) else { return nil }
            }
            return data
        } catch {
            return nil
        }
    }

    /// 解析 yt-dlp 进度行，如 "[download]  45.6% of 1.23MiB at 2.34MiB/s ETA 00:12"
    nonisolated static func parseYTDLPProgressLine(_ line: String) -> Double? {
        parseYTDLPProgressUpdate(line)?.progress
    }

    nonisolated static func parseYTDLPProgressUpdate(_ line: String) -> DownloadProgressUpdate? {
        if let structuredUpdate = parseYTDLPStructuredProgressUpdate(line) {
            return structuredUpdate
        }

        guard line.contains("[download]"), line.contains("%") else { return nil }
        // 忽略 "Destination:" 等非进度行
        guard !line.contains("Destination:"),
              !line.contains("already been downloaded"),
              !line.contains("Merging") else { return nil }
        let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for token in tokens where token.hasSuffix("%") {
            if let value = Double(token.dropLast()), value >= 0 {
                let progress = min(1.0, value / 100.0)
                let totalBytes = parseYTDLPTotalBytes(from: line)
                return DownloadProgressUpdate(
                    progress: progress,
                    speed: parseYTDLPSpeed(from: line),
                    downloadedBytes: totalBytes.map { $0 * progress },
                    totalBytes: totalBytes
                )
            }
        }
        return nil
    }

    nonisolated static func parseYTDLPStructuredProgressUpdate(_ line: String) -> DownloadProgressUpdate? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "lapianbao-progress "
        guard trimmed.hasPrefix(prefix) else { return nil }

        let fields = ytdlpStructuredProgressFields(from: String(trimmed.dropFirst(prefix.count)))
        let downloadedBytes = ytdlpStructuredProgressNumber(fields["downloaded"])
        let totalBytes = ytdlpStructuredProgressNumber(fields["total"])
            ?? ytdlpStructuredProgressNumber(fields["total_estimate"])
        let speed = ytdlpStructuredProgressSpeed(fields["speed"])

        let progress: Double?
        if let downloadedBytes,
           let totalBytes,
           totalBytes > 0 {
            progress = LibraryStore.normalizedProgress(downloadedBytes / totalBytes)
        } else {
            progress = nil
        }

        return DownloadProgressUpdate(
            progress: progress,
            speed: speed,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes
        )
    }

    nonisolated static func ytdlpStructuredProgressFields(from text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for token in text.split(separator: " ") {
            guard let separatorIndex = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<separatorIndex])
            let value = String(token[token.index(after: separatorIndex)...])
            fields[key] = value
        }
        return fields
    }

    nonisolated static func ytdlpStructuredProgressNumber(_ value: String?) -> Double? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized != "NA",
              normalized != "None",
              normalized != "null",
              let number = Double(normalized),
              number.isFinite,
              number >= 0
        else { return nil }
        return number
    }

    nonisolated static func isYTDLPPostProcessingLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains("[merger]")
            || lowercased.contains("[extractaudio]")
            || lowercased.contains("[fixup")
            || lowercased.contains("[movefiles]")
            || lowercased.contains("[videoconvertor]")
            || lowercased.contains("[videoremuxer]")
            || lowercased.contains("merging formats")
    }

    nonisolated static func parseYTDLPSpeed(from line: String) -> String? {
        let pattern = #"\bat\s+([^\s]+/s)\b"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let range = Range(match.range(at: 1), in: line)
        else { return nil }
        let speed = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return speed.isEmpty || speed == "Unknown/s" ? nil : speed
    }

    nonisolated static func ytdlpStructuredProgressSpeed(_ value: String?) -> String? {
        guard let bytesPerSecond = ytdlpStructuredProgressNumber(value),
              bytesPerSecond > 0
        else { return nil }
        return ByteCountFormatter.string(
            fromByteCount: Int64(bytesPerSecond.rounded()),
            countStyle: .file
        ) + "/s"
    }

    nonisolated static func parseYTDLPTotalBytes(from line: String) -> Double? {
        let pattern = #"\bof\s+~?\s*([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?i?B)\b"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let valueRange = Range(match.range(at: 1), in: line),
            let unitRange = Range(match.range(at: 2), in: line),
            let value = Double(String(line[valueRange]))
        else { return nil }

        let unit = String(line[unitRange]).lowercased()
        let multiplier: Double
        switch unit {
        case "b":
            multiplier = 1
        case "kb":
            multiplier = 1_000
        case "mb":
            multiplier = 1_000_000
        case "gb":
            multiplier = 1_000_000_000
        case "tb":
            multiplier = 1_000_000_000_000
        case "pb":
            multiplier = 1_000_000_000_000_000
        case "kib":
            multiplier = 1_024
        case "mib":
            multiplier = 1_048_576
        case "gib":
            multiplier = 1_073_741_824
        case "tib":
            multiplier = 1_099_511_627_776
        case "pib":
            multiplier = 1_125_899_906_842_624
        default:
            return nil
        }
        return value * multiplier
    }

    nonisolated static func importViaConfiguredAPI(
        sourceURL: URL,
        endpoint: String,
        destinationDirectory: URL,
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil
    ) async throws -> URL {
        guard let endpointURL = URL(string: endpoint) else {
            throw RemoteImportError.invalidAPIEndpoint
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            InstagramImportAPIRequest(url: sourceURL.absoluteString)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw RemoteImportError.invalidAPIResponse
        }

        let resolved = try JSONDecoder().decode(InstagramImportAPIResponse.self, from: data)
        let remoteFilename = resolved.filename?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = resolved.downloadURL.lastPathComponent.isEmpty
            ? "instagram-\(UUID().uuidString).mp4"
            : resolved.downloadURL.lastPathComponent
        let sourceFilename = remoteFilename.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        let outputURL = cleanedImportVideoURL(
            in: destinationDirectory,
            sourceURL: sourceURL,
            rawTitle: fileStem(from: sourceFilename),
            description: nil,
            uploader: nil,
            preferredExtension: fileExtension(from: sourceFilename, fallback: "mp4")
        )

        var downloadRequest = URLRequest(url: resolved.downloadURL)
        downloadRequest.timeoutInterval = 180
        return try await downloadRemoteFile(
            request: downloadRequest,
            to: outputURL,
            progressCallback: progressCallback
        )
    }

}
