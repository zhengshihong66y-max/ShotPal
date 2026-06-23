//
//  MusicWorkspaceModels.swift
//  LapianBao
//
//  Lightweight presentation models used by MusicWorkspaceView.
//

import Foundation
import Combine
import SwiftUI

nonisolated struct MusicDownloadCompletionSnapshot: Codable, Sendable, Equatable {
    var filePathByJobID: [UUID: String]

    static let empty = MusicDownloadCompletionSnapshot(filePathByJobID: [:])

    init(filePathByJobID: [UUID: String]) {
        self.filePathByJobID = filePathByJobID
    }

    init(
        jobs: [MusicDownloadJob],
        knownExistingPaths: Set<String>,
        checksFileSystem: Bool = true
    ) {
        let normalizedKnownPaths = Set(knownExistingPaths.map(LibraryStore.normalizedLocalFilePath))
        var completedPaths: [UUID: String] = [:]

        for job in jobs {
            guard
                case .succeeded = job.status,
                let filePath = job.filePath
            else { continue }

            let normalizedPath = LibraryStore.normalizedLocalFilePath(filePath)
            if normalizedKnownPaths.contains(normalizedPath)
                || (checksFileSystem && FileManager.default.fileExists(atPath: filePath)) {
                completedPaths[job.id] = filePath
            }
        }

        filePathByJobID = completedPaths
    }

    func fileURL(for job: MusicDownloadJob?) -> URL? {
        guard
            let job,
            case .succeeded = job.status,
            let filePath = filePathByJobID[job.id]
        else { return nil }
        return URL(fileURLWithPath: filePath)
    }
}

nonisolated struct MusicDownloadLookupCaches: Sendable {
    var jobsBySongKey: [String: [MusicDownloadJob]]
    var jobByNormalizedFilePath: [String: MusicDownloadJob]

    init(
        jobs: [MusicDownloadJob],
        completionSnapshot: MusicDownloadCompletionSnapshot
    ) {
        jobsBySongKey = Dictionary(grouping: jobs, by: \.songKey)
            .mapValues(latestMusicDownloadJobs)

        var jobsByPath: [String: MusicDownloadJob] = [:]
        for job in jobs {
            guard let filePath = completionSnapshot.filePathByJobID[job.id]
            else { continue }
            let key = LibraryStore.normalizedLocalFilePath(filePath)
            jobsByPath[key] = job
        }
        jobByNormalizedFilePath = jobsByPath
    }
}

nonisolated struct MusicWorkspaceLaunchPreparationStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case loading
        case ready
    }

    var phase: Phase
    var progress: Double
    var message: String

    static let idle = MusicWorkspaceLaunchPreparationStatus(
        phase: .idle,
        progress: 0,
        message: ""
    )
    static let ready = MusicWorkspaceLaunchPreparationStatus(
        phase: .ready,
        progress: 1,
        message: ""
    )

    static func loading(progress: Double, message: String) -> MusicWorkspaceLaunchPreparationStatus {
        MusicWorkspaceLaunchPreparationStatus(
            phase: .loading,
            progress: min(1, max(0, progress)),
            message: message
        )
    }

    var isLoading: Bool {
        phase == .loading
    }
}

