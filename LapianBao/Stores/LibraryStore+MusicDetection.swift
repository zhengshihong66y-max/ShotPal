//
//  LibraryStore+MusicDetection.swift
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
    nonisolated static func isActiveDownloadStatus(_ status: RemoteImportJob.Status) -> Bool {
        switch status {
        case .importing, .transcoding, .finalizing:
            return true
        default:
            return false
        }
    }

    nonisolated struct MusicDownloadSource: Sendable {
        let name: String
        let target: String
        var extraArguments: [String] = []
    }

    nonisolated static func downloadMusicFromYouTube(
        query: String,
        into destinationDirectory: URL,
        preResolvedURL: URL? = nil,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let processRegistry = ToolProcessRegistry()
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: URL.self) { group in
                group.addTask {
                    try await downloadMusicFromYouTubeSearch(
                        query: query,
                        into: destinationDirectory,
                        preResolvedURL: preResolvedURL,
                        processRegistry: processRegistry,
                        progressCallback: progressCallback
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 300_000_000_000)
                    processRegistry.cancelRunningProcess()
                    throw RemoteImportError.downloaderFailed("YouTube 音乐下载超时。通常是网络不可达、YouTube 限速，或当前地区无法访问 YouTube 搜索。")
                }

                guard let result = try await group.next() else {
                    throw RemoteImportError.downloaderFailed("YouTube 音乐下载失败")
                }
                group.cancelAll()
                return result
            }
        } onCancel: {
            processRegistry.cancelRunningProcess()
        }
    }

    nonisolated static func downloadMusicFromYouTubeSearch(
        query: String,
        into destinationDirectory: URL,
        preResolvedURL: URL? = nil,
        processRegistry: ToolProcessRegistry,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        progressCallback?(0.02)
        let sources = await musicDownloadSources(for: query, preResolvedURL: preResolvedURL)
        var failures: [String] = []

        // 与导入页一致:进度条直接反映当前尝试的真实下载进度,
        // 不按尝试源数量切段;换源重试时进度回到起点重新走。
        for source in sources {
            progressCallback?(0.02)

            do {
                return try await runMusicYTDLPDownloadWithTimeout(
                    source: source,
                    into: destinationDirectory,
                    processRegistry: processRegistry,
                    progressCallback: { progress in
                        progressCallback?(min(0.98, progress))
                    }
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append("\(source.name)：\(error.localizedDescription)")
                // 已配置 cookie 仍被风控拦下:立刻结束梯子,让上层走 cookie 自动更新并重试
                if configuredYouTubeCookieFileURL() != nil,
                   isYouTubeBotVerificationFailure(error.localizedDescription) {
                    break
                }
            }
        }

        throw RemoteImportError.downloaderFailed(
            failures.isEmpty ? "YouTube 搜索下载失败" : failures.suffix(3).joined(separator: "\n")
        )
    }

    nonisolated static func musicDownloadSources(
        for query: String,
        preResolvedURL: URL? = nil
    ) async -> [MusicDownloadSource] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        // 与视频下载一致:配置了 cookies.txt 时 cookie 尝试排最前,
        // 避免每首歌都先烧完整梯子被风控拦下的匿名尝试。
        let attempts = ytdlpYouTubeCookieFileArgumentAttempts(cookieFileURL: configuredYouTubeCookieFileURL(), purpose: .audio)
            + ytdlpYouTubeArgumentAttempts()
        func expandedSources(name: String, target: String) -> [MusicDownloadSource] {
            attempts.map { attempt in
                MusicDownloadSource(
                    name: attempt.label.isEmpty ? name : "\(name)（\(attempt.label)）",
                    target: target,
                    extraArguments: attempt.arguments
                )
            }
        }

        var sources: [MusicDownloadSource] = []

        // 识别后预搜索命中的播放页排最前:点下载时连搜索都不用做
        if let preResolvedURL {
            sources.append(contentsOf: expandedSources(name: "预搜索播放页", target: preResolvedURL.absoluteString))
        }

        // 配置了 cookie 时让下载进程用 ytsearch1: 一步完成搜索+下载,
        // 省掉独立搜索探测的一整个进程(慢代理下约 6-10 秒);
        // 失败时仍有多客户端/代理尝试和 cookie 自动愈合兜底。
        if configuredYouTubeCookieFileURL() != nil {
            sources.append(contentsOf: expandedSources(name: "YouTube 搜索直下", target: "ytsearch1:\(trimmedQuery)"))
            return sources
        }

        if let firstResultURL = await firstYouTubeSearchResultURL(for: trimmedQuery) {
            sources.append(contentsOf: expandedSources(name: "YouTube 播放页", target: firstResultURL.absoluteString))
        }
        sources.append(contentsOf: expandedSources(name: "YouTube 搜索兜底", target: "ytsearch1:\(trimmedQuery)"))
        return sources
    }

    nonisolated static func firstYouTubeSearchResultURL(for query: String) async -> URL? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        if let ytdlpURL = await firstYouTubeSearchResultURLWithYTDLP(for: trimmedQuery) {
            return ytdlpURL
        }
        return await firstYouTubeSearchResultURLFromSearchPage(for: trimmedQuery)
    }

    nonisolated static func firstYouTubeSearchResultURLWithYTDLP(for query: String) async -> URL? {
        guard let ytdlp = localYTDLPURL() else { return nil }

        let processRegistry = ToolProcessRegistry()
        return await withTaskCancellationHandler {
            await withTaskGroup(of: URL?.self) { group in
                group.addTask {
                    await runFirstYouTubeSearchResultYTDLP(
                        executableURL: ytdlp,
                        query: query,
                        processRegistry: processRegistry
                    )
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    processRegistry.cancelRunningProcess()
                    return nil
                }

                let result = await group.next() ?? nil
                group.cancelAll()
                return result
            }
        } onCancel: {
            processRegistry.cancelRunningProcess()
        }
    }

    nonisolated static func runFirstYouTubeSearchResultYTDLP(
        executableURL: URL,
        query: String,
        processRegistry: ToolProcessRegistry
    ) async -> URL? {
        let attempt = ytdlpYouTubeCookieFileArgumentAttempts(cookieFileURL: configuredYouTubeCookieFileURL(), purpose: .audio).first
            ?? ytdlpYouTubeArgumentAttempts().first
            ?? YTDLPArgumentAttempt(arguments: [])
        return await Task.detached(priority: .utility) { () -> URL? in
            var arguments = [
                "--no-playlist",
                "--skip-download",
                "--no-warnings",
                "--default-search", "ytsearch",
                "--print", "%(webpage_url)s",
                "ytsearch1:\(query)"
            ]
            arguments.insert(contentsOf: ytdlpProbeNetworkArguments(isYouTube: true), at: 3)
            arguments.insert(contentsOf: attempt.arguments, at: max(0, arguments.count - 2))
            let result = ExternalProcessRunner.run(
                executableURL: executableURL,
                arguments: arguments,
                environment: downloaderProcessEnvironment(),
                processRegistry: processRegistry
            )

            if Task.isCancelled {
                processRegistry.cancelRunningProcess()
                return nil
            }
            guard result.succeeded else { return nil }

            return firstYouTubeWatchURL(fromYTDLPOutput: result.outputText)
        }.value
    }

    nonisolated static func firstYouTubeSearchResultURLFromSearchPage(for query: String) async -> URL? {
        guard var components = URLComponents(string: "https://www.youtube.com/results") else { return nil }

        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        guard let searchURL = components.url else { return nil }

        var request = URLRequest(url: searchURL)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<400).contains(httpResponse.statusCode) {
                return nil
            }
            guard
                let html = String(data: data, encoding: .utf8),
                let url = firstYouTubeWatchURL(in: html)
            else { return nil }
            return url
        } catch {
            return nil
        }
    }

    nonisolated static func firstYouTubeWatchURL(fromYTDLPOutput output: String) -> URL? {
        for line in output.split(whereSeparator: \.isNewline) {
            let rawURLString = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = normalizedYouTubeWatchURL(from: rawURLString) {
                return url
            }
        }
        return firstYouTubeWatchURL(in: output)
    }

    nonisolated static func firstYouTubeWatchURL(in text: String) -> URL? {
        let patterns = [
            #""videoRenderer"\s*:\s*\{\s*"videoId"\s*:\s*"([A-Za-z0-9_-]{11})""#,
            #""videoId"\s*:\s*"([A-Za-z0-9_-]{11})""#,
            #"watch\?v=([A-Za-z0-9_-]{11})"#,
            #"%2Fwatch%3Fv%3D([A-Za-z0-9_-]{11})"#,
            #"/shorts/([A-Za-z0-9_-]{11})"#
        ]
        let nsText = text as NSString
        let searchRange = NSRange(location: 0, length: nsText.length)

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: searchRange) where match.numberOfRanges > 1 {
                let videoID = nsText.substring(with: match.range(at: 1))
                if let url = youTubeWatchURL(videoID: videoID) {
                    return url
                }
            }
        }
        return nil
    }

    nonisolated static func normalizedYouTubeWatchURL(from rawURLString: String) -> URL? {
        guard
            let url = URL(string: rawURLString),
            let videoID = youTubeVideoID(from: url)
        else { return nil }
        return youTubeWatchURL(videoID: videoID)
    }

    nonisolated static func youTubeVideoID(from url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if host == "youtu.be",
           let videoID = pathComponents.first,
           isValidYouTubeVideoID(videoID) {
            return videoID
        }

        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }

        if let videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "v" })?
            .value,
           isValidYouTubeVideoID(videoID) {
            return videoID
        }

        for marker in ["shorts", "embed"] {
            if let markerIndex = pathComponents.firstIndex(of: marker) {
                let videoIndex = pathComponents.index(after: markerIndex)
                if pathComponents.indices.contains(videoIndex) {
                    let videoID = pathComponents[videoIndex]
                    if isValidYouTubeVideoID(videoID) {
                        return videoID
                    }
                }
            }
        }
        return nil
    }

    nonisolated static func youTubeWatchURL(videoID: String) -> URL? {
        guard isValidYouTubeVideoID(videoID) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    nonisolated static func isValidYouTubeVideoID(_ videoID: String) -> Bool {
        videoID.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
    }

    nonisolated static func runMusicYTDLPDownloadWithTimeout(
        source: MusicDownloadSource,
        into destinationDirectory: URL,
        processRegistry: ToolProcessRegistry,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                try await runMusicYTDLPDownload(
                    source: source,
                    into: destinationDirectory,
                    processRegistry: processRegistry,
                    progressCallback: progressCallback
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 90_000_000_000)
                processRegistry.cancelRunningProcess()
                throw RemoteImportError.downloaderFailed("\(source.name) 下载超时")
            }

            guard let result = try await group.next() else {
                throw RemoteImportError.downloaderFailed("\(source.name) 下载失败")
            }
            group.cancelAll()
            return result
        }
    }

    nonisolated static func runMusicYTDLPDownload(
        source: MusicDownloadSource,
        into destinationDirectory: URL,
        processRegistry: ToolProcessRegistry,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await Task.detached(priority: .utility) {
            guard let ytdlp = usableYTDLPURL() else {
                throw RemoteImportError.downloaderFailed("未找到可用的 yt-dlp，自动安装/更新也未完成。请检查网络后在设置里重新运行 yt-dlp 自检。")
            }

            let startedAt = Date()
            let process = Process()
            process.executableURL = ytdlp
            var env = downloaderProcessEnvironment()
            env["PYTHONUNBUFFERED"] = "1"
            env["PYTHONIOENCODING"] = "utf-8"
            process.environment = env

            var arguments = [
                "--no-playlist",
                "-x",
                "--audio-format", "m4a",
                "--audio-quality", "0",
                "-f", "ba/bestaudio/best",
                "--progress",
                "--newline",
                "--no-colors",
                "--progress-template", "download:lapianbao-progress downloaded=%(progress.downloaded_bytes)s total=%(progress.total_bytes)s total_estimate=%(progress.total_bytes_estimate)s speed=%(progress.speed)s",
                "--default-search", "ytsearch",
                "--paths", destinationDirectory.path,
                "-o", "%(title).160B-%(id)s.%(ext)s",
                "--print", "after_move:filepath"
            ]
            if let ffmpegDirectoryPath = localFFmpegDirectoryPath() {
                arguments.insert(contentsOf: ["--ffmpeg-location", ffmpegDirectoryPath], at: 6)
            }
            arguments += ytdlpDownloadNetworkArguments(isYouTube: true)
            arguments += source.extraArguments
            arguments.append(source.target)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let outputCollector = PipeLineCollector()
            let errorCollector = PipeLineCollector()
            let progressTracker = YTDLPProgressTracker(
                expectedPartCount: 1,
                downloadCompletionProgress: 0.94,
                postProcessingProgress: 0.98
            )
            let handleProgressLines: @Sendable ([String]) -> Void = { lines in
                for line in lines {
                    if let update = progressTracker.update(from: line),
                       let progress = update.progress {
                        progressCallback?(progress)
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
                throw RemoteImportError.downloaderFailed(
                    ytdlpLaunchFailureMessage(error, executableURL: ytdlp)
                )
            }
            processRegistry.set(process)
            defer {
                processRegistry.set(nil)
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                handleProgressLines(outputCollector.finish(with: outputPipe.fileHandleForReading.readDataToEndOfFile()))
                handleProgressLines(errorCollector.finish(with: errorPipe.fileHandleForReading.readDataToEndOfFile()))
                if Task.isCancelled, process.isRunning {
                    process.terminate()
                }
            }

            process.waitUntilExit()

            if Task.isCancelled {
                processRegistry.cancelRunningProcess()
                throw CancellationError()
            }

            let output = String(data: outputCollector.data, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorCollector.data, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw RemoteImportError.downloaderFailed(
                    conciseYTDLPError(
                        errorOutput,
                        fallback: "\(source.name) 下载失败，请确认网络可访问 YouTube，且已安装 yt-dlp 和 ffmpeg"
                    )
                )
            }

            guard let downloadedURL = downloadedMusicFileURL(
                fromYTDLPOutput: output,
                destinationDirectory: destinationDirectory,
                startedAt: startedAt
            ) else {
                throw RemoteImportError.downloaderFailed(
                    conciseYTDLPError(errorOutput, fallback: "找不到已下载的音频文件")
                )
            }

            return downloadedURL
        }.value
    }

    nonisolated static func downloadedMusicFileURL(
        fromYTDLPOutput output: String,
        destinationDirectory: URL,
        startedAt: Date
    ) -> URL? {
        let fm = FileManager.default
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            if fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        let audioExtensions = Set(["m4a", "mp3", "wav", "aac", "opus", "webm"])
        let urls = (try? fm.contentsOfDirectory(
            at: destinationDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true,
                      let modifiedAt = values?.contentModificationDate,
                      modifiedAt >= startedAt.addingTimeInterval(-2) else { return nil }
                return (url, modifiedAt)
            }
            .sorted { $0.1 > $1.1 }
            .first?
            .0
    }

    nonisolated static func conciseYTDLPError(_ message: String, fallback: String) -> String {
        let lines = message
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return fallback }

        let meaningfulLines = lines.filter { !isIgnorableYTDLPDiagnosticLine($0) }
        let candidates = meaningfulLines.isEmpty ? lines : meaningfulLines
        if let errorIndex = candidates.firstIndex(where: { $0.localizedCaseInsensitiveContains("ERROR:") }) {
            return candidates[errorIndex...].prefix(6).joined(separator: "\n")
        }
        return candidates.suffix(6).joined(separator: "\n")
    }

    nonisolated static func isIgnorableYTDLPDiagnosticLine(_ line: String) -> Bool {
        let lowercased = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowercased.hasPrefix("warning:")
            || lowercased.hasPrefix("[download]")
            || lowercased.hasPrefix("[info]")
            || lowercased.hasPrefix("[debug]")
            || lowercased.contains("has already been downloaded")
            || lowercased.contains("destination:")
            || lowercased.contains("merging formats")
    }

    // MARK: – Music detection helpers

    enum MusicDetectionEvent: Sendable {
        case progress(String)
        case found(MusicRecognitionItem)
    }

    nonisolated static func runMusicDetection(
        videoPath: String,
        onEvent: @Sendable @escaping (MusicDetectionEvent) async -> Void
    ) async throws -> [MusicRecognitionItem] {
        let processRegistry = ToolProcessRegistry()
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: [MusicRecognitionItem].self) { group in
                group.addTask {
                    try await runMusicDetectionProcess(
                        videoPath: videoPath,
                        onEvent: onEvent,
                        processRegistry: processRegistry
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 130_000_000_000)
                    processRegistry.cancelRunningProcess()
                    throw MusicDetectionError.timeout
                }

                guard let result = try await group.next() else { return [] }
                group.cancelAll()
                return result
            }
        } onCancel: {
            processRegistry.cancelRunningProcess()
        }
    }

    nonisolated static func runMusicDetectionProcess(
        videoPath: String,
        onEvent: @Sendable @escaping (MusicDetectionEvent) async -> Void,
        processRegistry: ToolProcessRegistry
    ) async throws -> [MusicRecognitionItem] {
        await onEvent(.progress("检查音乐识别环境"))
        let pythonURL = try ensurePythonRuntime(
            named: "music-env",
            requirementsRelativePath: "Tools/requirements-music.txt",
            probeModules: ["shazamio", "requests"]
        )
        guard let scriptURL = localToolURL(
            relativePath: "Tools/detect_music.py"
        ) else {
            throw MusicDetectionError.scriptMissing
        }
        guard FileManager.default.fileExists(atPath: videoPath) else {
            throw MusicDetectionError.videoMissing(videoPath)
        }
        guard FileManager.default.isReadableFile(atPath: videoPath) else {
            throw MusicDetectionError.videoUnreadable(videoPath)
        }

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [scriptURL.path, videoPath]
        var env = ProcessInfo.processInfo.environment
        let scriptBinPath = scriptURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .path
        let pythonBinPath = pythonURL.deletingLastPathComponent().path
        var pathParts = [
            scriptBinPath,
            pythonBinPath,
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        if let currentPath = env["PATH"], !currentPath.isEmpty {
            pathParts.append(currentPath)
        }
        env["PATH"] = pathParts.joined(separator: ":")
        env["VIRTUAL_ENV"] = pythonURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONNOUSERSITE"] = "1"
        env.removeValue(forKey: "PYTHONPATH")
        env["LAPIANBAO_MUSIC_MAX_SEGMENTS"] = env["LAPIANBAO_MUSIC_MAX_SEGMENTS"] ?? "12"
        env["LAPIANBAO_MUSIC_RECOGNIZE_TIMEOUT"] = env["LAPIANBAO_MUSIC_RECOGNIZE_TIMEOUT"] ?? "10"
        env["LAPIANBAO_MUSIC_ITUNES_TIMEOUT"] = env["LAPIANBAO_MUSIC_ITUNES_TIMEOUT"] ?? "3"
        env["LAPIANBAO_MUSIC_FFPROBE_TIMEOUT"] = env["LAPIANBAO_MUSIC_FFPROBE_TIMEOUT"] ?? "12"
        env["LAPIANBAO_MUSIC_FFMPEG_TIMEOUT"] = env["LAPIANBAO_MUSIC_FFMPEG_TIMEOUT"] ?? "12"
        env["LAPIANBAO_MUSIC_TOTAL_TIMEOUT"] = env["LAPIANBAO_MUSIC_TOTAL_TIMEOUT"] ?? "120"
        process.environment = env
        let errorPipe = Pipe()
        process.standardError = errorPipe

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        let errorCollector = PipeDataCollector()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorCollector.append(handle.availableData)
        }

        try process.run()
        processRegistry.set(process)
        defer {
            processRegistry.set(nil)
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
            if Task.isCancelled, process.isRunning {
                process.terminate()
            }
        }

        var songs: [MusicRecognitionItem] = []
        let stream = Self.makeLineStream(pipe: outputPipe)

        for await line in stream {
            if Task.isCancelled {
                processRegistry.cancelRunningProcess()
                throw CancellationError()
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let type = json["type"] as? String
            else { continue }

            switch type {
            case "progress":
                let msg = (json["message"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let val = json["value"] as? Double ?? 0
                let percent = Int((min(1, max(0, val)) * 100).rounded())
                let statusPrefix = "识别中 \(percent)%"
                let displayMessage = Self.isMusicDetectionSegmentTotalMessage(msg)
                    ? statusPrefix
                    : "\(statusPrefix) · \(msg)"
                await onEvent(.progress(displayMessage))

            case "found":
                if let songDict = json["song"] as? [String: Any],
                   let song = parseMusicItem(from: songDict) {
                    songs.append(song)
                    await onEvent(.found(song))
                }

            case "done":
                if let arr = json["songs"] as? [[String: Any]] {
                    songs = arr.compactMap { parseMusicItem(from: $0) }
                }

            case "error":
                let msg = json["message"] as? String ?? "识别失败"
                processRegistry.cancelRunningProcess()
                throw MusicDetectionError.scriptError(msg)

            default:
                break
            }
        }

        process.waitUntilExit()
        if Task.isCancelled {
            processRegistry.cancelRunningProcess()
            throw CancellationError()
        }
        if process.terminationStatus != 0 {
            let err = String(data: errorCollector.data, encoding: .utf8) ?? ""
            throw MusicDetectionError.scriptError(err.isEmpty ? "音乐识别脚本退出失败" : err)
        }
        return songs
    }

    nonisolated static func makeLineStream(pipe: Pipe) -> AsyncStream<String> {
        AsyncStream { continuation in
            let handle = pipe.fileHandleForReading
            final class Buf: @unchecked Sendable { var data = Data() }
            let buf = Buf()

            handle.readabilityHandler = { h in
                let chunk = h.availableData
                guard !chunk.isEmpty else {
                    if !buf.data.isEmpty,
                       let line = String(data: buf.data, encoding: .utf8),
                       !line.isEmpty {
                        continuation.yield(line)
                    }
                    continuation.finish()
                    h.readabilityHandler = nil
                    return
                }
                buf.data.append(chunk)
                while let nlIdx = buf.data.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineSlice = buf.data[buf.data.startIndex..<nlIdx]
                    buf.data.removeSubrange(buf.data.startIndex...nlIdx)
                    if let line = String(data: lineSlice, encoding: .utf8), !line.isEmpty {
                        continuation.yield(line)
                    }
                }
            }

            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }

    nonisolated static func parseMusicItem(from dict: [String: Any]) -> MusicRecognitionItem? {
        guard let title = dict["title"] as? String, !title.isEmpty else { return nil }
        let artist = dict["artist"] as? String ?? ""
        let tags = dict["tags"] as? [String] ?? [dict["genre"] as? String ?? ""]
        return MusicRecognitionItem(
            title: title,
            artist: artist,
            artworkURL: dict["artwork_url"] as? String ?? "",
            appleMusicURL: dict["apple_music_url"] as? String ?? "",
            detectedAt: dict["detected_at"] as? Double ?? 0,
            duration: parseMusicDurationSeconds(from: dict),
            tags: tags
        )
    }

    nonisolated static func parseMusicDurationSeconds(from dict: [String: Any]) -> Double {
        func doubleValue(_ value: Any?) -> Double? {
            switch value {
            case let value as Double:
                return value
            case let value as Float:
                return Double(value)
            case let value as Int:
                return Double(value)
            case let value as Int64:
                return Double(value)
            case let value as String:
                return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            default:
                return nil
            }
        }

        if let seconds = doubleValue(dict["duration"] ?? dict["duration_seconds"]),
           seconds.isFinite,
           seconds > 0 {
            return seconds
        }

        if let millis = doubleValue(dict["track_time_millis"] ?? dict["trackTimeMillis"]),
           millis.isFinite,
           millis > 0 {
            return millis / 1000
        }

        return 0
    }

    nonisolated static func isMusicDetectionSegmentTotalMessage(_ message: String) -> Bool {
        message.isEmpty
            || message.range(
                of: #"^共\s*\d+\s*段$"#,
                options: .regularExpression
            ) != nil
    }

    enum MusicDetectionError: LocalizedError {
        case envNotSetup
        case scriptMissing
        case videoMissing(String)
        case videoUnreadable(String)
        case timeout
        case scriptError(String)

        var errorDescription: String? {
            switch self {
            case .envNotSetup:
                return "未检测到音乐识别环境，且自动安装没有完成。请确认本机有 Python 3.11 以上版本和网络连接。"
            case .scriptMissing:
                return "未找到音乐识别脚本：Tools/detect_music.py"
            case .videoMissing(let path):
                return "视频文件不存在或无法访问：\(path)"
            case .videoUnreadable(let path):
                return "当前运行环境无法读取视频文件：\(path)。如果这是 Xcode 预览，请重新打开素材库或使用真实 App 运行一次授权。"
            case .timeout:
                return "音乐识别超时，已停止本次识别。可以稍后重试，或换一个更短的视频片段。"
            case .scriptError(let msg):
                return msg
            }
        }
    }

}
