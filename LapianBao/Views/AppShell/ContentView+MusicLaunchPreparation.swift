//
//  ContentView+MusicLaunchPreparation.swift
//  LapianBao
//
//  Split from ContentView.swift.
//

import SwiftUI
import AppKit
import Foundation

extension ContentView {
    func musicWorkspaceLaunchPreparationID(containerWidth: CGFloat) -> String {
        let libraryPath = libraryStore.libraryURL?.standardizedFileURL.path ?? "no-library"
        let width = musicWorkspacePreparationWidthBucket(containerWidth: containerWidth)
        let scale = Int(((NSScreen.main?.backingScaleFactor ?? 2) * 100).rounded())
        return "\(libraryPath)|\(libraryStore.projectDataLoadState)|\(width)|\(scale)|\(musicWorkspaceLaunchSourceKey)"
    }

    func startMusicWorkspaceLaunchPreparation(containerWidth: CGFloat) {
        musicWorkspaceViewModel.startLaunchPreparationIfNeeded(
            libraryURL: libraryStore.libraryURL,
            contentWidth: CGFloat(musicWorkspacePreparationWidthBucket(containerWidth: containerWidth)),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            sourceKey: musicWorkspaceLaunchSourceKey,
            fallbackInput: makeLaunchMusicProjectionInput()
        )
    }

    var musicWorkspaceLaunchSourceKey: String {
        return [
            "sort:\(launchMusicSortOptionRawValue)",
            "direction:\(launchMusicSortDirectionRawValue)"
        ].joined(separator: "|")
    }

    func makeLaunchMusicProjectionInput() -> MusicWorkspaceProjectionInput? {
        guard
            libraryStore.libraryURL != nil,
            libraryStore.projectDataLoadState == .loaded
        else { return nil }
        let knownMusicPaths = libraryStore.knownLocalResourcePaths
            .union(libraryStore.localMusicAssets.map(\.filePath))
        let completionSnapshot = MusicDownloadCompletionSnapshot(
            jobs: libraryStore.musicDownloadJobs,
            knownExistingPaths: knownMusicPaths,
            checksFileSystem: false
        )
        return MusicWorkspaceProjectionInput(
            videos: libraryStore.videos,
            musicsByVideoPath: libraryStore.musicsByVideoPath,
            localMusicAssets: libraryStore.localMusicAssets,
            musicDownloadJobs: libraryStore.musicDownloadJobs,
            metadataByVideoPath: libraryStore.metadataByVideoPath,
            allMusicTags: libraryStore.allMusicTags,
            searchText: musicWorkspaceViewModel.searchText,
            searchResults: musicWorkspaceViewModel.searchResults,
            selectedMusicFilters: musicWorkspaceViewModel.selectedMusicFilters,
            isMusicTagFilterBarPresented: musicWorkspaceViewModel.isMusicTagFilterBarPresented,
            sortOption: MusicSortOption(rawValue: launchMusicSortOptionRawValue) ?? .title,
            sortDirection: VideoSortDirection(rawValue: launchMusicSortDirectionRawValue) ?? .ascending,
            musicDownloadCompletionSnapshot: completionSnapshot,
            musicDownloadLookupCaches: MusicDownloadLookupCaches(
                jobs: libraryStore.musicDownloadJobs,
                completionSnapshot: completionSnapshot
            ),
            localMusicWaveformSamplesByPath: libraryStore.localMusicWaveformSamplesByPath,
            knownLocalResourcePaths: libraryStore.knownLocalResourcePaths
        )
    }

    func musicWorkspacePreparationWidthBucket(containerWidth: CGFloat) -> Int {
        let estimatedWidth = estimatedMusicWorkspaceContentWidth(containerWidth: containerWidth)
        return max(620, Int((estimatedWidth / 80).rounded() * 80))
    }

    func estimatedMusicWorkspaceContentWidth(containerWidth: CGFloat) -> CGFloat {
        max(
            620,
            containerWidth
                - Design.railWidth
                - Design.panelSpacing
                - Design.libraryContentInset * 2
        )
    }
}
