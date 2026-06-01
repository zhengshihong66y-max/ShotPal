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

    var isScreenshot: Bool {
        sample?.kind == .screenshot
    }

    var isExportedScene: Bool {
        sample?.kind == .sceneRepresentative && sample?.isExported == true
    }
}

struct StoryboardVideoTimeline: View {
    let cuts: [Double]

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            var base = Path()
            base.addRoundedRect(
                in: CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2),
                cornerSize: CGSize(width: 1, height: 1)
            )
            context.fill(base, with: .color(.white.opacity(0.14)))

            for progress in cuts {
                let clamped = min(1, max(0, progress))
                let x = size.width * CGFloat(clamped)
                var line = Path()
                line.addRoundedRect(
                    in: CGRect(x: x - 0.5, y: 1, width: 1, height: size.height - 2),
                    cornerSize: CGSize(width: 0.5, height: 0.5)
                )
                context.fill(line, with: .color(.white.opacity(0.62)))
            }
        }
    }
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
    var isSelected = false
    var selectedStrokeColor: Color = .white.opacity(0.36)
    var selectedStrokeWidth: CGFloat = 1.1
    let onTap: () -> Void
    let dragItemProvider: (() -> NSItemProvider)?
    @ViewBuilder let overlayControl: (_ isHovered: Bool) -> OverlayControl

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                imageContent
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(tileShape)
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.56)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 48)
                        .allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text(numberText)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.96))
                            .shadow(color: .black.opacity(0.72), radius: 2, y: 1)
                            .padding(.leading, 9)
                            .padding(.bottom, 7)
                    }
                    .overlay {
                        if isSelected {
                            tileShape
                                .strokeBorder(selectedStrokeColor, lineWidth: selectedStrokeWidth)
                        }
                    }
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

