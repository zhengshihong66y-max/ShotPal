import Foundation

/// Deterministic, offline fixtures for row identity and download-to-library transitions.
@MainActor
enum CommandLineMusicRowsCheck {
    static func input(jobs: [MusicDownloadJob], assets: [LocalMusicAsset] = []) -> MusicWorkspaceProjectionInput {
        let paths = Set(assets.map(\.filePath) + jobs.compactMap(\.filePath))
        let completion = MusicDownloadCompletionSnapshot(jobs: jobs, knownExistingPaths: paths, checksFileSystem: false)
        return MusicWorkspaceProjectionInput(
            videos: [], musicsByVideoPath: [:], localMusicAssets: assets, musicDownloadJobs: jobs,
            metadataByVideoPath: [:], allMusicTags: [], searchText: "", searchResults: [],
            selectedMusicFilters: [], isMusicTagFilterBarPresented: false, sortOption: .title,
            sortDirection: .ascending, musicDownloadCompletionSnapshot: completion,
            musicDownloadLookupCaches: MusicDownloadLookupCaches(jobs: jobs, completionSnapshot: completion),
            localMusicWaveformSamplesByPath: [:], knownLocalResourcePaths: paths
        )
    }

    static func run() -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let song = MusicRecognitionItem(title: "Fixture Song", artist: "Fixture Artist", artworkURL: "",
                                        appleMusicURL: "https://music.apple.com/fixture", detectedAt: 0,
                                        duration: 123, tags: ["Pop"])
        let original = MusicDownloadJob(songKey: "Fixture Song|Fixture Artist", type: .original,
                                        status: .importing, song: song, downloadProgress: 0.42)
        var instrumental = original
        instrumental.id = UUID()
        instrumental.type = .instrumental
        instrumental.downloadProgress = 0.19
        let starting = input(jobs: [original, instrumental])
        let projection = MusicWorkspaceProjectionBuilder(input: starting).makeProjection()
        var onlineInput = starting
        onlineInput.searchMode = .onlineCatalog
        checks["music_search_modes_have_separate_projection_and_disk_cache_keys"] = MusicWorkspaceProjectionSignature(input: onlineInput) != MusicWorkspaceProjectionSignature(input: starting)
            && MusicWorkspaceDisplayCache.signature(for: onlineInput) != MusicWorkspaceDisplayCache.signature(for: starting)
        var staleCatalogInput = starting
        staleCatalogInput.searchResults = [AppleMusicSearchResult(trackID: 99999, title: "Stale Catalog Row", artist: "Other Artist", genre: "Pop", appleMusicURL: "https://music.apple.com/fixture")]
        checks["music_local_mode_never_exposes_stale_catalog_results"] = MusicWorkspaceProjectionBuilder(input: staleCatalogInput).makeProjection().filteredSearchItems.isEmpty
        let rows = projection.filteredEntries
        checks["music_original_and_instrumental_share_one_normal_row"] = rows.count == 1
        if case .local(let row) = rows.first {
            checks["music_pending_row_preserves_artwork_tags_and_title"] = row.displayTitle == song.title
                && row.displayArtist == song.artist && row.visibleTags.contains("Pop") && row.song == song
            checks["music_pending_row_has_two_real_jobs_without_fake_file"] = Set(row.downloadJobs.map(\.id)) == [original.id, instrumental.id]
                && row.primaryFileURL == nil && row.group.primaryAsset == nil && row.fileURLs.isEmpty
        }
        checks["music_buttons_display_independent_measured_percentages"] = musicDownloadTitle(type: .original, job: original) == "42%"
            && musicDownloadTitle(type: .instrumental, job: instrumental) == "19%"

