//
//  ContentView.swift
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

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var libraryStore: LibraryStore
    @StateObject var previewController = PreviewController()
    @StateObject var musicWorkspaceViewModel = MusicWorkspaceViewModel()
    @AppStorage(AppSettings.Key.appWorkspace) var appWorkspaceRawValue = AppWorkspace.home.rawValue
    @AppStorage(AppSettings.Key.isSidebarCollapsed) var isSidebarCollapsed = false
    @AppStorage(AppSettings.Key.musicSortOption) var launchMusicSortOptionRawValue = MusicSortOption.title.rawValue
    @AppStorage(AppSettings.Key.musicSortDirection) var launchMusicSortDirectionRawValue = VideoSortDirection.ascending.rawValue
    @State var mediaPanelWidth = AppSettings.mediaPanelWidth
    @State var frameMediaPanelWidth = AppSettings.frameMediaPanelWidth
    @State var isLibraryTagEditing = false
    @State var libraryTagRenameTarget: String?
    @State var libraryTagRenameInput = ""
    @FocusState var focusedLibraryTagRenameTarget: String?
    @State var isImportSheetPresented = false
    // 面板打开时刻:遮罩点击需忽略打开后的短窗口,防止打开面板的那次
    // 点击被手势系统在视图更新后重新命中遮罩、当场关闭面板
    @State var importPanelPresentedAt = Date.distantPast
    @State var importURLText = ""
    @State var importURLFeedbackMessage: String?
    @State var importEndpointText = ""
    @State var librarySearchText = ""
    @State var selectedLibraryPlatforms: Set<String> = []
    @State var selectedLibraryAuthors: Set<String> = []
    @State var isLibrarySidebarFilterAreaPresented = true
    @State var expandedImportBatchIDs: Set<UUID> = []
    @State var observedPasteboardChangeCount = NSPasteboard.general.changeCount
    @State var isImportDropTargeted = false
    @State var isTagFilterMenuPresented = false
    @State var activeLibraryCardMenuID: String?
    @State var libraryCardMenuDismissToken = 0
    @State var frameFilterVideoPath: String?
    @State var frameSelectedFrameID: UUID?
    @State var frameBoardMode: FramesBoardMode = .collection
    @State var pendingHomeSeekRequest: AppEventBus.SeekRequest?
    @State var pendingExportPanelRequest: AppEventBus.ExportPanelRequest?
    @State var mediaPanelDragStartWidth: Double?
    @State var mediaPanelDragStartX: CGFloat?
    @State var isDividerHovered = false
    @State var canRestorePersistedWorkspace = false
    @State var pendingStoryboardOpenPath: String?
    @State var hasMountedMusicWorkspace = false

    var appWorkspace: AppWorkspace {
        get {
            let stored = AppWorkspace(rawValue: appWorkspaceRawValue) ?? .home
            return stored.canRestoreFromUserDefaults ? stored : .home
        }
        nonmutating set {
            canRestorePersistedWorkspace = true
            appWorkspaceRawValue = newValue.rawValue
        }
    }

    var presentedAppWorkspace: AppWorkspace {
        canRestorePersistedWorkspace ? appWorkspace : .home
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 900

            ZStack {
                backgroundGradient

                mainLayout(isCompact: isCompact, containerWidth: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Design.windowInset)

                if isImportSheetPresented {
                    importOverlay(containerSize: proxy.size)
                }

            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(WindowConfigurator())
        .frame(minWidth: Design.minimumWindowWidth, minHeight: Design.minimumWindowHeight)
        .onDrop(
            of: Self.importDropTypeIdentifiers,
            isTargeted: $isImportDropTargeted,
            perform: handleImportDrop
        )
        .onReceive(Self.clipboardProbeTimer) { _ in
            handleClipboardChangeIfNeeded()
        }
        .onAppear {
            restorePersistedWorkspaceAfterFirstFrame()
        }
        .onReceive(libraryStore.$sceneDetectionProgress) { _ in
            completePendingStoryboardOpenIfReady()
        }
        .onReceive(libraryStore.$sceneCutsByVideoPath) { _ in
            completePendingStoryboardOpenIfReady()
        }
        .onReceive(libraryStore.$sceneDetectionErrorByVideoPath) { errors in
            if let path = pendingStoryboardOpenPath, errors[path] != nil {
                pendingStoryboardOpenPath = nil
            }
        }
        .onReceive(AppEventBus.openExportPanelRequestPublisher) { notification in
            guard let request = AppEventBus.exportPanelRequest(from: notification) else { return }
            if libraryStore.selectedVideo?.url.path != request.path {
                libraryStore.selectVideo(path: request.path)
            }
            pendingExportPanelRequest = request
            switchWorkspace(to: .home)
        }
    }

    static let clipboardProbeTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    static let importDropTypeIdentifiers = [
        UTType.url.identifier,
        UTType.plainText.identifier,
        UTType.text.identifier,
        UTType.utf8PlainText.identifier,
        UTType.html.identifier
    ]

    var backgroundGradient: some View {
        Design.contentBg.ignoresSafeArea()
    }

    func restorePersistedWorkspaceAfterFirstFrame() {
        guard !canRestorePersistedWorkspace else { return }
        let storedRawValue = AppSettings.appWorkspaceRawValue ?? AppWorkspace.home.rawValue
        let stored = AppWorkspace(rawValue: storedRawValue) ?? .home
        guard stored.canRestoreDuringLaunch else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            canRestorePersistedWorkspace = true
        }
    }

    @ViewBuilder
    func mainLayout(isCompact: Bool, containerWidth: CGFloat) -> some View {
        let activeMediaPanelWidth = resolvedMediaPanelWidth(containerWidth: containerWidth)
        let mediaWorkspaceToolbarWidth = homeMediaContentWidth(containerWidth: containerWidth)

        HStack(spacing: Design.panelSpacing) {
            if presentedAppWorkspace == .frames ||
                presentedAppWorkspace == .music ||
                presentedAppWorkspace == .settings {
                navigationRail
                    .frame(width: Design.railWidth, alignment: .leading)
                    .background(Design.sidebarBg)
                    .zIndex(10)

                workspaceView(toolbarWidth: mediaWorkspaceToolbarWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Design.sidebarBg)
                    .zIndex(presentedAppWorkspace == .frames ? 2 : 0)
            } else if isCompact {
                VStack(spacing: Design.panelSpacing) {
                    libraryColumn(isCompact: true)
                        .frame(maxWidth: .infinity, maxHeight: 280)

                    workspaceView(toolbarWidth: nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        libraryColumn(isCompact: false)
                            .frame(width: activeMediaPanelWidth)

                        workspaceView(toolbarWidth: nil)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Design.contentBg)
                    }

                    mediaPanelDivider(containerWidth: containerWidth)
                        .frame(maxHeight: .infinity)
                        .offset(x: activeMediaPanelWidth - 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: musicWorkspaceLaunchPreparationID(containerWidth: containerWidth)) {
            startMusicWorkspaceLaunchPreparation(containerWidth: containerWidth)
        }
    }

    func resolvedMediaPanelWidth(containerWidth: CGFloat) -> CGFloat {
        if presentedAppWorkspace == .frames {
            let defaultWidth = containerWidth * 0.5
            return clampedMediaPanelWidth(frameMediaPanelWidth ?? defaultWidth, containerWidth: containerWidth)
        }
        return clampedMediaPanelWidth(mediaPanelWidth, containerWidth: containerWidth)
    }

    func homeMediaContentWidth(containerWidth: CGFloat) -> CGFloat {
        let minimumSidebarWidth: CGFloat = 320
        let maximumSidebarWidth: CGFloat = 660
        let homePanelWidth = min(maximumSidebarWidth, max(minimumSidebarWidth, CGFloat(mediaPanelWidth)))
        return max(0, min(homePanelWidth, containerWidth) - Design.railWidth)
    }

    func clampedMediaPanelWidth(_ width: Double, containerWidth: CGFloat) -> CGFloat {
        clampedMediaPanelWidth(CGFloat(width), containerWidth: containerWidth)
    }

    func clampedMediaPanelWidth(_ width: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let minimumSidebarWidth: CGFloat = 320
        let maximumSidebarWidth: CGFloat = presentedAppWorkspace == .frames
            ? max(minimumSidebarWidth, containerWidth - 260)
            : 660
        return min(maximumSidebarWidth, max(minimumSidebarWidth, width))
    }

    func libraryColumn(isCompact: Bool) -> some View {
        HStack(spacing: 0) {
            navigationRail
                .frame(width: Design.railWidth, alignment: .leading)
                .zIndex(10)

            if presentedAppWorkspace == .frames {
                frameVideoFilterColumn(isCompact: isCompact)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                videoGrid(isCompact: isCompact, framed: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Design.sidebarBg)
    }

    var navigationRail: some View {
        VStack(spacing: 0) {
            // 顶部窗口按键与左侧 rail 图标共用同一条左缘视觉基线。
            ZStack(alignment: .topLeading) {
                Design.sidebarBg
                    .frame(
                        width: Design.trafficLightGuideX + Design.trafficLightClusterWidth,
                        height: Design.railTopChromeHeight
                    )

                WindowDragRegion()
                    .frame(
                        width: Design.trafficLightGuideX + Design.trafficLightClusterWidth,
                        height: Design.railTopChromeHeight
                    )

                windowControls
                    .position(
                        x: Design.trafficLightGuideX + Design.trafficLightClusterWidth / 2,
                        y: Design.trafficLightGuideY + Design.trafficLightSize / 2
                    )
            }
            .frame(width: Design.railWidth, height: Design.railTopChromeHeight)

            VStack(spacing: 8) {
                ForEach(AppWorkspace.allCases) { workspace in
                    navigationRailButton(workspace)
                }
            }
            .padding(.top, 14)

            Spacer()
        }
        .padding(.bottom, 12)
    }

    func navigationRailButton(_ workspace: AppWorkspace) -> some View {
        let isSelected = presentedAppWorkspace == workspace
        let isMusicPreparing = workspace == .music && musicWorkspaceViewModel.launchPreparationStatus.isLoading
        let iconColor = isMusicPreparing
            ? Color.gray.opacity(0.62)
            : (isSelected ? Color.white.opacity(0.94) : Color.white.opacity(0.40))

        return Button {
            if workspace == .frames {
                frameBoardMode = .collection
            }
            switchWorkspace(to: workspace)
        } label: {
            Image(systemName: workspace.icon)
                .font(.system(size: workspace.railIconSize, weight: isSelected ? .semibold : .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconColor)
                .frame(width: Design.railIconBoxSize, height: Design.railIconBoxSize)
                .offset(x: Design.railIconAlignmentOffsetX + workspace.railIconOffset)
                .frame(width: Design.railWidth, height: Design.railButtonHeight, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换到\(workspace.title)")
        .accessibilityIdentifier("workspace_\(workspace.rawValue)_button")
    }

    func mediaPanelDivider(containerWidth: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(isDividerHovered ? 0.18 : 0))
                .frame(width: 1)
                .animation(.easeInOut(duration: 0.12), value: isDividerHovered)

            ResizeLeftRightCursorView()
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isDividerHovered = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if mediaPanelDragStartWidth == nil {
                        mediaPanelDragStartWidth = resolvedMediaPanelWidth(containerWidth: containerWidth)
                        mediaPanelDragStartX = value.startLocation.x
                    }
                    let delta = value.location.x - (mediaPanelDragStartX ?? value.startLocation.x)
                    let nextWidth = clampedMediaPanelWidth(
                        (mediaPanelDragStartWidth ?? resolvedMediaPanelWidth(containerWidth: containerWidth)) + delta,
                        containerWidth: containerWidth
                    )
                    if presentedAppWorkspace == .frames {
                        frameMediaPanelWidth = nextWidth
                    } else {
                        mediaPanelWidth = nextWidth
                    }
                }
                .onEnded { _ in
                    if presentedAppWorkspace == .frames {
                        AppSettings.frameMediaPanelWidth = frameMediaPanelWidth
                    } else {
                        AppSettings.mediaPanelWidth = mediaPanelWidth
                    }
                    mediaPanelDragStartWidth = nil
                    mediaPanelDragStartX = nil
                }
        )
    }

    @ViewBuilder
    func workspaceView(toolbarWidth: CGFloat? = nil) -> some View {
        ZStack {
            switch presentedAppWorkspace {
            case .home:
                PreviewPanelView(
                    controller: previewController,
                    openStoryboardBoard: openFrameStoryboard,
                    pendingSeekRequest: $pendingHomeSeekRequest,
                    pendingExportPanelRequest: $pendingExportPanelRequest
                )
            case .frames:
                FramesWorkspaceView(
                    selectedVideoPath: $frameFilterVideoPath,
                    selectedFrameID: $frameSelectedFrameID,
                    boardMode: $frameBoardMode,
                    previewController: previewController,
                    toolbarWidth: toolbarWidth,
                    goHome: jumpToVideo
                )
            case .music:
                Color.clear
            case .settings:
                SettingsWorkspaceView()
            }

            if hasMountedMusicWorkspace || presentedAppWorkspace == .music {
                MusicWorkspaceView(
                    viewModel: musicWorkspaceViewModel,
                    toolbarWidth: toolbarWidth,
                    goHome: jumpToVideo
                )
                .opacity(presentedAppWorkspace == .music ? 1 : 0)
                .allowsHitTesting(presentedAppWorkspace == .music)
                .accessibilityHidden(presentedAppWorkspace != .music)
            }
        }
        .onAppear {
            if presentedAppWorkspace == .music {
                hasMountedMusicWorkspace = true
            }
        }
        .onChange(of: presentedAppWorkspace) { _, workspace in
            if workspace == .music {
                hasMountedMusicWorkspace = true
            }
        }
    }

    func jumpToVideo(path: String, time: Double) {
        pendingHomeSeekRequest = AppEventBus.SeekRequest(path: path, time: time)
        libraryStore.selectVideo(path: path)
        switchWorkspace(to: .home)
    }

    func openFrameStoryboard(for video: VideoItem) {
        libraryStore.selectVideo(path: video.url.path)
        frameFilterVideoPath = video.url.path
        frameSelectedFrameID = nil

        libraryStore.loadCachedSceneCuts(for: video)
        if libraryStore.hasSceneRecognitionResult(for: video) {
            openRecognizedFrameStoryboard(for: video)
            return
        }

        pendingStoryboardOpenPath = video.url.path
        libraryStore.detectSceneCuts(for: video)
        completePendingStoryboardOpenIfReady()
    }

    func completePendingStoryboardOpenIfReady() {
        guard
            let path = pendingStoryboardOpenPath,
            let video = libraryStore.videos.first(where: { $0.url.path == path }),
            libraryStore.sceneDetectionProgress[path] == nil,
            libraryStore.hasSceneRecognitionResult(for: video)
        else { return }

        pendingStoryboardOpenPath = nil
        openRecognizedFrameStoryboard(for: video)
    }

    func openRecognizedFrameStoryboard(for video: VideoItem) {
        libraryStore.selectVideo(path: video.url.path)
        frameFilterVideoPath = video.url.path
        frameSelectedFrameID = nil
        frameBoardMode = .storyboard
        switchWorkspace(to: .frames)
    }

    func switchWorkspace(to workspace: AppWorkspace) {
        guard presentedAppWorkspace != workspace else { return }
        let previous = presentedAppWorkspace
        var transaction = Transaction()
        transaction.disablesAnimations = true
        PerformanceDiagnostics.mark("workspace switch \(previous.rawValue)->\(workspace.rawValue)")
        withTransaction(transaction) {
            appWorkspace = workspace
        }
    }

    var windowControls: some View {
        NativeWindowTrafficLights(buttonSize: Design.trafficLightSize, buttonGap: Design.trafficLightGap)
            .frame(width: Design.trafficLightClusterWidth, height: Design.trafficLightSize)
    }

    var sidebar: some View {
        ZStack(alignment: .topLeading) {
            WindowDragRegion()
                .frame(height: isSidebarCollapsed ? 44 : 56)
                .padding(.leading, isSidebarCollapsed ? 48 : 88)
                .padding(.trailing, 12)

            windowControls
                .padding(.leading, isSidebarCollapsed ? 7 : 9)
                .padding(.top, isSidebarCollapsed ? 14 : 7)

            sidebarContent
                .padding(.top, isSidebarCollapsed ? 56 : 88)
                .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity)
        .glassPanel()
    }

    var sidebarContent: some View {
        VStack(alignment: isSidebarCollapsed ? .center : .leading, spacing: isSidebarCollapsed ? 4 : 0) {
            if isSidebarCollapsed {
                sidebarCollapseButton
                    .padding(.bottom, 12)
            } else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("拉片宝")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("English name: ShotPal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    sidebarCollapseButton
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            if !isSidebarCollapsed {
                sidebarSectionLabel("工作区")
            }

            ForEach(AppWorkspace.allCases) { workspace in
                sidebarItem(
                    icon: workspace.icon,
                    label: workspace.title,
                    isSelected: presentedAppWorkspace == workspace,
                    isLoading: workspace == .music && musicWorkspaceViewModel.launchPreparationStatus.isLoading
                ) {
                    switchWorkspace(to: workspace)
                }
            }

            Spacer()

            if !isSidebarCollapsed {
                Text("\(libraryStore.videos.count) 个视频")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
        }
    }

    var sidebarCollapseButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isSidebarCollapsed.toggle()
            }
        } label: {
            Image(systemName: isSidebarCollapsed ? "sidebar.left" : "sidebar.leading")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(isSidebarCollapsed ? .white.opacity(0.06) : .clear)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSidebarCollapsed ? "展开侧边栏" : "收起侧边栏")
        .accessibilityIdentifier("sidebar_collapse_button")
    }

    @ViewBuilder
    func sidebarSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }

    func sidebarItem(
        icon: String,
        label: String,
        isSelected: Bool,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isSidebarCollapsed {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isLoading ? Color.gray.opacity(0.62) : (isSelected ? .primary : .secondary))
                        .frame(width: 36, height: 32)
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                            .foregroundStyle(isLoading ? Color.gray.opacity(0.62) : (isSelected ? .primary : .secondary))
                        Text(label)
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
            }
            .frame(maxWidth: isSidebarCollapsed ? 40 : .infinity, alignment: isSidebarCollapsed ? .center : .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous)
                        .fill(.white.opacity(isSidebarCollapsed ? 0.12 : 0.10))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换到\(label)")
        .accessibilityIdentifier("sidebar_workspace_\(label)_button")
        .padding(.horizontal, isSidebarCollapsed ? 8 : 4)
        .padding(.vertical, isSidebarCollapsed ? 1 : 0)
    }

}
