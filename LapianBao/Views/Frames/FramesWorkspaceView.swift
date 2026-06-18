//
//  FramesWorkspaceView.swift
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

// MARK: - Workspace Pages

struct FrameStoryboardItem: Identifiable {
    let id: String
    let video: VideoItem
    let time: Double
    let cut: SceneCut?
    let sample: SampledFrame?
    let thumbnailImage: NSImage?
    let sceneIndex: Int?
}

struct FullResolutionFramePreview: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let videoURL: URL
    let time: Double
    let fallbackImage: NSImage?
    let dragItemProvider: (() -> NSItemProvider)?
    @State private var fullResolutionImage: NSImage?
    @State private var isLoadingFullResolution = false

    private var previewKey: String {
        "\(videoURL.path)#\(Int((max(0, time) * 1000).rounded()))"
    }

    var body: some View {
        previewContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if isLoadingFullResolution, fallbackImage != nil {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.black.opacity(0.42))
                        .clipShape(Circle())
                        .padding(8)
                }
            }
            .fullResolutionImageDrag(dragItemProvider)
            .task(id: previewKey) {
                await loadFullResolutionImage(for: previewKey)
            }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let image = fullResolutionImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else if let fallbackImage {
            Image(nsImage: fallbackImage)
                .resizable()
                .interpolation(.medium)
                .scaledToFit()
        } else {
            Color.black.opacity(0.24)
                .aspectRatio(16 / 9, contentMode: .fit)
        }
    }

    private func loadFullResolutionImage(for key: String) async {
        fullResolutionImage = nil
        isLoadingFullResolution = true
        let image = await libraryStore.fullResolutionFrameImage(videoURL: videoURL, time: time)
        guard !Task.isCancelled, key == previewKey else { return }
        fullResolutionImage = image
        isLoadingFullResolution = false
    }
}

private struct FrameBoardImageTile<OverlayControl: View>: View {
    let image: NSImage?
    let numberText: String
    let onTap: () -> Void
    let dragItemProvider: (() -> NSItemProvider)?
    @ViewBuilder let overlayControl: (_ isHovered: Bool) -> OverlayControl

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                GeometryReader { proxy in
                    ZStack(alignment: .bottomLeading) {
                        imageContent
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.56)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 48)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)

                        Text(numberText)
                            .font(Design.numericFont(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.96))
                            .shadow(color: .black.opacity(0.72), radius: 2, y: 1)
                            .padding(.leading, 9)
                            .padding(.bottom, 7)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(tileShape)
            }
            .buttonStyle(.plain)
            .fullResolutionImageDrag(dragItemProvider)

            overlayControl(isHovered)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .animation(.easeInOut(duration: 0.12), value: isHovered)
                .padding(8)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var imageContent: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
        } else {
            Color.black.opacity(0.26)
        }
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
    }
}

private struct FrameCardTagMenuButton: View {
    let tags: [String]
    let suggestedTags: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void
    let onJumpToVideo: (() -> Void)?
    let onShowInFinder: (() -> Void)?
    let onDelete: (() -> Void)?
    var showsUnavailableFileActions = false

    @State private var isMorePresented = false

    var body: some View {
        Button {
            isMorePresented.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 26)
        .help("更多")
        .popover(isPresented: $isMorePresented, arrowEdge: .trailing) {
            morePopover
                .transaction { $0.animation = nil }
        }
    }

