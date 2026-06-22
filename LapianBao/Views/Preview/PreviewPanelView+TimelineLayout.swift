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

                Button {
                    controller.togglePlayback()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.14))
                        .clipShape(Circle())
                }

                Button {
                    controller.stepFrame(by: 1)
                } label: {
                    Image(systemName: "goforward.1")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 28)
                }
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
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white.opacity(0.76))
        .frame(maxWidth: .infinity)
        .frame(height: 38)
    }

    func timelineTransportBar(for video: VideoItem, clock: PlaybackClockSnapshot) -> some View {
        HStack(spacing: 0) {
            timelineTransportTimecode(clock: clock)
                .layoutPriority(1)

            Spacer(minLength: transportSectionSpacing)

            timelineTransportPlaybackControls()
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: transportSectionSpacing)

            timelineTransportFunctionControls(for: video)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)
    }

    var transportSectionSpacing: CGFloat { 24 }
    var transportButtonSpacing: CGFloat { 22 }
    var transportFunctionButtonSpacing: CGFloat { 18 }
    var transportButtonSize: CGFloat { 22 }

    func timelineTransportTimecode(clock: PlaybackClockSnapshot) -> some View {
        Text("\(timelineFrameTimecode(clock.elapsed)) / \(timelineFrameTimecode(controller.duration))")
            .font(Design.numericFont(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(height: transportButtonSize, alignment: .leading)
    }

    func timelineTransportPlaybackControls() -> some View {
        let isPlaybackHighlighted = activeTransportShortcutFeedback == .playback

        return HStack(spacing: transportButtonSpacing) {
            TimelineShuttleButton(
                direction: .backward,
                size: transportButtonSize,
                isHighlighted: activeTransportShortcutFeedback == .backward,
                help: "J 后退一帧；按住连续后退",
                step: {
                    flashTransportShortcutFeedback(.backward)
                    controller.stepFrame(by: -1)
                },
                startShuttle: { startKeyboardShuttle(direction: -1) },
                stopShuttle: { stopKeyboardShuttle() }
            )

            Button {
                togglePreviewPlayback()
                flashTransportShortcutFeedback(.playback)
            } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(isPlaybackHighlighted ? 0.96 : 0.76))
                    .frame(width: transportButtonSize, height: transportButtonSize)
                    .contentShape(Rectangle())
                    .shadow(color: .white.opacity(isPlaybackHighlighted ? 0.32 : 0), radius: 5)
                    .animation(.easeOut(duration: 0.08), value: isPlaybackHighlighted)
            }
            .buttonStyle(.plain)

            TimelineShuttleButton(
                direction: .forward,
                size: transportButtonSize,
                isHighlighted: activeTransportShortcutFeedback == .forward,
                help: "L 前进一帧；按住连续前进",
                step: {
                    flashTransportShortcutFeedback(.forward)
                    controller.stepFrame(by: 1)
                },
                startShuttle: { startKeyboardShuttle(direction: 1) },
                stopShuttle: { stopKeyboardShuttle() }
            )
        }
    }

    func timelineTransportFunctionControls(for video: VideoItem) -> some View {
        HStack(spacing: transportFunctionButtonSpacing) {
            timelineTransportIconButton(
                icon: previewTabIcon(.frames),
                progress: frameTimelineRecognitionProgress(for: video),
                isActive: expandedPreviewTab == .frames || activeTransportShortcutFeedback == .framesTimeline,
                help: expandedPreviewTab == .frames ? "收起画面时间线" : "展开画面时间线"
            ) {
                toggleExpanded(.frames)
                flashTransportShortcutFeedback(.framesTimeline)
            }

            timelineTransportIconButton(
                icon: "camera.fill",
                isActive: activeTransportShortcutFeedback == .screenshot,
                help: "截取当前帧"
            ) {
                libraryStore.captureCurrentFrame(video: video, time: controller.elapsed)
                flashTransportShortcutFeedback(.screenshot)
            }

            timelineTransportIconButton(
                icon: previewTabIcon(.content),
                progress: contentTimelineRecognitionProgress(for: video),
                isActive: expandedPreviewTab == .audio || activeTransportShortcutFeedback == .contentTimeline,
                help: expandedPreviewTab == .audio ? "收起内容时间线" : "展开内容时间线"
            ) {
                toggleExpanded(.audio)
                flashTransportShortcutFeedback(.contentTimeline)
            }

            timelineTransportSelectionButton(
                isActive: audioInPoint != nil || activeTransportShortcutFeedback == .io,
                help: audioSelectionButtonHelp
            ) {
                setNextAudioSelectionPoint()
                flashTransportShortcutFeedback(.io)
            }

            timelineTransportIconButton(
                icon: "text.bubble.fill",
                isActive: isAnnotationPopoverPresented || activeTransportShortcutFeedback == .annotation,
                help: "添加批注"
            ) {
                beginTimelineAnnotation()
                flashTransportShortcutFeedback(.annotation)
            }
        }
    }

    func timelineTransportIconButton(
        icon: String,
        progress: Double? = nil,
        isActive: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        let isShowingProgress = progress != nil
        let isHighlighted = isActive || isShowingProgress

        return Button(action: action) {
            Group {
                if let progress {
                    Text(progressPercentText(progress))
                        .font(Design.numericFont(size: 9.5, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.54)
                        .monospacedDigit()
                        .transition(.opacity)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .transition(.opacity)
                }
            }
            .foregroundStyle(isHighlighted ? .white.opacity(0.94) : .white.opacity(0.62))
            .frame(width: transportButtonSize, height: transportButtonSize)
            .contentShape(Rectangle())
            .shadow(color: .white.opacity(isHighlighted ? 0.28 : 0), radius: 4)
            .animation(.easeOut(duration: 0.08), value: isHighlighted)
            .animation(.easeOut(duration: 0.12), value: isShowingProgress)
        }
        .buttonStyle(.plain)
    }

    func frameTimelineRecognitionProgress(for video: VideoItem) -> Double? {
        guard let progress = libraryStore.sceneDetectionProgress[video.url.path] else { return nil }
        return normalizedProgressFraction(progress)
    }

    func contentTimelineRecognitionProgress(for video: VideoItem) -> Double? {
        guard case let .running(message) = libraryStore.transcriptStatusByVideoPath[video.url.path] else {
            return nil
        }
        return activityProgressValue(from: message) ?? 0
    }

    func timelineTransportSelectionButton(
        isActive: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            TimelineRangeSelectionIcon(isActive: isActive)
                .frame(width: transportButtonSize, height: transportButtonSize)
                .contentShape(Rectangle())
                .shadow(color: .white.opacity(isActive ? 0.28 : 0), radius: 4)
                .animation(.easeOut(duration: 0.08), value: isActive)
        }
        .buttonStyle(.plain)
    }

    func timelineFrameTimecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--:--" }
        let fps = max(1, Int(controller.frameRate.rounded()))
        let totalFrames = max(0, Int((seconds * Double(fps)).rounded(.down)))
        let frame = totalFrames % fps
        let totalSeconds = totalFrames / fps
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frame)
        }
        return String(format: "%02d:%02d:%02d", minutes, secs, frame)
    }

    func videoTagStrip(for video: VideoItem) -> some View {
        let tags = libraryStore.videoTags(for: video)

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
            CenteredPlusGlyph(size: 7.4, thickness: 1.25)
                .foregroundStyle(.secondary)
                .frame(
                    width: Design.previewHeaderTagRowHeight,
                    height: Design.previewHeaderTagRowHeight,
                    alignment: .center
                )
                .background(.white.opacity(0.07))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .popover(isPresented: $isVideoTagPopoverPresented, arrowEdge: .bottom) {
            videoTagPopover(for: video)
        }
    }

    func videoTagPopover(for video: VideoItem) -> some View {
        let tags = libraryStore.videoTags(for: video)

        return TagEditorSection(
            domain: .video,
            tags: tags,
            suggestedTags: libraryStore.videoTagSuggestions(for: video),
            chipSize: .compact,
            verticalSpacing: 0,
            inputSpacing: 2,
            gridVerticalPadding: 0,
            onAdd: { tag in
                libraryStore.addTag(tag, to: video)
            },
            onRemove: { tag in
                libraryStore.removeTag(tag, from: video)
            }
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    func timelineStackContainer(
        for video: VideoItem,
        collapsedHeight: CGFloat,
        expandedHeight: CGFloat
    ) -> some View {
        let isExpanded = expandedPreviewTab != nil
        let height = isExpanded ? expandedHeight : collapsedHeight
        let laneAreaHeight = max(
            previewTimelineLaneHeight,
            height - previewTimelineTransportHeight - timelineLaneGap
        )

        return PlaybackClockDrivenView(
            clock: controller.clock,
            duration: controller.duration,
            playbackRate: controller.playbackRate,
            isPlaying: controller.isPlaying
        ) { clock in
            VStack(spacing: timelineLaneGap) {
                timelineTransportBar(for: video, clock: clock)
                    .frame(maxWidth: .infinity)
                    .frame(height: previewTimelineTransportHeight)

                compositeTimelineStack(for: video, expandedHeight: laneAreaHeight, clock: clock)
                    .frame(maxWidth: .infinity)
                    .frame(height: laneAreaHeight, alignment: .bottom)
            }
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
            .animation(timelineExpansionAnimation, value: expandedPreviewTab)
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

    var previewTimelineVisibleTabs: [PreviewTab] {
        [.frames, .audio]
    }

    var previewTimelineTransportHeight: CGFloat { 22 }

    var previewTimelineLaneStackTopInset: CGFloat {
        previewTimelineTransportHeight + timelineLaneGap
    }

    var previewTimelineLaneHeight: CGFloat {
        let available = collapsedPreviewTimelineStackHeight - previewTimelineTransportHeight - timelineLaneGap * 2
        return max(112, available / 2)
    }

    var previewTimelineLaneContentHeight: CGFloat {
        timelineLaneContentHeight(for: previewTimelineLaneHeight)
    }

    var timelineLaneOrder: [PreviewTab] {
        guard let expandedPreviewTab else { return previewTimelineVisibleTabs }
        guard previewTimelineVisibleTabs.contains(expandedPreviewTab) else { return previewTimelineVisibleTabs }
        return [expandedPreviewTab]
    }

    func timelineLaneContentHeight(for laneHeight: CGFloat) -> CGFloat {
        max(Design.timelineLaneContentHeight, laneHeight - Design.timelineLaneVisualGap * 2)
    }

    func expandedTimelineDetailHeight(for stackHeight: CGFloat) -> CGFloat {
        max(120, stackHeight - 16)
    }

    @ViewBuilder
    func annotationEditorOverlay(for video: VideoItem, in size: CGSize) -> some View {
        if isAnnotationPopoverPresented {
            let marker = annotationMarkerPoint(in: size)
            let anchor = annotationEditorPoint(in: size)

            ZStack(alignment: .topLeading) {
                annotationEditorConnector(from: anchor, to: marker)

                annotationEditorView(for: video)
                    .frame(width: Self.annotationEditorWidth, height: Self.annotationEditorHeight)
                    .background(.black.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 0.8)
                    }
                    .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
                    .position(anchor)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .zIndex(50)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    func annotationEditorConnector(from editorCenter: CGPoint, to marker: CGPoint) -> some View {
        let editorRect = CGRect(
            x: editorCenter.x - Self.annotationEditorWidth / 2,
            y: editorCenter.y - Self.annotationEditorHeight / 2,
            width: Self.annotationEditorWidth,
            height: Self.annotationEditorHeight
        )
        let start = annotationConnectorStart(from: editorRect, to: marker)

        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: start)
                path.addLine(to: marker)
            }
            .stroke(
                Design.annotationAccent.opacity(0.88),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            )

            Circle()
                .fill(Design.annotationAccent.opacity(0.96))
                .frame(width: 8, height: 8)
                .position(marker)

            Circle()
                .stroke(Design.annotationAccent.opacity(0.36), lineWidth: 1)
                .frame(width: 16, height: 16)
                .position(marker)
        }
        .allowsHitTesting(false)
    }

    func annotationConnectorStart(from editorRect: CGRect, to marker: CGPoint) -> CGPoint {
        let center = CGPoint(x: editorRect.midX, y: editorRect.midY)
        let dx = marker.x - center.x
        let dy = marker.y - center.y
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return center }

        let scaleX = abs(dx) > 0.001 ? (editorRect.width / 2) / abs(dx) : CGFloat.greatestFiniteMagnitude
        let scaleY = abs(dy) > 0.001 ? (editorRect.height / 2) / abs(dy) : CGFloat.greatestFiniteMagnitude
        let scale = min(scaleX, scaleY)

        return CGPoint(
            x: center.x + dx * scale,
            y: center.y + dy * scale
        )
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
        let laneHeight = previewTimelineLaneHeight
        let laneOrigin = previewTimelineLaneStackTopInset + (expandedPreviewTab == nil
            ? CGFloat(timelineIndex(for: tab)) * (laneHeight + timelineLaneGap)
            : 0)
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
        if annotationEditorAnchor.sourceTab == .content {
            return .audio
        }
        return annotationEditorAnchor.sourceTab
    }

    func timelineContentFrame(in size: CGSize, laneOrigin: CGFloat, laneHeight: CGFloat) -> CGRect {
        let horizontalPadding: CGFloat = 8
        let minX = horizontalPadding
        let maxX = max(minX + 1, size.width - horizontalPadding)
        let contentHeight = timelineLaneContentHeight(for: laneHeight)
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
        case .content: return 1
        }
    }

    @ViewBuilder
    func timelineLaneSlot(
        _ tab: PreviewTab,
        for video: VideoItem,
        detailHeight: CGFloat,
        clock: PlaybackClockSnapshot
    ) -> some View {
        timelineLaneForTab(
            tab,
            for: video,
            detailHeight: detailHeight,
            regularLaneHeight: previewTimelineLaneHeight,
            clock: clock
        )
            .frame(height: timelineSlotHeight(for: tab, detailHeight: detailHeight), alignment: .top)
            .clipped()
            .zIndex(timelineLaneZIndex(for: tab))
            .transition(timelineLaneTransition(for: tab))
    }

    func timelineSlotHeight(for tab: PreviewTab, detailHeight: CGFloat) -> CGFloat {
        if expandedPreviewTab == tab {
            return detailHeight + 16
        }

        if expandedPreviewTab != nil {
            return Design.collapsedTimelineLaneHeight
        }

        return previewTimelineLaneHeight
    }

    var timelineFadeAnimation: Animation {
        timelineExpansionAnimation
    }

    var timelineExpansionAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.08)
    }

    var timelineDetailAnimation: Animation {
        .easeOut(duration: 0.18).delay(0.05)
    }

    func timelineLaneZIndex(for tab: PreviewTab) -> Double {
        if expandedPreviewTab == tab { return 10 }
        return Double(previewTimelineVisibleTabs.count - timelineIndex(for: tab))
    }

    func timelineLaneTransition(for tab: PreviewTab) -> AnyTransition {
        let removalEdge = timelineRemovalEdge(for: tab)
        let insertion = AnyTransition.opacity
            .combined(with: .scale(scale: 0.985, anchor: .top))
        let removal = AnyTransition.opacity
            .combined(with: .scale(scale: 0.985, anchor: .center))
            .combined(with: .move(edge: removalEdge))
        return .asymmetric(insertion: insertion, removal: removal)
    }

    func timelineRemovalEdge(for tab: PreviewTab) -> Edge {
        guard let expandedPreviewTab else { return .bottom }
        return timelineIndex(for: tab) < timelineIndex(for: expandedPreviewTab) ? .top : .bottom
    }

    var timelineDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .opacity
                .combined(with: .scale(scale: 0.99, anchor: .top))
        )
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
                detailHeight: detailHeight,
                regularLaneHeight: regularLaneHeight,
                content: {
                    frameTimeline(for: video, clock: clock)
                },
                detail: {
                    frameTimelineDetailContent(
                        for: video,
                        activeProgressTick: sceneGridProgressTick(clock.elapsed)
                    )
                }
            )
        case .audio:
            timelineLane(
                tab: .audio,
                detailHeight: detailHeight,
                regularLaneHeight: regularLaneHeight,
                content: {
                    audioTimeline(for: video, clock: clock)
                },
                detail: {
                    contentTimelineDetailContent(for: video)
                }
            )
        case .content:
            timelineLane(
                tab: .content,
                detailHeight: detailHeight,
                regularLaneHeight: regularLaneHeight,
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

    func sceneGridProgressTick(_ elapsed: Double) -> Double {
        guard elapsed.isFinite else { return 0 }
        return (elapsed * 12).rounded() / 12
    }

    func timelineLane<Content: View, Detail: View>(
        tab: PreviewTab,
        detailHeight: CGFloat = Design.expandedTimelineDetailHeight,
        regularLaneHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        let isExpanded = expandedPreviewTab == tab
        let isCollapsed = expandedPreviewTab != nil && !isExpanded
        let laneHeight = isCollapsed ? Design.collapsedTimelineLaneHeight : (regularLaneHeight ?? Design.timelineLaneHeight)

        return VStack(spacing: 0) {
            if !isExpanded {
                ZStack {
                    if !isCollapsed {
                        let contentHeight = timelineLaneContentHeight(for: laneHeight)

                        content()
                            .frame(maxWidth: .infinity)
                            .frame(height: contentHeight)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(height: laneHeight)
                .padding(.horizontal, 8)
            }

            if isExpanded {
                ZStack {
                    if visibleTimelineDetailTab == tab {
                        detail()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(timelineDetailTransition)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: detailHeight)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .clipped()
                .allowsHitTesting(visibleTimelineDetailTab == tab)
                .animation(timelineDetailAnimation, value: visibleTimelineDetailTab)
            }
        }
        .background(.white.opacity(isExpanded ? 0.055 : 0.035))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(isExpanded ? 0.11 : 0.07), lineWidth: 0.7)
        }
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

    func exportCurrentStoryboard(for video: VideoItem) {
        if !libraryStore.hasSceneRecognitionResult(for: video) {
            pendingStoryboardExportPath = video.url.path
            startSceneRecognitionIfNeeded(for: video)
            return
        }

        guard exportStoryboardDocumentIfPossible(for: video) else { return }
        exportPanelFilter = .recent
        isExportPanelPresented = true
    }

    @discardableResult
    func exportStoryboardDocumentIfPossible(for video: VideoItem) -> Bool {
        let path = video.url.path
        guard libraryStore.sceneDetectionProgress[path] == nil else { return false }
        guard libraryStore.sceneDetectionErrorByVideoPath[path] == nil else { return false }
        return libraryStore.exportStoryboardDocument(video: video)
    }

    func completePendingStoryboardExportIfReady() {
        guard
            let path = pendingStoryboardExportPath,
            libraryStore.sceneDetectionProgress[path] == nil
        else { return }

        if libraryStore.sceneDetectionErrorByVideoPath[path] != nil {
            pendingStoryboardExportPath = nil
            return
        }

        let video = libraryStore.videos.first { $0.url.path == path }
            ?? (libraryStore.selectedVideo?.url.path == path ? libraryStore.selectedVideo : nil)
        guard let video, libraryStore.hasSceneRecognitionResult(for: video) else { return }

        pendingStoryboardExportPath = nil
        guard exportStoryboardDocumentIfPossible(for: video) else { return }
        exportPanelFilter = .recent
        isExportPanelPresented = true
    }

    func beginTimelineAnnotation() {
        switch expandedPreviewTab ?? activePreviewTab {
        case .frames:
            beginAnnotation(.frame, sourceTab: .frames)
        case .audio, .content:
            beginAnnotation(.content, sourceTab: .audio)
        }
    }

    var displayedAudioOutPoint: Double? {
        if let audioOutPoint { return audioOutPoint }
        guard audioInPoint != nil else { return nil }
        return controller.elapsed
    }


    func toggleExpanded(_ tab: PreviewTab) {
        if expandedPreviewTab == tab {
            applyExpandedTimeline(nil, activeTab: tab)
            return
        }

        if tab == .frames,
           let video = libraryStore.selectedVideo,
           shouldDelayFrameTimelineExpansion(for: video) {
            pendingTimelineExpansionTab = .frames
            pendingTimelineExpansionVideoPath = video.url.path
            libraryStore.detectSceneCuts(for: video)
            return
        }

        if tab == .audio,
           let video = libraryStore.selectedVideo,
           shouldDelayContentTimelineExpansion(for: video) {
            pendingTimelineExpansionTab = .audio
            pendingTimelineExpansionVideoPath = video.url.path
            startContentRecognitionIfNeeded(for: video)
            return
        }

        applyExpandedTimeline(tab, activeTab: tab)
    }

    func applyExpandedTimeline(_ nextExpandedTab: PreviewTab?, activeTab tab: PreviewTab) {
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

    func shouldDelayFrameTimelineExpansion(for video: VideoItem) -> Bool {
        let path = video.url.path
        libraryStore.loadCachedSceneCuts(for: video)
        return libraryStore.sceneCutsByVideoPath[path] == nil
    }

    func shouldDelayContentTimelineExpansion(for video: VideoItem) -> Bool {
        let path = video.url.path
        if !libraryStore.transcriptSegmentsByVideoPath[path, default: []].isEmpty {
            return false
        }
        if case .failed = libraryStore.transcriptStatusByVideoPath[path] {
            return false
        }
        if case .completed = libraryStore.transcriptStatusByVideoPath[path] {
            return false
        }
        return true
    }

    func completePendingTimelineExpansionIfReady() {
        guard
            let pendingTab = pendingTimelineExpansionTab,
            let pendingPath = pendingTimelineExpansionVideoPath,
            let video = libraryStore.selectedVideo,
            video.url.path == pendingPath
        else { return }

        switch pendingTab {
        case .frames:
            guard
                libraryStore.sceneDetectionProgress[pendingPath] == nil,
                libraryStore.sceneCutsByVideoPath[pendingPath] != nil
            else { return }
        case .audio:
            if !libraryStore.transcriptSegmentsByVideoPath[pendingPath, default: []].isEmpty {
                break
            }
            if case .failed = libraryStore.transcriptStatusByVideoPath[pendingPath] {
                return
            }
            guard !timelineTranscriptRecognitionIsRunning(for: pendingPath) else { return }
        case .content:
            return
        }

        pendingTimelineExpansionTab = nil
        pendingTimelineExpansionVideoPath = nil
        applyExpandedTimeline(pendingTab, activeTab: pendingTab)
    }

    func timelineTranscriptRecognitionIsRunning(for path: String) -> Bool {
        if case .running = libraryStore.transcriptStatusByVideoPath[path] {
            return true
        }
        return false
    }
}

private struct TimelineRangeSelectionIcon: View {
    let isActive: Bool

    var body: some View {
        let color = Color.white.opacity(isActive ? 0.94 : 0.62)

        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let rectWidth = side * 0.66
            let rectHeight = side * 0.46
            let handleWidth = max(1.4, side * 0.07)
            let handleHeight = side * 0.66

            ZStack {
                RoundedRectangle(cornerRadius: side * 0.08, style: .continuous)
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: max(1.2, side * 0.07),
                            dash: [side * 0.14, side * 0.09],
                            dashPhase: side * 0.02
                        )
                    )
                    .frame(width: rectWidth, height: rectHeight)

                Capsule()
                    .fill(color)
                    .frame(width: handleWidth, height: handleHeight)
                    .offset(x: -rectWidth / 2)

                Capsule()
                    .fill(color)
                    .frame(width: handleWidth, height: handleHeight)
                    .offset(x: rectWidth / 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

private struct TimelineShuttleButton: View {
    enum Direction {
        case backward
        case forward
    }

    let direction: Direction
    let size: CGFloat
    let isHighlighted: Bool
    let help: String
    let step: () -> Void
    let startShuttle: () -> Void
    let stopShuttle: () -> Void

    @State private var isPressing = false
    @State private var didStartShuttle = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        let isActive = isPressing || isHighlighted

        Image(systemName: icon)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white.opacity(isActive ? 0.96 : 0.62))
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .shadow(color: .white.opacity(isActive ? 0.32 : 0), radius: 5)
            .animation(.easeOut(duration: 0.08), value: isActive)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        beginPressIfNeeded()
                    }
                    .onEnded { _ in
                        endPress()
                    }
            )
            .onDisappear {
                cancelHold()
                if didStartShuttle {
                    stopShuttle()
                }
                isPressing = false
                didStartShuttle = false
            }
            .accessibilityLabel(Text(help))
            .accessibilityAddTraits(.isButton)
    }

    private var icon: String {
        switch direction {
        case .backward: return "backward.fill"
        case .forward: return "forward.fill"
        }
    }

    private func beginPressIfNeeded() {
        guard !isPressing else { return }
        isPressing = true
        didStartShuttle = false
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, isPressing else { return }
            didStartShuttle = true
            startShuttle()
        }
    }

    private func endPress() {
        cancelHold()
        if didStartShuttle {
            stopShuttle()
        } else {
            step()
        }
        isPressing = false
        didStartShuttle = false
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
    }
}
