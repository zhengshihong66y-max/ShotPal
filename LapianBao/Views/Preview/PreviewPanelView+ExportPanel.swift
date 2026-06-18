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
        .help(help)
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
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                case .audio(let clip):
                                    exportAudioClipRow(clip, index: recentAudioClipIndexByID[clip.id], showsSource: true, highlightIntensity: exportPanelHighlightedItemID == item.id ? exportPanelHighlightIntensity : 0)
                                        .id(item.id)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                case .transcript(let export):
                                    exportTranscriptRow(export, highlightIntensity: exportPanelHighlightedItemID == item.id ? exportPanelHighlightIntensity : 0)
                                        .id(item.id)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                case .transcriptProgress(let job):
                                    exportTranscriptProgressRow(job, highlightIntensity: exportPanelHighlightedItemID == item.id ? exportPanelHighlightIntensity : 0)
                                        .id(item.id)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    case .music:
                        exportMusicRecognitionPanel(for: video)
                    }
                }
                .padding(.trailing, 2)
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: visibleItemIDs)
            }
            .fadingVerticalScrollIndicators()
            .onAppear {
                syncExportPanelTracking(ids: visibleItemIDs, proxy: proxy, shouldTrackNewItems: false)
            }
            .onChange(of: visibleItemIDs) { _, ids in
                syncExportPanelTracking(ids: ids, proxy: proxy, shouldTrackNewItems: true)
            }
            .onChange(of: exportPanelFilter) { _, _ in
                syncExportPanelTracking(ids: visibleItemIDs, proxy: proxy, shouldTrackNewItems: false)
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
        return exportPanelItems(
            frames: libraryStore.sampledFrames.filter { visibleVideoPaths.contains($0.videoPath) },
            clips: libraryStore.audioClips.filter { visibleVideoPaths.contains($0.videoPath) },
            transcripts: libraryStore.transcriptExports.filter { visibleVideoPaths.contains($0.videoPath) },
            transcriptJobs: libraryStore.transcriptExportJobs.values.filter { visibleVideoPaths.contains($0.videoPath) }
        )
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

    func syncExportPanelTracking(ids: [String], proxy: ScrollViewProxy, shouldTrackNewItems: Bool) {
        let currentIDs = Set(ids)
        defer { exportPanelKnownItemIDs = currentIDs }

        guard shouldTrackNewItems, let newestID = ids.last(where: { !exportPanelKnownItemIDs.contains($0) }) else {
            return
        }

        exportPanelHighlightTask?.cancel()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            exportPanelHighlightedItemID = newestID
            exportPanelHighlightIntensity = 1
            proxy.scrollTo(newestID, anchor: .bottom)
        }

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
            .help("跳到这张画面")

            exportItemActionColumn(
                showInFinderURL: libraryStore.imageExportURL(for: frame),
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
        let visibleLimit = 5
        let hasOverflow = frame.tags.count > visibleLimit
        let visibleTagCount = hasOverflow ? visibleLimit - 1 : visibleLimit
        let visibleTags = Array(frame.tags.prefix(visibleTagCount))
        let overflowCount = max(0, frame.tags.count - visibleTagCount)

        return HStack(alignment: .center, spacing: 4) {
            WrappingFilterChipGroup(spacing: 4, rowSpacing: 4) {
                ForEach(visibleTags, id: \.self) { tag in
                    VideoTagChip(tag: tag, size: .mini)
                }

                if overflowCount > 0 {
                    VideoTagOverflowChip(count: overflowCount)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: 40, alignment: .topLeading)
            .clipped()

            InlineTagAddButton(
                title: "图片标签",
                domain: .frame,
                tags: frame.tags,
                suggestedTags: libraryStore.allFrameTags,
                buttonSize: 15,
                onAdd: { libraryStore.addFrameTag($0, to: frame) },
                onRemove: { libraryStore.removeFrameTagOrDeleteIfEmpty($0, from: frame) }
            )
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
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
            .help(isPlaying ? "暂停声音片段" : "播放导出的声音片段")
            .itemProviderDrag(audioClipDragProvider(for: clip))

            exportItemActionColumn(
                showInFinderURL: libraryStore.audioClipFileURL(for: clip),
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

                Text(job.errorMessage ?? "正在生成分镜字幕索引")
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
        .help(isFailed ? "字幕导出失败" : "字幕导出中")
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
            .help("跳到字幕起点")

            exportItemActionColumn(
                showInFinderURL: transcriptExportFileURL(for: export),
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
        .help(isPlaying ? "暂停声音片段" : "播放导出的声音片段")
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
            .help(showInFinderURL == nil ? "文件不存在" : showInFinderHelp)

            Button(action: onJump) {
                exportItemActionIcon("arrowshape.turn.up.left", tint: .white.opacity(0.70), size: buttonSize)
            }
            .buttonStyle(.plain)
            .help(jumpHelp)

            Button(role: .destructive, action: onDelete) {
                exportItemActionIcon("trash", tint: .white.opacity(0.70), size: buttonSize)
            }
            .buttonStyle(.plain)
            .help(deleteHelp)
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

        if case .running = status {
            ForEach(songs) { song in
                ExportMusicRecognitionRow(song: song, videoPath: path) {
                    controller.pause()
                    controller.seekToSeconds(song.detectedAt)
                }
            }
        } else if case .failed = status {
            AppEmptyState(
                title: "暂无音乐识别结果",
                style: .compact,
                minHeight: 82,
                showsBackground: true
            )
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

}
