import AppKit
import Foundation

@MainActor
enum CommandLineMusicArtworkCheck {
    static func run() -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let coverA = "https://covers.invalid/a.png"
        let coverB = "https://covers.invalid/b.png"
        let request = MusicArtworkRequest(urlString: coverA, title: "Song", artist: "Artist", shouldLoad: true, allowsFallbackLookup: false)
        let refreshed = MusicArtworkRequest(urlString: coverB, title: "Song", artist: "Artist", shouldLoad: true, allowsFallbackLookup: false)
        let otherSong = MusicArtworkRequest(urlString: coverB, title: "Other Song", artist: "Artist", shouldLoad: true, allowsFallbackLookup: false)
        let paused = MusicArtworkRequest(urlString: coverB, title: "Song", artist: "Artist", shouldLoad: false, allowsFallbackLookup: false)
        let imageA = NSImage(size: NSSize(width: 4, height: 4))
        let imageB = NSImage(size: NSSize(width: 8, height: 8))
        var state = MusicArtworkDisplayState()
        let first = state.begin(request)
        state.accept(imageA, for: request, generation: first)
        let second = state.begin(refreshed)
        checks["music_cover_same_song_refresh_keeps_valid_image"] = state.visibleImage(for: refreshed) === imageA
        checks["music_cover_old_response_cannot_replace_refreshed_image"] = !state.accept(imageB, for: request, generation: first)
        state.accept(imageB, for: refreshed, generation: second)
        checks["music_cover_new_song_never_shows_previous_song_image"] = state.visibleImage(for: otherSong) == nil
        _ = state.begin(paused)
        checks["music_cover_paused_loading_keeps_valid_image"] = state.visibleImage(for: paused) === imageB
        _ = state.begin(otherSong)
        checks["music_cover_switch_clears_only_other_song_image"] = state.visibleImage(for: otherSong) == nil
        _ = state.begin(request)
        checks["music_cover_a_b_a_switch_rejects_first_a_response"] = !state.accept(imageA, for: request, generation: first)

        for (index, invalid) in ["", "relative.jpg", "file:///private/fixture.jpg", "data:image/png;base64,fixture", "https://", "https://user:password@covers.invalid/a.png"].enumerated() {
            checks["music_cover_rejects_invalid_url_\(index)"] = normalizedMusicArtworkURL(invalid) == nil
        }
        checks["music_cover_apple_size_normalization_preserves_query"] = normalizedMusicArtworkURL(" //is1-ssl.mzstatic.com/image/100x100bb.jpg?token=fixture ")?.absoluteString
            == "https://is1-ssl.mzstatic.com/image/512x512bb.jpg?token=fixture"
        checks["music_cover_does_not_rewrite_other_cdn_paths"] = normalizedMusicArtworkURL("https://covers.invalid/100x100bb.jpg")?.path == "/100x100bb.jpg"
        checks["music_cover_skips_invalid_nonempty_metadata"] = MusicArtworkSelection.preferredURL(["not-a-url", coverA, coverB]) == coverA
        let unrelated = AppleMusicSearchResult(trackID: 1, title: "Different", artist: "Different", genre: "Pop", artworkURL: coverA)
        let match = AppleMusicSearchResult(trackID: 2, title: "Song", artist: "Artist", genre: "Pop", artworkURL: coverB)
        checks["music_cover_rejects_unrelated_search_artwork"] = MusicArtworkSelection.fallbackURL(in: [unrelated], title: "Song", artist: "Artist") == nil
        checks["music_cover_fallback_requires_song_and_artist_match"] = MusicArtworkSelection.fallbackURL(in: [unrelated, match], title: "song", artist: "artist")?.absoluteString == coverB
            && MusicArtworkSelection.fallbackURL(in: [match], title: "Song", artist: "Another Artist") == nil
        checks["music_cover_decoder_rejects_corrupt_data"] = MusicArtworkCache.decodedImage(data: Data([1, 2, 3])) == nil
        checks["music_cover_decoder_downsamples_large_images"] = false
        checks["music_cover_cache_cost_uses_decoded_pixels"] = false
        if let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2048, pixelsHigh: 1024,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                          isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
           let data = bitmap.representation(using: .png, properties: [:]),
           let decoded = MusicArtworkCache.decodedImage(data: data) {
            checks["music_cover_decoder_downsamples_large_images"] = decoded.size == NSSize(width: 1024, height: 512)
            checks["music_cover_cache_cost_uses_decoded_pixels"] = MusicArtworkCache.decodedCost(decoded) == 1024 * 512 * 4
        }

