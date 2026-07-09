//
//  CommandLineSceneTimelineCheck.swift
//  LapianBao
//
//  Deterministic guard for scene-recognition timeline split state.
//

import AppKit
import Darwin
import Foundation

enum CommandLineSceneTimelineCheck {
    nonisolated static let flag = "--lapianbao-scene-timeline-check"
    nonisolated static let cacheRestoreFlag = "--lapianbao-scene-cache-restore-check"

    nonisolated static func runIfRequested() {
        if CommandLine.arguments.contains(cacheRestoreFlag) {
            runSceneCacheRestoreCheck()
        }
        guard CommandLine.arguments.contains(flag) else { return }

        let stableCutTimes = LibraryStore.stableSceneCutTimes(from: [0, 0.0004, 2.0, 2.1, 6.0])
        let progresses = LibraryStore.normalizedSceneCutProgresses(from: stableCutTimes, duration: 10.0)
        let zeroBoundaryFiltered = stableCutTimes == [2.0, 6.0]
        let progressGenerated = progresses.count == 2
            && abs(progresses[0] - 0.2) < 0.0001
            && abs(progresses[1] - 0.6) < 0.0001
        let splitTimelineUsesFrameFallback = FrameScrubberSceneTimelineResolver.canRenderSplitTimeline(
            sceneCutCount: progresses.count,
            sceneImageCount: nil,
            frameImageCount: 16
        )
        let splitTimelineDoesNotRequireExactSceneImages = FrameScrubberSceneTimelineResolver.canRenderSplitTimeline(
            sceneCutCount: progresses.count,
            sceneImageCount: 1,
            frameImageCount: 16
        )
        let openingSpan = SceneTimelineOpeningZoomPolicy.viewportSpan(
            cutProgresses: [],
            cutCount: 119,
            visibleSceneLimit: 15,
            maxZoom: 240
        )
        let openingZoomUsesFifteenSceneWindow = openingSpan.map { abs($0 - 0.125) < 0.0001 } ?? false
        let denseOpeningSpan = SceneTimelineOpeningZoomPolicy.viewportSpan(
            cutProgresses: [],
            cutCount: 5_000,
            visibleSceneLimit: 15,
            maxZoom: 240
        )
        let denseTimelineUsesMaxZoom = denseOpeningSpan.map {
            abs($0 - (1 / 240)) < 0.0001
        } ?? false
        let clusteredProgresses = (1...30).map { Double($0) * 0.002 }
        let clusteredOpeningSpan = SceneTimelineOpeningZoomPolicy.viewportSpan(
            cutProgresses: clusteredProgresses,
            cutCount: 119,
            visibleSceneLimit: 15,
            maxZoom: 240
        )
        let clusteredTimelineUsesActualSceneBoundary = clusteredOpeningSpan.map {
            abs($0 - 0.03) < 0.0001
        } ?? false
        let emptyCutsDoNotSplit = !FrameScrubberSceneTimelineResolver.canRenderSplitTimeline(
            sceneCutCount: 0,
            sceneImageCount: 16,
            frameImageCount: 16
        )
        let sceneRepresentativeDragUsesPreviewFrame = abs(
            LibraryStore.sceneRepresentativeFrameTime(forCutTime: 2.0) - 2.08
        ) < 0.0001
        let succeeded = zeroBoundaryFiltered
            && progressGenerated
            && splitTimelineUsesFrameFallback
            && splitTimelineDoesNotRequireExactSceneImages
            && openingZoomUsesFifteenSceneWindow
            && denseTimelineUsesMaxZoom
            && clusteredTimelineUsesActualSceneBoundary
            && emptyCutsDoNotSplit
            && sceneRepresentativeDragUsesPreviewFrame

        let report = """
        {"status":"\(succeeded ? "succeeded" : "failed")","progresses":\(progresses),"zeroBoundaryFiltered":\(zeroBoundaryFiltered),"splitTimelineUsesFrameFallback":\(splitTimelineUsesFrameFallback),"splitTimelineDoesNotRequireExactSceneImages":\(splitTimelineDoesNotRequireExactSceneImages),"openingZoomUsesFifteenSceneWindow":\(openingZoomUsesFifteenSceneWindow),"denseTimelineUsesMaxZoom":\(denseTimelineUsesMaxZoom),"clusteredTimelineUsesActualSceneBoundary":\(clusteredTimelineUsesActualSceneBoundary),"sceneRepresentativeDragUsesPreviewFrame":\(sceneRepresentativeDragUsesPreviewFrame)}
        """
        FileHandle.standardOutput.write(Data(report.utf8))
        FileHandle.standardOutput.write(Data("\n".utf8))
        Darwin.exit(succeeded ? 0 : 1)
    }

