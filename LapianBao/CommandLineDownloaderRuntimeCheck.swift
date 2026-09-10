import Darwin
import Foundation

/// Executable acceptance checks exercise the shipped runtime and real download entry point.
enum CommandLineDownloaderRuntimeCheck {
    nonisolated static let flag = "--lapianbao-downloader-runtime-check"

    nonisolated static func runIfRequested() {
        guard CommandLine.arguments.contains(flag) else { return }
        Task { @MainActor in
            let report = await run()
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Darwin.exit(report["status"] as? String == "passed" ? 0 : 1)
        }
        dispatchMain()
    }

    @MainActor private static func run() async -> [String: Any] {
        var failures: [String] = []
        var lastBeat = Date()
        var maximumGap: TimeInterval = 0
        var beats = 0
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
                let now = Date()
                maximumGap = max(maximumGap, now.timeIntervalSince(lastBeat))
                lastBeat = now
                beats += 1
            }
        }
        let runtimeURLs = await withTaskGroup(of: URL?.self, returning: [URL?].self) { group in
            for _ in 0..<6 { group.addTask { await LibraryStore.readyYTDLPURL() } }
            var results: [URL?] = []
            for await result in group { results.append(result) }
            return results
        }
        if runtimeURLs.count != 6 || runtimeURLs.contains(where: { $0 == nil }) {
            failures.append("Concurrent readiness did not return six usable runtimes")
        }
        if Set(runtimeURLs.compactMap { $0?.path }).count != 1 {
            failures.append("Concurrent callers selected different runtimes")
        }
        let validationRuns = await DownloaderReadiness.shared.validationRuns
        if validationRuns != 1 { failures.append("Cold readiness ran \(validationRuns) times instead of once") }

        var publications = 0
        var lastProgress: Double?
        let coalescer = DownloadProgressCoalescer { progress, _ in
            publications += 1
            lastProgress = progress
        }
        for i in 0..<1000 { coalescer.submit(Double(i) / 1000, nil) }
        coalescer.submit(1, nil)
        try? await Task.sleep(for: .milliseconds(150))
        if publications > 2 || lastProgress != 1 { failures.append("Progress burst not coalesced or final value lost") }

        let timeout = await Task.detached {
            ExternalProcessRunner.run(executableURL: YTDLPRuntime.pythonURL,
                                      arguments: ["-I", "-B", "-c", "import time,signal; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)"],
                                      environment: YTDLPRuntime.environment, timeout: 0.3)
        }.value
        if !timeout.didTimeOut { failures.append("Unresponsive subprocess was not timed out") }
        let updaterChecks = await CommandLineDownloaderUpdateCheck.run()
        for (name, passed) in updaterChecks where !passed { failures.append("Updater: \(name)") }

        var downloadedPath: String?
        let args = CommandLine.arguments
        if let sourceIndex = args.firstIndex(of: "--source"), args.indices.contains(sourceIndex + 1),
           let destinationIndex = args.firstIndex(of: "--destination"), args.indices.contains(destinationIndex + 1),
           let source = URL(string: args[sourceIndex + 1]) {
            do {
                let result = try await LibraryStore.downloadVideo(
                    from: source, into: URL(fileURLWithPath: args[destinationIndex + 1]),
                    platform: LibraryStore.platformName(for: source) ?? "公开媒体", endpoint: ""
                )
                downloadedPath = result.url.path
            } catch {
                failures.append(LibraryStore.downloadRouteFailure(route: "下载验收", error: error))
            }
        }
        heartbeat.cancel()
        if beats == 0 || maximumGap > 0.25 { failures.append("Main actor heartbeat stalled: \(maximumGap)s") }
        var report: [String: Any] = [
            "status": failures.isEmpty ? "passed" : "failed", "failures": failures,
            "scope": "Current host only; not M4 certification", "readinessValidationRuns": validationRuns,
            "runtimePaths": runtimeURLs.compactMap { $0?.path }, "mainActorMaximumGapSeconds": maximumGap,
            "heartbeatCount": beats, "progressPublicationsFor1001Inputs": publications,
            "unresponsiveProcessTimedOut": timeout.didTimeOut
        ]
        report["updaterChecks"] = updaterChecks
        if let downloadedPath { report["downloadedPath"] = downloadedPath }
        return report
    }
}
