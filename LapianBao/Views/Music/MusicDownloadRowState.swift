import Foundation

nonisolated func musicDownloadTitle(type: MusicDownloadJob.DownloadType, job: MusicDownloadJob?) -> String {
    musicDownloadPercentage(job: job) ?? type.label
}

nonisolated func musicDownloadPercentage(job: MusicDownloadJob?) -> String? {
    guard let job else { return nil }
    switch job.status {
    case .importing, .transcoding:
        if let progress = job.downloadProgress, progress.isFinite {
            return "\(Int((normalizedProgressFraction(progress) * 100).rounded()))%"
        }
        return nil
    case .succeeded, .idle, .finalizing, .failed, .paused:
        return nil
    }
}

nonisolated func musicDownloadIsIndeterminate(job: MusicDownloadJob?) -> Bool {
    guard let job, LibraryStore.isActiveDownloadStatus(job.status) else { return false }
    return musicDownloadPercentage(job: job) == nil
}

/// Progress is live button state, not a reason to regroup, sort, or cache the list.
nonisolated enum MusicDownloadRowState {
    static func structuralJobs(_ jobs: [MusicDownloadJob]) -> [MusicDownloadJob] {
        jobs.map { job in
            var snapshot = job
            snapshot.downloadProgress = nil
            return snapshot
        }
    }

    static func liveJob(_ projected: MusicDownloadJob?, in jobs: [MusicDownloadJob]) -> MusicDownloadJob? {
        guard let projected else { return nil }
        return jobs.first { $0.id == projected.id } ?? projected
    }

    static func liveJob(
        for song: MusicRecognitionItem,
        type: MusicDownloadJob.DownloadType,
        projected: MusicDownloadJob?,
        in jobs: [MusicDownloadJob]
    ) -> MusicDownloadJob? {
        // A click creates a job synchronously, before the debounced list projection.
        // Resolve by song and track as well as ID, including synthetic local-file rows.
        let songKey = "\(song.title)|\(song.artist)"
        return jobs.last { $0.songKey == songKey && $0.type == type }
            ?? liveJob(projected, in: jobs)
    }

    static func displaySong(for job: MusicDownloadJob) -> MusicRecognitionItem {
        if let song = job.song { return song }
        var song = LibraryStore.musicRecognitionItem(fromSongKey: job.songKey, tags: [])
            ?? MusicRecognitionItem(title: job.songKey, artist: "", artworkURL: "", appleMusicURL: "", detectedAt: 0, tags: [])
        // Legacy jobs have no metadata snapshot. Never generate a new identity per refresh.
        song.id = job.id
        return song
    }

    static func hasUnfinishedJob(_ jobs: [MusicDownloadJob]) -> Bool {
        jobs.contains { job in
            if case .succeeded = job.status { return false }
            return true
        }
    }
}

nonisolated extension MusicWorkspaceProjectionBuilder {
    /// Empty-file groups use exactly the same ID and row as their eventual local files.
    /// They are not counted as local files until a file actually exists.
    func downloadBackedMusicGroups(
        alongside groups: [LocalMusicGroup],
        recognizedMusicIdentityKeys: Set<String>
    ) -> [LocalMusicGroup] {
        var occupiedIDs = Set(groups.map(\.id))
        let representedKeys = localMusicLibraryIdentityKeys(from: groups)
        var result = groups
        for job in input.musicDownloadJobs.sorted(by: { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt < rhs.createdAt
        }) {
            var song = MusicDownloadRowState.displaySong(for: job)
            song.artworkURL = MusicArtworkSelection.preferredURL(
                [song.artworkURL] + input.musicDownloadJobs.filter { $0.songKey == job.songKey }.compactMap { $0.song?.artworkURL }
            )
            let identity = musicSourceLookupKey(title: song.title, artist: song.artist)
            if let identity, recognizedMusicIdentityKeys.contains(identity) { continue }
            // Do not let the completion snapshot itself hide the row before the file scan arrives.
            if let identity, representedKeys.contains(identity), groups.contains(where: {
                localMusicGroupIdentityKeys($0).contains(identity)
            }) { continue }
            let titleKey = normalizedLocalMusicGroupingTitle(song.title)
            let artistKey = LibraryStore.normalizedMusicDuplicateText(song.artist)
            let id = !artistKey.isEmpty
                ? localMusicGroupKey(titleKey: titleKey, artistKey: artistKey)
                : "title|\(titleKey)"
            guard occupiedIDs.insert(id).inserted else { continue }
            result.append(LocalMusicGroup(
                id: id, title: song.title, artist: song.artist, artworkURL: song.artworkURL,
                tags: song.tags, displaySong: song, assets: [], originalAsset: nil,
                instrumentalAsset: nil, unknownAssets: []
            ))
        }
        return result
    }
}
