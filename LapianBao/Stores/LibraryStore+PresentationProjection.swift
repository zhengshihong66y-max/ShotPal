//
//  LibraryStore+PresentationProjection.swift
//  LapianBao
//
//  Cached UI projections for high-frequency browser views.
//

import Foundation

struct LibraryTagFilterOption: Equatable {
    var count: Int
    var isEnabled: Bool
}

struct LibraryBrowserProjection: Equatable {
    var visibleVideos: [VideoItem]
    var tagFilterOptions: [String: LibraryTagFilterOption]
    var importDateSections: [VideoDateSection]

    static let empty = LibraryBrowserProjection(
        visibleVideos: [],
        tagFilterOptions: [:],
        importDateSections: []
    )
}

struct LibraryBrowserProjectionCacheKey: Equatable {
    var revision: Int
    var searchText: String
    var selectedTags: [String]
    var selectedPlatforms: [String]
    var selectedAuthors: [String]
}

struct LibraryBrowserProjectionCache {
    var key: LibraryBrowserProjectionCacheKey
    var projection: LibraryBrowserProjection
}

extension LibraryStore {
    func markLibraryPresentationDirty() {
        libraryPresentationRevision &+= 1
        libraryBrowserProjectionCache = nil
    }

    func libraryBrowserProjection(
        searchText: String,
        selectedPlatforms: Set<String>,
        selectedAuthors: Set<String>
    ) -> LibraryBrowserProjection {
        let key = LibraryBrowserProjectionCacheKey(
            revision: libraryPresentationRevision,
            searchText: normalizedSearch(searchText),
            selectedTags: selectedTags.sorted(),
            selectedPlatforms: selectedPlatforms.sorted(),
            selectedAuthors: selectedAuthors.sorted()
        )

        if let cache = libraryBrowserProjectionCache, cache.key == key {
            return cache.projection
        }

        let projection = buildLibraryBrowserProjection(
            query: key.searchText,
            selectedPlatforms: selectedPlatforms,
            selectedAuthors: selectedAuthors
        )
        libraryBrowserProjectionCache = LibraryBrowserProjectionCache(key: key, projection: projection)
        return projection
    }

    private func buildLibraryBrowserProjection(
        query: String,
        selectedPlatforms: Set<String>,
        selectedAuthors: Set<String>
    ) -> LibraryBrowserProjection {
        let selectedVideoTags = selectedTags
        var countsByTag: [String: Int] = [:]

        let visibleVideos = filteredVideos.filter { video in
            return libraryVideo(
                video,
                tags: videoTags(for: video),
                query: query,
                selectedPlatforms: selectedPlatforms,
                selectedAuthors: selectedAuthors
            )
        }

        for video in visibleVideos {
            for tag in videoTagSet(for: video) {
                countsByTag[tag, default: 0] += 1
            }
        }

        let tagOptions = Dictionary(uniqueKeysWithValues: allTags.map { tag in
            let count = countsByTag[tag, default: 0]
            let isSelected = selectedVideoTags.contains(tag)
            return (tag, LibraryTagFilterOption(count: count, isEnabled: isSelected || count > 0))
        })

        return LibraryBrowserProjection(
            visibleVideos: visibleVideos,
            tagFilterOptions: tagOptions,
            importDateSections: importDateSections(from: visibleVideos)
        )
    }

    private func libraryVideo(
        _ video: VideoItem,
        tags: [String],
        query: String,
        selectedPlatforms: Set<String>,
        selectedAuthors: Set<String>
    ) -> Bool {
        if !selectedPlatforms.isEmpty {
            guard let platform = displaySourcePlatformName(for: video),
                  selectedPlatforms.contains(platform)
            else { return false }
        }

        if !selectedAuthors.isEmpty {
            guard let author = videoSourceAuthorName(for: video),
                  selectedAuthors.contains(author)
            else { return false }
        }

        guard !query.isEmpty else { return true }
        return normalizedSearch(displayTitle(for: video)).contains(query)
            || normalizedSearch(video.name).contains(query)
            || tags.contains { normalizedSearch($0).contains(query) }
            || normalizedSearch(displaySourcePlatformName(for: video) ?? "").contains(query)
            || normalizedSearch(videoSourceAuthorName(for: video) ?? "").contains(query)
            || videoMusicMatchesSearch(video, query: query)
    }

    private func videoMusicMatchesSearch(_ video: VideoItem, query: String) -> Bool {
        let songs = musicsByVideoPath[video.url.path, default: []]
        guard !songs.isEmpty else { return false }

        return songs.contains { song in
            normalizedSearch(song.title).contains(query)
                || normalizedSearch(song.artist).contains(query)
                || song.displayTags.contains { normalizedSearch($0).contains(query) }
        }
    }

    private func displayTitle(for video: VideoItem) -> String {
        videoSourceTitle(for: video) ?? video.name
    }

    private func displaySourcePlatformName(for video: VideoItem) -> String? {
        guard let platform = videoSourcePlatform(for: video) else { return nil }
        return VideoSourcePlatform.matching(platform)?.rawValue ?? platform
    }

    private func importDateSections(from videos: [VideoItem]) -> [VideoDateSection] {
        guard sortOption == .importDate else { return [] }

        var sections: [VideoDateSection] = []
        var sectionIndexByID: [String: Int] = [:]

        for video in videos {
            let section = importDateSection(for: video)

            if let index = sectionIndexByID[section.id] {
                sections[index].videos.append(video)
            } else {
                sectionIndexByID[section.id] = sections.count
                sections.append(VideoDateSection(id: section.id, title: section.title, videos: [video]))
            }
        }

        return sections
    }

    private func importDateSection(for video: VideoItem) -> (id: String, title: String) {
        guard let date = metadataByVideoPath[video.url.path]?.createdAt else {
            return ("unknown", "日期未知")
        }

        let startOfDay = Calendar.current.startOfDay(for: date)
        let id = String(Int(startOfDay.timeIntervalSince1970))
        let title = DateFormatter.localizedString(from: startOfDay, dateStyle: .medium, timeStyle: .none)
        return (id, title)
    }
}
