//
//  LibraryStore+IndexesAndBasics.swift
//  LapianBao
//
//  Split from LibraryStore.swift.
//

import AppKit
import AVFoundation
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

extension LibraryStore {
    var allTags: [String] {
        allTagsCache
    }

    var allFrameTags: [String] {
        frameTagsCache
    }

    var allAudioTags: [String] {
        audioTagsCache
    }

    var allMusicTags: [String] {
        musicTagsCache
    }

    var videoTagSuggestions: [String] {
        Self.cleanedVideoTagSuggestions(allTags + Self.defaultVideoTagSuggestions)
    }

    func videoTagSuggestions(for video: VideoItem) -> [String] {
        Self.cleanedVideoTagSuggestions(
            subjectiveVideoTags(
                forPath: video.url.path,
                tags: allTags + videoTags(for: video) + Self.defaultVideoTagSuggestions
            )
        )
    }

    func videoTags(for video: VideoItem) -> [String] {
        if let tags = videoTagsByPathCache[video.url.path] {
            return tags
        }

        return subjectiveVideoTags(
            forPath: video.url.path,
            tags: tagsByVideoPath[video.url.path, default: []]
        )
    }

    func videoTagSet(for video: VideoItem) -> Set<String> {
        if let tags = videoTagSetsByPathCache[video.url.path] {
            return tags
        }

        return Set(videoTags(for: video))
    }

    func videoTagSortKey(for video: VideoItem) -> String {
        if let key = videoTagSortKeyByPathCache[video.url.path] {
            return key
        }

        return videoTags(for: video).joined(separator: " ")
    }

    func rebuildAllTagsCache() {
        rebuildVideoTagIndexes()
    }

    func rebuildVideoTagIndexes() {
        var nextTagsByPath: [String: [String]] = [:]
        var nextTagSetsByPath: [String: Set<String>] = [:]
        var nextPathsByTag: [String: Set<String>] = [:]
        var nextTagSortKeysByPath: [String: String] = [:]
        var nextAllTags = Set<String>()

        for video in videos {
            let path = video.url.path
            let tags = subjectiveVideoTags(
                forPath: path,
                tags: tagsByVideoPath[path, default: []]
            )
            let tagSet = Set(tags)

            nextTagsByPath[path] = tags
            nextTagSetsByPath[path] = tagSet
            nextTagSortKeysByPath[path] = tags.joined(separator: " ")

            for tag in tagSet {
                nextAllTags.insert(tag)
                nextPathsByTag[tag, default: []].insert(path)
            }
        }

        allTagsCache = nextAllTags.sorted()
        videoTagsByPathCache = nextTagsByPath
        videoTagSetsByPathCache = nextTagSetsByPath
        videoPathsByTagCache = nextPathsByTag
        videoTagSortKeyByPathCache = nextTagSortKeysByPath
    }

    nonisolated static let defaultVideoTagSuggestions: [String] = [
        "参考",
        "灵感",
        "案例",
        "画面",
        "构图",
        "色彩",
        "光线",
        "运镜",
        "剪辑",
        "节奏",
        "文案",
        "声音"
    ]

    nonisolated static func cleanedVideoTagSuggestions(_ tags: [String]) -> [String] {
        var seenKeys = Set<String>()
        return tags.compactMap { rawTag in
            guard let tag = normalizedImportTag(rawTag),
                  let key = normalizedSubjectiveTagKey(tag),
                  !looksLikeSourceMetadataFragment(tag),
                  canonicalSourcePlatform(tag) == nil,
                  seenKeys.insert(key).inserted
            else { return nil }

            return tag
        }
    }

    func videoPathSet(matchingSelectedTags selectedVideoTags: Set<String>) -> Set<String>? {
        guard !selectedVideoTags.isEmpty else { return nil }

        let tagsByIncreasingScope = selectedVideoTags.sorted {
            let lhsCount = videoPathsByTagCache[$0]?.count ?? 0
            let rhsCount = videoPathsByTagCache[$1]?.count ?? 0
            if lhsCount != rhsCount { return lhsCount < rhsCount }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }

        guard let firstTag = tagsByIncreasingScope.first,
              var candidatePaths = videoPathsByTagCache[firstTag]
        else { return [] }

        for tag in tagsByIncreasingScope.dropFirst() {
            guard let paths = videoPathsByTagCache[tag] else { return [] }
            candidatePaths.formIntersection(paths)
            if candidatePaths.isEmpty { break }
        }

        return candidatePaths
    }

    func videosMatchingSelectedTags(_ selectedVideoTags: Set<String>) -> [VideoItem] {
        guard let candidatePaths = videoPathSet(matchingSelectedTags: selectedVideoTags) else {
            return videos
        }
        guard !candidatePaths.isEmpty else { return [] }

        return candidatePaths.compactMap { videoByPath[$0] }
    }

    func clearVideoSourceCaches() {
        videoSourcePlatformCache.removeAll()
        videoSourceAuthorCache.removeAll()
        videoSourceTitleCache.removeAll()
    }

    func beginLibrarySidebarMetricsBatch() {
        librarySidebarMetricsRebuildDeferralDepth += 1
    }

