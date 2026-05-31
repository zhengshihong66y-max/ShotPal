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
    @AppStorage("appWorkspace") var appWorkspaceRawValue = AppWorkspace.home.rawValue
    @AppStorage("isSidebarCollapsed") var isSidebarCollapsed = false
    @State var mediaPanelWidth = UserDefaults.standard.object(forKey: "mediaPanelWidth") as? Double ?? 340.0
    @State var frameMediaPanelWidth = UserDefaults.standard.object(forKey: "frameMediaPanelWidth") as? Double
    @State var renamingTag: String? = nil
    @State var renameInput = ""
    @State var isImportSheetPresented = false
    @State var isSettingsSheetPresented = false
    @State var importURLText = ""
    @State var importEndpointText = ""
    @State var librarySearchText = ""
    @State var isInstagramSavedSyncing = false
    @State var instagramSavedSyncMessage: String?
    @State var instagramSavedSyncIsError = false
    @State var isXiaohongshuSavedSyncing = false
    @State var xiaohongshuSavedSyncMessage: String?
    @State var xiaohongshuSavedSyncIsError = false
    @State var expandedImportBatchIDs: Set<UUID> = []
    @State var observedPasteboardChangeCount = NSPasteboard.general.changeCount
    @State var isImportDropTargeted = false
    @State var isTagFilterMenuPresented = false
    @State var frameFilterVideoPath: String?
    @State var frameSelectedFrameID: UUID?
    @State var mediaPanelDragStartWidth: Double?
    @State var mediaPanelDragStartX: CGFloat?
    @State var isDividerHovered = false
    @State var canRestorePersistedWorkspace = false

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

                if isSettingsSheetPresented {
                    settingsOverlay(containerSize: proxy.size)
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
        .alert("重命名标签", isPresented: Binding(
            get: { renamingTag != nil },
            set: { if !$0 { renamingTag = nil } }
        )) {
            TextField("新标签名", text: $renameInput)
            Button("确认") {
                if let old = renamingTag {
                    libraryStore.renameGlobalTag(old, to: renameInput)
                }
                renamingTag = nil
            }
            Button("取消", role: .cancel) { renamingTag = nil }
        } message: {
            Text("重命名后，所有含此标签的视频都会同步更新")
        }
        .onAppear(perform: restorePersistedWorkspaceAfterFirstFrame)
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
        let storedRawValue = UserDefaults.standard.string(forKey: "appWorkspace") ?? AppWorkspace.home.rawValue
        let stored = AppWorkspace(rawValue: storedRawValue) ?? .home
        guard stored.canRestoreDuringLaunch else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            canRestorePersistedWorkspace = true
        }
    }

    @ViewBuilder
    func mainLayout(isCompact: Bool, containerWidth: CGFloat) -> some View {
        let activeMediaPanelWidth = resolvedMediaPanelWidth(containerWidth: containerWidth)

        HStack(spacing: Design.panelSpacing) {
            if presentedAppWorkspace == .audio || presentedAppWorkspace == .frames || presentedAppWorkspace == .music {
                navigationRail
                    .frame(width: Design.railWidth, alignment: .leading)
                    .background(Design.sidebarBg)
                    .zIndex(1)

                workspaceView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Design.sidebarBg)
            } else if isCompact {
                VStack(spacing: Design.panelSpacing) {
                    libraryColumn(isCompact: true)
                        .frame(maxWidth: .infinity, maxHeight: 280)

                    workspaceView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        libraryColumn(isCompact: false)
                            .frame(width: activeMediaPanelWidth)

                        workspaceView
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
    }

    func resolvedMediaPanelWidth(containerWidth: CGFloat) -> CGFloat {
        if presentedAppWorkspace == .frames {
            let defaultWidth = containerWidth * 0.5
            return clampedMediaPanelWidth(frameMediaPanelWidth ?? defaultWidth, containerWidth: containerWidth)
        }
        return clampedMediaPanelWidth(mediaPanelWidth, containerWidth: containerWidth)
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
                .zIndex(1)

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
            // 顶部窗口按键与素材库工具栏共用同一条视觉中心线。
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
        let isSelected = workspace == .settings ? isSettingsSheetPresented : presentedAppWorkspace == workspace
        let selectionWidth = Design.railWidth - Design.railIconInset * 2

        return Button {
            if workspace == .settings {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    isSettingsSheetPresented = true
                }
            } else {
                appWorkspace = workspace
            }
        } label: {
            ZStack(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.10))
                        .frame(width: selectionWidth, height: Design.railButtonHeight)
                        .offset(x: Design.railSelectionGuideX)
                }

                Image(systemName: workspace.icon)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.88) : Color.white.opacity(0.40))
                    .frame(width: Design.railIconBoxSize, height: Design.railIconBoxSize)
                    .offset(x: workspace.railIconOffset)
                    .frame(width: Design.railWidth, height: Design.railButtonHeight)
                    .offset(x: Design.railButtonVisualOffsetX)
            }
            .frame(width: Design.railWidth, height: Design.railButtonHeight, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(workspace.title)
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
                        UserDefaults.standard.set(frameMediaPanelWidth, forKey: "frameMediaPanelWidth")
                    } else {
                        UserDefaults.standard.set(mediaPanelWidth, forKey: "mediaPanelWidth")
                    }
                    mediaPanelDragStartWidth = nil
                    mediaPanelDragStartX = nil
                }
        )
        .help("拖动调整素材库和预览区比例")
    }

    @ViewBuilder
    var workspaceView: some View {
        switch presentedAppWorkspace {
        case .home:
            PreviewPanelView(openWorkspace: { appWorkspace = $0 })
        case .frames:
            FramesWorkspaceView(
                selectedVideoPath: $frameFilterVideoPath,
                selectedFrameID: $frameSelectedFrameID,
                goHome: jumpToVideo
            )
        case .audio:
            AudioWorkspaceView(goHome: jumpToVideo)
        case .music:
            MusicWorkspaceView(goHome: jumpToVideo)
        case .content:
            ContentWorkspaceView(goHome: jumpToVideo)
        case .settings:
            SettingsWorkspaceView()
        }
    }

    func jumpToVideo(path: String, time: Double) {
        libraryStore.selectVideo(path: path)
        appWorkspace = .home
        NotificationCenter.default.post(
            name: .lapianBaoSeekRequest,
            object: nil,
            userInfo: ["path": path, "time": time]
        )
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
                HStack {
                    Text("拉片宝")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
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
                    isSelected: presentedAppWorkspace == workspace
                ) {
                    appWorkspace = workspace
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
        .help(isSidebarCollapsed ? "展开侧边栏" : "收起侧边栏")
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
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isSidebarCollapsed {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .frame(width: 36, height: 32)
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                            .foregroundStyle(isSelected ? .primary : .secondary)
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
        .padding(.horizontal, isSidebarCollapsed ? 8 : 4)
        .padding(.vertical, isSidebarCollapsed ? 1 : 0)
    }

}
