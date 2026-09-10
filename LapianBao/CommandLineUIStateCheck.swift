import AppKit
import Darwin
import Foundation

/// Offline regression fixtures. Never reads browser profiles or the user's library.
@MainActor
enum CommandLineUIStateCheck {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--lapianbao-ui-state-check") else { return }
        var checks: [String: Bool] = [:]
        _ = NSApplication.shared

        let field = SearchNSTextField(frame: NSRect(x: 20, y: 20, width: 280, height: 24))
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.isBezeled = false
        field.stringValue = "select this text"
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(field)
        checks["search_field_owns_selection_drags"] = !field.mouseDownCanMoveWindow
            && field.isEditable && field.isSelectable
        checks["search_hit_test_reaches_field"] = window.contentView?.hitTest(NSPoint(x: 30, y: 30)) === field
        checks["search_does_not_steal_initial_keyboard_focus"] = !field.acceptsFirstResponder

        let editor = ImportURLTextEditorView(frame: NSRect(x: 0, y: 60, width: 350, height: 100))
        window.contentView?.addSubview(editor)
        editor.configure(text: "https://youtu.be/test1234567", placeholder: "Links")
        _ = window.makeFirstResponder(editor.textView)
        editor.textView.setSelectedRange(NSRange(location: 8, length: 7))
        editor.configure(text: "", placeholder: "Links")
        checks["submitted_link_native_editor_cleared"] = editor.textView.string.isEmpty
            && editor.textView.selectedRange() == NSRange(location: 0, length: 0)
        editor.configure(text: "https://youtu.be/next1234567", placeholder: "Links")
        checks["editor_accepts_next_draft"] = editor.textView.string.hasSuffix("next1234567")
        window.close()