        var updated = original
        updated.downloadProgress = 0.73
        let progressed = input(jobs: [updated, instrumental])
        checks["music_progress_does_not_change_list_signature"] = MusicWorkspaceProjectionSignature(input: starting) == MusicWorkspaceProjectionSignature(input: progressed)
        checks["music_progress_does_not_rewrite_display_cache"] = MusicWorkspaceDisplayCache.signature(for: starting) == MusicWorkspaceDisplayCache.signature(for: progressed)
        checks["music_progress_is_not_a_structural_change"] = MusicDownloadRowState.structuralJobs(starting.musicDownloadJobs) == MusicDownloadRowState.structuralJobs(progressed.musicDownloadJobs)
        checks["music_cached_row_button_reads_live_progress"] = MusicDownloadRowState.liveJob(original, in: progressed.musicDownloadJobs)?.downloadProgress == 0.73
        checks["music_new_job_visible_before_first_projection"] = MusicDownloadRowState.liveJob(
            for: song, type: .original, projected: nil, in: [updated, instrumental]
        )?.downloadProgress == 0.73
        checks["music_new_job_keeps_track_types_separate"] = MusicDownloadRowState.liveJob(
            for: song, type: .instrumental, projected: nil, in: [updated, instrumental]
        )?.id == instrumental.id
        var unrelatedSong = song
        unrelatedSong.artist = "Unrelated Artist"
        checks["music_new_job_lookup_never_crosses_songs"] = MusicDownloadRowState.liveJob(
            for: unrelatedSong, type: .original, projected: nil, in: [updated]
        ) == nil
        var synthetic = original
        synthetic.id = UUID()
        synthetic.status = .succeeded("fixture.m4a")
        checks["music_new_job_overrides_synthetic_before_projection"] = MusicDownloadRowState.liveJob(
            for: song, type: .original, projected: synthetic, in: [updated]
        )?.id == updated.id
        checks["music_local_file_without_real_job_keeps_projected_playback"] = MusicDownloadRowState.liveJob(
            for: song, type: .original, projected: synthetic, in: []
        )?.id == synthetic.id
        let viewModel = MusicWorkspaceViewModel()
        viewModel.refreshProjection(signature: MusicWorkspaceProjectionSignature(input: starting)) { projection }
        let hydrationRevision = viewModel.displayCacheHydrationRevision
        viewModel.scheduleProjectionRefresh(signature: MusicWorkspaceProjectionSignature(input: progressed)) { projection }
        viewModel.scheduleProjectionRefresh(signature: MusicWorkspaceProjectionSignature(input: progressed)) { projection }
        checks["music_progress_does_not_reapply_rows_or_restart_hydration"] = viewModel.displayCacheHydrationRevision == hydrationRevision
        viewModel.cancelTasks()

        var changingSearch = starting
        changingSearch.searchText = "something unrelated"
        checks["music_normal_download_row_survives_changed_search"] = MusicWorkspaceProjectionBuilder(input: changingSearch).makeProjection().filteredEntries.map(\.id) == rows.map(\.id)

        var complete = original
        complete.status = .succeeded("fixture.m4a")
        complete.filePath = "/offline-fixture/fixture.m4a"
        complete.downloadProgress = 1
        complete.waveformSamples = [0.1, 0.4, 0.8]
        let beforeScan = MusicWorkspaceProjectionBuilder(input: input(jobs: [complete, instrumental])).makeProjection()
        checks["music_completion_keeps_row_before_scan_arrives"] = beforeScan.filteredEntries.map(\.id) == rows.map(\.id)
        let asset = LocalMusicAsset(filePath: complete.filePath!, title: song.title, fileExtension: "m4a", role: .original,
                                   tags: ["Pop"], duration: 123, fileSize: 10, modifiedAt: original.createdAt, recognizedSong: song)
        let savedInput = input(jobs: [complete, instrumental], assets: [asset])
        let saved = MusicWorkspaceProjectionBuilder(input: savedInput).makeProjection()
        var savedSearchInput = savedInput
        savedSearchInput.searchMode = .onlineCatalog
        savedSearchInput.searchText = "unrelated catalog query"
        checks["music_popover_query_does_not_filter_saved_library"] = MusicWorkspaceProjectionBuilder(input: savedSearchInput).makeProjection().filteredEntries.map(\.id) == saved.filteredEntries.map(\.id)
        checks["music_download_to_local_scan_keeps_same_row_id"] = saved.filteredEntries.map(\.id) == rows.map(\.id)
        if case .local(let row) = saved.filteredEntries.first {
            checks["music_local_scan_preserves_real_job_id_and_waveform"] = row.downloadJobs.first(where: { $0.type == .original })?.id == complete.id
                && row.downloadJobs.first(where: { $0.type == .original })?.waveformSamples == complete.waveformSamples
            checks["music_local_scan_keeps_other_track_progress"] = row.downloadJobs.first(where: { $0.type == .instrumental })?.downloadProgress == 0.19
        }
        var retry = original
        retry.status = .importing
        let retryProjection = MusicWorkspaceProjectionBuilder(input: input(jobs: [retry], assets: [asset])).makeProjection()
        if case .local(let row) = retryProjection.filteredEntries.first {
            checks["music_local_synthetic_job_cannot_hide_active_retry"] = row.downloadJobs.first?.id == retry.id && row.downloadJobs.first?.status == .importing
        }

        var searching = starting
        searching.searchMode = .onlineCatalog
        searching.searchText = "Fixture"
        searching.searchResults = [AppleMusicSearchResult(trackID: 1, title: song.title, artist: song.artist,
                                                          genre: "Pop", appleMusicURL: song.appleMusicURL)]
        let found = MusicWorkspaceProjectionBuilder(input: searching).makeProjection()
        checks["music_download_not_duplicated_in_search_section"] = found.filteredEntries.count == 1 && found.filteredSearchItems.isEmpty
        checks["music_search_projection_is_bound_to_its_query"] = found.searchQuery == "Fixture"