    func endLibrarySidebarMetricsBatch() {
        librarySidebarMetricsRebuildDeferralDepth = max(0, librarySidebarMetricsRebuildDeferralDepth - 1)
        guard librarySidebarMetricsRebuildDeferralDepth == 0,
              needsLibrarySidebarMetricsRebuild
        else { return }
        needsLibrarySidebarMetricsRebuild = false
        rebuildLibrarySidebarMetrics()
    }

    func markLibrarySidebarMetricsDirty() {
        guard librarySidebarMetricsRebuildDeferralDepth == 0 else {
            needsLibrarySidebarMetricsRebuild = true
            return
        }
        rebuildLibrarySidebarMetrics()
    }

    func rebuildLibrarySidebarMetrics() {
        let platformOrder = Dictionary(
            uniqueKeysWithValues: VideoSourcePlatform.allCases.enumerated().map { ($0.element.rawValue, $0.offset) }
        )
        var platformDisplayByKey: [String: String] = [:]
        var authorDisplayByKey: [String: String] = [:]
        var platformCountsByKey: [String: Int] = [:]
        var authorCountsByKey: [String: Int] = [:]
        var tagCountsByKey: [String: Int] = [:]

        func register(
            _ value: String?,
            displayByKey: inout [String: String],
            countsByKey: inout [String: Int]
        ) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedSearch(trimmed)
            guard !key.isEmpty else { return }
            if displayByKey[key] == nil {
                displayByKey[key] = trimmed
            }
            countsByKey[key, default: 0] += 1
        }

        for video in videos {
            let platform = videoSourcePlatform(for: video).map { VideoSourcePlatform.matching($0)?.rawValue ?? $0 }
            register(
                platform,
                displayByKey: &platformDisplayByKey,
                countsByKey: &platformCountsByKey
            )
            register(
                videoSourceAuthorName(for: video),
                displayByKey: &authorDisplayByKey,
                countsByKey: &authorCountsByKey
            )

            var seenTagKeys = Set<String>()
            for tag in videoTags(for: video) {
                let key = normalizedSearch(tag)
                guard !key.isEmpty, seenTagKeys.insert(key).inserted else { continue }
                tagCountsByKey[key, default: 0] += 1
            }
        }

        let platforms = platformCountsByKey.keys
            .compactMap { platformDisplayByKey[$0] }
            .sorted { lhs, rhs in
                let leftOrder = platformOrder[lhs] ?? Int.max
                let rightOrder = platformOrder[rhs] ?? Int.max
                if leftOrder != rightOrder { return leftOrder < rightOrder }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        let authors = authorCountsByKey.keys
            .filter { authorCountsByKey[$0, default: 0] > 1 }
            .compactMap { authorDisplayByKey[$0] }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        let platformCounts = Dictionary(uniqueKeysWithValues: platformCountsByKey.compactMap { key, count in
            platformDisplayByKey[key].map { ($0, count) }
        })
        let authorCounts = Dictionary(uniqueKeysWithValues: authorCountsByKey.compactMap { key, count in
            authorDisplayByKey[key].map { ($0, count) }
        })

        let nextMetrics = VideoLibrarySidebarMetrics(
            platforms: platforms,
            authors: authors,
            platformCounts: platformCounts,
            authorCounts: authorCounts,
            tagCountsByKey: tagCountsByKey
        )
        if librarySidebarMetrics != nextMetrics {
            librarySidebarMetrics = nextMetrics
        }
    }

    func rebuildSampledFrameIndexes() {
        collectedFramesCache = sampledFrames.sorted {
            if $0.videoName == $1.videoName { return $0.time < $1.time }
            return $0.videoName.localizedStandardCompare($1.videoName) == .orderedAscending
        }
        sampledFramesByVideoPath = Dictionary(grouping: sampledFrames, by: \.videoPath).mapValues {
            $0.sorted { lhs, rhs in
                if abs(lhs.time - rhs.time) > 0.001 { return lhs.time < rhs.time }
                return lhs.createdAt < rhs.createdAt
            }
        }
        sampledFrameByID = Dictionary(uniqueKeysWithValues: sampledFrames.map { ($0.id, $0) })
        frameTagsCache = Array(Set(sampledFrames.flatMap(\.tags))).sorted()

        let liveIDs = Set(sampledFrames.map(\.id))
        sampledFrameThumbnailImageByID = sampledFrameThumbnailImageByID.filter { liveIDs.contains($0.key) }
        sampledFrameThumbnailImageAccessTickByID = sampledFrameThumbnailImageAccessTickByID.filter { liveIDs.contains($0.key) }
    }

