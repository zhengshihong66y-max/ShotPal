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
    nonisolated static let downloaderYTDLPQuickCheckTimeout: TimeInterval = 1.5

    nonisolated static func localYTDLPURL() -> URL? {
        localYTDLPInfo()?.url
    }

    nonisolated static func localYTDLPInfo(
        timeout: TimeInterval = downloaderYTDLPQuickCheckTimeout
    ) -> (url: URL, version: String?)? {
        for path in localYTDLPCandidatePaths() {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)
            let result = ExternalProcessRunner.run(
                executableURL: url,
                arguments: ["--version"],
                environment: downloaderProcessEnvironment(),
                timeout: timeout
            )
            guard result.succeeded else { continue }
            return (url, firstNonEmptyLine(in: result.outputText))
        }
        return nil
    }

    nonisolated static func localYTDLPCandidatePaths() -> [String] {
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
        return paths
    }

    nonisolated static func usableYTDLPURL(repairIfNeeded: Bool = true) -> URL? {
        if let ytdlp = localYTDLPURL() {
            return ytdlp
        }
        guard repairIfNeeded else { return nil }

        var repairResult = DownloaderAutoRepairResult()
        repairYTDLPTooling(to: &repairResult)

        guard let managedYTDLP = appManagedYTDLPURL(),
              FileManager.default.isExecutableFile(atPath: managedYTDLP.path),
              isResponsiveYTDLP(at: managedYTDLP, timeout: 8)
        else {
            return localYTDLPURL()
        }
        return managedYTDLP
    }

    nonisolated static func isResponsiveYTDLP(at url: URL, timeout: TimeInterval = 5) -> Bool {
        ExternalProcessRunner.run(
            executableURL: url,
            arguments: ["--version"],
            environment: downloaderProcessEnvironment(),
            timeout: timeout
        ).succeeded
    }

    nonisolated static func loadDownloaderSelfCheckReport() -> DownloaderSelfCheckReport {
        guard
            let data = AppSettings.downloaderSelfCheckReportData,
            let report = try? JSONDecoder().decode(DownloaderSelfCheckReport.self, from: data)
        else {
            return DownloaderSelfCheckReport()
        }
        return report.status == .running ? DownloaderSelfCheckReport() : report
    }

    nonisolated static func saveDownloaderSelfCheckReport(_ report: DownloaderSelfCheckReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        AppSettings.downloaderSelfCheckReportData = data
    }

    nonisolated static func isDownloaderSelfCheckFresh(_ report: DownloaderSelfCheckReport) -> Bool {
        guard report.status == .succeeded,
              let checkedAt = report.checkedAt
        else { return false }
        return Calendar.current.isDateInToday(checkedAt)
    }

    nonisolated enum DownloaderSelfCheckRepairMode: Sendable {
        case afterFailure
        case always
    }

    nonisolated static let downloaderProblemYTDLP = "yt-dlp 下载器"
    nonisolated static let downloaderProblemYTDLPLaunch = "yt-dlp 启动"
    nonisolated static let downloaderSelfCheckTimeLimit: TimeInterval = 55
    nonisolated static let downloaderSelfCheckVersionTimeout: TimeInterval = 6
    nonisolated static let downloaderNightlyLatestReleaseAPIURL = "https://api.github.com/repos/yt-dlp/yt-dlp-nightly-builds/releases/latest"
    nonisolated static let downloaderTemporaryYTDLPPrefix = ".yt-dlp.download-"
    nonisolated static let downloaderBackupYTDLPPrefix = ".yt-dlp.backup-"
    nonisolated static let downloaderToolingLockDirectoryName = ".yt-dlp.self-check.lock"
    nonisolated static let downloaderToolingLockStaleAge: TimeInterval = 10 * 60

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
            return steps.suffix(6).joined(separator: "；")
        }
    }

    nonisolated struct DownloaderToolingLock: Sendable {
        var url: URL
    }

    nonisolated struct YTDLPNightlyRelease: Sendable {
        var version: String
        var downloadURL: String
        var digest: String?
        var htmlURL: String?
    }

    nonisolated struct YTDLPNightlyReleaseFetchResult: Sendable {
        var release: YTDLPNightlyRelease?
        var commandResult: DownloaderSelfCheckProcessResult
    }

    nonisolated struct GitHubYTDLPReleaseResponse: Decodable, Sendable {
        struct Asset: Decodable, Sendable {
            var name: String
            var digest: String?
            var browserDownloadURL: String

            private enum CodingKeys: String, CodingKey {
                case name, digest
                case browserDownloadURL = "browser_download_url"
            }
        }

        var tagName: String
        var htmlURL: String?
        var assets: [Asset]

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }

        var preferredMacOSRelease: YTDLPNightlyRelease? {
            guard let asset = assets.first(where: { $0.name == "yt-dlp" })
                    ?? assets.first(where: { $0.name == "yt-dlp_macos" })
            else { return nil }
            return YTDLPNightlyRelease(
                version: tagName,
                downloadURL: asset.browserDownloadURL,
                digest: asset.digest,
                htmlURL: htmlURL
            )
        }
    }

    nonisolated static func runningDownloaderSelfCheckReport(
        startedAt: Date,
        message: String,
        progress: Double
    ) -> DownloaderSelfCheckReport {
        DownloaderSelfCheckReport(
            status: .running,
            checkedAt: startedAt,
            message: message,
            progress: normalizedProgress(progress)
        )
    }

    nonisolated static func downloaderSelfCheckDeadline(startedAt: Date) -> Date {
        startedAt.addingTimeInterval(downloaderSelfCheckTimeLimit)
    }

    nonisolated static func remainingDownloaderSelfCheckTime(until deadline: Date?) -> TimeInterval? {
        guard let deadline else { return nil }
        return max(0, deadline.timeIntervalSinceNow)
    }

    nonisolated static func downloaderSelfCheckTimeout(
        requested timeout: TimeInterval,
        deadline: Date?,
        reserve: TimeInterval = 2
    ) -> TimeInterval? {
        guard let remaining = remainingDownloaderSelfCheckTime(until: deadline) else {
            return timeout
        }
        let available = remaining - reserve
        guard available >= 1 else { return nil }
        return min(timeout, available)
    }

    nonisolated static func runDownloaderSelfCheck(
        startedAt: Date,
        repairMode: DownloaderSelfCheckRepairMode = .afterFailure,
        progressHandler: (@Sendable (DownloaderSelfCheckReport) -> Void)? = nil
    ) async -> DownloaderSelfCheckReport {
        let task = Task.detached(priority: .utility) {
            @Sendable func publish(_ progress: Double, _ message: String) {
                progressHandler?(runningDownloaderSelfCheckReport(
                    startedAt: startedAt,
                    message: message,
                    progress: progress
                ))
            }

            let deadline: Date? = nil
            publish(0.04, "正在检查 yt-dlp 可用性")
            _ = removeStaleAppManagedYTDLPArtifactsIfPossible()

            let currentYTDLPInfo = localYTDLPInfo()
            let currentYTDLP = currentYTDLPInfo?.url
            let currentVersion = currentYTDLPInfo?.version

            if repairMode != .always,
               currentYTDLP != nil {
                let versionText = currentVersion ?? "未知版本"
                publish(1.0, "yt-dlp 可用")
                let report = DownloaderSelfCheckReport(
                    status: .succeeded,
                    checkedAt: startedAt,
                    message: "yt-dlp 可用：\(versionText)",
                    ytdlpPath: currentYTDLP?.path,
                    ytdlpVersion: currentVersion,
                    repairSummary: "本地可用性检查通过，未执行联网更新",
                    progress: 1
                )
                return reportByAddingDownloaderSelfCheckItems(to: report)
            }

            guard let curl = localCurlURL() else {
                var report = DownloaderSelfCheckReport(
                    status: currentYTDLP == nil ? .failed : .succeeded,
                    checkedAt: startedAt,
                    message: currentYTDLP == nil
                        ? "无法检查最新版：未找到 curl，也未找到可用 yt-dlp"
                        : "无法检查最新版：未找到 curl；当前 yt-dlp 可用",
                    ytdlpPath: currentYTDLP?.path,
                    ytdlpVersion: currentVersion,
                    problemLocation: currentYTDLP == nil ? downloaderProblemYTDLP : nil,
                    progress: 1
                )
                report.repairSummary = "未找到 curl，无法连接 GitHub 获取最新版"
                publish(1.0, "步骤 1/2：yt-dlp 最新版检查结束")
                return reportByAddingDownloaderSelfCheckItems(to: report)
            }

            let latestFetch = fetchLatestNightlyYTDLPRelease(
                using: curl,
                deadline: deadline,
                progressHandler: { progress, message in
                    publish(progress, message)
                }
            )

            guard let latestRelease = latestFetch.release else {
                let failure = selfCheckFailureMessage(
                    from: latestFetch.commandResult,
                    fallback: "无法读取 GitHub 最新版本"
                )
                let report = DownloaderSelfCheckReport(
                    status: currentYTDLP == nil ? .failed : .succeeded,
                    checkedAt: startedAt,
                    message: currentYTDLP == nil
                        ? "无法检查或安装最新版 yt-dlp：\(singleLineRepairMessage(failure))"
                        : "最新版检查未完成；当前 yt-dlp 可用：\(currentVersion ?? "未知版本")",
                    ytdlpPath: currentYTDLP?.path,
                    ytdlpVersion: currentVersion,
                    problemLocation: currentYTDLP == nil ? downloaderProblemYTDLP : nil,
                    repairSummary: singleLineRepairMessage(failure),
                    progress: 1
                )
                publish(1.0, "步骤 1/2：yt-dlp 最新版检查结束")
                return reportByAddingDownloaderSelfCheckItems(to: report)
            }

            let isOutdated = currentVersion.map {
                isYTDLPVersion($0, olderThan: latestRelease.version)
            } ?? true
            let shouldDownload = repairMode == .always || isOutdated
            let currentText = currentVersion ?? "未安装"
            publish(
                0.32,
                "步骤 1/2：最新版 \(latestRelease.version)，当前 \(currentText)"
            )

            guard shouldDownload else {
                publish(1.0, "步骤 2/2：yt-dlp 已是最新版")
                let report = DownloaderSelfCheckReport(
                    status: .succeeded,
                    checkedAt: startedAt,
                    message: "yt-dlp 已是最新版：\(latestRelease.version)",
                    ytdlpPath: currentYTDLP?.path,
                    ytdlpVersion: currentVersion,
                    repairSummary: "上游最新版 \(latestRelease.version)，无需替换",
                    progress: 1
                )
                return reportByAddingDownloaderSelfCheckItems(to: report)
            }

            publish(0.44, "步骤 2/2：正在下载最新 yt-dlp")
            var repairResult = DownloaderAutoRepairResult()
            repairYTDLPTooling(
                to: &repairResult,
                deadline: deadline,
                downloadTimeout: repairMode == .always ? 120 : 90,
                latestRelease: latestRelease,
                progressHandler: { progress, message in
                    publish(progress, message)
                }
            )

            let managedYTDLP = appManagedYTDLPURL()
            let installedVersion = managedYTDLP.flatMap {
                ytdlpVersion(at: $0, deadline: deadline)
            }
            let installSucceeded = managedYTDLP.map {
                FileManager.default.isExecutableFile(atPath: $0.path)
            } == true
                && installedVersion != nil
                && !(installedVersion.map { isYTDLPVersion($0, olderThan: latestRelease.version) } ?? true)

            publish(1.0, "步骤 2/2：yt-dlp 更新检查完成")
            let message: String
            let repairWasBlocked = repairResult.steps.contains {
                $0.contains("已有自检或修复正在运行")
            }
            if installSucceeded, repairWasBlocked {
                message = "已有 yt-dlp 自检或修复正在运行；当前 yt-dlp 可用：\(installedVersion ?? currentVersion ?? "未知版本")"
            } else if installSucceeded {
                message = "yt-dlp 已更新到最新版：\(installedVersion ?? latestRelease.version)"
            } else {
                message = currentYTDLP == nil
                    ? "yt-dlp 最新版安装失败：\(repairResult.summary)"
                    : "yt-dlp 最新版替换未完成；当前版本仍可用：\(currentVersion ?? "未知版本")"
            }
            let report = DownloaderSelfCheckReport(
                status: installSucceeded || currentYTDLP != nil ? .succeeded : .failed,
                checkedAt: startedAt,
                message: message,
                ytdlpPath: installSucceeded ? managedYTDLP?.path : currentYTDLP?.path,
                ytdlpVersion: installSucceeded ? installedVersion : currentVersion,
                problemLocation: installSucceeded || currentYTDLP != nil ? nil : downloaderProblemYTDLP,
                repairSummary: repairResult.summary,
                progress: 1
            )
            return reportByAddingDownloaderSelfCheckItems(to: report)
        }
        return await task.value
    }

    nonisolated static func reportByAddingDownloaderSelfCheckItems(
        to report: DownloaderSelfCheckReport
    ) -> DownloaderSelfCheckReport {
        let checks = [ytdlpServiceSelfCheckItem(from: report)]

        var enriched = report
        enriched.serviceChecks = checks

        let failures = checks.filter { $0.status == .failed }
        if !failures.isEmpty {
            enriched.status = .failed
            enriched.problemLocation = failures
                .prefix(4)
                .map(\.title)
                .joined(separator: "、")
            let summary = failures
                .prefix(3)
                .map { "\($0.title)：\($0.message)" }
                .joined(separator: "；")
            enriched.message = "下载器自检发现 \(failures.count) 项异常：\(summary)"
        } else if enriched.status == .idle || enriched.status == .running {
            enriched.status = .succeeded
            enriched.problemLocation = nil
            if enriched.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || enriched.message == "未自检" {
                enriched.message = "yt-dlp 自检通过"
            }
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

    nonisolated static func fetchLatestNightlyYTDLPRelease(
        using curl: URL,
        deadline: Date? = nil,
        requestTimeout: TimeInterval = 18,
        progressHandler: (@Sendable (Double, String) -> Void)? = nil
    ) -> YTDLPNightlyReleaseFetchResult {
        var lastResult = DownloaderSelfCheckProcessResult(
            terminationStatus: 1,
            output: "",
            errorOutput: "未启动 GitHub 最新版本检查"
        )
        let proxyAttempts: [String?] = currentYTDLPProxyURLs().map(Optional.some) + [nil]
        let segmentWidth = 0.24 / Double(max(proxyAttempts.count, 1))

        for (index, proxyURL) in proxyAttempts.enumerated() {
            guard let timeout = downloaderSelfCheckTimeout(
                requested: requestTimeout,
                deadline: deadline,
                reserve: 2
            ), timeout >= 4 else {
                break
            }

            let routeLabel = proxyURL == nil ? "直连" : "系统代理"
            let progressBase = 0.06 + segmentWidth * Double(index)
            progressHandler?(progressBase, "步骤 1/2：正在通过\(routeLabel)检查 yt-dlp 最新版本")

            let curlMaxTime = max(4, timeout - 1)
            var arguments = [
                "-L",
                "--fail",
                "--silent",
                "--show-error",
                "--retry", "1",
                "--connect-timeout", String(Int(min(6, max(2, curlMaxTime / 3)))),
                "--max-time", String(Int(curlMaxTime)),
                "-H", "Accept: application/vnd.github+json",
                "-H", "X-GitHub-Api-Version: 2022-11-28"
            ]
            if let proxyURL {
                arguments += ["--proxy", proxyURL]
            }
            arguments.append(downloaderNightlyLatestReleaseAPIURL)

            let result = runDownloaderSelfCheckProcess(
                executableURL: curl,
                arguments: arguments,
                timeout: timeout,
                progressTick: { elapsed in
                    let elapsedProgress = min(0.9, elapsed / timeout)
                    let progress = progressBase + segmentWidth * elapsedProgress
                    progressHandler?(
                        progress,
                        "步骤 1/2：正在通过\(routeLabel)检查 yt-dlp 最新版本（\(Int(elapsed.rounded())) 秒）"
                    )
                }
            )
            lastResult = result
            guard result.succeeded else { continue }

            guard let data = result.output.data(using: .utf8),
                  let response = try? JSONDecoder().decode(GitHubYTDLPReleaseResponse.self, from: data),
                  let release = response.preferredMacOSRelease
            else {
                lastResult = DownloaderSelfCheckProcessResult(
                    terminationStatus: 1,
                    output: result.output,
                    errorOutput: "GitHub 最新版本响应缺少 yt-dlp"
                )
                continue
            }

            progressHandler?(0.31, "步骤 1/2：发现 yt-dlp 最新版 \(release.version)")
            return YTDLPNightlyReleaseFetchResult(release: release, commandResult: result)
        }

        return YTDLPNightlyReleaseFetchResult(release: nil, commandResult: lastResult)
    }

    nonisolated static func repairYTDLPTooling(
        to result: inout DownloaderAutoRepairResult,
        deadline: Date? = nil,
        downloadTimeout: TimeInterval = 105,
        latestRelease: YTDLPNightlyRelease? = nil,
        progressHandler: (@Sendable (Double, String) -> Void)? = nil
    ) {
        guard let lock = acquireDownloaderToolingLock() else {
            result.didAttemptRepair = true
            result.steps.append("更新应用托管 yt-dlp 未启动：已有自检或修复正在运行")
            return
        }
        defer {
            _ = removeStaleAppManagedYTDLPArtifacts()
            releaseDownloaderToolingLock(lock)
        }

        if let artifactCleanupResult = removeStaleAppManagedYTDLPArtifacts() {
            appendDownloaderRepairStep(
                name: "清理 yt-dlp 临时文件",
                commandResult: artifactCleanupResult,
                to: &result
            )
        }

        if let cleanupResult = removeUnresponsiveAppManagedYTDLP() {
            appendDownloaderRepairStep(
                name: "清理失效的应用内 yt-dlp",
                commandResult: cleanupResult,
                to: &result
            )
        }

        guard let curl = localCurlURL() else {
            result.steps.append("更新应用托管 yt-dlp 未完成：未找到 curl")
            return
        }

        appendDownloaderRepairStep(
            name: "更新应用托管 yt-dlp nightly",
            commandResult: installAppManagedNightlyYTDLP(
                using: curl,
                deadline: deadline,
                downloadTimeout: downloadTimeout,
                latestRelease: latestRelease,
                progressHandler: progressHandler
            ),
            to: &result
        )
    }

    nonisolated static func acquireDownloaderToolingLock() -> DownloaderToolingLock? {
        guard let toolsDirectory = appSupportToolsDirectoryURL() else { return nil }
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let lockURL = toolsDirectory.appendingPathComponent(downloaderToolingLockDirectoryName, isDirectory: true)
        for _ in 0..<2 {
            do {
                try fileManager.createDirectory(at: lockURL, withIntermediateDirectories: false)
                let ownerText = "\(getpid())\n\(Date().timeIntervalSince1970)\n"
                try? ownerText.write(
                    to: lockURL.appendingPathComponent("owner"),
                    atomically: true,
                    encoding: .utf8
                )
                return DownloaderToolingLock(url: lockURL)
            } catch {
                guard fileManager.fileExists(atPath: lockURL.path),
                      removeStaleDownloaderToolingLock(at: lockURL)
                else {
                    return nil
                }
            }
        }
        return nil
    }

    nonisolated static func releaseDownloaderToolingLock(_ lock: DownloaderToolingLock) {
        try? FileManager.default.removeItem(at: lock.url)
    }

    nonisolated static func removeStaleDownloaderToolingLock(at lockURL: URL) -> Bool {
        let fileManager = FileManager.default
        let ownerURL = lockURL.appendingPathComponent("owner")
        let ownerText = (try? String(contentsOf: ownerURL, encoding: .utf8)) ?? ""
        let ownerPID = ownerText
            .split(whereSeparator: \.isNewline)
            .first
            .flatMap { Int32($0) }

        if let ownerPID, ownerPID > 0, isProcessAlive(pid: ownerPID) {
            return false
        }

        if ownerPID == nil,
           let attributes = try? fileManager.attributesOfItem(atPath: lockURL.path),
           let modifiedAt = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modifiedAt) < downloaderToolingLockStaleAge {
            return false
        }

        do {
            try fileManager.removeItem(at: lockURL)
            return true
        } catch {
            return false
        }
    }

    nonisolated static func isProcessAlive(pid: Int32) -> Bool {
        if Darwin.kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    nonisolated static func removeStaleAppManagedYTDLPArtifacts() -> DownloaderSelfCheckProcessResult? {
        guard let toolsDirectory = appSupportToolsDirectoryURL(),
              FileManager.default.fileExists(atPath: toolsDirectory.path)
        else { return nil }

        let fileManager = FileManager.default
        let candidates = (try? fileManager.contentsOfDirectory(
            at: toolsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        let removable = candidates.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix(downloaderTemporaryYTDLPPrefix)
                || name.hasPrefix(downloaderBackupYTDLPPrefix)
        }
        guard !removable.isEmpty else { return nil }

        var removedNames = [String]()
        var errors = [String]()
        for url in removable {
            do {
                try fileManager.removeItem(at: url)
                removedNames.append(url.lastPathComponent)
            } catch {
                errors.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        return DownloaderSelfCheckProcessResult(
            terminationStatus: errors.isEmpty ? 0 : 1,
            didTimeOut: false,
            output: removedNames.isEmpty ? "" : "已清理 \(removedNames.joined(separator: "、"))",
            errorOutput: errors.joined(separator: "；")
        )
    }

    nonisolated static func removeStaleAppManagedYTDLPArtifactsIfPossible() -> DownloaderSelfCheckProcessResult? {
        guard let lock = acquireDownloaderToolingLock() else { return nil }
        defer { releaseDownloaderToolingLock(lock) }
        return removeStaleAppManagedYTDLPArtifacts()
    }

    nonisolated static func removeUnresponsiveAppManagedYTDLP() -> DownloaderSelfCheckProcessResult? {
        guard let targetURL = appManagedYTDLPURL(),
              FileManager.default.isExecutableFile(atPath: targetURL.path),
              !isResponsiveYTDLP(at: targetURL, timeout: 2)
        else { return nil }

        do {
            try FileManager.default.removeItem(at: targetURL)
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 0,
                output: "已移除 \(targetURL.path)",
                errorOutput: ""
            )
        } catch {
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 1,
                output: "",
                errorOutput: error.localizedDescription
            )
        }
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

    nonisolated static func localCurlURL() -> URL? {
        [
            "/usr/bin/curl",
            "/opt/homebrew/bin/curl",
            "/usr/local/bin/curl"
        ]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map(URL.init(fileURLWithPath:))
    }

    nonisolated static func localShasumURL() -> URL? {
        [
            "/usr/bin/shasum",
            "/opt/homebrew/bin/shasum",
            "/usr/local/bin/shasum"
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

    nonisolated static func ytdlpVersion(
        at url: URL,
        deadline: Date? = nil,
        timeout requestedTimeout: TimeInterval = downloaderSelfCheckVersionTimeout
    ) -> String? {
        guard let timeout = downloaderSelfCheckTimeout(
            requested: requestedTimeout,
            deadline: deadline
        ) else { return nil }
        let result = runDownloaderSelfCheckProcess(
            executableURL: url,
            arguments: ["--version"],
            timeout: timeout
        )
        guard result.succeeded else { return nil }
        return firstNonEmptyLine(in: result.output)
    }

    nonisolated static func isYTDLPVersion(_ currentVersion: String, olderThan latestVersion: String) -> Bool {
        guard let current = ytdlpVersionComponents(currentVersion),
              let latest = ytdlpVersionComponents(latestVersion)
        else {
            return currentVersion.localizedStandardCompare(latestVersion) == .orderedAscending
        }

        let count = max(current.count, latest.count)
        for index in 0..<count {
            let lhs = index < current.count ? current[index] : 0
            let rhs = index < latest.count ? latest[index] : 0
            if lhs != rhs { return lhs < rhs }
        }
        return false
    }

    nonisolated static func ytdlpVersionComponents(_ version: String) -> [Int]? {
        let components = version
            .split { !$0.isNumber }
            .compactMap { Int($0) }
        return components.isEmpty ? nil : components
    }

    nonisolated static func normalizedSHA256Digest(_ digest: String) -> String? {
        let lowered = digest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = lowered.hasPrefix("sha256:")
            ? String(lowered.dropFirst("sha256:".count))
            : lowered
        guard value.count == 64,
              value.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil
        else { return nil }
        return value
    }

    nonisolated static func verifySHA256Digest(_ digest: String, for fileURL: URL) -> Bool {
        guard let expected = normalizedSHA256Digest(digest),
              let shasum = localShasumURL()
        else { return true }

        let result = runDownloaderSelfCheckProcess(
            executableURL: shasum,
            arguments: ["-a", "256", fileURL.path],
            timeout: 10
        )
        guard result.succeeded,
              let firstLine = firstNonEmptyLine(in: result.output),
              let actual = firstLine.split(separator: " ").first.map({ String($0).lowercased() })
        else { return false }
        return actual == expected
    }

    nonisolated static func replaceAppManagedYTDLP(at targetURL: URL, with temporaryURL: URL) throws {
        let fileManager = FileManager.default
        let backupURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent("\(downloaderBackupYTDLPPrefix)\(UUID().uuidString)")
        let hadExistingTarget = fileManager.fileExists(atPath: targetURL.path)

        if hadExistingTarget {
            try fileManager.moveItem(at: targetURL, to: backupURL)
        }

        do {
            try fileManager.moveItem(at: temporaryURL, to: targetURL)
        } catch {
            if hadExistingTarget {
                try? fileManager.moveItem(at: backupURL, to: targetURL)
            }
            throw error
        }

        guard isResponsiveYTDLP(at: targetURL, timeout: 8) else {
            try? fileManager.removeItem(at: targetURL)
            if hadExistingTarget {
                try? fileManager.moveItem(at: backupURL, to: targetURL)
            }
            throw NSError(
                domain: "LapianBao.YTDLP",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "新 yt-dlp 无法启动，已恢复旧版本"]
            )
        }

        if hadExistingTarget {
            try? fileManager.removeItem(at: backupURL)
        }
    }

    nonisolated static func installAppManagedNightlyYTDLP(
        using curl: URL,
        deadline: Date? = nil,
        downloadTimeout requestedDownloadTimeout: TimeInterval = 105,
        latestRelease: YTDLPNightlyRelease? = nil,
        progressHandler: (@Sendable (Double, String) -> Void)? = nil
    ) -> DownloaderSelfCheckProcessResult {
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

        let resolvedDownloadURL = latestRelease?.downloadURL ?? downloaderNightlyExecutableURL
        let temporaryURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent("\(downloaderTemporaryYTDLPPrefix)\(UUID().uuidString)")
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
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        var downloadResult: DownloaderSelfCheckProcessResult?
        let proxyAttempts: [String?] = currentYTDLPProxyURLs().map(Optional.some) + [nil]
        let segmentWidth = 0.17 / Double(max(proxyAttempts.count, 1))
        for (index, proxyURL) in proxyAttempts.enumerated() {
            guard let downloadTimeout = downloaderSelfCheckTimeout(
                requested: requestedDownloadTimeout,
                deadline: deadline,
                reserve: 10
            ), downloadTimeout >= 8 else {
                break
            }
            try? FileManager.default.removeItem(at: temporaryURL)
            let routeLabel = proxyURL == nil ? "直连" : "系统代理"
            let progressBase = 0.54 + segmentWidth * Double(index)
            progressHandler?(progressBase, "步骤 2/2：正在通过\(routeLabel)下载最新 yt-dlp")
            let curlMaxTime = max(6, downloadTimeout - 2)
            var arguments = [
                "-L",
                "--fail",
                "--silent",
                "--show-error",
                "--retry", "1",
                "--connect-timeout", String(Int(min(8, max(3, curlMaxTime / 3)))),
                "--max-time", String(Int(curlMaxTime)),
                "-o", temporaryURL.path
            ]
            if let proxyURL {
                arguments += ["--proxy", proxyURL]
            }
            arguments.append(resolvedDownloadURL)

            let result = runDownloaderSelfCheckProcess(
                executableURL: curl,
                arguments: arguments,
                timeout: downloadTimeout,
                progressTick: { elapsed in
                    let elapsedProgress = min(0.88, elapsed / downloadTimeout)
                    let progress = progressBase + segmentWidth * elapsedProgress
                    progressHandler?(
                        progress,
                        "步骤 2/2：正在通过\(routeLabel)下载最新 yt-dlp（\(Int(elapsed.rounded())) 秒）"
                    )
                }
            )
            downloadResult = result
            if result.succeeded {
                progressHandler?(0.72, "步骤 2/2：最新 yt-dlp 下载完成，正在安装")
                break
            }
        }
        guard let downloadResult else {
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 1,
                didTimeOut: false,
                output: "",
                errorOutput: "剩余时间不足，未启动 yt-dlp 下载"
            )
        }
        guard downloadResult.succeeded else { return downloadResult }

        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporaryURL.path)
            if let digest = latestRelease?.digest,
               !verifySHA256Digest(digest, for: temporaryURL) {
                return DownloaderSelfCheckProcessResult(
                    terminationStatus: 1,
                    didTimeOut: false,
                    output: "",
                    errorOutput: "下载文件 SHA256 校验失败"
                )
            }
            guard isResponsiveYTDLP(at: temporaryURL, timeout: 8) else {
                return DownloaderSelfCheckProcessResult(
                    terminationStatus: 1,
                    didTimeOut: false,
                    output: "",
                    errorOutput: "下载到的 yt-dlp 无法启动，已保留旧版本"
                )
            }
            if let expectedVersion = latestRelease?.version,
               let downloadedVersion = ytdlpVersion(at: temporaryURL, deadline: deadline),
               isYTDLPVersion(downloadedVersion, olderThan: expectedVersion) {
                return DownloaderSelfCheckProcessResult(
                    terminationStatus: 1,
                    didTimeOut: false,
                    output: "",
                    errorOutput: "下载到的 yt-dlp 版本过旧：\(downloadedVersion)，期望 \(expectedVersion)"
                )
            }
            try replaceAppManagedYTDLP(at: targetURL, with: temporaryURL)
            guard isResponsiveYTDLP(at: targetURL, timeout: 8) else {
                try? FileManager.default.removeItem(at: targetURL)
                return DownloaderSelfCheckProcessResult(
                    terminationStatus: 1,
                    didTimeOut: false,
                    output: "",
                    errorOutput: "应用内 yt-dlp 安装后无法启动"
                )
            }
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 0,
                didTimeOut: false,
                output: "已安装到 \(targetURL.path)",
                errorOutput: ""
            )
        } catch {
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 1,
                didTimeOut: false,
                output: "",
                errorOutput: error.localizedDescription
            )
        }
    }

    nonisolated static func ytdlpLaunchFailureMessage(_ error: Error, executableURL: URL) -> String {
        let path = executableURL.path
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            return "yt-dlp 启动失败：下载器文件不存在（\(path)）。请在设置里重新运行 YTDLP 自检。"
        }
        if !fileManager.isExecutableFile(atPath: path) {
            return "yt-dlp 启动失败：下载器没有执行权限（\(path)）。请在设置里重新运行 YTDLP 自检。"
        }
        return "yt-dlp 启动失败：\(error.localizedDescription)。下载器路径：\(path)。请在设置里重新运行 YTDLP 自检。"
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

    nonisolated static func runDownloaderSelfCheckProcess(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        progressTick: (@Sendable (TimeInterval) -> Void)? = nil
    ) -> DownloaderSelfCheckProcessResult {
        let result = ExternalProcessRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            environment: downloaderProcessEnvironment(),
            timeout: timeout,
            progressTick: progressTick
        )
        return DownloaderSelfCheckProcessResult(
            terminationStatus: result.terminationStatus,
            didTimeOut: result.didTimeOut,
            output: result.outputText,
            errorOutput: result.errorText
        )
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