        var song = MusicRecognitionItem(title: "Song", artist: "Artist", artworkURL: coverA, appleMusicURL: "", detectedAt: 0, tags: ["Pop"])
        let job = MusicDownloadJob(songKey: "Song|Artist", type: .original, status: .succeeded("song.m4a"), song: song, filePath: "/offline-fixture/song.m4a")
        song.artworkURL = ""
        let local = LocalMusicAsset(filePath: job.filePath!, title: "Song", fileExtension: "m4a", role: .original,
                                    tags: ["Pop"], duration: 1, fileSize: 1, modifiedAt: job.createdAt, recognizedSong: song)
        let projection = MusicWorkspaceProjectionBuilder(input: CommandLineMusicRowsCheck.input(jobs: [job], assets: [local])).makeProjection()
        checks["music_cover_survives_scan_with_incomplete_local_metadata"] = false
        if case .local(let row) = projection.filteredEntries.first {
            checks["music_cover_survives_scan_with_incomplete_local_metadata"] = row.group.artworkURL == coverA && row.song.artworkURL == coverA
        }
        var olderJob = job
        olderJob.song = song
        olderJob.status = .importing
        olderJob.filePath = nil
        olderJob.id = UUID()
        olderJob.createdAt = job.createdAt.addingTimeInterval(-10)
        let pending = MusicWorkspaceProjectionBuilder(input: CommandLineMusicRowsCheck.input(jobs: [olderJob, job])).makeProjection()
        checks["music_cover_pending_row_uses_valid_cover_from_same_song_job"] = false
        if case .local(let row) = pending.filteredEntries.first {
            checks["music_cover_pending_row_uses_valid_cover_from_same_song_job"] = row.group.artworkURL == coverA
        }
        for status: RemoteImportJob.Status in [.idle, .importing, .transcoding, .finalizing, .paused, .failed("fixture error"), .succeeded("song.m4a")] {
            var entry = job
            entry.status = status
            entry.downloadProgress = nil
            checks["music_button_no_status_text_\(String(describing: status))"] = musicDownloadTitle(type: .original, job: entry) == L10n.text("原曲")
        }
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            var entry = olderJob
            entry.downloadProgress = value
            checks["music_button_invalid_progress_\(value)_is_not_percentage"] = musicDownloadPercentage(job: entry) == nil
        }

        let doneCounter = ArtworkFetchFixture()
        let errorCounter = ArtworkFetchFixture(failures: 1)
        let retryCounter = ArtworkFetchFixture(failures: 1)
        var finished = false
        let task = Task { @MainActor in
            let url = URL(string: coverA)!
            let loader = MusicArtworkLoader { try await doneCounter.fetch($0) }
            async let a = loader.data(for: url)
            async let b = loader.data(for: url)
            let responses = await [a, b]
            let count = await doneCounter.count
            checks["music_cover_concurrent_rows_share_one_request"] = count == 1 && responses.allSatisfy { $0 == Data([1, 2, 3]) }
            let failed = MusicArtworkLoader { try await errorCounter.fetch($0) }
            _ = await failed.data(for: url)
            _ = await failed.data(for: url)
            checks["music_cover_failed_request_has_retry_cooldown"] = await errorCounter.count == 1
            let retry = MusicArtworkLoader(retryDelay: 0) { try await retryCounter.fetch($0) }
            _ = await retry.data(for: url)
            let recovered = await retry.data(for: url)
            let retryCount = await retryCounter.count
            checks["music_cover_transient_failure_can_retry"] = recovered != nil && retryCount == 2
            finished = true
        }
        let deadline = Date().addingTimeInterval(5)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        checks["music_cover_async_fixtures_finished"] = finished
        task.cancel()
        return checks
    }
}

private actor ArtworkFetchFixture {
    var count = 0
    var failures: Int
    init(failures: Int = 0) { self.failures = failures }
    func fetch(_ url: URL) async throws -> Data {
        count += 1
        try await Task.sleep(nanoseconds: 20_000_000)
        if failures > 0 { failures -= 1; throw URLError(.timedOut) }
        return Data([1, 2, 3])
    }
}