    func rebuildAnnotationIndexes() {
        annotationsByVideoPath = Dictionary(grouping: annotations, by: \.videoPath).mapValues {
            $0.sorted { lhs, rhs in
                if abs(lhs.time - rhs.time) > 0.001 { return lhs.time < rhs.time }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    func rebuildAudioClipIndexes() {
        audioClipsByVideoPath = Dictionary(grouping: audioClips, by: \.videoPath).mapValues {
            $0.sorted { lhs, rhs in
                if abs(lhs.inTime - rhs.inTime) > 0.001 { return lhs.inTime < rhs.inTime }
                return lhs.createdAt < rhs.createdAt
            }
        }
        audioTagsCache = Array(Set(audioClips.flatMap(\.tags) + localAudioAssets.flatMap(\.tags))).sorted()
    }

    func rebuildMusicIndexes() {
        let recognizedTags = musicsByVideoPath.values.flatMap { songs in
            songs.flatMap(\.displayTags)
        }
        musicTagsCache = Array(Set(recognizedTags)).sorted()
    }

    func refreshFilteredVideos() {
        let scopedVideos = videosMatchingSelectedTags(selectedTags)

        filteredVideos = scopedVideos.sorted { lhs, rhs in
            let result: ComparisonResult
            switch sortOption {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name)
            case .importDate:
                result = compareDates(metadataByVideoPath[lhs.url.path]?.createdAt, metadataByVideoPath[rhs.url.path]?.createdAt)
            case .duration:
                result = compareNumbers(metadataByVideoPath[lhs.url.path]?.duration, metadataByVideoPath[rhs.url.path]?.duration)
            case .fileSize:
                result = compareNumbers(metadataByVideoPath[lhs.url.path]?.fileSize, metadataByVideoPath[rhs.url.path]?.fileSize)
            case .resolution:
                let leftPixels = (metadataByVideoPath[lhs.url.path]?.pixelWidth ?? 0) * (metadataByVideoPath[lhs.url.path]?.pixelHeight ?? 0)
                let rightPixels = (metadataByVideoPath[rhs.url.path]?.pixelWidth ?? 0) * (metadataByVideoPath[rhs.url.path]?.pixelHeight ?? 0)
                result = compareNumbers(leftPixels, rightPixels)
            case .tags:
                let leftTags = videoTagSortKey(for: lhs)
                let rightTags = videoTagSortKey(for: rhs)
                result = leftTags.localizedStandardCompare(rightTags)
            }

            if result == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return sortDirection == .ascending ? result == .orderedAscending : result == .orderedDescending
        }
        markLibraryPresentationDirty()
    }

    func scheduleMetadataDependentRefresh() {
        metadataRefreshTask?.cancel()
        metadataRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.thumbnailLoadingPaths.isEmpty else {
                self.metadataRefreshTask = nil
                self.scheduleMetadataDependentRefresh()
                return
            }
            objectWillChange.send()
            refreshFilteredVideos()
            metadataRefreshTask = nil
        }
    }

    func compareDates(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        compareNumbers(lhs?.timeIntervalSince1970, rhs?.timeIntervalSince1970)
    }

    func compareNumbers<T: BinaryInteger>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        compareNumbers(lhs.map(Double.init), rhs.map(Double.init))
    }

