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

private let sceneCutActivationBoundaryTolerance: Double = 0.02

enum SceneTimelineOpeningZoomPolicy {
    nonisolated static func viewportSpan(
        cutProgresses: [Double],
        cutCount: Int,
        visibleSceneLimit: Int,
        maxZoom: Double
    ) -> Double? {
        let sceneCount = cutCount + 1
        guard sceneCount > visibleSceneLimit else { return nil }

        let maxZoomSpan = 1 / max(maxZoom, 1)
        let normalizedCuts = cutProgresses
            .map { min(1, max(0, $0)) }
            .filter { $0 > 0.001 }
            .sorted()

        if normalizedCuts.count >= visibleSceneLimit {
            let exactSpan = normalizedCuts[visibleSceneLimit - 1]
            if exactSpan.isFinite, exactSpan > 0 {
                return min(1, max(maxZoomSpan, exactSpan))
            }
        }

        let averageSpan = Double(visibleSceneLimit) / Double(sceneCount)
        return min(1, max(maxZoomSpan, averageSpan))
    }
}

extension PreviewPanelView {
    // MARK: – Helper views / computed properties

    func frameStripImages(for video: VideoItem) -> [NSImage]? {
        let path = video.url.path
        if let images = libraryStore.frameStripImagesByVideoPath[path], !images.isEmpty {
            return images
        }
        if let thumbnail = libraryStore.thumbnailImageByVideoPath[path] {
            return Array(repeating: thumbnail, count: 16)
        }
        return nil
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
        let target = controller.elapsed + sceneCutActivationBoundaryTolerance
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

    func sceneTimelineOpeningCutCount(for video: VideoItem) -> Int {
        let path = video.url.path
        if let cuts = libraryStore.sceneCutsByVideoPath[path], !cuts.isEmpty {
            return cuts.filter { $0.time > 0.001 }.count
        }
        return sceneTimelineOpeningCutProgresses(for: video).count
    }

    func sceneTimelineOpeningCutProgresses(for video: VideoItem) -> [Double] {
        let path = video.url.path
        if let cached = libraryStore.sceneCutProgressesByVideoPath[path], !cached.isEmpty {
            return cached.filter { $0 > 0.001 }
        }

        if let cuts = libraryStore.sceneCutsByVideoPath[path], !cuts.isEmpty {
            let knownDuration: Double
            if controller.duration > 0 {
                knownDuration = controller.duration
            } else {
                knownDuration = libraryStore.sceneCutProgressDuration(for: path)
            }
            guard knownDuration > 0 else { return [] }

            return cuts
                .map { min(1, max(0, $0.time / knownDuration)) }
                .filter { $0 > 0.001 }
        }

        return sceneStoryboardCuts(for: video)
    }

    func normalizedSampledFrames(for video: VideoItem) -> [Double] {
        guard controller.duration > 0 else { return [] }
        return libraryStore.sampledFrames(for: video)
            .map { min(1, max(0, $0.time / controller.duration)) }
    }

    var timelinePlayheadTint: Color {
        audioInPoint != nil && audioOutPoint == nil ? Design.timelineIOAccent : Design.timelinePlayheadAccent
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
        min(1, max(timelineMinimumViewportSpan, 1 / max(timelineZoom, 1)))
    }

    var timelineMinimumViewportSpan: Double {
        1 / max(Design.sceneTimelineAutoMaxZoom, 1)
    }

    var audioTimelineViewportSpan: Double {
        let baseSpan = max(0.02, min(1, Design.centeredWaveformViewportSpan))
        return min(1, max(0.02, baseSpan / max(audioTimelineZoom, 1)))
    }

    var timelineLiveFollowFrameInterval: TimeInterval {
        1.0 / 30.0
    }

    func timelineLiveFollowOffsetEpsilon(for span: Double) -> Double {
        min(0.0008, max(0.00005, span * 0.001))
    }

    func updateTimelineViewportWithoutAnimation(
        zoom: Double? = nil,
        offset: Double? = nil
    ) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let zoom {
                timelineZoom = zoom
            }
            if let offset {
                timelineOffset = offset
            }
        }
    }

    func focusSceneTimelineOnOpeningIfNeeded() {
        guard
            let video = libraryStore.selectedVideo,
            !timelineViewportWasManuallyAdjusted
        else { return }

        let cutCount = sceneTimelineOpeningCutCount(for: video)
        guard cutCount > 0 else { return }

        let cutProgresses = sceneTimelineOpeningCutProgresses(for: video)
        guard let span = sceneTimelineOpeningSpan(cutProgresses: cutProgresses, cutCount: cutCount) else { return }
        let key = sceneTimelineOpeningFocusKey(
            for: video,
            cutCount: cutCount,
            cutProgresses: cutProgresses,
            targetSpan: span
        )
        let targetZoom = min(Design.sceneTimelineAutoMaxZoom, max(1, 1 / span))
        let targetSpan = min(1, max(timelineMinimumViewportSpan, 1 / max(targetZoom, 1)))
        let isAlreadyFocused = sceneTimelineAutoFocusedKey == key
            && abs(timelineViewportSpan - targetSpan) <= 0.0005
            && timelineOffset <= 0.0005
        guard !isAlreadyFocused else { return }

        sceneTimelineAutoFocusedKey = key
        updateTimelineViewportWithoutAnimation(
            zoom: targetZoom,
            offset: 0
        )
    }

    func sceneTimelineOpeningFocusKey(
        for video: VideoItem,
        cutCount: Int,
        cutProgresses: [Double],
        targetSpan: Double
    ) -> String {
        let normalizedCuts = cutProgresses
            .map { min(1, max(0, $0)) }
            .filter { $0 > 0.001 }
            .sorted()
        let first = Int(((normalizedCuts.first ?? 0) * 1_000_000).rounded())
        let boundaryIndex = min(
            max(Design.sceneTimelineAutoVisibleSceneLimit - 1, 0),
            max(normalizedCuts.count - 1, 0)
        )
        let visibleBoundary = normalizedCuts.indices.contains(boundaryIndex)
            ? normalizedCuts[boundaryIndex]
            : targetSpan
        let boundary = Int((visibleBoundary * 1_000_000).rounded())
        let span = Int((targetSpan * 1_000_000).rounded())
        return "\(libraryStore.selectedVideoSelectionID.uuidString):\(video.url.path):\(cutCount):\(first):\(boundary):\(span)"
    }

    func sceneTimelineOpeningSpan(cutProgresses: [Double], cutCount: Int) -> Double? {
        SceneTimelineOpeningZoomPolicy.viewportSpan(
            cutProgresses: cutProgresses,
            cutCount: cutCount,
            visibleSceneLimit: Design.sceneTimelineAutoVisibleSceneLimit,
            maxZoom: Design.sceneTimelineAutoMaxZoom
        )
    }

    func panTimelineViewport(_ delta: Double) {
        timelineViewportWasManuallyAdjusted = true
        let span = timelineViewportSpan
        let maxOffset = max(0, 1 - span)
        let nextOffset = min(maxOffset, max(0, timelineOffset + delta))
        guard abs(nextOffset - timelineOffset) > 0.000001 else {
            protectManualTimelineScroll()
            return
        }
        updateTimelineViewportWithoutAnimation(offset: nextOffset)
        timelineAutoScrollLastUpdate = .distantPast
        protectManualTimelineScroll()
    }

    func panAudioTimelinePlayback(_ delta: Double) {
        controller.seekToProgress(controller.progress + delta)
    }

    func displayedTimelineOffset(for progress: Double) -> Double {
        let span = timelineViewportSpan
        guard span < 0.999 else { return 0 }
        guard controller.isPlaying || keyboardShuttleDirection != 0 else { return timelineOffset }
        guard Date() >= timelineManualScrollProtectionUntil else { return timelineOffset }

        return timelineFollowOffset(for: progress)
    }

    func timelineFollowOffset(for progress: Double) -> Double {
        let span = timelineViewportSpan
        guard span < 0.999 else { return 0 }

        let clamped = min(1, max(0, progress))
        let maxOffset = max(0, 1 - span)
        let margin = min(0.08, span * 0.18)
        let visibleStart = timelineOffset
        let visibleEnd = timelineOffset + span

        if clamped < visibleStart + margin {
            return max(0, clamped - margin)
        }
        if clamped > visibleEnd - margin {
            return min(maxOffset, clamped + margin - span)
        }
        return timelineOffset
    }

    func commitDisplayedTimelineOffsetIfNeeded(for progress: Double) {
        guard Date() >= timelineManualScrollProtectionUntil else { return }
        let span = timelineViewportSpan
        let targetOffset = timelineFollowOffset(for: progress)
        let offsetDelta = abs(targetOffset - timelineOffset)
        guard offsetDelta > timelineLiveFollowOffsetEpsilon(for: span) else { return }

        updateTimelineViewportWithoutAnimation(offset: targetOffset)
        timelineAutoScrollLastUpdate = .distantPast
    }

    func zoomAudioTimelineViewport(_ factor: Double, anchor _: Double) {
        let nextZoom = min(50, max(1, audioTimelineZoom * factor))
        guard abs(nextZoom - audioTimelineZoom) > 0.000001 else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            audioTimelineZoom = nextZoom
        }
    }

    func zoomTimelineViewport(_ factor: Double, anchor: Double) {
        timelineViewportWasManuallyAdjusted = true
        let oldSpan = timelineViewportSpan
        let anchorProgress = timelineOffset + min(1, max(0, anchor)) * oldSpan
        let nextZoom = min(Design.sceneTimelineAutoMaxZoom, max(1, timelineZoom * factor))
        let nextSpan = min(1, max(timelineMinimumViewportSpan, 1 / nextZoom))
        let maxOffset = max(0, 1 - nextSpan)
        guard abs(nextZoom - timelineZoom) > 0.000001 else {
            protectManualTimelineScroll()
            return
        }
        updateTimelineViewportWithoutAnimation(
            zoom: nextZoom,
            offset: min(maxOffset, max(0, anchorProgress - min(1, max(0, anchor)) * nextSpan))
        )
        timelineAutoScrollLastUpdate = .distantPast
        protectManualTimelineScroll()
    }

    func resetTimelineViewport() {
        updateTimelineViewportWithoutAnimation(zoom: 1, offset: 0)
        timelineAutoScrollLastUpdate = .distantPast
        timelineManualScrollProtectionUntil = .distantPast
        sceneTimelineAutoFocusedKey = nil
        timelineViewportWasManuallyAdjusted = false
    }

    func resetAudioTimelineViewport() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            audioTimelineZoom = 1
        }
    }

    func keepTimelineProgressVisible(_ progress: Double) {
        let span = timelineViewportSpan
        guard span < 0.999 else { return }
        let now = Date()
        guard now >= timelineManualScrollProtectionUntil else { return }

        let targetOffset = timelineFollowOffset(for: progress)
        let offsetDelta = abs(targetOffset - timelineOffset)
        guard offsetDelta > timelineLiveFollowOffsetEpsilon(for: span) else { return }
        if controller.isPlaying || keyboardShuttleDirection != 0 {
            return
        } else {
            withAnimation(.easeOut(duration: 0.14)) {
                timelineOffset = targetOffset
            }
            timelineAutoScrollLastUpdate = .distantPast
        }
    }

    func protectManualTimelineScroll() {
        timelineManualScrollProtectionUntil = Date().addingTimeInterval(0.75)
    }

    func handlePlaybackClockTick(_ elapsed: Double) {
        if !controller.isPlaying && keyboardShuttleDirection == 0 {
            keepTimelineProgressVisible(controller.progress)
        }

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

    func flashTransportShortcutFeedback(_ feedback: PreviewTransportShortcutFeedback) {
        transportShortcutFeedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.06)) {
            activeTransportShortcutFeedback = feedback
        }

        transportShortcutFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                if activeTransportShortcutFeedback == feedback {
                    activeTransportShortcutFeedback = nil
                }
            }
            transportShortcutFeedbackTask = nil
        }
    }

    func holdTransportShortcutFeedback(_ feedback: PreviewTransportShortcutFeedback) {
        transportShortcutFeedbackTask?.cancel()
        transportShortcutFeedbackTask = nil
        withAnimation(.easeOut(duration: 0.06)) {
            activeTransportShortcutFeedback = feedback
        }
    }

    func clearTransportShortcutFeedback(_ feedback: PreviewTransportShortcutFeedback? = nil) {
        guard feedback == nil || activeTransportShortcutFeedback == feedback else { return }
        transportShortcutFeedbackTask?.cancel()
        transportShortcutFeedbackTask = nil
        withAnimation(.easeOut(duration: 0.12)) {
            activeTransportShortcutFeedback = nil
        }
    }

    func handlePreviewKeyboardCommand(_ command: PreviewKeyboardCommand) -> Bool {
        guard let selectedVideo = libraryStore.selectedVideo else { return false }

        switch command {
        case .togglePlayback:
            flashTransportShortcutFeedback(.playback)
            controller.togglePlayback()
        case .pause:
            stopKeyboardShuttle()
            flashTransportShortcutFeedback(.playback)
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
            flashTransportShortcutFeedback(.forward)
        case .stepBackward:
            stopKeyboardShuttle()
            controller.stepFrame(by: -1)
            flashTransportShortcutFeedback(.backward)
        case .previousSceneCut:
            stopKeyboardShuttle()
            seekSceneCut(for: selectedVideo, direction: -1)
        case .nextSceneCut:
            stopKeyboardShuttle()
            seekSceneCut(for: selectedVideo, direction: 1)
        case .setAudioIn:
            flashTransportShortcutFeedback(.io)
            setAudioInPoint()
        case .setAudioOut:
            flashTransportShortcutFeedback(.io)
            setAudioOutPoint()
        case .clearAudioSelection:
            flashTransportShortcutFeedback(.io)
            clearAudioSelection()
        case .captureCurrentFrame:
            stopKeyboardShuttle()
            flashTransportShortcutFeedback(.screenshot)
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
        holdTransportShortcutFeedback(direction > 0 ? .forward : .backward)
        guard keyboardShuttleDirection != direction else { return }

        stopKeyboardShuttle(clearsTransportShortcutFeedback: false)
        keyboardShuttleDirection = direction
        keyboardShuttleFrameStep = 2
        controller.pause()
        controller.seekToSeconds(
            controller.elapsed + Double(direction) / max(controller.frameRate, 1),
            snapToFrame: true
        )

        keyboardShuttleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            while !Task.isCancelled, keyboardShuttleDirection == direction {
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
        holdTransportShortcutFeedback(keyboardShuttleDirection > 0 ? .forward : .backward)
    }

    func stopKeyboardShuttle(clearsTransportShortcutFeedback: Bool = true) {
        keyboardShuttleTask?.cancel()
        keyboardShuttleTask = nil
        if keyboardShuttleDirection != 0 {
            commitDisplayedTimelineOffsetIfNeeded(for: controller.progress)
        }
        keyboardShuttleDirection = 0
        keyboardShuttleFrameStep = 2
        keyboardShuttleLastCommandAt = .distantPast
        if clearsTransportShortcutFeedback {
            if let feedback = activeTransportShortcutFeedback, feedback == .backward || feedback == .forward {
                flashTransportShortcutFeedback(feedback)
            } else {
                clearTransportShortcutFeedback()
            }
        }
    }

}
