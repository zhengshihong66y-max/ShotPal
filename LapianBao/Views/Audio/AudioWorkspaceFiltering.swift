//
//  AudioWorkspaceFiltering.swift
//  LapianBao
//
//  Search, tag filtering, and sound-effect tag semantics.
//

import Foundation

private struct AudioTagCountRecord {
    var searchKeys: [String]
    var tagKeys: Set<String>

    func matchesSearch(_ query: String) -> Bool {
        query.isEmpty || searchKeys.contains { $0.contains(query) }
    }
}

extension AudioWorkspaceView {
    static let audioCategoryTagOrder = [
        "Whoosh",
        "Riser",
        "Hit",
        "Ambience",
        "Foley"
    ]

    static let featuredAudioTag = "精选"

    static let primaryAudioTagOrder = [
        "Whoosh",
        "Riser",
        "Hit",
        "Ambience",
        "Foley",
        "精选"
    ]

    func primaryAudioTagValues(from tags: [String]) -> [String] {
        let tagsByKey = Dictionary(uniqueKeysWithValues: tags.map { (normalizedSearch($0), $0) })
        return Self.primaryAudioTagOrder.compactMap { tagsByKey[normalizedSearch($0)] }
    }

    func secondaryAudioTagValues(from tags: [String]) -> [String] {
        let primaryKeys = Set(Self.primaryAudioTagOrder.map(normalizedSearch))
        return tags.filter { !primaryKeys.contains(normalizedSearch($0)) }
    }

    var selectedAudioCategoryTagKeys: Set<String> {
        let categoryKeys = Self.audioCategoryTagOrder.map(normalizedSearch)
        return Set(categoryKeys.filter { selectedAudioTagKeys.contains($0) })
    }

    func availableAudioTagKeys(matching selectedCategoryKeys: Set<String>) -> Set<String> {
        guard !selectedCategoryKeys.isEmpty else { return [] }

        var availableKeys = Set<String>()
        for record in audioTagCountRecords() where selectedCategoryKeys.isSubset(of: record.tagKeys) {
            availableKeys.formUnion(record.tagKeys)
        }
        return availableKeys
    }

    var filteredLocalAudioAssets: [LocalAudioAsset] {
        let query = normalizedSearch(searchText)
        let selectedTagKeys = selectedAudioTagKeys
        guard !query.isEmpty || !selectedTagKeys.isEmpty else {
            return libraryStore.localAudioAssets
        }
        return libraryStore.localAudioAssets.filter { asset in
            let tags = visibleTags(for: asset)
            let matchesSearch = query.isEmpty
                || normalizedSearch(asset.title).contains(query)
                || tags.contains { normalizedSearch($0).contains(query) }
            guard matchesSearch else { return false }
            return matchesSelectedAudioFilters(for: asset, selectedTagKeys: selectedTagKeys)
        }
    }