    func compareNumbers(_ lhs: Double?, _ rhs: Double?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left?, right?):
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
            return .orderedSame
        case (_?, nil):
            return .orderedAscending
        case (nil, _?):
            return .orderedDescending
        case (nil, nil):
            return .orderedSame
        }
    }

    var collectedFrames: [SampledFrame] {
        collectedFramesCache
    }

    func sampledFrames(for video: VideoItem) -> [SampledFrame] {
        sampledFramesByVideoPath[video.url.path, default: []]
    }

    func sampledFrame(id: UUID) -> SampledFrame? {
        sampledFrameByID[id]
    }

    func thumbnailImage(for frame: SampledFrame) -> NSImage? {
        if let cached = sampledFrameThumbnailImageByID[frame.id] {
            noteSampledFrameThumbnailImageAccess(for: frame.id)
            return cached
        }
        guard let image = NSImage(data: frame.thumbnailData) else { return nil }
        sampledFrameThumbnailImageByID[frame.id] = image
        noteSampledFrameThumbnailImageAccess(for: frame.id)
        trimDecodedSampledFrameImageCacheIfNeeded()
        return image
    }

    func noteTransientMediaAccess(for video: VideoItem) {
        noteTransientMediaAccess(for: video.url.path)
    }

    func noteTransientMediaAccess(for path: String) {
        transientMediaCacheAccessTick += 1
        transientMediaCacheAccessTickByPath[path] = transientMediaCacheAccessTick
        scheduleTransientMediaCacheTrim()
    }

    func scheduleTransientMediaCacheTrim(after delay: TimeInterval = LibraryStore.transientMediaCacheTrimDelay) {
        guard transientMediaCacheTrimTask == nil else { return }

        transientMediaCacheTrimTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.transientMediaCacheTrimTask = nil
            self.trimTransientMediaCachesIfNeeded()
        }
    }

    func trimTransientMediaCachesIfNeeded() {
        trimWaveformCacheIfNeeded()
        trimFrameStripCacheIfNeeded()
        trimSceneCutCacheIfNeeded()
        trimDecodedSampledFrameImageCacheIfNeeded()
        trimTransientMediaAccessTicks()
    }

    func trimWaveformCacheIfNeeded() {
        let keysToRemove = transientMediaKeysToRemove(
            from: Set(waveformSamplesByVideoPath.keys),
            maxCount: Self.maxResidentWaveformVideoCaches
        )
        guard !keysToRemove.isEmpty else { return }

        for path in keysToRemove {
            waveformSamplesByVideoPath.removeValue(forKey: path)
        }
        PerformanceDiagnostics.mark("trim waveform cache")
    }

    func trimFrameStripCacheIfNeeded() {
        let keys = Set(frameStripByVideoPath.keys).union(frameStripImagesByVideoPath.keys)
        let keysToRemove = transientMediaKeysToRemove(
            from: keys,
            maxCount: Self.maxResidentFrameStripVideoCaches
        )
        guard !keysToRemove.isEmpty else { return }

        for path in keysToRemove {
            frameStripByVideoPath.removeValue(forKey: path)
            frameStripImagesByVideoPath.removeValue(forKey: path)
            sceneStripImagesByVideoPath.removeValue(forKey: path)
        }
        PerformanceDiagnostics.mark("trim frame strip cache")
    }

    func trimSceneCutCacheIfNeeded() {
        let keys = Set(sceneCutsByVideoPath.keys)
            .union(sceneStripImagesByVideoPath.keys)
            .union(sceneCutProgressesByVideoPath.keys)
        let keysToRemove = transientMediaKeysToRemove(
            from: keys,
            maxCount: Self.maxResidentSceneCutVideoCaches
        )
        guard !keysToRemove.isEmpty else { return }

        for path in keysToRemove {
            sceneStripImagesByVideoPath.removeValue(forKey: path)
            if let video = selectedVideo(for: path),
               validCachedSceneCutEntry(for: video) != nil {
                sceneCutsByVideoPath.removeValue(forKey: path)
                sceneCutProgressesByVideoPath.removeValue(forKey: path)
                sceneThumbnailVersionsByVideoPath.removeValue(forKey: path)
                sceneThumbnailHydrationNeeded.remove(path)
            }
        }
        PerformanceDiagnostics.mark("trim scene cache")
    }

    func transientMediaKeysToRemove(
        from keys: Set<String>,
        maxCount: Int
    ) -> [String] {
        guard keys.count > maxCount else { return [] }

        let preserved = transientMediaPreservedPaths()
        let preservedCount = keys.filter { preserved.contains($0) }.count
        let removable = keys.filter { !preserved.contains($0) }
        let removableBudget = max(0, maxCount - preservedCount)
        guard removable.count > removableBudget else { return [] }

        return Array(removable.sorted {
            transientMediaCacheAccessTickByPath[$0, default: 0] < transientMediaCacheAccessTickByPath[$1, default: 0]
        }.prefix(removable.count - removableBudget))
    }

    func transientMediaPreservedPaths() -> Set<String> {
        var preserved = Set<String>()
        if let path = selectedVideo?.url.path {
            preserved.insert(path)
        }
        preserved.formUnion(waveformTasks.keys)
        preserved.formUnion(frameStripTasks.keys)
        preserved.formUnion(sceneDetectionTasks.keys)
        preserved.formUnion(sceneThumbnailHydrationTasks.keys)
        preserved.formUnion(musicDetectionTasks.keys)
        preserved.formUnion(transcriptTasks.keys)
        return preserved
    }

    func trimTransientMediaAccessTicks() {
        let livePaths = Set(waveformSamplesByVideoPath.keys)
            .union(frameStripByVideoPath.keys)
            .union(frameStripImagesByVideoPath.keys)
            .union(sceneCutsByVideoPath.keys)
            .union(sceneStripImagesByVideoPath.keys)
            .union(sceneCutProgressesByVideoPath.keys)
            .union(transientMediaPreservedPaths())
        transientMediaCacheAccessTickByPath = transientMediaCacheAccessTickByPath.filter { livePaths.contains($0.key) }
    }

    func noteSampledFrameThumbnailImageAccess(for id: UUID) {
        sampledFrameThumbnailImageAccessTick += 1
        sampledFrameThumbnailImageAccessTickByID[id] = sampledFrameThumbnailImageAccessTick
    }

    func trimDecodedSampledFrameImageCacheIfNeeded() {
        let limit = Self.maxDecodedSampledFrameImages
        guard sampledFrameThumbnailImageByID.count > limit else { return }

        let selectedPath = selectedVideo?.url.path
        let preservedIDs = Set(sampledFrameThumbnailImageByID.keys.filter { id in
            guard let selectedPath else { return false }
            return sampledFrameByID[id]?.videoPath == selectedPath
        })
        let removableIDs = sampledFrameThumbnailImageByID.keys.filter { !preservedIDs.contains($0) }
        let removableBudget = max(0, limit - preservedIDs.count)
        guard removableIDs.count > removableBudget else { return }

        let idsToRemove = removableIDs.sorted {
            sampledFrameThumbnailImageAccessTickByID[$0, default: 0] < sampledFrameThumbnailImageAccessTickByID[$1, default: 0]
        }.prefix(removableIDs.count - removableBudget)

        for id in idsToRemove {
            sampledFrameThumbnailImageByID.removeValue(forKey: id)
            sampledFrameThumbnailImageAccessTickByID.removeValue(forKey: id)
        }
        PerformanceDiagnostics.mark("trim sampled frame image cache")
    }

    func fullResolutionFrameImage(videoURL: URL, time: Double) async -> NSImage? {
        await Self.renderFrameImage(for: videoURL, at: time)
    }

    func fullResolutionFrameImage(for frame: SampledFrame) async -> NSImage? {
        await fullResolutionFrameImage(videoURL: URL(fileURLWithPath: frame.videoPath), time: frame.time)
    }

    func fullResolutionFrameProvider(for frame: SampledFrame) -> NSItemProvider {
        Self.frameDragItemProvider(
            videoURL: URL(fileURLWithPath: frame.videoPath),
            videoName: frame.videoName,
            time: frame.time,
            kind: frame.kind,
            fallbackData: frame.thumbnailData.isEmpty ? nil : frame.thumbnailData
        )
    }

    func fullResolutionFrameProvider(
        video: VideoItem,
        time: Double,
        kind: SampledFrame.Kind? = nil,
        fallbackImage: NSImage? = nil
    ) -> NSItemProvider {
        Self.frameDragItemProvider(
            videoURL: video.url,
            videoName: video.name,
            time: time,
            kind: kind,
            fallbackData: fallbackImage.flatMap(Self.jpegData(from:))
        )
    }

    func audioClipFileProvider(for clip: AudioClipItem) -> NSItemProvider? {
        guard let fileURL = audioClipFileURL(for: clip) else { return nil }
        let dragURL = externalAudioDragFileURL(for: fileURL, suggestedName: fileURL.lastPathComponent)
        return existingFileItemProvider(
            for: dragURL,
            suggestedName: fileURL.lastPathComponent,
            fallbackTypeIdentifier: UTType.audio.identifier,
            errorDomain: "LapianBao.AudioClipDragExport",
            missingFileMessage: "声音片段文件不存在"
        )
    }

    func audioClipFileURL(for clip: AudioClipItem) -> URL? {
        if let filePath = clip.filePath {
            let fileURL = URL(fileURLWithPath: filePath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }

        guard let libraryURL else { return nil }
        let fallbackURL = Self.mediaFolder(in: libraryURL, named: Self.soundEffectExportFolderName)
            .appendingPathComponent("\(Self.safeFileStem(clip.videoName))_\(Self.fileTimecode(clip.inTime))-\(Self.fileTimecode(clip.outTime)).m4a")
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            return fallbackURL
        }

        let legacyFallbackURL = Self.exportFolder(in: libraryURL, named: Self.legacySoundEffectExportFolderName)
            .appendingPathComponent("\(Self.safeFileStem(clip.videoName))_\(Self.fileTimecode(clip.inTime))-\(Self.fileTimecode(clip.outTime)).m4a")
        return FileManager.default.fileExists(atPath: legacyFallbackURL.path) ? legacyFallbackURL : nil
    }

    func localMusicFileURL(for asset: LocalMusicAsset) -> URL? {
        let url = URL(fileURLWithPath: asset.filePath)
        return localResourceFileExists(at: url.path) ? url : nil
    }

    func localAudioFileURL(for asset: LocalAudioAsset) -> URL? {
        let url = URL(fileURLWithPath: asset.filePath)
        return localResourceFileExists(at: url.path) ? url : nil
    }

    func localResourceFileExists(at path: String) -> Bool {
        if knownLocalResourcePaths.contains(path) {
            return true
        }
        return FileManager.default.fileExists(atPath: path)
    }

    func scanResourceLibrary(
        forceFullScan: Bool = false,
        refreshMode: ResourceLibraryRefreshMode = .deferred,
        loadCachedSnapshotSynchronously: Bool = true
    ) {
        guard let libraryURL else { return }
        let libraryPath = libraryURL.path
        var hasCachedSnapshot = false
        if loadCachedSnapshotSynchronously,
           let cachedSnapshot = Self.loadCachedResourceLibrarySnapshot(in: libraryURL) {
            hasCachedSnapshot = true
            PerformanceDiagnostics.mark("resource scan cache snapshot", path: libraryPath)
            applyResourceLibrarySnapshot(cachedSnapshot, libraryPath: libraryPath)
        } else if !loadCachedSnapshotSynchronously || refreshMode != .cachedOnly {
            hasCachedSnapshot = !loadCachedSnapshotSynchronously
            Task.detached(priority: .utility) { [weak self, libraryURL, libraryPath] in
                let snapshot = Self.loadCachedResourceLibrarySnapshot(in: libraryURL)
                    ?? (refreshMode == .cachedOnly ? nil : Self.quickResourceLibrarySnapshot(in: libraryURL))
                guard let snapshot else { return }
                await MainActor.run { [weak self] in
                    PerformanceDiagnostics.mark("resource scan async snapshot", path: libraryPath)
                    self?.applyResourceLibrarySnapshot(snapshot, libraryPath: libraryPath)
                }
            }
        }

        guard refreshMode != .cachedOnly else {
            PerformanceDiagnostics.mark("resource scan cached only", path: libraryPath)
            return
        }

        if !forceFullScan,
           resourceLibraryScanTask != nil,
           resourceLibraryScanTaskLibraryPath == libraryPath {
            PerformanceDiagnostics.mark("resource scan skipped running", path: libraryPath)
            return
        }

        if !forceFullScan,
           let lastFullScanAt = lastResourceLibraryFullScanAtByPath[libraryPath],
           Date().timeIntervalSince(lastFullScanAt) < Self.resourceLibraryFullScanCooldown {
            PerformanceDiagnostics.mark("resource scan skipped cooldown", path: libraryPath)
            return
        }

        resourceLibraryScanTask?.cancel()
        resourceLibraryScanGeneration += 1
        let scanGeneration = resourceLibraryScanGeneration
        resourceLibraryScanTaskLibraryPath = libraryPath
        let shouldRunImmediately = forceFullScan || refreshMode == .immediate
        let delay = shouldRunImmediately
            ? 0
            : (hasCachedSnapshot ? Self.cachedResourceLibraryFullScanDelay : Self.uncachedResourceLibraryFullScanDelay)
        let priority: TaskPriority = shouldRunImmediately ? .utility : .background
        PerformanceDiagnostics.mark(
            "resource scan scheduled \(shouldRunImmediately ? "immediate" : "deferred") delay=\(delay)",
            path: libraryPath
        )
        resourceLibraryScanTask = Task.detached(priority: priority) { [weak self, libraryURL, libraryPath, delay, scanGeneration] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }
            PerformanceDiagnostics.mark("resource scan started", path: libraryPath)
            let snapshot = await Self.scanResourceLibrarySnapshot(in: libraryURL)
            await MainActor.run { [weak self] in
                guard let self,
                      self.resourceLibraryScanGeneration == scanGeneration,
                      self.libraryURL?.path == libraryPath
                else { return }
                self.applyResourceLibrarySnapshot(snapshot, libraryPath: libraryPath)
                self.lastResourceLibraryFullScanAtByPath[libraryPath] = Date()
                self.resourceLibraryScanTask = nil
                self.resourceLibraryScanTaskLibraryPath = nil
                PerformanceDiagnostics.mark("resource scan finished", path: libraryPath)
            }
        }
    }

    func applyResourceLibrarySnapshot(_ snapshot: ResourceLibrarySnapshot, libraryPath: String) {
        guard let libraryURL, libraryURL.path == libraryPath else { return }
        let visibleMusic = visibleMusicAssetsAfterPackaging(snapshot.music, libraryURL: libraryURL)
        let visibleSnapshot = ResourceLibrarySnapshot(music: visibleMusic, audio: snapshot.audio)
        if visibleMusic != snapshot.music {
            Self.saveCachedResourceLibrarySnapshot(visibleSnapshot, in: libraryURL)
            Task.detached(priority: .background) {
                ResourceLibrarySQLite.write(libraryURL: libraryURL, music: visibleSnapshot.music, audio: visibleSnapshot.audio)
            }
        }
        let musicPaths = Set(visibleMusic.map(\.filePath))
        let audioPaths = Set(snapshot.audio.map(\.filePath))
        knownLocalResourcePaths = musicPaths.union(audioPaths)
        hydrateLocalWaveformCaches(from: visibleSnapshot, libraryURL: libraryURL)
        seedMusicFileDurations(from: visibleMusic)

        let previousMusicAssets = localMusicAssets
        let musicChanged = previousMusicAssets != visibleMusic
        let audioChanged = localAudioAssets != snapshot.audio
        if musicChanged {
            resetLocalMusicRecognitionStateIfNeeded(previousAssets: previousMusicAssets, nextAssets: visibleMusic)
            localMusicAssets = visibleMusic
        }
        if audioChanged {
            localAudioAssets = snapshot.audio
        }

        if musicChanged || audioChanged {
            pruneLocalWaveformCaches(musicPaths: musicPaths, audioPaths: audioPaths)
            cleanupInvalidGeneratedAudioClipRecords()
            reconcileMusicDownloadJobsWithLocalAssets(visibleMusic)
        }
    }

    func resetLocalMusicRecognitionStateIfNeeded(previousAssets: [LocalMusicAsset], nextAssets: [LocalMusicAsset]) {
        let previousByPath = Dictionary(uniqueKeysWithValues: previousAssets.map { ($0.filePath, $0) })
        let nextByPath = Dictionary(uniqueKeysWithValues: nextAssets.map { ($0.filePath, $0) })
        let removedPaths = Set(previousByPath.keys).subtracting(nextByPath.keys)
        let changedPaths = nextAssets.compactMap { asset -> String? in
            guard let previous = previousByPath[asset.filePath] else { return nil }
            if previous.fileSize != asset.fileSize || previous.modifiedAt != asset.modifiedAt {
                return asset.filePath
            }
            return nil
        }
        let pathsToReset = removedPaths.union(changedPaths)
        guard !pathsToReset.isEmpty else { return }

        for path in pathsToReset {
            musicsByVideoPath.removeValue(forKey: path)
            musicDetectionStatusByVideoPath.removeValue(forKey: path)
            localMusicWaveformSamplesByPath.removeValue(forKey: path)
            localMusicWaveformTasks[path]?.cancel()
            localMusicWaveformTasks[path] = nil
            let normalizedPath = Self.normalizedLocalFilePath(path)
            musicFileDurationsByPath.removeValue(forKey: normalizedPath)
            musicFileDurationTasks[normalizedPath]?.cancel()
            musicFileDurationTasks[normalizedPath] = nil

            let enrichmentKeys = musicTagEnrichmentTasks.keys.filter { $0.hasPrefix("\(path)|") }
            for key in enrichmentKeys {
                musicTagEnrichmentTasks[key]?.cancel()
                musicTagEnrichmentTasks[key] = nil
            }
        }

        saveProjectData()
    }

    func pruneLocalWaveformCaches(musicPaths: Set<String>, audioPaths: Set<String>) {
        localMusicWaveformSamplesByPath = localMusicWaveformSamplesByPath.filter { musicPaths.contains($0.key) }
        localAudioWaveformSamplesByPath = localAudioWaveformSamplesByPath.filter { audioPaths.contains($0.key) }
    }

    func cleanupInvalidGeneratedAudioClipRecords() {
        let originalCount = audioClips.count
        audioClips.removeAll { clip in
            guard let filePath = clip.filePath else { return false }
            let url = URL(fileURLWithPath: filePath)
            guard Self.isGeneratedAudioClipFile(url) else { return false }
            guard FileManager.default.fileExists(atPath: filePath) else { return true }
            let size = ((try? FileManager.default.attributesOfItem(atPath: filePath)[.size]) as? NSNumber)?.int64Value ?? 0
            return size <= Self.tinyGeneratedAudioClipByteLimit
        }
        if audioClips.count != originalCount {
            saveProjectData()
        }
    }

    func reconcileMusicDownloadJobsWithLocalAssets(_ assets: [LocalMusicAsset]) {
        guard !assets.isEmpty, !musicDownloadJobs.isEmpty else { return }
        var assetsByFilenameAndRole: [MusicDownloadAssetLookupKey: LocalMusicAsset] = [:]
        var assetsByFilename: [String: LocalMusicAsset] = [:]
        var assetsByStemAndRole: [MusicDownloadAssetLookupKey: LocalMusicAsset] = [:]
        var assetsByStem: [String: LocalMusicAsset] = [:]
        for asset in assets {
            let fileURL = URL(fileURLWithPath: asset.filePath)
            let filename = fileURL.lastPathComponent
            let stem = fileURL.deletingPathExtension().lastPathComponent
            guard FileManager.default.fileExists(atPath: asset.filePath) else { continue }
            let filenameKey = MusicDownloadAssetLookupKey(filename: filename, role: asset.role.rawValue)
            let stemKey = MusicDownloadAssetLookupKey(filename: stem, role: asset.role.rawValue)
            assetsByFilenameAndRole[filenameKey] = assetsByFilenameAndRole[filenameKey] ?? asset
            assetsByFilename[filename] = assetsByFilename[filename] ?? asset
            assetsByStemAndRole[stemKey] = assetsByStemAndRole[stemKey] ?? asset
            assetsByStem[stem] = assetsByStem[stem] ?? asset
        }

        var didChange = false
        for index in musicDownloadJobs.indices {
            guard !Self.isActiveDownloadStatus(musicDownloadJobs[index].status) else { continue }

            let role = Self.localMusicRole(for: musicDownloadJobs[index].type)
            let existingPath = musicDownloadJobs[index].filePath.flatMap { path in
                FileManager.default.fileExists(atPath: path) ? path : nil
            }
            let resolvedAsset = existingPath.map { path in
                LocalMusicAsset(
                    filePath: path,
                    title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                    fileExtension: URL(fileURLWithPath: path).pathExtension.lowercased(),
                    role: role,
                    tags: [],
                    duration: 0,
                    fileSize: 0,
                    modifiedAt: nil
                )
            } ?? resolvedMusicDownloadAsset(
                for: musicDownloadJobs[index],
                role: role,
                assetsByFilenameAndRole: assetsByFilenameAndRole,
                assetsByFilename: assetsByFilename,
                assetsByStemAndRole: assetsByStemAndRole,
                assetsByStem: assetsByStem
            )
            guard let resolvedAsset else { continue }

            if musicDownloadJobs[index].filePath != resolvedAsset.filePath {
                musicDownloadJobs[index].filePath = resolvedAsset.filePath
                musicDownloadJobs[index].waveformSamples = nil
                didChange = true
            }

            if completedMusicDownloadFileURL(for: musicDownloadJobs[index]) == nil {
                musicDownloadJobs[index].status = .succeeded(URL(fileURLWithPath: resolvedAsset.filePath).lastPathComponent)
                musicDownloadJobs[index].downloadProgress = 1
                didChange = true
            }
        }

        if didChange {
            saveProjectData()
        }
    }

    func resolvedMusicDownloadAsset(
        for job: MusicDownloadJob,
        role: LocalMusicAsset.Role,
        assetsByFilenameAndRole: [MusicDownloadAssetLookupKey: LocalMusicAsset],
        assetsByFilename: [String: LocalMusicAsset],
        assetsByStemAndRole: [MusicDownloadAssetLookupKey: LocalMusicAsset],
        assetsByStem: [String: LocalMusicAsset]
    ) -> LocalMusicAsset? {
        for candidate in musicDownloadFilenameCandidates(for: job) {
            let roleKey = MusicDownloadAssetLookupKey(filename: candidate, role: role.rawValue)
            if let asset = assetsByFilenameAndRole[roleKey] ?? assetsByFilename[candidate] {
                return asset
            }

            let stem = URL(fileURLWithPath: candidate).deletingPathExtension().lastPathComponent
            guard !stem.isEmpty else { continue }
            let stemRoleKey = MusicDownloadAssetLookupKey(filename: stem, role: role.rawValue)
            if let asset = assetsByStemAndRole[stemRoleKey] ?? assetsByStem[stem] {
                return asset
            }
        }
        return nil
    }

    func musicDownloadFilenameCandidates(for job: MusicDownloadJob) -> [String] {
        var candidates: [String] = []
        if let filePath = job.filePath {
            candidates.append(URL(fileURLWithPath: filePath).lastPathComponent)
        }
        if case let .succeeded(filename) = job.status {
            candidates.append(URL(fileURLWithPath: filename).lastPathComponent)
        }

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    func completedMusicDownloadFileURL(for job: MusicDownloadJob) -> URL? {
        guard
            case .succeeded = job.status,
            let filePath = job.filePath,
            FileManager.default.fileExists(atPath: filePath)
        else { return nil }
        return URL(fileURLWithPath: filePath)
    }

    nonisolated static func localMusicRole(for type: MusicDownloadJob.DownloadType) -> LocalMusicAsset.Role {
        switch type {
        case .original:
            return .original
        case .instrumental:
            return .instrumental
        }
    }

    nonisolated struct MusicDownloadAssetLookupKey: Hashable {
        var filename: String
        var role: String
    }

    func annotations(for video: VideoItem) -> [AnnotationItem] {
        annotationsByVideoPath[video.url.path, default: []]
    }

    func audioClips(for video: VideoItem) -> [AudioClipItem] {
        audioClipsByVideoPath[video.url.path, default: []]
    }

    func selectedVideo(for path: String) -> VideoItem? {
        videos.first { $0.url.path == path }
    }

    func selectVideo(_ video: VideoItem, autoplay: Bool) {
        noteTransientMediaAccess(for: video)
        PerformanceDiagnostics.mark("select video", path: video.url.path)
        loadMetadataIfNeeded(for: video, priority: .userInitiated, allowThumbnailGeneration: true)
        loadWaveform(for: video)
        loadFrameStrip(for: video)
        loadCachedSceneCuts(for: video)
        shouldAutoplaySelectedVideo = autoplay
        selectedVideo = video
        selectedVideoSelectionID = UUID()
    }

    func selectVideo(path: String, autoplay: Bool = false) {
        guard let video = selectedVideo(for: path) else { return }
        selectVideo(video, autoplay: autoplay)
    }

    func setSort(option: VideoSortOption) {
        sortOption = option
    }

    func setSort(direction: VideoSortDirection) {
        sortDirection = direction
    }

    func startExternalServiceSelfCheck(force: Bool = true) {
        startExternalServiceSelfCheck(force: force, repairMode: .afterFailure)
    }

    private func startExternalServiceSelfCheck(
        force: Bool,
        repairMode: LibraryStore.DownloaderSelfCheckRepairMode
    ) {
        guard downloaderSelfCheckTask == nil else { return }
        if !force,
           Self.isDownloaderSelfCheckFresh(downloaderSelfCheckReport),
           downloaderSelfCheckReport.status == .succeeded,
           let ytdlpPath = downloaderSelfCheckReport.ytdlpPath,
           FileManager.default.isExecutableFile(atPath: ytdlpPath) {
            return
        }

        let startedAt = Date()
        updateDownloaderSelfCheckReport(DownloaderSelfCheckReport(
            status: .running,
            checkedAt: startedAt,
            message: "正在检查 yt-dlp 可用性",
            progress: 0.01
        ))

        downloaderSelfCheckTask = Task { [weak self] in
            let report = await Self.runDownloaderSelfCheck(
                startedAt: startedAt,
                repairMode: repairMode,
                progressHandler: { [weak self] progressReport in
                    Task { @MainActor [weak self] in
                        guard let self, self.downloaderSelfCheckReport.isRunning else { return }
                        self.updateDownloaderSelfCheckReport(progressReport)
                    }
                }
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updateDownloaderSelfCheckReport(report)
                self.downloaderSelfCheckTask = nil
            }
        }
    }

    func prepareExternalServiceWork() {
        prewarmSavedCollectionCookieCache()
    }

    func startExternalServiceSelfCheckPreflightIfNeeded() {
        guard downloaderSelfCheckTask == nil else { return }
        if let lastExternalSelfCheckPreflightAt,
           Date().timeIntervalSince(lastExternalSelfCheckPreflightAt) < Self.externalSelfCheckPreflightCooldown {
            return
        }
        lastExternalSelfCheckPreflightAt = Date()
        startExternalServiceSelfCheck(force: false)
    }

    func updateDownloaderSelfCheckReport(_ report: DownloaderSelfCheckReport) {
        downloaderSelfCheckReport = report
        Self.saveDownloaderSelfCheckReport(report)
    }

}
