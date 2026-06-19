//
//  MusicWorkspaceModels.swift
//  LapianBao
//
//  Lightweight presentation models used by MusicWorkspaceView.
//

import Foundation
import Combine
import SwiftUI

struct MusicDownloadLookupCaches {
    var jobsBySongKey: [String: [MusicDownloadJob]]
    var jobByNormalizedFilePath: [String: MusicDownloadJob]

    init(
        jobs: [MusicDownloadJob],
        completedFileURL: (MusicDownloadJob) -> URL?
    ) {
        jobsBySongKey = Dictionary(grouping: jobs, by: \.songKey)
            .mapValues(latestMusicDownloadJobs)

        var jobsByPath: [String: MusicDownloadJob] = [:]
        for job in jobs {
            guard let filePath = job.filePath,
                  completedFileURL(job) != nil
            else { continue }
            let key = LibraryStore.normalizedLocalFilePath(filePath)
            jobsByPath[key] = job
        }
        jobByNormalizedFilePath = jobsByPath
    }
}

@MainActor
final class MusicWorkspaceViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var searchResults: [AppleMusicSearchResult] = []
    @Published var isSearching = false
    @Published var searchMessage: String?
    @Published var selectedMusicFilters: Set<MusicFilterOption> = []
    @Published var isMusicTagFilterBarPresented = false
    @Published var projection = MusicWorkspaceProjection.empty

    private var workspacePreparationTask: Task<Void, Never>?
    private var workspaceMaintenanceTask: Task<Void, Never>?
    private var projectionRefreshTask: Task<Void, Never>?
    private var completedMusicDownloadLibrarySignature = Set<String>()

    var selectedMusicTagFilterCount: Int {
        selectedMusicFilters.filter {
            $0.kind == .local || $0.kind == .artist || $0.kind == .tag
        }.count
    }

    func cancelTasks() {
        workspacePreparationTask?.cancel()
        workspacePreparationTask = nil
        workspaceMaintenanceTask?.cancel()
        workspaceMaintenanceTask = nil
        projectionRefreshTask?.cancel()
        projectionRefreshTask = nil
    }

    func refreshProjection(build: () -> MusicWorkspaceProjection) {
        projection = build()
    }

    func scheduleProjectionRefresh(build: @escaping @MainActor () -> MusicWorkspaceProjection) {
        projectionRefreshTask?.cancel()
        projectionRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard let self, !Task.isCancelled else { return }
            refreshProjection(build: build)
        }
    }

    func scheduleDeferredPreparation(prepare: @escaping @MainActor () -> Void) {
        workspacePreparationTask?.cancel()
        workspacePreparationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
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

    func rememberCompletedMusicDownloadLibraryState(
        jobs: [MusicDownloadJob],
        completedFileURL: (MusicDownloadJob) -> URL?
    ) {
        completedMusicDownloadLibrarySignature = completedMusicDownloadSignature(
            jobs: jobs,
            completedFileURL: completedFileURL
        )
    }

    func completedMusicDownloadLibraryChanged(
        jobs: [MusicDownloadJob],
        completedFileURL: (MusicDownloadJob) -> URL?
    ) -> Bool {
        let nextSignature = completedMusicDownloadSignature(
            jobs: jobs,
            completedFileURL: completedFileURL
        )
        defer { completedMusicDownloadLibrarySignature = nextSignature }
        return nextSignature != completedMusicDownloadLibrarySignature
    }

    private func completedMusicDownloadSignature(
        jobs: [MusicDownloadJob],
        completedFileURL: (MusicDownloadJob) -> URL?
    ) -> Set<String> {
        var signature = Set<String>()
        for job in jobs {
            guard let fileURL = completedFileURL(job) else { continue }
            signature.insert("\(job.id.uuidString)|\(fileURL.path)")
        }
        return signature
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

struct RecognizedMusicAsset: Identifiable {
    var videoPath: String
    var videoName: String
    var song: MusicRecognitionItem

    var id: String { "\(videoPath)-\(song.id.uuidString)" }
}

struct LocalMusicGroup: Identifiable {
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

enum MusicLibraryEntry: Identifiable {
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

struct MusicLibraryEntrySortCandidate {
    var entry: MusicLibraryEntry
    var snapshot: MusicSortSnapshot
}

struct MusicSortSnapshot {
    var title: String
    var artist: String
    var addedAt: Date?
    var id: String
}

struct LocalMusicAssetProjection {
    var asset: LocalMusicAsset
    var song: MusicRecognitionItem?
    var title: String
    var artist: String
    var titleKey: String
    var artistKey: String
    var role: LocalMusicAsset.Role
    var tags: [String]
}

struct LocalMusicRoleAsset: Identifiable {
    var role: LocalMusicAsset.Role
    var asset: LocalMusicAsset

    var id: String { "\(role.rawValue)|\(asset.filePath)" }
}

struct MusicArtistFilterValue {
    var displayName: String
    var songCount: Int
}

struct AppleMusicSearchResultRowProjection: Identifiable {
    var item: AppleMusicSearchResult
    var song: MusicRecognitionItem
    var visibleTags: [String]
    var downloadJobs: [MusicDownloadJob]
    var hasDownloadedWaveform: Bool

    var id: Int { item.id }
}

struct RecognizedMusicRowProjection: Identifiable {
    var asset: RecognizedMusicAsset
    var visibleTags: [String]
    var suggestedTags: [String]
    var downloadJobs: [MusicDownloadJob]
    var hasDownloadedWaveform: Bool
    var downloadedFileURLs: [URL]

    var id: String { asset.id }
}

struct LocalMusicGroupRowProjection: Identifiable {
    var group: LocalMusicGroup
    var roleAssets: [LocalMusicRoleAsset]
    var downloadJobs: [MusicDownloadJob]
    var displayTitle: String
    var displayArtist: String
    var visibleTags: [String]
    var suggestedTags: [String]
    var primaryFileURL: URL?
    var fileURLs: [URL]
    var sourceText: String?
    var song: MusicRecognitionItem
    var duration: Double

    var id: String { group.id }
}

enum MusicLibraryRowProjection: Identifiable {
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

struct MusicWorkspaceProjection {
    var recognizedAssets: [RecognizedMusicAsset] = []
    var displayedLocalMusicGroups: [LocalMusicGroup] = []
    var filteredEntries: [MusicLibraryRowProjection] = []
    var filteredSearchItems: [AppleMusicSearchResultRowProjection] = []
    var filterValues: [MusicFilterKind: [String]] = [:]
    var musicFilterCounts: [MusicFilterKind: [String: Int]] = [:]

    static let empty = MusicWorkspaceProjection()
}

enum MusicRowMetrics {
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
    static let minimumInfoWidthCompact: CGFloat = 126
    static let minimumInfoWidthRegular: CGFloat = 150
}
