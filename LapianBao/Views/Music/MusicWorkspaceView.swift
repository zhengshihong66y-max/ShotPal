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
    @ObservedObject var viewModel: MusicWorkspaceViewModel
    let goHome: (String, Double) -> Void

    @AppStorage(AppSettings.Key.musicSortOption) private var musicSortOptionRawValue = MusicSortOption.title.rawValue
    @AppStorage(AppSettings.Key.musicSortDirection) private var musicSortDirectionRawValue = VideoSortDirection.ascending.rawValue
    @State private var musicWorkspaceContentWidth: CGFloat = 0

    private func prepareMusicWorkspaceExternalServiceWork() {
        libraryStore.prepareExternalServiceWork()
    }

    var body: some View {
        let projection = viewModel.projection

        VStack(alignment: .leading, spacing: 12) {
            musicHeader()

            TopChromeBoundedContent {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.isMusicTagFilterBarPresented {
                        musicQuickFilterArea(
                            filterValues: projection.filterValues,
                            localMusicCount: projection.musicFilterCounts[.local, default: [:]][MusicFilterOption.local.value],
                            artistSongCounts: projection.musicFilterCounts[.artist, default: [:]],
                            musicTagCounts: projection.musicFilterCounts[.tag, default: [:]]
                        )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            recognizedMusicSection(
                                allAssets: projection.recognizedAssets,
                                allLocalGroups: projection.displayedLocalMusicGroups,
                                filteredEntries: projection.filteredEntries
                            )
                            searchSection(results: projection.filteredSearchItems)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: MusicWorkspaceContentWidthPreferenceKey.self,
                                    value: proxy.size.width
                                )
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, Design.libraryContentInset)
                        .padding(.bottom, 12)
                    }
                    .fadingVerticalScrollIndicators()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)
        .background(Design.sidebarBg)
        .overlay(alignment: .bottom) {
            if viewModel.launchPreparationStatus.isLoading {
                musicCacheLoadingProgressBar(viewModel.launchPreparationStatus)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .onPreferenceChange(MusicWorkspaceContentWidthPreferenceKey.self) { width in
            let normalizedWidth = max(0, width.rounded(.down))
            if abs(musicWorkspaceContentWidth - normalizedWidth) > 1 {
                musicWorkspaceContentWidth = normalizedWidth
            }
        }
        .onAppear {
            prepareMusicWorkspaceForDisplay()
        }
        .onChange(of: libraryStore.videos) { _, _ in
            scheduleMusicProjectionRefresh()
        }
        .onChange(of: libraryStore.musicsByVideoPath) { _, _ in
            scheduleMusicProjectionRefresh()
        }
        .onChange(of: libraryStore.localMusicAssets) { _, _ in
            scheduleMusicProjectionRefresh()
            scheduleDeferredMusicWorkspaceMaintenance()
        }
        .onChange(of: libraryStore.musicDownloadJobs) { _, _ in
            scheduleMusicProjectionRefresh()
            let completionSnapshot = currentMusicDownloadCompletionSnapshot()
            if viewModel.completedMusicDownloadLibraryChanged(snapshot: completionSnapshot) {
                scheduleDeferredMusicWorkspacePreparation()
                scheduleDeferredMusicWorkspaceMaintenance()
            }
        }
        .onChange(of: viewModel.searchText) { _, _ in
            scheduleMusicProjectionRefresh()
        }
        .onChange(of: viewModel.searchResults) { _, _ in
            scheduleMusicProjectionRefresh()
        }
        .onChange(of: viewModel.selectedMusicFilters) { _, _ in
            scheduleMusicProjectionRefresh()
        }
        .onChange(of: viewModel.isMusicTagFilterBarPresented) { _, isPresented in
            if isPresented {
                scheduleMusicProjectionRefresh()
            }
        }
        .onChange(of: musicSortOptionRawValue) { _, _ in
            scheduleMusicProjectionRefresh()
        }
        .onChange(of: musicSortDirectionRawValue) { _, _ in
            scheduleMusicProjectionRefresh()
        }
        .task(id: viewModel.searchText) {
            await runAppleMusicSearch()
        }
        .task(id: musicWorkspaceDisplayCacheHydrationID) {
            await prewarmMusicWorkspaceDisplayCachesForScroll()
        }
    }

    private func prepareMusicWorkspaceForDisplay() {
        let isFirstDisplay = viewModel.markWorkspaceDisplayed()
        let cachedProjectionApplied: Bool
        if isFirstDisplay {
            if viewModel.useCurrentPreparedProjectionForInitialDisplayIfAvailable() {
                cachedProjectionApplied = true
            } else if viewModel.launchPreparationStatus.isLoading {
                cachedProjectionApplied = false
            } else {
                cachedProjectionApplied = applyCachedMusicWorkspaceProjectionIfAvailable()
            }
        } else {
            cachedProjectionApplied = false
        }
        let completionSnapshot = cachedProjectionApplied
            ? viewModel.projection.musicDownloadCompletionSnapshot
            : currentMusicDownloadCompletionSnapshot()
        if isFirstDisplay {
            viewModel.rememberCompletedMusicDownloadLibraryState(snapshot: completionSnapshot)
        } else if viewModel.completedMusicDownloadLibraryChanged(snapshot: completionSnapshot) {
            scheduleDeferredMusicWorkspacePreparation()
            scheduleDeferredMusicWorkspaceMaintenance()
        }

        if !cachedProjectionApplied && !viewModel.launchPreparationStatus.isLoading {
            _ = viewModel.applyLatestProjectionIfAvailable()
            scheduleInitialMusicProjectionRefresh()
        }
        viewModel.scheduleHeavyRowMediaHydration(resetBeforeLoading: isFirstDisplay && !cachedProjectionApplied)
        if isFirstDisplay {
            scheduleDeferredMusicWorkspacePreparation()
            scheduleDeferredMusicWorkspaceMaintenance()
        }
    }

    private func scheduleInitialMusicProjectionRefresh() {
        viewModel.scheduleInitialProjectionRefresh {
            scheduleMusicProjectionRefresh(delayNanoseconds: 0)
        }
    }

    private func scheduleDeferredMusicWorkspacePreparation() {
        viewModel.scheduleDeferredPreparation {
            libraryStore.syncCompletedMusicDownloadsIntoLocalAssets()
            libraryStore.scanResourceLibrary(
                refreshMode: .deferred,
                loadCachedSnapshotSynchronously: false
            )
            scheduleMusicProjectionRefresh()
        }
    }

    private func scheduleDeferredMusicWorkspaceMaintenance() {
        viewModel.scheduleDeferredMaintenance {
            libraryStore.seedMusicFileDurations(from: libraryStore.localMusicAssets)
        }
    }

    private var musicWorkspaceDisplayCacheHydrationID: String {
        let contentWidth = Int(musicWorkspaceContentWidth.rounded(.down))
        guard contentWidth > 0 else { return "empty" }
        let scale = Int(((NSScreen.main?.backingScaleFactor ?? 2) * 100).rounded())
        return [
            "\(viewModel.displayCacheHydrationRevision)",
            "\(contentWidth)",
            "\(scale)"
        ].joined(separator: "|")
    }

    private func prewarmMusicWorkspaceDisplayCachesForScroll() async {
        let projection = viewModel.projection
        let contentWidth = musicWorkspaceContentWidth
        guard contentWidth > 0 else { return }
        guard !projection.allEntries.isEmpty || !projection.filteredSearchItems.isEmpty else { return }

        try? await Task.sleep(nanoseconds: 90_000_000)
        guard !Task.isCancelled else { return }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        async let waveformRequests: [DownloadedMusicWaveformRenderPrewarmRequest] = Task.detached(priority: .utility) {
            MusicWorkspaceDisplayCacheHydrator.waveformRenderPrewarmRequests(
                projection: projection,
                containerWidth: contentWidth,
                scale: scale
            )
        }.value
        async let artworkURLs: [URL] = Task.detached(priority: .utility) {
            MusicWorkspaceDisplayCacheHydrator.artworkURLs(projection: projection)
        }.value

        let (requests, urls) = await (waveformRequests, artworkURLs)
        guard !Task.isCancelled else { return }

        async let waveformPrewarm: Void = DownloadedMusicWaveformRenderPrewarmQueue.shared.prewarm(requests)
        async let artworkPrewarm: Void = MusicArtworkCache.prewarmCachedArtwork(urls: urls)
        _ = await (waveformPrewarm, artworkPrewarm)
    }

    private func scheduleMusicProjectionRefresh(delayNanoseconds: UInt64 = 140_000_000) {
        let input = makeMusicProjectionInput()
        let signature = MusicWorkspaceProjectionSignature(input: input)
        let libraryURL = libraryStore.libraryURL
        viewModel.scheduleProjectionRefresh(
            signature: signature,
            delayNanoseconds: delayNanoseconds
        ) {
            let projection = MusicWorkspaceProjectionBuilder(input: input).makeProjection()
            if let libraryURL, input.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let cacheSignature = MusicWorkspaceDisplayCache.signature(for: input)
                MusicWorkspaceDisplayCache.save(
                    projection: projection,
                    signature: cacheSignature,
                    in: libraryURL
                )
            }
            return projection
        }
    }

    private func musicHeader() -> some View {
        LibraryToolbar(placeholder: "", text: $viewModel.searchText, searchExpands: false) {
            musicTagFilterButton
            musicSortMenu
        }
    }

    private func musicCacheLoadingProgressBar(_ status: MusicWorkspaceLaunchPreparationStatus) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: status.progress)
                .controlSize(.mini)
                .tint(Design.neutralStrongAccent)
                .frame(width: 118)

            Text(progressPercentText(status.progress))
                .font(Design.numericCaption2(weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.32))
        .clipShape(Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
    }

    private var musicTagFilterButton: some View {
        Button {
            viewModel.isMusicTagFilterBarPresented.toggle()
        } label: {
            toolbarIcon(
                systemName: selectedMusicTagFilterCount == 0 ? "tag" : "tag.fill",
                size: 12,
                tint: viewModel.isMusicTagFilterBarPresented || selectedMusicTagFilterCount > 0
                    ? Design.neutralStrongAccent
                    : Design.libraryToolbarIconTint
            )
                .overlay(alignment: .topTrailing) {
                    if selectedMusicTagFilterCount > 0 {
                        libraryToolbarBadge(selectedMusicTagFilterCount)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .contentShape(Rectangle())
    }

    private var musicSortMenu: some View {
        Menu {
            Section("排序方式") {
                ForEach(MusicSortOption.allCases) { option in
                    Button {
                        let previousOption = selectedMusicSortOption
                        musicSortOptionRawValue = option.rawValue
                        if option == .addedDate, previousOption != .addedDate {
                            musicSortDirectionRawValue = VideoSortDirection.descending.rawValue
                        }
                    } label: {
                        Label(option.title, systemImage: selectedMusicSortOption == option ? "checkmark" : "")
                    }
                }
            }

            Section("方向") {
                ForEach(VideoSortDirection.allCases) { direction in
                    Button {
                        musicSortDirectionRawValue = direction.rawValue
                    } label: {
                        Label(direction.title, systemImage: selectedMusicSortDirection == direction ? "checkmark" : direction.systemImage)
                    }
                }
            }
        } label: {
            libraryToolbarIcon(systemName: "arrow.up.arrow.down", size: 12, opticalOffsetX: 2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
    }

    private func musicQuickFilterArea(
        filterValues: [MusicFilterKind: [String]],
        localMusicCount: Int?,
        artistSongCounts: [String: Int],
        musicTagCounts: [String: Int]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isMusicTagFilterBarPresented {
                musicQuickFilterChipRow(
                    title: "作者",
                    kind: .artist,
                    values: filterValues[.artist, default: []],
                    counts: artistSongCounts,
                    allSystemImage: nil,
                    emptyText: "暂无可显示作者"
                )
                musicQuickFilterChipRow(
                    title: "类型",
                    kind: .tag,
                    values: filterValues[.tag, default: []],
                    counts: musicTagCounts,
                    allSystemImage: "tag",
                    leadingOptions: [MusicFilterOption.local],
                    leadingCounts: [MusicFilterOption.local.value: localMusicCount].compactMapValues { $0 }
                )
            }
        }
        .padding(.horizontal, Design.libraryContentInset)
        .padding(.vertical, 10)
    }

    private func musicQuickFilterChipRow(
        title: String,
        kind: MusicFilterKind,
        values: [String],
        counts: [String: Int] = [:],
        allSystemImage: String?,
        leadingOptions: [MusicFilterOption] = [],
        leadingCounts: [String: Int] = [:],
        emptyText: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)

            if values.isEmpty && leadingOptions.isEmpty {
                Text(emptyText ?? "暂无\(title)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(minHeight: 28, alignment: .leading)
            } else {
                WrappingFilterChipGroup {
                    ForEach(leadingOptions) { option in
                        QuickFilterChoiceChip(
                            title: option.value,
                            systemImage: "externaldrive",
                            count: leadingCounts[option.value],
                            isSelected: viewModel.selectedMusicFilters.contains(option),
                            tint: Design.annotationAccent
                        ) {
                            toggleMusicFilter(option)
                        }
                    }

                    ForEach(values, id: \.self) { value in
                        let option = MusicFilterOption(kind: kind, value: value)
                        QuickFilterChoiceChip(
                            title: value,
                            systemImage: kind == .tag ? nil : allSystemImage,
                            count: counts[value],
                            isSelected: viewModel.selectedMusicFilters.contains(option),
                            tint: Design.annotationAccent
                        ) {
                            if kind == .tag {
                                toggleMusicFilter(option)
                            } else {
                                toggleSingleMusicFilter(option)
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    @ViewBuilder
    private func searchSection(
        results: [AppleMusicSearchResultRowProjection]
    ) -> some View {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty && !viewModel.isSearching {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title: "AM 搜索", count: results.count, icon: "magnifyingglass")

                if let searchMessage = viewModel.searchMessage {
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
                        ForEach(results) { row in
                            appleMusicResultRow(row)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recognizedMusicSection(
        allAssets: [RecognizedMusicAsset],
        allLocalGroups: [LocalMusicGroup],
        filteredEntries: [MusicLibraryRowProjection]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if allAssets.isEmpty && allLocalGroups.isEmpty {
                AppEmptyState(
                    title: "主页暂无识别音乐",
                    systemImage: "music.note.list",
                    style: .compact,
                    minHeight: 90
                )
            } else if filteredEntries.isEmpty {
                AppEmptyState(
                    title: "没有匹配条目",
                    systemImage: "line.3.horizontal.decrease.circle",
                    style: .compact,
                    minHeight: 90
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredEntries) { entry in
                        switch entry {
                        case .recognized(let row):
                            recognizedMusicAssetRow(row)
                        case .local(let row):
                            localMusicGroupRow(row)
                        }
                    }
                }
            }
        }
    }

    private func musicRowLayout(
        containerWidth: CGFloat,
        tags: [String],
        hasWaveform _: Bool,
        includesSafari: Bool,
        hasTagEditor: Bool = false,
        actionWidth: CGFloat = MusicRowMetrics.buttonsWidth,
        sideActionWidth: CGFloat = 0
    ) -> (
        infoWidth: CGFloat,
        tagWidth: CGFloat,
        waveformWidth: CGFloat,
        metadataWidth: CGFloat,
        showsTags: Bool,
        showsWaveform: Bool
    ) {
        let hasTagContent = hasTagEditor || !tags.isEmpty
        let showsTags = hasTagContent && containerWidth >= (includesSafari ? 560 : 500)
        let showsWaveform = containerWidth >= (showsTags ? (includesSafari ? 800 : 760) : 620)
        let metadataWidth = MusicRowMetrics.metadataWidth
        let safariWidth: CGFloat = includesSafari ? 24 : 0
        let minimumWaveformWidth: CGFloat = showsWaveform ? (containerWidth < 900 ? 168 : 236) : 0
        let downloadControlsWidth = actionWidth
            + (showsWaveform ? MusicRowMetrics.columnSpacing + minimumWaveformWidth : 0)
        let visibleColumnCount = 3
            + (showsTags ? 1 : 0)
            + (includesSafari ? 1 : 0)
            + (sideActionWidth > 0 ? 1 : 0)
        let spacingWidth = CGFloat(max(0, visibleColumnCount - 1)) * MusicRowMetrics.columnSpacing
        let fixedWidth = MusicRowMetrics.totalHorizontalPadding
            + MusicRowMetrics.artworkSize
            + safariWidth
            + downloadControlsWidth
            + sideActionWidth
            + spacingWidth
        let flexibleWidth = max(0, containerWidth - fixedWidth)
        let tagWidth = musicTagColumnWidth(
            tags: tags,
            flexibleWidth: flexibleWidth,
            showsTags: showsTags,
            showsWaveform: showsWaveform,
            containerWidth: containerWidth,
            hasTagEditor: hasTagEditor
        )
        let remainingWidth = max(0, flexibleWidth - tagWidth)
        let preferredInfoWidth: CGFloat = containerWidth < 820 ? 210 : 282
        let minimumInfoWidth = min(musicMinimumInfoWidth(containerWidth: containerWidth), remainingWidth)
        let infoWidth = min(preferredInfoWidth, max(minimumInfoWidth, remainingWidth * 0.60))
        let waveformWidth = showsWaveform
            ? minimumWaveformWidth + Swift.max(CGFloat.zero, remainingWidth - infoWidth)
            : 0
        return (infoWidth, tagWidth, waveformWidth, metadataWidth, showsTags, showsWaveform)
    }

    private func musicTagColumnWidth(
        tags _: [String],
        flexibleWidth: CGFloat,
        showsTags: Bool,
        showsWaveform _: Bool,
        containerWidth: CGFloat,
        hasTagEditor _: Bool = false
    ) -> CGFloat {
        guard showsTags, flexibleWidth > 0 else { return 0 }

        let reservedInfoWidth = min(musicMinimumInfoWidth(containerWidth: containerWidth), flexibleWidth)
        let tagBudget = max(0, flexibleWidth - reservedInfoWidth)
        guard tagBudget > 0 else { return 0 }

        return min(MusicRowMetrics.tagColumnWidth, tagBudget)
    }

    private func musicMinimumInfoWidth(containerWidth: CGFloat) -> CGFloat {
        containerWidth < 820
            ? MusicRowMetrics.minimumInfoWidthCompact
            : MusicRowMetrics.minimumInfoWidthRegular
    }

    private func appleMusicResultRow(_ row: AppleMusicSearchResultRowProjection) -> some View {
        let item = row.item
        let song = row.song
        let downloadJobs = row.downloadJobs
        let visibleTags = row.visibleTags
        let hasDownloadedWaveform = row.hasDownloadedWaveform
        let rowDragProvider = musicDownloadDragProvider(from: downloadJobs)

        return GeometryReader { proxy in
            let layout = musicRowLayout(
                containerWidth: proxy.size.width,
                tags: visibleTags,
                hasWaveform: hasDownloadedWaveform,
                includesSafari: false,
                actionWidth: MusicRowMetrics.verticalButtonsWidth
            )

            HStack(alignment: .top, spacing: MusicRowMetrics.columnSpacing) {
                musicArtwork(
                    urlString: item.artworkURL,
                    title: item.title,
                    artist: item.artist,
                    shouldLoad: viewModel.allowsHeavyRowMedia
                )

                musicInfoColumn(
                    title: item.title.isEmpty ? "未知曲目" : item.title,
                    artist: item.artist.isEmpty ? "未知作者" : item.artist,
                    sourceText: nil,
                    width: layout.infoWidth
                )

                musicTagColumn(tags: visibleTags, layout: layout)

                if viewModel.allowsHeavyRowMedia {
                    MusicDownloadControlsAndWaveform(
                        song: song,
                        downloadJobs: downloadJobs,
                        buttonsWidth: MusicRowMetrics.verticalButtonsWidth,
                        buttonLayout: .vertical,
                        elementSpacing: MusicRowMetrics.columnSpacing,
                        timeWidth: layout.metadataWidth,
                        waveformWidth: layout.waveformWidth,
                        waveformHeight: MusicRowMetrics.waveformHeight,
                        fallbackDuration: item.duration
                    )
                } else {
                    deferredMusicDownloadControls(
                        buttonsWidth: MusicRowMetrics.verticalButtonsWidth,
                        waveformWidth: layout.waveformWidth,
                        waveformHeight: MusicRowMetrics.waveformHeight
                    )
                }
            }
            .padding(.horizontal, MusicRowMetrics.contentInsetX)
            .padding(.vertical, MusicRowMetrics.contentInsetY)
            .frame(width: proxy.size.width, height: MusicRowMetrics.rowHeight, alignment: .topLeading)
            .background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
            .contentShape(Rectangle())
            .itemProviderDrag(rowDragProvider)
        }
        .frame(height: MusicRowMetrics.rowHeight)
    }

    private func recognizedMusicAssetRow(_ row: RecognizedMusicRowProjection) -> some View {
        let asset = row.asset
        let downloadJobs = row.downloadJobs
        let visibleTags = row.visibleTags
        let hasDownloadedWaveform = row.hasDownloadedWaveform
        let rowDragProvider = musicDownloadDragProvider(from: downloadJobs)
        let downloadedFileURLs = row.downloadedFileURLs

        return GeometryReader { proxy in
            let layout = musicRowLayout(
                containerWidth: proxy.size.width,
                tags: visibleTags,
                hasWaveform: hasDownloadedWaveform,
                includesSafari: false,
                hasTagEditor: true,
                actionWidth: MusicRowMetrics.verticalButtonsWidth,
                sideActionWidth: MusicRowMetrics.sideActionWidth
            )

            HStack(alignment: .top, spacing: MusicRowMetrics.columnSpacing) {
                Button {
                    goHome(asset.videoPath, asset.song.detectedAt)
                } label: {
                    HStack(alignment: .top, spacing: MusicRowMetrics.columnSpacing) {
                        musicArtwork(
                            urlString: asset.song.artworkURL,
                            title: asset.song.title,
                            artist: asset.song.artist,
                            shouldLoad: viewModel.allowsHeavyRowMedia
                        )

                        musicInfoColumn(
                            title: asset.song.title.isEmpty ? "未知曲目" : asset.song.title,
                            artist: asset.song.artist.isEmpty ? "未知作者" : asset.song.artist,
                            sourceText: asset.sourceText,
                            width: layout.infoWidth
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                musicTagColumn(
                    tags: visibleTags,
                    layout: layout,
                    suggestedTags: row.suggestedTags,
                    onAdd: { libraryStore.addMusicTag($0, to: asset.song, in: asset.videoPath) },
                    onRemove: { libraryStore.removeMusicTag($0, from: asset.song, in: asset.videoPath) }
                )

                if viewModel.allowsHeavyRowMedia {
                    MusicDownloadControlsAndWaveform(
                        song: asset.song,
                        downloadJobs: downloadJobs,
                        buttonsWidth: MusicRowMetrics.verticalButtonsWidth,
                        buttonLayout: .vertical,
                        elementSpacing: MusicRowMetrics.columnSpacing,
                        timeWidth: layout.metadataWidth,
                        waveformWidth: layout.waveformWidth,
                        waveformHeight: MusicRowMetrics.waveformHeight,
                        fallbackDuration: asset.song.duration
                    )
                } else {
                    deferredMusicDownloadControls(
                        buttonsWidth: MusicRowMetrics.verticalButtonsWidth,
                        waveformWidth: layout.waveformWidth,
                        waveformHeight: MusicRowMetrics.waveformHeight
                    )
                }

                recognizedMusicActionColumn(asset: asset, fileURLs: downloadedFileURLs)
                    .frame(
                        width: MusicRowMetrics.sideActionWidth,
                        height: MusicRowMetrics.artworkSize,
                        alignment: .center
                    )
            }
            .padding(.horizontal, MusicRowMetrics.contentInsetX)
            .padding(.vertical, MusicRowMetrics.contentInsetY)
            .frame(width: proxy.size.width, height: MusicRowMetrics.rowHeight, alignment: .topLeading)
            .background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
            .contentShape(Rectangle())
            .itemProviderDrag(rowDragProvider)
        }
        .frame(height: MusicRowMetrics.rowHeight)
    }

    private func localMusicGroupRow(_ row: LocalMusicGroupRowProjection) -> some View {
        let group = row.group
        let downloadJobs = row.downloadJobs
        let displayTitle = row.displayTitle
        let displayArtist = row.displayArtist
        let visibleTags = row.visibleTags
        let primaryFileURL = row.primaryFileURL
        let rowDragProvider = musicDownloadDragProvider(from: downloadJobs)
        let sourceText = row.sourceText
        let fileURLs = row.fileURLs

        return GeometryReader { proxy in
            let layout = musicRowLayout(
                containerWidth: proxy.size.width,
                tags: visibleTags,
                hasWaveform: true,
                includesSafari: false,
                hasTagEditor: true,
                actionWidth: MusicRowMetrics.verticalButtonsWidth,
                sideActionWidth: MusicRowMetrics.sideActionWidth
            )
            HStack(alignment: .top, spacing: MusicRowMetrics.columnSpacing) {
                Button {
                    if let primaryFileURL {
                        NSWorkspace.shared.open(primaryFileURL)
                    }
                } label: {
                    musicArtwork(
                        urlString: group.artworkURL,
                        title: displayTitle,
                        artist: displayArtist,
                        shouldLoad: viewModel.allowsHeavyRowMedia
                    )
                    .opacity(primaryFileURL == nil ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .disabled(primaryFileURL == nil)
                .frame(width: MusicRowMetrics.artworkSize, height: MusicRowMetrics.artworkSize, alignment: .center)

                musicInfoColumn(
                    title: displayTitle.isEmpty ? "未知曲目" : displayTitle,
                    artist: displayArtist,
                    sourceText: sourceText,
                    width: layout.infoWidth
                )

                musicTagColumn(
                    tags: visibleTags,
                    layout: layout,
                    suggestedTags: row.suggestedTags,
                    onAdd: { addLocalMusicGroupTag($0, to: group) },
                    onRemove: { removeLocalMusicGroupTag($0, from: group) }
                )

                if viewModel.allowsHeavyRowMedia {
                    MusicDownloadControlsAndWaveform(
                        song: row.song,
                        downloadJobs: downloadJobs,
                        buttonsWidth: MusicRowMetrics.verticalButtonsWidth,
                        buttonLayout: .vertical,
                        elementSpacing: MusicRowMetrics.columnSpacing,
                        timeWidth: layout.metadataWidth,
                        waveformWidth: layout.waveformWidth,
                        waveformHeight: MusicRowMetrics.waveformHeight,
                        fallbackDuration: row.duration
                    )
                } else {
                    deferredMusicDownloadControls(
                        buttonsWidth: MusicRowMetrics.verticalButtonsWidth,
                        waveformWidth: layout.waveformWidth,
                        waveformHeight: MusicRowMetrics.waveformHeight
                    )
                }

                localMusicActionColumn(group: group, fileURLs: fileURLs)
                    .frame(
                        width: MusicRowMetrics.sideActionWidth,
                        height: MusicRowMetrics.artworkSize,
                        alignment: .center
                    )
            }
            .padding(.horizontal, MusicRowMetrics.contentInsetX)
            .padding(.vertical, MusicRowMetrics.contentInsetY)
            .frame(width: proxy.size.width, height: MusicRowMetrics.rowHeight, alignment: .topLeading)
            .background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
            .contentShape(Rectangle())
            .itemProviderDrag(rowDragProvider)
        }
        .frame(height: MusicRowMetrics.rowHeight)
    }

    private func addLocalMusicGroupTag(_ tag: String, to group: LocalMusicGroup) {
        let builder = makeMusicProjectionBuilder()
        for asset in group.assets {
            libraryStore.addLocalMusicTag(tag, to: asset)
            if let song = builder.localMusicDisplaySong(for: asset) {
                libraryStore.addMusicTag(tag, to: song, in: asset.filePath)
            }
        }
    }

    private func removeLocalMusicGroupTag(_ tag: String, from group: LocalMusicGroup) {
        let builder = makeMusicProjectionBuilder()
        for asset in group.assets {
            libraryStore.removeLocalMusicTag(tag, from: asset)
            if let song = builder.localMusicDisplaySong(for: asset) {
                libraryStore.removeMusicTag(tag, from: song, in: asset.filePath)
            }
        }
    }

    private func localMusicActionColumn(group: LocalMusicGroup, fileURLs: [URL]) -> some View {
        VStack(spacing: MusicRowMetrics.actionButtonSpacing) {
            Button {
                showLocalMusicGroupInFinder(fileURLs)
            } label: {
                musicRowActionIcon("folder")
            }
            .buttonStyle(.plain)
            .disabled(fileURLs.isEmpty)

            musicFeaturedButton(isFeatured: hasFeaturedMusicTag(group.tags)) {
                toggleFeaturedLocalMusicGroup(group)
            }
        }
        .frame(
            width: MusicRowMetrics.sideActionWidth,
            height: MusicRowMetrics.actionColumnHeight,
            alignment: .center
        )
    }

    private func recognizedMusicActionColumn(asset: RecognizedMusicAsset, fileURLs: [URL]) -> some View {
        VStack(spacing: MusicRowMetrics.actionButtonSpacing) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
            } label: {
                musicRowActionIcon("folder")
            }
            .buttonStyle(.plain)
            .disabled(fileURLs.isEmpty)

            musicFeaturedButton(isFeatured: hasFeaturedMusicTag(asset.song.tags)) {
                toggleFeaturedRecognizedMusicAsset(asset)
            }
        }
        .frame(
            width: MusicRowMetrics.sideActionWidth,
            height: MusicRowMetrics.actionColumnHeight,
            alignment: .center
        )
    }

    private func musicFeaturedButton(isFeatured: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            musicRowActionIcon(
                isFeatured ? "star.fill" : "star",
                tint: isFeatured ? .yellow : .white.opacity(0.70)
            )
        }
        .buttonStyle(.plain)
    }

    private func musicRowActionIcon(_ systemName: String, tint: Color = .white.opacity(0.70)) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: MusicRowMetrics.actionButtonSize, height: MusicRowMetrics.actionButtonSize)
            .contentShape(Rectangle())
    }

    private func showLocalMusicGroupInFinder(_ fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
    }

    private func toggleFeaturedRecognizedMusicAsset(_ asset: RecognizedMusicAsset) {
        if hasFeaturedMusicTag(asset.song.tags) {
            libraryStore.removeMusicTag(MusicRecognitionItem.featuredMusicTag, from: asset.song, in: asset.videoPath)
        } else {
            libraryStore.addMusicTag(MusicRecognitionItem.featuredMusicTag, to: asset.song, in: asset.videoPath)
        }
    }

    private func toggleFeaturedLocalMusicGroup(_ group: LocalMusicGroup) {
        if hasFeaturedMusicTag(group.tags) {
            let builder = makeMusicProjectionBuilder()
            for asset in group.assets {
                libraryStore.removeLocalMusicTag(MusicRecognitionItem.featuredMusicTag, from: asset)
                if let song = builder.localMusicDisplaySong(for: asset) {
                    libraryStore.removeMusicTag(MusicRecognitionItem.featuredMusicTag, from: song, in: asset.filePath)
                }
            }
        } else {
            for asset in group.assets {
                libraryStore.addLocalMusicTag(MusicRecognitionItem.featuredMusicTag, to: asset)
            }
        }
    }

    private func musicInfoColumn(
        title: String,
        artist: String,
        sourceText: String?,
        width: CGFloat
    ) -> some View {
        let artistLine = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceLine = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(artistLine.isEmpty ? " " : artistLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(sourceLine.isEmpty ? " " : sourceLine)
                .font(Design.numericCaption2())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: width, height: MusicRowMetrics.artworkSize, alignment: .topLeading)
    }

    @ViewBuilder
    private func musicTagColumn(
        tags: [String],
        layout: (
            infoWidth: CGFloat,
            tagWidth: CGFloat,
            waveformWidth: CGFloat,
            metadataWidth: CGFloat,
            showsTags: Bool,
            showsWaveform: Bool
        ),
        suggestedTags: [String] = [],
        onAdd: ((String) -> Void)? = nil,
        onRemove: ((String) -> Void)? = nil
    ) -> some View {
        if layout.showsTags {
            if let onRemove {
                EditableMusicTagStrip(
                    title: "音乐标签",
                    tags: tags,
                    suggestedTags: suggestedTags,
                    onAdd: onAdd,
                    onRemove: onRemove
                )
                .padding(.top, MusicRowMetrics.tagColumnTopInset)
                .frame(width: layout.tagWidth, height: MusicRowMetrics.artworkSize, alignment: .topLeading)
                .clipped()
            } else if !tags.isEmpty {
                MusicEntryTagStrip(tags: tags)
                    .padding(.top, MusicRowMetrics.tagColumnTopInset)
                    .frame(width: layout.tagWidth, height: MusicRowMetrics.artworkSize, alignment: .topLeading)
                    .clipped()
            } else {
                Color.clear
                    .frame(width: layout.tagWidth, height: MusicRowMetrics.artworkSize, alignment: .topLeading)
            }
        }
    }

    private func sectionHeader(title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Design.annotationAccent)
            Text(title)
                .font(.headline.weight(.semibold))
            Text("\(count)")
                .font(Design.numericCaption2(weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
            Spacer()
        }
    }

    private func toolbarIcon(
        systemName: String,
        size: CGFloat,
        tint: Color = Design.libraryToolbarIconTint
    ) -> some View {
        libraryToolbarIcon(systemName: systemName, size: size, tint: tint)
    }

    private var selectedMusicSortOption: MusicSortOption {
        MusicSortOption(rawValue: musicSortOptionRawValue) ?? .title
    }

    private var selectedMusicSortDirection: VideoSortDirection {
        VideoSortDirection(rawValue: musicSortDirectionRawValue) ?? .ascending
    }

    private func makeMusicProjectionBuilder() -> MusicWorkspaceProjectionBuilder {
        MusicWorkspaceProjectionBuilder(input: makeMusicProjectionInput())
    }

    private func makeMusicProjectionInput(
        completionSnapshot suppliedCompletionSnapshot: MusicDownloadCompletionSnapshot? = nil
    ) -> MusicWorkspaceProjectionInput {
        let completionSnapshot = suppliedCompletionSnapshot ?? currentMusicDownloadCompletionSnapshot()
        return MusicWorkspaceProjectionInput(
            videos: libraryStore.videos,
            musicsByVideoPath: libraryStore.musicsByVideoPath,
            localMusicAssets: libraryStore.localMusicAssets,
            musicDownloadJobs: libraryStore.musicDownloadJobs,
            metadataByVideoPath: libraryStore.metadataByVideoPath,
            allMusicTags: libraryStore.allMusicTags,
            searchText: viewModel.searchText,
            searchResults: viewModel.searchResults,
            selectedMusicFilters: viewModel.selectedMusicFilters,
            isMusicTagFilterBarPresented: viewModel.isMusicTagFilterBarPresented,
            sortOption: selectedMusicSortOption,
            sortDirection: selectedMusicSortDirection,
            musicDownloadCompletionSnapshot: completionSnapshot,
            musicDownloadLookupCaches: MusicDownloadLookupCaches(
                jobs: libraryStore.musicDownloadJobs,
                completionSnapshot: completionSnapshot
            ),
            localMusicWaveformSamplesByPath: libraryStore.localMusicWaveformSamplesByPath,
            knownLocalResourcePaths: libraryStore.knownLocalResourcePaths
        )
    }

    private func currentMusicDownloadCompletionSnapshot() -> MusicDownloadCompletionSnapshot {
        MusicDownloadCompletionSnapshot(
            jobs: libraryStore.musicDownloadJobs,
            knownExistingPaths: currentKnownMusicFilePaths()
        )
    }

    private func currentKnownMusicFilePaths() -> Set<String> {
        libraryStore.knownLocalResourcePaths
            .union(libraryStore.localMusicAssets.map(\.filePath))
    }

    private func applyCachedMusicWorkspaceProjectionIfAvailable() -> Bool {
        guard
            let libraryURL = libraryStore.libraryURL,
            let cachedProjection = MusicWorkspaceDisplayCache.loadLatest(in: libraryURL)
        else { return false }
        viewModel.applyPreparedProjection(cachedProjection)
        return true
    }

    private func hasFeaturedMusicTag(_ tags: [String]) -> Bool {
        tags.contains { MusicRecognitionItem.isFeaturedMusicTag($0) }
    }

    private var selectedMusicTagFilterCount: Int {
        viewModel.selectedMusicTagFilterCount
    }

    private func toggleMusicFilter(_ option: MusicFilterOption) {
        viewModel.toggleMusicFilter(option)
    }

    private func toggleSingleMusicFilter(_ option: MusicFilterOption) {
        viewModel.toggleSingleMusicFilter(option)
    }

    private func musicArtwork(
        urlString: String,
        title: String = "",
        artist: String = "",
        shouldLoad: Bool = true
    ) -> some View {
        MusicArtworkView(
            urlString: urlString,
            title: title,
            artist: artist,
            shouldLoad: shouldLoad,
            allowsFallbackLookup: false
        )
            .frame(width: MusicRowMetrics.artworkSize, height: MusicRowMetrics.artworkSize)
    }

    private func deferredMusicDownloadControls(
        buttonsWidth: CGFloat,
        waveformWidth: CGFloat,
        waveformHeight: CGFloat
    ) -> some View {
        HStack(alignment: .top, spacing: MusicRowMetrics.columnSpacing) {
            VStack(spacing: MusicRowMetrics.actionButtonSpacing) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(.white.opacity(0.06), lineWidth: 0.8)
                    }
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(.white.opacity(0.06), lineWidth: 0.8)
                    }
            }
            .frame(width: buttonsWidth, height: waveformHeight, alignment: .top)

            if waveformWidth > 0 {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(.white.opacity(0.06), lineWidth: 0.8)
                    }
                    .frame(width: waveformWidth, height: waveformHeight)
            }
        }
        .frame(height: waveformHeight, alignment: .top)
        .redacted(reason: .placeholder)
    }

    private func musicDownloadDragProvider(from jobs: [MusicDownloadJob]) -> (() -> NSItemProvider)? {
        let preferredJob = MusicDownloadJob.DownloadType.allCases.compactMap { type in
            jobs.first { job in
                job.type == type && completedMusicFileURL(for: job) != nil
            }
        }
        .first
        return musicDownloadFileDragProvider(for: preferredJob)
    }

    private func runAppleMusicSearch() async {
        await viewModel.runAppleMusicSearch(
            prepareExternalServiceWork: prepareMusicWorkspaceExternalServiceWork,
            search: LibraryStore.searchAppleMusic(query:)
        )
    }

}

private struct EditableMusicTagStrip: View {
    let title: String
    let tags: [String]
    let suggestedTags: [String]
    let onAdd: ((String) -> Void)?
    let onRemove: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)

            editableTagFlow(maxChipWidth: width)
                .padding(.top, 4)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
    }

    private func editableTagFlow(maxChipWidth: CGFloat) -> some View {
        MusicEntryTagFlowLayout(spacing: MusicRowMetrics.tagSpacing, rowSpacing: MusicRowMetrics.tagSpacing) {
            ForEach(tags, id: \.self) { tag in
                EditableMusicTagChip(
                    tag: tag,
                    size: .compact,
                    maxChipWidth: maxChipWidth,
                    onRemove: { onRemove(tag) }
                )
            }

            if let onAdd {
                MusicEntryTagAddChip(
                    title: title,
                    tags: tags,
                    suggestedTags: suggestedTags,
                    size: .compact,
                    onAdd: onAdd,
                    onRemove: onRemove
                )
            }
        }
    }
}

private struct MusicEntryTagStrip: View {
    let tags: [String]

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)

            tagFlow(size: .compact, maxChipWidth: width)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tagFlow(size: MusicEntryTagChip.Size, maxChipWidth: CGFloat) -> some View {
        MusicEntryTagFlowLayout(spacing: MusicRowMetrics.tagSpacing, rowSpacing: MusicRowMetrics.tagSpacing) {
            ForEach(tags, id: \.self) { tag in
                MusicEntryTagChip(tag: tag, size: size, maxChipWidth: maxChipWidth)
            }
        }
    }
}

private struct EditableMusicTagChip: View {
    let tag: String
    let size: MusicEntryTagChip.Size
    let maxChipWidth: CGFloat
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        MusicEntryTagChip(tag: tag, size: size, maxChipWidth: maxChipWidth)
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 6.5, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 11, height: 11)
                        .background(Color.black.opacity(0.72), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.20), lineWidth: 0.6)
                        }
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .scaleEffect(isHovered ? 1 : 0.72)
                .offset(x: 4, y: -4)
                .contentShape(Circle())
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

private struct MusicEntryTagAddChip: View {
    let title: String
    let tags: [String]
    let suggestedTags: [String]
    let size: MusicEntryTagChip.Size
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var isPresented = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            CenteredPlusGlyph(size: max(7, size.fontSize * 0.88), thickness: 1.2)
                .foregroundStyle(isHovered ? Design.tagChipForeground : .secondary)
                .frame(width: addChipWidth - size.horizontalPadding * 2, height: size.height, alignment: .center)
                .padding(.horizontal, size.horizontalPadding)
                .frame(width: addChipWidth, height: size.height, alignment: .center)
                .background(isHovered ? Design.tagChipProminentFill : Design.tagChipFill)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(isHovered ? Design.tagChipSelectedStroke : Design.tagChipStroke, lineWidth: 0.8)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { isHovered = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            TagEditorSection(
                title: title,
                domain: .music,
                tags: tags,
                suggestedTags: suggestedTags,
                chipSize: .compact,
                onAdd: onAdd,
                onRemove: onRemove
            )
            .padding(12)
        }
    }

    private var addChipWidth: CGFloat {
        size.height + size.horizontalPadding * 2
    }
}