        searching.musicDownloadJobs = []
        searching.musicDownloadLookupCaches = MusicDownloadLookupCaches(jobs: [], completionSnapshot: .empty)
        searching.searchResults += searching.searchResults
        var sameSongOtherID = searching.searchResults[0]
        sameSongOtherID.trackID = 2
        searching.searchResults.append(sameSongOtherID)
        checks["music_duplicate_search_ids_and_songs_are_deduplicated"] = MusicWorkspaceProjectionBuilder(input: searching).makeProjection().filteredSearchItems.map(\.id) == [1]

        let firstVideo = VideoItem(url: URL(fileURLWithPath: "/offline-fixture/a/Same Name.mov"))
        let secondVideo = VideoItem(url: URL(fileURLWithPath: "/offline-fixture/b/Same Name.mov"))
        var secondSong = song
        secondSong.id = UUID()
        var tied = input(jobs: [original])
        tied.videos = [secondVideo, firstVideo]
        tied.musicsByVideoPath = [secondVideo.url.path: [secondSong], firstVideo.url.path: [song]]
        let tiedProjection = MusicWorkspaceProjectionBuilder(input: tied).makeProjection()
        tied.searchText = "unrelated catalog query"
        tied.searchMode = .onlineCatalog
        checks["music_popover_query_does_not_filter_recognized_library"] = MusicWorkspaceProjectionBuilder(input: tied).makeProjection().filteredEntries.map(\.id) == tiedProjection.filteredEntries.map(\.id)
        checks["music_recognized_duplicates_have_deterministic_source_identity"] = tiedProjection.recognizedAssets.count == 1
            && tiedProjection.recognizedAssets.first?.videoPath == firstVideo.url.path
        checks["music_recognized_download_does_not_create_second_local_row"] = tiedProjection.filteredEntries.count == 1
        var retryWithOldFile = complete
        retryWithOldFile.status = .importing
        var recognizedRetry = input(jobs: [retryWithOldFile], assets: [asset])
        recognizedRetry.videos = [firstVideo]
        recognizedRetry.musicsByVideoPath = [firstVideo.url.path: [song]]
        checks["music_retry_preserves_file_provenance_without_duplicate_row"] = MusicWorkspaceProjectionBuilder(input: recognizedRetry).makeProjection().filteredEntries.count == 1

        let noLibraryStore = LibraryStore()
        _ = noLibraryStore.prepareMusicDownloadJob(song: song, type: .original)
        _ = noLibraryStore.prepareMusicDownloadJob(song: song, type: .original)
        checks["music_repeated_download_without_library_does_not_duplicate_jobs"] = noLibraryStore.musicDownloadJobs.count == 1
            && noLibraryStore.musicDownloadJobs.first?.song == song

        var phase = original
        phase.status = .transcoding
        phase.downloadProgress = nil
        checks["music_unknown_transcode_progress_is_not_fake_percent"] = musicDownloadTitle(type: .original, job: phase) == L10n.text("原曲")
        checks["music_unknown_active_progress_shows_activity_not_fake_zero"] = musicDownloadIsIndeterminate(job: phase)
            && musicDownloadPercentage(job: phase) == nil
        for status: RemoteImportJob.Status in [.importing, .transcoding, .finalizing] {
            phase.status = status
            phase.downloadProgress = nil
            checks["music_unmeasured_\(status)_shows_activity"] = musicDownloadIsIndeterminate(job: phase)
        }
        for status: RemoteImportJob.Status in [.idle, .paused, .failed("fixture error"), .succeeded("fixture.m4a")] {
            phase.status = status
            checks["music_inactive_\(status)_has_no_spinner"] = !musicDownloadIsIndeterminate(job: phase)
        }
        checks["music_measured_progress_replaces_spinner"] = !musicDownloadIsIndeterminate(job: original)
            && musicDownloadTitle(type: .original, job: original) == "42%"
        phase.status = .transcoding
        checks["music_phase_change_refreshes_structure"] = MusicWorkspaceProjectionSignature(input: input(jobs: [phase])) != MusicWorkspaceProjectionSignature(input: input(jobs: [original]))
        phase.status = .failed("fixture service error")
        checks["music_failed_row_has_no_visible_status_but_keeps_error_detail"] = musicDownloadTitle(type: .original, job: phase) == L10n.text("原曲")
            && musicDownloadHelp(type: .original, job: phase) == "fixture service error"

        var legacy = original
        legacy.song = nil
        checks["music_legacy_job_metadata_has_stable_identity"] = MusicDownloadRowState.displaySong(for: legacy).id == MusicDownloadRowState.displaySong(for: legacy).id
        do {
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(MusicDownloadJob.self, from: encoded)
            checks["music_metadata_survives_restart_with_paused_state"] = decoded.song == song && decoded.id == original.id && decoded.status == .paused
            let oldData = try JSONEncoder().encode(legacy)
            let oldDecoded = try JSONDecoder().decode(MusicDownloadJob.self, from: oldData)
            checks["music_old_jobs_without_metadata_still_decode"] = oldDecoded.song == nil && oldDecoded.id == legacy.id
        } catch {
            checks["music_job_persistence_fixture"] = false
        }
        return checks
    }
}
