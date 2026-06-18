//
//  AudioWorkspaceRows.swift
//  LapianBao
//
//  Row layout and row-level actions for the sound-effect workspace.
//

import AppKit
import Foundation
import SwiftUI

extension AudioWorkspaceView {
    @ViewBuilder
    func audioEntriesSection(localAssets: [LocalAudioAsset], clips: [AudioClipItem]) -> some View {
        if libraryStore.localAudioAssets.isEmpty && libraryStore.audioClips.isEmpty {
            AppEmptyState(
                title: "暂无音效条目",
                systemImage: "waveform",
                style: .compact,
                minHeight: 90
            )
        } else if localAssets.isEmpty && clips.isEmpty {
            AppEmptyState(
                title: "没有匹配条目",
                systemImage: "line.3.horizontal.decrease.circle",
                style: .compact,
                minHeight: 90
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(localAssets) { asset in
                    localAudioAssetRow(asset)
                }
                ForEach(clips) { clip in
                    audioClipAssetRow(clip)
                }
            }
        }
    }

    func audioRowLayout(
        containerWidth: CGFloat
    ) -> (nameWidth: CGFloat, tagWidth: CGFloat, waveformWidth: CGFloat, timeWidth: CGFloat, actionWidth: CGFloat, showsTags: Bool) {
        let showsTags = containerWidth >= 760
        let horizontalPadding = AudioRowMetrics.totalHorizontalPadding
        let rowSpacing = AudioRowMetrics.columnSpacing
        let visibleColumnCount = 5 + (showsTags ? 1 : 0)
        let spacingWidth = CGFloat(max(0, visibleColumnCount - 1)) * rowSpacing
        let timeWidth: CGFloat = containerWidth < 640 ? 82 : 96
        let actionWidth: CGFloat = AudioRowMetrics.actionButtonSize
        let fixedWidth = horizontalPadding + AudioRowMetrics.previewButtonSize + timeWidth + actionWidth + spacingWidth
        let flexibleWidth = max(0, containerWidth - fixedWidth)
        let preferredNameWidth: CGFloat = containerWidth < 760 ? 170 : 240
        let minimumNameWidth = min(containerWidth < 760 ? 110 : 130, flexibleWidth)
        let waveformWidth = audioWaveformWidth(containerWidth: containerWidth, actionWidth: actionWidth)
        let remainingWidth = max(0, flexibleWidth - waveformWidth)
        let targetNameWidth = remainingWidth * 0.36
        let nameWidth = showsTags
            ? min(remainingWidth, min(preferredNameWidth, max(minimumNameWidth, targetNameWidth)))
            : remainingWidth
        let tagWidth = showsTags ? max(0, remainingWidth - nameWidth) : 0
        return (nameWidth, tagWidth, waveformWidth, timeWidth, actionWidth, showsTags)
    }

    func audioWaveformWidth(containerWidth: CGFloat, actionWidth: CGFloat) -> CGFloat {
        let rowSpacing = AudioRowMetrics.columnSpacing
        let reservesTagColumn = containerWidth >= 760
        let commonVisibleColumnCount = 4 + (reservesTagColumn ? 1 : 0) + 1
        let commonSpacingWidth = CGFloat(max(0, commonVisibleColumnCount - 1)) * rowSpacing
        let commonHorizontalPadding = AudioRowMetrics.totalHorizontalPadding
        let commonTimeWidth: CGFloat = containerWidth < 640 ? 82 : 96
        let commonFixedWidth = commonHorizontalPadding + AudioRowMetrics.previewButtonSize + commonTimeWidth + actionWidth + commonSpacingWidth
        let commonFlexibleWidth = max(0, containerWidth - commonFixedWidth)
        let minimumNameWidth = min(containerWidth < 760 ? 110 : 130, commonFlexibleWidth)
        let minimumTagWidth = reservesTagColumn ? min(82, max(48, commonFlexibleWidth * 0.14)) : 0
        let minimumWaveformWidth: CGFloat = containerWidth < 760 ? 120 : 220
        let preferredWaveformWidth = min(
            max(containerWidth < 900 ? 200 : 320, containerWidth * (containerWidth < 900 ? 0.42 : 0.52)),
            containerWidth < 900 ? 360 : 620
        )
        let waveformBudget = max(0, commonFlexibleWidth - minimumNameWidth - minimumTagWidth)

        if waveformBudget < minimumWaveformWidth {
            return waveformBudget
        }
        return min(preferredWaveformWidth, waveformBudget)
    }

