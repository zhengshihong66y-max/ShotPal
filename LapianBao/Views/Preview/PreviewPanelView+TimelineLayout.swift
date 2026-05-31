//
//  PreviewPanelView+TimelineLayout.swift
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
    var previewTransportControls: some View {
        ZStack {
            HStack(spacing: 10) {
                Button {
                    controller.stepFrame(by: -1)
                } label: {
                    Image(systemName: "gobackward.1")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 28)
                }
                .help("后退一帧")

                Button {
                    controller.togglePlayback()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.14))
                        .clipShape(Circle())
                }
                .help(controller.isPlaying ? "暂停" : "播放")

                Button {
                    controller.stepFrame(by: 1)
                } label: {
                    Image(systemName: "goforward.1")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 28)
                }
                .help("前进一帧")
            }

            HStack {
                Spacer()
                Button {
                    annotationText = ""
                    isAnnotationPopoverPresented = true
                } label: {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 28)
                }
                .help("添加批注")
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white.opacity(0.76))
        .frame(maxWidth: .infinity)
        .frame(height: 38)
    }

    func videoTagStrip(for video: VideoItem) -> some View {
        let tags = libraryStore.tagsByVideoPath[video.url.path, default: []]

        return ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    PreviewTitleTagChip(tag: tag)
                }

                videoTagAddButton(for: video)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Design.previewHeaderTagRowHeight, maxHeight: Design.previewHeaderTagRowHeight, alignment: .leading)
        .scrollIndicators(.hidden)
    }

    func videoTagAddButton(for video: VideoItem) -> some View {
        Button {
            isVideoTagPopoverPresented = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 9, height: Design.previewHeaderTagRowHeight)

                if isVideoTagAddHovered {
                    Text("添加标签")
                        .font(.system(size: 9, weight: .semibold))
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, isVideoTagAddHovered ? 5 : 2)
            .frame(width: isVideoTagAddHovered ? 58 : 14, height: Design.previewHeaderTagRowHeight)
            .background(.white.opacity(isVideoTagAddHovered ? 0.11 : 0.07))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isVideoTagAddHovered = hovering
            }
        }
        .help("添加标签")
        .popover(isPresented: $isVideoTagPopoverPresented, arrowEdge: .bottom) {
            videoTagPopover(for: video)
        }
    }

    func videoTagPopover(for video: VideoItem) -> some View {
        let tags = libraryStore.tagsByVideoPath[video.url.path, default: []]

        return VStack(alignment: .leading, spacing: 10) {
            TagSuggestionGrid(currentTags: tags, suggestedTags: libraryStore.allTags) { tag in
                libraryStore.addTag(tag, to: video)
            }

            HStack(spacing: 8) {
                TextField("添加标签", text: $draftVideoTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit {
                        addDraftVideoTag(to: video)
                    }

                Button {
                    addDraftVideoTag(to: video)
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(draftVideoTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    func addDraftVideoTag(to video: VideoItem) {
        let tag = draftVideoTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        libraryStore.addTag(tag, to: video)
        draftVideoTag = ""
        isVideoTagPopoverPresented = false
    }

    func timelineStackContainer(
        for video: VideoItem,
        collapsedHeight: CGFloat,
        expandedHeight: CGFloat
    ) -> some View {
        let isExpanded = expandedPreviewTab != nil
        let height = isExpanded ? expandedHeight : collapsedHeight

        return PlaybackClockDrivenView(clock: controller.clock) { clock in
            compositeTimelineStack(for: video, expandedHeight: height, clock: clock)
        }
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .clipped()
            .overlay(alignment: .topLeading) {
                GeometryReader { overlayProxy in
                    annotationEditorOverlay(for: video, in: overlayProxy.size)
                }
                .allowsHitTesting(isAnnotationPopoverPresented)
            }
            .shadow(color: .black.opacity(isExpanded ? 0.18 : 0), radius: isExpanded ? 18 : 0, y: -4)
            .animation(timelineFadeAnimation, value: expandedPreviewTab)
    }

    @ViewBuilder
    func compositeTimelineStack(
        for video: VideoItem,
        expandedHeight: CGFloat? = nil,
        clock: PlaybackClockSnapshot
    ) -> some View {
        let detailHeight = expandedHeight.map { height in
            expandedTimelineDetailHeight(for: height)
        } ?? Design.expandedTimelineDetailHeight

        VStack(spacing: timelineLaneGap) {
            ForEach(timelineLaneOrder, id: \.self) { tab in
                timelineLaneSlot(tab, for: video, detailHeight: detailHeight, clock: clock)
            }
        }
    }

    var timelineLaneGap: CGFloat { 8 }

    var timelineLaneOrder: [PreviewTab] {
        guard let expandedPreviewTab else { return PreviewTab.allCases }
        return [expandedPreviewTab]
    }

    func expandedTimelineDetailHeight(for stackHeight: CGFloat) -> CGFloat {
        max(120, stackHeight - Design.timelineLaneHeight - 16)
    }

    @ViewBuilder
    func annotationEditorOverlay(for video: VideoItem, in size: CGSize) -> some View {
        if isAnnotationPopoverPresented {
            let anchor = annotationEditorPoint(in: size)
            annotationEditorView(for: video)
                .frame(width: Self.annotationEditorWidth)
                .background(.black.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
                .position(anchor)
                .zIndex(50)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    func annotationEditorPoint(in size: CGSize) -> CGPoint {
        let marker = annotationMarkerPoint(in: size)
        let halfWidth = Self.annotationEditorWidth / 2
        let halfHeight = Self.annotationEditorHeight / 2
        let x = min(max(marker.x, halfWidth + 6), max(halfWidth + 6, size.width - halfWidth - 6))
        let aboveY = marker.y - halfHeight - 14
        let belowY = marker.y + halfHeight + 14
        let rawY = aboveY >= halfHeight + 4 ? aboveY : belowY
        let y = min(max(rawY, halfHeight + 4), max(halfHeight + 4, size.height - halfHeight - 4))
        return CGPoint(x: x, y: y)
    }

    func annotationMarkerPoint(in size: CGSize) -> CGPoint {
        let tab = visibleAnnotationSourceTab()
        let laneHeight = Design.timelineLaneHeight
        let laneOrigin = expandedPreviewTab == nil
            ? CGFloat(timelineIndex(for: tab)) * (laneHeight + timelineLaneGap)
            : 0
        let contentFrame = timelineContentFrame(in: size, laneOrigin: laneOrigin, laneHeight: laneHeight)
        let progress = min(1, max(0, annotationEditorAnchor.progress))
        let x: CGFloat

        switch tab {
        case .frames:
            let local = (progress - timelineOffset) / max(timelineViewportSpan, 0.0001)
            x = contentFrame.minX + contentFrame.width * CGFloat(local)
        case .audio:
            let span = max(0.02, min(1, Design.centeredWaveformViewportSpan))
            let focus = min(1, max(0, controller.progress))
            x = contentFrame.midX + contentFrame.width * CGFloat((progress - focus) / span)
        case .content:
            x = contentFrame.minX + contentFrame.width * CGFloat(progress)
        }

        return CGPoint(
            x: min(max(x, contentFrame.minX + 9), contentFrame.maxX - 9),
            y: annotationMarkerY(for: annotationEditorAnchor.kind, tab: tab, in: contentFrame)
        )
    }

    func visibleAnnotationSourceTab() -> PreviewTab {
        if let expandedPreviewTab, expandedPreviewTab != annotationEditorAnchor.sourceTab {
            return expandedPreviewTab
        }
        return annotationEditorAnchor.sourceTab
    }

    func timelineContentFrame(in size: CGSize, laneOrigin: CGFloat, laneHeight: CGFloat) -> CGRect {
        let horizontalPadding: CGFloat = 8
        let headerSpacing: CGFloat = 8
        let minX = horizontalPadding + Design.timelineLaneButtonSize + headerSpacing
        let maxX = max(minX + 1, size.width - horizontalPadding)
        let sideButtonCount: CGFloat = 3
        let sideButtonsHeight = Design.timelineLaneButtonSize * sideButtonCount
        let visualGap = max(Design.timelineLaneVisualGap, (laneHeight - sideButtonsHeight) / (sideButtonCount + 1))
        let contentHeight = max(Design.timelineLaneContentHeight, laneHeight - visualGap * 2)
        let minY = laneOrigin + max(0, (laneHeight - contentHeight) / 2)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: contentHeight)
    }

    func annotationMarkerY(for kind: AnnotationItem.Kind, tab: PreviewTab, in frame: CGRect) -> CGFloat {
        switch tab {
        case .frames:
            return frame.midY + 3
        case .audio:
            return frame.midY + 4
        case .content:
            return frame.minY + annotationLaneCenter(for: kind, height: frame.height)
        }
    }

    func annotationLaneCenter(for kind: AnnotationItem.Kind, height: CGFloat) -> CGFloat {
        let margin: CGFloat = min(max(12, height * 0.16), max(12, height / 2))
        switch kind {
        case .frame:
            return margin
        case .audio:
            return height / 2
        case .content:
            return max(margin, height - margin)
        }
    }

    func timelineIndex(for tab: PreviewTab) -> Int {
        switch tab {
        case .frames: return 0
        case .audio: return 1
        case .content: return 2
        }
    }

    @ViewBuilder
    func timelineLaneSlot(
        _ tab: PreviewTab,
        for video: VideoItem,
        detailHeight: CGFloat,
        clock: PlaybackClockSnapshot
    ) -> some View {
        timelineLaneForTab(tab, for: video, detailHeight: detailHeight, clock: clock)
            .frame(height: timelineSlotHeight(for: tab, detailHeight: detailHeight), alignment: .top)
            .clipped()
            .transition(.identity)
    }

    func timelineSlotHeight(for tab: PreviewTab, detailHeight: CGFloat) -> CGFloat {
        if expandedPreviewTab == tab {
            return Design.timelineLaneHeight + detailHeight + 16
        }

        if expandedPreviewTab != nil {
            return Design.collapsedTimelineLaneHeight
        }

        return Design.timelineLaneHeight
    }

    var timelineFadeAnimation: Animation {
        .easeInOut(duration: 0.18)
    }

    @ViewBuilder
    func timelineLaneForTab(
        _ tab: PreviewTab,
        for video: VideoItem,
        detailHeight: CGFloat = Design.expandedTimelineDetailHeight,
        regularLaneHeight: CGFloat? = nil,
        clock: PlaybackClockSnapshot
    ) -> some View {
        switch tab {
        case .frames:
            timelineLane(
                tab: .frames,
                icon: previewTabIcon(.frames),
                accent: previewTabAccent(.frames),
                detailHeight: detailHeight,
                regularLaneHeight: regularLaneHeight,
                actions: {
                    trackHeaderButton(icon: "camera.fill", help: "截取当前帧") {
                        libraryStore.captureCurrentFrame(video: video, time: controller.elapsed)
                    }

                    Spacer(minLength: 0)

                    trackHeaderButton(icon: "text.bubble.fill", help: "添加批注") {
                        beginAnnotation(.frame, sourceTab: .frames)
                    }
                },
                content: {
                    frameTimeline(for: video, clock: clock)
                },
                detail: {
                    timelineDetailContent(.frames, for: video)
                }
            )
        case .audio:
            timelineLane(
                tab: .audio,
                icon: previewTabIcon(.audio),
                accent: previewTabAccent(.audio),
                detailHeight: detailHeight,
                regularLaneHeight: regularLaneHeight,
                actions: {
                    audioSelectionActionButton(for: video)

                    Spacer(minLength: 0)

                    trackHeaderButton(icon: "text.bubble.fill", help: "添加声音批注") {
                        beginAnnotation(.audio, sourceTab: .audio)
                    }
                },
                content: {
                    audioTimeline(for: video, clock: clock)
                },
                detail: {
                    audioTimelineDetailContent(for: video)
                }
            )
        case .content:
            timelineLane(
                tab: .content,
                icon: previewTabIcon(.content),
                accent: previewTabAccent(.content),
                detailHeight: detailHeight,
                regularLaneHeight: regularLaneHeight,
                actions: {
                    trackHeaderButton(icon: "square.and.arrow.up", help: "导出字幕") {
                        exportCurrentTranscript(for: video)
                    }
                    .disabled(libraryStore.transcriptSegmentsByVideoPath[video.url.path, default: []].isEmpty)

                    Spacer(minLength: 0)

                    trackHeaderButton(icon: "text.bubble.fill", help: "添加内容批注") {
                        beginAnnotation(.content, sourceTab: .content)
                    }
                },
                content: {
                    contentTimeline(for: video, clock: clock)
                },
                detail: {
                    timelineDetailContent(.content, for: video)
                }
            )
        }
    }

    func previewTabIcon(_ tab: PreviewTab) -> String {
        switch tab {
        case .frames: return "photo.on.rectangle"
        case .audio: return "waveform"
        case .content: return "text.quote"
        }
    }

    func previewTabAccent(_ tab: PreviewTab) -> Color {
        switch tab {
        case .frames: return Design.captureFrameAccent
        case .audio: return .orange
        case .content: return Design.annotationAccent
        }
    }


    func timelineLane<Content: View, Actions: View, Detail: View>(
        tab: PreviewTab,
        icon: String,
        accent: Color,
        detailHeight: CGFloat = Design.expandedTimelineDetailHeight,
        regularLaneHeight: CGFloat? = nil,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        let isExpanded = expandedPreviewTab == tab
        let isCollapsed = expandedPreviewTab != nil && !isExpanded
        let laneHeight = isCollapsed ? Design.collapsedTimelineLaneHeight : (regularLaneHeight ?? Design.timelineLaneHeight)

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                trackHeader(tab: tab, icon: icon, accent: accent, isExpanded: isExpanded, isCollapsed: isCollapsed, actions: actions)

                if !isCollapsed {
                    let sideButtonCount: CGFloat = 3
                    let sideButtonsHeight = Design.timelineLaneButtonSize * sideButtonCount
                    let visualGap = max(Design.timelineLaneVisualGap, (laneHeight - sideButtonsHeight) / (sideButtonCount + 1))
                    let contentHeight = max(Design.timelineLaneContentHeight, laneHeight - visualGap * 2)

                    content()
                        .frame(maxWidth: .infinity)
                        .frame(height: contentHeight)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(height: laneHeight)
            .padding(.horizontal, 8)

            if isExpanded {
                ZStack {
                    if visibleTimelineDetailTab == tab {
                        detail()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: detailHeight)
                .padding(.horizontal, 8)
                .padding(.top, 0)
                .padding(.bottom, 8)
                .clipped()
                .allowsHitTesting(visibleTimelineDetailTab == tab)
            }
        }
        .background(.white.opacity(isExpanded ? 0.055 : 0.035))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(isExpanded ? 0.11 : 0.07), lineWidth: 0.7)
        }
    }

    func trackHeader<Actions: View>(
        tab: PreviewTab,
        icon: String,
        accent: Color,
        isExpanded: Bool,
        isCollapsed: Bool,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Button {
                toggleExpanded(tab)
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: Design.timelineLaneButtonSize, height: Design.timelineLaneButtonSize)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "收起\(tab.rawValue)" : "展开\(tab.rawValue)")

            if !isCollapsed {
                Spacer(minLength: 0)

                actions()
            }

            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.82))
        .frame(width: Design.timelineLaneButtonSize)
        .frame(maxHeight: .infinity)
    }

    var audioSelectionButtonTitle: String {
        if audioInPoint == nil || audioOutPoint != nil { return "I" }
        return "O"
    }

    var audioSelectionButtonHelp: String {
        if audioInPoint == nil || audioOutPoint != nil { return "设置声音 In 点" }
        return "设置声音 Out 点"
    }

    func setNextAudioSelectionPoint() {
        if audioInPoint == nil || audioOutPoint != nil {
            setAudioInPoint()
        } else {
            setAudioOutPoint()
        }
    }

    func setAudioInPoint() {
        audioInPoint = controller.elapsed
        audioOutPoint = nil
    }

    func setAudioOutPoint() {
        guard audioInPoint != nil else { return }
        audioOutPoint = controller.elapsed
    }

    func clearAudioSelection() {
        audioInPoint = nil
        audioOutPoint = nil
    }

    func exportCurrentAudioSelection(for video: VideoItem) {
        guard let inT = audioInPoint, let outT = audioOutPoint else { return }
        guard libraryStore.audioClipExportProgressByVideoPath[video.url.path] == nil else { return }
        libraryStore.exportAudioClip(video: video, inTime: inT, outTime: outT)
        exportPanelFilter = .recent
        isExportPanelPresented = true
    }

    func exportCurrentTranscript(for video: VideoItem) {
        guard libraryStore.exportTranscriptMarkdown(video: video) else { return }
        exportPanelFilter = .recent
        isExportPanelPresented = true
    }

    var displayedAudioOutPoint: Double? {
        if let audioOutPoint { return audioOutPoint }
        guard audioInPoint != nil else { return nil }
        return controller.elapsed
    }

    func trackHeaderButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: Design.timelineLaneButtonSize, height: Design.timelineLaneButtonSize)
        }
        .help(help)
    }

    func trackHeaderTextButton(_ text: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption2.weight(.bold).monospaced())
                .frame(width: Design.timelineLaneButtonSize, height: Design.timelineLaneButtonSize)
        }
        .help(help)
    }

    @ViewBuilder
    func audioSelectionActionButton(for video: VideoItem) -> some View {
        if audioInPoint != nil, audioOutPoint != nil {
            trackHeaderButton(icon: "square.and.arrow.up", help: "导出选区音频") {
                exportCurrentAudioSelection(for: video)
            }
            .disabled(libraryStore.audioClipExportProgressByVideoPath[video.url.path] != nil)
        } else {
            trackHeaderTextButton(audioSelectionButtonTitle, help: audioSelectionButtonHelp) {
                setNextAudioSelectionPoint()
            }
        }
    }


    func toggleExpanded(_ tab: PreviewTab) {
        let nextExpandedTab: PreviewTab? = expandedPreviewTab == tab ? nil : tab

        withAnimation(timelineFadeAnimation) {
            activePreviewTab = tab
            expandedPreviewTab = nextExpandedTab
            visibleTimelineDetailTab = nextExpandedTab
            if let nextExpandedTab, isAnnotationPopoverPresented, annotationEditorAnchor.sourceTab != nextExpandedTab {
                isAnnotationPopoverPresented = false
                editingAnnotationID = nil
            }
        }

        if nextExpandedTab != nil {
            startRecognitionForVisibleTimelineIfNeeded(tab: tab)
        }
    }
}
