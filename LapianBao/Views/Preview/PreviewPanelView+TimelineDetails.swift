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
            ScenePanelView(
                video: video,
                controller: controller,
                sceneCuts: libraryStore.sceneCutsByVideoPath[video.url.path] ?? [],
                hasSceneRecognitionResult: libraryStore.sceneCutsByVideoPath[video.url.path] != nil,
                sceneDetectionProgress: libraryStore.sceneDetectionProgress[video.url.path],
                sceneThumbnailVersion: libraryStore.sceneThumbnailVersionsByVideoPath[video.url.path] ?? 0,
                sceneThumbnailsNeedHydration: libraryStore.sceneThumbnailsNeedHydration(for: video),
                isHydratingSceneThumbnails: libraryStore.isHydratingSceneThumbnails(for: video),
                sampledFrames: libraryStore.sampledFrames(for: video),
                activeItemID: activeSceneItemID(for: video),
                openStoryboardBoard: { openStoryboardBoard(video) }
            )
            .equatable()
        case .audio, .content:
            if tab == .audio {
                audioTimelineDetailContent(for: video)
            } else {
                contentTimelineDetailContent(for: video)
            }
        }
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
            HStack(alignment: .top, spacing: Self.contentTimelineDetailBlockGap) {
                subtitleTimelineBlock(for: video)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                videoNodeTimelineBlock(for: video)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    func contentRecognitionStartBlock(for video: VideoItem, status: TranscriptJobStatus?) -> some View {
        if case let .running(message) = status {
            timelineProgressRow(message)
        } else if case let .failed(message) = status {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Color.red.opacity(0.86))
                .multilineTextAlignment(.center)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            timelineProgressRow("准备字幕分析…")
        }
    }

    @ViewBuilder
    func subtitleTimelineBlock(for video: VideoItem) -> some View {
        let path = video.url.path
        let status = libraryStore.transcriptStatusByVideoPath[path]
        let segments = libraryStore.transcriptSegmentsByVideoPath[path, default: []]

        VStack(alignment: .leading, spacing: 8) {
            if case let .running(message) = status {
                timelineProgressRow(message)

                if !segments.isEmpty {
                    subtitleSegmentList(segments)
                }
            } else if segments.isEmpty {
                VStack(spacing: 10) {
                    if case let .failed(message) = status {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Color.red.opacity(0.86))
                            .multilineTextAlignment(.center)
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
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    func videoNodeTimelineBlock(for video: VideoItem) -> some View {
        let segments = libraryStore.transcriptSegmentsByVideoPath[video.url.path, default: []]
        let chapters = loadedContentNodeChapters(for: video)

        VStack(alignment: .leading, spacing: 8) {
            switch contentNodeTimelineStatus {
            case let .running(videoPath) where videoPath == video.url.path:
                timelineProgressRow("正在整理视频节点…")
            case let .failed(videoPath, message) where videoPath == video.url.path:
                VStack(spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.red.opacity(0.86))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            default:
                if chapters.isEmpty {
                    if segments.isEmpty {
                        timelineProgressRow("等待字幕生成…")
                    } else {
                        timelineContentNodePrompt(video: video, segments: segments)
                    }
                } else {
                    videoNodeList(chapters, video: video)
                }
            }
        }
        .padding(Self.contentTimelineDetailBlockPadding)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func timelineProgressRow(_ message: String) -> some View {
        RecognitionProgressRow(
            message: message,
            progress: activityProgressValue(from: message)
        )
        .recognitionProgressCard()
    }

    func timelineContentNodePrompt(video: VideoItem, segments: [TranscriptSegment]) -> some View {
        VStack(spacing: 10) {
            Button {
                generateContentNodeTimeline(video: video, segments: segments)
            } label: {
                Label("生成视频节点", systemImage: "sparkles")
            }
            .buttonStyle(.borderless)
            .help("使用本机 Ollama 文本模型把字幕整理成视频节点")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                                    .font(.caption2.monospacedDigit().weight(.semibold))
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
            }
            .onChange(of: activeTranscriptSegmentID) { _, newID in
                if let newID {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
    }

    func videoNodeList(_ chapters: [TranscriptTimelineChapter], video: VideoItem) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 7) {
                ForEach(chapters) { chapter in
                    let isActive = isActiveContentNode(chapter, in: chapters)
                    Button {
                        activeTranscriptSegmentID = chapter.segmentID
                        controller.pause()
                        controller.seekToSeconds(chapter.start)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(formatDuration(chapter.start))
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundStyle(Design.annotationAccent)
                                if let end = chapter.end {
                                    Text("- \(formatDuration(end))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Text(chapter.type)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Text(chapter.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(chapter.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(isActive ? Color.white.opacity(0.12) : Color.white.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(.white.opacity(isActive ? 0.24 : 0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(chapter.summary)
                }
            }
        }
    }

    func loadedContentNodeChapters(for video: VideoItem) -> [TranscriptTimelineChapter] {
        if case let .loaded(videoPath, chapters) = contentNodeTimelineStatus,
           videoPath == video.url.path {
            return chapters
        }
        return []
    }

    func isActiveContentNode(_ chapter: TranscriptTimelineChapter, in chapters: [TranscriptTimelineChapter]) -> Bool {
        let elapsed = controller.elapsed
        if elapsed >= chapter.start, elapsed <= (chapter.end ?? controller.duration) {
            return true
        }
        guard chapter.end == nil else { return false }
        return chapters.last { $0.start <= elapsed }?.id == chapter.id
    }

    func canSeekAdjacentContentChapter(for video: VideoItem, direction: Int) -> Bool {
        adjacentContentChapter(for: video, direction: direction) != nil
    }

    func seekAdjacentContentChapter(for video: VideoItem, direction: Int) {
        guard let chapter = adjacentContentChapter(for: video, direction: direction) else { return }
        activeTranscriptSegmentID = chapter.segmentID
        controller.seekToSeconds(chapter.start)
    }

    func adjacentContentChapter(for video: VideoItem, direction: Int) -> TranscriptTimelineChapter? {
        let chapters = loadedContentNodeChapters(for: video).sorted { $0.start < $1.start }
        guard !chapters.isEmpty else { return nil }

        let elapsed = controller.elapsed
        let currentIndex = chapters.lastIndex { $0.start <= elapsed + 0.1 }

        if direction < 0 {
            guard let currentIndex else { return nil }
            let targetIndex = max(0, currentIndex - 1)
            return targetIndex == currentIndex ? nil : chapters[targetIndex]
        }

        if let currentIndex {
            let targetIndex = currentIndex + 1
            return chapters.indices.contains(targetIndex) ? chapters[targetIndex] : nil
        }

        return chapters.first
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
        case .content:
            startContentRecognitionIfNeeded(for: video)
        case .audio, .none:
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
            libraryStore.sceneDetectionProgress[path] == nil
        else { return }

        libraryStore.detectSceneCuts(for: video)
    }

    func startContentRecognitionIfNeeded(for video: VideoItem) {
        let path = video.url.path
        let segments = libraryStore.transcriptSegmentsByVideoPath[path, default: []]

        if segments.isEmpty {
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

    func generateContentNodeTimeline(video: VideoItem, segments: [TranscriptSegment]) {
        guard !segments.isEmpty else { return }
        let authorName = libraryStore.videoAuthorName(for: video)
        contentNodeTimelineStatus = .running(videoPath: video.url.path)
        libraryStore.prepareExternalServiceWork()

        Task {
            do {
                let chapters = try await LocalTranscriptTimelineAnalyzer.analyze(
                    videoName: video.name,
                    videoAuthor: authorName,
                    segments: segments
                )
                await MainActor.run {
                    contentNodeTimelineStatus = .loaded(videoPath: video.url.path, chapters: chapters)
                }
            } catch {
                await MainActor.run {
                    contentNodeTimelineStatus = .failed(videoPath: video.url.path, message: LocalTranscriptTimelineAnalyzer.userFacingMessage(for: error))
                }
            }
        }
    }

    func frameTimeline(for video: VideoItem, clock: PlaybackClockSnapshot) -> some View {
        let cuts = libraryStore.sceneCutsByVideoPath[video.url.path] ?? []

        return FrameScrubberView(
            frames: frameStripImages(for: video),
            progress: clock.progress,
            timecodeText: clock.timecodeText,
            sceneCuts: sceneStoryboardCuts(for: video),
            isPlaying: controller.isPlaying,
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
            timelineHeight: Design.timelineLaneContentHeight,
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
            chapters: loadedContentNodeChapters(for: video),
            duration: controller.duration,
            annotationItems: normalizedAnnotations(for: video),
            onAnnotationSelect: { openAnnotation($0, sourceTab: .content) },
            playheadTint: Design.timelinePlayheadAccent,
            stepBack: { controller.stepFrame(by: -1) },
            stepForward: { controller.stepFrame(by: 1) },
            onScreenshot: { libraryStore.captureCurrentFrame(video: video, time: controller.elapsed) },
            onAnnotate: { beginAnnotation(.content, sourceTab: .content) }
        )
    }

    func openDetailWorkspace(_ workspace: AppWorkspace) {
        switch workspace {
        case .frames:
            activePreviewTab = .frames
        case .audio:
            activePreviewTab = .audio
        case .content:
            activePreviewTab = .content
        case .home, .music, .settings:
            break
        }
        openWorkspace(workspace)
    }

    func annotationEditorView(for video: VideoItem) -> some View {
        let editingAnnotation = editingAnnotation(for: video)
        let title = editingAnnotation.map { "编辑\($0.kind.title)批注" }
            ?? "添加\(pendingAnnotationKind.title)批注 · \(previewTimecodeText)"

        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            TextEditor(text: $annotationText)
                .frame(width: 260, height: 88)
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