    func localAudioAssetRow(_ asset: LocalAudioAsset) -> some View {
        let samples = libraryStore.localAudioWaveformSamplesByPath[asset.filePath]
        let tags = displayedTags(for: asset)
        let previewID = AudioPreviewID.local(asset.id)
        let isPreviewing = audioPreviewController.activeID == previewID

        return GeometryReader { proxy in
            let layout = audioRowLayout(
                containerWidth: proxy.size.width
            )
            let fileURL = FileManager.default.fileExists(atPath: asset.filePath)
                ? URL(fileURLWithPath: asset.filePath)
                : nil

            HStack(alignment: .center, spacing: AudioRowMetrics.columnSpacing) {
                Button {
                    toggleLocalAudioPreview(asset)
                } label: {
                    Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isPreviewing ? .white : .secondary)
                        .frame(width: AudioRowMetrics.previewButtonSize, height: AudioRowMetrics.previewButtonSize)
                        .background(.white.opacity(isPreviewing ? 0.20 : 0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isPreviewing ? "停止音效预览" : "播放音效预览")
                .disabled(libraryStore.localAudioFileURL(for: asset) == nil)

                Text(asset.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: layout.nameWidth, alignment: .leading)

                audioTagColumn(
                    tags: tags,
                    suggestedTags: displayedAudioTagSuggestions(libraryStore.allAudioTags),
                    layout: layout,
                    onAdd: { libraryStore.addLocalAudioTag($0, to: asset) },
                    onRemove: { libraryStore.removeLocalAudioTag($0, from: asset) }
                )

                VStack(alignment: .trailing, spacing: 3) {
                    audioPlaybackDetail(totalDuration: asset.duration, isPreviewing: isPreviewing)
                        .font(Design.numericCaption(weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(width: layout.timeWidth, alignment: .trailing)

                audioWaveformColumn(
                    samples: samples,
                    width: layout.waveformWidth,
                    isActive: isPreviewing
                )

                localAudioActionColumn(asset: asset, fileURL: fileURL)
                    .frame(width: layout.actionWidth, height: AudioRowMetrics.actionColumnHeight, alignment: .trailing)
            }
            .padding(.horizontal, AudioRowMetrics.horizontalPadding)
            .padding(.vertical, AudioRowMetrics.verticalPadding)
            .frame(width: proxy.size.width, height: AudioRowMetrics.rowHeight, alignment: .leading)
            .background(.white.opacity(isPreviewing ? 0.075 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(isPreviewing ? 0.20 : 0.07), lineWidth: 0.7)
            }
            .contentShape(Rectangle())
            .itemProviderDrag(localAudioDragProvider(for: asset))
        }
        .frame(height: AudioRowMetrics.rowHeight)
    }

    func audioClipAssetRow(_ clip: AudioClipItem) -> some View {
        let tags = displayedTags(for: clip)
        let previewID = AudioPreviewID.clip(clip.id)
        let isPreviewing = audioPreviewController.activeID == previewID

        return GeometryReader { proxy in
            let layout = audioRowLayout(
                containerWidth: proxy.size.width
            )

            HStack(alignment: .center, spacing: AudioRowMetrics.columnSpacing) {
                Button {
                    toggleAudioClipPreview(clip)
                } label: {
                    Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isPreviewing ? .white : .secondary)
                        .frame(width: AudioRowMetrics.previewButtonSize, height: AudioRowMetrics.previewButtonSize)
                        .background(.white.opacity(isPreviewing ? 0.20 : 0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isPreviewing ? "停止音效预览" : "播放音效预览")
                .disabled(libraryStore.audioClipFileURL(for: clip) == nil)

                Text(audioClipDisplayName(clip))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: layout.nameWidth, alignment: .leading)

                audioTagColumn(
                    tags: tags,
                    suggestedTags: audioTagSuggestions(for: clip),
                    layout: layout,
                    onAdd: { libraryStore.addAudioTag($0, to: clip) },
                    onRemove: { libraryStore.removeAudioTag($0, from: clip) }
                )

                Button {
                    goHome(clip.videoPath, clip.inTime)
                } label: {
                    audioPlaybackDetail(totalDuration: clip.outTime - clip.inTime, isPreviewing: isPreviewing)
                        .font(Design.numericCaption(weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .buttonStyle(.plain)
                .help("跳到原视频片段")
                .frame(width: layout.timeWidth, alignment: .trailing)

                audioWaveformColumn(
                    samples: clip.waveformSamples,
                    width: layout.waveformWidth,
                    isActive: isPreviewing
                )

                audioClipActionColumn(clip: clip, provider: audioClipDragProvider(for: clip))
                    .frame(width: layout.actionWidth, height: AudioRowMetrics.actionColumnHeight, alignment: .center)
            }
            .padding(.horizontal, AudioRowMetrics.horizontalPadding)
            .padding(.vertical, AudioRowMetrics.verticalPadding)
            .frame(width: proxy.size.width, height: AudioRowMetrics.rowHeight, alignment: .leading)
            .background(.white.opacity(isPreviewing ? 0.075 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(isPreviewing ? 0.20 : 0.07), lineWidth: 0.7)
            }
            .contentShape(Rectangle())
            .itemProviderDrag(audioClipDragProvider(for: clip))
        }
        .frame(height: AudioRowMetrics.rowHeight)
    }

    func audioClipActionColumn(clip: AudioClipItem, provider: (() -> NSItemProvider)?) -> some View {
        VStack(spacing: 4) {
            audioFeaturedButton(isFeatured: hasFeaturedAudioTag(clip.tags)) {
                toggleFeaturedAudioClip(clip)
            }

            audioDragHandle(provider: provider)
        }
        .frame(width: AudioRowMetrics.actionButtonSize, height: AudioRowMetrics.actionColumnHeight, alignment: .center)
    }

    func audioDragHandle(provider: (() -> NSItemProvider)?) -> some View {
        let isAvailable = provider != nil
        return Image(systemName: "doc.on.doc")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: AudioRowMetrics.actionButtonSize, height: AudioRowMetrics.actionButtonSize)
            .background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.7)
            }
            .opacity(isAvailable ? 1 : 0.32)
            .itemProviderDrag(provider)
            .help(isAvailable ? "拖出音效文件" : "音效文件不存在")
    }

    func localAudioActionColumn(asset: LocalAudioAsset, fileURL: URL?) -> some View {
        VStack(spacing: 4) {
            Button {
                showLocalAudioInFinder(asset)
            } label: {
                audioActionIcon("folder")
            }
            .buttonStyle(.plain)
            .disabled(fileURL == nil)
            .help(fileURL == nil ? "音效文件不存在" : "在访达显示")

            audioFeaturedButton(isFeatured: hasFeaturedAudioTag(asset.tags)) {
                toggleFeaturedLocalAudioAsset(asset)
            }
        }
        .frame(width: AudioRowMetrics.actionButtonSize, height: AudioRowMetrics.actionColumnHeight, alignment: .center)
    }

    func audioFeaturedButton(isFeatured: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            audioActionIcon(
                isFeatured ? "star.fill" : "star",
                tint: isFeatured ? .yellow : .white.opacity(0.70)
            )
            .background(isFeatured ? Color.yellow.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isFeatured ? Color.yellow.opacity(0.34) : Color.clear, lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .help(isFeatured ? "取消精选" : "加入精选")
    }

    func audioActionIcon(_ systemName: String, tint: Color = .white.opacity(0.70)) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: AudioRowMetrics.actionButtonSize, height: AudioRowMetrics.actionButtonSize)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    func audioWaveformColumn(
        samples: [Double]?,
        width: CGFloat,
        isActive: Bool
    ) -> some View {
        if isActive {
            ActiveAudioWaveformStrip(progressStore: audioPreviewController.progressStore, samples: samples)
                .frame(width: width, height: AudioRowMetrics.waveformHeight)
        } else {
            AudioClipWaveformStrip(samples: samples, isActive: false, progress: 0)
                .equatable()
                .frame(width: width, height: AudioRowMetrics.waveformHeight)
        }
    }

    @ViewBuilder
    func audioPlaybackDetail(totalDuration: Double, isPreviewing: Bool) -> some View {
        if isPreviewing {
            ActiveAudioPlaybackTime(progressStore: audioPreviewController.progressStore, fallbackDuration: totalDuration)
        } else {
            Text(audioDurationClockText(totalDuration))
        }
    }

    @ViewBuilder
    func audioTagColumn(
        tags: [String],
        suggestedTags: [String] = [],
        layout: (nameWidth: CGFloat, tagWidth: CGFloat, waveformWidth: CGFloat, timeWidth: CGFloat, actionWidth: CGFloat, showsTags: Bool),
        onAdd: @escaping (String) -> Void,
        onRemove: @escaping (String) -> Void
    ) -> some View {
        if layout.showsTags {
            EditableAudioTagStrip(
                title: "声音标签",
                tags: tags,
                suggestedTags: suggestedTags,
                onAdd: onAdd,
                onRemove: onRemove
            )
            .frame(width: layout.tagWidth, alignment: .leading)
        }
    }

    func toggleAudioClipPreview(_ clip: AudioClipItem) {
        guard let fileURL = libraryStore.audioClipFileURL(for: clip) else { return }
        toggleAudioPreview(
            fileURL: fileURL,
            id: .clip(clip.id),
            notificationID: clip.id,
            totalDuration: clip.outTime - clip.inTime
        )
    }

    func toggleLocalAudioPreview(_ asset: LocalAudioAsset) {
        guard let fileURL = libraryStore.localAudioFileURL(for: asset) else { return }
        toggleAudioPreview(
            fileURL: fileURL,
            id: .local(asset.id),
            notificationID: UUID(),
            totalDuration: asset.duration
        )
    }

    func toggleAudioPreview(fileURL: URL, id: AudioPreviewID, notificationID: UUID, totalDuration: Double) {
        audioPreviewController.toggle(
            fileURL: fileURL,
            id: id,
            notificationID: notificationID,
            totalDuration: totalDuration
        )
    }

    func toggleFeaturedLocalAudioAsset(_ asset: LocalAudioAsset) {
        if hasFeaturedAudioTag(asset.tags) {
            libraryStore.removeLocalAudioTag(Self.featuredAudioTag, from: asset)
        } else {
            libraryStore.addLocalAudioTag(Self.featuredAudioTag, to: asset)
        }
    }

    func toggleFeaturedAudioClip(_ clip: AudioClipItem) {
        if hasFeaturedAudioTag(clip.tags) {
            libraryStore.removeAudioTag(Self.featuredAudioTag, from: clip)
        } else {
            libraryStore.addAudioTag(Self.featuredAudioTag, to: clip)
        }
    }

    func showLocalAudioInFinder(_ asset: LocalAudioAsset) {
        guard let fileURL = libraryStore.localAudioFileURL(for: asset) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func audioClipDragProvider(for clip: AudioClipItem) -> (() -> NSItemProvider)? {
        guard libraryStore.audioClipFileURL(for: clip) != nil else { return nil }
        return {
            libraryStore.audioClipFileProvider(for: clip) ?? NSItemProvider()
        }
    }

    func localAudioDragProvider(for asset: LocalAudioAsset) -> (() -> NSItemProvider)? {
        guard let fileURL = libraryStore.localAudioFileURL(for: asset) else { return nil }
        return { fileDragProvider(for: fileURL, suggestedName: fileURL.lastPathComponent) }
    }

    func audioDurationClockText(_ duration: Double) -> String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        return clockText(duration)
    }
}
