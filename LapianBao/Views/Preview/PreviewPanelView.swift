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

// MARK: - PreviewPanelView
/// 预览面板：使用 @StateObject controller 驱动播放，
/// 场景网格由 ScenePanelView（Equatable）单独渲染，与 Timer 完全解耦。
struct PreviewPanelView: View {
    @EnvironmentObject var libraryStore: LibraryStore
    @StateObject var controller = PreviewController()
    let openWorkspace: (AppWorkspace) -> Void
    @Namespace var tabNamespace
    static let contentTimelineDetailBlockGap: CGFloat = 8
    static let contentTimelineDetailBlockPadding: CGFloat = 8
    static let annotationEditorWidth: CGFloat = 288
    static let annotationEditorHeight: CGFloat = 184
    static let exportActionButtonSize: CGFloat = 22
    static let exportRowContentHeight: CGFloat = 78
    static let exportRowVerticalPadding: CGFloat = 10
    static let exportRowHeight: CGFloat = exportRowContentHeight + exportRowVerticalPadding * 2
    static let exportFramePreviewWidth: CGFloat = 100
    static let exportFramePreviewMinWidth: CGFloat = 48
    static let exportFramePreviewMaxWidth: CGFloat = 142
    static let exportTranscriptIconWidth: CGFloat = 34
    @State var activePreviewTab: PreviewTab = .frames
    @State var annotationText = ""
    @State var pendingAnnotationKind: AnnotationItem.Kind = .frame
    @State var editingAnnotationID: UUID?
    @State var isAnnotationPopoverPresented = false
    @State var annotationEditorAnchor = AnnotationEditorAnchor(progress: 0, kind: .frame, sourceTab: .frames)
    @State var audioInPoint: Double?
    @State var audioOutPoint: Double?
    @State var activeTranscriptSegmentID: UUID? = nil
    @State var contentNodeTimelineStatus: TranscriptTimelineStatus = .idle
    @State var expandedPreviewTab: PreviewTab?
    @State var visibleTimelineDetailTab: PreviewTab?
    @State var timelineZoom: Double = 1
    @State var timelineOffset: Double = 0
    @State var sceneTimelineAutoFocusedKey: String?
    @State var isVideoTagPopoverPresented = false
    @State var isVideoTagAddHovered = false
    @State var draftVideoTag = ""
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
            controller.loadVideo(libraryStore.selectedVideo, autoplay: false)
            focusSceneTimelineOnOpeningIfNeeded()
            hydrateSceneThumbnailsForFrameTimelineIfIdle()
            PreviewKeyboardCommandDispatcher.setHandler { command in
                handlePreviewKeyboardCommand(command)
            }
        }
        .onDisappear {
            PreviewKeyboardCommandDispatcher.clearHandler()
            stopKeyboardShuttle()
            stopExportAudioClipPlayback()
            exportPanelHighlightTask?.cancel()
            exportPanelHighlightTask = nil
            libraryStore.cancelAllSceneThumbnailHydration()
            controller.stopPlayback()
        }
        .onChange(of: isVideoTagPopoverPresented) { _, isPresented in
            if !isPresented {
                draftVideoTag = ""
            }
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
            resetTimelineViewport()
            stopKeyboardShuttle()
            stopExportAudioClipPlayback()
            focusSceneTimelineOnOpeningIfNeeded()
            hydrateSceneThumbnailsForFrameTimelineIfIdle()
            startMusicDetectionIfNeeded(for: libraryStore.selectedVideo, filter: exportPanelFilter)
        }
        .onChange(of: libraryStore.playbackSupportByVideoPath) { _, _ in
            controller.applyPlaybackSupportIfNeeded()
        }
        .onChange(of: controller.isPlaying) { _, isPlaying in
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
        .onChange(of: activePreviewTab) { _, _ in
            focusSceneTimelineOnOpeningIfNeeded()
            hydrateSceneThumbnailsForFrameTimelineIfIdle()
        }
        .onChange(of: libraryStore.sceneCutProgressesByVideoPath) { _, _ in
            focusSceneTimelineOnOpeningIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lapianBaoSeekRequest)) { notification in
            guard
                let path = notification.userInfo?["path"] as? String,
                let time = notification.userInfo?["time"] as? Double,
                path == libraryStore.selectedVideo?.url.path
            else { return }
            controller.pause()
            controller.seekToSeconds(time)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lapianBaoPausePreviewRequest)) { _ in
            controller.pause()
            stopExportAudioClipPlayback()
        }
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
