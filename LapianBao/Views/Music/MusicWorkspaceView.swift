//
//  MusicWorkspaceView.swift
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

struct MusicWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let goHome: (String, Double) -> Void

    @State private var searchText = ""
    @State private var searchResults: [AppleMusicSearchResult] = []
    @State private var isSearching = false
    @State private var searchMessage: String?
    @State private var selectedMusicFilters: Set<MusicFilterOption> = []

    var body: some View {
        let recognizedAssets = musicAssets
        let filteredRecognizedAssets = filteredRecognizedMusicAssets(from: recognizedAssets)
        let filteredSearchItems = filteredSearchResults
        let filterValues = musicFilterValues(from: recognizedAssets)

        VStack(alignment: .leading, spacing: 12) {
            musicHeader(filterValues: filterValues)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    searchSection(results: filteredSearchItems)
                    recognizedMusicSection(allAssets: recognizedAssets, filteredAssets: filteredRecognizedAssets)
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
        .onAppear {
            libraryStore.enrichMusicTagsIfNeeded()
            libraryStore.prepareExternalServiceWork()
        }
        .task(id: searchText) {
            await runAppleMusicSearch()
        }
    }

    private func musicHeader(filterValues: [MusicFilterKind: [String]]) -> some View {
        HStack(spacing: Design.libraryToolbarButtonGap) {
            LibraryToolbarSearchField(placeholder: "搜索标题、作者、标签", text: $searchText)

            musicTagFilterMenu(filterValues: filterValues)
            musicMetadataFilterMenu(filterValues: filterValues)

            if !selectedMusicFilters.isEmpty {
                Button {
                    selectedMusicFilters.removeAll()
                } label: {
                    toolbarIcon(systemName: "xmark.circle", size: 12)
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

    private func musicTagFilterMenu(filterValues: [MusicFilterKind: [String]]) -> some View {
        Menu {
            let tagValues = filterValues[.tag, default: []]

            if tagValues.isEmpty {
                Button("暂无标签") {}
                    .disabled(true)
            } else {
                Button {
                    selectedMusicFilters = selectedMusicFilters.filter { $0.kind != .tag }
                } label: {
                    HStack {
                        if selectedMusicTagFilterCount == 0 { Image(systemName: "checkmark") }
                        Text("全部标签")
                    }
                }

                Divider()

                Section("标签") {
                    ForEach(tagValues, id: \.self) { value in
                        let option = MusicFilterOption(kind: .tag, value: value)
                        Button {
                            toggleMusicFilter(option)
                        } label: {
                            HStack {
                                Image(systemName: selectedMusicFilters.contains(option) ? "checkmark.square.fill" : "square")
                                VideoTagColorDot(tag: value)
                                Text(value)
                            }
                        }
                    }
                }
            }
        } label: {
            toolbarIcon(systemName: "tag", size: 12)
                .overlay(alignment: .topTrailing) {
                    if selectedMusicTagFilterCount > 0 {
                        Text("\(selectedMusicTagFilterCount)")
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

    private func musicMetadataFilterMenu(filterValues: [MusicFilterKind: [String]]) -> some View {
        Menu {
            Button {
                selectedMusicFilters = selectedMusicFilters.filter { $0.kind == .tag }
            } label: {
                HStack {
                    if selectedMusicMetadataFilterCount == 0 { Image(systemName: "checkmark") }
                    Text("全部标题和作者")
                }
            }

            musicFilterSection(kind: .title, filterValues: filterValues)
            musicFilterSection(kind: .artist, filterValues: filterValues)
        } label: {
            toolbarIcon(systemName: "line.3.horizontal.decrease.circle", size: 12)
                .overlay(alignment: .topTrailing) {
                    if selectedMusicMetadataFilterCount > 0 {
                        Text("\(selectedMusicMetadataFilterCount)")
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
        .help("标题和作者筛选")
    }

    @ViewBuilder
    private func musicFilterSection(
        kind: MusicFilterKind,
        filterValues: [MusicFilterKind: [String]]
    ) -> some View {
        let values = filterValues[kind, default: []]
        if !values.isEmpty {
            Divider()
            Section(kind.rawValue) {
                ForEach(values, id: \.self) { value in
                    let option = MusicFilterOption(kind: kind, value: value)
                    Button {
                        toggleMusicFilter(option)
                    } label: {
                        HStack {
                            Image(systemName: selectedMusicFilters.contains(option) ? "checkmark.square.fill" : "square")
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
    private func searchSection(results: [AppleMusicSearchResult]) -> some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty || isSearching || searchMessage != nil {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title: "AM 搜索", count: results.count, icon: "magnifyingglass")

                if isSearching {
                    GenerationProgressRow(
                        message: "正在搜索 AM",
                        progress: nil,
                        tint: .white,
                        systemImage: "magnifyingglass",
                        compact: true,
                        showPercent: false
                    )
                } else if let searchMessage {
                    AppEmptyState(
                        title: searchMessage,
                        systemImage: "magnifyingglass",
                        style: .compact,
                        minHeight: 86
                    )
                } else if results.isEmpty {
                    AppEmptyState(
                        title: "没有匹配条目",
                        systemImage: "line.3.horizontal.decrease.circle",
                        style: .compact,
                        minHeight: 86
                    )
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { item in
                            appleMusicResultRow(item)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recognizedMusicSection(
        allAssets: [RecognizedMusicAsset],
        filteredAssets: [RecognizedMusicAsset]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if allAssets.isEmpty {
                AppEmptyState(
                    title: folderMusicRecognitionStatusText ?? "暂无 AM 条目",
                    systemImage: "sparkles",
                    style: .compact,
                    minHeight: 90
                )
            } else if filteredAssets.isEmpty {
                AppEmptyState(
                    title: "没有匹配条目",
                    systemImage: "line.3.horizontal.decrease.circle",
                    style: .compact,
                    minHeight: 90
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredAssets) { asset in
                        recognizedMusicAssetRow(asset)
                    }
                }
            }
        }
    }

    private func musicRowLayout(
        containerWidth: CGFloat,
        hasTags: Bool,
        hasDownloadStatus: Bool,
        includesSafari: Bool
    ) -> (
        infoWidth: CGFloat,
        tagWidth: CGFloat,
        statusWidth: CGFloat,
        timeWidth: CGFloat,
        showsTags: Bool,
        showsDownloadStatus: Bool
    ) {
        let showsDownloadStatus = hasDownloadStatus && containerWidth >= 760
        let showsTags = hasTags && containerWidth >= (showsDownloadStatus ? 900 : 760)
        let timeWidth: CGFloat = 56
        let buttonsWidth: CGFloat = 160
        let safariWidth: CGFloat = includesSafari ? 24 : 0
        let visibleColumnCount = 4
            + (showsTags ? 1 : 0)
            + (showsDownloadStatus ? 1 : 0)
            + (includesSafari ? 1 : 0)
        let spacingWidth = CGFloat(max(0, visibleColumnCount - 1)) * 14
        let fixedWidth = 18 + 56 + timeWidth + buttonsWidth + safariWidth + spacingWidth
        let flexibleWidth = max(0, containerWidth - fixedWidth)
        let tagWidth = showsTags ? min(160, max(96, flexibleWidth * 0.22)) : 0
        let statusWidth = showsDownloadStatus ? min(300, max(132, flexibleWidth * 0.34)) : 0
        let remainingWidth = max(0, flexibleWidth - tagWidth - statusWidth)
        let infoWidth = min(containerWidth < 820 ? 210 : 270, max(120, remainingWidth))
        return (infoWidth, tagWidth, statusWidth, timeWidth, showsTags, showsDownloadStatus)
    }

    private func appleMusicResultRow(_ item: AppleMusicSearchResult) -> some View {
        let song = item.asMusicRecognitionItem()
        let downloadJobs = musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs)
        let visibleTags = visibleTags(for: song)

        return GeometryReader { proxy in
            let layout = musicRowLayout(
                containerWidth: proxy.size.width,
                hasTags: !visibleTags.isEmpty,
                hasDownloadStatus: !downloadJobs.isEmpty,
                includesSafari: URL(string: item.appleMusicURL) != nil
            )

            HStack(alignment: .center, spacing: 14) {
                musicArtwork(urlString: item.artworkURL, title: item.title, artist: item.artist)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.isEmpty ? "未知曲目" : item.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(item.artist.isEmpty ? "未知作者" : item.artist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: layout.infoWidth, alignment: .leading)

                if layout.showsTags {
                    MusicTagStrip(tags: visibleTags)
                        .frame(width: layout.tagWidth, alignment: .leading)
                }

                Text(item.duration > 0 ? formatDuration(item.duration) : "--:--")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(width: layout.timeWidth, alignment: .trailing)

                if layout.showsDownloadStatus {
                    MusicDownloadInlineStatusStack(downloadJobs: downloadJobs)
                        .frame(width: layout.statusWidth, alignment: .leading)
                }

                musicDownloadButtons(song: song)

                if let url = URL(string: item.appleMusicURL) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "safari")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("打开 AM 页面")
                }
            }
            .padding(9)
            .frame(width: proxy.size.width, height: 86, alignment: .leading)
            .background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
        }
        .frame(height: 86)
    }

    private func recognizedMusicAssetRow(_ asset: RecognizedMusicAsset) -> some View {
        let downloadJobs = musicDownloadJobs(for: asset.song, in: libraryStore.musicDownloadJobs)
        let visibleTags = visibleTags(for: asset.song)

        return GeometryReader { proxy in
            let layout = musicRowLayout(
                containerWidth: proxy.size.width,
                hasTags: !visibleTags.isEmpty,
                hasDownloadStatus: !downloadJobs.isEmpty,
                includesSafari: false
            )

            HStack(alignment: .center, spacing: 14) {
                Button {
                    goHome(asset.videoPath, asset.song.detectedAt)
                } label: {
                    HStack(spacing: 10) {
                        musicArtwork(
                            urlString: asset.song.artworkURL,
                            title: asset.song.title,
                            artist: asset.song.artist
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(asset.song.title.isEmpty ? "未知曲目" : asset.song.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(asset.song.artist.isEmpty ? "未知作者" : asset.song.artist)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(asset.videoName)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(width: layout.infoWidth, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("跳到视频中此段落")

                if layout.showsTags {
                    MusicTagStrip(tags: visibleTags)
                        .frame(width: layout.tagWidth, alignment: .leading)
                }

                Button {
                    goHome(asset.videoPath, asset.song.detectedAt)
                } label: {
                    Text(clockText(asset.song.detectedAt))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .frame(width: layout.timeWidth, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .help("跳到原视频时间点")

                if layout.showsDownloadStatus {
                    MusicDownloadInlineStatusStack(downloadJobs: downloadJobs)
                        .frame(width: layout.statusWidth, alignment: .leading)
                }

                musicDownloadButtons(song: asset.song)
            }
            .padding(9)
            .frame(width: proxy.size.width, height: 86, alignment: .leading)
            .background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
        }
        .frame(height: 86)
    }

    private func musicDownloadButtons(song: MusicRecognitionItem) -> some View {
        let jobs = musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs)
        let originalJob = jobs.first { $0.type == .original }
        let instrumentalJob = jobs.first { $0.type == .instrumental }

        return HStack(spacing: 6) {
            musicDownloadButton(song: song, type: .original, job: originalJob)
            musicDownloadButton(song: song, type: .instrumental, job: instrumentalJob)
        }
        .frame(width: 160, alignment: .trailing)
    }

    private func musicDownloadButton(
        song: MusicRecognitionItem,
        type: MusicDownloadJob.DownloadType,
        job: MusicDownloadJob?
    ) -> some View {
        let isDownloaded = completedMusicFileURL(for: job) != nil
        let isActive = job.map { isActiveDownloadStatus($0.status) } ?? false

        return Button {
            if let url = completedMusicFileURL(for: job) {
                NSWorkspace.shared.open(url)
            } else {
                libraryStore.downloadMusic(song: song, type: type)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: musicDownloadIcon(type: type, job: job))
                    .font(.system(size: 11, weight: .semibold))
                Text(musicDownloadTitle(type: type, job: job))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundStyle(isDownloaded ? .white.opacity(0.94) : .white.opacity(isActive ? 0.86 : 0.56))
            .frame(width: 76, height: 28)
            .background(.white.opacity(isDownloaded ? 0.15 : (isActive ? 0.10 : 0.045)))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.white.opacity(isDownloaded ? 0.18 : 0.07), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .disabled(isActive)
        .help(musicDownloadHelp(type: type, job: job))
        .contextMenu {
            Button {
                libraryStore.downloadMusic(song: song, type: type)
            } label: {
                Label("重新下载\(type.label)", systemImage: "arrow.clockwise")
            }
        }
    }

    private func sectionHeader(title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
            Text(title)
                .font(.headline.weight(.semibold))
            Text("\(count)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
            Spacer()
        }
    }

    private func toolbarIcon(systemName: String, size: CGFloat) -> some View {
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

    private func musicArtwork(urlString: String, title: String = "", artist: String = "") -> some View {
        MusicArtworkView(
            urlString: urlString,
            title: title,
            artist: artist
        )
            .frame(width: 56, height: 56)
    }

    private var musicAssets: [RecognizedMusicAsset] {
        let videoNameByPath = Dictionary(
            uniqueKeysWithValues: libraryStore.videos.map { ($0.url.path, $0.name) }
        )
        let localNameByPath = Dictionary(
            uniqueKeysWithValues: libraryStore.localMusicAssets.map { ($0.filePath, $0.title) }
        )

        return libraryStore.musicsByVideoPath.flatMap { path, songs in
            guard videoNameByPath[path] != nil || localNameByPath[path] != nil else {
                return [RecognizedMusicAsset]()
            }
            let videoName = videoNameByPath[path]
                ?? localNameByPath[path]
                ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return songs
                .filter(isAMReadySong)
                .map { song in
                    RecognizedMusicAsset(videoPath: path, videoName: videoName, song: song)
                }
        }
        .sorted { lhs, rhs in
            if lhs.videoName == rhs.videoName {
                return lhs.song.detectedAt < rhs.song.detectedAt
            }
            return lhs.videoName.localizedStandardCompare(rhs.videoName) == .orderedAscending
        }
    }

    private var folderMusicRecognitionStatusText: String? {
        let assets = libraryStore.localMusicAssets
        guard !assets.isEmpty else { return nil }

        let unresolved = assets.filter { asset in
            let songs = libraryStore.musicsByVideoPath[asset.filePath, default: []]
            return songs.allSatisfy { !isAMReadySong($0) }
        }
        guard !unresolved.isEmpty else { return nil }

        if unresolved.contains(where: { asset in
            if case .running = libraryStore.musicDetectionStatusByVideoPath[asset.filePath] {
                return true
            }
            return false
        }) {
            return "正在识别文件夹内音乐"
        }

        let failedCount = unresolved.filter { asset in
            if case .failed = libraryStore.musicDetectionStatusByVideoPath[asset.filePath] {
                return true
            }
            return false
        }.count

        if failedCount == unresolved.count {
            return "文件夹内音乐暂未识别成功"
        }
        return "等待识别文件夹内音乐"
    }

    private var filteredSearchResults: [AppleMusicSearchResult] {
        searchResults.filter { item in
            let song = item.asMusicRecognitionItem()
            guard isAMReadySong(song) else { return false }
            return matchesSelectedMusicFilters(for: song)
        }
    }

    private func filteredRecognizedMusicAssets(from assets: [RecognizedMusicAsset]) -> [RecognizedMusicAsset] {
        let query = normalizedSearch(searchText)
        guard !query.isEmpty || !selectedMusicFilters.isEmpty else {
            return assets
        }
        return assets.filter { asset in
            let matchesSearch = query.isEmpty
                || normalizedSearch(asset.song.title).contains(query)
                || normalizedSearch(asset.song.artist).contains(query)
                || normalizedSearch(asset.videoName).contains(query)
                || visibleTags(for: asset.song).contains { normalizedSearch($0).contains(query) }
            guard matchesSearch else { return false }
            return matchesSelectedMusicFilters(for: asset)
        }
    }

    private func musicFilterValues(from assets: [RecognizedMusicAsset]) -> [MusicFilterKind: [String]] {
        let titleValues = assets.map(\.song.title)
        let artistValues = assets.map(\.song.artist)
        let tagValues = assets.flatMap { visibleTags(for: $0.song) }

        return [
            .title: cleanedMusicFilterValues(titleValues),
            .artist: cleanedMusicFilterValues(artistValues),
            .tag: cleanedMusicFilterValues(tagValues)
        ]
    }

    private func cleanedMusicFilterValues(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var selectedMusicTagFilterCount: Int {
        selectedMusicFilters.filter { $0.kind == .tag }.count
    }

    private var selectedMusicMetadataFilterCount: Int {
        selectedMusicFilters.filter { $0.kind != .tag }.count
    }

    private func toggleMusicFilter(_ option: MusicFilterOption) {
        if selectedMusicFilters.contains(option) {
            selectedMusicFilters.remove(option)
        } else {
            selectedMusicFilters.insert(option)
        }
    }

    private func matchesSelectedMusicFilters(for asset: RecognizedMusicAsset) -> Bool {
        matchesSelectedMusicFilters(for: asset.song)
    }

    private func matchesSelectedMusicFilters(for song: MusicRecognitionItem) -> Bool {
        guard !selectedMusicFilters.isEmpty else { return true }
        let options = Set(filterOptions(for: song))
        return selectedMusicFilters.allSatisfy { options.contains($0) }
    }

    private func filterOptions(for song: MusicRecognitionItem) -> [MusicFilterOption] {
        let metadata = [
            MusicFilterOption(kind: .title, value: song.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            MusicFilterOption(kind: .artist, value: song.artist.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        let tags = visibleTags(for: song).map { MusicFilterOption(kind: .tag, value: $0) }
        return (metadata + tags).filter { !$0.value.isEmpty }
    }

    private func visibleTags(for song: MusicRecognitionItem) -> [String] {
        MusicRecognitionItem.cleanedTags(song.tags)
            .filter { !isMetadataValue($0, for: song) }
    }

    private func isMetadataValue(_ value: String, for song: MusicRecognitionItem) -> Bool {
        let valueKey = normalizedSearch(value)
        guard !valueKey.isEmpty else { return true }

        let titleKey = normalizedSearch(song.title)
        let artistKey = normalizedSearch(song.artist)
        if valueKey == titleKey || valueKey == artistKey {
            return true
        }

        let separators = CharacterSet(charactersIn: ",，/、·&")
        let artistParts = song.artist
            .components(separatedBy: separators)
            .map(normalizedSearch)
            .filter { !$0.isEmpty }
        return artistParts.contains(valueKey)
    }

    private func isAMReadySong(_ song: MusicRecognitionItem) -> Bool {
        let hasTitle = !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasArtist = !song.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasArtwork = normalizedMusicArtworkURL(song.artworkURL) != nil
            || !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAMLink = !song.appleMusicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasTitle && hasArtist && hasArtwork && hasAMLink
    }

    private func runAppleMusicSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchMessage = nil
            isSearching = false
            return
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }

        isSearching = true
        searchMessage = nil
        libraryStore.prepareExternalServiceWork()
        do {
            let results = try await LibraryStore.searchAppleMusic(query: query)
            guard !Task.isCancelled else { return }
            searchResults = results
            searchMessage = results.isEmpty ? "没有搜索结果" : nil
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            searchMessage = "搜索失败"
        }
        isSearching = false
    }

}

nonisolated func normalizedSearch(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
}

func fileSizeText(_ size: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
}

func fileDragProvider(for fileURL: URL, suggestedName: String) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.suggestedName = suggestedName
    let typeIdentifier = UTType(filenameExtension: fileURL.pathExtension)?.identifier ?? UTType.data.identifier

    provider.registerFileRepresentation(
        forTypeIdentifier: typeIdentifier,
        fileOptions: .openInPlace,
        visibility: .all
    ) { completion in
        let progress = Progress(totalUnitCount: 1)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            completion(nil, true, NSError(
                domain: "LapianBao.FileDrag",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "文件不存在"]
            ))
            return progress
        }

        progress.completedUnitCount = 1
        completion(fileURL, true, nil)
        return progress
    }

    provider.registerObject(fileURL as NSURL, visibility: .all)
    return provider
}