private struct MusicEntryTagChip: View {
    enum Size {
        case regular
        case compact
        case mini

        var fontSize: CGFloat {
            switch self {
            case .regular: return 11
            case .compact: return 9.5
            case .mini: return 8.5
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: return 7
            case .compact: return 5.5
            case .mini: return 4.5
            }
        }

        var height: CGFloat {
            switch self {
            case .regular: return 18
            case .compact: return 16
            case .mini: return 14
            }
        }

        var minimumScaleFactor: CGFloat {
            switch self {
            case .regular: return 0.72
            case .compact: return 0.64
            case .mini: return 0.54
            }
        }
    }

    let tag: String
    let size: Size
    let maxChipWidth: CGFloat

    var body: some View {
        let chipWidth = min(maxChipWidth, estimatedChipWidth)
        let textWidth = max(12, chipWidth - size.horizontalPadding * 2)

        Text(tag)
            .font(.system(size: size.fontSize, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(size.minimumScaleFactor)
            .allowsTightening(true)
            .frame(width: textWidth, height: size.height, alignment: .center)
            .foregroundStyle(Design.tagChipForeground)
            .padding(.horizontal, size.horizontalPadding)
            .frame(width: chipWidth, height: size.height, alignment: .center)
            .background(Design.tagChipFill)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Design.tagChipStroke, lineWidth: 0.8)
            }
    }