@MainActor
final class MusicWorkspaceViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var searchResults: [AppleMusicSearchResult] = []
    @Published var isSearching = false
    @Published var searchMessage: String?
    @Published var selectedMusicFilters: Set<MusicFilterOption> = []
    @Published var isMusicTagFilterBarPresented = true
    @Published var projection = MusicWorkspaceProjection.empty
    @Published var allowsHeavyRowMedia = false
    @Published var displayCacheHydrationRevision = 0
    @Published var launchPreparationStatus = MusicWorkspaceLaunchPreparationStatus.idle

    private var hasDisplayedWorkspace = false
    private var isInitialWorkspaceWarmupActive = false
    private var isInitialProjectionReady = false
    private var isInitialHeavyMediaReady = false
    private var initialProjectionRefreshTask: Task<Void, Never>?
    private var workspacePreparationTask: Task<Void, Never>?
    private var workspaceMaintenanceTask: Task<Void, Never>?
    private var projectionRefreshTask: Task<Void, Never>?
    private var heavyRowMediaTask: Task<Void, Never>?
    private var launchPreparationTask: Task<Void, Never>?
    private var launchPreparationKey: String?
    private var launchPreparationLibraryPath: String?
    private var completedMusicDownloadLibrarySignature = Set<String>()

    var selectedMusicTagFilterCount: Int {
        selectedMusicFilters.filter {
            $0.kind == .local || $0.kind == .artist || $0.kind == .tag
        }.count
    }

    func cancelTasks() {
        initialProjectionRefreshTask?.cancel()
        initialProjectionRefreshTask = nil
        workspacePreparationTask?.cancel()
        workspacePreparationTask = nil
        workspaceMaintenanceTask?.cancel()
        workspaceMaintenanceTask = nil
        projectionRefreshTask?.cancel()
        projectionRefreshTask = nil
        heavyRowMediaTask?.cancel()
        heavyRowMediaTask = nil
        launchPreparationTask?.cancel()
        launchPreparationTask = nil
    }

    var hasPreparedProjection: Bool {
        !projection.allEntries.isEmpty
            || !projection.filteredEntries.isEmpty
            || !projection.filteredSearchItems.isEmpty
            || !projection.recognizedAssets.isEmpty
            || !projection.displayedLocalMusicGroups.isEmpty
    }

    func useCurrentPreparedProjectionForInitialDisplayIfAvailable() -> Bool {
        guard hasPreparedProjection else { return false }
        markInitialProjectionReady()
        return true
    }

    func startLaunchPreparationIfNeeded(
        libraryURL: URL?,
        contentWidth: CGFloat,
        scale: CGFloat,
        sourceKey: String,
        fallbackInput: MusicWorkspaceProjectionInput?
    ) {
        guard let libraryURL else {
            launchPreparationTask?.cancel()
            launchPreparationTask = nil
            launchPreparationKey = nil
            launchPreparationLibraryPath = nil
            launchPreparationStatus = .idle
            return
        }

        let libraryPath = libraryURL.standardizedFileURL.path
        guard let fallbackInput else {
            launchPreparationTask?.cancel()
            launchPreparationTask = nil
            launchPreparationKey = nil
            launchPreparationStatus = .idle
            return
        }
        if launchPreparationStatus.phase == .ready,
           launchPreparationLibraryPath == libraryPath {
            return
        }

        let normalizedWidth = max(1, Int(contentWidth.rounded(.down)))
        let normalizedScale = max(100, Int((scale * 100).rounded()))
        let key = [
            libraryPath,
            "\(normalizedWidth)",
            "\(normalizedScale)",
            sourceKey
        ].joined(separator: "|")
        guard launchPreparationKey != key else { return }

        launchPreparationTask?.cancel()
        launchPreparationKey = key
        launchPreparationLibraryPath = libraryPath
        launchPreparationStatus = .loading(progress: 0.04, message: "读取音乐缓存")

        launchPreparationTask = Task { [weak self, libraryURL, normalizedWidth, scale] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self, !Task.isCancelled else { return }

            let cachedProjection = await Task.detached(priority: .utility) {
                MusicWorkspaceDisplayCache.loadLatest(in: libraryURL)
            }.value
            guard !Task.isCancelled else { return }

            let preparedProjection: MusicWorkspaceProjection
            if let cachedProjection {
                preparedProjection = cachedProjection
            } else {
                self.launchPreparationStatus = .loading(progress: 0.16, message: "生成音乐列表")
                preparedProjection = await Task.detached(priority: .utility) {
                    let projection = MusicWorkspaceProjectionBuilder(input: fallbackInput).makeProjection()
                    let cacheSignature = MusicWorkspaceDisplayCache.signature(for: fallbackInput)
                    MusicWorkspaceDisplayCache.save(
                        projection: projection,
                        signature: cacheSignature,
                        in: libraryURL
                    )
                    return projection
                }.value
                guard !Task.isCancelled else { return }
            }

            self.launchPreparationStatus = .loading(progress: 0.28, message: "准备音乐列表")
            self.applyPreparedProjection(preparedProjection)
            self.allowsHeavyRowMedia = true
            guard !Task.isCancelled else { return }

            self.launchPreparationStatus = .loading(progress: 0.45, message: "加载波形缓存")
            let requests = await Task.detached(priority: .utility) {
                MusicWorkspaceDisplayCacheHydrator.waveformRenderPrewarmRequests(
                    projection: preparedProjection,
                    containerWidth: CGFloat(normalizedWidth),
                    scale: scale
                )
            }.value
            guard !Task.isCancelled else { return }
            if !requests.isEmpty {
                self.launchPreparationStatus = .loading(
                    progress: 0.45,
                    message: "加载波形缓存 \(requests.count)"
                )
            }
            await DownloadedMusicWaveformRenderPrewarmQueue.shared.prewarm(requests)
            guard !Task.isCancelled else { return }

            self.launchPreparationStatus = .loading(progress: 0.82, message: "加载封面缓存")
            let artworkURLs = await Task.detached(priority: .utility) {
                MusicWorkspaceDisplayCacheHydrator.artworkURLs(projection: preparedProjection)
            }.value
            guard !Task.isCancelled else { return }
            if !artworkURLs.isEmpty {
                self.launchPreparationStatus = .loading(
                    progress: 0.82,
                    message: "加载封面缓存 \(artworkURLs.count)"
                )
            }
            await MusicArtworkCache.prewarmCachedArtwork(urls: artworkURLs)
            guard !Task.isCancelled else { return }

            self.launchPreparationStatus = .ready
            self.launchPreparationTask = nil
        }
    }

    func markWorkspaceDisplayed() -> Bool {
        if !hasDisplayedWorkspace {
            beginInitialWorkspaceWarmup()
        }
        defer { hasDisplayedWorkspace = true }
        return !hasDisplayedWorkspace
    }

    private func beginInitialWorkspaceWarmup() {
        isInitialWorkspaceWarmupActive = true
        isInitialProjectionReady = false
        isInitialHeavyMediaReady = false
    }

    private func updateInitialWorkspaceWarmupVisibility() {
        guard isInitialWorkspaceWarmupActive else { return }
        let isReady = isInitialProjectionReady && isInitialHeavyMediaReady
        guard isReady else { return }
        isInitialWorkspaceWarmupActive = false
    }

    private func markInitialProjectionReady() {
        guard isInitialWorkspaceWarmupActive else { return }
        isInitialProjectionReady = true
        updateInitialWorkspaceWarmupVisibility()
    }

    func refreshProjection(
        signature: MusicWorkspaceProjectionSignature,
        build: () -> MusicWorkspaceProjection
    ) {
        let nextProjection = build()
        Self.storeProjection(nextProjection, for: signature)
        projection = nextProjection
        displayCacheHydrationRevision &+= 1
    }

    func scheduleProjectionRefresh(
        signature: MusicWorkspaceProjectionSignature,
        delayNanoseconds: UInt64 = 140_000_000,
        build: @escaping @Sendable () -> MusicWorkspaceProjection
    ) {
        projectionRefreshTask?.cancel()
        if applyCachedProjection(for: signature) {
            markInitialProjectionReady()
            return
        }
        projectionRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            if self.applyCachedProjection(for: signature) {
                self.markInitialProjectionReady()
                return
            }
            let nextProjection = await Task.detached(priority: .userInitiated) {
                build()
            }.value
            guard !Task.isCancelled else { return }
            self.refreshProjection(signature: signature) {
                nextProjection
            }
            self.markInitialProjectionReady()
        }
    }

    private static let projectionCacheLimit = 8
    private static var projectionCache: [MusicWorkspaceProjectionSignature: MusicWorkspaceProjection] = [:]
    private static var projectionCacheOrder: [MusicWorkspaceProjectionSignature] = []
    private static var latestProjection: MusicWorkspaceProjection?

    private func applyCachedProjection(for signature: MusicWorkspaceProjectionSignature) -> Bool {
        guard let cachedProjection = Self.projectionCache[signature] else { return false }
        projection = cachedProjection
        displayCacheHydrationRevision &+= 1
        return true
    }

    func applyLatestProjectionIfAvailable() -> Bool {
        guard let latestProjection = Self.latestProjection else { return false }
        projection = latestProjection
        displayCacheHydrationRevision &+= 1
        return true
    }

    func applyPreparedProjection(_ preparedProjection: MusicWorkspaceProjection) {
        projection = preparedProjection
        Self.latestProjection = preparedProjection
        displayCacheHydrationRevision &+= 1
        markInitialProjectionReady()
    }

    private static func storeProjection(
        _ projection: MusicWorkspaceProjection,
        for signature: MusicWorkspaceProjectionSignature
    ) {
        latestProjection = projection
        projectionCache[signature] = projection
        projectionCacheOrder.removeAll { $0 == signature }
        projectionCacheOrder.append(signature)
        while projectionCacheOrder.count > projectionCacheLimit {
            let removed = projectionCacheOrder.removeFirst()
            projectionCache.removeValue(forKey: removed)
        }
    }

    func scheduleHeavyRowMediaHydration(
        delayNanoseconds: UInt64 = 520_000_000,
        resetBeforeLoading: Bool
    ) {
        heavyRowMediaTask?.cancel()
        guard resetBeforeLoading else {
            isInitialHeavyMediaReady = true
            updateInitialWorkspaceWarmupVisibility()
            allowsHeavyRowMedia = true
            return
        }
        guard !allowsHeavyRowMedia else {
            isInitialHeavyMediaReady = true
            updateInitialWorkspaceWarmupVisibility()
            return
        }
        allowsHeavyRowMedia = false
        heavyRowMediaTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            allowsHeavyRowMedia = true
            isInitialHeavyMediaReady = true
            updateInitialWorkspaceWarmupVisibility()
        }
    }

    func scheduleInitialProjectionRefresh(
        delayNanoseconds: UInt64 = 180_000_000,
        refresh: @escaping @MainActor () -> Void
    ) {
        initialProjectionRefreshTask?.cancel()
        initialProjectionRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    func scheduleDeferredPreparation(prepare: @escaping @MainActor () -> Void) {
        workspacePreparationTask?.cancel()
        workspacePreparationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            prepare()
        }
    }

    func scheduleDeferredMaintenance(seedDurations: @escaping @MainActor () -> Void) {
        workspaceMaintenanceTask?.cancel()
        workspaceMaintenanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            seedDurations()
        }
    }

    func rememberCompletedMusicDownloadLibraryState(snapshot: MusicDownloadCompletionSnapshot) {
        completedMusicDownloadLibrarySignature = completedMusicDownloadSignature(snapshot: snapshot)
    }

    func completedMusicDownloadLibraryChanged(snapshot: MusicDownloadCompletionSnapshot) -> Bool {
        let nextSignature = completedMusicDownloadSignature(snapshot: snapshot)
        defer { completedMusicDownloadLibrarySignature = nextSignature }
        return nextSignature != completedMusicDownloadLibrarySignature
    }

    private func completedMusicDownloadSignature(snapshot: MusicDownloadCompletionSnapshot) -> Set<String> {
        Set(snapshot.filePathByJobID.map { "\($0.key.uuidString)|\($0.value)" })
    }

    func toggleMusicFilter(_ option: MusicFilterOption) {
        if selectedMusicFilters.contains(option) {
            selectedMusicFilters.remove(option)
        } else {
            selectedMusicFilters.insert(option)
        }
    }

    func toggleSingleMusicFilter(_ option: MusicFilterOption) {
        if selectedMusicFilters.contains(option) {
            selectedMusicFilters.remove(option)
        } else {
            selectedMusicFilters = selectedMusicFilters.filter { $0.kind != option.kind }
            selectedMusicFilters.insert(option)
        }
    }

    func runAppleMusicSearch(
        prepareExternalServiceWork: () -> Void,
        search: (String) async throws -> [AppleMusicSearchResult]
    ) async {
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
        if !searchResults.isEmpty {
            searchResults = []
        }

        prepareExternalServiceWork()
        do {
            let results = try await search(query)
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

nonisolated struct RecognizedMusicAsset: Identifiable, Codable, Sendable {
    var videoPath: String
    var videoName: String
    var sourceVideoNames: [String]
    var song: MusicRecognitionItem

    var id: String { "\(videoPath)-\(song.id.uuidString)" }

    init(
        videoPath: String,
        videoName: String,
        sourceVideoNames: [String]? = nil,
        song: MusicRecognitionItem
    ) {
        self.videoPath = videoPath
        self.videoName = videoName
        self.sourceVideoNames = sourceVideoNames ?? [videoName]
        self.song = song
    }

    var sourceText: String {
        let names = sourceVideoNames.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard let first = names.first else { return videoName }
        if names.count <= 2 {
            return names.joined(separator: "、")
        }
        return "\(first) 等 \(names.count) 个视频"
    }
}

nonisolated struct LocalMusicGroup: Identifiable, Codable, Sendable {
    var id: String
    var title: String
    var artist: String
    var artworkURL: String
    var tags: [String]
    var displaySong: MusicRecognitionItem?
    var assets: [LocalMusicAsset]
    var originalAsset: LocalMusicAsset?
    var instrumentalAsset: LocalMusicAsset?
    var unknownAssets: [LocalMusicAsset]

    var primaryAsset: LocalMusicAsset {
        originalAsset ?? instrumentalAsset ?? unknownAssets.first ?? assets[0]
    }

    var hasBothRecognizedRoles: Bool {
        originalAsset != nil && instrumentalAsset != nil
    }
}

nonisolated enum MusicLibraryEntry: Identifiable, Codable, Sendable {
    case recognized(RecognizedMusicAsset)
    case local(LocalMusicGroup)

    var id: String {
        switch self {
        case .recognized(let asset):
            return "recognized|\(asset.id)"
        case .local(let group):
            return "local|\(group.id)"
        }
    }
}

nonisolated struct MusicLibraryEntrySortCandidate: Codable, Sendable {
    var entry: MusicLibraryEntry
    var snapshot: MusicSortSnapshot
}

nonisolated struct MusicSortSnapshot: Codable, Sendable {
    var title: String
    var artist: String
    var addedAt: Date?
    var id: String
}

nonisolated struct LocalMusicAssetProjection: Codable, Sendable {
    var asset: LocalMusicAsset
    var song: MusicRecognitionItem?
    var title: String
    var artist: String
    var titleKey: String
    var artistKey: String
    var role: LocalMusicAsset.Role
    var tags: [String]
}

nonisolated struct LocalMusicRoleAsset: Identifiable, Codable, Sendable {
    var role: LocalMusicAsset.Role
    var asset: LocalMusicAsset

    var id: String { "\(role.rawValue)|\(asset.filePath)" }
}

nonisolated struct MusicArtistFilterValue: Codable, Sendable {
    var displayName: String
    var songCount: Int
}

nonisolated struct AppleMusicSearchResultRowProjection: Identifiable, Codable, Sendable {
    var item: AppleMusicSearchResult
    var song: MusicRecognitionItem
    var visibleTags: [String]
    var downloadJobs: [MusicDownloadJob]
    var hasDownloadedWaveform: Bool

    var id: Int { item.id }
}

nonisolated struct RecognizedMusicRowProjection: Identifiable, Codable, Sendable {
    var asset: RecognizedMusicAsset
    var visibleTags: [String]
    var downloadJobs: [MusicDownloadJob]
    var hasDownloadedWaveform: Bool
    var downloadedFileURLs: [URL]

    var id: String { asset.id }
}

nonisolated struct LocalMusicGroupRowProjection: Identifiable, Codable, Sendable {
    var group: LocalMusicGroup
    var roleAssets: [LocalMusicRoleAsset]
    var downloadJobs: [MusicDownloadJob]
    var displayTitle: String
    var displayArtist: String
    var visibleTags: [String]
    var primaryFileURL: URL?
    var fileURLs: [URL]
    var sourceText: String?
    var song: MusicRecognitionItem
    var duration: Double

    var id: String { group.id }
}

nonisolated enum MusicLibraryRowProjection: Identifiable, Codable, Sendable {
    case recognized(RecognizedMusicRowProjection)
    case local(LocalMusicGroupRowProjection)

    var id: String {
        switch self {
        case .recognized(let row):
            return "recognized|\(row.id)"
        case .local(let row):
            return "local|\(row.id)"
        }
    }
}

nonisolated struct MusicWorkspaceProjection: Codable, Sendable {
    var recognizedAssets: [RecognizedMusicAsset] = []
    var displayedLocalMusicGroups: [LocalMusicGroup] = []
    var allEntries: [MusicLibraryRowProjection] = []
    var filteredEntries: [MusicLibraryRowProjection] = []
    var filteredSearchItems: [AppleMusicSearchResultRowProjection] = []
    var filterValues: [MusicFilterKind: [String]] = [:]
    var musicFilterCounts: [MusicFilterKind: [String: Int]] = [:]
    var musicDownloadCompletionSnapshot: MusicDownloadCompletionSnapshot = .empty

    static let empty = MusicWorkspaceProjection()
}

nonisolated enum MusicWorkspaceDisplayCacheHydrator {
    static func waveformRenderPrewarmRequests(
        projection: MusicWorkspaceProjection,
        containerWidth: CGFloat,
        scale: CGFloat
    ) -> [DownloadedMusicWaveformRenderPrewarmRequest] {
        guard containerWidth > 0 else { return [] }

        var requests: [DownloadedMusicWaveformRenderPrewarmRequest] = []
        var seenKeys = Set<String>()

        func appendJobs(
            _ jobs: [MusicDownloadJob],
            tags: [String],
            sideActionWidth: CGFloat
        ) {
            let waveformWidth = musicWorkspaceWaveformWidth(
                containerWidth: containerWidth,
                tags: tags,
                includesSafari: false,
                actionWidth: MusicRowMetrics.verticalButtonsWidth,
                sideActionWidth: sideActionWidth
            )
            guard waveformWidth > 0 else { return }

            let displaySize = CGSize(width: waveformWidth, height: MusicRowMetrics.waveformHeight)
            for job in jobs {
                guard let samples = job.waveformSamples, !samples.isEmpty else { continue }
                guard let request = DownloadedMusicWaveformRenderPrewarmRequest(
                    samples: samples,
                    size: displaySize,
                    scale: scale,
                    isCompact: false,
                    includesActiveLayers: true
                ) else { continue }
                guard seenKeys.insert(request.key).inserted else { continue }
                requests.append(request)
            }
        }

        for entry in projection.allEntries {
            switch entry {
            case .recognized(let row):
                appendJobs(
                    row.downloadJobs,
                    tags: row.visibleTags,
                    sideActionWidth: MusicRowMetrics.sideActionWidth
                )
            case .local(let row):
                appendJobs(
                    row.downloadJobs,
                    tags: row.visibleTags,
                    sideActionWidth: MusicRowMetrics.sideActionWidth
                )
            }
        }

        for row in projection.filteredSearchItems {
            appendJobs(
                row.downloadJobs,
                tags: row.visibleTags,
                sideActionWidth: 0
            )
        }

        return requests
    }

    static func artworkURLs(projection: MusicWorkspaceProjection) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ rawURLString: String) {
            guard let url = normalizedMusicArtworkURL(rawURLString) else { return }
            guard seen.insert(url.absoluteString).inserted else { return }
            urls.append(url)
        }

        for entry in projection.allEntries {
            switch entry {
            case .recognized(let row):
                append(row.asset.song.artworkURL)
            case .local(let row):
                append(row.group.artworkURL)
            }
        }

        for row in projection.filteredSearchItems {
            append(row.item.artworkURL)
        }

        return urls
    }

    private static func musicWorkspaceWaveformWidth(
        containerWidth: CGFloat,
        tags: [String],
        includesSafari: Bool,
        actionWidth: CGFloat,
        sideActionWidth: CGFloat
    ) -> CGFloat {
        let showsTags = !tags.isEmpty && containerWidth >= (includesSafari ? 560 : 500)
        let showsWaveform = containerWidth >= (showsTags ? (includesSafari ? 800 : 760) : 620)
        guard showsWaveform else { return 0 }

        let safariWidth: CGFloat = includesSafari ? 24 : 0
        let minimumWaveformWidth: CGFloat = containerWidth < 900 ? 168 : 236
        let downloadControlsWidth = actionWidth + MusicRowMetrics.columnSpacing + minimumWaveformWidth
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
        let tagWidth = musicWorkspaceTagColumnWidth(
            flexibleWidth: flexibleWidth,
            showsTags: showsTags,
            containerWidth: containerWidth
        )
        let remainingWidth = max(0, flexibleWidth - tagWidth)
        let preferredInfoWidth: CGFloat = containerWidth < 820 ? 210 : 282
        let minimumInfoWidth = min(musicWorkspaceMinimumInfoWidth(containerWidth: containerWidth), remainingWidth)
        let infoWidth = min(preferredInfoWidth, max(minimumInfoWidth, remainingWidth * 0.60))
        return minimumWaveformWidth + Swift.max(CGFloat.zero, remainingWidth - infoWidth)
    }

    private static func musicWorkspaceTagColumnWidth(
        flexibleWidth: CGFloat,
        showsTags: Bool,
        containerWidth: CGFloat
    ) -> CGFloat {
        guard showsTags, flexibleWidth > 0 else { return 0 }
        let reservedInfoWidth = min(musicWorkspaceMinimumInfoWidth(containerWidth: containerWidth), flexibleWidth)
        let tagBudget = max(0, flexibleWidth - reservedInfoWidth)
        guard tagBudget > 0 else { return 0 }
        return min(MusicRowMetrics.tagColumnWidth, tagBudget)
    }

    private static func musicWorkspaceMinimumInfoWidth(containerWidth: CGFloat) -> CGFloat {
        containerWidth < 820
            ? MusicRowMetrics.minimumInfoWidthCompact
            : MusicRowMetrics.minimumInfoWidthRegular
    }
}

