//
//  PreviewPanelView+ExportPanel.swift
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

private func previewStableHexKey(for string: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1_099_511_628_211
    }
    return String(hash, radix: 16)
}

private enum ExportFrameTagPreviewItem {
    case tag(String)
    case overflow(Int)
    case add
}

extension PreviewPanelView {
    func videoDisplayName(for video: VideoItem) -> String {
        libraryStore.videoSourceTitle(for: video) ?? video.name
    }

    func previewHeader(for video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: Design.previewHeaderTitleTagGap) {
            Text(videoDisplayName(for: video))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, minHeight: Design.previewHeaderTitleLineHeight, maxHeight: Design.previewHeaderTitleLineHeight, alignment: .leading)
                .layoutPriority(1)
                .accessibilityIdentifier("preview_video_title_\(previewStableHexKey(for: video.url.path))")

            videoTagStrip(for: video)
        }
        .padding(.top, Design.previewHeaderTopInset)
        .padding(.bottom, Design.previewHeaderBottomInset)
        .frame(maxWidth: .infinity, minHeight: Design.previewHeaderHeight, maxHeight: Design.previewHeaderHeight, alignment: .topLeading)
        .clipped()
    }

    func previewFrameDragProvider(for video: VideoItem) -> NSItemProvider {
        controller.pause()
        return libraryStore.fullResolutionFrameProvider(
            video: video,
            time: controller.elapsed,
            kind: .screenshot
        )
    }

    func exportPanel(for video: VideoItem, isOverlay: Bool) -> some View {
        let frames = libraryStore.sampledFrames(for: video)
        let clips = libraryStore.audioClips(for: video)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                exportFilterPicker
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isOverlay {
                    previewExportOverlayButton(
                        systemImage: "xmark",
                        help: "关闭导出区"
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isExportPanelPresented = false
                        }
                    }
                }
            }

            exportPanelContent(video: video, frames: frames, clips: clips, isOverlay: isOverlay)
        }
        .padding(Design.previewExportPanelPadding)
        .background(isOverlay ? Color.black.opacity(0.72) : Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(isOverlay ? 0.18 : 0.09), lineWidth: 0.8)
        }
        .shadow(color: isOverlay ? .black.opacity(0.32) : .clear, radius: 18, y: 10)
    }

    func previewExportOverlayButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if systemImage.hasPrefix("square.and.arrow") {
                floatingExportButtonIcon(
                    systemImage: "square.and.arrow.up",
                    size: Design.previewExportOverlayButtonSize,
                    iconSize: Design.previewExportOverlayButtonIconSize
                )
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: Design.previewExportOverlayButtonIconSize, weight: .semibold))
                    .frame(
                        width: Design.previewExportOverlayButtonSize,
                        height: Design.previewExportOverlayButtonSize
                    )
                    .background(.black.opacity(0.44))
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.88))
        .accessibilityLabel(help)
        .accessibilityIdentifier(previewExportButtonIdentifier(for: help))
    }

    func previewExportButtonIdentifier(for help: String) -> String {
        switch help {
        case "打开导出区":
            return "preview_export_panel_open_button"
        case "关闭导出区":
            return "preview_export_panel_close_button"
        default:
            return "preview_export_panel_action_button"
        }
    }

    var exportFilterPicker: some View {
        HStack(spacing: 3) {
            ForEach(ExportPanelFilter.allCases) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        exportPanelFilter = filter
                    }
                    startMusicDetectionIfNeeded(for: libraryStore.selectedVideo, filter: filter)
                } label: {
                    exportFilterButtonLabel(for: filter)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("显示\(filter.rawValue)导出项")
                .accessibilityIdentifier("export_filter_\(exportFilterAccessibilityKey(filter))_button")
            }
        }
        .padding(3)
        .background(.white.opacity(0.055))
        .clipShape(Capsule())
    }

    func exportFilterButtonLabel(for filter: ExportPanelFilter) -> some View {
        let isSelected = exportPanelFilter == filter
        let runningProgress = exportFilterRunningProgress(for: filter)
        let title: String = {
            guard let runningProgress else { return filter.rawValue }
            return runningProgress.percentText ?? "0%"
        }()

        return Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .frame(maxWidth: .infinity, alignment: .center)
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(isSelected ? Color.white.opacity(0.14) : Color.clear)
        .clipShape(Capsule())
        .contentShape(Capsule())
    }

    func exportFilterAccessibilityKey(_ filter: ExportPanelFilter) -> String {
        switch filter {
        case .recent:
            return "recent"
        case .images:
            return "images"
        case .audio:
            return "audio"
        case .music:
            return "music"
        }
    }

    func exportFilterRunningProgress(for filter: ExportPanelFilter) -> (progress: Double, percentText: String?)? {
        guard
            filter == .music,
            let video = libraryStore.selectedVideo,
            case let .running(message) = libraryStore.musicDetectionStatusByVideoPath[video.url.path]
        else { return nil }

        guard let progress = activityProgressValue(from: message) else {
            return (0.04, nil)
        }
        return (progress, progressPercentText(progress))
    }

    func startMusicDetectionIfNeeded(for video: VideoItem?, filter: ExportPanelFilter) {
        guard filter == .music, let video else { return }
        let path = video.url.path
        guard libraryStore.musicsByVideoPath[path, default: []].isEmpty else { return }

        switch libraryStore.musicDetectionStatusByVideoPath[path] {
        case nil, .idle:
            libraryStore.detectMusic(for: video)
        case .running, .completed, .failed:
            return
        }
    }

    func exportPanelContent(video: VideoItem, frames: [SampledFrame], clips: [AudioClipItem], isOverlay: Bool) -> some View {
        let sortedFrames = frames.sorted { $0.createdAt < $1.createdAt }
        let sortedAudioClips = clips.sorted { $0.createdAt < $1.createdAt }
        let recentItems = exportPanelFilter == .recent ? recentExportPanelItems() : []
        let recentAudioClipIndexByID = recentExportAudioClipIndexByID(from: recentItems)
        let visibleItemIDs: [String] = {
            switch exportPanelFilter {
            case .recent:
                return recentItems.map(\.id)
            case .images:
                return sortedFrames.map { ExportPanelItem.frame($0).id }
            case .audio:
                return sortedAudioClips.map { ExportPanelItem.audio($0).id }
            case .music:
                return []
            }
        }()

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    switch exportPanelFilter {
                    case .recent:
                        if recentItems.isEmpty {
                            AppEmptyState(title: "暂无素材", style: .inline, minHeight: 80)
                        } else {
                            ForEach(recentItems) { item in
                                switch item {
                                case .frame(let frame):
                                    exportFrameRow(frame, highlightIntensity: exportPanelHighlightedItemID == item.id ? exportPanelHighlightIntensity : 0)
                                        .id(item.id)
                                case .audio(let clip):
                                    exportAudioClipRow(clip, index: recentAudioClipIndexByID[clip.id], showsSource: true, highlightIntensity: exportPanelHighlightedItemID == item.id ? exportPanelHighlightIntensity : 0)
                                        .id(item.id)
                                case .transcript(let export):
                                    exportTranscriptRow(export, highlightIntensity: exportPanelHighlightedItemID == item.id ? exportPanelHighlightIntensity : 0)
                                        .id(item.id)
                                case .transcriptProgress(let job):
                                    exportTranscriptProgressRow(job, highlightIntensity: exportPanelHighlightedItemID == item.id ? exportPanelHighlightIntensity : 0)
                                        .id(item.id)
                                }
                            }
                        }
                    case .images:
                        if frames.isEmpty {
                            AppEmptyState(title: "暂无图片", style: .inline, minHeight: 80)
                        } else {
                            ForEach(sortedFrames) { frame in
                                let itemID = ExportPanelItem.frame(frame).id
                                exportFrameRow(frame, highlightIntensity: exportPanelHighlightedItemID == itemID ? exportPanelHighlightIntensity : 0)
                                    .id(itemID)
                            }
                        }
                    case .audio:
                        if clips.isEmpty {
                            AppEmptyState(title: "暂无声音", style: .inline, minHeight: 80)
                        } else {
                            ForEach(Array(sortedAudioClips.enumerated()), id: \.element.id) { index, clip in
                                let itemID = ExportPanelItem.audio(clip).id
                                exportAudioClipRow(clip, index: index + 1, highlightIntensity: exportPanelHighlightedItemID == itemID ? exportPanelHighlightIntensity : 0)
                                    .id(itemID)
                            }
                        }
                    case .music:
                        exportMusicRecognitionPanel(for: video)
                    }
                }
                .padding(.trailing, 2)
            }
            .fadingVerticalScrollIndicators()
            .onAppear {
                syncExportPanelTracking(
                    ids: visibleItemIDs,
                    proxy: proxy,
                    shouldTrackNewItems: false,
                    shouldScrollToLatest: true
                )
            }
            .onChange(of: visibleItemIDs) { _, ids in
                syncExportPanelTracking(ids: ids, proxy: proxy, shouldTrackNewItems: true)
            }
            .onChange(of: exportPanelFilter) { _, _ in
                syncExportPanelTracking(
                    ids: visibleItemIDs,
                    proxy: proxy,
                    shouldTrackNewItems: false,
                    shouldScrollToLatest: true
                )
            }
        }
    }

    func exportPanelItems(
        frames: [SampledFrame],
        clips: [AudioClipItem],
        transcripts: [TranscriptExportItem] = [],
        transcriptJobs: [TranscriptExportJob] = []
    ) -> [ExportPanelItem] {
        let frameItems = frames.map(ExportPanelItem.frame)
        let clipItems = clips.map(ExportPanelItem.audio)
        let transcriptItems = transcripts.map(ExportPanelItem.transcript)
        let transcriptProgressItems = transcriptJobs.map(ExportPanelItem.transcriptProgress)
        return (frameItems + clipItems + transcriptItems + transcriptProgressItems).sorted { $0.createdAt < $1.createdAt }
    }

    func recentExportPanelItems() -> [ExportPanelItem] {
        let visibleVideoPaths = Set(libraryStore.videos.map { $0.url.path })
        let recentFrames = libraryStore.sampledFrames.reversed().lazy
            .filter { visibleVideoPaths.contains($0.videoPath) }
            .prefix(Self.exportPanelRecentItemLimit)
        let recentAudioClips = libraryStore.audioClips.reversed().lazy
            .filter { visibleVideoPaths.contains($0.videoPath) }
            .prefix(Self.exportPanelRecentItemLimit)
        let recentTranscripts = libraryStore.transcriptExports.reversed().lazy
            .filter { visibleVideoPaths.contains($0.videoPath) }
            .prefix(Self.exportPanelRecentItemLimit)
        let recentTranscriptJobs = libraryStore.transcriptExportJobs.values.reversed().lazy
            .filter { visibleVideoPaths.contains($0.videoPath) }
            .prefix(Self.exportPanelRecentItemLimit)
        let items = exportPanelItems(
            frames: Array(recentFrames),
            clips: Array(recentAudioClips),
            transcripts: Array(recentTranscripts),
            transcriptJobs: Array(recentTranscriptJobs)
        )
        guard items.count > Self.exportPanelRecentItemLimit else { return items }
        return Array(items.suffix(Self.exportPanelRecentItemLimit))
    }

    func recentExportAudioClipIndexByID(from items: [ExportPanelItem]) -> [UUID: Int] {
        let sortedClips = items.compactMap { item -> AudioClipItem? in
            if case let .audio(clip) = item { return clip }
            return nil
        }
        return Dictionary(
            uniqueKeysWithValues: sortedClips.enumerated().map { ($0.element.id, $0.offset + 1) }
        )
    }

    func syncExportPanelTracking(
        ids: [String],
        proxy: ScrollViewProxy,
        shouldTrackNewItems: Bool,
        shouldScrollToLatest: Bool = false
    ) {
        let currentIDs = Set(ids)
        defer { exportPanelKnownItemIDs = currentIDs }

        if shouldScrollToLatest {
            scrollExportPanelToLatest(ids: ids, proxy: proxy, animated: false)
        }

        guard shouldTrackNewItems, let newestID = ids.last(where: { !exportPanelKnownItemIDs.contains($0) }) else {
            return
        }

        exportPanelHighlightTask?.cancel()
        exportPanelHighlightedItemID = newestID
        exportPanelHighlightIntensity = 1
        scrollExportPanelToLatest(ids: ids, proxy: proxy, animated: false)

        exportPanelHighlightTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 1.05)) {
                exportPanelHighlightIntensity = 0
            }
            try? await Task.sleep(nanoseconds: 1_080_000_000)
            guard !Task.isCancelled else { return }
            if exportPanelHighlightIntensity <= 0.001 {
                exportPanelHighlightedItemID = nil
            }
        }
    }

    func scrollExportPanelToLatest(ids: [String], proxy: ScrollViewProxy, animated: Bool) {
        guard let newestID = ids.last else { return }
        Task { @MainActor in
            await Task.yield()
            if animated {
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(newestID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(newestID, anchor: .bottom)
            }
        }
    }

    func exportSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }

    func exportFrameRow(_ frame: SampledFrame, showsMetadata: Bool = true, highlightIntensity: Double = 0) -> some View {
        let title = exportFrameDisplayTitle(for: frame)
        let highlight = min(1, max(0, highlightIntensity))

        return HStack(spacing: 9) {
            Button {
                jumpToExportLocation(path: frame.videoPath, time: frame.time)
            } label: {
                HStack(spacing: 9) {
                    exportFramePreview(
                        image: libraryStore.thumbnailImage(for: frame),
                        showsMetadata: showsMetadata
                    )

                    if showsMetadata {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.86))
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)

                            Spacer(minLength: 4)

                            exportFrameTagPreview(for: frame)
                        }
                        .frame(height: Self.exportRowContentHeight, alignment: .top)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: Self.exportRowContentHeight, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("跳到这张画面")
            .accessibilityIdentifier("export_frame_row_\(frame.id.uuidString)")

            exportItemActionColumn(
                showInFinderURL: libraryStore.imageExportURL(for: frame),
                accessibilityIdentifierPrefix: "export_frame_\(frame.id.uuidString)",
                jumpHelp: "跳到这张画面",
                deleteHelp: "删除这张画面",
                onJump: {
                    jumpToExportLocation(path: frame.videoPath, time: frame.time)
                },
                onDelete: {
                    libraryStore.deleteSampledFrame(frame)
                }
            )
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, Self.exportRowVerticalPadding)
        .frame(height: Self.exportRowHeight)
        .background(exportRowBackground(isActive: false, progress: 0, highlightIntensity: highlight))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(exportRowStrokeColor(highlightIntensity: highlight, fallback: .white.opacity(0.07)), lineWidth: 0.8 + 0.4 * highlight)
        }
        .fullResolutionImageDrag {
            libraryStore.fullResolutionFrameProvider(for: frame)
        }
    }

    func exportFramePreview(image: NSImage?, showsMetadata: Bool) -> some View {
        let previewWidth = exportFramePreviewWidth(for: image, showsMetadata: showsMetadata)
        let previewShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

        return ZStack {
            previewShape
                .fill(.black.opacity(0.28))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                    .frame(width: previewWidth, height: Self.exportRowContentHeight)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: previewWidth, height: Self.exportRowContentHeight)
        .clipShape(previewShape)
        .overlay {
            previewShape
                .stroke(.white.opacity(0.06), lineWidth: 0.7)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    func exportFramePreviewWidth(for image: NSImage?, showsMetadata: Bool) -> CGFloat {
        guard !showsMetadata else { return Self.exportFramePreviewWidth }
        let aspectRatio = exportFramePreviewAspectRatio(for: image)
        return min(
            Self.exportFramePreviewMaxWidth,
            max(Self.exportFramePreviewMinWidth, Self.exportRowContentHeight * aspectRatio)
        )
    }

    func exportFramePreviewAspectRatio(for image: NSImage?) -> CGFloat {
        guard
            let size = image?.size,
            size.width > 0,
            size.height > 0
        else { return 16 / 9 }
        return size.width / size.height
    }

    func exportDocumentPreview(systemImage: String, tint: Color) -> some View {
        let previewShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

        return ZStack {
            previewShape
                .fill(.white.opacity(0.075))

            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: Self.exportTranscriptIconWidth, height: Self.exportRowContentHeight)
        .clipShape(previewShape)
        .overlay {
            previewShape
                .stroke(.white.opacity(0.08), lineWidth: 0.7)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    func exportFrameDisplayTitle(for frame: SampledFrame) -> String {
        guard let video = libraryStore.selectedVideo(for: frame.videoPath) else {
            return frame.videoName
        }
        return videoDisplayName(for: video)
    }

    func exportFrameTagPreview(for frame: SampledFrame) -> some View {
        GeometryReader { proxy in
            let rows = exportFrameTagTwoLineLayout(tags: frame.tags, maxWidth: proxy.size.width)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .center, spacing: 4) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                            exportFrameTagPreviewItem(item, frame: frame)
                        }
                    }
                    .frame(height: 18, alignment: .leading)
                }
            }
            .frame(width: proxy.size.width, height: 38, alignment: .topLeading)
            .clipped()
        }
        .frame(height: 38, alignment: .leading)
        .clipped()
    }

    @ViewBuilder
    private func exportFrameTagPreviewItem(_ item: ExportFrameTagPreviewItem, frame: SampledFrame) -> some View {
        switch item {
        case .tag(let tag):
            VideoTagChip(tag: tag, size: .mini)
        case .overflow(let hiddenCount):
            VideoTagOverflowChip(count: hiddenCount)
        case .add:
            InlineTagAddButton(
                title: nil,
                domain: .frame,
                tags: frame.tags,
                suggestedTags: libraryStore.allFrameTags,
                buttonSize: 15,
                onAdd: { libraryStore.addFrameTag($0, to: frame) },
                onRemove: { libraryStore.removeFrameTagOrDeleteIfEmpty($0, from: frame) }
            )
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func exportFrameTagTwoLineLayout(tags: [String], maxWidth: CGFloat) -> [[ExportFrameTagPreviewItem]] {
        let availableWidth = max(0, maxWidth)
        guard availableWidth > 0 else { return [] }

        guard !tags.isEmpty else {
            return [[.add]]
        }

        for visibleCount in stride(from: tags.count, through: 1, by: -1) {
            let hiddenCount = tags.count - visibleCount
            var items = tags.prefix(visibleCount).map(ExportFrameTagPreviewItem.tag)

            if hiddenCount > 0 {
                items.append(.overflow(hiddenCount))
            }

            items.append(.add)
            if let rows = exportFrameTagRows(items, maxWidth: availableWidth) {
                return rows
            }
        }

        var fallbackItems: [ExportFrameTagPreviewItem] = [.tag(tags[0])]
        if tags.count > 1 {
            fallbackItems.append(.overflow(tags.count - 1))
        }
        fallbackItems.append(.add)
        return exportFrameTagRows(fallbackItems, maxWidth: availableWidth) ?? [fallbackItems]
    }

    private func exportFrameTagRows(_ items: [ExportFrameTagPreviewItem], maxWidth: CGFloat) -> [[ExportFrameTagPreviewItem]]? {
        var rows: [[ExportFrameTagPreviewItem]] = [[]]
        var currentWidth: CGFloat = 0

        for item in items {
            let width = exportFrameTagPreviewItemWidth(item)
            let nextWidth = rows[rows.count - 1].isEmpty
                ? width
                : currentWidth + 4 + width

            if !rows[rows.count - 1].isEmpty, nextWidth > maxWidth {
                guard rows.count < 2 else { return nil }
                rows.append([item])
                currentWidth = width
                continue
            }

            rows[rows.count - 1].append(item)
            currentWidth = nextWidth
        }

        return rows
    }

    private func exportFrameTagPreviewItemWidth(_ item: ExportFrameTagPreviewItem) -> CGFloat {
        switch item {
        case .tag(let tag):
            return exportFrameMiniTagChipWidth(for: tag)
        case .overflow(let hiddenCount):
            return exportFrameTagOverflowChipWidth(for: hiddenCount)
        case .add:
            return 15
        }
    }

    func exportFrameMiniTagChipWidth(for tag: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let textWidth = (tag as NSString).size(withAttributes: [.font: font]).width
        return min(VideoTagChipSize.mini.maxTextWidth, ceil(textWidth))
            + VideoTagChipSize.mini.horizontalPadding * 2
    }

    func exportFrameTagOverflowChipWidth(for hiddenCount: Int) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let textWidth = ("+\(hiddenCount)" as NSString).size(withAttributes: [.font: font]).width
        return ceil(textWidth) + 12
    }

    func exportAudioTagPreview(for clip: AudioClipItem) -> some View {
        HStack(spacing: 4) {
            if !clip.tags.isEmpty {
                ForEach(Array(clip.tags.prefix(2)), id: \.self) { tag in
                    VideoTagChip(tag: tag, size: .mini)
                }
                if clip.tags.count > 2 {
                    VideoTagOverflowChip(count: clip.tags.count - 2)
                }
            }

            InlineTagAddButton(
                title: "声音标签",
                domain: .audio,
                tags: clip.tags,
                suggestedTags: libraryStore.allAudioTags,
                buttonSize: 15,
                onAdd: { libraryStore.addAudioTag($0, to: clip) },
                onRemove: { libraryStore.removeAudioTag($0, from: clip) }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    func exportAudioClipRow(_ clip: AudioClipItem, index: Int?, showsSource: Bool = false, highlightIntensity: Double = 0) -> some View {
        let isPlaying = activeExportAudioClipID == clip.id
        let highlight = min(1, max(0, highlightIntensity))
        let progress = isPlaying ? activeExportAudioProgress : 0
        let duration = max(0, clip.outTime - clip.inTime)
        let title = showsSource ? clip.videoName : audioClipTitle(index: index)
        let waveformHeight: CGFloat = showsSource ? 40 : 58

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: showsSource ? 3 : 4) {
                if showsSource {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 16, alignment: .center)
                }

                HStack(spacing: 8) {
                    exportAudioTagPreview(for: clip)
                        .layoutPriority(1)

                    Spacer(minLength: 0)
                }
                .frame(height: 16, alignment: .center)

                exportAudioWaveformWithTimecode(
                    samples: clip.waveformSamples,
                    isPlaying: isPlaying,
                    progress: progress,
                    duration: duration,
                    height: waveformHeight
                )
            }
            .frame(height: Self.exportRowContentHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleExportAudioClipPlayback(clip)
            }
            .itemProviderDrag(audioClipDragProvider(for: clip))
            .accessibilityLabel(isPlaying ? "暂停导出声音片段" : "播放导出声音片段")
            .accessibilityIdentifier("export_audio_row_\(clip.id.uuidString)")

            exportItemActionColumn(
                showInFinderURL: libraryStore.audioClipFileURL(for: clip),
                accessibilityIdentifierPrefix: "export_audio_\(clip.id.uuidString)",
                jumpHelp: "回到原视频位置",
                deleteHelp: "删除声音片段",
                onJump: {
                    jumpToExportLocation(path: clip.videoPath, time: clip.inTime)
                },
                onDelete: {
                    deleteExportAudioClip(clip)
                }
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, Self.exportRowVerticalPadding)
        .frame(height: Self.exportRowHeight)
        .background(exportRowBackground(isActive: isPlaying, progress: 0, highlightIntensity: highlight))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(exportRowStrokeColor(highlightIntensity: highlight, fallback: isPlaying ? .white.opacity(0.20) : .white.opacity(0.07)), lineWidth: 0.8 + 0.4 * highlight)
        }
        .onAppear {
            libraryStore.loadAudioClipWaveformIfNeeded(clip)
        }
        .itemProviderDrag(audioClipDragProvider(for: clip))
    }

    func exportTranscriptProgressRow(_ job: TranscriptExportJob, highlightIntensity: Double = 0) -> some View {
        let highlight = min(1, max(0, highlightIntensity))
        let progress = normalizedProgressFraction(job.progress)
        let isFailed = job.isFailed
        let tint = isFailed ? Color.red.opacity(0.86) : Design.annotationAccent

        return HStack(alignment: .center, spacing: 10) {
            exportDocumentPreview(systemImage: isFailed ? "exclamationmark.triangle.fill" : "doc.text", tint: tint)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(job.videoName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)

                    Text(isFailed ? "失败" : progressPercentText(progress))
                        .font(Design.numericCaption2(weight: .semibold))
                        .foregroundStyle(isFailed ? tint.opacity(0.86) : .white.opacity(0.58))
                }

                Text(isFailed ? "字幕导出失败：\(job.errorMessage ?? "未知错误")" : "正在生成分镜字幕索引")
                    .font(.caption2)
                    .foregroundStyle(isFailed ? tint.opacity(0.78) : .white.opacity(0.48))
                    .lineLimit(1)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .frame(height: 4)
            }
            .frame(height: Self.exportRowContentHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, Self.exportRowVerticalPadding)
        .frame(height: Self.exportRowHeight)
        .background(exportRowBackground(isActive: true, progress: progress, highlightIntensity: highlight))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(exportRowStrokeColor(highlightIntensity: highlight, fallback: tint.opacity(0.22)), lineWidth: 0.8 + 0.4 * highlight)
        }
    }

    func transcriptExportFileURL(for export: TranscriptExportItem) -> URL? {
        FileManager.default.fileExists(atPath: export.filePath) ? URL(fileURLWithPath: export.filePath) : nil
    }

    func transcriptExportDragProvider(for export: TranscriptExportItem) -> (() -> NSItemProvider)? {
        guard let fileURL = transcriptExportFileURL(for: export) else { return nil }
        let suggestedName = fileURL.lastPathComponent.isEmpty ? "\(export.videoName).md" : fileURL.lastPathComponent

        return {
            existingFileItemProvider(
                for: fileURL,
                suggestedName: suggestedName,
                fallbackTypeIdentifier: UTType.plainText.identifier,
                errorDomain: "LapianBao.TranscriptDragExport",
                missingFileMessage: "字幕文件不存在"
            )
        }
    }

    func transcriptCharacterCount(for export: TranscriptExportItem) -> Int {
        let segments = libraryStore.transcriptSegmentsByVideoPath[export.videoPath, default: []]
        let segmentText = segments
            .map(\.text)
            .joined()
        if !segmentText.isEmpty {
            return visibleCharacterCount(in: segmentText)
        }

        guard let markdown = try? String(contentsOfFile: export.filePath, encoding: .utf8) else { return 0 }
        let transcriptText = markdown
            .components(separatedBy: "## 原脚本")
            .last?
            .components(separatedBy: .newlines)
            .map { line -> String in
                guard let range = line.range(of: "] ") else { return line }
                return String(line[range.upperBound...])
            }
            .joined() ?? markdown
        return visibleCharacterCount(in: transcriptText)
    }

    func visibleCharacterCount(in text: String) -> Int {
        text.filter { !$0.isWhitespace && !$0.isNewline }.count
    }

    func exportTranscriptRow(_ export: TranscriptExportItem, highlightIntensity: Double = 0) -> some View {
        let highlight = min(1, max(0, highlightIntensity))
        let characterCount = transcriptCharacterCount(for: export)
        let dragProvider = transcriptExportDragProvider(for: export)

        return HStack(alignment: .center, spacing: 10) {
            Button {
                jumpToExportLocation(path: export.videoPath, time: export.startTime)
            } label: {
                HStack(spacing: 10) {
                    exportDocumentPreview(systemImage: "doc.text", tint: Design.annotationAccent)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(export.videoName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)

                        Spacer(minLength: 4)

                        Text("\(characterCount) 字")
                            .font(Design.numericCaption2())
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                    }
                    .frame(height: Self.exportRowContentHeight, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.exportRowContentHeight, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("跳到字幕起点")
            .accessibilityIdentifier("export_transcript_row_\(export.id.uuidString)")

            exportItemActionColumn(
                showInFinderURL: transcriptExportFileURL(for: export),
                accessibilityIdentifierPrefix: "export_transcript_\(export.id.uuidString)",
                jumpHelp: "跳到字幕起点",
                deleteHelp: "删除字幕条目",
                onJump: {
                    jumpToExportLocation(path: export.videoPath, time: export.startTime)
                },
                onDelete: {
                    libraryStore.deleteTranscriptExport(export)
                }
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, Self.exportRowVerticalPadding)
        .frame(height: Self.exportRowHeight)
        .background(exportRowBackground(isActive: false, progress: 0, highlightIntensity: highlight))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(exportRowStrokeColor(highlightIntensity: highlight, fallback: .white.opacity(0.07)), lineWidth: 0.8 + 0.4 * highlight)
        }
        .itemProviderDrag(dragProvider)
    }

    func exportAudioPlayButton(clip: AudioClipItem, isPlaying: Bool, progress: Double) -> some View {
        Button {
            toggleExportAudioClipPlayback(clip)
        } label: {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(isPlaying ? 0.13 : 0.08))
                    if progress > 0 {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(0.22))
                            .frame(width: proxy.size.width * CGFloat(min(1, max(0, progress))))
                    }
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(.white.opacity(isPlaying ? 0.20 : 0.10), lineWidth: 0.8)
                }
            }
            .frame(width: 58, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!FileManager.default.fileExists(atPath: clip.videoPath))
        .accessibilityLabel(isPlaying ? "暂停导出声音片段" : "播放导出声音片段")
        .accessibilityIdentifier("export_audio_play_button_\(clip.id.uuidString)")
    }

    func jumpToExportLocation(path: String, time: Double) {
        stopExportAudioClipPlayback()
        controller.pause()

        if path == libraryStore.selectedVideo?.url.path {
            controller.seekToSeconds(time)
            return
        }

        guard libraryStore.selectedVideo(for: path) != nil else { return }
        libraryStore.selectVideo(path: path)
        DispatchQueue.main.async {
            AppEventBus.postSeekRequest(path: path, time: time)
        }
    }

    func exportItemActionColumn(
        showInFinderURL: URL?,
        showInFinderHelp: String = "在访达显示",
        accessibilityIdentifierPrefix: String,
        jumpHelp: String,
        deleteHelp: String,
        onJump: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        let buttonSize = Self.exportActionButtonSize
        let spacing = max(0, (Self.exportRowContentHeight - buttonSize * 3) / 2)

        return VStack(spacing: spacing) {
            Button {
                guard let showInFinderURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([showInFinderURL])
            } label: {
                exportItemActionIcon(
                    "folder",
                    tint: .white.opacity(showInFinderURL == nil ? 0.28 : 0.70),
                    size: buttonSize
                )
            }
            .buttonStyle(.plain)
            .disabled(showInFinderURL == nil)
            .accessibilityLabel(showInFinderHelp)
            .accessibilityIdentifier("\(accessibilityIdentifierPrefix)_show_in_finder_button")

            Button(action: onJump) {
                exportItemActionIcon("arrowshape.turn.up.left", tint: .white.opacity(0.70), size: buttonSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(jumpHelp)
            .accessibilityIdentifier("\(accessibilityIdentifierPrefix)_jump_button")

            Button(role: .destructive, action: onDelete) {
                exportItemActionIcon("trash", tint: .white.opacity(0.70), size: buttonSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(deleteHelp)
            .accessibilityIdentifier("\(accessibilityIdentifierPrefix)_delete_button")
        }
        .frame(width: buttonSize)
        .frame(height: Self.exportRowContentHeight, alignment: .center)
    }

    func exportItemActionIcon(_ systemImage: String, tint: Color, size: CGFloat = 26) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: min(13, size - 9), weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    }

    func exportAudioWaveformWithTimecode(
        samples: [Double]?,
        isPlaying: Bool,
        progress: Double,
        duration: Double,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            AudioClipWaveformStrip(
                samples: samples,
                isActive: isPlaying,
                progress: progress,
                playbackDuration: duration,
                smoothsPlaybackProgress: true
            )

            if isPlaying, duration > 0 {
                SmoothTimelineProgressReader(
                    progress: progress,
                    duration: duration,
                    isPlaying: true
                ) { displayedProgress in
                    exportAudioWaveformTimecodeLabel(
                        formatDuration(duration * min(1, max(0, displayedProgress))),
                        isPlaying: true
                    )
                }
            } else {
                exportAudioWaveformTimecodeLabel(
                    audioClipTimecode(duration: duration, progress: progress, isPlaying: false),
                    isPlaying: false
                )
            }
        }
        .frame(height: height)
    }

    func exportAudioWaveformTimecodeLabel(_ text: String, isPlaying: Bool) -> some View {
        Text(text)
            .font(Design.numericCaption2(weight: .semibold))
            .foregroundStyle(.white.opacity(isPlaying ? 0.84 : 0.62))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.44))
            .clipShape(Capsule())
            .padding(.trailing, 4)
            .padding(.bottom, 3)
            .allowsHitTesting(false)
    }

    func audioClipTimecode(duration: Double, progress: Double, isPlaying: Bool) -> String {
        guard isPlaying else { return formatDuration(duration) }
        return formatDuration(duration * min(1, max(0, progress)))
    }

    func exportRowBackground(isActive: Bool, progress: Double, highlightIntensity: Double = 0) -> some View {
        let highlight = min(1, max(0, highlightIntensity))
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(isActive ? 0.075 : 0.055))
                if highlight > 0 {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Design.captureFrameAccent.opacity(0.18 * highlight))
                }
                if progress > 0 {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(0.13))
                        .frame(width: proxy.size.width * CGFloat(min(1, max(0, progress))))
                }
            }
        }
    }

    func exportRowStrokeColor(highlightIntensity: Double, fallback: Color) -> Color {
        let highlight = min(1, max(0, highlightIntensity))
        guard highlight > 0 else { return fallback }
        return Design.captureFrameAccent.opacity(0.52 * highlight)
    }

    func toggleExportAudioClipPlayback(_ clip: AudioClipItem) {
        guard FileManager.default.fileExists(atPath: clip.videoPath) else { return }

        if activeExportAudioClipID == clip.id {
            stopExportAudioClipPlayback()
            return
        }

        stopExportAudioClipPlayback()
        controller.pause()

        let item = AVPlayerItem(url: URL(fileURLWithPath: clip.videoPath))
        let player = AVPlayer(playerItem: item)
        let start = CMTime(seconds: max(0, clip.inTime), preferredTimescale: 600)
        let end = max(clip.inTime, clip.outTime)
        exportAudioPlayer = player
        activeExportAudioClipID = clip.id
        activeExportAudioProgress = 0

        exportAudioTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            let duration = max(0.001, end - clip.inTime)
            activeExportAudioProgress = min(1, max(0, (seconds - clip.inTime) / duration))
            if seconds >= end {
                stopExportAudioClipPlayback()
            }
        }

        exportAudioPlaybackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            stopExportAudioClipPlayback()
        }

        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            player.play()
        }
    }

    func stopExportAudioClipPlayback() {
        if let exportAudioTimeObserver, let exportAudioPlayer {
            exportAudioPlayer.removeTimeObserver(exportAudioTimeObserver)
            self.exportAudioTimeObserver = nil
        }

        exportAudioPlayer?.pause()
        exportAudioPlayer = nil
        activeExportAudioClipID = nil
        activeExportAudioProgress = 0

        if let exportAudioPlaybackEndObserver {
            NotificationCenter.default.removeObserver(exportAudioPlaybackEndObserver)
            self.exportAudioPlaybackEndObserver = nil
        }
    }

    func deleteExportAudioClip(_ clip: AudioClipItem) {
        if activeExportAudioClipID == clip.id {
            stopExportAudioClipPlayback()
        }
        libraryStore.deleteAudioClip(clip)
    }

    @ViewBuilder
    func exportMusicRecognitionPanel(for video: VideoItem) -> some View {
        let path = video.url.path
        let status = libraryStore.musicDetectionStatusByVideoPath[path]
        let songs = libraryStore.musicsByVideoPath[path, default: []]

        Group {
            if case .running = status {
                ForEach(songs) { song in
                    ExportMusicRecognitionRow(song: song, videoPath: path) {
                        controller.pause()
                        controller.seekToSeconds(song.detectedAt)
                    }
                }
            } else if case let .failed(message) = status {
                RecognitionFailureIndicator(message: message, minHeight: 82)
            } else if status == .completed, songs.isEmpty {
                AppEmptyState(
                    title: "暂无音乐识别结果",
                    style: .compact,
                    minHeight: 82,
                    showsBackground: true
                )
            } else if songs.isEmpty {
                AppEmptyState(
                    title: "暂无音乐识别记录",
                    systemImage: "music.note",
                    description: "选择音乐后会自动开始识别。",
                    style: .compact,
                    minHeight: 82
                )
            } else {
                ForEach(songs) { song in
                    ExportMusicRecognitionRow(song: song, videoPath: path) {
                        controller.pause()
                        controller.seekToSeconds(song.detectedAt)
                    }
                }
            }
        }
        .background(alignment: .topLeading) {
            exportMusicWaveformRenderPrewarmProbe(songs: songs)
        }
    }

    private func exportMusicWaveformRenderPrewarmProbe(songs: [MusicRecognitionItem]) -> some View {
        GeometryReader { proxy in
            let signature = exportMusicWaveformRenderPrewarmSignature(
                songs: songs,
                panelWidth: proxy.size.width
            )

            Color.clear
                .task(id: signature) {
                    guard proxy.size.width > 0 else { return }
                    let requests = exportMusicWaveformRenderPrewarmRequests(
                        songs: songs,
                        panelWidth: proxy.size.width
                    )
                    guard !requests.isEmpty else { return }
                    await DownloadedMusicWaveformRenderPrewarmQueue.shared.prewarm(requests)
                }
        }
        .allowsHitTesting(false)
    }

    private func exportMusicWaveformRenderPrewarmSignature(
        songs: [MusicRecognitionItem],
        panelWidth: CGFloat
    ) -> Int {
        guard panelWidth > 0 else { return 0 }

        let contentWidth = max(0, panelWidth - 14)
        guard contentWidth > 0 else { return 0 }

        var hasher = Hasher()
        hasher.combine(Int(contentWidth.rounded(.up)))

        for song in songs {
            for job in musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs, recognitionID: song.id) where completedMusicFileURL(for: job) != nil {
                hasher.combine(job.id)
                hasher.combine(job.filePath)
                hasher.combine(exportMusicWaveformSamplesForRenderPrewarm(job)?.count ?? 0)
            }
        }

        return hasher.finalize()
    }

    private func exportMusicWaveformRenderPrewarmRequests(
        songs: [MusicRecognitionItem],
        panelWidth: CGFloat
    ) -> [DownloadedMusicWaveformRenderPrewarmRequest] {
        let contentWidth = max(0, panelWidth - 14)
        guard contentWidth > 0 else { return [] }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return songs.flatMap { song in
            musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs, recognitionID: song.id).compactMap { job in
                guard completedMusicFileURL(for: job) != nil else { return nil }
                guard let samples = exportMusicWaveformSamplesForRenderPrewarm(job), !samples.isEmpty else { return nil }
                return DownloadedMusicWaveformRenderPrewarmRequest(
                    samples: samples,
                    size: CGSize(width: contentWidth, height: 32),
                    scale: scale,
                    isCompact: true
                )
            }
        }
    }

    private func exportMusicWaveformSamplesForRenderPrewarm(_ job: MusicDownloadJob) -> [Double]? {
        if let samples = job.waveformSamples, !samples.isEmpty {
            return samples
        }

        guard let filePath = job.filePath else { return nil }
        if let samples = libraryStore.localMusicWaveformSamplesByPath[filePath], !samples.isEmpty {
            return samples
        }

        let normalizedPath = LibraryStore.normalizedLocalFilePath(filePath)
        guard
            let localAsset = libraryStore.localMusicAssets.first(where: {
                LibraryStore.normalizedLocalFilePath($0.filePath) == normalizedPath
            })
        else { return nil }
        return libraryStore.localMusicWaveformSamplesByPath[localAsset.filePath]
    }

}
