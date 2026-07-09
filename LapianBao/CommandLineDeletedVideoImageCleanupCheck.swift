//
//  CommandLineDeletedVideoImageCleanupCheck.swift
//  LapianBao
//

import Darwin
import Foundation

enum CommandLineDeletedVideoImageCleanupCheck {
    nonisolated static let flag = "--lapianbao-deleted-video-image-cleanup-check"

    nonisolated struct Report: Codable {
        var status = "failed"
        var appDeleteRemovedVideoFile = false
        var appDeleteRemovedImageFile = false
        var appDeleteRemovedFrameRecord = false
        var missingVideoLoadRemovedImageFile = false
        var missingVideoLoadRemovedFrameRecord = false
        var failures: [String] = []
    }

    nonisolated static func runIfRequested() {
        guard CommandLine.arguments.contains(flag) else { return }

        let report = MainActor.assumeIsolated {
            runCheck()
        }
        write(report)
        Darwin.exit(report.status == "succeeded" ? 0 : 1)
    }

    @MainActor
    private static func runCheck() -> Report {
        var report = Report()
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("LapianBaoDeletedVideoImageCleanupCheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try runAppDeleteCheck(rootURL: rootURL.appendingPathComponent("AppDelete", isDirectory: true), report: &report)
            try runMissingVideoLoadCheck(
                rootURL: rootURL.appendingPathComponent("MissingVideoLoad", isDirectory: true),
                report: &report
            )
        } catch {
            report.failures.append(error.localizedDescription)
        }

        report.status = report.failures.isEmpty ? "succeeded" : "failed"
        return report
    }

    @MainActor
    private static func runAppDeleteCheck(rootURL: URL, report: inout Report) throws {
        let fileManager = FileManager.default
        let videoURL = rootURL.appendingPathComponent("Videos", isDirectory: true)
            .appendingPathComponent("deleted-video.mp4")
        let imageURL = rootURL.appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent("deleted-video_00-00-01-000.jpg")
        try writePlaceholderFile(at: videoURL)
        try writePlaceholderFile(at: imageURL)

        let video = VideoItem(url: videoURL)
        let store = LibraryStore()
        store.libraryURL = rootURL
        store.videos = [video]
        store.sampledFrames = [
            makeFrame(videoURL: videoURL, imageURL: imageURL, videoName: video.name)
        ]

        store.removeVideo(video)
        store.projectSaveTask?.cancel()
        store.videoLibrarySnapshotSaveTask?.cancel()

        report.appDeleteRemovedVideoFile = !fileManager.fileExists(atPath: videoURL.path)
        report.appDeleteRemovedImageFile = !fileManager.fileExists(atPath: imageURL.path)
        report.appDeleteRemovedFrameRecord = store.sampledFrames.isEmpty

        appendFailure(
            report.appDeleteRemovedVideoFile,
            "deleting a video from the app must remove the original video file from its library path",
            to: &report
        )
        appendFailure(
            report.appDeleteRemovedImageFile,
            "deleting a video from the app must remove generated image exports from their original paths",
            to: &report
        )
        appendFailure(
            report.appDeleteRemovedFrameRecord,
            "deleting a video from the app must remove sampled-frame records for that video",
            to: &report
        )
    }

    @MainActor
    private static func runMissingVideoLoadCheck(rootURL: URL, report: inout Report) throws {
        let fileManager = FileManager.default
        let missingVideoURL = rootURL.appendingPathComponent("Videos", isDirectory: true)
            .appendingPathComponent("missing-video.mp4")
        let imageURL = rootURL.appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent("missing-video_00-00-02-000.jpg")
        try writePlaceholderFile(at: imageURL)

        let store = LibraryStore()
        store.libraryURL = rootURL
        store.videos = []
        store.applyProjectData(ProjectDataFile(
            sampledFrames: [
                makeFrame(videoURL: missingVideoURL, imageURL: imageURL, videoName: "missing-video", time: 2)
            ],
            annotations: [],
            audioClips: [],
            transcripts: [:],
            transcriptExports: nil,
            musicsByVideoPath: nil,
            musicDownloadJobs: nil
        ))
        store.projectSaveTask?.cancel()

        report.missingVideoLoadRemovedImageFile = !fileManager.fileExists(atPath: imageURL.path)
        report.missingVideoLoadRemovedFrameRecord = store.sampledFrames.isEmpty

        appendFailure(
            report.missingVideoLoadRemovedImageFile,
            "loading project data after a video disappears must remove orphan generated image exports",
            to: &report
        )
        appendFailure(
            report.missingVideoLoadRemovedFrameRecord,
            "loading project data after a video disappears must prune orphan sampled-frame records",
            to: &report
        )
    }

    private nonisolated static func makeFrame(
        videoURL: URL,
        imageURL: URL,
        videoName: String,
        time: Double = 1
    ) -> SampledFrame {
        SampledFrame(
            videoPath: videoURL.path,
            videoName: videoName,
            time: time,
            sceneIndex: nil,
            kind: .screenshot,
            isExported: true,
            filePath: imageURL.path,
            note: "",
            tags: [],
            thumbnailData: Data([0xff, 0xd8, 0xff, 0xd9])
        )
    }

    private nonisolated static func writePlaceholderFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0, 1, 2, 3]).write(to: url, options: .atomic)
    }

    private nonisolated static func appendFailure(_ condition: Bool, _ message: String, to report: inout Report) {
        if !condition {
            report.failures.append(message)
        }
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
