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
        for video: VideoItem
    ) -> some View {
        ScenePanelView(
            video: video,
            controller: controller,
            sceneCuts: libraryStore.sceneCutsByVideoPath[video.url.path] ?? [],
            hasSceneRecognitionResult: libraryStore.hasSceneRecognitionResult(for: video),
            sceneDetectionProgress: libraryStore.sceneDetectionProgress[video.url.path],
            sceneDetectionError: libraryStore.sceneDetectionErrorByVideoPath[video.url.path],
            sceneThumbnailVersion: libraryStore.sceneThumbnailVersionsByVideoPath[video.url.path] ?? 0,
            sceneThumbnailsNeedHydration: libraryStore.sceneThumbnailsNeedHydration(for: video),
            isHydratingSceneThumbnails: libraryStore.isHydratingSceneThumbnails(for: video),
            sampledFrames: libraryStore.sampledFrames(for: video),
            activeItemID: activeSceneItemID(for: video),
            playbackDuration: controller.duration,
            playbackRate: controller.playbackRate,
            isPlaybackPlaying: controller.isPlaying,
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
                    .accessibilityIdentifier("transcript_generate_button")
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
        .accessibilityLabel("导出字幕")
        .accessibilityIdentifier("transcript_export_button")
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
                        .accessibilityIdentifier("transcript_segment_row")
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
        libraryStore.loadCachedSceneCuts(for: video)
        if libraryStore.hasSceneRecognitionResult(for: video) {
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
        let viewportStart = displayedTimelineOffset(for: clock.progress)

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
            viewportStart: viewportStart,
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
            viewportSpan: audioTimelineViewportSpan,
            playheadTint: timelinePlayheadTint,
            panViewport: panAudioTimelinePlayback,
            zoomViewport: zoomAudioTimelineViewport
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

        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.88)
            AnnotationEditorTextView(text: $annotationText)
                .frame(maxWidth: .infinity)
                .frame(height: 122)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            HStack(spacing: 12) {
                if let editingAnnotation {
                    AnnotationEditorActionButton(
                        title: "删除",
                        role: .destructive,
                        accessibilityIdentifier: "annotation_editor_delete_button"
                    ) {
                        libraryStore.deleteAnnotation(editingAnnotation)
                        editingAnnotationID = nil
                        isAnnotationPopoverPresented = false
                    }
                }

                AnnotationEditorActionButton(
                    title: "取消",
                    role: .secondary,
                    accessibilityIdentifier: "annotation_editor_cancel_button"
                ) {
                    editingAnnotationID = nil
                    isAnnotationPopoverPresented = false
                }
                AnnotationEditorActionButton(
                    title: "保存",
                    role: .primary,
                    accessibilityIdentifier: "annotation_editor_save_button"
                ) {
                    saveAnnotationEditor(for: video, editingAnnotation: editingAnnotation)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: AnnotationEditorActionButton.height)
            .zIndex(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    func saveAnnotationEditor(for video: VideoItem, editingAnnotation: AnnotationItem?) {
        let latestText = currentAnnotationEditorText()
        annotationText = latestText
        let trimmedText = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let didSave: Bool
        if let editingAnnotation {
            didSave = libraryStore.updateAnnotation(editingAnnotation, text: trimmedText)
        } else {
            let annotationTime = controller.duration > 0
                ? annotationEditorAnchor.progress * controller.duration
                : controller.elapsed
            didSave = libraryStore.addAnnotation(video: video, time: annotationTime, text: trimmedText, kind: pendingAnnotationKind)
        }

        guard didSave else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        editingAnnotationID = nil
        isAnnotationPopoverPresented = false
    }

    func currentAnnotationEditorText() -> String {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           isAnnotationEditorTextView(textView)
        {
            return textView.string
        }
        if let textView = annotationEditorTextView(in: NSApp.keyWindow?.contentView) {
            return textView.string
        }
        for window in NSApp.windows where window != NSApp.keyWindow {
            if let textView = annotationEditorTextView(in: window.contentView) {
                return textView.string
            }
        }
        return annotationText
    }

    func annotationEditorTextView(in rootView: NSView?) -> NSTextView? {
        guard let rootView else { return nil }
        if let textView = rootView as? NSTextView, isAnnotationEditorTextView(textView) {
            return textView
        }
        for subview in rootView.subviews {
            if let textView = annotationEditorTextView(in: subview) {
                return textView
            }
        }
        return nil
    }

    func isAnnotationEditorTextView(_ textView: NSTextView) -> Bool {
        textView.accessibilityIdentifier() == AnnotationEditorAccessibility.textViewIdentifier
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

private enum AnnotationEditorAccessibility {
    static let textViewIdentifier = "annotation_editor_text_view"
}

private struct AnnotationEditorActionButton: View {
    enum Role {
        case primary
        case secondary
        case destructive
    }

    static let height: CGFloat = 30

    let title: String
    let role: Role
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        AnnotationEditorNativeActionButton(
            title: title,
            role: role,
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
        .frame(minWidth: 64)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAction(named: Text(title), action)
    }

}

private struct AnnotationEditorNativeActionButton: NSViewRepresentable {
    let title: String
    let role: AnnotationEditorActionButton.Role
    let accessibilityIdentifier: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> AnnotationEditorNSButton {
        let button = AnnotationEditorNSButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.masksToBounds = true
        button.setAccessibilityRole(.button)
        updateButton(button, context: context)
        return button
    }

    func updateNSView(_ button: AnnotationEditorNSButton, context: Context) {
        context.coordinator.action = action
        updateButton(button, context: context)
    }

    private func updateButton(_ button: AnnotationEditorNSButton, context: Context) {
        let colors = role.colors
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: colors.foreground
            ]
        )
        button.alignment = .center
        button.layer?.backgroundColor = colors.background.cgColor
        button.layer?.borderColor = colors.border.cgColor
        button.layer?.borderWidth = 0.8
        button.setAccessibilityIdentifier(accessibilityIdentifier)
        button.setAccessibilityLabel(title)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private final class AnnotationEditorNSButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(64, super.intrinsicContentSize.width + 10), height: AnnotationEditorActionButton.height)
    }
}

private extension AnnotationEditorActionButton.Role {
    var colors: (foreground: NSColor, background: NSColor, border: NSColor) {
        switch self {
        case .primary:
            return (
                NSColor.white.withAlphaComponent(0.96),
                NSColor(red: 0.68, green: 0.72, blue: 0.72, alpha: 0.34),
                NSColor(red: 0.68, green: 0.72, blue: 0.72, alpha: 0.36)
            )
        case .secondary:
            return (
                NSColor.white.withAlphaComponent(0.78),
                NSColor.white.withAlphaComponent(0.08),
                NSColor.white.withAlphaComponent(0.12)
            )
        case .destructive:
            return (
                NSColor.systemRed.withAlphaComponent(0.9),
                NSColor.systemRed.withAlphaComponent(0.12),
                NSColor.systemRed.withAlphaComponent(0.18)
            )
        }
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
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityIdentifier(AnnotationEditorAccessibility.textViewIdentifier)
        textView.setAccessibilityLabel("批注输入框")

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
        textView.textContainerInset = NSSize(width: 12, height: 10)
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
