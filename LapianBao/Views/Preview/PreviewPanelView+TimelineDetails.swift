//
//  PreviewPanelView+TimelineDetails.swift
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
    @ViewBuilder
    func timelineDetailContent(_ tab: PreviewTab, for video: VideoItem) -> some View {
        switch tab {
        case .frames:
            frameTimelineDetailContent(for: video)
        case .audio, .content:
            contentTimelineDetailContent(for: video)
        }
    }

    func frameTimelineDetailContent(
        for video: VideoItem,
        activeProgressTick: Double? = nil
    ) -> some View {
        ScenePanelView(
            video: video,
            controller: controller,
            sceneCuts: libraryStore.sceneCutsByVideoPath[video.url.path] ?? [],
            hasSceneRecognitionResult: libraryStore.sceneCutsByVideoPath[video.url.path] != nil,
            sceneDetectionProgress: libraryStore.sceneDetectionProgress[video.url.path],
            sceneDetectionError: libraryStore.sceneDetectionErrorByVideoPath[video.url.path],
            sceneThumbnailVersion: libraryStore.sceneThumbnailVersionsByVideoPath[video.url.path] ?? 0,
            sceneThumbnailsNeedHydration: libraryStore.sceneThumbnailsNeedHydration(for: video),
            isHydratingSceneThumbnails: libraryStore.isHydratingSceneThumbnails(for: video),
            sampledFrames: libraryStore.sampledFrames(for: video),
            activeItemID: activeSceneItemID(for: video),
            activeProgressTick: activeProgressTick,
            openStoryboardBoard: { openStoryboardBoard(video) },
            exportStoryboard: { exportCurrentStoryboard(for: video) },
            storyboardExportTitle: storyboardExportButtonTitle(for: video)
        )
        .equatable()
    }

    func audioTimelineDetailContent(for video: VideoItem) -> some View {
        homeAudioClipList(for: video)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func contentTimelineDetailContent(for video: VideoItem) -> some View {
        let path = video.url.path
        let status = libraryStore.transcriptStatusByVideoPath[path]
        let segments = libraryStore.transcriptSegmentsByVideoPath[path, default: []]

        if segments.isEmpty {
            contentRecognitionStartBlock(for: video, status: status)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ZStack(alignment: .bottomTrailing) {
                subtitleTimelineBlock(for: video)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                contentTimelineExportButtons(for: video)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    func contentRecognitionStartBlock(for video: VideoItem, status: TranscriptJobStatus?) -> some View {
        if case let .failed(message) = status {
            RecognitionFailureIndicator(message: message, minHeight: 34)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    func subtitleTimelineBlock(for video: VideoItem) -> some View {
        let path = video.url.path
        let status = libraryStore.transcriptStatusByVideoPath[path]
        let segments = libraryStore.transcriptSegmentsByVideoPath[path, default: []]

        VStack(alignment: .leading, spacing: 8) {
            if case .running = status {
                if !segments.isEmpty {
                    subtitleSegmentList(segments)
                }
            } else if segments.isEmpty {
                VStack(spacing: 10) {
                    if case let .failed(message) = status {
                        RecognitionFailureIndicator(message: message, minHeight: 28)
                    } else {
                        AppEmptyState(
                            title: "暂无字幕",
                            style: .inline,
                            fillsWidth: false
                        )
                    }

                    Button {
                        libraryStore.transcribe(video: video)
                    } label: {
                        Label(statusFailed(status) ? "重试" : "生成字幕", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                subtitleSegmentList(segments)
            }
        }
        .padding(Self.contentTimelineDetailBlockPadding)
    }

    func timelineProgressRow(_ message: String) -> some View {
        RecognitionProgressRow(
            message: message,
            progress: activityProgressValue(from: message)
        )
        .recognitionProgressCard()
    }

    func contentTimelineExportButtons(for video: VideoItem) -> some View {
        HStack(spacing: 7) {
            transcriptExportOverlayButton(for: video)
        }
    }

    func transcriptExportOverlayButton(for video: VideoItem) -> some View {
        Button {
            exportCurrentTranscript(for: video)
        } label: {
            contentTimelineExportButtonLabel(systemImage: "square.and.arrow.up", title: "导出字幕")
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    func storyboardExportButtonTitle(for video: VideoItem) -> String {
        let path = video.url.path
        if pendingStoryboardExportPath == path {
            if let progress = libraryStore.sceneDetectionProgress[path] {
                return "导出中 \(progressPercentText(progress))"
            }
            return "等待导出"
        }
        return libraryStore.hasSceneRecognitionResult(for: video) ? "导出分镜表" : "识别后导出"
    }

    func storyboardExportButtonHelp(for video: VideoItem) -> String {
        let path = video.url.path
        if pendingStoryboardExportPath == path {
            return "分镜识别完成后自动导出 Word"
        }
        return libraryStore.hasSceneRecognitionResult(for: video) ? "导出分镜表 Word" : "先识别分镜，完成后自动导出 Word"
    }

    func contentTimelineExportButtonLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.monochrome)

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.black.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 0.7)
        }
    }

    func subtitleSegmentList(_ segments: [TranscriptSegment]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(segments) { segment in
                        let isActive = segment.id == activeTranscriptSegmentID
                        Button {
                            controller.pause()
                            controller.seekToSeconds(segment.start)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text(formatDuration(segment.start))
                                    .font(Design.numericCaption2(weight: .semibold))
                                    .foregroundStyle(isActive ? Design.annotationAccent : Design.annotationAccent.opacity(0.62))
                                    .frame(width: 52, alignment: .leading)
                                Text(segment.text)
                                    .font(.caption)
                                    .foregroundStyle(isActive ? .primary : .secondary)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 7)
                            .background(isActive ? Color.white.opacity(0.10) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(segment.id)
                    }
                }
                .padding(.bottom, 48)
            }
            .fadingVerticalScrollIndicators()
            .onChange(of: activeTranscriptSegmentID) { _, newID in
                if let newID {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
    }

    func statusFailed(_ status: TranscriptJobStatus?) -> Bool {
        if case .failed = status { return true }
        return false
    }

    func startRecognitionForVisibleTimelineIfNeeded(tab: PreviewTab? = nil) {
        guard let video = libraryStore.selectedVideo else { return }
        let timeline = tab ?? visibleTimelineDetailTab

        switch timeline {
        case .frames:
            startSceneRecognitionIfNeeded(for: video)
        case .audio, .content:
            startContentRecognitionIfNeeded(for: video)
        case .none:
            break
        }
    }

    func hydrateSceneThumbnailsForFrameTimelineIfIdle() {
        guard
            let video = libraryStore.selectedVideo,
            !controller.isPlaying,
            activePreviewTab == .frames || visibleTimelineDetailTab == .frames
        else { return }

        libraryStore.hydrateSceneThumbnailsIfNeeded(for: video)
    }

    func startSceneRecognitionIfNeeded(for video: VideoItem) {
        let path = video.url.path
        if libraryStore.sceneCutsByVideoPath[path] != nil {
            hydrateSceneThumbnailsForFrameTimelineIfIdle()
            return
        }

        guard
            libraryStore.sceneDetectionProgress[path] == nil,
            libraryStore.sceneDetectionErrorByVideoPath[path] == nil
        else { return }

        libraryStore.detectSceneCuts(for: video)
    }

    func startContentRecognitionIfNeeded(for video: VideoItem) {
        let path = video.url.path
        let segments = libraryStore.transcriptSegmentsByVideoPath[path, default: []]

        if segments.isEmpty {
            libraryStore.prepareExternalServiceWork()
            startSubtitleRecognitionIfNeeded(for: video)
        }
    }

    func startSubtitleRecognitionIfNeeded(for video: VideoItem) {
        switch libraryStore.transcriptStatusByVideoPath[video.url.path] {
        case .running(_), .failed(_), .completed:
            return
        case .idle, .none:
            break
        }
        libraryStore.transcribe(video: video)
    }

    func frameTimeline(for video: VideoItem, clock: PlaybackClockSnapshot) -> some View {
        let cuts = libraryStore.sceneCutsByVideoPath[video.url.path] ?? []

        return FrameScrubberView(
            frames: frameStripImages(for: video),
            progress: clock.progress,
            timecodeText: clock.timecodeText,
            sceneCuts: sceneStoryboardCuts(for: video),
            isPlaying: controller.isPlaying,
            playbackRate: controller.playbackRate,
            togglePlayback: { controller.togglePlayback() },
            seek: { controller.seekToProgress($0) },
            screenshotMarkers: normalizedSampledFrames(for: video),
            annotationItems: normalizedAnnotations(for: video, kind: .frame),
            prevScene: prevSceneAction(cuts: cuts),
            nextScene: nextSceneAction(cuts: cuts),
            stepBack: { controller.stepFrame(by: -1) },
            stepForward: { controller.stepFrame(by: 1) },
            onScreenshot: { libraryStore.captureCurrentFrame(video: video, time: controller.elapsed) },
            onAnnotate: { beginAnnotation(.frame, sourceTab: .frames) },
            onAnnotationSelect: { openAnnotation($0, sourceTab: .frames) },
            viewportStart: timelineOffset,
            viewportSpan: timelineViewportSpan,
            duration: controller.duration,
            zoomLevel: timelineZoom,
            panViewport: panTimelineViewport,
            zoomViewport: zoomTimelineViewport,
            resetViewport: resetTimelineViewport,
            timelineHeight: previewTimelineLaneContentHeight,
            sceneImages: sceneStripImages(for: video)
        )
    }

    func audioTimeline(for video: VideoItem, clock: PlaybackClockSnapshot) -> some View {
        let dur = controller.duration

        let outPoint = audioOutPoint ?? (audioInPoint == nil ? nil : clock.elapsed)

        return CenteredWaveformTimeline(
            samples: libraryStore.waveformSamplesByVideoPath[video.url.path],
            progress: clock.progress,
            seek: { controller.seekToProgress($0) },
            sceneCuts: [],
            inPoint: audioInPoint.map { dur > 0 ? $0 / dur : 0 },
            outPoint: outPoint.map { dur > 0 ? $0 / dur : 0 },
            annotationItems: normalizedAnnotations(for: video, kind: .audio),
            onAnnotationSelect: { openAnnotation($0, sourceTab: .audio) },
            onClearSelection: { clearAudioSelection() },
            viewportSpan: Design.centeredWaveformViewportSpan,
            playheadTint: timelinePlayheadTint,
            panViewport: panAudioTimelinePlayback
        )
    }

    func contentTimeline(for video: VideoItem, clock: PlaybackClockSnapshot) -> some View {
        SimpleProgressBar(
            progress: clock.progress,
            timecodeText: clock.timecodeText,
            isPlaying: controller.isPlaying,
            togglePlayback: { controller.togglePlayback() },
            seek: { controller.seekToProgress($0) },
            annotationItems: normalizedAnnotations(for: video),
            onAnnotationSelect: { openAnnotation($0, sourceTab: .content) },
            playheadTint: Design.timelinePlayheadAccent,
            stepBack: { controller.stepFrame(by: -1) },
            stepForward: { controller.stepFrame(by: 1) },
            onScreenshot: { libraryStore.captureCurrentFrame(video: video, time: controller.elapsed) },
            onAnnotate: { beginAnnotation(.content, sourceTab: .content) }
        )
    }

    func annotationEditorView(for video: VideoItem) -> some View {
        let editingAnnotation = editingAnnotation(for: video)
        let title = editingAnnotation.map { "编辑\($0.kind.title)批注" }
            ?? "添加\(pendingAnnotationKind.title)批注 · \(previewTimecodeText)"

        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            AnnotationEditorTextView(text: $annotationText)
                .frame(maxWidth: .infinity)
                .frame(height: 104)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            HStack {
                if let editingAnnotation {
                    Button(role: .destructive) {
                        libraryStore.deleteAnnotation(editingAnnotation)
                        editingAnnotationID = nil
                        isAnnotationPopoverPresented = false
                    } label: {
                        Text("删除")
                    }
                }

                Spacer()
                Button("取消") {
                    editingAnnotationID = nil
                    isAnnotationPopoverPresented = false
                }
                Button("保存") {
                    if let editingAnnotation {
                        libraryStore.updateAnnotation(editingAnnotation, text: annotationText)
                    } else {
                        let annotationTime = controller.duration > 0
                            ? annotationEditorAnchor.progress * controller.duration
                            : controller.elapsed
                        libraryStore.addAnnotation(video: video, time: annotationTime, text: annotationText, kind: pendingAnnotationKind)
                    }
                    editingAnnotationID = nil
                    isAnnotationPopoverPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }

    func beginAnnotation(_ kind: AnnotationItem.Kind, sourceTab: PreviewTab) {
        pendingAnnotationKind = kind
        editingAnnotationID = nil
        annotationText = ""
        annotationEditorAnchor = AnnotationEditorAnchor(
            progress: min(1, max(0, controller.progress)),
            kind: kind,
            sourceTab: sourceTab
        )
        isAnnotationPopoverPresented = true
    }

    func openAnnotation(_ id: UUID, sourceTab: PreviewTab) {
        guard let annotation = libraryStore.annotations.first(where: { $0.id == id }) else { return }
        pendingAnnotationKind = annotation.kind
        editingAnnotationID = id
        annotationText = annotation.text
        let progress = controller.duration > 0 ? annotation.time / controller.duration : controller.progress
        annotationEditorAnchor = AnnotationEditorAnchor(
            progress: min(1, max(0, progress)),
            kind: annotation.kind,
            sourceTab: sourceTab
        )
        isAnnotationPopoverPresented = true
    }

    func editingAnnotation(for video: VideoItem) -> AnnotationItem? {
        guard let editingAnnotationID else { return nil }
        return libraryStore.annotations(for: video).first { $0.id == editingAnnotationID }
    }

}

private struct AnnotationEditorTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.font = .systemFont(ofSize: 16, weight: .regular)
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = context.coordinator.textView ?? scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
