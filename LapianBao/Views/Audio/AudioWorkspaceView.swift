//
//  AudioWorkspaceView.swift
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

struct AudioWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let goHome: (String, Double) -> Void
    @State private var selectedAudioFilters: Set<AudioFilterOption> = []
    @State private var searchText = ""
    @State private var audioPreviewPlayer: AVPlayer?
    @State private var audioPreviewTimeObserver: Any?
    @State private var audioPreviewEndObserver: NSObjectProtocol?
    @State private var activeAudioPreviewID: AudioPreviewID?
    @State private var activeAudioPreviewProgress: Double = 0

    private enum AudioPreviewID: Equatable {
        case local(String)
        case clip(UUID)
    }

    var body: some View {
        let filteredLocalAssets = filteredLocalAudioAssets
        let filteredClips = filteredAudioClips

        VStack(alignment: .leading, spacing: 12) {
            audioHeader()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    audioEntriesSection(localAssets: filteredLocalAssets, clips: filteredClips)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())
        }
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)
        .background(Design.sidebarBg)
        .onDisappear {
            stopAudioPreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lapianBaoMusicPreviewStarted)) { notification in
            guard notification.userInfo?["source"] as? String != "audioWorkspace" else { return }
            stopAudioPreview()
        }
    }

    private func audioHeader() -> some View {
        HStack(spacing: Design.libraryToolbarButtonGap) {
            LibraryToolbarSearchField(placeholder: "搜索名字、标签", text: $searchText)

            audioTagFilterMenu

            if !selectedAudioFilters.isEmpty {
                Button {
                    selectedAudioFilters.removeAll()
                } label: {
                    audioToolbarIcon(systemName: "xmark.circle", size: 12)
                }
                .buttonStyle(.plain)
                .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
                .contentShape(Rectangle())
                .help("清除筛选")
            }
        }
        .frame(minHeight: Design.libraryToolbarHeight)
        .padding(.horizontal, 14)
    }

    private var audioTagFilterMenu: some View {
        Menu {
            let tagValues = audioFilterValues(for: .tag)

            if tagValues.isEmpty {
                Button("暂无标签") {}
                    .disabled(true)
            } else {
                Button {
                    selectedAudioFilters = selectedAudioFilters.filter { $0.kind != .tag }
                } label: {
                    HStack {
                        if selectedAudioTagFilterCount == 0 { Image(systemName: "checkmark") }
                        Text("全部标签")
                    }
                }

                Divider()

                Section("标签") {
                    ForEach(tagValues, id: \.self) { value in
                        let option = AudioFilterOption(kind: .tag, value: value)
                        Button {
                            toggleAudioFilter(option)
                        } label: {
                            HStack {
                                Image(systemName: selectedAudioFilters.contains(option) ? "checkmark.square.fill" : "square")
                                VideoTagColorDot(tag: value)
                                Text(value)
                            }
                        }
                    }
                }
            }
        } label: {
            audioToolbarIcon(systemName: "tag", size: 12)
                .overlay(alignment: .topTrailing) {
                    if selectedAudioTagFilterCount > 0 {
                        Text("\(selectedAudioTagFilterCount)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .help("标签筛选")
    }

    @ViewBuilder
    private func audioFilterSection(kind: AudioFilterKind) -> some View {
        let values = audioFilterValues(for: kind)
        if !values.isEmpty {
            Divider()
            Section(kind.rawValue) {
                ForEach(values, id: \.self) { value in
                    let option = AudioFilterOption(kind: kind, value: value)
                    Button {
                        toggleAudioFilter(option)
                    } label: {
                        HStack {
                            Image(systemName: selectedAudioFilters.contains(option) ? "checkmark.square.fill" : "square")
                            if kind == .tag {
                                VideoTagColorDot(tag: value)
                            }
                            Text(value)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func audioEntriesSection(localAssets: [LocalAudioAsset], clips: [AudioClipItem]) -> some View {
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

    private func audioToolbarIcon(systemName: String, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Design.libraryToolbarIconTint)
            .frame(
                width: Design.libraryToolbarButtonSlotWidth,
                height: Design.libraryToolbarButtonSlotHeight,
                alignment: .center
            )
    }

    private func audioRowLayout(
        containerWidth: CGFloat,
        includesTagEditor: Bool,
        hasTags: Bool,
        prefersTimeRange: Bool
    ) -> (nameWidth: CGFloat, tagWidth: CGFloat, waveformWidth: CGFloat, timeWidth: CGFloat, showsTags: Bool) {
        let showsTags = hasTags && containerWidth >= (includesTagEditor ? 760 : 680)
        let horizontalPadding: CGFloat = includesTagEditor ? 18 : 20
        let rowSpacing: CGFloat = 14
        let visibleColumnCount = 4 + (showsTags ? 1 : 0) + (includesTagEditor ? 1 : 0)
        let spacingWidth = CGFloat(max(0, visibleColumnCount - 1)) * rowSpacing
        let timeWidth: CGFloat = prefersTimeRange
            ? (containerWidth < 760 ? 92 : 112)
            : (containerWidth < 640 ? 62 : 72)
        let fixedWidth = horizontalPadding + 28 + timeWidth + (includesTagEditor ? 24 : 0) + spacingWidth
        let flexibleWidth = max(0, containerWidth - fixedWidth)
        let tagWidth = showsTags ? min(170, max(84, flexibleWidth * 0.24)) : 0
        let preferredNameWidth: CGFloat = containerWidth < 760 ? 170 : 240
        let minimumNameWidth = min(100, flexibleWidth * 0.48)
        let targetNameWidth = flexibleWidth * (showsTags ? 0.34 : 0.42)
        let nameWidth = min(preferredNameWidth, max(minimumNameWidth, targetNameWidth))
        let waveformWidth = max(0, flexibleWidth - nameWidth - tagWidth)
        return (nameWidth, tagWidth, waveformWidth, timeWidth, showsTags)
    }

    private func localAudioAssetRow(_ asset: LocalAudioAsset) -> some View {
        let samples = libraryStore.localAudioWaveformSamplesByPath[asset.filePath]
        let tags = visibleTags(for: asset)
        let previewID = AudioPreviewID.local(asset.id)
        let isPreviewing = activeAudioPreviewID == previewID

        return GeometryReader { proxy in
            let layout = audioRowLayout(
                containerWidth: proxy.size.width,
                includesTagEditor: false,
                hasTags: !tags.isEmpty,
                prefersTimeRange: false
            )

            HStack(alignment: .center, spacing: 14) {
                Button {
                    toggleLocalAudioPreview(asset)
                } label: {
                    Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isPreviewing ? .white : .orange)
                        .frame(width: 28, height: 28)
                        .background(.orange.opacity(isPreviewing ? 0.82 : 0.13))
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

                if layout.showsTags {
                    MusicTagStrip(tags: tags)
                        .frame(width: layout.tagWidth, alignment: .leading)
                }

                VStack(alignment: .trailing, spacing: 3) {
                    Text(asset.duration > 0 ? formatDuration(asset.duration) : asset.fileExtension.uppercased())
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(fileSizeText(asset.fileSize))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(width: layout.timeWidth, alignment: .trailing)

                audioWaveformColumn(
                    samples: samples,
                    width: layout.waveformWidth,
                    isActive: isPreviewing,
                    progress: isPreviewing ? activeAudioPreviewProgress : 0
                )
            }
            .padding(10)
            .frame(width: proxy.size.width, height: 72, alignment: .leading)
            .background(.white.opacity(isPreviewing ? 0.075 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(isPreviewing ? 0.20 : 0.07), lineWidth: 0.7)
            }
        }
        .frame(height: 72)
        .itemProviderDrag(localAudioDragProvider(for: asset))
        .help("可拖出音效文件")
    }

    private func audioClipAssetRow(_ clip: AudioClipItem) -> some View {
        let tags = visibleTags(for: clip)
        let previewID = AudioPreviewID.clip(clip.id)
        let isPreviewing = activeAudioPreviewID == previewID

        return GeometryReader { proxy in
            let layout = audioRowLayout(
                containerWidth: proxy.size.width,
                includesTagEditor: true,
                hasTags: !tags.isEmpty,
                prefersTimeRange: true
            )

            HStack(alignment: .center, spacing: 14) {
                Button {
                    toggleAudioClipPreview(clip)
                } label: {
                    Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isPreviewing ? .white : .orange)
                        .frame(width: 28, height: 28)
                        .background(.orange.opacity(isPreviewing ? 0.82 : 0.13))
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

                if layout.showsTags {
                    MusicTagStrip(tags: tags)
                        .frame(width: layout.tagWidth, alignment: .leading)
                }

                Button {
                    goHome(clip.videoPath, clip.inTime)
                } label: {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(clockText(clip.inTime)) - \(clockText(clip.outTime))")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(formatDuration(clip.outTime - clip.inTime))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .buttonStyle(.plain)
                .help("跳到原视频时间段")
                .frame(width: layout.timeWidth, alignment: .trailing)

                audioWaveformColumn(
                    samples: clip.waveformSamples,
                    width: layout.waveformWidth,
                    isActive: isPreviewing,
                    progress: isPreviewing ? activeAudioPreviewProgress : 0
                )

                InlineTagEditorButton(
                    title: "声音标签",
                    tags: clip.tags,
                    suggestedTags: audioTagSuggestions(for: clip),
                    buttonSize: 24,
                    onAdd: { libraryStore.addAudioTag($0, to: clip) },
                    onRemove: { libraryStore.removeAudioTag($0, from: clip) }
                )
            }
            .padding(9)
            .frame(width: proxy.size.width, height: 72, alignment: .leading)
            .background(.white.opacity(isPreviewing ? 0.075 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(isPreviewing ? 0.20 : 0.07), lineWidth: 0.7)
            }
        }
        .frame(height: 72)
        .itemProviderDrag(audioClipDragProvider(for: clip))
        .help("可拖出音效文件")
    }

    @ViewBuilder
    private func audioWaveformColumn(
        samples: [Double]?,
        width: CGFloat,
        isActive: Bool,
        progress: Double
    ) -> some View {
        AudioClipWaveformStrip(samples: samples, isActive: isActive, progress: progress)
            .equatable()
            .frame(width: width, height: 42)
    }

    private var filteredLocalAudioAssets: [LocalAudioAsset] {
        let query = normalizedSearch(searchText)
        guard !query.isEmpty || !selectedAudioFilters.isEmpty else {
            return libraryStore.localAudioAssets
        }
        return libraryStore.localAudioAssets.filter { asset in
            let tags = visibleTags(for: asset)
            let matchesSearch = query.isEmpty
                || normalizedSearch(asset.title).contains(query)
                || tags.contains { normalizedSearch($0).contains(query) }
            guard matchesSearch else { return false }
            return matchesSelectedAudioFilters(for: asset)
        }
    }

    private var filteredAudioClips: [AudioClipItem] {
        let query = normalizedSearch(searchText)
        guard !query.isEmpty || !selectedAudioFilters.isEmpty else {
            return libraryStore.audioClips.sorted { $0.createdAt > $1.createdAt }
        }
        return libraryStore.audioClips
            .filter { clip in
                let name = audioClipDisplayName(clip)
                let tags = visibleTags(for: clip)
                let matchesSearch = query.isEmpty
                    || normalizedSearch(name).contains(query)
                    || normalizedSearch(clip.videoName).contains(query)
                    || tags.contains { normalizedSearch($0).contains(query) }
                guard matchesSearch else { return false }
                return matchesSelectedAudioFilters(for: clip)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var audioFilterTags: [String] {
        let localTags = libraryStore.localAudioAssets.flatMap { visibleTags(for: $0) }
        let clipTags = libraryStore.audioClips.flatMap { visibleTags(for: $0) }
        return cleanedAudioTags(localTags + clipTags)
    }

    private var selectedAudioTagFilterCount: Int {
        selectedAudioFilters.filter { $0.kind == .tag }.count
    }

    private func audioFilterValues(for kind: AudioFilterKind) -> [String] {
        let values: [String]
        switch kind {
        case .name:
            values = libraryStore.localAudioAssets.map(\.title) + libraryStore.audioClips.map(audioClipDisplayName)
        case .tag:
            values = audioFilterTags
        }

        return cleanedAudioTags(values)
    }

    private func toggleAudioFilter(_ option: AudioFilterOption) {
        if selectedAudioFilters.contains(option) {
            selectedAudioFilters.remove(option)
        } else {
            selectedAudioFilters.insert(option)
        }
    }

    private func matchesSelectedAudioFilters(for asset: LocalAudioAsset) -> Bool {
        guard !selectedAudioFilters.isEmpty else { return true }
        let options = Set(
            [AudioFilterOption(kind: .name, value: asset.title.trimmingCharacters(in: .whitespacesAndNewlines))] +
            visibleTags(for: asset).map { AudioFilterOption(kind: .tag, value: $0) }
        )
        return selectedAudioFilters.allSatisfy { options.contains($0) }
    }

    private func matchesSelectedAudioFilters(for clip: AudioClipItem) -> Bool {
        guard !selectedAudioFilters.isEmpty else { return true }
        let options = Set(
            [AudioFilterOption(kind: .name, value: audioClipDisplayName(clip))] +
            visibleTags(for: clip).map { AudioFilterOption(kind: .tag, value: $0) }
        )
        return selectedAudioFilters.allSatisfy { options.contains($0) }
    }

    private func audioClipDisplayName(_ clip: AudioClipItem) -> String {
        let note = clip.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            return note
        }
        return clip.videoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名音效" : clip.videoName
    }

    private func visibleTags(for asset: LocalAudioAsset) -> [String] {
        cleanedAudioTags(asset.tags)
            .filter { !isAudioMetadataValue($0, names: [asset.title]) }
    }

    private func visibleTags(for clip: AudioClipItem) -> [String] {
        cleanedAudioTags(combinedTags(for: clip))
            .filter { !isAudioMetadataValue($0, names: [audioClipDisplayName(clip), clip.videoName]) }
    }

    private func isAudioMetadataValue(_ value: String, names: [String]) -> Bool {
        let valueKey = normalizedSearch(value)
        guard !valueKey.isEmpty else { return true }
        return names
            .map(normalizedSearch)
            .filter { !$0.isEmpty }
            .contains(valueKey)
    }

    private func cleanedAudioTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert(normalizedSearch($0)).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func sourceTags(for videoPath: String) -> [String] {
        libraryStore.tagsByVideoPath[videoPath, default: []]
    }

    private func combinedTags(for clip: AudioClipItem) -> [String] {
        Array(Set(clip.tags + sourceTags(for: clip.videoPath))).sorted()
    }

    private func audioTagSuggestions(for clip: AudioClipItem) -> [String] {
        Array(Set(libraryStore.allAudioTags + sourceTags(for: clip.videoPath))).sorted()
    }

    private func toggleAudioClipPreview(_ clip: AudioClipItem) {
        guard let fileURL = libraryStore.audioClipFileURL(for: clip) else { return }
        toggleAudioPreview(fileURL: fileURL, id: .clip(clip.id), notificationID: clip.id)
    }

    private func toggleLocalAudioPreview(_ asset: LocalAudioAsset) {
        guard let fileURL = libraryStore.localAudioFileURL(for: asset) else { return }
        toggleAudioPreview(fileURL: fileURL, id: .local(asset.id), notificationID: UUID())
    }

    private func toggleAudioPreview(fileURL: URL, id: AudioPreviewID, notificationID: UUID) {
        if activeAudioPreviewID == id {
            stopAudioPreview()
            return
        }

        startAudioPreview(fileURL: fileURL, id: id, notificationID: notificationID)
    }

    private func startAudioPreview(fileURL: URL, id: AudioPreviewID, notificationID: UUID) {
        stopAudioPreview()
        NotificationCenter.default.post(name: .lapianBaoPausePreviewRequest, object: nil)
        NotificationCenter.default.post(
            name: .lapianBaoMusicPreviewStarted,
            object: nil,
            userInfo: ["id": notificationID, "source": "audioWorkspace"]
        )

        let item = AVPlayerItem(url: fileURL)
        let player = AVPlayer(playerItem: item)
        audioPreviewPlayer = player
        activeAudioPreviewID = id
        activeAudioPreviewProgress = 0

        audioPreviewTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { time in
            let elapsed = time.seconds
            guard elapsed.isFinite else { return }
            let duration = item.duration.seconds
            if duration.isFinite, duration > 0 {
                activeAudioPreviewProgress = min(1, max(0, elapsed / duration))
            }
        }

        audioPreviewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            stopAudioPreview()
        }

        player.play()
    }

    private func stopAudioPreview() {
        if let audioPreviewTimeObserver, let audioPreviewPlayer {
            audioPreviewPlayer.removeTimeObserver(audioPreviewTimeObserver)
        }
        audioPreviewTimeObserver = nil

        audioPreviewPlayer?.pause()
        audioPreviewPlayer = nil
        activeAudioPreviewID = nil
        activeAudioPreviewProgress = 0

        if let audioPreviewEndObserver {
            NotificationCenter.default.removeObserver(audioPreviewEndObserver)
            self.audioPreviewEndObserver = nil
        }
    }

    private func audioClipDragProvider(for clip: AudioClipItem) -> (() -> NSItemProvider)? {
        guard libraryStore.audioClipFileURL(for: clip) != nil else { return nil }
        return {
            libraryStore.audioClipFileProvider(for: clip) ?? NSItemProvider()
        }
    }

    private func localAudioDragProvider(for asset: LocalAudioAsset) -> (() -> NSItemProvider)? {
        guard let fileURL = libraryStore.localAudioFileURL(for: asset) else { return nil }
        return { fileDragProvider(for: fileURL, suggestedName: fileURL.lastPathComponent) }
    }
}