nonisolated struct MusicWorkspaceProjectionSignature: Hashable, Sendable {
    private var digest: Int
    private var videoCount: Int
    private var recognizedSongCount: Int
    private var localMusicCount: Int
    private var downloadJobCount: Int
    private var searchResultCount: Int
    private var filterCount: Int

    init(input: MusicWorkspaceProjectionInput) {
        var hasher = Hasher()
        var recognizedSongCount = 0

        hasher.combine("videos")
        for video in input.videos {
            hasher.combine(video.url.path)
            hasher.combine(video.name)
        }

        hasher.combine("music-recognition")
        for path in input.musicsByVideoPath.keys.sorted() {
            hasher.combine(path)
            let songs = input.musicsByVideoPath[path] ?? []
            recognizedSongCount += songs.count
            for song in songs {
                Self.combine(song, into: &hasher)
            }
        }

        hasher.combine("local-music")
        for asset in input.localMusicAssets.sorted(by: { $0.filePath < $1.filePath }) {
            hasher.combine(asset.filePath)
            hasher.combine(asset.title)
            hasher.combine(asset.fileExtension)
            hasher.combine(asset.role.rawValue)
            hasher.combine(asset.duration)
            hasher.combine(asset.fileSize)
            hasher.combine(asset.createdAt)
            hasher.combine(asset.modifiedAt)
            for tag in asset.tags {
                hasher.combine(tag)
            }
            if let recognizedSong = asset.recognizedSong {
                Self.combine(recognizedSong, into: &hasher)
            }
        }

        hasher.combine("download-jobs")
        for job in input.musicDownloadJobs.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(job.id)
            hasher.combine(job.songKey)
            hasher.combine(job.type.rawValue)
            hasher.combine(Self.statusSignature(job.status))
            hasher.combine(job.downloadProgress)
            hasher.combine(job.filePath)
            hasher.combine(job.waveformSamples?.count ?? 0)
            hasher.combine(job.isPreparingWaveform)
            hasher.combine(job.createdAt)
        }

        hasher.combine("download-completion")
        for (id, path) in input.musicDownloadCompletionSnapshot.filePathByJobID.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            hasher.combine(id)
            hasher.combine(path)
        }

        hasher.combine("metadata")
        for path in input.metadataByVideoPath.keys.sorted() {
            hasher.combine(path)
            guard let metadata = input.metadataByVideoPath[path] else { continue }
            hasher.combine(metadata.duration)
            hasher.combine(metadata.frameRate)
            hasher.combine(metadata.pixelWidth)
            hasher.combine(metadata.pixelHeight)
            hasher.combine(metadata.fileSize)
            hasher.combine(metadata.createdAt)
            hasher.combine(metadata.modifiedAt)
        }

        hasher.combine("tags")
        for tag in input.allMusicTags {
            hasher.combine(tag)
        }

        hasher.combine("query")
        hasher.combine(input.searchText)
        for result in input.searchResults {
            hasher.combine(result.trackID)
            hasher.combine(result.title)
            hasher.combine(result.artist)
            hasher.combine(result.album)
            hasher.combine(result.genre)
            hasher.combine(result.artworkURL)
            hasher.combine(result.appleMusicURL)
            hasher.combine(result.duration)
        }

        hasher.combine("filters")
        for filter in input.selectedMusicFilters.sorted(by: { $0.id < $1.id }) {
            hasher.combine(filter.kind.rawValue)
            hasher.combine(filter.value)
        }
        hasher.combine(input.isMusicTagFilterBarPresented)
        hasher.combine(input.sortOption.rawValue)
        hasher.combine(input.sortDirection.rawValue)

        hasher.combine("known-paths")
        for path in input.knownLocalResourcePaths.sorted() {
            hasher.combine(path)
        }

        digest = hasher.finalize()
        videoCount = input.videos.count
        self.recognizedSongCount = recognizedSongCount
        localMusicCount = input.localMusicAssets.count
        downloadJobCount = input.musicDownloadJobs.count
        searchResultCount = input.searchResults.count
        filterCount = input.selectedMusicFilters.count
    }

    private static func combine(_ song: MusicRecognitionItem, into hasher: inout Hasher) {
        hasher.combine(song.id)
        hasher.combine(song.title)
        hasher.combine(song.artist)
        hasher.combine(song.artworkURL)
        hasher.combine(song.appleMusicURL)
        hasher.combine(song.detectedAt)
        hasher.combine(song.duration)
        for tag in song.tags {
            hasher.combine(tag)
        }
    }

    private static func statusSignature(_ status: RemoteImportJob.Status) -> String {
        switch status {
        case .idle:
            return "idle"
        case .importing:
            return "importing"
        case .transcoding:
            return "transcoding"
        case .finalizing:
            return "finalizing"
        case .paused:
            return "paused"
        case .succeeded(let filename):
            return "succeeded|\(filename)"
        case .failed(let message):
            return "failed|\(message)"
        }
    }
}

