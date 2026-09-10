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
    nonisolated static let downloaderYTDLPQuickCheckTimeout: TimeInterval = 6

    nonisolated static func localYTDLPURL() -> URL? {
        // Synchronous worker-only compatibility entry; async callers use shared readiness.
        localYTDLPInfo()?.url
    }

    nonisolated static func localYTDLPInfo(
        timeout: TimeInterval = downloaderYTDLPQuickCheckTimeout
    ) -> (url: URL, version: String?)? {
        guard YTDLPRuntime.dependenciesOperational(timeout: timeout) else { return nil }
        for path in localYTDLPCandidatePaths() {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)
            let versionResult = YTDLPRuntime.run(
                archive: url,
                arguments: ["--version"],
                timeout: timeout
            )
            guard versionResult.succeeded,
                  isOperationalYTDLP(at: url, timeout: timeout)
            else { continue }
            return (url, firstNonEmptyLine(in: versionResult.outputText))
        }
        return nil
    }

    nonisolated static func localYTDLPCandidatePaths() -> [String] {
        var paths = [YTDLPRuntime.archiveURL.path]
        // Old first-use downloads have no verified receipt and are deliberately ignored.
        if let managed = appManagedYTDLPURL(),
           let receipt = YTDLPRuntime.verifiedUpdate(at: managed),
           let bundledVersion = ytdlpVersion(at: YTDLPRuntime.archiveURL),
           isYTDLPVersion(bundledVersion, olderThan: receipt.version) {
            paths.insert(managed.path, at: 0)
        }
        return paths
    }

    nonisolated static func isResponsiveYTDLP(at url: URL, timeout: TimeInterval = 5) -> Bool {
        let versionResult = YTDLPRuntime.run(
            archive: url,
            arguments: ["--version"],
            timeout: timeout
        )
        guard versionResult.succeeded else { return false }
        return isOperationalYTDLP(at: url, timeout: timeout)
    }

    nonisolated static func isOperationalYTDLP(at url: URL, timeout: TimeInterval = 5) -> Bool {
        let archiveCheck = ExternalProcessRunner.run(
            executableURL: YTDLPRuntime.pythonURL,
            arguments: ["-I", "-B", "-c", "import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert any(n.startswith('yt_dlp_ejs/') and n.endswith('.js') for n in z.namelist()), 'EJS missing'", url.path],
            environment: YTDLPRuntime.environment,
            timeout: timeout
        )
        guard archiveCheck.succeeded else { return false }
        return YTDLPRuntime.run(
            archive: url,
            arguments: ["--help"],
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
        case checkLatestAndRepair
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
            guard !steps.isEmpty else { return L10n.text("未找到可自动更新渠道") }
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
            guard let asset = assets.first(where: { $0.name == "yt-dlp" }),
                  asset.digest.flatMap(LibraryStore.normalizedSHA256Digest) != nil
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

            let deadline: Date? = downloaderSelfCheckDeadline(startedAt: startedAt)
            publish(0.04, L10n.text("正在检查 yt-dlp 可用性"))
            let currentYTDLPInfo = await DownloaderReadiness.shared.ready()
            let currentYTDLP = currentYTDLPInfo?.url
            let currentVersion = currentYTDLPInfo?.version

            if repairMode == .afterFailure {
                let versionText = currentVersion ?? L10n.text("未知版本")
                publish(1.0, L10n.text("yt-dlp 可用"))
                let report = DownloaderSelfCheckReport(
                    status: currentYTDLP == nil ? .failed : .succeeded,
                    checkedAt: startedAt,
                    message: currentYTDLP == nil ? YTDLPRuntime.unavailableMessage : L10n.text("内置下载运行环境可用：\(versionText)（未验证平台下载）"),
                    ytdlpPath: currentYTDLP?.path,
                    ytdlpVersion: currentVersion,
                    repairSummary: L10n.text("仅检查本地运行环境；未执行联网安装或平台下载"),
                    progress: 1
                )
                return reportByAddingDownloaderSelfCheckItems(to: report)
            }

            guard let curl = localCurlURL() else {
                var report = DownloaderSelfCheckReport(
                    status: currentYTDLP == nil ? .failed : .succeeded,
                    checkedAt: startedAt,
                    message: currentYTDLP == nil
                        ? L10n.text("无法检查最新版：未找到 curl，也未找到可用 yt-dlp")
                        : L10n.text("无法检查最新版：未找到 curl；当前 yt-dlp 可用"),
                    ytdlpPath: currentYTDLP?.path,
                    ytdlpVersion: currentVersion,
                    problemLocation: currentYTDLP == nil ? downloaderProblemYTDLP : nil,
                    progress: 1
                )
                report.repairSummary = L10n.text("未找到 curl，无法连接 GitHub 获取最新版")
                publish(1.0, L10n.text("步骤 1/2：yt-dlp 最新版检查结束"))
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
                    fallback: L10n.text("无法读取 GitHub 最新版本")
                )
                let report = DownloaderSelfCheckReport(
                    status: currentYTDLP == nil ? .failed : .succeeded,
                    checkedAt: startedAt,
                    message: currentYTDLP == nil
                        ? L10n.text("无法检查或安装最新版 yt-dlp：\(singleLineRepairMessage(failure))")
                        : L10n.text("最新版检查未完成；当前 yt-dlp 可用：\(currentVersion ?? L10n.text("未知版本"))"),
                    ytdlpPath: currentYTDLP?.path,
                    ytdlpVersion: currentVersion,
                    problemLocation: currentYTDLP == nil ? downloaderProblemYTDLP : nil,
                    repairSummary: singleLineRepairMessage(failure),
                    progress: 1
                )
                publish(1.0, L10n.text("步骤 1/2：yt-dlp 最新版检查结束"))
                return reportByAddingDownloaderSelfCheckItems(to: report)
            }

            let isOutdated = currentVersion.map {
                isYTDLPVersion($0, olderThan: latestRelease.version)
            } ?? true
            let shouldDownload = repairMode == .always || isOutdated
            let currentText = currentVersion ?? L10n.text("未安装")
            publish(
                0.32,
                L10n.text("步骤 1/2：最新版 \(latestRelease.version)，当前 \(currentText)")
            )

            guard shouldDownload else {
                publish(1.0, L10n.text("步骤 2/2：yt-dlp 已是最新版"))
                let report = DownloaderSelfCheckReport(
                    status: .succeeded,
                    checkedAt: startedAt,
                    message: L10n.text("yt-dlp 已是最新版：\(latestRelease.version)"),
                    ytdlpPath: currentYTDLP?.path,
                    ytdlpVersion: currentVersion,
                    repairSummary: L10n.text("上游最新版 \(latestRelease.version)，无需替换"),
                    progress: 1
                )
                return reportByAddingDownloaderSelfCheckItems(to: report)
            }

            publish(0.44, L10n.text("步骤 2/2：正在下载最新 yt-dlp"))
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

            publish(1.0, L10n.text("步骤 2/2：yt-dlp 更新检查完成"))
            let message: String
            let repairWasBlocked = repairResult.steps.contains {
                $0.contains("已有自检或修复正在运行")
            }
            if installSucceeded, repairWasBlocked {
                message = L10n.text("已有 yt-dlp 自检或修复正在运行；当前 yt-dlp 可用：\(installedVersion ?? currentVersion ?? L10n.text("未知版本"))")
            } else if installSucceeded {
                message = L10n.text("yt-dlp 已更新到最新版：\(installedVersion ?? latestRelease.version)")
            } else {
                message = currentYTDLP == nil
                    ? L10n.text("yt-dlp 最新版安装失败：\(repairResult.summary)")
                    : L10n.text("yt-dlp 最新版替换未完成；当前版本仍可用：\(currentVersion ?? L10n.text("未知版本"))")
            }
            let report = DownloaderSelfCheckReport(
                status: installSucceeded || (repairMode == .afterFailure && currentYTDLP != nil) ? .succeeded : .failed,
                checkedAt: startedAt,
                message: message,
                ytdlpPath: installSucceeded ? managedYTDLP?.path : currentYTDLP?.path,
                ytdlpVersion: installSucceeded ? installedVersion : currentVersion,
                problemLocation: installSucceeded || (repairMode == .afterFailure && currentYTDLP != nil) ? nil : downloaderProblemYTDLP,
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
            enriched.message = L10n.text("下载器自检发现 \(failures.count) 项异常：\(summary)")
        } else if enriched.status == .idle || enriched.status == .running {
            enriched.status = .succeeded
            enriched.problemLocation = nil
            if enriched.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || enriched.message == "未自检" {
                enriched.message = L10n.text("yt-dlp 自检通过")
            }
        }

        return enriched
    }

    nonisolated static func ytdlpServiceSelfCheckItem(from report: DownloaderSelfCheckReport) -> ExternalServiceSelfCheckItem {
        if let path = report.ytdlpPath {
            let version = report.ytdlpVersion.map { " · \($0)" } ?? ""
            return ExternalServiceSelfCheckItem(
                key: "ytdlp",
                title: L10n.text("yt-dlp 下载器"),
                status: .succeeded,
                message: "\(path)\(version)"
            )
        }
        return ExternalServiceSelfCheckItem(
            key: "ytdlp",
            title: L10n.text("yt-dlp 下载器"),
            status: .failed,
            message: YTDLPRuntime.unavailableMessage
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
            errorOutput: L10n.text("未启动 GitHub 最新版本检查")
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

            let routeLabel = proxyURL == nil ? L10n.text("直连") : L10n.text("系统代理")
            let progressBase = 0.06 + segmentWidth * Double(index)
            progressHandler?(progressBase, L10n.text("步骤 1/2：正在通过\(routeLabel)检查 yt-dlp 最新版本"))

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
                        L10n.text("步骤 1/2：正在通过\(routeLabel)检查 yt-dlp 最新版本（\(Int(elapsed.rounded())) 秒）")
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
                    errorOutput: L10n.text("GitHub 最新版本响应缺少 yt-dlp")
                )
                continue
            }

            progressHandler?(0.31, L10n.text("步骤 1/2：发现 yt-dlp 最新版 \(release.version)"))
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
                name: L10n.text("清理 yt-dlp 临时文件"),
                commandResult: artifactCleanupResult,
                to: &result
            )
        }

        guard let curl = localCurlURL() else {
            result.steps.append(L10n.text("更新应用托管 yt-dlp 未完成：未找到 curl"))
            return
        }

        appendDownloaderRepairStep(
            name: L10n.text("更新应用托管 yt-dlp nightly"),
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
            output: removedNames.isEmpty ? "" : L10n.text("已清理 \(removedNames.joined(separator: "、"))"),
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
                output: L10n.text("已移除 \(targetURL.path)"),
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
            result.steps.append(L10n.text("\(name)完成"))
        } else {
            let message = selfCheckFailureMessage(from: commandResult, fallback: L10n.text("失败"))
            result.steps.append(L10n.text("\(name)未完成：\(singleLineRepairMessage(message))"))
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
        let result = YTDLPRuntime.run(
            archive: url,
            arguments: ["--version"],
            timeout: timeout
        )
        guard result.succeeded else { return nil }
        return firstNonEmptyLine(in: result.outputText)
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
        guard let expected = normalizedSHA256Digest(digest) else { return false }
        return YTDLPRuntime.digest(fileURL) == expected
    }

    nonisolated static func replaceAppManagedYTDLP(at targetURL: URL, with temporaryURL: URL) throws {
        let fileManager = FileManager.default
        let backupURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent("\(downloaderBackupYTDLPPrefix)\(UUID().uuidString)")
        let hadExistingTarget = fileManager.fileExists(atPath: targetURL.path)

        guard isResponsiveYTDLP(at: temporaryURL, timeout: 8) else {
            throw NSError(domain: "LapianBao.YTDLP", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L10n.text("新 yt-dlp 校验失败，旧版本未改动")])
        }
        if hadExistingTarget {
            // Copy the backup: moving the live file away creates a reader-visible gap.
            try fileManager.copyItem(at: targetURL, to: backupURL)
        }

        // Same-directory POSIX rename replaces the live inode atomically. Readers
        // that already opened the old archive can finish using their existing FD.
        guard Darwin.rename(temporaryURL.path, targetURL.path) == 0 else {
            let failure = errno
            try? fileManager.removeItem(at: backupURL)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }

        guard isResponsiveYTDLP(at: targetURL, timeout: 8) else {
            if hadExistingTarget {
                guard Darwin.rename(backupURL.path, targetURL.path) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                                  userInfo: [NSLocalizedDescriptionKey: L10n.text("更新回滚失败；内置下载器仍保留，备份路径：\(backupURL.path)")])
                }
            } else {
                try? fileManager.removeItem(at: targetURL)
            }
            throw NSError(
                domain: "LapianBao.YTDLP",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: L10n.text("新 yt-dlp 无法启动，已恢复旧版本")]
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
                errorOutput: L10n.text("无法创建应用工具目录")
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
            let routeLabel = proxyURL == nil ? L10n.text("直连") : L10n.text("系统代理")
            let progressBase = 0.54 + segmentWidth * Double(index)
            progressHandler?(progressBase, L10n.text("步骤 2/2：正在通过\(routeLabel)下载最新 yt-dlp"))
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
                        L10n.text("步骤 2/2：正在通过\(routeLabel)下载最新 yt-dlp（\(Int(elapsed.rounded())) 秒）")
                    )
                }
            )
            downloadResult = result
            if result.succeeded {
                progressHandler?(0.72, L10n.text("步骤 2/2：最新 yt-dlp 下载完成，正在安装"))
                break
            }
        }
        guard let downloadResult else {
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 1,
                didTimeOut: false,
                output: "",
                errorOutput: L10n.text("剩余时间不足，未启动 yt-dlp 下载")
            )
        }
        guard downloadResult.succeeded else { return downloadResult }

        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporaryURL.path)
            guard let digest = latestRelease?.digest,
                  verifySHA256Digest(digest, for: temporaryURL) else {
                return DownloaderSelfCheckProcessResult(
                    terminationStatus: 1,
                    didTimeOut: false,
                    output: "",
                    errorOutput: L10n.text("下载文件 SHA256 校验失败")
                )
            }
            guard isResponsiveYTDLP(at: temporaryURL, timeout: 8) else {
                return DownloaderSelfCheckProcessResult(
                    terminationStatus: 1,
                    didTimeOut: false,
                    output: "",
                    errorOutput: L10n.text("下载到的 yt-dlp 无法启动，已保留旧版本")
                )
            }
            if let expectedVersion = latestRelease?.version,
               let downloadedVersion = ytdlpVersion(at: temporaryURL, deadline: deadline),
               isYTDLPVersion(downloadedVersion, olderThan: expectedVersion) {
                return DownloaderSelfCheckProcessResult(
                    terminationStatus: 1,
                    didTimeOut: false,
                    output: "",
                    errorOutput: L10n.text("下载到的 yt-dlp 版本过旧：\(downloadedVersion)，期望 \(expectedVersion)")
                )
            }
            try replaceAppManagedYTDLP(at: targetURL, with: temporaryURL)
            guard isResponsiveYTDLP(at: targetURL, timeout: 8) else {
                try? FileManager.default.removeItem(at: targetURL)
                return DownloaderSelfCheckProcessResult(
                    terminationStatus: 1,
                    didTimeOut: false,
                    output: "",
                    errorOutput: L10n.text("应用内 yt-dlp 安装后无法启动")
                )
            }
            let receipt = YTDLPRuntime.UpdateReceipt(version: latestRelease!.version, sha256: normalizedSHA256Digest(digest)!)
            try JSONEncoder().encode(receipt).write(to: YTDLPRuntime.receiptURL(for: targetURL), options: .atomic)
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 0,
                didTimeOut: false,
                output: L10n.text("已安装到 \(targetURL.path)"),
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
            return L10n.text("yt-dlp 启动失败：下载器文件不存在（\(path)）。请在设置里重新运行 YTDLP 自检。")
        }
        if !fileManager.isExecutableFile(atPath: path) {
            return L10n.text("yt-dlp 启动失败：下载器没有执行权限（\(path)）。请在设置里重新运行 YTDLP 自检。")
        }
        return L10n.text("yt-dlp 启动失败：\(error.localizedDescription)。下载器路径：\(path)。请在设置里重新运行 YTDLP 自检。")
    }

    nonisolated static func ytdlpPythonURL() -> URL? {
        FileManager.default.isExecutableFile(atPath: YTDLPRuntime.pythonURL.path) ? YTDLPRuntime.pythonURL : nil
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
        if result.didTimeOut { return L10n.text("超时") }
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