        let cookiePath = "/fixture/browser-cookies.txt"
        let retained = YouTubeCookieStore.statusDetail(phase: .failed("fixture failure"), path: cookiePath, fileAvailable: true)
        checks["failed_sync_reports_retained_file"] = retained.contains(L10n.text("上次文件已保留；本次同步失败：")) && retained.contains("fixture failure")
        let saved = YouTubeCookieStore.statusDetail(phase: .succeeded(Date()), path: cookiePath, fileAvailable: true)
        checks["saved_cookie_does_not_claim_verified_login"] = saved == L10n.text("\("browser-cookies.txt") · 文件已保存，平台登录有效性未验证")
        let missing = YouTubeCookieStore.statusDetail(phase: .succeeded(Date()), path: cookiePath, fileAvailable: false)
        checks["deleted_cookie_file_not_shown_as_ready"] = missing == L10n.text("cookies 文件不可读取，请重新同步")
        checks["cookies_are_optional"] = YouTubeCookieStore.statusDetail(phase: .idle, path: nil, fileAvailable: false) == L10n.text("未配置（可选）；公开链接可能无需 cookies")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("lapianbao-ui-state-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            let fixture = temp.appendingPathComponent("cookies.txt")
            try """
            # Netscape HTTP Cookie File
            #HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t4102444800\tvalid\tfixture
            .youtube.com\tTRUE\t/\tTRUE\t1\texpired\tfixture
            .youtube.com\tTRUE\t/\tTRUE\t0\tempty\t
            .bilibili.com\tTRUE\t/\tTRUE\t0\tsession\tfixture
            .youtube.com.evil.test\tTRUE\t/\tTRUE\t0\twrongdomain\tfixture
            """.write(to: fixture, atomically: true, encoding: .utf8)
            let filtered = YouTubeCookieStore.filteredBrowserCookieContents(at: fixture) ?? ""
            checks["cookie_filter_keeps_http_only_and_session"] = filtered.contains("#HttpOnly_") && filtered.contains("session")
            checks["cookie_filter_drops_expired_empty_and_other_domains"] = !filtered.contains("expired") && !filtered.contains("empty") && !filtered.contains("wrongdomain")
            let videoAttempts = LibraryStore.ytdlpYouTubeCookieFileArgumentAttempts(cookieFileURL: fixture)
            let audioAttempts = LibraryStore.ytdlpYouTubeCookieFileArgumentAttempts(cookieFileURL: fixture, purpose: .audio)
            defer {
                let copies = Set((videoAttempts + audioAttempts).compactMap { attempt -> String? in
                    guard let index = attempt.arguments.firstIndex(of: "--cookies"), attempt.arguments.indices.contains(index + 1) else { return nil }
                    return attempt.arguments[index + 1]
                })
                for copy in copies where copy != fixture.path { try? FileManager.default.removeItem(atPath: copy) }
            }
            checks["youtube_cookie_video_defaults_preserve_client_and_manifest_selection"] = videoAttempts.first?.arguments.count == 2
                && videoAttempts.first?.arguments.first == "--cookies"
            checks["youtube_cookie_audio_has_default_client_fallback"] = audioAttempts.contains { $0.arguments.count == 2 && $0.arguments.first == "--cookies" }
            checks["youtube_cookie_attempts_never_pass_live_cookie_file"] = (videoAttempts + audioAttempts).allSatisfy { !$0.arguments.contains(fixture.path) }
            // Run the real Swift export/commit path against a synthetic Python module.
            let module = temp.appendingPathComponent("yt_dlp", isDirectory: true)
            try FileManager.default.createDirectory(at: module, withIntermediateDirectories: true)
            let moduleFile = module.appendingPathComponent("__init__.py")
            try """
            class YoutubeDL:
                def __init__(self, params): self.params = params
                def __enter__(self): return self
                cookiejar = None
                def __exit__(self, *args):
                    with open(self.params['cookiefile'], 'w') as stream:
                        stream.write('.youtube.com\\tTRUE\\t/\\tTRUE\\t0\\tfixture\\tnew-synthetic-value\\n')
            """.write(to: moduleFile, atomically: true, encoding: .utf8)
            let savedFile = temp.appendingPathComponent("saved-cookies.txt")
            try "old fixture".write(to: savedFile, atomically: true, encoding: .utf8)
            let export = YouTubeCookieStore.runRefresh(ytdlp: temp, exportURL: savedFile)
            if case .success = export {
                checks["cookie_refresh_atomically_replaces_saved_file"] = (try String(contentsOf: savedFile, encoding: .utf8)).contains("new-synthetic-value")
            } else { checks["cookie_refresh_atomically_replaces_saved_file"] = false }
            let attrs = try FileManager.default.attributesOfItem(atPath: savedFile.path)
            checks["cookie_saved_file_is_private"] = (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600
            try "raise RuntimeError('fixture Keychain access denied')".write(to: moduleFile, atomically: true, encoding: .utf8)
            let failure = YouTubeCookieStore.runRefresh(ytdlp: temp, exportURL: savedFile)
            if case .failure(let message) = failure {
                checks["failed_cookie_refresh_preserves_saved_file"] = (try String(contentsOf: savedFile, encoding: .utf8)).contains("new-synthetic-value")
                checks["keychain_failure_has_specific_message"] = (message.contains("钥匙串") || message.contains("Keychain"))
            } else { checks["failed_cookie_refresh_preserves_saved_file"] = false }
        } catch { checks["cookie_fixture_io"] = false }

        let verification = "ERROR: [youtube] fixture: Sign in to confirm you're not a bot."
        let cookieArguments = ["--cookies", "/fixture/cookies.txt"]
        var authenticationRetry = LibraryStore.YTDLPAuthenticationRetryState()
        authenticationRetry.recordFailure(verification, arguments: [])
        checks["youtube_anonymous_rejection_keeps_other_routes"] = authenticationRetry.allows(arguments: [])
        authenticationRetry.recordFailure("HTTP Error 503", arguments: cookieArguments)
        checks["youtube_non_auth_failure_does_not_request_cookie_refresh"] = authenticationRetry.verificationFailure == nil
        authenticationRetry.recordFailure(verification, arguments: cookieArguments)
        checks["youtube_auth_failure_keeps_remaining_cookie_client"] = authenticationRetry.allows(arguments: cookieArguments + ["--extractor-args", "youtube:player_client=web_safari"])
        checks["youtube_auth_failure_keeps_configured_proxy_cookie_route"] = authenticationRetry.allows(arguments: cookieArguments + ["--proxy", "http://127.0.0.1:12345"])
        checks["youtube_auth_failure_skips_anonymous_downgrade"] = !authenticationRetry.allows(arguments: [])
        authenticationRetry.recordFailure("The page needs to be reloaded.", arguments: cookieArguments)
        checks["youtube_auth_failure_remains_available_for_bounded_refresh"] = authenticationRetry.verificationFailure == verification
        let source = URL(string: "https://www.youtube.com/watch?v=fixture")!
        let anonymousMessage = LibraryStore.userFacingYTDLPFailureMessage(verification, sourceURL: source, usedCookies: false)
        let cookieMessage = LibraryStore.userFacingYTDLPFailureMessage(verification, sourceURL: source, usedCookies: true)
        checks["youtube_error_distinguishes_actual_cookie_usage"] = anonymousMessage != cookieMessage && (anonymousMessage.contains("未携带 cookies") || anonymousMessage.contains("did not include cookies")) && (cookieMessage.contains("本次携带的 cookies") || cookieMessage.contains("cookies sent with this request"))
        checks["youtube_final_error_does_not_promise_another_retry"] = !cookieMessage.contains("会用它重试") && (cookieMessage.contains("公开链接也可能触发验证") || cookieMessage.contains("Public links may also require verification"))
        checks["youtube_corrected_error_still_triggers_existing_refresh"] = LibraryStore.isYouTubeBotVerificationFailure(cookieMessage)

        let results = [
            AppleMusicSearchResult(trackID: 3, title: "Zebra", artist: "Z Artist", genre: "Pop", appleMusicURL: "https://music.apple.com/us/album/fixture/3"),
            AppleMusicSearchResult(trackID: 1, title: "Alpha", artist: "A Artist", genre: "Pop", appleMusicURL: "https://music.apple.com/us/album/fixture/1"),
            AppleMusicSearchResult(trackID: 2, title: "Middle", artist: "M Artist", genre: "Pop", appleMusicURL: "https://music.apple.com/us/album/fixture/2")
        ]
        let active = MusicDownloadJob(songKey: "Zebra|Z Artist", type: .original, status: .importing, downloadProgress: 0.42)
        let paused = MusicDownloadJob(songKey: "Alpha|A Artist", type: .instrumental, status: .paused)
        let failed = MusicDownloadJob(songKey: "Middle|M Artist", type: .original, status: .failed("fixture failure"))
        let completed = MusicDownloadJob(songKey: "Done|Artist", type: .original, status: .succeeded("done.m4a"))
        let jobs = [active, paused, failed, completed]
        var input = MusicWorkspaceProjectionInput(
            videos: [], musicsByVideoPath: [:], localMusicAssets: [], musicDownloadJobs: [],
            metadataByVideoPath: [:], allMusicTags: [], searchText: "fixture", searchResults: results,
            selectedMusicFilters: [], isMusicTagFilterBarPresented: false, sortOption: .title,
            sortDirection: .ascending, musicDownloadCompletionSnapshot: .empty,
            musicDownloadLookupCaches: MusicDownloadLookupCaches(jobs: [], completionSnapshot: .empty),
            localMusicWaveformSamplesByPath: [:], knownLocalResourcePaths: [])
        for sort in MusicSortOption.allCases {
            input.searchMode = .onlineCatalog
            for direction in [VideoSortDirection.ascending, .descending] {
                input.sortOption = sort
                input.sortDirection = direction
                let rows = MusicWorkspaceProjectionBuilder(input: input).makeProjection().filteredSearchItems
                checks["search_relevance_\(sort.rawValue)_\(direction.rawValue)"] = rows.map(\.id) == [3, 1, 2]
            }
        }
        input.searchText = ""
        input.searchResults = []
        input.musicDownloadJobs = jobs
        input.musicDownloadLookupCaches = MusicDownloadLookupCaches(jobs: jobs, completionSnapshot: .empty)
        let cleared = MusicWorkspaceProjectionBuilder(input: input).makeProjection()
        let visible = cleared.filteredEntries.flatMap { row -> [MusicDownloadJob] in
            if case .local(let row) = row { return row.downloadJobs }
            return []
        }.filter { MusicDownloadRowState.hasUnfinishedJob([$0]) }
        checks["search_clear_retains_pending_downloads"] = cleared.filteredSearchItems.isEmpty
            && Set(visible.map(\.id)) == Set([active.id, paused.id, failed.id])
        checks["normal_music_row_retains_measured_progress"] = visible.first(where: { $0.id == active.id })?.downloadProgress == 0.42
        let tracker = LibraryStore.YTDLPProgressTracker(expectedPartCount: 1,
            allowsEstimatedMultipartProgress: false, reportsPostProcessingProgress: false)
        checks["music_progress_uses_real_bytes"] = tracker.update(from: "lapianbao-progress downloaded=42 total=100 total_estimate=NA speed=10")?.progress == 0.42
        checks["music_extraction_does_not_invent_progress"] = tracker.update(from: "[ExtractAudio] Destination: fixture.m4a")?.progress == nil

        checks.merge(CommandLineMusicRowsCheck.run(), uniquingKeysWith: { _, new in new })
        checks.merge(CommandLineMusicArtworkCheck.run(), uniquingKeysWith: { _, new in new })
        checks.merge(CommandLineMusicSearchCheck.run(), uniquingKeysWith: { _, new in new })
        checks.merge(CommandLineMusicGenreCheck.run(), uniquingKeysWith: { _, new in new })
        checks.merge(CommandLineMusicRowsRenderCheck.run(), uniquingKeysWith: { _, new in new })
        checks.merge(CommandLineMusicNoticeCheck.run(), uniquingKeysWith: { _, new in new })
        checks.merge(CommandLineTranscriptTimelineCheck.run(), uniquingKeysWith: { _, new in new })
        let passed = checks.values.allSatisfy { $0 }
        let report: [String: Any] = ["status": passed ? "succeeded" : "failed", "checks": checks,
            "limitations": ["Native in-process checks, not a real mouse-drag or M4 test", "Synthetic cookies only; browser authorization not tested"]]
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        Darwin.exit(passed ? 0 : 1)
    }
}
