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

            let videoInfo = fetchYTDLPVideoInfo(
                executableURL: executableURL,
                sourceURL: sourceURL,
                environment: env,
                extraArguments: extraArguments
            )
            let authorName = normalizedImportTag(videoInfo?.bestUploader ?? "")
            let sourceTitle = screenedSourceTitle(
                rawTitle: videoInfo?.title,
                description: videoInfo?.description,
                sourceURL: sourceURL
            )
            let expectedPartCount = videoInfo?.expectedDownloadPartCount ?? 2
            let progressTracker = YTDLPProgressTracker(
                expectedPartCount: expectedPartCount,
                allowsEstimatedMultipartProgress: true,
                reportsPostProcessingProgress: false
            )
            let baseOutputURL = cleanedImportVideoURL(
                in: destinationDirectory,
                sourceURL: sourceURL,
                rawTitle: videoInfo?.title,
                description: videoInfo?.description,
                uploader: videoInfo?.bestUploader,
                preferredExtension: "mp4"
            )
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
                "--user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            ]
            arguments += ytdlpDownloadNetworkArguments(isYouTube: isYouTubeURL(downloaderSourceURL))
            if let ffmpegDirectoryPath = localFFmpegDirectoryPath() {
                arguments += ["--ffmpeg-location", ffmpegDirectoryPath]
            }
            arguments += ytdlpFormatSelectionArguments()
            arguments += extraArguments
            if isBilibiliURL(sourceURL) {
                arguments += [
                    "--referer", "https://www.bilibili.com/",
                    "--extractor-args", "bilibili:prefer_multi_flv=False"
                ]
            }
            arguments += [
                "--paths", destinationDirectory.path,
                "-o", outputTemplate,
                "--print", "after_move:filepath",
                downloaderSourceURL.absoluteString
            ]
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let outputCollector = PipeLineCollector()
            let errorCollector = PipeLineCollector()
            let handleProgressLines: @Sendable ([String]) -> Void = { lines in
                for line in lines {
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

            try process.run()
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
                throw YTDLPDownloaderFailure(message: errorOutput, authorName: authorName)
            }

            let outputPath = output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .last?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard
                let outputPath,
                !outputPath.isEmpty,
                FileManager.default.fileExists(atPath: outputPath)
            else {
                throw YTDLPDownloaderFailure(message: errorOutput, authorName: authorName)
            }

            return DownloadedVideoResult(
                url: URL(fileURLWithPath: outputPath),
                authorName: authorName,
                sourceTitle: sourceTitle
            )
        }.value
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

        let authorName = normalizedImportTag(plan.info.bestUploader ?? "")
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
        env["PATH"] = "/opt/homebrew/bin:/opt/miniconda3/bin:/opt/anaconda3/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
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
            return [
                YTDLPArgumentAttempt(label: "本地解析", arguments: []),
                YTDLPArgumentAttempt(label: "Chrome Cookie", arguments: ["--cookies-from-browser", "chrome"])
            ]
        }
        return [YTDLPArgumentAttempt(arguments: [])]
    }

    nonisolated static func ytdlpYouTubeArgumentAttempts() -> [YTDLPArgumentAttempt] {
        return [
            YTDLPArgumentAttempt(label: "本地解析", arguments: []),
            YTDLPArgumentAttempt(label: "备用客户端", arguments: ytdlpYouTubeClientArguments()),
            YTDLPArgumentAttempt(label: "本地代理", arguments: ["--proxy", "http://127.0.0.1:1082"]),
            YTDLPArgumentAttempt(label: "代理备用客户端", arguments: ["--proxy", "http://127.0.0.1:1082"] + ytdlpYouTubeClientArguments()),
            YTDLPArgumentAttempt(label: "Safari Cookie", arguments: ["--cookies-from-browser", "safari"] + ytdlpYouTubeClientArguments()),
            YTDLPArgumentAttempt(label: "远程组件", arguments: ["--remote-components", "ejs:github"] + ytdlpYouTubeClientArguments())
        ]
    }

    nonisolated static func ytdlpYouTubeClientArguments() -> [String] {
        ["--extractor-args", "youtube:player_client=web_safari,mweb,android_vr"]
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
            "--retry-sleep", "fragment:exp=1:8"
        ]
        if isYouTube {
            arguments += ["--sleep-requests", "0.75"]
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
        guard line.contains("[download]"), line.contains("%") else { return nil }
        // 忽略 "Destination:" 等非进度行
        guard !line.contains("Destination:"),
              !line.contains("already been downloaded"),
              !line.contains("Merging") else { return nil }
        let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for token in tokens where token.hasSuffix("%") {
            if let value = Double(token.dropLast()), value >= 0 {
                return DownloadProgressUpdate(
                    progress: min(1.0, value / 100.0),
                    speed: parseYTDLPSpeed(from: line)
                )
            }
        }
        return nil
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