struct FramesWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Binding var selectedVideoPath: String?
    @Binding var selectedFrameID: UUID?
    let goHome: (String, Double) -> Void
    @AppStorage("frameBoardGridSize") private var frameBoardGridSize = 1
    @AppStorage("storyboardVideoPickerGridSize") private var storyboardVideoPickerGridSize = 2
    @State private var boardMode: FramesBoardMode = .storyboard
    @State private var frameSearchText = ""
    @State private var selectedFrameTags: Set<String> = []
    @State private var isFrameTagFilterPresented = false
    @State private var isStoryboardVideoPickerPresented = false
    @State private var detailFrame: SampledFrame?
    @State private var detailStoryboardItem: FrameStoryboardItem?
    @State private var frameAnalysisState: FrameAnalysisState = .idle
    @State private var analyzedFrameID: UUID?
    @State private var frameAnalysisTask: Task<Void, Never>?

    private var storyboardVideos: [VideoItem] {
        let query = normalizedSearch(frameSearchText)
        let videos = query.isEmpty ? libraryStore.videos : libraryStore.videos.filter { video in
            let tags = libraryStore.tagsByVideoPath[video.url.path, default: []]
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

    private var tagFilteredFrames: [SampledFrame] {
        visibleExportedFrames
    }

    private var tagSections: [(key: String, title: String, frames: [SampledFrame])] {
        guard !selectedFrameTags.isEmpty else { return [] }
        return selectedFrameTags.sorted().compactMap { tag -> (key: String, title: String, frames: [SampledFrame])? in
            let frames = tagFilteredFrames.filter { $0.tags.contains(tag) }
            guard !frames.isEmpty else { return nil }
            return (key: tag, title: tag, frames: frames)
        }
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
        }
        .onDisappear {
            frameAnalysisTask?.cancel()
        }
    }

    private var frameBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            frameBoardToolbar

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
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var storyboardFrameBoard: some View {
        if let video = selectedStoryboardVideo {
            let items = storyboardItems(for: video)

            if items.isEmpty {
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
                .padding(.horizontal, 14)
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
                .scrollIndicators(.hidden)
                .background(HiddenScrollIndicators())
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
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())
        }
    }

    @ViewBuilder
    private var tagFilteredFrameBoard: some View {
        if selectedFrameTags.isEmpty {
            AppEmptyState(
                title: "请选择图片标签",
                systemImage: "tag",
                description: libraryStore.allFrameTags.isEmpty ? "给导出的图片添加标签后，这里会显示标签筛选。" : "点右上角标签按钮选择要查看的标签。",
                style: .large
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
        } else if tagFilteredFrames.isEmpty {
            AppEmptyState(
                title: "没有匹配标签的画面",
                systemImage: "tag",
                style: .large
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(tagSections, id: \.key) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            frameSectionDivider(section.title)
                            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                                ForEach(Array(section.frames.enumerated()), id: \.element.id) { index, frame in
                                    frameBoardCard(frame, title: frameCardTitle(for: frame, index: index))
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())
        }
    }

    private var frameBoardToolbar: some View {
        HStack(spacing: Design.libraryToolbarButtonGap) {
            LibraryToolbarSearchField(placeholder: "搜索图片、标签", text: $frameSearchText)

            frameModeButton(.collection)
            frameModeButton(.storyboard)
            if boardMode == .collection {
                frameTagFilterButton
            }

            frameGridSizeControl
        }
        .frame(minHeight: Design.libraryToolbarHeight)
        .padding(.horizontal, 14)
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
                .background(isFrameTagFilterPresented ? Color.white.opacity(0.10) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if !selectedFrameTags.isEmpty {
                        Text("\(selectedFrameTags.count)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Design.neutralBadgeFill)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -3)
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
            HStack(spacing: 8) {
                Label("图片标签", systemImage: "tag")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if !selectedFrameTags.isEmpty {
                    Text("\(selectedFrameTags.count)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                Button {
                    selectedFrameTags.removeAll()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(selectedFrameTags.isEmpty)
                .help("显示全部图片")

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isFrameTagFilterPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("收起标签筛选")
            }

            if libraryStore.allFrameTags.isEmpty {
                Text("暂无图片标签")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(minHeight: 28, alignment: .leading)
            } else {
                WrappingFilterChipGroup {
                    QuickFilterChoiceChip(
                        title: "全部",
                        systemImage: "photo.on.rectangle",
                        isSelected: selectedFrameTags.isEmpty
                    ) {
                        selectedFrameTags.removeAll()
                    }

                    ForEach(libraryStore.allFrameTags, id: \.self) { tag in
                        QuickFilterChoiceChip(
                            title: tag,
                            tagColorKey: tag,
                            isSelected: selectedFrameTags.contains(tag)
                        ) {
                            toggleFrameTag(tag)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, 14)
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
        Image(systemName: mode.icon)
            .font(.system(size: 12, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Design.libraryToolbarIconTint)
            .frame(
                width: frameModeButtonWidth(for: mode),
                height: Design.libraryToolbarButtonSlotHeight,
                alignment: .center
            )
            .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())

            storyboardVideoPickerSizeControl
                .padding(12)
        }
        .frame(width: storyboardVideoPickerWidth, height: storyboardVideoPickerHeight)
    }

    private func storyboardVideoPickerItem(_ video: VideoItem) -> some View {
        let path = video.url.path
        let isSelected = selectedStoryboardVideo?.url.path == path
        let cuts = libraryStore.sceneCutProgressesByVideoPath[path] ?? normalizedSceneCutProgresses(for: video)
        let columnCount = storyboardVideoPickerColumnCount

        return Button {
            selectedVideoPath = path
            prepareStoryboard(for: video)
            isStoryboardVideoPickerPresented = false
        } label: {
            if columnCount == 1 {
                storyboardVideoPickerListLabel(video: video, path: path, cuts: cuts, isSelected: isSelected)
            } else {
                storyboardVideoPickerGridLabel(video: video, path: path, cuts: cuts, isSelected: isSelected)
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
        path: String,
        cuts: [Double],
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 10) {
            storyboardVideoPickerThumbnail(path: path)
                .frame(width: 74, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(video.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if let duration = libraryStore.durationByVideoPath[path] {
                        Text(formatDuration(duration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                StoryboardVideoTimeline(cuts: cuts)
                    .frame(height: 14)
            }

            storyboardVideoPickerSelectionIcon(isSelected: isSelected, size: 13)
        }
        .padding(8)
        .contentShape(Rectangle())
    }

    private func storyboardVideoPickerGridLabel(
        video: VideoItem,
        path: String,
        cuts: [Double],
        isSelected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                storyboardVideoPickerThumbnail(path: path)
                    .frame(maxWidth: .infinity)
                    .frame(height: storyboardVideoPickerThumbnailHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                storyboardVideoPickerSelectionIcon(isSelected: isSelected, size: 12)
                    .padding(5)
                    .background(.black.opacity(0.34))
                    .clipShape(Circle())
                    .padding(5)
            }

            Text(video.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            if let duration = libraryStore.durationByVideoPath[path] {
                Text(formatDuration(duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            StoryboardVideoTimeline(cuts: cuts)
                .frame(height: 12)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: storyboardVideoPickerItemHeight(for: storyboardVideoPickerColumnCount), alignment: .topLeading)
        .contentShape(Rectangle())
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

    private func storyboardVideoPickerSelectionIcon(isSelected: Bool, size: CGFloat) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isSelected ? Design.neutralStrongAccent : .secondary)
    }

    private var storyboardVideoPickerThumbnailHeight: CGFloat {
        storyboardVideoPickerColumnCount == 2 ? 96 : 68
    }

    private func storyboardVideoPickerItemHeight(for columnCount: Int) -> CGFloat {
        columnCount == 1 ? 62 : (columnCount == 2 ? 154 : 126)
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
        HStack(spacing: 5) {
            Image(systemName: "square.grid.3x3")
                .font(.caption2)
                .foregroundStyle(.secondary)

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
            .frame(width: 56)
            .controlSize(.small)
            .help("图片看板密度")

            Image(systemName: "rectangle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var frameTagFilterPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("图片标签筛选")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全部") {
                    selectedFrameTags.removeAll()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(selectedFrameTags.isEmpty)
            }

            if libraryStore.allFrameTags.isEmpty {
                AppEmptyState(title: "暂无图片标签", style: .inline, alignment: .leading)
                    .frame(minHeight: 36)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(libraryStore.allFrameTags, id: \.self) { tag in
                            Button {
                                toggleFrameTag(tag)
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: selectedFrameTags.contains(tag) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selectedFrameTags.contains(tag) ? Design.neutralStrongAccent : .secondary)
                                        .frame(width: 15)
                                    VideoTagColorDot(tag: tag)
                                    Text(tag)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(selectedFrameTags.contains(tag) ? Color.white.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 260)
                .scrollIndicators(.hidden)
            }
        }
        .padding(12)
        .frame(width: 280)
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
        } else if libraryStore.sceneDetectionProgress[path] == nil {
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

    private func normalizedSceneCutProgresses(for video: VideoItem) -> [Double] {
        let path = video.url.path
        guard let duration = libraryStore.durationByVideoPath[path], duration > 0 else { return [] }
        return libraryStore.sceneCutsByVideoPath[path, default: []]
            .map { min(1, max(0, $0.time / duration)) }
    }

    @ViewBuilder
    private func storyboardProgressView(for video: VideoItem) -> some View {
        let path = video.url.path
        if let progress = libraryStore.sceneDetectionProgress[path] {
            RecognitionProgressRow(message: "正在识别分镜...", progress: progress)
                .recognitionProgressCard()
        } else if libraryStore.isHydratingSceneThumbnails(for: video) {
            RecognitionProgressRow(message: "正在补齐分镜缩略图...", progress: nil, showPercent: false)
                .recognitionProgressCard()
        }
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

    private func frameToolbarIcon(
        systemName: String,
        size: CGFloat,
        tint: Color = Design.libraryToolbarIconTint
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(
                width: Design.libraryToolbarButtonSlotWidth,
                height: Design.libraryToolbarButtonSlotHeight,
                alignment: .center
            )
    }

    private func toolbarMenuLabel(title: String, systemImage: String, maxWidth: CGFloat) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Design.libraryToolbarIconTint)
                .frame(width: 14)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: maxWidth, minHeight: Design.libraryToolbarButtonSlotHeight, maxHeight: Design.libraryToolbarButtonSlotHeight)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.7)
        }
    }

    private func frameSectionDivider(_ title: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
    }

    private func storyboardBoardCard(_ item: FrameStoryboardItem, title: String) -> some View {
        FrameBoardImageTile(
            image: item.thumbnailImage,
            numberText: title,
            isSelected: item.sample?.id == selectedFrameID,
            selectedStrokeColor: item.isScreenshot ? Design.screenshotFrameAccent.opacity(0.98) : .white.opacity(0.36),
            selectedStrokeWidth: item.isScreenshot ? 1.4 : 1.1,
            onTap: {
                activateStoryboardItem(item)
            },
            dragItemProvider: {
                storyboardDragProvider(for: item)
            }
        ) { _ in
            if let sample = item.sample {
                InlineTagEditorButton(
                    title: "图片标签",
                    tags: sample.tags,
                    suggestedTags: libraryStore.allFrameTags,
                    onAdd: { libraryStore.addFrameTag($0, to: sample) },
                    onRemove: { libraryStore.removeFrameTag($0, from: sample) }
                )
            } else if let cut = item.cut {
                Button {
                    libraryStore.markSceneFrameExported(video: item.video, cut: cut, sceneIndex: item.sceneIndex)
                } label: {
                    cardOverlayExportButtonIcon()
                }
                .buttonStyle(.plain)
                .help("导出这张分镜")
            }
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

    private func frameBoardCard(_ frame: SampledFrame, title: String) -> some View {
        FrameBoardImageTile(
            image: libraryStore.thumbnailImage(for: frame),
            numberText: title,
            isSelected: selectedFrameID == frame.id,
            onTap: {
                selectedFrameID = frame.id
                detailFrame = latestFrame(frame)
            },
            dragItemProvider: {
                libraryStore.fullResolutionFrameProvider(for: frame)
            }
        ) { _ in
            InlineTagEditorButton(
                title: "图片标签",
                tags: frame.tags,
                suggestedTags: libraryStore.allFrameTags,
                onAdd: { libraryStore.addFrameTag($0, to: frame) },
                onRemove: { libraryStore.removeFrameTag($0, from: frame) }
            )
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
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(frame.videoName)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(clockText(frame.time)) · \(frame.kind == .screenshot ? "手动截图帧" : "场景代表帧")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        detailFrame = nil
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }

                selectedFramePreview(frame)
                    .frame(maxWidth: .infinity, maxHeight: 430)
                    .background(Color.black.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                ColorSwatches(imageData: frame.thumbnailData, orientation: .horizontal)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    InlineTagEditorButton(
                        title: "图片标签",
                        tags: latestFrame(frame).tags,
                        suggestedTags: libraryStore.allFrameTags,
                        onAdd: { libraryStore.addFrameTag($0, to: frame); detailFrame = latestFrame(frame) },
                        onRemove: { libraryStore.removeFrameTag($0, from: frame); detailFrame = latestFrame(frame) }
                    )

                    Spacer()

                    Button {
                        detailFrame = nil
                        goHome(frame.videoPath, frame.time)
                    } label: {
                        Label("回到原视频", systemImage: "arrowshape.turn.up.left.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
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
        }
    }

    private func storyboardDetailOverlay(_ item: FrameStoryboardItem) -> some View {
        detailOverlayContainer(dismiss: { detailStoryboardItem = nil }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(storyboardCardTitle(for: item, index: item.sceneIndex ?? 0))
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(item.video.name) · \(clockText(item.time))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        detailStoryboardItem = nil
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }

                storyboardItemPreview(item)
                    .frame(maxWidth: .infinity, maxHeight: 430)
                    .background(Color.black.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                ColorSwatches(imageData: storyboardColorData(for: item), orientation: .horizontal)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    if let sample = item.sample {
                        InlineTagEditorButton(
                            title: "图片标签",
                            tags: sample.tags,
                            suggestedTags: libraryStore.allFrameTags,
                            onAdd: { libraryStore.addFrameTag($0, to: sample) },
                            onRemove: { libraryStore.removeFrameTag($0, from: sample) }
                        )
                    }

                    Spacer()

                    Button {
                        detailStoryboardItem = nil
                        goHome(item.video.url.path, item.time)
                    } label: {
                        Label("回到原视频", systemImage: "arrowshape.turn.up.left.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
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
        }
    }

    private func latestFrame(_ frame: SampledFrame) -> SampledFrame {
        libraryStore.sampledFrame(id: frame.id) ?? frame
    }

    @ViewBuilder
    private func storyboardItemPreview(_ item: FrameStoryboardItem) -> some View {
        FullResolutionFramePreview(
            videoURL: item.video.url,
            time: storyboardOriginalFrameTime(for: item),
            fallbackImage: item.sample.flatMap { libraryStore.thumbnailImage(for: $0) } ?? item.thumbnailImage,
            dragItemProvider: { storyboardDragProvider(for: item) }
        )
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
    private func selectedFramePreview(_ frame: SampledFrame) -> some View {
        FullResolutionFramePreview(
            videoURL: URL(fileURLWithPath: frame.videoPath),
            time: frame.time,
            fallbackImage: libraryStore.thumbnailImage(for: frame),
            dragItemProvider: { libraryStore.fullResolutionFrameProvider(for: frame) }
        )
    }

    private func storyboardOriginalFrameTime(for item: FrameStoryboardItem) -> Double {
        if let sample = item.sample {
            return sample.time
        }
        return item.cut == nil ? item.time : item.time + 0.08
    }

    private func frameAnalysisView(for frame: SampledFrame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                analyzeFrame(frame)
            } label: {
                Label(isAnalyzingCurrentFrame(frame) ? "正在分析" : "分析画面", systemImage: "sparkles")
            }
            .disabled(isAnalyzingCurrentFrame(frame))
            .buttonStyle(.bordered)
            .help("使用本机 Ollama 视觉模型分析景别、构图和色调")

            switch frameAnalysisState {
            case .idle:
                EmptyView()
            case .loading where analyzedFrameID == frame.id:
                RecognitionProgressRow(
                    message: "正在调用本机视觉模型...",
                    progress: nil,
                    showPercent: false
                )
                .recognitionProgressCard()
            case let .loaded(analysis) where analyzedFrameID == frame.id:
                FrameAnalysisSummary(analysis: analysis)
            case let .failed(message) where analyzedFrameID == frame.id:
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.red.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
        }
    }

    private func isAnalyzingCurrentFrame(_ frame: SampledFrame) -> Bool {
        if case .loading = frameAnalysisState, analyzedFrameID == frame.id {
            return true
        }
        return false
    }

    private func analyzeFrame(_ frame: SampledFrame) {
        frameAnalysisTask?.cancel()
        analyzedFrameID = frame.id
        frameAnalysisState = .loading
        libraryStore.prepareExternalServiceWork()

        frameAnalysisTask = Task { @MainActor in
            do {
                let analysis = try await LocalFrameAnalyzer.analyze(imageData: frame.thumbnailData)
                guard !Task.isCancelled, analyzedFrameID == frame.id else { return }
                frameAnalysisState = .loaded(analysis)
            } catch {
                guard !Task.isCancelled, analyzedFrameID == frame.id else { return }
                frameAnalysisState = .failed(LocalFrameAnalyzer.userFacingMessage(for: error))
            }
        }
    }
}