nonisolated struct MusicWorkspaceDisplayCacheFile: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    var signature: String
    var generatedAt: Date
    var projection: MusicWorkspaceProjection
}

nonisolated enum MusicWorkspaceDisplayCache {
    static func loadLatest(in libraryURL: URL) -> MusicWorkspaceProjection? {
        let url = ProjectRepository.musicWorkspaceCacheURL(in: libraryURL)
        guard
            let cache = ProjectRepository.readJSON(
                MusicWorkspaceDisplayCacheFile.self,
                from: url,
                decoder: ProjectRepository.makeDecoder(dateDecodingStrategy: .iso8601)
            ),
            cache.version == MusicWorkspaceDisplayCacheFile.currentVersion
        else { return nil }
        return applyingAdaptiveArtistFilterLimit(to: cache.projection)
    }

    static func save(
        projection: MusicWorkspaceProjection,
        signature: String,
        in libraryURL: URL
    ) {
        let cache = MusicWorkspaceDisplayCacheFile(
            version: MusicWorkspaceDisplayCacheFile.currentVersion,
            signature: signature,
            generatedAt: Date(),
            projection: projection
        )
        try? ProjectRepository.writeJSON(
            cache,
            to: ProjectRepository.musicWorkspaceCacheURL(in: libraryURL),
            encoder: ProjectRepository.makeEncoder(
                outputFormatting: [.prettyPrinted, .sortedKeys],
                dateEncodingStrategy: .iso8601
            )
        )
    }

    private static func applyingAdaptiveArtistFilterLimit(
        to projection: MusicWorkspaceProjection
    ) -> MusicWorkspaceProjection {
        let artistValues = projection.filterValues[.artist, default: []]
        let artistCounts = projection.musicFilterCounts[.artist, default: [:]]
        let singleSongArtistCount = artistValues.filter { artistCounts[$0] == 1 }.count
        guard singleSongArtistCount > MusicWorkspaceProjectionBuilder.singleSongArtistFilterCollapseThreshold else {
            return projection
        }

        var adjustedProjection = projection
        adjustedProjection.filterValues[.artist] = artistValues.filter {
            artistCounts[$0, default: 0] > 1
        }
        return adjustedProjection
    }

    static func signature(for input: MusicWorkspaceProjectionInput) -> String {
        var digest = StableMusicWorkspaceDigest()

        digest.combine("music-workspace-cache-v\(MusicWorkspaceDisplayCacheFile.currentVersion)")

        digest.combine("videos")
        for video in input.videos.sorted(by: { $0.url.path < $1.url.path }) {
            digest.combine(video.url.path)
            digest.combine(video.name)
        }

        digest.combine("recognized")
        for path in input.musicsByVideoPath.keys.sorted() {
            digest.combine(path)
            for song in input.musicsByVideoPath[path, default: []] {
                combine(song, into: &digest)
            }
        }

        digest.combine("local-music")
        for asset in input.localMusicAssets.sorted(by: { $0.filePath < $1.filePath }) {
            digest.combine(asset.filePath)
            digest.combine(asset.title)
            digest.combine(asset.fileExtension)
            digest.combine(asset.role.rawValue)
            digest.combine(asset.tags)
            digest.combine(asset.duration)
            digest.combine(asset.fileSize)
            digest.combine(asset.createdAt)
            digest.combine(asset.modifiedAt)
            if let recognizedSong = asset.recognizedSong {
                combine(recognizedSong, into: &digest)
            } else {
                digest.combine("no-recognized-song")
            }
        }

        digest.combine("download-jobs")
        for job in input.musicDownloadJobs.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            digest.combine(job.id)
            digest.combine(job.songKey)
            digest.combine(job.type.rawValue)
            digest.combine(statusSignature(job.status))
            digest.combine(job.downloadProgress)
            digest.combine(job.filePath)
            digest.combine(job.waveformSamples?.count ?? 0)
            if let samples = job.waveformSamples {
                digest.combine(DownloadedMusicWaveformRenderCache.sampleSignature(samples))
            }
            digest.combine(job.isPreparingWaveform)
            digest.combine(job.createdAt)
        }

        digest.combine("metadata")
        for path in input.metadataByVideoPath.keys.sorted() {
            digest.combine(path)
            guard let metadata = input.metadataByVideoPath[path] else { continue }
            digest.combine(metadata.duration)
            digest.combine(metadata.frameRate)
            digest.combine(metadata.pixelWidth)
            digest.combine(metadata.pixelHeight)
            digest.combine(metadata.fileSize)
            digest.combine(metadata.createdAt)
            digest.combine(metadata.modifiedAt)
        }

        digest.combine("tags")
        digest.combine(input.allMusicTags)

        digest.combine("query")
        digest.combine(input.searchText)
        for result in input.searchResults.sorted(by: { $0.trackID < $1.trackID }) {
            digest.combine(result.trackID)
            digest.combine(result.title)
            digest.combine(result.artist)
            digest.combine(result.album)
            digest.combine(result.genre)
            digest.combine(result.artworkURL)
            digest.combine(result.appleMusicURL)
            digest.combine(result.duration)
        }

        digest.combine("filters")
        for filter in input.selectedMusicFilters.sorted(by: { $0.id < $1.id }) {
            digest.combine(filter.kind.rawValue)
            digest.combine(filter.value)
        }
        digest.combine(input.isMusicTagFilterBarPresented)
        digest.combine(input.sortOption.rawValue)
        digest.combine(input.sortDirection.rawValue)

        digest.combine("waveform-samples")
        for path in input.localMusicWaveformSamplesByPath.keys.sorted() {
            let samples = input.localMusicWaveformSamplesByPath[path, default: []]
            digest.combine(path)
            digest.combine(samples.count)
            digest.combine(DownloadedMusicWaveformRenderCache.sampleSignature(samples))
        }

        digest.combine("known-paths")
        for path in input.knownLocalResourcePaths.sorted() {
            digest.combine(path)
        }

        return digest.finalize()
    }

    private static func combine(_ song: MusicRecognitionItem, into digest: inout StableMusicWorkspaceDigest) {
        digest.combine(song.id)
        digest.combine(song.title)
        digest.combine(song.artist)
        digest.combine(song.artworkURL)
        digest.combine(song.appleMusicURL)
        digest.combine(song.detectedAt)
        digest.combine(song.duration)
        digest.combine(song.tags)
    }

    private static func statusSignature(_ status: RemoteImportJob.Status) -> String {
        switch status {
        case .idle:
            return "idle"
        case .importing:
            return "importing"
        case .transcoding:
            return "transcoding"
        case .finalizing:
            return "finalizing"
        case .paused:
            return "paused"
        case .succeeded(let filename):
            return "succeeded|\(filename)"
        case .failed(let message):
            return "failed|\(message)"
        }
    }
}

