//
//  PreviewPanelView.swift
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

enum PreviewTransportShortcutFeedback: Equatable {
    case playback
    case backward
    case forward
    case framesTimeline
    case contentTimeline
    case screenshot
    case io
    case annotation
}

// MARK: - PreviewPanelView
/// 预览面板：使用 @StateObject controller 驱动播放，
/// 场景网格由 ScenePanelView（Equatable）单独渲染，与 Timer 完全解耦。
struct PreviewPanelView: View {
    @EnvironmentObject var libraryStore: LibraryStore
    @ObservedObject var controller: PreviewController
    let openStoryboardBoard: (VideoItem) -> Void
    @Binding var pendingSeekRequest: AppEventBus.SeekRequest?
    @Binding var pendingExportPanelRequest: AppEventBus.ExportPanelRequest?
    @Namespace var tabNamespace
    static let contentTimelineDetailBlockGap: CGFloat = 8
    static let contentTimelineDetailBlockPadding: CGFloat = 8
    static let annotationEditorWidth: CGFloat = 336
    static let annotationEditorHeight: CGFloat = 226
    static let exportActionButtonSize: CGFloat = 22
    static let exportRowContentHeight: CGFloat = 78
    static let exportRowVerticalPadding: CGFloat = 10
    static let exportRowHeight: CGFloat = exportRowContentHeight + exportRowVerticalPadding * 2
    static let exportFramePreviewWidth: CGFloat = 100
    static let exportFramePreviewMinWidth: CGFloat = 48
    static let exportFramePreviewMaxWidth: CGFloat = 142
    static let exportTranscriptIconWidth: CGFloat = exportFramePreviewWidth
    static let exportPanelRecentItemLimit = 120
    @State var activePreviewTab: PreviewTab = .frames
    @State var annotationText = ""
    @State var pendingAnnotationKind: AnnotationItem.Kind = .frame
    @State var editingAnnotationID: UUID?
    @State var isAnnotationPopoverPresented = false
    @State var annotationEditorAnchor = AnnotationEditorAnchor(progress: 0, kind: .frame, sourceTab: .frames)
    @State var audioInPoint: Double?
    @State var audioOutPoint: Double?
    @State var activeTranscriptSegmentID: UUID? = nil
    @State var expandedPreviewTab: PreviewTab?
    @State var visibleTimelineDetailTab: PreviewTab?
    @State var pendingTimelineExpansionTab: PreviewTab?
    @State var pendingTimelineExpansionVideoPath: String?
    @State var timelineZoom: Double = 1
    @State var timelineOffset: Double = 0
    @State var audioTimelineZoom: Double = 1
    @State var timelineAutoScrollLastUpdate = Date.distantPast
    @State var timelineManualScrollProtectionUntil = Date.distantPast
    @State var sceneTimelineAutoFocusedKey: String?
    @State var timelineViewportWasManuallyAdjusted = false
    @State var isVideoTagPopoverPresented = false
    @State var isExportPanelPresented = false
    @State var exportPanelFilter: ExportPanelFilter = .recent
    @State var exportPanelKnownItemIDs: Set<String> = []
    @State var exportPanelHighlightedItemID: String?
    @State var exportPanelHighlightIntensity: Double = 0
    @State var exportPanelHighlightTask: Task<Void, Never>?
    @State var exportAudioPlayer: AVPlayer?
    @State var activeExportAudioClipID: UUID?
    @State var activeExportAudioProgress: Double = 0
    @State var exportAudioTimeObserver: Any?
    @State var exportAudioPlaybackEndObserver: NSObjectProtocol?
    @State var keyboardShuttleTask: Task<Void, Never>?
    @State var keyboardShuttleDirection = 0
    @State var keyboardShuttleFrameStep = 2
    @State var keyboardShuttleLastCommandAt = Date.distantPast
    @State var activeTransportShortcutFeedback: PreviewTransportShortcutFeedback?
    @State var transportShortcutFeedbackTask: Task<Void, Never>?
    @State var pendingSeekTask: Task<Void, Never>?
    @State var pendingStoryboardExportPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedVideo = libraryStore.selectedVideo {
                previewWorkspace(for: selectedVideo)
            } else {
                AppEmptyState(
                    title: "选择一个视频",
                    systemImage: "play.rectangle",
                    description: "点击左侧视频后，会在这里直接播放。",
                    style: .large
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .contentPanel()
        .onAppear {
            controller.libraryStore = libraryStore
            controller.loadVideo(libraryStore.selectedVideo, autoplay: false, preserveIfAlreadyLoaded: true)
            consumePendingSeekRequestIfNeeded()
            consumePendingExportPanelRequestIfNeeded()
            focusSceneTimelineOnOpeningIfNeeded()
            hydrateSceneThumbnailsForFrameTimelineIfIdle()
            PreviewKeyboardCommandDispatcher.setHandler { command in
                handlePreviewKeyboardCommand(command)
            }
        }
        .onDisappear {
            PreviewKeyboardCommandDispatcher.clearHandler()
            stopKeyboardShuttle()
            transportShortcutFeedbackTask?.cancel()
            transportShortcutFeedbackTask = nil
            activeTransportShortcutFeedback = nil
            pendingSeekTask?.cancel()
            pendingSeekTask = nil
            stopExportAudioClipPlayback()
            exportPanelHighlightTask?.cancel()
            exportPanelHighlightTask = nil
            libraryStore.cancelAllSceneThumbnailHydration()
            controller.pause()
        }
        .onChange(of: libraryStore.selectedVideoSelectionID) { _, _ in
            libraryStore.cancelAllSceneThumbnailHydration()
            controller.libraryStore = libraryStore
            controller.loadVideo(
                libraryStore.selectedVideo,
                autoplay: libraryStore.shouldAutoplaySelectedVideo
            )
            audioInPoint = nil
            audioOutPoint = nil
            activeTranscriptSegmentID = nil
            editingAnnotationID = nil
            isAnnotationPopoverPresented = false
            expandedPreviewTab = nil
            visibleTimelineDetailTab = nil
            pendingTimelineExpansionTab = nil
            pendingTimelineExpansionVideoPath = nil
            resetTimelineViewport()
            resetAudioTimelineViewport()
            consumePendingSeekRequestIfNeeded()
            consumePendingExportPanelRequestIfNeeded()
            stopKeyboardShuttle()
            stopExportAudioClipPlayback()
            focusSceneTimelineOnOpeningIfNeeded()
            hydrateSceneThumbnailsForFrameTimelineIfIdle()
            startMusicDetectionIfNeeded(for: libraryStore.selectedVideo, filter: exportPanelFilter)
        }
        .onChange(of: libraryStore.playbackSupportByVideoPath) { _, _ in
            controller.applyPlaybackSupportIfNeeded()
        }
        .onChange(of: controller.isPlaying) { wasPlaying, isPlaying in
            if wasPlaying && !isPlaying {
                commitDisplayedTimelineOffsetIfNeeded(for: controller.progress)
            }
            guard let video = libraryStore.selectedVideo else { return }
            if isPlaying {
                libraryStore.cancelSceneThumbnailHydration(for: video)
            } else if activePreviewTab == .frames || visibleTimelineDetailTab == .frames {
                hydrateSceneThumbnailsForFrameTimelineIfIdle()
            }
        }
        .onReceive(controller.clock.$value) { value in
            handlePlaybackClockTick(value.elapsed)
        }
        .onChange(of: visibleTimelineDetailTab) { _, _ in
            startRecognitionForVisibleTimelineIfNeeded()
        }
        .onReceive(libraryStore.$sceneDetectionProgress) { _ in
            completePendingTimelineExpansionIfReady()
            completePendingStoryboardExportIfReady()
        }
        .onReceive(libraryStore.$sceneCutsByVideoPath) { _ in
            completePendingTimelineExpansionIfReady()
            completePendingStoryboardExportIfReady()
            focusSceneTimelineOnOpeningIfNeeded()
        }
        .onReceive(libraryStore.$transcriptSegmentsByVideoPath) { _ in
            completePendingTimelineExpansionIfReady()
        }
        .onReceive(libraryStore.$transcriptStatusByVideoPath) { statuses in
            completePendingTimelineExpansionIfReady()
            guard
                pendingTimelineExpansionTab == .audio,
                let path = pendingTimelineExpansionVideoPath,
                case .failed = statuses[path]
            else { return }

            pendingTimelineExpansionTab = nil
            pendingTimelineExpansionVideoPath = nil
        }
        .onReceive(libraryStore.$sceneDetectionErrorByVideoPath) { errors in
            if let path = pendingStoryboardExportPath, errors[path] != nil {
                pendingStoryboardExportPath = nil
            }

            guard
                let path = pendingTimelineExpansionVideoPath,
                errors[path] != nil
            else { return }

            pendingTimelineExpansionTab = nil
            pendingTimelineExpansionVideoPath = nil
        }
        .onChange(of: activePreviewTab) { _, _ in
            focusSceneTimelineOnOpeningIfNeeded()
            hydrateSceneThumbnailsForFrameTimelineIfIdle()
        }
        .onChange(of: libraryStore.sceneCutProgressesByVideoPath) { _, _ in
            focusSceneTimelineOnOpeningIfNeeded()
        }
        .onChange(of: controller.duration) { _, _ in
            focusSceneTimelineOnOpeningIfNeeded()
        }
        .onReceive(AppEventBus.seekRequestPublisher) { notification in
            guard
                let request = AppEventBus.seekRequest(from: notification),
                request.path == libraryStore.selectedVideo?.url.path
            else { return }
            performSeekWhenReady(request, clearsPendingRequest: false)
        }
        .onChange(of: pendingSeekRequest) { _, _ in
            consumePendingSeekRequestIfNeeded()
        }
        .onChange(of: pendingExportPanelRequest) { _, _ in
            consumePendingExportPanelRequestIfNeeded()
        }
        .onReceive(AppEventBus.pausePreviewRequestPublisher) { _ in
            controller.pause()
            stopExportAudioClipPlayback()
        }
    }

    func consumePendingSeekRequestIfNeeded() {
        guard
            let request = pendingSeekRequest,
            request.path == libraryStore.selectedVideo?.url.path
        else { return }
        performSeekWhenReady(request, clearsPendingRequest: true)
    }

    func consumePendingExportPanelRequestIfNeeded() {
        guard
            let request = pendingExportPanelRequest,
            request.path == libraryStore.selectedVideo?.url.path
        else { return }

        exportPanelFilter = ExportPanelFilter(rawValue: request.filter) ?? .recent
        isExportPanelPresented = true
        pendingExportPanelRequest = nil
    }

    func performSeekWhenReady(_ request: AppEventBus.SeekRequest, clearsPendingRequest: Bool) {
        pendingSeekTask?.cancel()
        pendingSeekTask = Task { @MainActor in
            for attempt in 0 ..< 8 {
                guard !Task.isCancelled else { return }
                guard request.path == libraryStore.selectedVideo?.url.path else { return }

                if controller.currentVideoPath == request.path,
                   (controller.effectiveDuration ?? 0) > 0 {
                    controller.pause()
                    controller.seekToSeconds(request.time)
                    clearPendingSeekRequestIfNeeded(request, clearsPendingRequest: clearsPendingRequest)
                    return
                }

                if attempt == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
            }

            guard !Task.isCancelled, request.path == libraryStore.selectedVideo?.url.path else { return }
            controller.pause()
            controller.seekToSeconds(request.time)
            clearPendingSeekRequestIfNeeded(request, clearsPendingRequest: clearsPendingRequest)
        }
    }

    func clearPendingSeekRequestIfNeeded(
        _ request: AppEventBus.SeekRequest,
        clearsPendingRequest: Bool
    ) {
        guard clearsPendingRequest, pendingSeekRequest == request else { return }
        pendingSeekRequest = nil
    }

    var collapsedPreviewTimelineStackHeight: CGFloat {
        Design.timelineLaneHeight * 3 + timelineLaneGap * 2
    }

    func previewWorkspace(for video: VideoItem) -> some View {
        GeometryReader { proxy in
            let showsSidebar = proxy.size.width >= 720
            let sidebarWidth = max(240, min(320, proxy.size.width * 0.20))
            let stageGap: CGFloat = showsSidebar ? 12 : 0
            let playerWidth = showsSidebar ? max(360, proxy.size.width - sidebarWidth - stageGap) : proxy.size.width
            let workspaceGap: CGFloat = 8
            let headerHeight = Design.previewHeaderHeight
            let topChromeHeight = headerHeight + workspaceGap
            let timelineHeight = collapsedPreviewTimelineStackHeight
            let verticalBudget = max(0, proxy.size.height - topChromeHeight - workspaceGap * 2)
            let stageHeight = max(220, verticalBudget - timelineHeight)
            let overlayInset = Design.previewExportOverlayButtonInset
            let overlayAvailableWidth = max(1, proxy.size.width - overlayInset * 2)
            let overlayPreferredWidth = max(
                Design.previewExportOverlayMinWidth,
                proxy.size.width * Design.previewExportOverlayWidthRatio
            )
            let overlayPanelWidth = min(overlayAvailableWidth, overlayPreferredWidth)
            let overlayPanelHeight = max(1, stageHeight - overlayInset * 2)

            if showsSidebar {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: stageGap) {
                        VStack(alignment: .leading, spacing: workspaceGap) {
                            previewHeader(for: video)
                                .frame(width: playerWidth, alignment: .leading)

                            PreviewPlayerView(
                                player: controller.player,
                                statusMessage: controller.playbackMessage,
                                onSurfaceTap: togglePreviewPlayback
                            )
                            .frame(width: playerWidth, height: stageHeight, alignment: .topLeading)
                            .transaction { $0.animation = nil }
                        }
                        .frame(width: playerWidth, alignment: .topLeading)

                        exportPanel(for: video, isOverlay: false)
                            .frame(
                                width: sidebarWidth,
                                height: stageHeight + topChromeHeight - Design.previewHeaderTopInset,
                                alignment: .top
                            )
                            .padding(.top, Design.previewHeaderTopInset)
                            .frame(width: sidebarWidth, height: stageHeight + topChromeHeight, alignment: .top)
                            .transaction { $0.animation = nil }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    timelineStackContainer(
                        for: video,
                        collapsedHeight: timelineHeight,
                        expandedHeight: timelineHeight
                    )
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                }
                .padding(.bottom, workspaceGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: workspaceGap) {
                    previewHeader(for: video)

                    ZStack(alignment: .topTrailing) {
                        PreviewPlayerView(
                            player: controller.player,
                            statusMessage: controller.playbackMessage,
                            onSurfaceTap: togglePreviewPlayback
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: stageHeight)
                        .transaction { $0.animation = nil }

                        if isExportPanelPresented {
                            exportPanel(for: video, isOverlay: true)
                                .frame(width: overlayPanelWidth, height: overlayPanelHeight, alignment: .topTrailing)
                                .padding(overlayInset)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            previewExportOverlayButton(
                                systemImage: "square.and.arrow.up",
                                help: "打开导出区"
                            ) {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    isExportPanelPresented = true
                                }
                            }
                            .padding(Design.previewExportOverlayButtonInset + Design.previewExportPanelPadding)
                        }
                    }
                    .frame(height: stageHeight, alignment: .topLeading)
                    .clipped()

                    timelineStackContainer(
                        for: video,
                        collapsedHeight: timelineHeight,
                        expandedHeight: timelineHeight
                    )
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                }
                .padding(.bottom, workspaceGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

}
