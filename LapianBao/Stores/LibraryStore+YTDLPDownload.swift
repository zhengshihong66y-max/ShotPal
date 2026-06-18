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
            let authorName = normalizedSourceAuthorName(videoInfo?.bestUploader ?? "")
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

            let startedAt = Date()
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

            return DownloadedVideoResult(
                url: downloadedURL,
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
            var attempts = [
                YTDLPArgumentAttempt(label: "本地解析", arguments: []),
                YTDLPArgumentAttempt(label: "Chrome Cookie", arguments: ["--cookies-from-browser", "chrome"])
            ]
            for proxyURL in currentYTDLPProxyURLs() {
                let proxyArguments = ["--proxy", proxyURL]
                let label = ytdlpProxyAttemptLabel(for: proxyURL)
                attempts.append(YTDLPArgumentAttempt(label: label, arguments: proxyArguments))
                attempts.append(YTDLPArgumentAttempt(
                    label: "\(label) + Chrome Cookie",
                    arguments: proxyArguments + ["--cookies-from-browser", "chrome"]
                ))
            }
            return attempts
        }
        return [YTDLPArgumentAttempt(arguments: [])]
    }

    nonisolated static func ytdlpYouTubeArgumentAttempts() -> [YTDLPArgumentAttempt] {
        let browserCookieAttempts = ytdlpBrowserCookieAttempts()
        let clientArguments = ytdlpYouTubeClientArguments()
        var attempts = [YTDLPArgumentAttempt(label: "本地解析", arguments: [])]
        attempts += browserCookieAttempts

        for proxyURL in currentYTDLPProxyURLs() {
            let proxyArguments = ["--proxy", proxyURL]
            let label = ytdlpProxyAttemptLabel(for: proxyURL)
            attempts.append(YTDLPArgumentAttempt(label: label, arguments: proxyArguments))
            for cookieAttempt in browserCookieAttempts {
                attempts.append(YTDLPArgumentAttempt(
                    label: "\(label) + \(cookieAttempt.label)",
                    arguments: proxyArguments + cookieAttempt.arguments
                ))
            }
            attempts.append(YTDLPArgumentAttempt(label: "\(label)备用客户端", arguments: proxyArguments + clientArguments))
        }

        attempts.append(YTDLPArgumentAttempt(label: "备用客户端", arguments: clientArguments))
        for cookieAttempt in browserCookieAttempts {
            attempts.append(YTDLPArgumentAttempt(
                label: "\(cookieAttempt.label) + 备用客户端",
                arguments: cookieAttempt.arguments + clientArguments
            ))
        }
        attempts.append(YTDLPArgumentAttempt(label: "远程组件", arguments: ["--remote-components", "ejs:github"] + clientArguments))
        return uniqueYTDLPArgumentAttempts(attempts)
    }

    nonisolated static func ytdlpYouTubeSelfCheckArgumentAttempts() -> [YTDLPArgumentAttempt] {
        let browserCookieAttempts = Array(ytdlpBrowserCookieAttempts().prefix(1))
        let proxyURLs = currentYTDLPProxyURLs()
        let clientArguments = ytdlpYouTubeClientArguments()
        var attempts: [YTDLPArgumentAttempt] = []

        if let proxyURL = proxyURLs.first {
            let proxyArguments = ["--proxy", proxyURL]
            let proxyLabel = ytdlpProxyAttemptLabel(for: proxyURL)
            for cookieAttempt in browserCookieAttempts {
                attempts.append(YTDLPArgumentAttempt(
                    label: "\(proxyLabel) + \(cookieAttempt.label)",
                    arguments: proxyArguments + cookieAttempt.arguments
                ))
            }
            attempts.append(YTDLPArgumentAttempt(label: proxyLabel, arguments: proxyArguments))
            attempts.append(YTDLPArgumentAttempt(label: "\(proxyLabel)备用客户端", arguments: proxyArguments + clientArguments))
        } else {
            attempts += browserCookieAttempts
            attempts.append(YTDLPArgumentAttempt(label: "备用客户端", arguments: clientArguments))
        }

        attempts.append(YTDLPArgumentAttempt(label: "本地解析", arguments: []))
        return Array(uniqueYTDLPArgumentAttempts(attempts).prefix(4))
    }

    nonisolated static func ytdlpBrowserCookieAttempts() -> [YTDLPArgumentAttempt] {
        struct BrowserCandidate {
            var label: String
            var name: String
            var relativeProfilePath: String?
        }

        let candidates = [
            BrowserCandidate(label: "Chrome Cookie", name: "chrome", relativeProfilePath: "Library/Application Support/Google/Chrome"),
            BrowserCandidate(label: "Edge Cookie", name: "edge", relativeProfilePath: "Library/Application Support/Microsoft Edge"),
            BrowserCandidate(label: "Brave Cookie", name: "brave", relativeProfilePath: "Library/Application Support/BraveSoftware/Brave-Browser"),
            BrowserCandidate(label: "Firefox Cookie", name: "firefox", relativeProfilePath: "Library/Application Support/Firefox"),
            BrowserCandidate(label: "Chromium Cookie", name: "chromium", relativeProfilePath: "Library/Application Support/Chromium"),
            BrowserCandidate(label: "Safari Cookie", name: "safari", relativeProfilePath: "Library/Containers/com.apple.Safari/Data/Library/Cookies")
        ]

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        var attempts = candidates.compactMap { candidate -> YTDLPArgumentAttempt? in
            if let relativeProfilePath = candidate.relativeProfilePath {
                let path = homeURL.appendingPathComponent(relativeProfilePath).path
                guard FileManager.default.fileExists(atPath: path) else { return nil }
            }
            return YTDLPArgumentAttempt(
                label: candidate.label,
                arguments: ["--cookies-from-browser", candidate.name]
            )
        }

        if !attempts.contains(where: { $0.arguments == ["--cookies-from-browser", "chrome"] }) {
            attempts.insert(
                YTDLPArgumentAttempt(label: "Chrome Cookie", arguments: ["--cookies-from-browser", "chrome"]),
                at: 0
            )
        }
        return attempts
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
            || isYouTubeBotVerificationFailure(message)
    }

    nonisolated static func userFacingYTDLPFailureMessage(
        _ message: String,
        sourceURL: URL,
        fallback: String = "yt-dlp 下载失败"
    ) -> String {
        let concise = conciseYTDLPError(message, fallback: fallback)
        guard isYouTubeURL(sourceURL),
              isYouTubeBotVerificationFailure(concise)
        else { return concise }

        return "YouTube 要求登录验证：请先在 Chrome、Edge、Brave 或 Firefox 登录 YouTube 后重试。若仍失败，请给拉片宝开启完全磁盘访问权限，以便读取浏览器 Cookie；也可以配置可用代理或手动 Cookie。"
    }

    nonisolated static func isYouTubeBotVerificationFailure(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("sign in to confirm")
            && lowercased.contains("not a bot")
            || lowercased.contains("use --cookies-from-browser")
            && lowercased.contains("youtube")
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

    nonisolated static func ytdlpRemoteImportCandidateMetadata(for sourceURL: URL) async -> RemoteImportCandidateMetadata {
        guard let ytdlp = localYTDLPURL() else {
            return RemoteImportCandidateMetadata()
        }

        let environment = downloaderProcessEnvironment()
        let info = ytdlpArgumentAttempts(for: sourceURL)
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