nonisolated private struct StableMusicWorkspaceDigest {
    private var value: UInt64 = 14_695_981_039_346_656_037

    mutating func combine(_ text: String?) {
        append(text ?? "<nil>")
    }

    mutating func combine(_ value: UUID) {
        append(value.uuidString)
    }

    mutating func combine(_ value: Bool) {
        append(value ? "1" : "0")
    }

    mutating func combine(_ value: Int) {
        append(String(value))
    }

    mutating func combine(_ value: Int?) {
        append(value.map(String.init) ?? "<nil>")
    }

    mutating func combine(_ value: Int64?) {
        append(value.map(String.init) ?? "<nil>")
    }

    mutating func combine(_ value: UInt64) {
        append(String(value))
    }

    mutating func combine(_ value: Double?) {
        guard let value, value.isFinite else {
            append("<nil>")
            return
        }
        append(String(format: "%.6f", value))
    }

    mutating func combine(_ value: Date?) {
        guard let value else {
            append("<nil>")
            return
        }
        append(String(format: "%.6f", value.timeIntervalSince1970))
    }

    mutating func combine(_ values: [String]) {
        append("[")
        for value in values {
            combine(value)
        }
        append("]")
    }

    mutating func finalize() -> String {
        String(value, radix: 16)
    }

    private mutating func append(_ text: String) {
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        value ^= 0xff
        value &*= 1_099_511_628_211
    }
}