    private var morePopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            TagEditorSection(
                domain: .frame,
                tags: tags,
                suggestedTags: suggestedTags,
                onAdd: onAdd,
                onRemove: onRemove
            )
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if onJumpToVideo != nil || onShowInFinder != nil || onDelete != nil || showsUnavailableFileActions {
                Divider()

                actionSection
            }
        }
        .frame(minWidth: 220)
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let onJumpToVideo {
                Button {
                    isMorePresented = false
                    onJumpToVideo()
                } label: {
                    Label("回到原视频位置", systemImage: "arrowshape.turn.up.left.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if onShowInFinder != nil || showsUnavailableFileActions {
                let isEnabled = onShowInFinder != nil

                Button {
                    guard let onShowInFinder else { return }
                    isMorePresented = false
                    onShowInFinder()
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                        .foregroundStyle(frameMenuActionForeground(isEnabled: isEnabled))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }

            if onDelete != nil || showsUnavailableFileActions {
                let isEnabled = onDelete != nil

                Button {
                    guard let onDelete else { return }
                    isMorePresented = false
                    onDelete()
                } label: {
                    Label("删除图片", systemImage: "trash")
                        .foregroundStyle(frameMenuActionForeground(isEnabled: isEnabled, destructive: true))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
        .padding(.vertical, 6)
    }

}

private struct FrameDetailMoreButton: View {
    let tags: [String]
    let suggestedTags: [String]
    let onAdd: ((String) -> Void)?
    let onRemove: ((String) -> Void)?
    let onJumpToVideo: () -> Void
    let onShowInFinder: (() -> Void)?
    let onDelete: (() -> Void)?
    var showsUnavailableFileActions = false

    @State private var isMorePresented = false

    var body: some View {
        Button {
            isMorePresented.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 26)
        .help("更多")
        .popover(isPresented: $isMorePresented, arrowEdge: .trailing) {
            detailPopover
                .transaction { $0.animation = nil }
        }
    }

    private var detailPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onAdd {
                TagEditorSection(
                    domain: .frame,
                    tags: tags,
                    suggestedTags: suggestedTags,
                    emptyTitle: "暂无图片标签",
                    onAdd: onAdd,
                    onRemove: onRemove
                )
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)

                Divider()
            }

            detailActionSection
        }
        .frame(minWidth: 220)
    }

    private var detailActionSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                isMorePresented = false
                onJumpToVideo()
            } label: {
                Label("回到原视频位置", systemImage: "arrowshape.turn.up.left.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if onShowInFinder != nil || showsUnavailableFileActions {
                let isEnabled = onShowInFinder != nil

                Button {
                    guard let onShowInFinder else { return }
                    isMorePresented = false
                    onShowInFinder()
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                        .foregroundStyle(frameMenuActionForeground(isEnabled: isEnabled))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }

            if onDelete != nil || showsUnavailableFileActions {
                let isEnabled = onDelete != nil

                Button {
                    guard let onDelete else { return }
                    isMorePresented = false
                    onDelete()
                } label: {
                    Label("删除图片", systemImage: "trash")
                        .foregroundStyle(frameMenuActionForeground(isEnabled: isEnabled, destructive: true))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
        .padding(.vertical, 6)
    }
}

private func frameMenuActionForeground(isEnabled: Bool, destructive: Bool = false) -> Color {
    guard isEnabled else { return .white.opacity(0.34) }
    return destructive ? .red : .white.opacity(0.88)
}

struct FramesWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Binding var selectedVideoPath: String?
    @Binding var selectedFrameID: UUID?
    let goHome: (String, Double) -> Void
    @AppStorage(AppSettings.Key.frameBoardGridSize) private var frameBoardGridSize = 1
    @AppStorage(AppSettings.Key.storyboardVideoPickerGridSize) private var storyboardVideoPickerGridSize = 2
    @State private var boardMode: FramesBoardMode = .storyboard
    @State private var frameSearchText = ""
    @State private var selectedFrameTags: Set<String> = []
    @State private var isFrameTagFilterPresented = true
    @State private var isStoryboardVideoPickerPresented = false
    @State private var detailFrame: SampledFrame?
    @State private var detailStoryboardItem: FrameStoryboardItem?
    @State private var storyboardThumbnailPrewarmKey = ""
    @State private var pendingStoryboardRecognitionPath: String?

    private var storyboardVideos: [VideoItem] {
        let query = normalizedSearch(frameSearchText)
        let videos = query.isEmpty ? libraryStore.videos : libraryStore.videos.filter { video in
            let tags = libraryStore.videoTags(for: video)
            return normalizedSearch(video.name).contains(query)
                || tags.contains { normalizedSearch($0).contains(query) }
                || libraryStore.sampledFrames(for: video).contains { self.frameMatchesSearch($0, query: query) }
        }

        return videos.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var storyboardVideoPaths: [String] {
        storyboardVideos.map { $0.url.path }
    }

    private var selectedStoryboardVideo: VideoItem? {
        if let selectedVideoPath,
           let video = storyboardVideos.first(where: { $0.url.path == selectedVideoPath }) {
            return video
        }
        return storyboardVideos.first
    }

    private var allExportedFrames: [SampledFrame] {
        libraryStore.collectedFrames
    }

    private var visibleExportedFrames: [SampledFrame] {
        let query = normalizedSearch(frameSearchText)
        let frames = libraryStore.collectedFrames.filter { frame in
            let matchesTags = selectedFrameTags.isEmpty || selectedFrameTags.allSatisfy { frame.tags.contains($0) }
            let matchesSearch = query.isEmpty || self.frameMatchesSearch(frame, query: query)
            return matchesTags && matchesSearch
        }
        return sourceTimeSorted(frames)
    }

    private var gridColumns: [GridItem] {
        let clampedSize = min(max(frameBoardGridSize, 0), 2)
        let count = [5, 4, 3][clampedSize]
        return Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
            count: count
        )
    }

    private var storyboardVideoPickerColumnCount: Int {
        let clampedSize = min(max(storyboardVideoPickerGridSize, 0), 2)
        return max(1, 3 - clampedSize)
    }

    private var storyboardVideoPickerColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8),
            count: storyboardVideoPickerColumnCount
        )
    }

    private var storyboardVideoPickerWidth: CGFloat {
        560
    }

    private var storyboardVideoPickerHeight: CGFloat {
        let maxContentHeight = (1 ... 3)
            .map { columnCount in
                let rowCount = Int(ceil(Double(storyboardVideos.count) / Double(columnCount)))
                let rowHeight = storyboardVideoPickerItemHeight(for: columnCount)
                return CGFloat(rowCount) * rowHeight + CGFloat(max(0, rowCount - 1)) * 8 + 70
            }
            .max() ?? 180
        return min(480, max(180, maxContentHeight))
    }

    var body: some View {
        ZStack {
            frameBoard

            if let frame = detailFrame {
                frameDetailOverlay(frame)
            }
            if let item = detailStoryboardItem {
                storyboardDetailOverlay(item)
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Design.sidebarBg)
        .onAppear {
            syncStoryboardSelectionIfNeeded()
        }
        .onChange(of: boardMode) { _, _ in
            syncStoryboardSelectionIfNeeded()
        }
        .onChange(of: selectedVideoPath) { _, _ in
            guard boardMode == .storyboard else { return }
            prepareStoryboard(for: selectedStoryboardVideo)
        }
        .onChange(of: storyboardVideoPaths) { _, _ in
            syncStoryboardSelectionIfNeeded()
            completePendingStoryboardRecognitionIfReady()
        }
        .onChange(of: libraryStore.sceneDetectionProgress) { _, _ in
            completePendingStoryboardRecognitionIfReady()
        }
        .onChange(of: libraryStore.sceneDetectionErrorByVideoPath) { _, errors in
            if let path = pendingStoryboardRecognitionPath, errors[path] != nil {
                pendingStoryboardRecognitionPath = nil
            }
        }
    }

    private var frameBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            frameBoardToolbar

            TopChromeBoundedContent {
                if boardMode == .collection && isFrameTagFilterPresented {
                    frameTagQuickFilterBar
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                switch boardMode {
                case .storyboard:
                    storyboardFrameBoard
                case .collection:
                    allExportedFrameBoard
                }
            }
        }
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var storyboardFrameBoard: some View {
        if let video = selectedStoryboardVideo {
            let items = storyboardItems(for: video)
            let path = video.url.path

            if items.isEmpty {
                if let progress = libraryStore.sceneDetectionProgress[path] {
                    storyboardRecognitionCenter(progress: progress)
                        .padding(.horizontal, Design.libraryContentInset)
                } else if let message = libraryStore.sceneDetectionErrorByVideoPath[path] {
                    storyboardRecognitionFailureCenter(message: message, video: video)
                        .padding(.horizontal, Design.libraryContentInset)
                } else {
                    VStack(spacing: 12) {
                        storyboardProgressView(for: video)
                        AppEmptyState(
                            title: storyboardEmptyTitle(for: video),
                            systemImage: "rectangle.stack",
                            description: storyboardEmptyDescription(for: video),
                            style: .large
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, Design.libraryContentInset)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        storyboardProgressView(for: video)

                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                storyboardBoardCard(item, title: storyboardCardTitle(for: item, index: index))
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 14)
                }
                .fadingVerticalScrollIndicators()
            }
        } else if libraryStore.videos.isEmpty {
            AppEmptyState(
                title: "暂无视频",
                systemImage: "play.rectangle",
                description: "导入视频后，分镜模式会按视频展示分镜和截图。",
                style: .large
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
        } else {
            AppEmptyState(
                title: "没有匹配视频",
                systemImage: "line.3.horizontal.decrease.circle",
                style: .large
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
        }
    }

    @ViewBuilder
    private var allExportedFrameBoard: some View {
        if allExportedFrames.isEmpty {
            AppEmptyState(
                title: "暂无收藏图片",
                systemImage: "photo.on.rectangle",
                style: .large
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
        } else if visibleExportedFrames.isEmpty {
            AppEmptyState(
                title: "没有匹配图片",
                systemImage: "line.3.horizontal.decrease.circle",
                style: .large
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                    ForEach(Array(visibleExportedFrames.enumerated()), id: \.element.id) { index, frame in
                        frameBoardCard(frame, title: frameCardTitle(for: frame, index: index))
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 14)
            }
            .fadingVerticalScrollIndicators()
        }
    }

    private var frameBoardToolbar: some View {
        LibraryToolbar(placeholder: "", text: $frameSearchText, searchExpands: false) {
            frameModeButton(.collection)
            frameModeButton(.storyboard)
            if boardMode == .collection {
                frameTagFilterButton
            }

            frameGridSizeControl
        }
    }

    private var frameTagFilterButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isFrameTagFilterPresented.toggle()
            }
        } label: {
            frameToolbarIcon(
                systemName: selectedFrameTags.isEmpty ? "tag" : "tag.fill",
                size: 12,
                tint: isFrameTagFilterPresented || !selectedFrameTags.isEmpty
                    ? Design.neutralStrongAccent
                    : Design.libraryToolbarIconTint
            )
                .overlay(alignment: .topTrailing) {
                    if !selectedFrameTags.isEmpty {
                        libraryToolbarBadge(selectedFrameTags.count)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .contentShape(Rectangle())
        .help("图片标签筛选")
    }

    private var frameTagQuickFilterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if libraryStore.allFrameTags.isEmpty {
                HStack(spacing: 8) {
                    Text("暂无图片标签")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 28, alignment: .leading)
            } else {
                let tagCounts = frameTagCountsByName(for: libraryStore.allFrameTags)

                WrappingFilterChipGroup {
                    ForEach(libraryStore.allFrameTags, id: \.self) { tag in
                        QuickFilterChoiceChip(
                            title: tag,
                            count: tagCounts[tag],
                            isSelected: selectedFrameTags.contains(tag)
                        ) {
                            toggleFrameTag(tag)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, Design.libraryContentInset)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func frameModeButton(_ mode: FramesBoardMode) -> some View {
        let isSelected = boardMode == mode
        let button = Button {
            handleFrameModeButtonTap(mode)
        } label: {
            frameModeButtonLabel(for: mode, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .frame(width: frameModeButtonWidth(for: mode), height: Design.libraryToolbarButtonSlotHeight)
        .contentShape(Rectangle())
        .help(frameModeButtonHelp(for: mode))

        if mode == .storyboard {
            button
                .popover(isPresented: $isStoryboardVideoPickerPresented, arrowEdge: .bottom) {
                    storyboardVideoPickerPopover
                }
        } else {
            button
        }
    }

    private func handleFrameModeButtonTap(_ mode: FramesBoardMode) {
        if boardMode == mode {
            if mode == .storyboard && !storyboardVideos.isEmpty {
                isStoryboardVideoPickerPresented.toggle()
            }
            return
        }

        isFrameTagFilterPresented = false
        isStoryboardVideoPickerPresented = false
        withAnimation(.easeInOut(duration: 0.16)) {
            boardMode = mode
        }
    }

    private func frameModeButtonLabel(for mode: FramesBoardMode, isSelected: Bool) -> some View {
        libraryToolbarIcon(
            systemName: mode.icon,
            size: 12,
            tint: isSelected ? Color.white.opacity(0.92) : Design.libraryToolbarIconTint
        )
    }

    private func frameModeButtonWidth(for _: FramesBoardMode) -> CGFloat {
        Design.libraryToolbarButtonSlotWidth
    }

    private func frameModeButtonHelp(for mode: FramesBoardMode) -> String {
        switch mode {
        case .storyboard:
            return selectedStoryboardVideo.map { "分镜：\($0.name)" } ?? "分镜"
        case .collection:
            return "全部图片"
        }
    }

    private var storyboardVideoPickerPopover: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVGrid(columns: storyboardVideoPickerColumns, alignment: .leading, spacing: 8) {
                    ForEach(storyboardVideos) { video in
                        storyboardVideoPickerItem(video)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(10)
                .padding(.bottom, 42)
            }
            .fadingVerticalScrollIndicators()

            storyboardVideoPickerSizeControl
                .padding(12)
        }
        .frame(width: storyboardVideoPickerWidth, height: storyboardVideoPickerHeight)
        .onAppear {
            prewarmStoryboardVideoPickerThumbnailsIfNeeded()
        }
        .onChange(of: storyboardVideoPaths) { _, _ in
            prewarmStoryboardVideoPickerThumbnailsIfNeeded()
        }
    }

    private func storyboardVideoPickerItem(_ video: VideoItem) -> some View {
        let path = video.url.path
        let isSelected = selectedStoryboardVideo?.url.path == path
        let columnCount = storyboardVideoPickerColumnCount

        return Button {
            handleStoryboardVideoPickerSelection(video)
        } label: {
            if columnCount == 1 {
                storyboardVideoPickerListLabel(video: video, path: path)
            } else {
                storyboardVideoPickerGridLabel(video: video, path: path)
            }
        }
        .buttonStyle(.plain)
        .background(isSelected ? .white.opacity(0.08) : .white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(isSelected ? 0.14 : 0.06), lineWidth: 0.8)
        }
    }

    private func storyboardVideoPickerListLabel(
        video: VideoItem,
        path: String
    ) -> some View {
        HStack(spacing: 10) {
            storyboardVideoPickerCover(video: video, path: path)
                .frame(width: 74, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(video.name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(height: storyboardVideoPickerItemHeight(for: 1), alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func storyboardVideoPickerGridLabel(
        video: VideoItem,
        path: String
    ) -> some View {
        let columnCount = storyboardVideoPickerColumnCount
        let metrics = storyboardVideoPickerGridMetrics(for: columnCount)

        return VStack(alignment: .leading, spacing: metrics.contentSpacing) {
            storyboardVideoPickerCover(video: video, path: path)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(video.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.middle)
                .lineSpacing(1)
                .frame(
                    maxWidth: .infinity,
                    minHeight: metrics.titleHeight,
                    maxHeight: metrics.titleHeight,
                    alignment: .topLeading
                )
                .clipped()
        }
        .padding(metrics.padding)
        .frame(height: storyboardVideoPickerItemHeight(for: columnCount), alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private func handleStoryboardVideoPickerSelection(_ video: VideoItem) {
        let path = video.url.path
        libraryStore.loadCachedSceneCuts(for: video)

        if libraryStore.hasSceneRecognitionResult(for: video) {
            pendingStoryboardRecognitionPath = nil
            selectedVideoPath = path
            prepareStoryboard(for: video)
            isStoryboardVideoPickerPresented = false
            return
        }

        pendingStoryboardRecognitionPath = path
        libraryStore.detectSceneCuts(for: video)
    }

    private func completePendingStoryboardRecognitionIfReady() {
        guard let path = pendingStoryboardRecognitionPath,
              libraryStore.sceneDetectionProgress[path] == nil,
              let video = storyboardVideos.first(where: { $0.url.path == path }),
              libraryStore.hasSceneRecognitionResult(for: video)
        else { return }

        pendingStoryboardRecognitionPath = nil
        selectedVideoPath = path
        prepareStoryboard(for: video)
        isStoryboardVideoPickerPresented = false
    }

    private func prewarmStoryboardVideoPickerThumbnailsIfNeeded() {
        let key = storyboardVideoPaths.joined(separator: "\n")
        guard storyboardThumbnailPrewarmKey != key else { return }
        storyboardThumbnailPrewarmKey = key
        libraryStore.prewarmCachedThumbnailImages(for: storyboardVideos)
    }

    private func storyboardVideoPickerCover(video: VideoItem, path: String) -> some View {
        ZStack {
            storyboardVideoPickerThumbnail(path: path)

            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    storyboardVideoPickerRecognitionBadge(for: video)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer(minLength: 0)
                    storyboardVideoPickerTimeBadge(path: path)
                }
            }
            .padding(6)
        }
        .clipped()
    }

    private func storyboardVideoPickerThumbnail(path: String) -> some View {
        ZStack {
            if let image = libraryStore.thumbnailImageByVideoPath[path] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black.opacity(0.28)
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func storyboardVideoPickerRecognitionBadge(for video: VideoItem) -> some View {
        let path = video.url.path
        if let progress = libraryStore.sceneDetectionProgress[path] {
            VStack(alignment: .leading, spacing: 3) {
                Text(progressPercentText(progress))
                    .font(Design.numericCaption2().weight(.bold))
                    .foregroundStyle(.white.opacity(0.92))

                ProgressView(value: normalizedProgressFraction(progress))
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .frame(width: storyboardVideoPickerColumnCount == 1 ? 46 : 72)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(.black.opacity(0.40))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if libraryStore.sceneRecognitionCutCount(for: video) != nil {
            HStack(spacing: 5) {
                Text("已识别")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.14))
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func storyboardVideoPickerTimeBadge(path: String) -> some View {
        if let duration = libraryStore.durationByVideoPath[path] {
            Text(formatDuration(duration))
                .font(Design.numericFont(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.72), radius: 2.4, x: 0, y: 1)
                .shadow(color: .black.opacity(0.38), radius: 7, x: 0, y: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .allowsTightening(true)
        }
    }

    private struct StoryboardVideoPickerGridMetrics {
        let padding: CGFloat
        let thumbnailHeight: CGFloat
        let contentSpacing: CGFloat
        let titleHeight: CGFloat
    }

    private func storyboardVideoPickerGridMetrics(for columnCount: Int) -> StoryboardVideoPickerGridMetrics {
        switch columnCount {
        case 2:
            return StoryboardVideoPickerGridMetrics(
                padding: 8,
                thumbnailHeight: 104,
                contentSpacing: 8,
                titleHeight: 38
            )
        case 3:
            return StoryboardVideoPickerGridMetrics(
                padding: 8,
                thumbnailHeight: 88,
                contentSpacing: 8,
                titleHeight: 38
            )
        default:
            return StoryboardVideoPickerGridMetrics(
                padding: 8,
                thumbnailHeight: 46,
                contentSpacing: 0,
                titleHeight: 0
            )
        }
    }

    private func storyboardVideoPickerItemHeight(for columnCount: Int) -> CGFloat {
        guard columnCount > 1 else { return 62 }
        let metrics = storyboardVideoPickerGridMetrics(for: columnCount)
        return metrics.padding * 2 + metrics.thumbnailHeight + metrics.contentSpacing + metrics.titleHeight
    }

    private var storyboardVideoPickerSizeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { Double(storyboardVideoPickerGridSize) },
                    set: {
                        let nextSize = Int($0.rounded())
                        if storyboardVideoPickerGridSize != nextSize {
                            storyboardVideoPickerGridSize = nextSize
                        }
                    }
                ),
                in: 0...2
            )
            .frame(width: 64)
            .controlSize(.small)

            Image(systemName: "rectangle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.black.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
        .help("调整下拉大小")
    }

    private var frameGridSizeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Design.libraryToolbarIconTint)

            Slider(
                value: Binding(
                    get: { Double(frameBoardGridSize) },
                    set: {
                        let nextSize = Int($0.rounded())
                        if frameBoardGridSize != nextSize {
                            frameBoardGridSize = nextSize
                        }
                    }
                ),
                in: 0...2
            )
            .frame(width: 64)
            .controlSize(.small)

            Image(systemName: "rectangle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Design.libraryToolbarIconTint)
        }
        .padding(.horizontal, 9)
        .frame(height: Design.libraryToolbarButtonSlotHeight)
        .help("图片看板密度")
    }

    private func syncStoryboardSelectionIfNeeded() {
        guard boardMode == .storyboard else { return }
        guard let video = selectedStoryboardVideo else {
            selectedVideoPath = nil
            return
        }

        if selectedVideoPath != video.url.path {
            selectedVideoPath = video.url.path
        }
        prepareStoryboard(for: video)
    }

    private func prepareStoryboard(for video: VideoItem?) {
        guard let video else { return }
        let path = video.url.path

        libraryStore.loadCachedSceneCuts(for: video)
        if libraryStore.sceneCutsByVideoPath[path] != nil {
            libraryStore.hydrateSceneThumbnailsIfNeeded(for: video)
        } else if libraryStore.sceneDetectionProgress[path] == nil,
                  libraryStore.sceneDetectionErrorByVideoPath[path] == nil {
            libraryStore.detectSceneCuts(for: video)
        }
    }

    private func storyboardItems(for video: VideoItem) -> [FrameStoryboardItem] {
        let path = video.url.path
        let samples = libraryStore.sampledFrames(for: video)
        guard let cuts = libraryStore.sceneCutsByVideoPath[path], !cuts.isEmpty else {
            return sourceTimeSorted(samples).map { sample in
                FrameStoryboardItem(
                    id: "sample-\(sample.id.uuidString)",
                    video: video,
                    time: sample.time,
                    cut: nil,
                    sample: sample,
                    thumbnailImage: libraryStore.thumbnailImage(for: sample),
                    sceneIndex: sample.sceneIndex
                )
            }
        }

        let representativeSamples = Dictionary(
            samples
                .filter { $0.kind == .sceneRepresentative }
                .map { (sceneSampleKey(for: $0.time), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var matchedSampleIDs = Set<UUID>()
        var items: [FrameStoryboardItem] = []

        for (index, cut) in cuts.enumerated() {
            let sample = representativeSamples[sceneSampleKey(for: cut.time)]
            if let sample {
                matchedSampleIDs.insert(sample.id)
            }

            items.append(FrameStoryboardItem(
                id: "cut-\(cut.id)",
                video: video,
                time: cut.time,
                cut: cut,
                sample: sample,
                thumbnailImage: sample.flatMap { libraryStore.thumbnailImage(for: $0) }
                    ?? libraryStore.displaySceneCutImage(for: video, cut: cut),
                sceneIndex: index
            ))
        }

        for sample in samples where sample.kind == .screenshot || !matchedSampleIDs.contains(sample.id) {
            items.append(FrameStoryboardItem(
                id: "sample-\(sample.id.uuidString)",
                video: video,
                time: sample.time,
                cut: nil,
                sample: sample,
                thumbnailImage: libraryStore.thumbnailImage(for: sample),
                sceneIndex: sample.sceneIndex
            ))
        }

        return items.sorted {
            if abs($0.time - $1.time) > 0.001 { return $0.time < $1.time }
            return $0.id < $1.id
        }
    }

    private func sourceTimeSorted(_ frames: [SampledFrame]) -> [SampledFrame] {
        frames.sorted {
            if $0.videoName == $1.videoName {
                if abs($0.time - $1.time) > 0.001 { return $0.time < $1.time }
                return $0.createdAt < $1.createdAt
            }
            return $0.videoName.localizedStandardCompare($1.videoName) == .orderedAscending
        }
    }

    private func frameMatchesSearch(_ frame: SampledFrame, query: String) -> Bool {
        normalizedSearch(frame.videoName).contains(query)
            || normalizedSearch(frame.kind == .screenshot ? "截图" : "场景").contains(query)
            || normalizedSearch(clockText(frame.time)).contains(query)
            || frame.tags.contains { normalizedSearch($0).contains(query) }
    }

    private func sceneSampleKey(for time: Double) -> Int {
        Int((time * 50).rounded())
    }

    @ViewBuilder
    private func storyboardProgressView(for video: VideoItem) -> some View {
        let path = video.url.path
        if let progress = libraryStore.sceneDetectionProgress[path] {
            storyboardRecognitionStatus(progress: progress)
                .padding(.vertical, 10)
        } else if let message = libraryStore.sceneDetectionErrorByVideoPath[path] {
            storyboardRecognitionFailureStatus(message: message, video: video)
                .padding(.vertical, 10)
        } else if libraryStore.isHydratingSceneThumbnails(for: video) {
            RecognitionProgressRow(message: "正在补齐分镜缩略图...", progress: nil, showPercent: false)
                .recognitionProgressCard()
        }
    }

    private func storyboardRecognitionCenter(progress: Double) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)

            storyboardRecognitionStatus(progress: progress, showsIcon: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func storyboardRecognitionFailureCenter(message: String, video: VideoItem) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.red.opacity(0.88))

            storyboardRecognitionFailureStatus(message: message, video: video)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func storyboardRecognitionStatus(progress: Double, showsIcon: Bool = true) -> some View {
        HStack(spacing: 9) {
            if showsIcon {
                Image(systemName: "rectangle.stack")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("正在识别分镜")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(progressPercentText(progress))
                .font(Design.numericFont(size: 20, weight: .bold))
                .foregroundStyle(.primary.opacity(0.78))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func storyboardRecognitionFailureStatus(message: String, video: VideoItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.red.opacity(0.9))

            VStack(alignment: .leading, spacing: 3) {
                Text("场景识别失败")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Button {
                libraryStore.detectSceneCuts(for: video, force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("重新识别场景")
        }
        .recognitionProgressCard()
    }

    private func storyboardEmptyTitle(for video: VideoItem) -> String {
        if libraryStore.sceneDetectionProgress[video.url.path] != nil {
            return "正在生成分镜"
        }
        return libraryStore.sceneCutsByVideoPath[video.url.path] == nil ? "暂无分镜" : "这个视频暂无分镜或截图"
    }

    private func storyboardEmptyDescription(for video: VideoItem) -> String? {
        if libraryStore.sceneDetectionProgress[video.url.path] != nil {
            return "识别完成后会显示这个视频的分镜和截图。"
        }
        return "切到主页截图或完成分镜识别后会出现在这里。"
    }

    private func toggleFrameTag(_ tag: String) {
        if selectedFrameTags.contains(tag) {
            selectedFrameTags.remove(tag)
        } else {
            selectedFrameTags.insert(tag)
        }
    }

    private func frameTagCountsByName(for tags: [String]) -> [String: Int] {
        let query = normalizedSearch(frameSearchText)
        let requestedTags = Set(tags)
        var counts: [String: Int] = [:]

        for frame in libraryStore.collectedFrames {
            guard query.isEmpty || frameMatchesSearch(frame, query: query) else { continue }
            let frameTags = Set(frame.tags)
            guard selectedFrameTags.isSubset(of: frameTags) else { continue }

            for tag in frameTags where requestedTags.contains(tag) {
                counts[tag, default: 0] += 1
            }
        }

        return Dictionary(uniqueKeysWithValues: tags.map { ($0, counts[$0, default: 0]) })
    }

    private func frameToolbarIcon(
        systemName: String,
        size: CGFloat,
        tint: Color = Design.libraryToolbarIconTint
    ) -> some View {
        libraryToolbarIcon(systemName: systemName, size: size, tint: tint)
    }

    private func storyboardBoardCard(_ item: FrameStoryboardItem, title: String) -> some View {
        FrameBoardImageTile(
            image: item.thumbnailImage,
            numberText: title,
            onTap: {
                activateStoryboardItem(item)
            },
            dragItemProvider: {
                storyboardDragProvider(for: item)
            }
        ) { _ in
            let sample = latestStoryboardSample(for: item)
            FrameCardTagMenuButton(
                tags: sample?.tags ?? [],
                suggestedTags: libraryStore.allFrameTags,
                onAdd: { addStoryboardFrameTag($0, to: item) },
                onRemove: { tag in
                    if let sample = latestStoryboardSample(for: item) {
                        libraryStore.removeFrameTagOrDeleteIfEmpty(tag, from: sample)
                    }
                },
                onJumpToVideo: { goHome(item.video.url.path, item.time) },
                onShowInFinder: sample.map { sample in
                    { showFrameInFinder(sample) }
                },
                onDelete: sample.map { sample in
                    { deleteFrame(sample) }
                },
                showsUnavailableFileActions: item.cut != nil && sample == nil
            )
        }
        .help(item.sample == nil ? "回到原视频这个分镜" : "\(item.video.name) · \(clockText(item.time))")
    }

    private func activateStoryboardItem(_ item: FrameStoryboardItem) {
        if let sample = item.sample {
            selectedFrameID = sample.id
            detailFrame = latestFrame(sample)
        } else {
            detailStoryboardItem = item
        }
    }

    private func storyboardDragProvider(for item: FrameStoryboardItem) -> NSItemProvider {
        if let sample = item.sample {
            return libraryStore.fullResolutionFrameProvider(for: sample)
        }

        return libraryStore.fullResolutionFrameProvider(
            video: item.video,
            time: storyboardOriginalFrameTime(for: item),
            kind: .sceneRepresentative,
            fallbackImage: item.thumbnailImage
        )
    }

    private func video(for path: String) -> VideoItem {
        libraryStore.videos.first { $0.url.path == path }
            ?? VideoItem(url: URL(fileURLWithPath: path))
    }

    private func frameBoardCard(_ frame: SampledFrame, title: String) -> some View {
        FrameBoardImageTile(
            image: libraryStore.thumbnailImage(for: frame),
            numberText: title,
            onTap: {
                selectedFrameID = frame.id
                detailFrame = latestFrame(frame)
            },
            dragItemProvider: {
                libraryStore.fullResolutionFrameProvider(for: frame)
            }
        ) { _ in
            FrameCardTagMenuButton(
                tags: frame.tags,
                suggestedTags: libraryStore.allFrameTags,
                onAdd: { libraryStore.addFrameTag($0, to: frame) },
                onRemove: { libraryStore.removeFrameTagOrDeleteIfEmpty($0, from: frame) },
                onJumpToVideo: { goHome(frame.videoPath, frame.time) },
                onShowInFinder: { showFrameInFinder(frame) },
                onDelete: { deleteFrame(frame) }
            )
        }
    }

    private func showFrameInFinder(_ frame: SampledFrame) {
        if let imageURL = libraryStore.imageExportURL(for: frame) {
            NSWorkspace.shared.activateFileViewerSelecting([imageURL])
        } else {
            let video = video(for: frame.videoPath)
            NSWorkspace.shared.open(libraryStore.imageExportDestination(for: video))
        }
    }

    private func deleteFrame(_ frame: SampledFrame) {
        libraryStore.deleteSampledFrame(frame)
        if selectedFrameID == frame.id {
            selectedFrameID = nil
            detailFrame = nil
        }
    }

    private func storyboardCardTitle(for item: FrameStoryboardItem, index: Int) -> String {
        let number = String(format: "%02d", (item.sceneIndex ?? index) + 1)
        return number
    }

    private func frameCardTitle(for frame: SampledFrame, index: Int) -> String {
        let number = String(format: "%02d", (frame.sceneIndex ?? index) + 1)
        return number
    }

    private func detailOverlayContainer<Content: View>(
        dismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.44)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)

                content()
            }
            .frame(
                width: proxy.size.width + Design.railWidth,
                height: proxy.size.height,
                alignment: .center
            )
            .offset(x: -Design.railWidth)
        }
        .ignoresSafeArea()
        .zIndex(10)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private func frameDetailOverlay(_ frame: SampledFrame) -> some View {
        detailOverlayContainer(dismiss: { detailFrame = nil }) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    selectedFrameDetailPreview(frame)

                    FrameDetailMoreButton(
                        tags: latestFrame(frame).tags,
                        suggestedTags: libraryStore.allFrameTags,
                        onAdd: {
                            libraryStore.addFrameTag($0, to: frame)
                            detailFrame = latestFrame(frame)
                        },
                        onRemove: {
                            let deleted = libraryStore.removeFrameTagOrDeleteIfEmpty($0, from: frame)
                            detailFrame = deleted ? nil : latestFrame(frame)
                        },
                        onJumpToVideo: {
                            detailFrame = nil
                            goHome(frame.videoPath, frame.time)
                        },
                        onShowInFinder: { showFrameInFinder(frame) },
                        onDelete: {
                            deleteFrame(frame)
                            detailFrame = nil
                        }
                    )
                    .padding(10)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                ColorSwatches(imageData: frame.thumbnailData, orientation: .horizontal)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .frame(width: 720)
            .background(Design.sidebarBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.40), radius: 26, y: 16)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture { }
        }
    }

    private func storyboardDetailOverlay(_ item: FrameStoryboardItem) -> some View {
        detailOverlayContainer(dismiss: { detailStoryboardItem = nil }) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    storyboardItemDetailPreview(item)

                    let sample = latestStoryboardSample(for: item)

                    FrameDetailMoreButton(
                        tags: sample?.tags ?? [],
                        suggestedTags: libraryStore.allFrameTags,
                        onAdd: storyboardTagAddAction(for: item),
                        onRemove: sample.map { sample in
                            { libraryStore.removeFrameTagOrDeleteIfEmpty($0, from: sample) }
                        },
                        onJumpToVideo: {
                            detailStoryboardItem = nil
                            goHome(item.video.url.path, item.time)
                        },
                        onShowInFinder: sample.map { sample in
                            { showFrameInFinder(sample) }
                        },
                        onDelete: sample.map { sample in
                            {
                                deleteFrame(sample)
                                detailStoryboardItem = nil
                            }
                        },
                        showsUnavailableFileActions: item.cut != nil && sample == nil
                    )
                    .padding(10)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                ColorSwatches(imageData: storyboardColorData(for: item), orientation: .horizontal)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .frame(width: 720)
            .background(Design.sidebarBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.40), radius: 26, y: 16)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture { }
        }
    }

    private func selectedFrameDetailPreview(_ frame: SampledFrame) -> some View {
        let fallbackImage = libraryStore.thumbnailImage(for: frame)
        return detailPreviewBox(image: fallbackImage) {
            selectedFramePreview(frame, fallbackImage: fallbackImage)
        }
    }

    private func storyboardItemDetailPreview(_ item: FrameStoryboardItem) -> some View {
        let fallbackImage = storyboardPreviewFallbackImage(for: item)
        return detailPreviewBox(image: fallbackImage) {
            storyboardItemPreview(item, fallbackImage: fallbackImage)
        }
    }

    private func detailPreviewBox<Content: View>(
        image: NSImage?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let previewSize = detailPreviewSize(for: image)
        return content()
            .frame(width: previewSize.width, height: previewSize.height)
            .background(Color.black.opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func detailPreviewSize(for image: NSImage?) -> CGSize {
        let aspectRatio = detailPreviewAspectRatio(for: image)
        let maxWidth: CGFloat = 688
        let maxHeight: CGFloat = 430
        let widthAtMaxHeight = maxHeight * aspectRatio

        if widthAtMaxHeight <= maxWidth {
            return CGSize(width: widthAtMaxHeight, height: maxHeight)
        }

        return CGSize(width: maxWidth, height: maxWidth / aspectRatio)
    }

    private func detailPreviewAspectRatio(for image: NSImage?) -> CGFloat {
        guard
            let size = image?.size,
            size.width > 0,
            size.height > 0
        else { return 16 / 9 }

        return min(10, max(0.1, size.width / size.height))
    }

    private func latestFrame(_ frame: SampledFrame) -> SampledFrame {
        libraryStore.sampledFrame(id: frame.id) ?? frame
    }

    private func latestStoryboardSample(for item: FrameStoryboardItem) -> SampledFrame? {
        if let sample = item.sample {
            return latestFrame(sample)
        }

        guard let cut = item.cut else { return nil }
        return libraryStore.sampledFrames(for: item.video).first {
            $0.kind == .sceneRepresentative &&
            sceneSampleKey(for: $0.time) == sceneSampleKey(for: cut.time)
        }
    }

    private func storyboardTagAddAction(for item: FrameStoryboardItem) -> ((String) -> Void)? {
        guard latestStoryboardSample(for: item) != nil || item.cut != nil else { return nil }
        return { tag in
            addStoryboardFrameTag(tag, to: item)
        }
    }

    private func addStoryboardFrameTag(_ tag: String, to item: FrameStoryboardItem) {
        if let sample = latestStoryboardSample(for: item) {
            libraryStore.addFrameTag(tag, to: sample)
            return
        }

        guard let cut = item.cut else { return }
        let video = item.video
        let sceneIndex = item.sceneIndex
        Task {
            if let frame = await libraryStore.ensureSceneFrameExported(
                video: video,
                cut: cut,
                sceneIndex: sceneIndex
            ) {
                libraryStore.addFrameTag(tag, to: frame)
            }
        }
    }

    @ViewBuilder
    private func storyboardItemPreview(_ item: FrameStoryboardItem, fallbackImage: NSImage? = nil) -> some View {
        FullResolutionFramePreview(
            videoURL: item.video.url,
            time: storyboardOriginalFrameTime(for: item),
            fallbackImage: fallbackImage ?? storyboardPreviewFallbackImage(for: item),
            dragItemProvider: { storyboardDragProvider(for: item) }
        )
    }

    private func storyboardPreviewFallbackImage(for item: FrameStoryboardItem) -> NSImage? {
        item.sample.flatMap { libraryStore.thumbnailImage(for: $0) } ?? item.thumbnailImage
    }

    private func storyboardColorData(for item: FrameStoryboardItem) -> Data {
        if let data = item.sample?.thumbnailData {
            return data
        }
        return jpegData(from: item.thumbnailImage) ?? Data()
    }

    private func jpegData(from image: NSImage?) -> Data? {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
    }

    @ViewBuilder
    private func selectedFramePreview(_ frame: SampledFrame, fallbackImage: NSImage? = nil) -> some View {
        FullResolutionFramePreview(
            videoURL: URL(fileURLWithPath: frame.videoPath),
            time: frame.time,
            fallbackImage: fallbackImage ?? libraryStore.thumbnailImage(for: frame),
            dragItemProvider: { libraryStore.fullResolutionFrameProvider(for: frame) }
        )
    }

    private func storyboardOriginalFrameTime(for item: FrameStoryboardItem) -> Double {
        if let sample = item.sample {
            return sample.time
        }
        return item.cut == nil ? item.time : item.time + 0.08
    }
}