    nonisolated private static func runSceneCacheRestoreCheck() {
        let result = MainActor.assumeIsolated {
            sceneCacheRestoreCheckResult()
        }
        FileHandle.standardOutput.write(Data(result.report.utf8))
        FileHandle.standardOutput.write(Data("\n".utf8))
        Darwin.exit(result.exitCode)
    }

    @MainActor
    private static func sceneCacheRestoreCheckResult() -> (report: String, exitCode: Int32) {
        let fileManager = FileManager.default
        let libraryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LapianBaoSceneCacheRestore-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: libraryURL)
        }

        do {
            let oldRelativePath = "拉片宝视频下载/Relocated.mp4"
            let currentRelativePath = "视频/Relocated.mp4"
            let videoURL = libraryURL.appendingPathComponent(currentRelativePath)
            try fileManager.createDirectory(
                at: videoURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([0, 1, 2, 3, 4, 5]).write(to: videoURL)
            let modifiedAt = Date(timeIntervalSince1970: 1_782_000_000)
            try fileManager.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: videoURL.path)

            let store = LibraryStore()
            store.libraryURL = libraryURL
            guard let signature = store.videoFileSignature(for: videoURL) else {
                throw NSError(domain: "LapianBaoSceneCacheRestoreCheck", code: 1)
            }

            store.sceneCutCache[oldRelativePath] = LibraryStore.SceneCutCacheEntry(
                detectorVersion: "transnetv2+hardcut-rescue@2026-05-24.2",
                videoID: store.stableVideoID(for: oldRelativePath),
                relativePath: oldRelativePath,
                fileSize: signature.fileSize,
                modificationTime: signature.modificationTime,
                duration: 10,
                cutTimes: [2, 6],
                thumbnailData: nil,
                sceneIDs: [0, 1].map { store.sceneID(for: oldRelativePath, index: $0) },
                generatedAt: modifiedAt
            )

            let video = VideoItem(url: videoURL)
            let recognizedBeforeLoad = store.hasSceneRecognitionResult(for: video)
            let persistedBeforeLoad = store.sceneCutCache[currentRelativePath] != nil
            store.loadCachedSceneCuts(for: video)
            let loadedCutCount = store.sceneCutsByVideoPath[videoURL.path]?.count ?? 0
            let persistedAfterLoad = store.sceneCutCache[currentRelativePath]?.relativePath == currentRelativePath
            let upgradedAfterLoad = store.sceneCutCache[currentRelativePath]?.detectorVersion == LibraryStore.sceneDetectorVersion
            let hasAfterLoad = store.hasSceneRecognitionResult(for: video)
            let succeeded = recognizedBeforeLoad
                && !persistedBeforeLoad
                && loadedCutCount == 2
                && persistedAfterLoad
                && upgradedAfterLoad
                && hasAfterLoad

            let report = """
            {"status":"\(succeeded ? "succeeded" : "failed")","recognizedBeforeLoad":\(recognizedBeforeLoad),"loadedCutCount":\(loadedCutCount),"persistedAfterLoad":\(persistedAfterLoad),"upgradedAfterLoad":\(upgradedAfterLoad)}
            """
            return (report, succeeded ? 0 : 1)
        } catch {
            let report = """
            {"status":"failed","error":"\(String(describing: error).replacingOccurrences(of: "\"", with: "\\\""))"}
            """
            return (report, 1)
        }
    }
}
