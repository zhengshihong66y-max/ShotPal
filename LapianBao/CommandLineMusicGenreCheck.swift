import Foundation

@MainActor
enum CommandLineMusicGenreCheck {
    static func run() -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let cases: [(String, String)] = [
            ("国际流行", "Pop"), ("國際流行", "Pop"), ("国语流行", "Mandopop"),
            ("粵語流行", "Cantopop"), ("电子音乐", "Electronic"), ("電子音樂", "Electronic"),
            ("R&B/灵魂乐", "R&B/Soul"), (" Ｒ＆Ｂ ／ 靈魂樂 ", "R&B/Soul"),
            ("嘻哈/说唱", "Hip-Hop/Rap"), ("另類音樂", "Alternative"), ("爵士乐", "Jazz"),
            ("原声音乐", "Soundtrack"), ("动画", "Soundtrack"), ("唱作歌手", "Singer/Songwriter"),
            ("鄉村音樂", "Country"), ("日本流行乐", "J-Pop"), ("韩国流行乐", "K-Pop"),
            ("儿童音乐", "Children's Music"), ("兒童音樂", "Children's Music"),
            ("Fitness & Workout", "Fitness & Workout"), ("French Pop", "French Pop"),
            ("Acoustic Blues", "Acoustic Blues"), ("Afrobeats", "Afrobeats"),
            ("Holiday", "Holiday"), ("Vocal", "Vocal")
        ]
        do {
            let json: [String: Any] = ["results": cases.enumerated().map { index, pair in
                ["trackId": index + 9000, "trackName": "Fixture Song \(index)", "artistName": "Fixture Artist \(index)",
                 "primaryGenreName": pair.0, "trackViewUrl": "https://music.apple.com/cn/album/fixture/\(index + 9000)"] as [String: Any]
            }]
            let data = try JSONSerialization.data(withJSONObject: json)
            let results = try JSONDecoder().decode(AppleMusicSearchResponse.self, from: data).results
            var input = CommandLineMusicRowsCheck.input(jobs: [])
            input.searchMode = .onlineCatalog
            input.searchText = "Fixture"
            input.searchResults = results
            let rows = MusicWorkspaceProjectionBuilder(input: input).makeProjection().filteredSearchItems
            checks["music_genres_all_fixture_rows_visible"] = rows.count == cases.count
            for (index, pair) in cases.enumerated() {
                let song = results[index].asMusicRecognitionItem()
                checks["music_genre_\(index)_json_to_song"] = song.tags == [pair.1] && song.displayTags == [pair.1]
                checks["music_genre_\(index)_row_display"] = rows.first { $0.id == index + 9000 }?.visibleTags == [pair.1]
                checks["music_genre_\(index)_canonical_is_idempotent"] = MusicRecognitionItem.canonicalMusicGenreTag(pair.1) == pair.1
                let job = MusicDownloadJob(songKey: "\(song.title)|\(song.artist)", type: .original, status: .paused, song: song)
                let restored = try JSONDecoder().decode(MusicDownloadJob.self, from: JSONEncoder().encode(job))
                checks["music_genre_\(index)_download_snapshot_survives_restart"] = restored.song?.displayTags == [pair.1]
            }
            input.selectedMusicFilters = [MusicFilterOption(kind: .tag, value: "Pop")]
            let popRows = MusicWorkspaceProjectionBuilder(input: input).makeProjection().filteredSearchItems
            checks["music_genre_pop_filter_matches_localized_catalog_tags"] = popRows.map(\.id) == [9000, 9001]
            input.selectedMusicFilters = [MusicFilterOption(kind: .tag, value: "Electronic")]
            let electronicRows = MusicWorkspaceProjectionBuilder(input: input).makeProjection().filteredSearchItems
            checks["music_genre_electronic_filter_excludes_other_genres"] = electronicRows.map(\.id) == [9004, 9005]
            checks["music_genre_arbitrary_content_is_not_a_genre"] = MusicRecognitionItem.cleanedGenreTags(["download", "夏日旅行", "Fixture Artist", "https://example.com"]).isEmpty
            let unknown = AppleMusicSearchResult(trackID: 9999, title: "Fixture", artist: "Artist", genre: "")
            checks["music_genre_missing_metadata_still_has_fallback"] = unknown.asMusicRecognitionItem().displayTags == ["Soundtrack"]
            checks["music_genre_old_display_cache_invalidated"] = MusicWorkspaceDisplayCacheFile.currentVersion >= 5
            for status in [403, 429, 503] {
                let response = HTTPURLResponse(url: URL(string: "https://itunes.apple.com/search")!, statusCode: status, httpVersion: nil, headerFields: nil)!
                do {
                    _ = try LibraryStore.decodeAppleMusicSearchResponse(data: Data(), response: response)
                    checks["music_search_http_\(status)_is_not_empty_success"] = false
                } catch let error as AppleMusicSearchError {
                    checks["music_search_http_\(status)_is_not_empty_success"] = error.errorDescription?.contains("HTTP \(status)") == true
                }
            }
            let ok = HTTPURLResponse(url: URL(string: "https://itunes.apple.com/search")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            checks["music_search_http_200_empty_is_real_empty_success"] = try LibraryStore.decodeAppleMusicSearchResponse(data: Data(#"{"results":[]}"#.utf8), response: ok).isEmpty

            if let index = CommandLine.arguments.firstIndex(of: "--music-genre-fixture"), CommandLine.arguments.count > index + 1 {
                let source = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                let actual = try JSONDecoder().decode(AppleMusicSearchResponse.self, from: source).results
                // Independently transcribed expectations from the cached CN Billie Jean response.
                let expected = ["国际流行": "Pop", "国语流行": "Mandopop", "动画": "Soundtrack",
                                "原声音乐": "Soundtrack", "电子音乐": "Electronic"]
                checks["music_genre_actual_catalog_fixture_is_nonempty"] = !actual.isEmpty
                for (index, item) in actual.enumerated() {
                    checks["music_genre_actual_catalog_\(index)_preserves_provider_genre"] = expected[item.genre].map {
                        item.asMusicRecognitionItem().displayTags == [$0]
                    } ?? false
                }
            }
        } catch {
            checks["music_genre_fixture_decoding"] = false
        }
        return checks
    }
}
