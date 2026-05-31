//
//  LibraryStore+DownloaderSelfCheck.swift
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
    nonisolated static func localYTDLPURL() -> URL? {
        var paths = [String]()
        if let appManagedPath = appManagedYTDLPURL()?.path {
            paths.append(appManagedPath)
        }
        paths += [
            // Conda 版保留为回退，适合 Homebrew Python 兼容性异常的机器。
            "/opt/miniconda3/bin/yt-dlp",
            "/opt/anaconda3/bin/yt-dlp",
            // Homebrew 版常见，但如果 Python 环境异常会卡住；下面会做短超时健康检查。
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        return paths.first {
            FileManager.default.isExecutableFile(atPath: $0)
                && isResponsiveYTDLP(at: URL(fileURLWithPath: $0))
        }
            .map(URL.init(fileURLWithPath:))
    }

    nonisolated static func isResponsiveYTDLP(at url: URL, timeout: TimeInterval = 5) -> Bool {
        let process = Process()
        process.executableURL = url
        process.arguments = ["--version"]
        process.environment = downloaderProcessEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            if process.isRunning {
                process.terminate()
            }
            return false
        }

        return process.terminationStatus == 0
    }

    nonisolated static func loadDownloaderSelfCheckReport() -> DownloaderSelfCheckReport {
        guard
            let data = UserDefaults.standard.data(forKey: downloaderSelfCheckReportKey),
            let report = try? JSONDecoder().decode(DownloaderSelfCheckReport.self, from: data)
        else {
            return DownloaderSelfCheckReport()
        }
        return report.status == .running ? DownloaderSelfCheckReport() : report
    }

    nonisolated static func saveDownloaderSelfCheckReport(_ report: DownloaderSelfCheckReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        UserDefaults.standard.set(data, forKey: downloaderSelfCheckReportKey)
    }

    nonisolated static func isDownloaderSelfCheckFresh(_ report: DownloaderSelfCheckReport) -> Bool {
        guard report.status == .succeeded,
              let checkedAt = report.checkedAt
        else { return false }
        return Calendar.current.isDateInToday(checkedAt)
    }

    nonisolated struct DownloaderSelfCheckProcessResult: Sendable {
        var terminationStatus: Int32?
        var didTimeOut: Bool = false
        var output: String = ""
        var errorOutput: String = ""

        var succeeded: Bool { terminationStatus == 0 && !didTimeOut }
    }

    nonisolated struct DownloaderAutoRepairResult: Sendable {
        var didAttemptRepair = false
        var steps: [String] = []

        var summary: String {
            guard !steps.isEmpty else { return "未找到可自动更新渠道" }
            return steps.suffix(4).joined(separator: "；")
        }
    }

    nonisolated static func runDownloaderSelfCheck(startedAt: Date) async -> DownloaderSelfCheckReport {
        await Task.detached(priority: .utility) {
            let initialReport = runDownloaderSelfCheckOnce(startedAt: startedAt)
            guard initialReport.status == .failed else {
                return await reportByAddingExternalServiceChecks(to: initialReport)
            }

            let repairResult = runDownloaderAutoRepair()
            guard repairResult.didAttemptRepair else {
                var report = initialReport
                report.message = "\(initialReport.message)\n自动修复：\(repairResult.summary)"
                return await reportByAddingExternalServiceChecks(to: report)
            }

            var repairedReport = runDownloaderSelfCheckOnce(startedAt: Date())
            if repairedReport.status == .succeeded {
                repairedReport.message = "\(repairedReport.message)\n自动修复：\(repairResult.summary)"
                return await reportByAddingExternalServiceChecks(to: repairedReport)
            }

            repairedReport.message = "自动修复后仍失败：\(repairedReport.message)\n修复记录：\(repairResult.summary)"
            return await reportByAddingExternalServiceChecks(to: repairedReport)
        }.value
    }

    nonisolated static func runDownloaderSelfCheckOnce(startedAt: Date) -> DownloaderSelfCheckReport {
        guard let ytdlp = localYTDLPURL() else {
            return DownloaderSelfCheckReport(
                status: .failed,
                checkedAt: startedAt,
                message: "未找到 yt-dlp"
            )
        }

        let versionResult = runDownloaderSelfCheckProcess(
            executableURL: ytdlp,
            arguments: ["--version"],
            timeout: 10
        )
        let version = firstNonEmptyLine(in: versionResult.output)
        guard versionResult.succeeded, version != nil else {
            return DownloaderSelfCheckReport(
                status: .failed,
                checkedAt: startedAt,
                message: "yt-dlp 无法启动：\(selfCheckFailureMessage(from: versionResult, fallback: "请检查 yt-dlp 安装"))",
                ytdlpPath: ytdlp.path,
                ytdlpVersion: version
            )
        }

        guard let ffmpegURL = localFFmpegURL() else {
            return DownloaderSelfCheckReport(
                status: .failed,
                checkedAt: startedAt,
                message: "未找到 ffmpeg",
                ytdlpPath: ytdlp.path,
                ytdlpVersion: version
            )
        }

        var failures: [String] = []
        for attempt in ytdlpYouTubeArgumentAttempts() {
            let probeResult = runDownloaderSelfCheckProcess(
                executableURL: ytdlp,
                arguments: downloaderSelfCheckYouTubeProbeArguments(extraArguments: attempt.arguments),
                timeout: attempt.arguments.contains("--remote-components") ? 60 : 45
            )
            let outputLine = firstNonEmptyLine(in: probeResult.output)
            if probeResult.succeeded,
               let outputLine,
               let title = downloaderSelfCheckYouTubeProbeTitle(from: outputLine) {
                let label = attempt.label.isEmpty ? "默认线路" : attempt.label
                return DownloaderSelfCheckReport(
                    status: .succeeded,
                    checkedAt: startedAt,
                    message: "自检通过：YouTube 解析正常（\(label)）",
                    ytdlpPath: ytdlp.path,
                    ytdlpVersion: version,
                    ffmpegPath: ffmpegURL.path,
                    youtubeProbeTitle: title
                )
            }

            let label = attempt.label.isEmpty ? "默认线路" : attempt.label
            failures.append("\(label)：\(selfCheckFailureMessage(from: probeResult, fallback: "YouTube 解析失败"))")
        }

        return DownloaderSelfCheckReport(
            status: .failed,
            checkedAt: startedAt,
            message: failures.suffix(2).joined(separator: "\n"),
            ytdlpPath: ytdlp.path,
            ytdlpVersion: version,
            ffmpegPath: ffmpegURL.path
        )
    }

    nonisolated static func reportByAddingExternalServiceChecks(
        to report: DownloaderSelfCheckReport
    ) async -> DownloaderSelfCheckReport {
        async let appleMusicCheck = httpServiceSelfCheck(
            key: "appleMusicSearch",
            title: "Apple Music 搜索",
            url: appleMusicSelfCheckURL(),
            timeout: 8,
            successStatusUpperBound: 300,
            failureIsWarning: false
        )
        async let cobaltCheck = httpServiceSelfCheck(
            key: "cobalt",
            title: "Cobalt 下载兜底",
            url: URL(string: "https://api.cobalt.tools/"),
            timeout: 8,
            successStatusUpperBound: 500,
            failureIsWarning: false
        )
        async let xiaohongshuCheck = httpServiceSelfCheck(
            key: "xiaohongshuWeb",
            title: "小红书网页抓取",
            url: URL(string: "https://www.xiaohongshu.com/explore"),
            timeout: 8,
            successStatusUpperBound: 500,
            failureIsWarning: false
        )
        async let customImportAPICheck = configuredImportAPIServiceSelfCheck()
        async let ollamaCheck = ollamaServiceSelfCheck()

        var checks: [ExternalServiceSelfCheckItem] = [
            ytdlpServiceSelfCheckItem(from: report),
            ffmpegServiceSelfCheckItem(from: report),
            youtubeServiceSelfCheckItem(from: report),
            chromeCookieImportSelfCheck()
        ]

        checks.append(await appleMusicCheck)
        checks.append(await cobaltCheck)
        checks.append(await xiaohongshuCheck)
        if let customImportAPICheck = await customImportAPICheck {
            checks.append(customImportAPICheck)
        }
        checks.append(await ollamaCheck)

        var enriched = report
        enriched.serviceChecks = checks

        let failures = checks.filter { $0.status == .failed }
        let warnings = checks.filter { $0.status == .warning }
        if !failures.isEmpty {
            enriched.status = .failed
            let summary = failures
                .prefix(3)
                .map { "\($0.title)：\($0.message)" }
                .joined(separator: "；")
            enriched.message = "外部服务自检发现 \(failures.count) 项异常：\(summary)"
        } else if warnings.isEmpty {
            enriched.status = .succeeded
            enriched.message = "外部服务自检通过"
        } else if enriched.status == .succeeded {
            enriched.message = "核心下载自检通过，\(warnings.count) 项可选服务未就绪"
        }

        return enriched
    }

    nonisolated static func ytdlpServiceSelfCheckItem(from report: DownloaderSelfCheckReport) -> ExternalServiceSelfCheckItem {
        if let path = report.ytdlpPath {
            let version = report.ytdlpVersion.map { " · \($0)" } ?? ""
            return ExternalServiceSelfCheckItem(
                key: "ytdlp",
                title: "yt-dlp 下载器",
                status: .succeeded,
                message: "\(path)\(version)"
            )
        }
        return ExternalServiceSelfCheckItem(
            key: "ytdlp",
            title: "yt-dlp 下载器",
            status: .failed,
            message: "未找到或无法启动，已尝试自动安装/更新"
        )
    }

    nonisolated static func ffmpegServiceSelfCheckItem(from report: DownloaderSelfCheckReport) -> ExternalServiceSelfCheckItem {
        if let path = report.ffmpegPath {
            return ExternalServiceSelfCheckItem(
                key: "ffmpeg",
                title: "ffmpeg 转码器",
                status: .succeeded,
                message: path
            )
        }
        return ExternalServiceSelfCheckItem(
            key: "ffmpeg",
            title: "ffmpeg 转码器",
            status: .failed,
            message: "未找到 ffmpeg，下载后转码/合并可能失败"
        )
    }

    nonisolated static func youtubeServiceSelfCheckItem(from report: DownloaderSelfCheckReport) -> ExternalServiceSelfCheckItem {
        if let title = report.youtubeProbeTitle {
            return ExternalServiceSelfCheckItem(
                key: "youtube",
                title: "YouTube 抓取",
                status: .succeeded,
                message: title
            )
        }
        return ExternalServiceSelfCheckItem(
            key: "youtube",
            title: "YouTube 抓取",
            status: .failed,
            message: singleLineRepairMessage(report.message)
        )
    }

    nonisolated static func appleMusicSelfCheckURL() -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "test"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "country", value: "CN")
        ]
        return components?.url
    }

    nonisolated static func configuredImportAPIServiceSelfCheck() async -> ExternalServiceSelfCheckItem? {
        let endpoint = UserDefaults.standard.string(forKey: instagramImportEndpointDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !endpoint.isEmpty else { return nil }
        return await httpServiceSelfCheck(
            key: "customImportAPI",
            title: "自定义导入 API",
            url: URL(string: endpoint),
            timeout: 8,
            successStatusUpperBound: 500,
            failureIsWarning: false
        )
    }

    nonisolated static func httpServiceSelfCheck(
        key: String,
        title: String,
        url: URL?,
        timeout: TimeInterval,
        successStatusUpperBound: Int,
        failureIsWarning: Bool
    ) async -> ExternalServiceSelfCheckItem {
        guard let url else {
            return ExternalServiceSelfCheckItem(
                key: key,
                title: title,
                status: failureIsWarning ? .warning : .failed,
                message: "地址无效"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ExternalServiceSelfCheckItem(
                    key: key,
                    title: title,
                    status: failureIsWarning ? .warning : .failed,
                    message: "没有收到 HTTP 响应"
                )
            }
            let statusCode = httpResponse.statusCode
            if (200..<successStatusUpperBound).contains(statusCode) {
                return ExternalServiceSelfCheckItem(
                    key: key,
                    title: title,
                    status: .succeeded,
                    message: "HTTP \(statusCode)"
                )
            }
            return ExternalServiceSelfCheckItem(
                key: key,
                title: title,
                status: failureIsWarning ? .warning : .failed,
                message: "HTTP \(statusCode)"
            )
        } catch {
            return ExternalServiceSelfCheckItem(
                key: key,
                title: title,
                status: failureIsWarning ? .warning : .failed,
                message: singleLineRepairMessage(error.localizedDescription)
            )
        }
    }

    nonisolated static func chromeCookieImportSelfCheck() -> ExternalServiceSelfCheckItem {
        var missingTools: [String] = []
        if localYTDLPURL() == nil {
            missingTools.append("yt-dlp")
        }
        if localCurlURL() == nil {
            missingTools.append("curl")
        }

        return ExternalServiceSelfCheckItem(
            key: "chromeCookieImport",
            title: "Chrome 收藏后台读取",
            status: missingTools.isEmpty ? .succeeded : .failed,
            message: missingTools.isEmpty
                ? "使用已登录 Cookie 后台读取，不打开浏览器窗口"
                : "缺少 \(missingTools.joined(separator: "、"))，无法后台读取 Chrome Cookie"
        )
    }

    nonisolated static func ollamaServiceSelfCheck() async -> ExternalServiceSelfCheckItem {
        await httpServiceSelfCheck(
            key: "ollama",
            title: "Ollama 本地分析",
            url: URL(string: "http://127.0.0.1:11434/api/tags"),
            timeout: 3,
            successStatusUpperBound: 300,
            failureIsWarning: true
        )
    }

    nonisolated static func runDownloaderAutoRepair() -> DownloaderAutoRepairResult {
        var result = DownloaderAutoRepairResult()

        if let ytdlp = localYTDLPURL() {
            appendDownloaderRepairStep(
                name: "清理 yt-dlp 缓存",
                commandResult: runDownloaderSelfCheckProcess(
                    executableURL: ytdlp,
                    arguments: ["--rm-cache-dir"],
                    timeout: 20
                ),
                to: &result
            )

            appendDownloaderRepairStep(
                name: "更新 yt-dlp nightly 通道",
                commandResult: runDownloaderSelfCheckProcess(
                    executableURL: ytdlp,
                    arguments: ["--update-to", "nightly"],
                    timeout: 120
                ),
                to: &result
            )
        }

        if let brew = localBrewURL() {
            appendDownloaderRepairStep(
                name: "更新 Homebrew 索引",
                commandResult: runDownloaderSelfCheckProcess(
                    executableURL: brew,
                    arguments: ["update", "--quiet"],
                    timeout: 180
                ),
                to: &result
            )

            let upgradeResult = runDownloaderSelfCheckProcess(
                executableURL: brew,
                arguments: ["upgrade", "yt-dlp"],
                timeout: 240
            )
            appendDownloaderRepairStep(name: "升级 Homebrew yt-dlp", commandResult: upgradeResult, to: &result)

            if !upgradeResult.succeeded {
                appendDownloaderRepairStep(
                    name: "安装 Homebrew yt-dlp",
                    commandResult: runDownloaderSelfCheckProcess(
                        executableURL: brew,
                        arguments: ["install", "yt-dlp"],
                        timeout: 240
                    ),
                    to: &result
                )
            }
        }

        if let curl = localCurlURL() {
            appendDownloaderRepairStep(
                name: "安装应用内 nightly 下载器",
                commandResult: installAppManagedNightlyYTDLP(using: curl),
                to: &result
            )
        }

        if let python = ytdlpPythonURL() {
            appendDownloaderRepairStep(
                name: "升级 Python 下载组件",
                commandResult: runDownloaderSelfCheckProcess(
                    executableURL: python,
                    arguments: [
                        "-m", "pip", "install",
                        "--upgrade",
                        "--pre",
                        "yt-dlp[default]",
                        "yt-dlp-ejs"
                    ],
                    timeout: 240
                ),
                to: &result
            )
        }

        return result
    }

    nonisolated static func appendDownloaderRepairStep(
        name: String,
        commandResult: DownloaderSelfCheckProcessResult,
        to result: inout DownloaderAutoRepairResult
    ) {
        result.didAttemptRepair = true
        if commandResult.succeeded {
            result.steps.append("\(name)完成")
        } else {
            let message = selfCheckFailureMessage(from: commandResult, fallback: "失败")
            result.steps.append("\(name)未完成：\(singleLineRepairMessage(message))")
        }
    }

    nonisolated static func singleLineRepairMessage(_ message: String) -> String {
        let collapsed = message
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        return String(collapsed.prefix(160))
    }

    nonisolated static func localBrewURL() -> URL? {
        [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map(URL.init(fileURLWithPath:))
    }

    nonisolated static func localCurlURL() -> URL? {
        [
            "/usr/bin/curl",
            "/opt/homebrew/bin/curl",
            "/usr/local/bin/curl"
        ]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map(URL.init(fileURLWithPath:))
    }

    nonisolated static func appSupportToolsDirectoryURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LapianBao", isDirectory: true)
            .appendingPathComponent("Tools", isDirectory: true)
    }

    nonisolated static func appManagedYTDLPURL() -> URL? {
        appSupportToolsDirectoryURL()?.appendingPathComponent("yt-dlp")
    }

    nonisolated static func installAppManagedNightlyYTDLP(using curl: URL) -> DownloaderSelfCheckProcessResult {
        guard let toolsDirectory = appSupportToolsDirectoryURL(),
              let targetURL = appManagedYTDLPURL()
        else {
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 1,
                didTimeOut: false,
                output: "",
                errorOutput: "无法创建应用工具目录"
            )
        }

        let temporaryURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent(".yt-dlp.download")
        do {
            try FileManager.default.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: temporaryURL)
        } catch {
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 1,
                didTimeOut: false,
                output: "",
                errorOutput: error.localizedDescription
            )
        }

        let downloadResult = runDownloaderSelfCheckProcess(
            executableURL: curl,
            arguments: [
                "-L",
                "--fail",
                "--silent",
                "--show-error",
                "--retry", "2",
                "--connect-timeout", "15",
                "-o", temporaryURL.path,
                downloaderNightlyMacOSURL
            ],
            timeout: 180
        )
        guard downloadResult.succeeded else { return downloadResult }

        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporaryURL.path)
            try? FileManager.default.removeItem(at: targetURL)
            try FileManager.default.moveItem(at: temporaryURL, to: targetURL)
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 0,
                didTimeOut: false,
                output: "已安装到 \(targetURL.path)",
                errorOutput: ""
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 1,
                didTimeOut: false,
                output: "",
                errorOutput: error.localizedDescription
            )
        }
    }

    nonisolated static func ytdlpPythonURL() -> URL? {
        guard let ytdlp = localYTDLPURL(),
              let firstLine = try? String(contentsOf: ytdlp, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .first
        else { return nil }

        let shebang = String(firstLine)
        guard shebang.hasPrefix("#!") else { return nil }
        let path = shebang.dropFirst(2)
            .split(separator: " ")
            .first
            .map(String.init) ?? ""
        let loweredPath = path.lowercased()
        guard !loweredPath.contains("/cellar/yt-dlp/") else { return nil }
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    nonisolated static func downloaderSelfCheckYouTubeProbeArguments(extraArguments: [String]) -> [String] {
        var arguments = [
            "--no-playlist",
            "--skip-download",
            "--no-warnings",
            "--print", "%(id)s|%(title)s"
        ]
        arguments += ytdlpProbeNetworkArguments(isYouTube: true)
        arguments += ytdlpFormatSelectionArguments()
        arguments += extraArguments
        arguments.append(downloaderSelfCheckProbeURL)
        return arguments
    }

    nonisolated static func runDownloaderSelfCheckProcess(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> DownloaderSelfCheckProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = downloaderProcessEnvironment()

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
            return DownloaderSelfCheckProcessResult(
                terminationStatus: nil,
                output: "",
                errorOutput: error.localizedDescription
            )
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        let didTimeOut = semaphore.wait(timeout: .now() + timeout) == .timedOut
        if didTimeOut, process.isRunning {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 2)
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        return DownloaderSelfCheckProcessResult(
            terminationStatus: didTimeOut ? nil : process.terminationStatus,
            didTimeOut: didTimeOut,
            output: String(data: outputCollector.data, encoding: .utf8) ?? "",
            errorOutput: String(data: errorCollector.data, encoding: .utf8) ?? ""
        )
    }

    nonisolated static func downloaderSelfCheckYouTubeProbeTitle(from outputLine: String) -> String? {
        let parts = outputLine.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              isValidYouTubeVideoID(parts[0])
        else { return nil }
        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    nonisolated static func selfCheckFailureMessage(
        from result: DownloaderSelfCheckProcessResult,
        fallback: String
    ) -> String {
        if result.didTimeOut { return "超时" }
        let message = [result.errorOutput, result.output]
            .map { conciseYTDLPError($0, fallback: "") }
            .first(where: { !$0.isEmpty })
        return message ?? fallback
    }

    nonisolated static func firstNonEmptyLine(in text: String) -> String? {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    nonisolated static func ytdlpFormatSelectionArguments() -> [String] {
        [
            "-f", "bv*[vcodec^=avc1]+ba/b[ext=mp4]/bestvideo+bestaudio/best",
            "-S", "res,codec:h264:m4a",
            "--merge-output-format", "mp4"
        ]
    }

}