    private var estimatedChipWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: size.fontSize, weight: .semibold)
        let textWidth = (tag as NSString).size(withAttributes: [.font: font]).width
        return ceil(textWidth) + size.horizontalPadding * 2
    }
}

private struct MusicEntryTagFlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(for: subviews, maxWidth: proposal.width ?? 0).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(for: subviews, maxWidth: bounds.width)
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func layout(
        for subviews: Subviews,
        maxWidth: CGFloat
    ) -> (positions: [CGPoint], sizes: [CGSize], size: CGSize) {
        guard !subviews.isEmpty else {
            return ([], [], .zero)
        }

        let widthLimit = max(1, maxWidth)
        let sizes = subviews.map { subview in
            let size = subview.sizeThatFits(.unspecified)
            return CGSize(width: min(size.width, widthLimit), height: size.height)
        }
        var positions: [CGPoint] = []
        positions.reserveCapacity(sizes.count)

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for size in sizes {
            if x > 0, x + spacing + size.width > widthLimit {
                y += rowHeight + rowSpacing
                x = 0
                rowHeight = 0
            }

            if x > 0 {
                x += spacing
            }

            positions.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width
        }

        return (
            positions: positions,
            sizes: sizes,
            size: CGSize(width: min(usedWidth, widthLimit), height: y + rowHeight)
        )
    }
}

private struct MusicWorkspaceContentWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

nonisolated func normalizedSearch(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
}

func fileDragProvider(for fileURL: URL, suggestedName: String) -> NSItemProvider {
    let type = UTType(filenameExtension: fileURL.pathExtension)
    let dragURL = type?.conforms(to: .audio) == true
        ? externalAudioDragFileURL(for: fileURL, suggestedName: suggestedName)
        : fileURL
    return existingFileItemProvider(
        for: dragURL,
        suggestedName: suggestedName,
        fallbackTypeIdentifier: UTType.data.identifier,
        errorDomain: "LapianBao.FileDrag",
        missingFileMessage: "文件不存在"
    )
}
