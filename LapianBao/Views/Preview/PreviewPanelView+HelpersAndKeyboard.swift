//
//  PreviewPanelView+HelpersAndKeyboard.swift
//  LapianBao
//
//  Split from ContentView.swift.
//

import SwiftUI
import AVFoundation
import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension PreviewPanelView {
    // MARK: – Helper views / computed properties

    func frameStripImages(for video: VideoItem) -> [NSImage]? {
        guard let images = libraryStore.frameStripImagesByVideoPath[video.url.path],
              !images.isEmpty else { return nil }
        return images
    }

    /// 场景识别完成时返回每个场景的代表帧列表（index 0 = 片头帧，1…N = 切点首帧）。
    /// 未完成识别时返回 nil，FrameScrubberView 回退到均匀采样帧带。
    func sceneStripImages(for video: VideoItem) -> [NSImage]? {
        guard let images = libraryStore.sceneStripImagesByVideoPath[video.url.path], !images.isEmpty else { return nil }
        return images
    }

    func activeTranscriptSegmentID(at elapsed: Double, in segments: [TranscriptSegment]) -> UUID? {
        guard !segments.isEmpty else { return nil }
        var lower = 0
        var upper = segments.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if segments[middle].start <= elapsed {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let index = lower - 1
        return segments.indices.contains(index) ? segments[index].id : nil
    }

    func activeSceneItemID(for video: VideoItem) -> String? {
        guard let cuts = libraryStore.sceneCutsByVideoPath[video.url.path], !cuts.isEmpty else { return nil }
        let target = controller.elapsed
        var lower = 0
        var upper = cuts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cuts[middle].time <= target {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let idx = max(0, lower - 1)
        return "cut-\(cuts[idx].id)"
    }

    var previewTimecodeText: String {
        formatDuration(controller.elapsed)
    }

    func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }


    func normalizedSceneCuts(for video: VideoItem) -> [Double] {
        let path = video.url.path
        guard
            let cuts = libraryStore.sceneCutsByVideoPath[path],
            !cuts.isEmpty
        else {
            return libraryStore.sceneCutProgressesByVideoPath[path] ?? []
        }

        if let cached = libraryStore.sceneCutProgressesByVideoPath[path], !cached.isEmpty {
            return cached
        }

        guard
            controller.duration > 0
        else { return [] }
        return cuts.map { min(1, max(0, $0.time / controller.duration)) }
    }

    func sceneStoryboardCuts(for video: VideoItem) -> [Double] {
        let cuts = normalizedSceneCuts(for: video)
        guard cuts.first.map({ $0 <= 0.001 }) == true else { return cuts }
        return Array(cuts.dropFirst())
    }

    func normalizedSampledFrames(for video: VideoItem) -> [Double] {
        guard controller.duration > 0 else { return [] }
        return libraryStore.sampledFrames(for: video)
            .map { min(1, max(0, $0.time / controller.duration)) }
    }

    var timelinePlayheadTint: Color {
        audioInPoint != nil && audioOutPoint == nil ? .orange : .white.opacity(0.92)
    }

    func normalizedAnnotations(for video: VideoItem, kind: AnnotationItem.Kind? = nil) -> [TimelineAnnotationMarker] {
        guard controller.duration > 0 else { return [] }
        return libraryStore.annotations(for: video).compactMap { annotation in
            guard kind == nil || annotation.kind == kind else { return nil }
            return TimelineAnnotationMarker(
                id: annotation.id,
                progress: min(1, max(0, annotation.time / controller.duration)),
                text: annotation.text,
                kind: annotation.kind
            )
        }
    }

    func prevSceneAction(cuts: [SceneCut]) -> (() -> Void)? {
        guard !cuts.isEmpty else { return nil }
        return {
            let t = self.controller.elapsed
            if let prev = cuts.last(where: { $0.time < t - 0.1 }) {
                self.controller.seekToSeconds(prev.time)
            } else {
                self.controller.seekToSeconds(0)
            }
        }
    }

    func nextSceneAction(cuts: [SceneCut]) -> (() -> Void)? {
        guard !cuts.isEmpty else { return nil }
        return {
            let t = self.controller.elapsed
            if let next = cuts.first(where: { $0.time > t + 0.1 }) {
                self.controller.seekToSeconds(next.time)
            }
        }
    }

    var timelineViewportSpan: Double {
        min(1, max(0.02, 1 / max(timelineZoom, 1)))
    }

    func focusSceneTimelineOnOpeningIfNeeded() {
        guard
            activePreviewTab == .frames,
            let video = libraryStore.selectedVideo,
            timelineViewportSpan >= 0.999,
            timelineOffset <= 0.0005
        else { return }

        let cuts = sceneStoryboardCuts(for: video)
        guard !cuts.isEmpty else { return }

        let key = sceneTimelineOpeningFocusKey(for: video, cuts: cuts)
        guard sceneTimelineAutoFocusedKey != key else { return }

        sceneTimelineAutoFocusedKey = key
        guard let span = sceneTimelineOpeningSpan(from: cuts) else { return }

        timelineZoom = min(Design.sceneTimelineAutoMaxZoom, max(1, 1 / span))
        timelineOffset = 0
    }

    func sceneTimelineOpeningFocusKey(for video: VideoItem, cuts: [Double]) -> String {
        let first = Int(((cuts.first ?? 0) * 1_000_000).rounded())
        let last = Int(((cuts.last ?? 0) * 1_000_000).rounded())
        return "\(libraryStore.selectedVideoSelectionID.uuidString):\(video.url.path):\(cuts.count):\(first):\(last)"
    }

    func sceneTimelineOpeningSpan(from cuts: [Double]) -> Double? {
        let sceneCount = cuts.count + 1
        guard sceneCount > Design.sceneTimelineAutoVisibleSceneLimit else { return nil }

        let targetSpan = Double(Design.sceneTimelineAutoVisibleSceneLimit) / Double(sceneCount)
        let maxZoomSpan = 1 / Design.sceneTimelineAutoMaxZoom
        return min(1, max(maxZoomSpan, targetSpan))
    }

    func panTimelineViewport(_ delta: Double) {
        let span = timelineViewportSpan
        let maxOffset = max(0, 1 - span)
        timelineOffset = min(maxOffset, max(0, timelineOffset + delta))
    }

    func panAudioTimelinePlayback(_ delta: Double) {
        controller.seekToProgress(controller.progress + delta)
    }

    func zoomTimelineViewport(_ factor: Double, anchor: Double) {
        let oldSpan = timelineViewportSpan
        let anchorProgress = timelineOffset + min(1, max(0, anchor)) * oldSpan
        let nextZoom = min(50, max(1, timelineZoom * factor))
        let nextSpan = min(1, max(0.02, 1 / nextZoom))
        let maxOffset = max(0, 1 - nextSpan)
        timelineZoom = nextZoom
        timelineOffset = min(maxOffset, max(0, anchorProgress - min(1, max(0, anchor)) * nextSpan))
    }

    func resetTimelineViewport() {
        timelineZoom = 1
        timelineOffset = 0
    }

    func keepTimelineProgressVisible(_ progress: Double) {
        let span = timelineViewportSpan
        guard span < 0.999 else { return }

        let clamped = min(1, max(0, progress))
        let maxOffset = max(0, 1 - span)
        let margin = min(0.08, span * 0.18)
        let visibleStart = timelineOffset
        let visibleEnd = timelineOffset + span
        let targetOffset: Double?

        if clamped < visibleStart + margin {
            targetOffset = max(0, clamped - margin)
        } else if clamped > visibleEnd - margin {
            targetOffset = min(maxOffset, clamped + margin - span)
        } else {
            targetOffset = nil
        }

        guard let targetOffset, abs(targetOffset - timelineOffset) > 0.0005 else { return }
        if controller.isPlaying || keyboardShuttleDirection != 0 {
            timelineOffset = targetOffset
        } else {
            withAnimation(.easeOut(duration: 0.14)) {
                timelineOffset = targetOffset
            }
        }
    }

    func handlePlaybackClockTick(_ elapsed: Double) {
        keepTimelineProgressVisible(controller.progress)

        guard let video = libraryStore.selectedVideo else { return }
        let segs = libraryStore.transcriptSegmentsByVideoPath[video.url.path, default: []]
        let segmentID = activeTranscriptSegmentID(at: elapsed, in: segs)
        if segmentID != activeTranscriptSegmentID {
            activeTranscriptSegmentID = segmentID
        }
    }

    func togglePreviewPlayback() {
        stopKeyboardShuttle()
        controller.togglePlayback()
    }

    // MARK: – Keyboard control

    func handlePreviewKeyboardCommand(_ command: PreviewKeyboardCommand) -> Bool {
        guard let selectedVideo = libraryStore.selectedVideo else { return false }

        switch command {
        case .togglePlayback:
            controller.togglePlayback()
        case .pause:
            stopKeyboardShuttle()
            controller.pause()
        case .shuttleForward:
            startKeyboardShuttle(direction: 1)
        case .shuttleBackward:
            startKeyboardShuttle(direction: -1)
        case .stopShuttle:
            stopKeyboardShuttle()
        case .increaseShuttleSpeed:
            increaseKeyboardShuttleSpeed()
        case .stepForward:
            stopKeyboardShuttle()
            controller.stepFrame(by: 1)
        case .stepBackward:
            stopKeyboardShuttle()
            controller.stepFrame(by: -1)
        case .previousSceneCut:
            stopKeyboardShuttle()
            seekSceneCut(for: selectedVideo, direction: -1)
        case .nextSceneCut:
            stopKeyboardShuttle()
            seekSceneCut(for: selectedVideo, direction: 1)
        case .setAudioIn:
            setAudioInPoint()
        case .setAudioOut:
            setAudioOutPoint()
        case .clearAudioSelection:
            clearAudioSelection()
        case .captureCurrentFrame:
            stopKeyboardShuttle()
            libraryStore.captureCurrentFrame(video: selectedVideo, time: controller.elapsed)
        case .exportAudioSelection:
            exportCurrentAudioSelection(for: selectedVideo)
        }

        return true
    }

    func seekSceneCut(for video: VideoItem, direction: Int) {
        let cuts = libraryStore.sceneCutsByVideoPath[video.url.path] ?? []
        guard !cuts.isEmpty else { return }
        let elapsed = controller.elapsed

        if direction < 0 {
            if let previous = cuts.last(where: { $0.time < elapsed - 0.1 }) {
                controller.seekToSeconds(previous.time)
            } else {
                controller.seekToSeconds(0)
            }
            return
        }

        if let next = cuts.first(where: { $0.time > elapsed + 0.1 }) {
            controller.seekToSeconds(next.time)
        }
    }

    func startKeyboardShuttle(direction: Int) {
        keyboardShuttleLastCommandAt = Date()
        guard keyboardShuttleDirection != direction else { return }

        stopKeyboardShuttle()
        keyboardShuttleDirection = direction
        keyboardShuttleFrameStep = 2
        controller.pause()
        controller.seekToSeconds(
            controller.elapsed + Double(direction) / max(controller.frameRate, 1),
            snapToFrame: true
        )

        keyboardShuttleTask = Task { @MainActor in
            let startedAt = Date()
            try? await Task.sleep(nanoseconds: 180_000_000)
            while !Task.isCancelled, keyboardShuttleDirection == direction {
                let now = Date()
                guard now.timeIntervalSince(startedAt) <= 8,
                      now.timeIntervalSince(keyboardShuttleLastCommandAt) <= 1.2
                else {
                    stopKeyboardShuttle()
                    break
                }

                let frameStep = Double(keyboardShuttleFrameStep) / max(controller.frameRate, 1)
                let next = controller.elapsed + Double(direction) * frameStep
                if direction > 0, next >= controller.duration {
                    controller.seekToSeconds(controller.duration, snapToFrame: true)
                    stopKeyboardShuttle()
                    break
                }
                if direction < 0, next <= 0 {
                    controller.seekToSeconds(0, snapToFrame: true)
                    stopKeyboardShuttle()
                    break
                }

                controller.seekToSeconds(next, snapToFrame: true)
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    func increaseKeyboardShuttleSpeed() {
        guard keyboardShuttleDirection != 0 else { return }
        keyboardShuttleLastCommandAt = Date()
        keyboardShuttleFrameStep = min(keyboardShuttleFrameStep + 1, 12)
    }

    func stopKeyboardShuttle() {
        keyboardShuttleTask?.cancel()
        keyboardShuttleTask = nil
        keyboardShuttleDirection = 0
        keyboardShuttleFrameStep = 2
        keyboardShuttleLastCommandAt = .distantPast
    }

}
