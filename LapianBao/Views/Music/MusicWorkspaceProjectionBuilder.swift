//
//  MusicWorkspaceProjectionBuilder.swift
//  LapianBao
//
//  Projection, grouping, filtering, sorting, and tag semantics for MusicWorkspaceView.
//

import Foundation

nonisolated struct MusicWorkspaceProjectionInput: Sendable {
    var videos: [VideoItem]
    var musicsByVideoPath: [String: [MusicRecognitionItem]]
    var localMusicAssets: [LocalMusicAsset]
    var musicDownloadJobs: [MusicDownloadJob]
    var metadataByVideoPath: [String: VideoMetadata]
    var allMusicTags: [String]
    var searchText: String
    var searchResults: [AppleMusicSearchResult]
    var selectedMusicFilters: Set<MusicFilterOption>
    var isMusicTagFilterBarPresented: Bool
    var sortOption: MusicSortOption
    var sortDirection: VideoSortDirection
    var musicDownloadCompletionSnapshot: MusicDownloadCompletionSnapshot
    var musicDownloadLookupCaches: MusicDownloadLookupCaches
    var localMusicWaveformSamplesByPath: [String: [Double]]
    var knownLocalResourcePaths: Set<String>
}

nonisolated struct MusicWorkspaceProjectionBuilder: Sendable {
    static let singleSongArtistFilterCollapseThreshold = 24

    var input: MusicWorkspaceProjectionInput
    private let videoNameByPath: [String: String]
    private let localMusicFilePaths: Set<String>
    private let searchQuery: String

    init(input: MusicWorkspaceProjectionInput) {
        self.input = input
        videoNameByPath = Dictionary(
            uniqueKeysWithValues: input.videos.map { ($0.url.path, $0.name) }
        )
        localMusicFilePaths = Set(input.localMusicAssets.map(\.filePath))
        searchQuery = normalizedSearch(input.searchText)
    }

    func makeProjection() -> MusicWorkspaceProjection {
        let recognizedAssets = musicAssets
        let sourceVideoNamesByMusicKey = recognizedSourceVideoNamesByMusicKey(from: recognizedAssets)
        let recognizedMusicIdentityKeys = musicIdentityKeys(from: recognizedAssets)
        let allLocalMusicGroups = groupedLocalMusicAssets(from: folderLocalMusicAssets)
        let displayedLocalMusicGroups = allLocalMusicGroups.filter {
            shouldDisplayLocalMusicGroup($0, recognizedMusicIdentityKeys: recognizedMusicIdentityKeys)
        }
        let localMusicIdentityKeys = localMusicLibraryIdentityKeys(from: displayedLocalMusicGroups)
        let artistTags = input.isMusicTagFilterBarPresented
            ? musicArtistTagLookup(from: recognizedAssets, localGroups: displayedLocalMusicGroups)
            : [:]
        let filterValues = input.isMusicTagFilterBarPresented
            ? musicFilterValues(
                from: recognizedAssets,
                localGroups: displayedLocalMusicGroups,
                artistTags: artistTags
            )
            : [:]
        let musicFilterCounts = input.isMusicTagFilterBarPresented
            ? musicDynamicFilterCounts(
                filterValues: filterValues,
                assets: recognizedAssets,
                localGroups: displayedLocalMusicGroups
            )
            : [:]
        let filteredRecognizedAssets = filteredRecognizedMusicAssets(from: recognizedAssets)
        let matchingLocalMusicGroups = filteredLocalMusicGroups(from: displayedLocalMusicGroups)
        let filteredMusicEntries = sortedMusicLibraryEntries(
            recognizedAssets: filteredRecognizedAssets,
            localGroups: matchingLocalMusicGroups
        )
        let allMusicEntries = sortedMusicLibraryEntries(
            recognizedAssets: recognizedAssets,
            localGroups: displayedLocalMusicGroups
        )
        let filteredSearchItems = sortedAppleMusicSearchResults(
            filteredSearchResults(localMusicIdentityKeys: localMusicIdentityKeys)
        )
        let allMusicRows = allMusicEntries.map {
            musicLibraryRowProjection(for: $0, sourceVideoNamesByMusicKey: sourceVideoNamesByMusicKey)
        }
        let filteredMusicRows = filteredMusicEntries.map {
            musicLibraryRowProjection(for: $0, sourceVideoNamesByMusicKey: sourceVideoNamesByMusicKey)
        }
        let filteredSearchRows = filteredSearchItems.map(appleMusicSearchResultRowProjection(for:))

        return MusicWorkspaceProjection(
            recognizedAssets: recognizedAssets,
            displayedLocalMusicGroups: displayedLocalMusicGroups,
            allEntries: allMusicRows,
            filteredEntries: filteredMusicRows,
            filteredSearchItems: filteredSearchRows,
            filterValues: filterValues,
            musicFilterCounts: musicFilterCounts,
            musicDownloadCompletionSnapshot: input.musicDownloadCompletionSnapshot
        )
    }

    func sortedMusicLibraryEntries(
        recognizedAssets: [RecognizedMusicAsset],
        localGroups: [LocalMusicGroup]
    ) -> [MusicLibraryEntry] {
        let candidates = recognizedAssets.map { asset in
            MusicLibraryEntrySortCandidate(
                entry: .recognized(asset),
                snapshot: sortSnapshot(for: asset)
            )
        } + localGroups.map { group in
            MusicLibraryEntrySortCandidate(
                entry: .local(group),
                snapshot: sortSnapshot(for: group)
            )
        }

        return candidates.sorted {
            musicSortPrecedes($0.snapshot, $1.snapshot)
        }
        .map(\.entry)
    }

    func isLocalMusicEntry(_ entry: MusicLibraryEntry) -> Bool {
        if case .local = entry { return true }
        return false
    }

    func sortedAppleMusicSearchResults(_ results: [AppleMusicSearchResult]) -> [AppleMusicSearchResult] {
        results.sorted {
            musicSortPrecedes(sortSnapshot(for: $0), sortSnapshot(for: $1))
        }
    }

    func musicLibraryRowProjection(
        for entry: MusicLibraryEntry,
        sourceVideoNamesByMusicKey: [String: [String]]
    ) -> MusicLibraryRowProjection {
        switch entry {
        case .recognized(let asset):
            return .recognized(recognizedMusicRowProjection(for: asset))
        case .local(let group):
            return .local(localMusicGroupRowProjection(
                for: group,
                sourceVideoNamesByMusicKey: sourceVideoNamesByMusicKey
            ))
        }
    }

    func appleMusicSearchResultRowProjection(
        for item: AppleMusicSearchResult
    ) -> AppleMusicSearchResultRowProjection {
        let song = item.asMusicRecognitionItem()
        let downloadJobs = musicDownloadJobs(for: song)
        return AppleMusicSearchResultRowProjection(
            item: item,
            song: song,
            visibleTags: visibleTags(for: song),
            downloadJobs: downloadJobs,
            hasDownloadedWaveform: hasCompletedMusicDownload(downloadJobs)
        )
    }

    func recognizedMusicRowProjection(
        for asset: RecognizedMusicAsset
    ) -> RecognizedMusicRowProjection {
        let downloadJobs = musicDownloadJobs(for: asset.song)
        return RecognizedMusicRowProjection(
            asset: asset,
            visibleTags: displayedMusicTags(visibleTags(for: asset.song)),
            suggestedTags: musicTagSuggestions(
                title: asset.song.title,
                artist: asset.song.artist
            ),
            downloadJobs: downloadJobs,
            hasDownloadedWaveform: hasCompletedMusicDownload(downloadJobs),
            downloadedFileURLs: completedMusicFileURLs(from: downloadJobs)
        )
    }

    func localMusicGroupRowProjection(
        for group: LocalMusicGroup,
        sourceVideoNamesByMusicKey: [String: [String]]
    ) -> LocalMusicGroupRowProjection {
        let roleAssets = localMusicRoleAssets(for: group)
        let downloadJobs = localMusicDownloadJobs(for: group, roleAssets: roleAssets)
        return LocalMusicGroupRowProjection(
            group: group,
            roleAssets: roleAssets,
            downloadJobs: downloadJobs,
            displayTitle: group.title,
            displayArtist: group.artist,
            visibleTags: displayedMusicTags(visibleTags(for: group)),
            suggestedTags: musicTagSuggestions(for: group),
            primaryFileURL: localMusicFileURL(for: group.primaryAsset),
            fileURLs: localMusicFileURLs(for: group),
            sourceText: localMusicGroupSourceText(
                for: group,
                sourceVideoNamesByMusicKey: sourceVideoNamesByMusicKey
            ),
            song: localMusicGroupSong(for: group),
            duration: localMusicGroupDuration(for: group)
        )
    }

    func sortSnapshot(for asset: RecognizedMusicAsset) -> MusicSortSnapshot {
        MusicSortSnapshot(
            title: asset.song.title,
            artist: asset.song.artist,
            addedAt: input.metadataByVideoPath[asset.videoPath]?.createdAt,
            id: asset.id
        )
    }

    func sortSnapshot(for group: LocalMusicGroup) -> MusicSortSnapshot {
        MusicSortSnapshot(
            title: group.title,
            artist: group.artist,
            addedAt: localMusicGroupAddedAt(for: group),
            id: group.id
        )
    }

    func sortSnapshot(for entry: MusicLibraryEntry) -> MusicSortSnapshot {
        switch entry {
        case .recognized(let asset):
            return sortSnapshot(for: asset)
        case .local(let group):
            return sortSnapshot(for: group)
        }
    }

    func sortSnapshot(for item: AppleMusicSearchResult) -> MusicSortSnapshot {
        MusicSortSnapshot(
            title: item.title,
            artist: item.artist,
            addedAt: nil,
            id: "\(item.trackID)"
        )
    }

    func musicSortPrecedes(_ lhs: MusicSortSnapshot, _ rhs: MusicSortSnapshot) -> Bool {
        let option = input.sortOption
        let primaryResult = musicSortComparison(lhs, rhs, option: option)

        if primaryResult != .orderedSame {
            if musicSortHasMissingPrimary(lhs, rhs, option: option) {
                return primaryResult == .orderedAscending
            }
            return input.sortDirection == .ascending
                ? primaryResult == .orderedAscending
                : primaryResult == .orderedDescending
        }

        for fallbackOption in [MusicSortOption.title, .artist, .addedDate] where fallbackOption != option {
            let result = musicSortComparison(lhs, rhs, option: fallbackOption)
            if result != .orderedSame {
                return result == .orderedAscending
            }
        }

        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }

    func musicSortComparison(
        _ lhs: MusicSortSnapshot,
        _ rhs: MusicSortSnapshot,
        option: MusicSortOption
    ) -> ComparisonResult {
        switch option {
        case .title:
            return musicSortTextCompare(lhs.title, rhs.title)
        case .addedDate:
            return musicSortDateCompare(lhs.addedAt, rhs.addedAt)
        case .artist:
            return musicSortTextCompare(lhs.artist, rhs.artist)
        }
    }

    func musicSortHasMissingPrimary(
        _ lhs: MusicSortSnapshot,
        _ rhs: MusicSortSnapshot,
        option: MusicSortOption
    ) -> Bool {
        switch option {
        case .title:
            return lhs.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                != rhs.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .addedDate:
            return (lhs.addedAt != nil) != (rhs.addedAt != nil)
        case .artist:
            return lhs.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                != rhs.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func musicSortTextCompare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)

        if left.isEmpty, !right.isEmpty { return .orderedDescending }
        if !left.isEmpty, right.isEmpty { return .orderedAscending }
        return left.localizedStandardCompare(right)
    }

    func musicSortDateCompare(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        guard let lhs, let rhs else {
            if lhs == nil, rhs != nil { return .orderedDescending }
            if lhs != nil, rhs == nil { return .orderedAscending }
            return .orderedSame
        }

        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    func localMusicGroupAddedAt(for group: LocalMusicGroup) -> Date? {
        var latestDate: Date?

        func collect(_ date: Date?) {
            guard let date else { return }
            if latestDate.map({ date > $0 }) ?? true {
                latestDate = date
            }
        }

        for asset in group.assets {
            collect(localMusicDownloadJob(for: asset)?.createdAt)
            collect(asset.createdAt ?? asset.modifiedAt)
        }

        return latestDate
    }

    var musicAssets: [RecognizedMusicAsset] {
        let assets = input.musicsByVideoPath.flatMap { path, songs in
            let isLocalMusic = localMusicFilePaths.contains(path)
            guard let videoName = videoNameByPath[path] else {
                return [RecognizedMusicAsset]()
            }
            return songs
                .filter { isDisplayableRecognizedSong($0, isLocalMusic: isLocalMusic) }
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
        return mergedRecognizedMusicAssets(assets)
    }

    func mergedRecognizedMusicAssets(_ assets: [RecognizedMusicAsset]) -> [RecognizedMusicAsset] {
        var mergedByKey: [String: RecognizedMusicAsset] = [:]
        var orderedKeys: [String] = []

        for asset in assets {
            let key = musicSourceLookupKey(title: asset.song.title, artist: asset.song.artist) ?? asset.id
            guard var current = mergedByKey[key] else {
                mergedByKey[key] = asset
                orderedKeys.append(key)
                continue
            }
            current = mergedRecognizedMusicAsset(current, with: asset)
            mergedByKey[key] = current
        }

        return orderedKeys.compactMap { mergedByKey[$0] }
    }

    func mergedRecognizedMusicAsset(
        _ current: RecognizedMusicAsset,
        with duplicate: RecognizedMusicAsset
    ) -> RecognizedMusicAsset {
        var merged = current
        merged.sourceVideoNames = mergedSourceVideoNames(current.sourceVideoNames + duplicate.sourceVideoNames)
        merged.song = mergedMusicRecognitionItem(current.song, with: duplicate.song)
        return merged
    }

    func mergedSourceVideoNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    func mergedMusicRecognitionItem(
        _ current: MusicRecognitionItem,
        with duplicate: MusicRecognitionItem
    ) -> MusicRecognitionItem {
        var merged = current
        if merged.artworkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.artworkURL = duplicate.artworkURL
        }
        if merged.appleMusicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.appleMusicURL = duplicate.appleMusicURL
        }
        if merged.duration <= 0, duplicate.duration.isFinite, duplicate.duration > 0 {
            merged.duration = duplicate.duration
        }
        merged.tags = MusicRecognitionItem.cleanedMusicTags(
            current.tags + duplicate.tags,
            title: merged.title,
            artist: merged.artist
        )
        return merged
    }

    var folderLocalMusicAssets: [LocalMusicAsset] {
        input.localMusicAssets
    }

    func groupedLocalMusicAssets(from assets: [LocalMusicAsset]) -> [LocalMusicGroup] {
        let projections = assets.map(localMusicProjection(for:))
        let recognizedKeysByTitle = Dictionary(grouping: projections) { projection in
            projection.titleKey
        }
        .mapValues { titleProjections in
            Set(titleProjections.compactMap { projection -> String? in
                guard !projection.titleKey.isEmpty, !projection.artistKey.isEmpty else { return nil }
                return localMusicGroupKey(titleKey: projection.titleKey, artistKey: projection.artistKey)
            })
        }

        var projectionsByKey: [String: [LocalMusicAssetProjection]] = [:]
        for projection in projections {
            let key: String
            if !projection.titleKey.isEmpty, !projection.artistKey.isEmpty {
                key = localMusicGroupKey(titleKey: projection.titleKey, artistKey: projection.artistKey)
            } else if !projection.titleKey.isEmpty,
                      let recognizedKeys = recognizedKeysByTitle[projection.titleKey],
                      recognizedKeys.count == 1,
                      let recognizedKey = recognizedKeys.first {
                key = recognizedKey
            } else if !projection.titleKey.isEmpty {
                key = "title|\(projection.titleKey)"
            } else {
                key = "file|\(LibraryStore.normalizedLocalFilePath(projection.asset.filePath))"
            }
            projectionsByKey[key, default: []].append(projection)
        }

        return projectionsByKey.map { key, projections in
            localMusicGroup(id: key, projections: projections)
        }
        .sorted { lhs, rhs in
            if lhs.title != rhs.title {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            if lhs.artist != rhs.artist {
                return lhs.artist.localizedStandardCompare(rhs.artist) == .orderedAscending
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    func localMusicProjection(for asset: LocalMusicAsset) -> LocalMusicAssetProjection {
        let song = localMusicDisplaySong(for: asset)
        let title = localMusicDisplayTitle(for: asset, song: song)
        let artist = song?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let role = localMusicDisplayRole(for: asset)
        let tags = visibleTags(for: asset, song: song)
        return LocalMusicAssetProjection(
            asset: asset,
            song: song,
            title: title,
            artist: artist,
            titleKey: normalizedLocalMusicGroupingTitle(title),
            artistKey: LibraryStore.normalizedMusicDuplicateText(artist),
            role: role,
            tags: tags
        )
    }

    func localMusicGroup(id: String, projections: [LocalMusicAssetProjection]) -> LocalMusicGroup {
        let sortedProjections = projections.sorted { lhs, rhs in
            let lhsRole = localMusicRoleSortOrder(lhs.role)
            let rhsRole = localMusicRoleSortOrder(rhs.role)
            if lhsRole != rhsRole { return lhsRole < rhsRole }
            return LibraryStore.preferredLocalMusicAssetSort(lhs.asset, rhs.asset)
        }
        let displaySong = sortedProjections.compactMap(\.song).first(where: hasRecognizedTitleAndArtist)
            ?? sortedProjections.compactMap(\.song).first
        let displayTitle = displaySong?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? sortedProjections.first?.title
            ?? ""
        let displayArtist = displaySong?.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? sortedProjections.first { !$0.artist.isEmpty }?.artist
            ?? ""
        let artworkURL = displaySong?.artworkURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let allTags = sortedProjections.flatMap(\.tags)
        let tags = MusicRecognitionItem.cleanedMusicTags(allTags, title: displayTitle, artist: displayArtist)
        let originalAsset = preferredLocalMusicAsset(in: sortedProjections, role: .original)
        let instrumentalAsset = preferredLocalMusicAsset(in: sortedProjections, role: .instrumental)
        let unknownAssets = sortedProjections
            .filter { $0.role == .unknown }
            .map(\.asset)

        return LocalMusicGroup(
            id: id,
            title: displayTitle,
            artist: displayArtist,
            artworkURL: artworkURL,
            tags: tags,
            displaySong: displaySong,
            assets: sortedProjections.map(\.asset),
            originalAsset: originalAsset,
            instrumentalAsset: instrumentalAsset,
            unknownAssets: unknownAssets
        )
    }

    func localMusicGroupKey(titleKey: String, artistKey: String) -> String {
        "song|\(artistKey)|\(titleKey)"
    }

    func normalizedLocalMusicGroupingTitle(_ title: String) -> String {
        var text = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        let patterns = [
            #"\([^)]*(instrumental|karaoke|off vocal|off-vocal|伴奏|纯音乐|无人声|原曲|original|inst)[^)]*\)"#,
            #"（[^）]*(instrumental|karaoke|off vocal|off-vocal|伴奏|纯音乐|无人声|原曲|original|inst)[^）]*）"#,
            #"\[[^\]]*(instrumental|karaoke|off vocal|off-vocal|伴奏|纯音乐|无人声|原曲|original|inst)[^\]]*\]"#,
            #"【[^】]*(instrumental|karaoke|off vocal|off-vocal|伴奏|纯音乐|无人声|原曲|original|inst)[^】]*】"#,
            #"\b(instrumental|karaoke|off vocal|off-vocal|original|official audio|official music video|music video|inst)\b"#,
            #"(伴奏版?|纯音乐|无人声|原曲|官方音频|音乐视频)"#
        ]
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func preferredLocalMusicAsset(
        in projections: [LocalMusicAssetProjection],
        role: LocalMusicAsset.Role
    ) -> LocalMusicAsset? {
        projections
            .filter { $0.role == role }
            .map(\.asset)
            .sorted(by: LibraryStore.preferredLocalMusicAssetSort)
            .first
    }

    func localMusicGroupSong(for group: LocalMusicGroup) -> MusicRecognitionItem {
        group.displaySong ?? MusicRecognitionItem(
            title: group.title,
            artist: group.artist,
            artworkURL: group.artworkURL,
            appleMusicURL: "",
            detectedAt: 0,
            tags: group.tags
        )
    }

    func localMusicDownloadJobs(
        for group: LocalMusicGroup,
        roleAssets: [LocalMusicRoleAsset]
    ) -> [MusicDownloadJob] {
        let song = localMusicGroupSong(for: group)
        let songKey = "\(song.title)|\(song.artist)"
        let persistedJobs = input.musicDownloadLookupCaches.jobsBySongKey[songKey] ?? []
        let syntheticJobs = roleAssets.compactMap { roleAsset -> MusicDownloadJob? in
            let type = localMusicDownloadType(for: roleAsset.role)
            let fileURL = URL(fileURLWithPath: roleAsset.asset.filePath)
            guard localMusicFileExists(at: roleAsset.asset.filePath) else { return nil }
            return MusicDownloadJob(
                id: stableLocalMusicDownloadJobID(
                    filePath: roleAsset.asset.filePath,
                    type: type
                ),
                songKey: songKey,
                type: type,
                status: .succeeded(fileURL.lastPathComponent),
                downloadProgress: 1,
                filePath: roleAsset.asset.filePath,
                waveformSamples: input.localMusicWaveformSamplesByPath[roleAsset.asset.filePath],
                isPreparingWaveform: false,
                createdAt: roleAsset.asset.modifiedAt ?? Date.distantPast
            )
        }
        return latestMusicDownloadJobs(persistedJobs + syntheticJobs)
    }

    func musicDownloadJobs(for song: MusicRecognitionItem) -> [MusicDownloadJob] {
        let songKey = "\(song.title)|\(song.artist)"
        return input.musicDownloadLookupCaches.jobsBySongKey[songKey] ?? []
    }

    func completedMusicFileURL(for job: MusicDownloadJob?) -> URL? {
        guard
            let job,
            case .succeeded = job.status,
            let filePath = job.filePath
        else { return nil }

        if input.musicDownloadCompletionSnapshot.filePathByJobID[job.id] != nil {
            return URL(fileURLWithPath: filePath)
        }

        if localMusicFileExists(at: filePath) {
            return URL(fileURLWithPath: filePath)
        }

        return nil
    }

    func hasCompletedMusicDownload(_ jobs: [MusicDownloadJob]) -> Bool {
        jobs.contains { completedMusicFileURL(for: $0) != nil }
    }

    func completedMusicFileURLs(from jobs: [MusicDownloadJob]) -> [URL] {
        var seenPaths = Set<String>()
        return MusicDownloadJob.DownloadType.allCases.compactMap { type in
            jobs.last { job in
                job.type == type && completedMusicFileURL(for: job) != nil
            }
        }
        .compactMap(completedMusicFileURL)
        .compactMap { url in
            guard seenPaths.insert(url.path).inserted else { return nil }
            return url
        }
    }

    func localMusicFileURL(for asset: LocalMusicAsset) -> URL? {
        let url = URL(fileURLWithPath: asset.filePath)
        return localMusicFileExists(at: url.path) ? url : nil
    }

    func localMusicFileURLs(for group: LocalMusicGroup) -> [URL] {
        var seenPaths = Set<String>()
        return group.assets.compactMap { asset -> URL? in
            guard let url = localMusicFileURL(for: asset) else { return nil }
            guard seenPaths.insert(url.path).inserted else { return nil }
            return url
        }
    }

    func localMusicFileExists(at path: String) -> Bool {
        input.knownLocalResourcePaths.contains(path)
            || localMusicFilePaths.contains(path)
    }

    func localMusicRoleAssets(for group: LocalMusicGroup) -> [LocalMusicRoleAsset] {
        var roleAssets: [LocalMusicRoleAsset] = []
        if let originalAsset = group.originalAsset {
            roleAssets.append(LocalMusicRoleAsset(role: .original, asset: originalAsset))
        }
        if let instrumentalAsset = group.instrumentalAsset {
            roleAssets.append(LocalMusicRoleAsset(role: .instrumental, asset: instrumentalAsset))
        }
        if roleAssets.isEmpty {
            roleAssets.append(contentsOf: group.unknownAssets.map {
                LocalMusicRoleAsset(role: .unknown, asset: $0)
            })
        }
        if roleAssets.isEmpty {
            roleAssets.append(LocalMusicRoleAsset(role: localMusicDisplayRole(for: group.primaryAsset), asset: group.primaryAsset))
        }
        return roleAssets
    }

    func localMusicDownloadType(for role: LocalMusicAsset.Role) -> MusicDownloadJob.DownloadType {
        switch role {
        case .instrumental:
            return .instrumental
        case .original, .unknown:
            return .original
        }
    }

    func localMusicRoleSortOrder(_ role: LocalMusicAsset.Role) -> Int {
        switch role {
        case .original: return 0
        case .instrumental: return 1
        case .unknown: return 2
        }
    }

    func localMusicGroupMetadataLabels(for group: LocalMusicGroup) -> [String] {
        var labels = localMusicRoleAssets(for: group).map { $0.role.label }
        let fileExtensions = Set(group.assets.map {
            $0.fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }.filter { !$0.isEmpty })
        labels.append(contentsOf: fileExtensions.sorted())
        if group.assets.count > 1 {
            labels.append("\(group.assets.count) 个文件")
        }
        return labels
    }

    func localMusicGroupDuration(for group: LocalMusicGroup) -> Double {
        let durations = group.assets.map(\.duration).filter { $0.isFinite && $0 > 0 }
        if let longestDuration = durations.max() {
            return longestDuration
        }
        return 0
    }

    func recognizedSourceVideoNamesByMusicKey(
        from assets: [RecognizedMusicAsset]
    ) -> [String: [String]] {
        var sourceNamesByKey: [String: [String]] = [:]
        var seenNamesByKey: [String: Set<String>] = [:]

        func appendSource(title: String, artist: String, videoName rawVideoName: String) {
            guard let key = musicSourceLookupKey(title: title, artist: artist) else { return }
            let videoName = rawVideoName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !videoName.isEmpty,
                  seenNamesByKey[key, default: []].insert(videoName).inserted
            else { return }
            sourceNamesByKey[key, default: []].append(videoName)
        }

        for asset in assets {
            for videoName in asset.sourceVideoNames {
                appendSource(title: asset.song.title, artist: asset.song.artist, videoName: videoName)
            }
        }

        for (path, songs) in input.musicsByVideoPath {
            guard let videoName = videoNameByPath[path] else { continue }
            for song in songs where hasRecognizedTitleAndArtist(song) {
                appendSource(title: song.title, artist: song.artist, videoName: videoName)
            }
        }

        return sourceNamesByKey
    }

    func localMusicGroupSourceText(
        for group: LocalMusicGroup,
        sourceVideoNamesByMusicKey: [String: [String]]
    ) -> String? {
        var sourceNames: [String] = []
        var seenSourceNames = Set<String>()

        func collect(title: String, artist: String) {
            guard let key = musicSourceLookupKey(title: title, artist: artist),
                  let names = sourceVideoNamesByMusicKey[key]
            else { return }

            for name in names where seenSourceNames.insert(name).inserted {
                sourceNames.append(name)
            }
        }

        if let song = group.displaySong {
            collect(title: song.title, artist: song.artist)
        }
        collect(title: group.title, artist: group.artist)

        for asset in group.assets {
            let song = localMusicDisplaySong(for: asset)
            if let song {
                collect(title: song.title, artist: song.artist)
            }
            collect(
                title: localMusicDisplayTitle(for: asset, song: song),
                artist: song?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? group.artist
            )
        }

        guard !sourceNames.isEmpty else { return nil }
        if sourceNames.count <= 2 {
            return sourceNames.joined(separator: "、")
        }
        return "\(sourceNames[0]) 等 \(sourceNames.count) 个视频"
    }

    func musicSourceLookupKey(title: String, artist: String) -> String? {
        let titleKey = LibraryStore.normalizedMusicDuplicateText(title)
        let artistKey = LibraryStore.normalizedMusicDuplicateText(artist)
        guard !titleKey.isEmpty, !artistKey.isEmpty else { return nil }
        return "\(artistKey)|\(titleKey)"
    }

    func filteredSearchResults(localMusicIdentityKeys: Set<String>) -> [AppleMusicSearchResult] {
        input.searchResults.filter { item in
            let song = item.asMusicRecognitionItem()
            guard isAMReadySong(song) else { return false }
            guard !isMusicAlreadyInLocalLibrary(song, localMusicIdentityKeys: localMusicIdentityKeys) else { return false }
            return matchesSelectedMusicFilters(for: song)
        }
    }

    func isMusicAlreadyInLocalLibrary(
        _ song: MusicRecognitionItem,
        localMusicIdentityKeys: Set<String>
    ) -> Bool {
        guard let key = musicSourceLookupKey(title: song.title, artist: song.artist) else { return false }
        return localMusicIdentityKeys.contains(key)
    }

    func localMusicLibraryIdentityKeys(from groups: [LocalMusicGroup]) -> Set<String> {
        var keys = Set<String>()

        func collect(title: String, artist: String) {
            guard let key = musicSourceLookupKey(title: title, artist: artist) else { return }
            keys.insert(key)
        }

        for group in groups {
            collect(title: group.title, artist: group.artist)
            if let song = group.displaySong {
                collect(title: song.title, artist: song.artist)
            }

            for asset in group.assets {
                if let song = localMusicDisplaySong(for: asset) {
                    collect(title: song.title, artist: song.artist)
                }
            }
        }

        for job in input.musicDownloadJobs {
            guard
                completedMusicFileURL(for: job) != nil,
                let song = LibraryStore.musicRecognitionItem(fromSongKey: job.songKey, tags: [])
            else { continue }
            collect(title: song.title, artist: song.artist)
        }

        return keys
    }

    func musicIdentityKeys(from assets: [RecognizedMusicAsset]) -> Set<String> {
        Set(assets.compactMap { asset in
            musicSourceLookupKey(title: asset.song.title, artist: asset.song.artist)
        })
    }

    func shouldDisplayLocalMusicGroup(
        _ group: LocalMusicGroup,
        recognizedMusicIdentityKeys: Set<String>
    ) -> Bool {
        guard !recognizedMusicIdentityKeys.isEmpty,
              localMusicGroupIsFullyDownloadBacked(group)
        else { return true }

        let groupIdentityKeys = localMusicGroupIdentityKeys(group)
        guard !groupIdentityKeys.isEmpty else { return true }
        return groupIdentityKeys.isDisjoint(with: recognizedMusicIdentityKeys)
    }

    func localMusicGroupIsFullyDownloadBacked(_ group: LocalMusicGroup) -> Bool {
        !group.assets.isEmpty && group.assets.allSatisfy { localMusicDownloadJob(for: $0) != nil }
    }

    func localMusicGroupIdentityKeys(_ group: LocalMusicGroup) -> Set<String> {
        var keys = Set<String>()

        func collect(title: String, artist: String) {
            guard let key = musicSourceLookupKey(title: title, artist: artist) else { return }
            keys.insert(key)
        }

        collect(title: group.title, artist: group.artist)
        if let song = group.displaySong {
            collect(title: song.title, artist: song.artist)
        }

        for asset in group.assets {
            if let song = localMusicDisplaySong(for: asset) {
                collect(title: song.title, artist: song.artist)
            }
        }

        return keys
    }

    func filteredRecognizedMusicAssets(from assets: [RecognizedMusicAsset]) -> [RecognizedMusicAsset] {
        guard !searchQuery.isEmpty || !input.selectedMusicFilters.isEmpty else {
            return assets
        }
        return assets.filter { asset in
            guard musicAssetMatchesSearch(asset, query: searchQuery) else { return false }
            return matchesSelectedMusicFilters(for: asset)
        }
    }

    func filteredLocalMusicGroups(from groups: [LocalMusicGroup]) -> [LocalMusicGroup] {
        guard !searchQuery.isEmpty || !input.selectedMusicFilters.isEmpty else {
            return groups
        }
        return groups.filter { group in
            guard musicGroupMatchesSearch(group, query: searchQuery) else { return false }
            return matchesSelectedMusicFilters(for: group)
        }
    }

    func musicFilterValues(
        from assets: [RecognizedMusicAsset],
        localGroups: [LocalMusicGroup],
        artistTags: [String: MusicArtistFilterValue]
    ) -> [MusicFilterKind: [String]] {
        let artistValues = artistTags.values.map(\.displayName)
        let tagValues = [MusicRecognitionItem.featuredMusicTag] + assets.flatMap {
            musicFilterTags(for: $0.song)
        } + localGroups.flatMap { musicFilterTags(for: $0) }

        return [
            .local: [MusicFilterOption.local.value],
            .artist: cleanedMusicFilterValues(artistValues),
            .tag: cleanedMusicTagFilterValues(tagValues)
        ]
    }

    func cleanedMusicFilterValues(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func cleanedMusicTagFilterValues(_ values: [String]) -> [String] {
        cleanedMusicFilterValues(values)
            .filter { !MusicRecognitionItem.isFallbackMusicTag($0) }
            .sorted { lhs, rhs in
                if isFeaturedMusicTag(lhs) != isFeaturedMusicTag(rhs) { return isFeaturedMusicTag(lhs) }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }

    func musicDynamicFilterCounts(
        filterValues: [MusicFilterKind: [String]],
        assets: [RecognizedMusicAsset],
        localGroups: [LocalMusicGroup]
    ) -> [MusicFilterKind: [String: Int]] {
        if searchQuery.isEmpty, input.selectedMusicFilters.isEmpty {
            return fastMusicDynamicFilterCounts(
                filterValues: filterValues,
                assets: assets,
                localGroups: localGroups
            )
        }
        let searchMatchedAssets = searchQuery.isEmpty
            ? assets
            : assets.filter { musicAssetMatchesSearch($0, query: searchQuery) }
        let searchMatchedGroups = searchQuery.isEmpty
            ? localGroups
            : localGroups.filter { musicGroupMatchesSearch($0, query: searchQuery) }

        return Dictionary(
            uniqueKeysWithValues: MusicFilterKind.allCases.map { kind in
                let counts = Dictionary(
                    uniqueKeysWithValues: filterValues[kind, default: []].map { value in
                        let option = MusicFilterOption(kind: kind, value: value)
                        return (
                            value,
                            musicCandidateCount(
                                for: option,
                                fromSearchMatchedAssets: searchMatchedAssets,
                                searchMatchedLocalGroups: searchMatchedGroups
                            )
                        )
                    }
                )
                return (kind, counts)
            }
        )
    }

    func fastMusicDynamicFilterCounts(
        filterValues: [MusicFilterKind: [String]],
        assets: [RecognizedMusicAsset],
        localGroups: [LocalMusicGroup]
    ) -> [MusicFilterKind: [String: Int]] {
        let artistValues = Set(filterValues[.artist, default: []])
        let tagValues = Set(filterValues[.tag, default: []])
        var songKeysByArtist: [String: Set<String>] = [:]
        var tagCounts: [String: Int] = Dictionary(uniqueKeysWithValues: tagValues.map { ($0, 0) })

        func collectArtist(title: String, artist: String) {
            let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard artistValues.contains(artist),
                  let key = musicSongIdentityKey(title: title, artist: artist)
            else { return }
            songKeysByArtist[artist, default: []].insert(key)
        }

        func collectTags(_ tags: [String]) {
            for tag in Set(tags) where tagValues.contains(tag) {
                tagCounts[tag, default: 0] += 1
            }
        }

        for asset in assets {
            collectArtist(title: asset.song.title, artist: asset.song.artist)
            collectTags(musicFilterTags(for: asset.song))
        }

        for group in localGroups {
            collectArtist(title: group.title, artist: group.artist)
            collectTags(musicFilterTags(for: group))
        }

        let artistCounts = Dictionary(uniqueKeysWithValues: artistValues.map { artist in
            (artist, songKeysByArtist[artist, default: []].count)
        })
        return [
            .local: [MusicFilterOption.local.value: localMusicCandidateCount(assets: assets, localGroups: localGroups)],
            .artist: artistCounts,
            .tag: tagCounts
        ]
    }

    func musicCandidateCount(
        for option: MusicFilterOption,
        fromSearchMatchedAssets assets: [RecognizedMusicAsset],
        searchMatchedLocalGroups localGroups: [LocalMusicGroup]
    ) -> Int {
        let candidateFilters = candidateMusicFilters(for: option)
        let matchingAssets = assets.filter { asset in
            matchesMusicFilters(for: asset, filters: candidateFilters)
        }
        let matchingGroups = localGroups.filter { group in
            matchesMusicFilters(for: group, filters: candidateFilters)
        }

        switch option.kind {
        case .local:
            return matchingAssets.count + matchingGroups.count
        case .artist:
            return musicUniqueSongCount(assets: matchingAssets, localGroups: matchingGroups)
        case .tag:
            return matchingAssets.count + matchingGroups.count
        }
    }

    func candidateMusicFilters(for option: MusicFilterOption) -> Set<MusicFilterOption> {
        if input.selectedMusicFilters.contains(option) {
            return input.selectedMusicFilters
        }

        var filters = input.selectedMusicFilters
        if option.kind == .artist {
            filters = filters.filter { $0.kind != .artist }
        }
        filters.insert(option)
        return filters
    }

    func musicUniqueSongCount(
        assets: [RecognizedMusicAsset],
        localGroups: [LocalMusicGroup]
    ) -> Int {
        var songKeys = Set<String>()

        for asset in assets {
            if let key = musicSongIdentityKey(title: asset.song.title, artist: asset.song.artist) {
                songKeys.insert(key)
            }
        }

        for group in localGroups {
            if let key = musicSongIdentityKey(title: group.title, artist: group.artist) {
                songKeys.insert(key)
            }
        }

        return songKeys.count
    }

    func localMusicCandidateCount(
        assets: [RecognizedMusicAsset],
        localGroups: [LocalMusicGroup]
    ) -> Int {
        assets.filter { hasLocalMusicFile(for: $0) }.count
            + localGroups.filter { hasLocalMusicFile(for: $0) }.count
    }

    func musicSongIdentityKey(title: String, artist: String) -> String? {
        let artistKey = normalizedSearch(artist)
        let titleKey = normalizedSearch(title)
        guard !artistKey.isEmpty, !titleKey.isEmpty else { return nil }
        return "\(artistKey)|\(titleKey)"
    }

    func matchesSelectedMusicFilters(for asset: RecognizedMusicAsset) -> Bool {
        matchesMusicFilters(for: asset, filters: input.selectedMusicFilters)
    }

    func matchesSelectedMusicFilters(for group: LocalMusicGroup) -> Bool {
        matchesMusicFilters(for: group, filters: input.selectedMusicFilters)
    }

    func matchesSelectedMusicFilters(for song: MusicRecognitionItem) -> Bool {
        matchesMusicFilters(for: song, filters: input.selectedMusicFilters)
    }

    func matchesMusicFilters(for asset: RecognizedMusicAsset, filters: Set<MusicFilterOption>) -> Bool {
        matchesMusicFilters(
            filters: filters,
            isLocal: hasLocalMusicFile(for: asset),
            options: Set(filterOptions(for: asset.song))
        )
    }

    func matchesMusicFilters(for group: LocalMusicGroup, filters: Set<MusicFilterOption>) -> Bool {
        matchesMusicFilters(
            filters: filters,
            isLocal: hasLocalMusicFile(for: group),
            options: Set(filterOptions(for: group))
        )
    }

    func matchesMusicFilters(for song: MusicRecognitionItem, filters: Set<MusicFilterOption>) -> Bool {
        matchesMusicFilters(
            filters: filters,
            isLocal: hasCompletedMusicDownload(musicDownloadJobs(for: song)),
            options: Set(filterOptions(for: song))
        )
    }

    func matchesMusicFilters(
        filters: Set<MusicFilterOption>,
        isLocal: Bool,
        options: Set<MusicFilterOption>
    ) -> Bool {
        guard !filters.isEmpty else { return true }
        return filters.allSatisfy { option in
            switch option.kind {
            case .local:
                return isLocal
            case .artist, .tag:
                return options.contains(option)
            }
        }
    }

    func hasLocalMusicFile(for asset: RecognizedMusicAsset) -> Bool {
        if localMusicFilePaths.contains(asset.videoPath), localMusicFileExists(at: asset.videoPath) {
            return true
        }
        return hasCompletedMusicDownload(musicDownloadJobs(for: asset.song))
    }

    func hasLocalMusicFile(for group: LocalMusicGroup) -> Bool {
        !localMusicFileURLs(for: group).isEmpty
    }

    func musicAssetMatchesSearch(_ asset: RecognizedMusicAsset, query: String) -> Bool {
        query.isEmpty
            || normalizedSearch(asset.song.title).contains(query)
            || normalizedSearch(asset.song.artist).contains(query)
            || asset.sourceVideoNames.contains { normalizedSearch($0).contains(query) }
            || musicFilterTags(for: asset.song).contains { normalizedSearch($0).contains(query) }
    }

    func musicGroupMatchesSearch(_ group: LocalMusicGroup, query: String) -> Bool {
        let tags = musicFilterTags(for: group)
        let metadataLabels = localMusicGroupMetadataLabels(for: group)
        return query.isEmpty
            || normalizedSearch(group.title).contains(query)
            || normalizedSearch(group.artist).contains(query)
            || group.assets.contains { normalizedSearch($0.title).contains(query) }
            || group.assets.contains { normalizedSearch(localMusicDisplayRole(for: $0).label).contains(query) }
            || group.assets.contains { normalizedSearch($0.fileExtension).contains(query) }
            || metadataLabels.contains { normalizedSearch($0).contains(query) }
            || tags.contains { normalizedSearch($0).contains(query) }
    }

    func filterOptions(for song: MusicRecognitionItem) -> [MusicFilterOption] {
        let metadata = [
            MusicFilterOption(kind: .artist, value: song.artist.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        let tags = musicFilterTags(for: song).map {
            MusicFilterOption(kind: .tag, value: $0)
        }
        return (metadata + tags).filter { !$0.value.isEmpty }
    }

    func filterOptions(for group: LocalMusicGroup) -> [MusicFilterOption] {
        let metadata = [
            MusicFilterOption(kind: .artist, value: group.artist.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        let tags = musicFilterTags(for: group).map { MusicFilterOption(kind: .tag, value: $0) }
        return (metadata + tags).filter { !$0.value.isEmpty }
    }

    func musicFilterTags(for song: MusicRecognitionItem) -> [String] {
        let tags = visibleTags(for: song)
        return hasFeaturedMusicTag(song.tags)
            ? cleanedMusicTagFilterValues(tags + [MusicRecognitionItem.featuredMusicTag])
            : tags
    }

    func musicFilterTags(for group: LocalMusicGroup) -> [String] {
        let tags = visibleTags(for: group)
        return hasFeaturedMusicTag(group.tags)
            ? cleanedMusicTagFilterValues(tags + [MusicRecognitionItem.featuredMusicTag])
            : tags
    }

    func visibleTags(for song: MusicRecognitionItem) -> [String] {
        musicMetadataFilteredTags(
            MusicRecognitionItem.cleanedMusicTags(song.displayTags, title: song.title, artist: song.artist),
            metadataValues: [song.title, song.artist]
        )
    }

    func visibleTags(for asset: LocalMusicAsset) -> [String] {
        visibleTags(for: asset, song: localMusicDisplaySong(for: asset))
    }

    func visibleTags(for asset: LocalMusicAsset, song: MusicRecognitionItem?) -> [String] {
        let title = localMusicDisplayTitle(for: asset, song: song)
        let artist = song?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let songTags = song.map { visibleTags(for: $0) } ?? []
        return musicMetadataFilteredTags(
            MusicRecognitionItem.cleanedMusicTags(songTags + asset.tags, title: title, artist: artist),
            metadataValues: musicMetadataValues(for: asset, title: title, artist: artist)
        )
    }

    func visibleTags(for group: LocalMusicGroup) -> [String] {
        musicMetadataFilteredTags(
            MusicRecognitionItem.cleanedMusicTags(group.tags, title: group.title, artist: group.artist),
            metadataValues: musicMetadataValues(for: group)
        )
    }

    func displayedMusicTags(_ tags: [String]) -> [String] {
        tags.filter {
            !isFeaturedMusicTag($0) && !MusicRecognitionItem.isFallbackMusicTag($0)
        }
    }

    func musicTagSuggestions(title: String, artist: String, extraMetadataValues: [String] = []) -> [String] {
        musicMetadataFilteredTags(
            input.allMusicTags,
            metadataValues: [title, artist] + extraMetadataValues
        )
        .filter { !isFeaturedMusicTag($0) && !MusicRecognitionItem.isFallbackMusicTag($0) }
    }

    func musicTagSuggestions(for group: LocalMusicGroup) -> [String] {
        musicMetadataFilteredTags(
            input.allMusicTags,
            metadataValues: musicMetadataValues(for: group)
        )
        .filter { !isFeaturedMusicTag($0) && !MusicRecognitionItem.isFallbackMusicTag($0) }
    }

    func isFeaturedMusicTag(_ tag: String) -> Bool {
        MusicRecognitionItem.isFeaturedMusicTag(tag)
    }

    func hasFeaturedMusicTag(_ tags: [String]) -> Bool {
        tags.contains { isFeaturedMusicTag($0) }
    }

    func musicMetadataValues(for group: LocalMusicGroup) -> [String] {
        [group.title, group.artist] + group.assets.flatMap { asset in
            let song = localMusicDisplaySong(for: asset)
            return musicMetadataValues(
                for: asset,
                title: localMusicDisplayTitle(for: asset, song: song),
                artist: song?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? group.artist
            )
        }
    }

    func musicMetadataValues(for asset: LocalMusicAsset, title: String, artist: String) -> [String] {
        let fileName = URL(fileURLWithPath: asset.filePath).deletingPathExtension().lastPathComponent
        return [title, artist, asset.title, fileName, asset.fileExtension]
    }

    func musicMetadataFilteredTags(_ tags: [String], metadataValues: [String]) -> [String] {
        let metadataKeys = Set(metadataValues.flatMap { musicMetadataKeys(for: $0) })
        guard !metadataKeys.isEmpty else { return tags }
        return tags.filter { !metadataKeys.contains(MusicRecognitionItem.canonicalMusicGenreKey($0)) }
    }

    func musicMetadataKeys(for value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let parts = trimmed
            .components(separatedBy: CharacterSet(charactersIn: ",，/、·&+;；"))
            .map(MusicRecognitionItem.canonicalMusicGenreKey)
            .filter { !$0.isEmpty }
        return [MusicRecognitionItem.canonicalMusicGenreKey(trimmed)] + parts
    }

    func musicArtistTagLookup(
        from assets: [RecognizedMusicAsset],
        localGroups: [LocalMusicGroup]
    ) -> [String: MusicArtistFilterValue] {
        var songKeysByArtistKey: [String: Set<String>] = [:]
        var displayNameByArtistKey: [String: String] = [:]

        for asset in assets {
            collectMusicArtistSong(
                title: asset.song.title,
                artist: asset.song.artist,
                songKeysByArtistKey: &songKeysByArtistKey,
                displayNameByArtistKey: &displayNameByArtistKey
            )
        }

        for group in localGroups {
            collectMusicArtistSong(
                title: group.title,
                artist: group.artist,
                songKeysByArtistKey: &songKeysByArtistKey,
                displayNameByArtistKey: &displayNameByArtistKey
            )
        }

        let artistValues: [String: MusicArtistFilterValue] = displayNameByArtistKey.compactMapValues { displayName in
            let artistKey = normalizedSearch(displayName)
            let songCount = songKeysByArtistKey[artistKey, default: []].count
            guard songCount > 0 else { return nil }
            return MusicArtistFilterValue(displayName: displayName, songCount: songCount)
        }
        let singleSongArtistCount = artistValues.values.filter { $0.songCount == 1 }.count
        guard singleSongArtistCount > Self.singleSongArtistFilterCollapseThreshold else {
            return artistValues
        }

        let selectedArtistValues = Set(input.selectedMusicFilters.filter { $0.kind == .artist }.map(\.value))
        return artistValues.filter { entry in
            entry.value.songCount > 1 || selectedArtistValues.contains(entry.value.displayName)
        }
    }

    func collectMusicArtistSong(
        title: String,
        artist: String,
        songKeysByArtistKey: inout [String: Set<String>],
        displayNameByArtistKey: inout [String: String]
    ) {
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let artistKey = normalizedSearch(artist)
        let titleKey = normalizedSearch(title)
        guard !artistKey.isEmpty, !titleKey.isEmpty else { return }

        songKeysByArtistKey[artistKey, default: []].insert("\(artistKey)|\(titleKey)")
        if displayNameByArtistKey[artistKey] == nil {
            displayNameByArtistKey[artistKey] = artist
        }
    }

    func isAMReadySong(_ song: MusicRecognitionItem) -> Bool {
        let hasTitleAndArtist = hasRecognizedTitleAndArtist(song)
        let hasArtwork = normalizedMusicArtworkURL(song.artworkURL) != nil
            || !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAMLink = !song.appleMusicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasTitleAndArtist && hasArtwork && hasAMLink
    }

    func isDisplayableRecognizedSong(_ song: MusicRecognitionItem, isLocalMusic: Bool) -> Bool {
        isLocalMusic ? hasRecognizedTitleAndArtist(song) : isAMReadySong(song)
    }

    func hasRecognizedTitleAndArtist(_ song: MusicRecognitionItem) -> Bool {
        LibraryStore.hasRecognizedTitleAndArtist(song)
    }

    func localMusicDisplaySong(for asset: LocalMusicAsset) -> MusicRecognitionItem? {
        if let song = asset.recognizedSong, hasRecognizedTitleAndArtist(song) {
            return song
        }
        let songs = input.musicsByVideoPath[asset.filePath, default: []]
        if let song = songs.first(where: hasRecognizedTitleAndArtist) {
            return song
        }
        if let song = asset.recognizedSong,
           !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return song
        }
        if let song = songs.first(where: { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return song
        }
        if let job = localMusicDownloadJob(for: asset) {
            return LibraryStore.musicRecognitionItem(fromSongKey: job.songKey, tags: asset.tags)
        }
        return nil
    }

    func localMusicDownloadJob(for asset: LocalMusicAsset) -> MusicDownloadJob? {
        let assetPath = LibraryStore.normalizedLocalFilePath(asset.filePath)
        return input.musicDownloadLookupCaches.jobByNormalizedFilePath[assetPath]
    }

    func localMusicDisplayTitle(for asset: LocalMusicAsset, song: MusicRecognitionItem?) -> String {
        let title = song?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? asset.title : title
    }

    func localMusicDisplayRole(for asset: LocalMusicAsset) -> LocalMusicAsset.Role {
        if let job = localMusicDownloadJob(for: asset) {
            return LibraryStore.localMusicRole(for: job.type)
        }
        return asset.role
    }

    func stableLocalMusicDownloadJobID(
        filePath: String,
        type: MusicDownloadJob.DownloadType
    ) -> UUID {
        let key = "\(type.rawValue)|\(LibraryStore.normalizedLocalFilePath(filePath))"
        var firstHash: UInt64 = 0xcbf29ce484222325
        var secondHash: UInt64 = 0x9e3779b97f4a7c15

        for byte in key.utf8 {
            firstHash ^= UInt64(byte)
            firstHash = firstHash &* 0x100000001b3
            secondHash ^= UInt64(byte) &+ 0x9e3779b97f4a7c15 &+ (secondHash << 6) &+ (secondHash >> 2)
        }

        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8((firstHash >> UInt64(index * 8)) & 0xff)
            bytes[index + 8] = UInt8((secondHash >> UInt64(index * 8)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