nonisolated enum MusicRowMetrics {
    static let rowHeight: CGFloat = 72
    static let contentInsetX: CGFloat = 14
    static let contentInsetY: CGFloat = 10
    static let columnGap: CGFloat = 14
    static let contentHeight: CGFloat = rowHeight - contentInsetY * 2
    static let artworkSize: CGFloat = contentHeight
    static let columnSpacing: CGFloat = columnGap
    static let rowPadding: CGFloat = contentInsetY
    static let totalHorizontalPadding: CGFloat = contentInsetX * 2
    static let buttonsWidth: CGFloat = 156
    static let verticalButtonsWidth: CGFloat = 78
    static let actionButtonSize: CGFloat = 24
    static let actionButtonSpacing: CGFloat = 4
    static let actionColumnHeight: CGFloat = contentHeight
    static let sideActionWidth: CGFloat = actionButtonSize
    static let metadataWidth: CGFloat = 64
    static let waveformHeight: CGFloat = contentHeight
    static let tagSpacing: CGFloat = 4
    static let tagColumnWidth: CGFloat = 118
    static let tagColumnTopInset: CGFloat = 0
    static let tagChipCompactFontSize: CGFloat = 9.5
    static let tagChipCompactHorizontalPadding: CGFloat = 5.5
    static let tagChipCompactHeight: CGFloat = 16
    static let minimumInfoWidthCompact: CGFloat = 126
    static let minimumInfoWidthRegular: CGFloat = 150
}