    var filteredAudioClips: [AudioClipItem] {
        let query = normalizedSearch(searchText)
        let selectedTagKeys = selectedAudioTagKeys
        guard !query.isEmpty || !selectedTagKeys.isEmpty else {
            return libraryStore.audioClips.sorted { $0.createdAt > $1.createdAt }
        }
        return libraryStore.audioClips
            .filter { clip in
                let name = audioClipDisplayName(clip)
                let tags = visibleTags(for: clip)
                let matchesSearch = query.isEmpty
                    || normalizedSearch(name).contains(query)
                    || normalizedSearch(clip.videoName).contains(query)
                    || tags.contains { normalizedSearch($0).contains(query) }
                guard matchesSearch else { return false }
                return matchesSelectedAudioFilters(for: clip, selectedTagKeys: selectedTagKeys)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var audioFilterTags: [String] {
        let localTags = libraryStore.localAudioAssets.flatMap { visibleTags(for: $0) }
        let clipTags = libraryStore.audioClips.flatMap { visibleTags(for: $0) }
        return cleanedAudioTags(localTags + clipTags)
    }

    func audioDynamicTagCountsByName(for tags: [String]) -> [String: Int] {
        var counts = Dictionary(uniqueKeysWithValues: tags.map { ($0, 0) })
        var tagNameByKey: [String: String] = [:]
        for tag in tags {
            let key = normalizedSearch(tag)
            guard !key.isEmpty else { continue }
            tagNameByKey[key] = tag
        }
        guard !tagNameByKey.isEmpty else { return counts }

        let query = normalizedSearch(searchText)
        let selectedTagKeys = selectedAudioTagKeys

        for record in audioTagCountRecords() {
            guard record.matchesSearch(query) else { continue }
            guard selectedTagKeys.isSubset(of: record.tagKeys) else {
                continue
            }

            for tagKey in record.tagKeys {
                guard let tagName = tagNameByKey[tagKey] else { continue }
                counts[tagName, default: 0] += 1
            }
        }

        return counts
    }

    private func audioTagCountRecords() -> [AudioTagCountRecord] {
        var records: [AudioTagCountRecord] = []
        records.reserveCapacity(libraryStore.localAudioAssets.count + libraryStore.audioClips.count)

        for asset in libraryStore.localAudioAssets {
            let tags = visibleTags(for: asset)
            let tagKeys = Set(tags.map(normalizedSearch).filter { !$0.isEmpty })
            records.append(
                AudioTagCountRecord(
                    searchKeys: [normalizedSearch(asset.title)] + Array(tagKeys),
                    tagKeys: tagKeys
                )
            )
        }

        for clip in libraryStore.audioClips {
            let name = audioClipDisplayName(clip)
            let tags = visibleTags(for: clip)
            let tagKeys = Set(tags.map(normalizedSearch).filter { !$0.isEmpty })
            records.append(
                AudioTagCountRecord(
                    searchKeys: [normalizedSearch(name), normalizedSearch(clip.videoName)] + Array(tagKeys),
                    tagKeys: tagKeys
                )
            )
        }

        return records
    }

    var selectedAudioTagFilterCount: Int {
        selectedAudioTagKeys.count
    }

    func toggleAudioTagFilter(_ tag: String) {
        let tagKey = normalizedSearch(tag)
        guard !tagKey.isEmpty else { return }
        if selectedAudioTagKeys.contains(tagKey) {
            selectedAudioTagKeys.remove(tagKey)
        } else {
            selectedAudioTagKeys.insert(tagKey)
        }
    }

    func matchesSelectedAudioFilters(
        for asset: LocalAudioAsset,
        selectedTagKeys: Set<String>
    ) -> Bool {
        guard !selectedTagKeys.isEmpty else { return true }
        let tagKeys = Set(visibleTags(for: asset).map(normalizedSearch))
        return selectedTagKeys.isSubset(of: tagKeys)
    }

    func matchesSelectedAudioFilters(
        for clip: AudioClipItem,
        selectedTagKeys: Set<String>
    ) -> Bool {
        guard !selectedTagKeys.isEmpty else { return true }
        let tagKeys = Set(visibleTags(for: clip).map(normalizedSearch))
        return selectedTagKeys.isSubset(of: tagKeys)
    }

    func audioClipDisplayName(_ clip: AudioClipItem) -> String {
        let note = clip.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            return note
        }
        return clip.videoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名音效" : clip.videoName
    }

    func visibleTags(for asset: LocalAudioAsset) -> [String] {
        cleanedAudioTags(asset.tags)
            .filter { !isAudioMetadataValue($0, names: [asset.title]) }
    }

    func visibleTags(for clip: AudioClipItem) -> [String] {
        cleanedAudioTags(clip.tags)
            .filter { !isAudioMetadataValue($0, names: [audioClipDisplayName(clip), clip.videoName]) }
    }

    func displayedTags(for asset: LocalAudioAsset) -> [String] {
        visibleTags(for: asset).filter { !isFeaturedAudioTag($0) }
    }

    func displayedTags(for clip: AudioClipItem) -> [String] {
        visibleTags(for: clip).filter { !isFeaturedAudioTag($0) }
    }

    func displayedAudioTagSuggestions(_ tags: [String]) -> [String] {
        cleanedAudioTags(tags).filter { !isFeaturedAudioTag($0) }
    }

    func isFeaturedAudioTag(_ tag: String) -> Bool {
        normalizedSearch(tag) == normalizedSearch(Self.featuredAudioTag)
    }

    func hasFeaturedAudioTag(_ tags: [String]) -> Bool {
        tags.contains { isFeaturedAudioTag($0) }
    }

    func isAudioMetadataValue(_ value: String, names: [String]) -> Bool {
        let valueKey = normalizedSearch(value)
        guard !valueKey.isEmpty else { return true }
        return names
            .map(normalizedSearch)
            .filter { !$0.isEmpty }
            .contains(valueKey)
    }

    func cleanedAudioTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert(normalizedSearch($0)).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func audioTagSuggestions(for clip: AudioClipItem) -> [String] {
        displayedAudioTagSuggestions(Array(Set(libraryStore.allAudioTags + clip.tags)))
    }
}
