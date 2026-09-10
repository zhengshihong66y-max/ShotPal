import Foundation

@MainActor
enum CommandLineMusicSearchCheck {
    static func run() -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let model = MusicWorkspaceViewModel(searchMode: .onlineCatalog)
        let fixture = MusicSearchFixture()
        let old = AppleMusicSearchResult(trackID: 801, title: "Old", artist: "Artist", genre: "Pop")
        let new = AppleMusicSearchResult(trackID: 802, title: "New", artist: "Artist", genre: "Pop")
        func wait(_ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(3)
            while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            return condition()
        }
        let localModel = MusicWorkspaceViewModel()
        localModel.searchText = "a local song"
        localModel.searchResults = [old]
        localModel.searchMessage = "stale network error"
        localModel.isSearching = true
        var localFinished = false
        var preparedNetwork = false
        var sentNetwork = false
        let localTask = Task { @MainActor in
            await localModel.runAppleMusicSearch(prepareExternalServiceWork: { preparedNetwork = true },
                                                 search: { _ in sentNetwork = true; return [new] },
                                                 debounceNanoseconds: 0)
            localFinished = true
        }
        checks["music_local_search_is_default_and_never_shows_network_loading"] = localModel.searchMode == .library && !localModel.isShowingSearchProgress
        _ = wait { localFinished }
        checks["music_local_search_does_not_prepare_or_call_online_service"] = localFinished && !preparedNetwork && !sentNetwork
        checks["music_local_search_discards_stale_online_feedback"] = localModel.searchResults.isEmpty && localModel.searchMessage == nil && !localModel.isSearching
        localTask.cancel()
        var completed = Set<Int>()
        func start(_ slot: Int, query: String) -> Task<Void, Never> {
            model.searchText = query
            return Task { @MainActor in
                await model.runAppleMusicSearch(prepareExternalServiceWork: {}, search: { _ in
                    try await fixture.search(slot)
                }, debounceNanoseconds: 0)
                completed.insert(slot)
            }
        }
        let first = start(1, query: "old")
        checks["music_search_first_request_started"] = wait { fixture.pending[1] != nil }
        checks["music_search_loading_is_visible_before_results"] = model.isShowingSearchProgress
        let second = start(2, query: "new")
        checks["music_search_second_request_started"] = wait { fixture.pending[2] != nil }
        first.cancel()
        fixture.finish(1, with: .success([old]))
        _ = wait { completed.contains(1) }
        checks["music_search_old_cancellation_keeps_new_loading"] = model.isSearching && model.searchResults.isEmpty
        fixture.finish(2, with: .success([new]))
        _ = wait { completed.contains(2) }
        checks["music_search_new_query_owns_results"] = model.searchResults.map(\.id) == [802] && model.searchResultsQuery == "new"
        checks["music_search_waits_for_matching_projection"] = model.isShowingSearchProgress
        model.projection.searchQuery = "new"
        checks["music_search_completed_query_exposes_results"] = !model.isShowingSearchProgress

        let sameOld = start(3, query: "same")
        _ = wait { fixture.pending[3] != nil }
        let sameNew = start(4, query: "same")
        _ = wait { fixture.pending[4] != nil }
        fixture.finish(4, with: .success([new]))
        _ = wait { completed.contains(4) }
        fixture.finish(3, with: .success([old]))
        _ = wait { completed.contains(3) }
        checks["music_search_same_query_late_response_is_rejected"] = model.searchResults.map(\.id) == [802]

        let beforeClear = start(5, query: "clear me")
        _ = wait { fixture.pending[5] != nil }
        model.searchText = ""
        var clearFinished = false
        let clear = Task { @MainActor in
            await model.runAppleMusicSearch(prepareExternalServiceWork: {}, search: { _ in [old] }, debounceNanoseconds: 0)
            clearFinished = true
        }
        _ = wait { clearFinished }
        fixture.finish(5, with: .success([old]))
        _ = wait { completed.contains(5) }
        checks["music_search_clear_cannot_be_undone_by_late_response"] = model.searchResults.isEmpty
            && model.searchResultsQuery.isEmpty && !model.isShowingSearchProgress && !model.isSearching

        let empty = start(6, query: "nothing")
        _ = wait { fixture.pending[6] != nil }
        fixture.finish(6, with: .success([]))
        _ = wait { completed.contains(6) }
        model.projection.searchQuery = "nothing"
        checks["music_search_empty_response_has_visible_message"] = model.searchMessage == L10n.text("没有搜索结果") && !model.isShowingSearchProgress
        let failure = start(7, query: "network failure")
        _ = wait { fixture.pending[7] != nil }
        fixture.finish(7, with: .failure(URLError(.timedOut)))
        _ = wait { completed.contains(7) }
        model.projection.searchQuery = "network failure"
        checks["music_search_failure_has_visible_message"] = model.searchMessage == L10n.text("搜索失败") && !model.isShowingSearchProgress

        let rejected = start(8, query: "service rejection")
        _ = wait { fixture.pending[8] != nil }
        fixture.finish(8, with: .failure(AppleMusicSearchError.httpStatus(403)))
        _ = wait { completed.contains(8) }
        model.projection.searchQuery = "service rejection"
        checks["music_search_service_rejection_shows_http_status"] = model.searchMessage?.contains("HTTP 403") == true && !model.isShowingSearchProgress

        model.searchText = "debounce"
        var sent = false
        var debounceFinished = false
        let debounce = Task { @MainActor in
            await model.runAppleMusicSearch(prepareExternalServiceWork: {}, search: { _ in sent = true; return [] }, debounceNanoseconds: 1_000_000_000)
            debounceFinished = true
        }
        _ = wait { model.isSearching }
        checks["music_search_debounce_gives_immediate_feedback"] = model.isShowingSearchProgress && !sent
        debounce.cancel()
        _ = wait { debounceFinished }
        checks["music_search_cancelled_debounce_does_not_send_request"] = !sent && !model.isSearching
        checks["music_search_all_async_fixtures_completed"] = completed == Set(1...8) && clearFinished && debounceFinished
        [first, second, sameOld, sameNew, beforeClear, clear, empty, failure, rejected, debounce].forEach { $0.cancel() }
        fixture.cancelRemaining()
        model.cancelTasks()
        return checks
    }
}

@MainActor
private final class MusicSearchFixture {
    var pending: [Int: CheckedContinuation<[AppleMusicSearchResult], Error>] = [:]
    func search(_ slot: Int) async throws -> [AppleMusicSearchResult] {
        try await withCheckedThrowingContinuation { pending[slot] = $0 }
    }
    func finish(_ slot: Int, with result: Result<[AppleMusicSearchResult], Error>) {
        pending.removeValue(forKey: slot)?.resume(with: result)
    }
    func cancelRemaining() {
        let remaining = pending.values
        pending.removeAll()
        remaining.forEach { $0.resume(throwing: CancellationError()) }
    }
}
