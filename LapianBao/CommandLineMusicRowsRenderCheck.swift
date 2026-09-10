import AppKit
import SwiftUI

/// Render the real workspace against an in-memory library, without network or user media.
@MainActor
enum CommandLineMusicRowsRenderCheck {
    static func run() -> [String: Bool] {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--music-rows-preview-directory"), arguments.count > index + 1 else { return [:] }
        var checks: [String: Bool] = [:]
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        let coverURL = URL(string: "https://covers.invalid/music-row-fixture.png")!
        let cover = NSImage(size: NSSize(width: 240, height: 120))
        cover.lockFocus()
        NSColor.systemIndigo.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 240, height: 120)).fill()
        NSColor.systemTeal.setFill()
        NSBezierPath(ovalIn: NSRect(x: 72, y: 12, width: 96, height: 96)).fill()
        cover.unlockFocus()
        MusicArtworkCache.shared.setObject(cover, forKey: coverURL as NSURL)
        defer { MusicArtworkCache.shared.removeObject(forKey: coverURL as NSURL) }
        let song = MusicRecognitionItem(title: "New Music · 新加入的音乐", artist: "Fixture Artist",
                                        artworkURL: coverURL.absoluteString, appleMusicURL: "", detectedAt: 0,
                                        duration: 180, tags: ["Pop", "Rock", "Electronic"])
        let original = MusicDownloadJob(songKey: "\(song.title)|\(song.artist)", type: .original,
                                        status: .importing, song: song, downloadProgress: 0.42)
        let instrumental = MusicDownloadJob(songKey: original.songKey, type: .instrumental,
                                            status: .importing, song: song, downloadProgress: 0.19)
        var pausedSong = song
        pausedSong.title = "Night Drive · 夜行"
        let paused = MusicDownloadJob(songKey: "\(pausedSong.title)|\(pausedSong.artist)", type: .original,
                                      status: .paused, song: pausedSong)
        var failedSong = song
        failedSong.title = "Winter Light · 冬日"
        failedSong.artworkURL = ""
        let failed = MusicDownloadJob(songKey: "\(failedSong.title)|\(failedSong.artist)", type: .original,
                                      status: .failed("Synthetic service failure"), song: failedSong)
        let jobs = [original, instrumental, paused, failed]
        let store = LibraryStore()
        store.musicDownloadJobs = jobs
        let viewModel = MusicWorkspaceViewModel(searchMode: .onlineCatalog)
        viewModel.isMusicTagFilterBarPresented = false
        viewModel.allowsHeavyRowMedia = true
        var input = CommandLineMusicRowsCheck.input(jobs: jobs)
        input.searchMode = .onlineCatalog
        // Match the view's preferences without overwriting the user's chosen sort order.
        @AppStorage(AppSettings.Key.musicSortOption) var sortRawValue = MusicSortOption.title.rawValue
        @AppStorage(AppSettings.Key.musicSortDirection) var directionRawValue = VideoSortDirection.ascending.rawValue
        input.sortOption = MusicSortOption(rawValue: sortRawValue) ?? .title
        input.sortDirection = VideoSortDirection(rawValue: directionRawValue) ?? .ascending
        viewModel.refreshProjection(signature: MusicWorkspaceProjectionSignature(input: input)) {
            MusicWorkspaceProjectionBuilder(input: input).makeProjection()
        }
        var receivedQueries: [String] = []
        var host = NSHostingView(rootView: MusicWorkspaceView(viewModel: viewModel, toolbarWidth: nil, goHome: { _, _ in }, searchAppleMusic: { query in
            receivedQueries.append(query)
            try await Task.sleep(nanoseconds: 200_000_000)
            if query == "No Fixture Results" { return [] }
            if query == "Failed Fixture" { throw URLError(.timedOut) }
            return [AppleMusicSearchResult(trackID: 991, title: "Search Fixture Song", artist: "Search Artist",
                                            genre: "国际流行", artworkURL: coverURL.absoluteString,
                                            appleMusicURL: "https://music.apple.com/cn/album/fixture/991"),
                    AppleMusicSearchResult(trackID: 992, title: "Electronic Fixture Song", artist: "Another Artist",
                                            genre: "电子音乐", artworkURL: coverURL.absoluteString,
                                            appleMusicURL: "https://music.apple.com/cn/album/fixture/992")]
        })
            .environmentObject(store)
            .environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1060, height: 520),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer {
            viewModel.cancelTasks()
            window.close()
        }
        func settle(_ seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
        }
        func snapshot(_ name: String, view: NSView? = nil) throws -> NSBitmapImageRep {
            let target = view ?? host
            target.layoutSubtreeIfNeeded()
            guard let bitmap = target.bitmapImageRepForCachingDisplay(in: target.bounds) else {
                throw NSError(domain: "MusicRowRender", code: 1)
            }
            target.cacheDisplay(in: target.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "MusicRowRender", code: 2)
            }
            try data.write(to: directory.appendingPathComponent(name + ".png"))
            return bitmap
        }
        func searchField(in view: NSView) -> SearchNSTextField? {
            if let field = view as? SearchNSTextField { return field }
            return view.subviews.lazy.compactMap { searchField(in: $0) }.first
        }
        func typeQuery(_ query: String) -> Bool {
            guard let field = searchField(in: host) else { return false }
            field.stringValue = query
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            return true
        }
        var searchCoordinator: ClickActivatedSearchTextField.Coordinator? {
            searchField(in: host)?.delegate as? ClickActivatedSearchTextField.Coordinator
        }
        func snapshotPopover(_ name: String) throws {
            guard let popover = searchCoordinator?.popover, popover.isShown,
                  let content = popover.contentViewController?.view else {
                throw NSError(domain: "MusicSearchPopover", code: 1)
            }
            _ = try snapshot(name, view: content)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            settle(0.65)
            viewModel.cancelTasks() // Exclude one-time startup preparation from the progress stress test.
            let before = try snapshot("music-rows-42-percent")
            let rowIDs = viewModel.projection.filteredEntries.map(\.id)
            let revision = viewModel.displayCacheHydrationRevision
            for step in 43...73 {
                store.musicDownloadJobs[0].downloadProgress = Double(step) / 100
                settle(0.01)
            }
            let after = try snapshot("music-rows-73-percent")
            checks["music_render_progress_keeps_row_ids"] = rowIDs == viewModel.projection.filteredEntries.map(\.id)
            checks["music_render_31_progress_ticks_do_not_rebuild_list"] = revision == viewModel.displayCacheHydrationRevision
            var changed = 0
            var compared = 0
            for y in stride(from: 0, to: min(before.pixelsHigh, after.pixelsHigh), by: 2) {
                for x in stride(from: 0, to: min(before.pixelsWide, after.pixelsWide), by: 2) {
                    guard let lhs = before.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          let rhs = after.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    compared += 1
                    if abs(lhs.redComponent - rhs.redComponent) + abs(lhs.greenComponent - rhs.greenComponent)
                        + abs(lhs.blueComponent - rhs.blueComponent) > 0.08 { changed += 1 }
                }
            }
            checks["music_render_progress_changes_pixels_without_whole_list_flicker"] = changed > 0 && Double(changed) / Double(max(1, compared)) < 0.02
            window.setContentSize(NSSize(width: 620, height: 520))
            settle(0.15)
            _ = try snapshot("music-rows-compact")
            checks["music_render_compact_normal_rows"] = host.bounds.width == 620 && rowIDs.count == 3
            checks["music_popover_initially_closed"] = searchCoordinator?.popover.isShown == false
            if let field = searchField(in: host) {
                checks["music_popover_uses_local_editor_for_repeated_clicks"] = field.cell?.fieldEditor(for: field) === field.popoverFieldEditor
                    && !field.popoverFieldEditor.mouseDownCanMoveWindow
            }
            searchField(in: host)?.onActivate?()
            settle(0.1)
            checks["music_popover_click_opens_empty_prompt"] = searchCoordinator?.popover.isShown == true
            try snapshotPopover("music-search-prompt")
            checks["music_search_native_field_updates_binding"] = typeQuery("Search Fixture") && viewModel.searchText == "Search Fixture"
            settle(0.08)
            checks["music_search_native_field_shows_loading"] = viewModel.isShowingSearchProgress
            try snapshotPopover("music-search-loading")
            settle(0.9)
            checks["music_search_native_field_reaches_service"] = receivedQueries == ["Search Fixture"]
            checks["music_search_native_results_reach_display_projection"] = !viewModel.isShowingSearchProgress
                && viewModel.projection.filteredSearchItems.map(\.id) == [991, 992]
                && viewModel.projection.searchQuery == "Search Fixture"
            checks["music_search_native_rows_show_distinct_catalog_genres"] = viewModel.projection.filteredSearchItems.map(\.visibleTags) == [["Pop"], ["Electronic"]]
            checks["music_search_results_keep_download_rows"] = rowIDs == viewModel.projection.filteredEntries.map(\.id)
            try snapshotPopover("music-search-results")
            checks["music_popover_has_bounded_independent_result_layout"] = searchCoordinator?.popover.contentSize.width == 592
                && (searchCoordinator?.popover.contentSize.height ?? 0) <= 420
            _ = try snapshot("music-library-during-search")
            searchCoordinator?.popover.performClose(nil)
            settle(0.1)
            checks["music_popover_dismiss_keeps_query_and_downloads"] = searchCoordinator?.popover.isShown == false
                && viewModel.searchText == "Search Fixture" && rowIDs == viewModel.projection.filteredEntries.map(\.id)
            searchField(in: host)?.popoverFieldEditor.onActivate?()
            settle(0.1)
            checks["music_popover_reopens_without_repeating_search"] = searchCoordinator?.popover.isShown == true && receivedQueries == ["Search Fixture"]
            _ = typeQuery("No Fixture Results")
            settle(0.9)
            checks["music_search_native_empty_result_finishes_loading"] = !viewModel.isShowingSearchProgress && viewModel.searchMessage == L10n.text("没有搜索结果")
            try snapshotPopover("music-search-empty")
            _ = typeQuery("Failed Fixture")
            settle(0.9)
            checks["music_search_native_failure_finishes_loading"] = !viewModel.isShowingSearchProgress && viewModel.searchMessage == L10n.text("搜索失败")
            try snapshotPopover("music-search-failure")
            _ = typeQuery("")
            settle(0.25)
            checks["music_search_native_clear_restores_library"] = !viewModel.isShowingSearchProgress && viewModel.searchResults.isEmpty
                && rowIDs == viewModel.projection.filteredEntries.map(\.id)
            checks["music_popover_clear_keeps_prompt_open"] = searchCoordinator?.popover.isShown == true
            searchCoordinator?.popover.close()

            // Exercise the shipping local-only mode through the same native editor and view.
            let localStore = LibraryStore()
            let localModel = MusicWorkspaceViewModel()
            localModel.isMusicTagFilterBarPresented = false
            defer { localModel.cancelTasks() }
            localStore.localMusicAssets = [("Moonlight", "Local Artist", "Pop"), ("晨光", "Another Artist", "Electronic")].map { title, artist, genre in
                LocalMusicAsset(filePath: "/offline-fixture/\(title).m4a", title: title, fileExtension: "m4a", role: .original,
                                tags: [genre], duration: 120, fileSize: 10, modifiedAt: Date(timeIntervalSince1970: 0),
                                recognizedSong: MusicRecognitionItem(title: title, artist: artist, artworkURL: coverURL.absoluteString,
                                                                    appleMusicURL: "", detectedAt: 0, duration: 120, tags: [genre]))
            }
            localStore.knownLocalResourcePaths = Set(localStore.localMusicAssets.map(\.filePath))
            var localRequests = 0
            window.contentView = nil
            host = NSHostingView(rootView: MusicWorkspaceView(viewModel: localModel, toolbarWidth: nil, goHome: { _, _ in }, searchAppleMusic: { _ in
                localRequests += 1
                return []
            }).environmentObject(localStore).environment(\.colorScheme, .dark))
            window.contentView = host
            settle(0.7)
            let localIDs = localModel.projection.filteredEntries.map(\.id)
            checks["music_local_native_fixture_has_saved_rows"] = localIDs.count == 2
            checks["music_local_native_field_has_no_catalog_editor"] = !(searchField(in: host)?.cell is SearchPopoverTextFieldCell)
            searchField(in: host)?.onActivate?()
            checks["music_local_click_does_not_open_online_popover"] = searchCoordinator?.popover.isShown == false
            for (query, title) in [("  moonLIGHT  ", "Moonlight"), ("Local Artist", "Moonlight"), ("electronic", "晨光"), ("晨光", "晨光")] {
                _ = typeQuery(query)
                settle(0.4)
                let titles = localModel.projection.filteredEntries.compactMap { entry -> String? in
                    if case .local(let row) = entry { return row.displayTitle }
                    return nil
                }
                checks["music_local_native_query_\(query)_filters_library"] = titles == [title]
            }
            _ = try snapshot("music-local-search")
            _ = typeQuery("no saved match")
            settle(0.4)
            checks["music_local_no_match_does_not_become_online_search"] = localModel.projection.filteredEntries.isEmpty && localRequests == 0
                && !localModel.isShowingSearchProgress && localModel.searchMessage == nil
            localStore.musicDownloadJobs = [paused]
            settle(0.4)
            checks["music_local_unmatched_download_task_remains_available"] = localStore.musicDownloadJobs.count == 1 && localModel.projection.filteredEntries.count == 1
            _ = typeQuery("")
            settle(0.4)
            checks["music_local_clear_restores_saved_rows_and_keeps_download"] = Set(localIDs).isSubset(of: Set(localModel.projection.filteredEntries.map(\.id)))
                && localModel.projection.filteredEntries.count == 3
            checks["music_local_native_typing_makes_zero_online_requests"] = localRequests == 0 && searchCoordinator?.popover.isShown == false
            _ = try snapshot("music-local-cleared")

            // Freeze the projected jobs at []: button feedback must not wait for a list refresh.
            let feedbackStore = LibraryStore()
            feedbackStore.libraryURL = directory
            let controlsHost = NSHostingView(rootView: MusicDownloadControlsAndWaveform(
                song: song, downloadJobs: [], buttonsWidth: 96, buttonLayout: .vertical,
                waveformWidth: 0, waveformHeight: 56
            ).padding(20).background(Design.sidebarBg)
                .environmentObject(feedbackStore).environment(\.colorScheme, .dark))
            window.contentView = controlsHost
            window.setContentSize(NSSize(width: 180, height: 110))
            func spinnerCount(_ view: NSView) -> Int {
                (view is NSProgressIndicator ? 1 : 0) + view.subviews.reduce(0) { $0 + spinnerCount($1) }
            }
            settle(0.1)
            checks["music_native_idle_button_has_no_spinner"] = spinnerCount(controlsHost) == 0
            let preparedID = feedbackStore.prepareMusicDownloadJob(song: song, type: .original)
            checks["music_click_prepares_active_job_synchronously"] = preparedID != nil
                && feedbackStore.musicDownloadJobs.first?.status == .importing
                && feedbackStore.musicDownloadJobs.first?.downloadProgress == nil
            settle(0.05)
            _ = try snapshot("music-button-immediate-activity", view: controlsHost)
            checks["music_native_new_job_shows_spinner_with_empty_projection"] = spinnerCount(controlsHost) == 1
            checks["music_click_while_preparing_does_not_duplicate_task"] = feedbackStore.prepareMusicDownloadJob(song: song, type: .original) == nil
                && feedbackStore.musicDownloadJobs.count == 1
            if let preparedID {
                feedbackStore.updateMusicDownloadJob(id: preparedID) { $0.downloadProgress = 0.07 }
                settle(0.05)
                _ = try snapshot("music-button-first-measurement", view: controlsHost)
                checks["music_native_first_measurement_replaces_spinner_without_projection"] = spinnerCount(controlsHost) == 0
                feedbackStore.updateMusicDownloadJob(id: preparedID) { $0.downloadProgress = nil; $0.status = .transcoding }
                settle(0.05)
                checks["music_native_unmeasured_extraction_restores_spinner"] = spinnerCount(controlsHost) == 1
                feedbackStore.updateMusicDownloadJob(id: preparedID) { $0.status = .failed("Synthetic failure") }
                settle(0.05)
                checks["music_native_failure_stops_spinner"] = spinnerCount(controlsHost) == 0
            }

            // Deliberately use a long interval to distinguish immediate delivery from throttled ticks.
            var deliveries: [(Double?, String?)] = []
            let coalescer = DownloadProgressCoalescer(interval: 0.4) { progress, phase in
                deliveries.append((progress, phase))
            }
            coalescer.submit(nil, nil)
            settle(0.04)
            checks["download_initial_feedback_bypasses_throttle"] = deliveries.count == 1 && deliveries[0].0 == nil
            coalescer.submit(nil, nil) // A pending unknown update cannot delay the first bytes.
            coalescer.submit(0.07, nil)
            settle(0.04)
            checks["download_first_measured_progress_bypasses_pending_throttle"] = deliveries.count == 2 && deliveries.last?.0 == 0.07
            for step in 8...40 { coalescer.submit(Double(step) / 100, nil) }
            settle(0.08)
            checks["download_following_measurements_still_coalesce"] = deliveries.count == 2
            settle(0.4)
            checks["download_coalesced_delivery_keeps_latest_real_measurement"] = deliveries.count == 3 && deliveries.last?.0 == 0.4
            coalescer.submit(0.5, nil)
            coalescer.submit(nil, "transcoding")
            settle(0.04)
            checks["download_unknown_phase_immediately_clears_old_percentage"] = deliveries.count == 4
                && deliveries.last?.0 == nil && deliveries.last?.1 == "transcoding"
            coalescer.submit(1, "transcoding")
            settle(0.04)
            checks["download_completion_bypasses_throttle"] = deliveries.count == 5 && deliveries.last?.0 == 1
            settle(0.45)
            checks["download_superseded_timers_do_not_redeliver"] = deliveries.count == 5
        } catch {
            checks["music_row_render_fixture_io"] = false
        }
        return checks
    }
}
