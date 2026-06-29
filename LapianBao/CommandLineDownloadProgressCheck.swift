//
//  CommandLineDownloadProgressCheck.swift
//  LapianBao
//

import Darwin
import Foundation

enum CommandLineDownloadProgressCheck {
    nonisolated static let flag = "--lapianbao-download-progress-check"

    nonisolated struct Report: Codable {
        var status: String
        var singlePartHalfProgress: Double?
        var singlePartFullProgress: Double?
        var structuredByteHalfProgress: Double?
        var liveDownloadFullProgress: Double?
        var livePostProcessingProgress: Double?
        var multipartWithoutSizesFirstPartProgress: Double?
        var multipartKnownSizesFirstPartProgress: Double?
        var multipartObservedSizesSecondPartProgress: Double?
        var postProcessingProgress: Double?
        var failures: [String]
    }

    nonisolated static func runIfRequested() {
        guard CommandLine.arguments.contains(flag) else { return }

        let report = runCheck()
        write(report)
        Darwin.exit(report.status == "succeeded" ? 0 : 1)
    }

    private nonisolated static func runCheck() -> Report {
        var failures: [String] = []

        let singlePartTracker = LibraryStore.YTDLPProgressTracker(
            expectedPartCount: 1,
            allowsEstimatedMultipartProgress: false,
            reportsPostProcessingProgress: false
        )
        let singlePartHalfProgress = singlePartTracker.update(
            from: "[download]  50.0% of 10.00MiB at 1.00MiB/s ETA 00:05"
        )?.progress
        let singlePartFullProgress = singlePartTracker.update(
            from: "[download] 100.0% of 10.00MiB at 1.00MiB/s ETA 00:00"
        )?.progress
        let postProcessingProgress = singlePartTracker.update(
            from: "[Merger] Merging formats into \"video.mp4\""
        )?.progress

        if !approximatelyEqual(singlePartHalfProgress, 0.5) {
            failures.append("single part 50% must stay 50%")
        }
        if !approximatelyEqual(singlePartFullProgress, 1.0) {
            failures.append("single part 100% must stay 100%")
        }
        if postProcessingProgress != nil {
            failures.append("post-processing lines must not invent download progress")
        }

        let structuredByteHalfProgress = LibraryStore.parseYTDLPProgressUpdate(
            "lapianbao-progress downloaded=5242880 total=10485760 total_estimate=NA speed=1048576"
        )?.progress
        if !approximatelyEqual(structuredByteHalfProgress, 0.5) {
            failures.append("structured yt-dlp byte progress must use downloaded_bytes / total_bytes")
        }

        let liveDownloadTracker = LibraryStore.YTDLPProgressTracker(
            expectedPartCount: 1,
            downloadCompletionProgress: 0.96,
            postProcessingProgress: 0.98,
            allowsEstimatedMultipartProgress: false,
            reportsPostProcessingProgress: true
        )
        let liveDownloadFullProgress = liveDownloadTracker.update(
            from: "lapianbao-progress downloaded=10485760 total=10485760 total_estimate=NA speed=1048576"
        )?.progress
        let livePostProcessingProgress = liveDownloadTracker.update(
            from: "[Merger] Merging formats into \"video.mp4\""
        )?.progress
        if !approximatelyEqual(liveDownloadFullProgress, 0.96) {
            failures.append("live yt-dlp download completion must stop below final imported 100%")
        }
        if !approximatelyEqual(livePostProcessingProgress, 0.98) {
            failures.append("yt-dlp post-processing must advance to 98%, not 100%")
        }

        let multipartWithoutSizesTracker = LibraryStore.YTDLPProgressTracker(
            expectedPartCount: 2,
            allowsEstimatedMultipartProgress: false,
            reportsPostProcessingProgress: false
        )
        let multipartWithoutSizesFirstPartProgress = multipartWithoutSizesTracker.update(
            from: "[download] 100.0% of 8.00MiB at 2.00MiB/s ETA 00:00"
        )?.progress

        if multipartWithoutSizesFirstPartProgress != nil {
            failures.append("multipart downloads without known sizes must not jump to 50%")
        }

        let multipartKnownSizesTracker = LibraryStore.YTDLPProgressTracker(
            expectedPartCount: 2,
            expectedPartByteCounts: [10_000_000, 90_000_000],
            allowsEstimatedMultipartProgress: false,
            reportsPostProcessingProgress: false
        )
        let multipartKnownSizesFirstPartProgress = multipartKnownSizesTracker.update(
            from: "[download] 100.0% at 2.00MiB/s ETA 00:00"
        )?.progress

        if !approximatelyEqual(multipartKnownSizesFirstPartProgress, 0.1) {
            failures.append("multipart downloads with known sizes must use byte-weighted progress")
        }

        let multipartObservedSizesTracker = LibraryStore.YTDLPProgressTracker(
            expectedPartCount: 2,
            allowsEstimatedMultipartProgress: false,
            reportsPostProcessingProgress: false
        )
        _ = multipartObservedSizesTracker.update(
            from: "[download] 100.0% of 10.00MiB at 2.00MiB/s ETA 00:00"
        )
        let multipartObservedSizesSecondPartProgress = multipartObservedSizesTracker.update(
            from: "[download]  20.0% of 90.00MiB at 1.00MiB/s ETA 00:02"
        )?.progress

        if !approximatelyEqual(multipartObservedSizesSecondPartProgress, 0.28) {
            failures.append("multipart downloads must use observed yt-dlp part sizes once they are available")
        }

        return Report(
            status: failures.isEmpty ? "succeeded" : "failed",
            singlePartHalfProgress: singlePartHalfProgress,
            singlePartFullProgress: singlePartFullProgress,
            structuredByteHalfProgress: structuredByteHalfProgress,
            liveDownloadFullProgress: liveDownloadFullProgress,
            livePostProcessingProgress: livePostProcessingProgress,
            multipartWithoutSizesFirstPartProgress: multipartWithoutSizesFirstPartProgress,
            multipartKnownSizesFirstPartProgress: multipartKnownSizesFirstPartProgress,
            multipartObservedSizesSecondPartProgress: multipartObservedSizesSecondPartProgress,
            postProcessingProgress: postProcessingProgress,
            failures: failures
        )
    }

    private nonisolated static func approximatelyEqual(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.0001
    }

    private nonisolated static func write(_ report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}
