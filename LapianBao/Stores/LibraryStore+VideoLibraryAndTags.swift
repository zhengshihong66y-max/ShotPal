//
//  LibraryStore+VideoLibraryAndTags.swift
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
    func scanVideos(in folder: URL) {
        let organized = Self.organizeVideoFiles(in: folder)
        applyScannedVideos(
            in: folder,
            urls: organized.urls,
            deferProjectDataLoad: false,
            videoPathRemap: organized.pathRemap,
            videoFolderTagsByPath: organized.folderTagsByPath
        )
    }

    func applyScannedVideos(in folder: URL, urls: [URL]) {
        applyScannedVideos(
            in: folder,
            urls: urls,
            deferProjectDataLoad: false,
            videoPathRemap: [:],
            videoFolderTagsByPath: [:]
        )
    }

    func applyScannedVideos(
        in folder: URL,
        urls: [URL],
        deferProjectDataLoad: Bool,
        projectDataLoadDelay: TimeInterval = 0,
        selectFirstVideo: Bool = true,
        metadataPrefetchLimit: Int? = nil,
        metadataWorkerCount: Int = 3,
        metadataBackgroundPrefetchDelay: TimeInterval? = nil,
        videoPathRemap: [String: String] = [:],
        videoFolderTagsByPath: [String: [String]] = [:],
        cachedMetadataByPath: [String: VideoMetadata] = [:],
        cachedThumbnailDataByPath: [String: Data] = [:],
        cachedPlaybackSupportByPath: [String: VideoPlaybackSupport] = [:],
        preservedSelectionPath: String? = nil,
        preservedSelectedTags: Set<String>? = nil
    ) {
        flushProjectDataSave()
        projectLoadTask?.cancel()
        projectLoadTask = nil
        projectDataLoadState = .idle
        projectDataDirty = false
        startupAutomationLibraryPath = nil
        libraryURL = folder
        UserDefaults.standard.set(folder.path, forKey: lastLibraryPathKey)
        Self.ensureMediaFolders(in: folder)
        pendingVideoPathRemap = videoPathRemap
        pendingVideoFolderTagsByPath = videoFolderTagsByPath

        let scannedVideos = urls
            .filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            .map(VideoItem.init(url:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let previousMetadataByPath = metadataByVideoPath
        let previousThumbnailDataByPath = thumbnailDataByVideoPath
        let previousPlaybackSupportByPath = playbackSupportByVideoPath
        let metadataVideos = metadataPrefetchLimit.map {
            Array(scannedVideos.prefix(max(0, $0)))
        } ?? scannedVideos
        metadataByVideoPath = Self.fileResourceMetadataByPath(for: scannedVideos, preserving: previousMetadataByPath)
        hydrateCachedVideoRenderState(
            for: scannedVideos,
            previousMetadataByPath: previousMetadataByPath,
            previousThumbnailDataByPath: previousThumbnailDataByPath,
            previousPlaybackSupportByPath: previousPlaybackSupportByPath,
            cachedMetadataByPath: cachedMetadataByPath,
            cachedThumbnailDataByPath: cachedThumbnailDataByPath,
            cachedPlaybackSupportByPath: cachedPlaybackSupportByPath
        )
        videos = scannedVideos

        if let preservedSelectionPath,
           let preservedVideo = videos.first(where: { $0.url.path == preservedSelectionPath }) {
            selectVideo(preservedVideo, autoplay: false)
        } else if selectFirstVideo, let firstVideo = videos.first {
            selectVideo(firstVideo, autoplay: false)
        } else {
            selectedVideo = nil
            shouldAutoplaySelectedVideo = false
            selectedVideoSelectionID = UUID()
        }
        selectedTags = preservedSelectedTags ?? []
        tagsByVideoPath = [:]
        sourceInfoByVideoPath = [:]
        frameStripByVideoPath = [:]
        frameStripImagesByVideoPath = [:]
        sceneStripImagesByVideoPath = [:]
        sceneCutProgressesByVideoPath = [:]
        sceneThumbnailVersionsByVideoPath = [:]
        frameStripTasks.values.forEach { $0.cancel() }
        frameStripTasks.removeAll()
        musicDownloadBatchTask?.cancel()
        musicDownloadBatchTask = nil
        musicDownloadTasks.values.forEach { $0.cancel() }
        musicDownloadTasks.removeAll()
        loadTagsJSON()
        loadSourceInfoJSON()
        applyPendingVideoPathMigrationToLoadedMetadata()
        if deferProjectDataLoad {
            scheduleDeferredSourceInfoAndTags(for: folder.path)
        } else {
            ensureVideoSourceInfoAndTags()
        }
        if deferProjectDataLoad {
            loadProjectDataDeferred(after: projectDataLoadDelay)
        } else {
            loadProjectData()
        }
        loadThumbnails(for: metadataVideos, workerCount: metadataWorkerCount)
        if let metadataBackgroundPrefetchDelay,
           let metadataPrefetchLimit,
           videos.count > metadataPrefetchLimit {
            scheduleDeferredMetadataLoad(
                for: Array(videos.dropFirst(max(0, metadataPrefetchLimit))),
                after: metadataBackgroundPrefetchDelay,
                workerCount: 1
            )
        }
        loadSceneCutCache()
        scanResourceLibrary(loadCachedSnapshotSynchronously: !deferProjectDataLoad)
        scheduleCurrentVideoLibrarySnapshotSave(after: 1.0)
    }

    func hydrateCachedVideoRenderState(
        for scannedVideos: [VideoItem],
        previousMetadataByPath: [String: VideoMetadata],
        previousThumbnailDataByPath: [String: Data],
        previousPlaybackSupportByPath: [String: VideoPlaybackSupport],
        cachedMetadataByPath: [String: VideoMetadata],
        cachedThumbnailDataByPath: [String: Data],
        cachedPlaybackSupportByPath: [String: VideoPlaybackSupport]
    ) {
        let scannedPaths = Set(scannedVideos.map { $0.url.path })
        thumbnailDataByVideoPath = previousThumbnailDataByPath.filter { scannedPaths.contains($0.key) }
        thumbnailImageByVideoPath = thumbnailDataByVideoPath.compactMapValues(Self.decodedThumbnailImage(from:))
        durationByVideoPath = [:]
        playbackSupportByVideoPath = previousPlaybackSupportByPath.filter { scannedPaths.contains($0.key) }

        for video in scannedVideos {
            let path = video.url.path
            let metadata = cachedMetadataByPath[path] ?? previousMetadataByPath[path]
            if let metadata,
               Self.cachedVideoMetadata(metadata, matchesFileAt: video.url) {
                metadataByVideoPath[path] = Self.fileResourceMetadata(for: video.url, preserving: metadata)
                if let duration = metadata.duration {
                    durationByVideoPath[path] = duration
                }
            }

            if let thumbnailData = cachedThumbnailDataByPath[path] ?? previousThumbnailDataByPath[path],
               Self.cachedVideoMetadata(metadataByVideoPath[path], matchesFileAt: video.url) {
                thumbnailDataByVideoPath[path] = thumbnailData
                if let image = Self.decodedThumbnailImage(from: thumbnailData) {
                    thumbnailImageByVideoPath[path] = image
                }
            }

            if let playbackSupport = cachedPlaybackSupportByPath[path] ?? previousPlaybackSupportByPath[path],
               Self.cachedVideoMetadata(metadataByVideoPath[path], matchesFileAt: video.url) {
                playbackSupportByVideoPath[path] = playbackSupport
            }
        }
    }

    func saveCurrentVideoLibrarySnapshot() {
        guard let snapshot = currentVideoLibrarySnapshot() else { return }
        Task.detached(priority: .utility) {
            Self.saveCachedVideoOrganization(snapshot.result, in: snapshot.libraryURL)
        }
    }

    func scheduleCurrentVideoLibrarySnapshotSave(after delay: TimeInterval = 2.0) {
        guard libraryURL != nil else { return }
        videoLibrarySnapshotNeedsSave = true
        guard videoLibrarySnapshotSaveTask == nil else { return }

        videoLibrarySnapshotSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.videoLibrarySnapshotSaveTask = nil
            guard self.videoLibrarySnapshotNeedsSave else { return }
            self.videoLibrarySnapshotNeedsSave = false
            self.saveCurrentVideoLibrarySnapshot()
        }
    }

    func flushCurrentVideoLibrarySnapshot() {
        videoLibrarySnapshotSaveTask?.cancel()
        videoLibrarySnapshotSaveTask = nil
        videoLibrarySnapshotNeedsSave = false
        guard let snapshot = currentVideoLibrarySnapshot() else { return }
        Self.saveCachedVideoOrganization(snapshot.result, in: snapshot.libraryURL)
    }

    private func currentVideoLibrarySnapshot() -> (libraryURL: URL, result: VideoOrganizationResult)? {
        guard let libraryURL, !videos.isEmpty else { return nil }

        let currentPaths = Set(videos.map { $0.url.path })
        let urlsByPath = Dictionary(uniqueKeysWithValues: videos.map { ($0.url.path, $0.url) })
        let folderTagsByPath = pendingVideoFolderTagsByPath.filter { currentPaths.contains($0.key) }
        let metadataByPath = metadataByVideoPath.filter { currentPaths.contains($0.key) }
        let thumbnailDataByPath = thumbnailDataByVideoPath.filter { currentPaths.contains($0.key) }
        let playbackSupportByPath = playbackSupportByVideoPath.filter { currentPaths.contains($0.key) }

        let urls = urlsByPath.values
            .filter { Self.supportedVideoExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let snapshotPaths = Set(urls.map(\.path))

        return (
            libraryURL,
            VideoOrganizationResult(
                urls: urls,
                pathRemap: [:],
                folderTagsByPath: folderTagsByPath.filter { snapshotPaths.contains($0.key) },
                metadataByPath: metadataByPath.filter { snapshotPaths.contains($0.key) },
                thumbnailDataByPath: thumbnailDataByPath.filter { snapshotPaths.contains($0.key) },
                playbackSupportByPath: playbackSupportByPath.filter { snapshotPaths.contains($0.key) }
            )
        )
    }

    nonisolated struct VideoOrganizationResult: Sendable {
        var urls: [URL]
        var pathRemap: [String: String]
        var folderTagsByPath: [String: [String]]
        var metadataByPath: [String: VideoMetadata]
        var thumbnailDataByPath: [String: Data]
        var playbackSupportByPath: [String: VideoPlaybackSupport]

        init(
            urls: [URL],
            pathRemap: [String: String],
            folderTagsByPath: [String: [String]],
            metadataByPath: [String: VideoMetadata] = [:],
            thumbnailDataByPath: [String: Data] = [:],
            playbackSupportByPath: [String: VideoPlaybackSupport] = [:]
        ) {
            self.urls = urls
            self.pathRemap = pathRemap
            self.folderTagsByPath = folderTagsByPath
            self.metadataByPath = metadataByPath
            self.thumbnailDataByPath = thumbnailDataByPath
            self.playbackSupportByPath = playbackSupportByPath
        }
    }

    nonisolated struct CachedVideoLibrary: Codable, Sendable {
        var version: Int
        var generatedAt: Date
        var entries: [CachedVideoEntry]
    }

    nonisolated struct CachedVideoEntry: Codable, Sendable {
        var relativePath: String
        var folderTags: [String]
        var metadata: VideoMetadata?
        var thumbnailData: Data?
        var playbackSupport: VideoPlaybackSupport?
    }

    nonisolated static func organizeVideoFiles(in folder: URL) -> VideoOrganizationResult {
        ensureMediaFolders(in: folder)

        let fm = FileManager.default
        let videoRoot = mediaFolder(in: folder, named: videoFolderName)
        try? fm.createDirectory(at: videoRoot, withIntermediateDirectories: true)

        var urls: [URL] = []
        var pathRemap: [String: String] = [:]
        var folderTagsByPath: [String: [String]] = [:]
        var assetTagsByPath = loadResourceAssetTags(in: folder)
        var didUpdateAssetTags = false

        for originalURL in allVideoCandidateURLs(in: folder) {
            guard !isVideoLibraryExcludedURL(originalURL, libraryURL: folder) else { continue }

            let originalPath = originalURL.standardizedFileURL.path
            let folderTags = videoFolderTags(for: originalURL, libraryURL: folder, videoRoot: videoRoot)
            let audioFolderName = audioDestinationFolderName(forVideoContainer: originalURL)
            let targetRoot = audioFolderName.map { mediaFolder(in: folder, named: $0) } ?? videoRoot
            let targetURL = flattenedDestinationURL(for: originalURL, targetRoot: targetRoot)
            let finalURL: URL

            if originalPath == targetURL.standardizedFileURL.path {
                finalURL = originalURL
            } else {
                try? fm.createDirectory(at: targetRoot, withIntermediateDirectories: true)
                do {
                    try fm.moveItem(at: originalURL, to: targetURL)
                    finalURL = targetURL
                    pathRemap[originalPath] = finalURL.path
                } catch {
                    finalURL = originalURL
                }
            }

            if let audioFolderName {
                let oldRelativePath = libraryRelativePath(for: originalURL, base: folder)
                let newRelativePath = libraryRelativePath(for: finalURL, base: folder)
                let oldTags = assetTagsByPath.removeValue(forKey: oldRelativePath) ?? []
                let baseTags = oldTags.filter { ![videoFolderName, musicExportFolderName, soundEffectExportFolderName].contains($0) }
                let kindTags = audioFolderName == musicExportFolderName
                    ? [musicExportFolderName, inferredMusicRole(from: finalURL).label]
                    : [soundEffectExportFolderName, "音效"]
                assetTagsByPath[newRelativePath] = cleanedResourceTags(kindTags + baseTags + folderTags)
                didUpdateAssetTags = true
                continue
            }

            if !folderTags.isEmpty {
                folderTagsByPath[finalURL.path] = folderTags
            }
            urls.append(finalURL)
        }

        if didUpdateAssetTags {
            saveResourceAssetTags(assetTagsByPath, in: folder)
        }

        removeEmptyDirectories(under: videoRoot, preserving: [videoRoot])
        let importsRoot = folder.appendingPathComponent("Imports", isDirectory: true)
        removeEmptyDirectories(under: importsRoot, preserving: [])
        removeDirectoryIfEmpty(importsRoot)

        urls = urls
            .filter { supportedVideoExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        let result = VideoOrganizationResult(urls: urls, pathRemap: pathRemap, folderTagsByPath: folderTagsByPath)
        saveCachedVideoOrganization(result, in: folder)
        return result
    }

    nonisolated static func videoURLs(in folder: URL) -> [URL] {
        organizeVideoFiles(in: folder).urls
    }

    nonisolated static func quickVideoOrganizationSnapshot(in folder: URL) -> VideoOrganizationResult {
        ensureMediaFolders(in: folder)

        let videoRoot = mediaFolder(in: folder, named: videoFolderName)
        var urls: [URL] = []
        var folderTagsByPath: [String: [String]] = [:]

        for originalURL in quickVideoSnapshotCandidateURLs(in: folder) {
            guard !isVideoLibraryExcludedURL(originalURL, libraryURL: folder) else { continue }
            guard audioDestinationFolderName(forVideoContainer: originalURL) == nil else { continue }

            let folderTags = videoFolderTags(for: originalURL, libraryURL: folder, videoRoot: videoRoot)
            if !folderTags.isEmpty {
                folderTagsByPath[originalURL.path] = folderTags
            }
            urls.append(originalURL)
        }

        urls = urls
            .filter { supportedVideoExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return VideoOrganizationResult(urls: urls, pathRemap: [:], folderTagsByPath: folderTagsByPath)
    }

    nonisolated static func quickVideoSnapshotCandidateURLs(in folder: URL) -> [URL] {
        let videoRoot = mediaFolder(in: folder, named: videoFolderName)
        let organizedURLs = allVideoCandidateURLs(in: videoRoot)
        return organizedURLs.isEmpty ? allVideoCandidateURLs(in: folder) : organizedURLs
    }

    nonisolated static func videoLibraryCacheURL(in libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent(".lapianbao_videos_cache.json")
    }

    nonisolated static func loadCachedVideoLibrary(in libraryURL: URL) -> CachedVideoLibrary? {
        let url = videoLibraryCacheURL(in: libraryURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard
            let data = try? Data(contentsOf: url),
            let cache = try? decoder.decode(CachedVideoLibrary.self, from: data),
            cache.version == videoLibraryCacheVersion
        else { return nil }
        return cache
    }

    nonisolated static func loadCachedVideoOrganization(in libraryURL: URL) -> VideoOrganizationResult? {
        guard let cache = loadCachedVideoLibrary(in: libraryURL) else { return nil }

        let fm = FileManager.default
        var urls: [URL] = []
        var folderTagsByPath: [String: [String]] = [:]
        var metadataByPath: [String: VideoMetadata] = [:]
        var thumbnailDataByPath: [String: Data] = [:]
        var playbackSupportByPath: [String: VideoPlaybackSupport] = [:]
        for entry in cache.entries {
            let fileURL = libraryURL.appendingPathComponent(entry.relativePath)
            let path = fileURL.path
            guard supportedVideoExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            guard fm.fileExists(atPath: path) else { continue }
            urls.append(fileURL)
            if !entry.folderTags.isEmpty {
                folderTagsByPath[path] = entry.folderTags
            }
            if let metadata = entry.metadata,
               cachedVideoMetadata(metadata, matchesFileAt: fileURL) {
                metadataByPath[path] = fileResourceMetadata(for: fileURL, preserving: metadata)
                if let thumbnailData = entry.thumbnailData {
                    thumbnailDataByPath[path] = thumbnailData
                }
                if let playbackSupport = entry.playbackSupport {
                    playbackSupportByPath[path] = playbackSupport
                }
            }
        }

        if !cache.entries.isEmpty && urls.isEmpty {
            return nil
        }

        let displayURLs = preferredVideoDisplayURLs(from: urls, libraryURL: libraryURL)

        return VideoOrganizationResult(
            urls: displayURLs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending },
            pathRemap: [:],
            folderTagsByPath: folderTagsByPath,
            metadataByPath: metadataByPath,
            thumbnailDataByPath: thumbnailDataByPath,
            playbackSupportByPath: playbackSupportByPath
        )
    }

    nonisolated static func preferredVideoDisplayURLs(from urls: [URL], libraryURL: URL) -> [URL] {
        let videoRoot = mediaFolder(in: libraryURL, named: videoFolderName).standardizedFileURL
        let videoRootPath = videoRoot.path.hasSuffix("/") ? videoRoot.path : videoRoot.path + "/"
        let organizedURLs = urls.filter { $0.standardizedFileURL.path.hasPrefix(videoRootPath) }
        let candidates = organizedURLs.isEmpty ? urls : organizedURLs
        var seenPaths = Set<String>()

        return candidates.filter { url in
            seenPaths.insert(url.standardizedFileURL.path).inserted
        }
    }

    nonisolated static func saveCachedVideoOrganization(_ result: VideoOrganizationResult, in libraryURL: URL) {
        var existingEntriesByRelativePath: [String: CachedVideoEntry] = [:]
        for entry in loadCachedVideoLibrary(in: libraryURL)?.entries ?? [] {
            existingEntriesByRelativePath[entry.relativePath] = entry
        }
        let entries = result.urls.map { url in
            let relativePath = libraryRelativePath(for: url, base: libraryURL)
            let existingEntry = existingEntriesByRelativePath[relativePath]
            let metadata = result.metadataByPath[url.path] ?? existingEntry?.metadata
            let hasFreshMetadata = cachedVideoMetadata(metadata, matchesFileAt: url)
            let freshMetadata = hasFreshMetadata ? metadata : nil
            let thumbnailData = result.thumbnailDataByPath[url.path] ?? existingEntry?.thumbnailData
            let playbackSupport = result.playbackSupportByPath[url.path] ?? existingEntry?.playbackSupport
            return CachedVideoEntry(
                relativePath: relativePath,
                folderTags: result.folderTagsByPath[url.path, default: []],
                metadata: freshMetadata,
                thumbnailData: hasFreshMetadata ? thumbnailData : nil,
                playbackSupport: hasFreshMetadata ? playbackSupport : nil
            )
        }
        let cache = CachedVideoLibrary(
            version: videoLibraryCacheVersion,
            generatedAt: Date(),
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: videoLibraryCacheURL(in: libraryURL), options: Data.WritingOptions.atomic)
    }

    nonisolated static func cachedVideoMetadata(_ metadata: VideoMetadata?, matchesFileAt url: URL) -> Bool {
        guard let metadata else { return false }
        return cachedVideoMetadata(metadata, matchesFileAt: url)
    }

    nonisolated static func cachedVideoMetadata(_ metadata: VideoMetadata, matchesFileAt url: URL) -> Bool {
        let current = fileResourceMetadata(for: url)
        if let cachedSize = metadata.fileSize,
           let currentSize = current.fileSize,
           cachedSize != currentSize {
            return false
        }
        if let cachedModifiedAt = metadata.modifiedAt,
           let currentModifiedAt = current.modifiedAt,
           abs(cachedModifiedAt.timeIntervalSince(currentModifiedAt)) > 1 {
            return false
        }
        return true
    }

    nonisolated static func allVideoCandidateURLs(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let urls = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

        return urls
            .filter { supportedVideoExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    nonisolated static func isVideoLibraryExcludedURL(_ url: URL, libraryURL: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let excludedRoots = [
            mediaFolder(in: libraryURL, named: musicExportFolderName),
            mediaFolder(in: libraryURL, named: soundEffectExportFolderName),
            mediaFolder(in: libraryURL, named: imageExportFolderName),
            exportFolder(in: libraryURL, named: musicExportFolderName),
            exportFolder(in: libraryURL, named: legacySoundEffectExportFolderName),
            exportFolder(in: libraryURL, named: imageExportFolderName)
        ].map { $0.standardizedFileURL.path.hasSuffix("/") ? $0.standardizedFileURL.path : $0.standardizedFileURL.path + "/" }

        return excludedRoots.contains { path.hasPrefix($0) }
    }

    nonisolated static func videoFolderTags(for url: URL, libraryURL: URL, videoRoot: URL) -> [String] {
        let parentURL = url.deletingLastPathComponent().standardizedFileURL
        let parentPath = parentURL.path
        let videoRootPath = videoRoot.standardizedFileURL.path
        let libraryPath = libraryURL.standardizedFileURL.path

        let rawTags: [String]
        if parentPath.hasPrefix(videoRootPath + "/") {
            rawTags = resourceFolderTags(for: url, under: videoRoot)
        } else if parentPath == libraryPath {
            rawTags = []
        } else {
            rawTags = resourceFolderTags(for: url, under: libraryURL)
        }

        let ignored = Set([videoFolderName, "Imports", "Import", "import", "download", "downloads", "Downloaded Video", "Downloaded Videos"])
        return cleanedResourceTags(rawTags).filter { !ignored.contains($0) }
    }

    nonisolated static func audioDestinationFolderName(forVideoContainer url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !name.isEmpty else { return nil }

        let soundEffectHints = [
            "sound effect", "free sounds", "sfx vault", "foley",
            "快门", "电门", "枪", "跺脚", "闪回", "音效"
        ]
        if soundEffectHints.contains(where: { name.contains($0) }) {
            return soundEffectExportFolderName
        }

        let musicHints = [
            "official music video", "official mv", "music video",
            "instrumental", "karaoke", "伴奏", "off vocal", "off-vocal"
        ]
        if musicHints.contains(where: { name.contains($0) }) {
            return musicExportFolderName
        }

        return nil
    }

    nonisolated struct ResourceLibrarySnapshot: Codable, Sendable {
        var music: [LocalMusicAsset]
        var audio: [LocalAudioAsset]
    }

    nonisolated static func resourceLibraryCacheURL(in libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent(".lapianbao_resource_cache.json")
    }

    nonisolated static func loadCachedResourceLibrarySnapshot(in libraryURL: URL) -> ResourceLibrarySnapshot? {
        let url = resourceLibraryCacheURL(in: libraryURL)
        guard
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(ResourceLibrarySnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    nonisolated static func saveCachedResourceLibrarySnapshot(_ snapshot: ResourceLibrarySnapshot, in libraryURL: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: resourceLibraryCacheURL(in: libraryURL), options: .atomic)
    }

    nonisolated static func quickResourceLibrarySnapshot(in libraryURL: URL) -> ResourceLibrarySnapshot {
        ensureMediaFolders(in: libraryURL)

        let musicRoot = mediaFolder(in: libraryURL, named: musicExportFolderName)
        let audioRoot = mediaFolder(in: libraryURL, named: soundEffectExportFolderName)
        let legacyMusicRoot = exportFolder(in: libraryURL, named: musicExportFolderName)
        let legacyAudioRoot = exportFolder(in: libraryURL, named: legacySoundEffectExportFolderName)
        let persistedAssetTags = loadResourceAssetTags(in: libraryURL)

        let musicFiles = collectMediaFiles(
            sourceRoots: [musicRoot, legacyMusicRoot],
            extensions: Set(supportedAudioExtensions + supportedVideoExtensions),
            extraTagsBySourcePath: [legacyMusicRoot.path: ["导出"]]
        )
        let audioFiles = collectMediaFiles(
            sourceRoots: [audioRoot, legacyAudioRoot],
            extensions: Set(supportedAudioExtensions + supportedVideoExtensions),
            extraTagsBySourcePath: [legacyAudioRoot.path: ["导出"]],
            skipGeneratedAudioClipFiles: true
        )

        let music: [LocalMusicAsset] = musicFiles.map { entry in
            let role = inferredMusicRole(from: entry.url)
            let relativePath = libraryRelativePath(for: entry.url, base: libraryURL)
            let tags = cleanedResourceTags(
                [musicExportFolderName, role.label] +
                (persistedAssetTags[relativePath] ?? []) +
                entry.tags
            )
            return LocalMusicAsset(
                filePath: entry.url.path,
                title: entry.url.deletingPathExtension().lastPathComponent,
                fileExtension: entry.url.pathExtension.lowercased(),
                role: role,
                tags: tags,
                duration: 0,
                fileSize: entry.fileSize,
                modifiedAt: entry.modifiedAt
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let audio: [LocalAudioAsset] = audioFiles.map { entry in
            let relativePath = libraryRelativePath(for: entry.url, base: libraryURL)
            let tags = cleanedResourceTags(
                [soundEffectExportFolderName, "音效"] +
                (persistedAssetTags[relativePath] ?? []) +
                entry.tags
            )
            return LocalAudioAsset(
                filePath: entry.url.path,
                title: entry.url.deletingPathExtension().lastPathComponent,
                fileExtension: entry.url.pathExtension.lowercased(),
                tags: tags,
                duration: 0,
                fileSize: entry.fileSize,
                modifiedAt: entry.modifiedAt
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        return ResourceLibrarySnapshot(music: music, audio: audio)
    }

    nonisolated static func scanResourceLibrarySnapshot(in libraryURL: URL) async -> ResourceLibrarySnapshot {
        return await Task.detached(priority: .utility) {
            ensureMediaFolders(in: libraryURL)

            let musicRoot = mediaFolder(in: libraryURL, named: musicExportFolderName)
            let audioRoot = mediaFolder(in: libraryURL, named: soundEffectExportFolderName)
            let legacyMusicRoot = exportFolder(in: libraryURL, named: musicExportFolderName)
            let legacyAudioRoot = exportFolder(in: libraryURL, named: legacySoundEffectExportFolderName)
            var persistedAssetTags = loadResourceAssetTags(in: libraryURL)

            let musicFiles = flattenMediaFiles(
                sourceRoots: [musicRoot, legacyMusicRoot],
                targetRoot: musicRoot,
                extensions: Set(supportedAudioExtensions + supportedVideoExtensions),
                extraTagsBySourcePath: [legacyMusicRoot.path: ["导出"]],
                deleteDuplicateFiles: true
            )
            let audioFiles = flattenMediaFiles(
                sourceRoots: [audioRoot, legacyAudioRoot],
                targetRoot: audioRoot,
                extensions: Set(supportedAudioExtensions + supportedVideoExtensions),
                extraTagsBySourcePath: [legacyAudioRoot.path: ["导出"]],
                skipGeneratedAudioClipFiles: true,
                deleteTinyGeneratedAudioClipFiles: true
            )

            let liveResourcePaths = Set((musicFiles + audioFiles).map {
                libraryRelativePath(for: $0.url, base: libraryURL)
            })
            persistedAssetTags = persistedAssetTags.filter { relativePath, _ in
                if relativePath.hasPrefix("\(musicExportFolderName)/") ||
                    relativePath.hasPrefix("\(soundEffectExportFolderName)/") {
                    return liveResourcePaths.contains(relativePath)
                }
                return true
            }

            let music: [LocalMusicAsset] = musicFiles.map { entry -> LocalMusicAsset in
                let role = inferredMusicRole(from: entry.url)
                let relativePath = libraryRelativePath(for: entry.url, base: libraryURL)
                let tags = cleanedResourceTags(
                    [musicExportFolderName, role.label] +
                    (persistedAssetTags[relativePath] ?? []) +
                    entry.tags
                )
                persistedAssetTags[relativePath] = tags
                return LocalMusicAsset(
                    filePath: entry.url.path,
                    title: entry.url.deletingPathExtension().lastPathComponent,
                    fileExtension: entry.url.pathExtension.lowercased(),
                    role: role,
                    tags: tags,
                    duration: 0,
                    fileSize: entry.fileSize,
                    modifiedAt: entry.modifiedAt
                )
            }
            .sorted { (lhs: LocalMusicAsset, rhs: LocalMusicAsset) in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

            let audio: [LocalAudioAsset] = audioFiles.map { entry -> LocalAudioAsset in
                let relativePath = libraryRelativePath(for: entry.url, base: libraryURL)
                let tags = cleanedResourceTags(
                    [soundEffectExportFolderName, "音效"] +
                    (persistedAssetTags[relativePath] ?? []) +
                    entry.tags
                )
                persistedAssetTags[relativePath] = tags
                return LocalAudioAsset(
                    filePath: entry.url.path,
                    title: entry.url.deletingPathExtension().lastPathComponent,
                    fileExtension: entry.url.pathExtension.lowercased(),
                    tags: tags,
                    duration: 0,
                    fileSize: entry.fileSize,
                    modifiedAt: entry.modifiedAt
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            saveResourceAssetTags(persistedAssetTags, in: libraryURL)
            let snapshot = ResourceLibrarySnapshot(music: music, audio: audio)
            saveCachedResourceLibrarySnapshot(snapshot, in: libraryURL)
            Task.detached(priority: .background) {
                ResourceLibrarySQLite.write(libraryURL: libraryURL, music: music, audio: audio)
            }
            return snapshot
        }.value
    }

    nonisolated struct FlattenedResourceFile: Sendable {
        var url: URL
        var tags: [String]
        var fileSize: Int64
        var modifiedAt: Date?
    }

    nonisolated static func collectMediaFiles(
        sourceRoots: [URL],
        extensions: Set<String>,
        extraTagsBySourcePath: [String: [String]] = [:],
        skipGeneratedAudioClipFiles: Bool = false
    ) -> [FlattenedResourceFile] {
        let fm = FileManager.default
        var results: [FlattenedResourceFile] = []
        var seenSourceRoots = Set<String>()

        for sourceRoot in sourceRoots where seenSourceRoots.insert(sourceRoot.standardizedFileURL.path).inserted {
            guard directoryExists(sourceRoot) else { continue }
            let sourceRootPath = sourceRoot.standardizedFileURL.path
            let urls = fm.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )?.compactMap { $0 as? URL } ?? []

            for url in urls {
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                if skipGeneratedAudioClipFiles, isGeneratedAudioClipFile(url) { continue }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                guard values?.isRegularFile == true else { continue }

                results.append(FlattenedResourceFile(
                    url: url,
                    tags: resourceFolderTags(for: url, under: sourceRoot) + (extraTagsBySourcePath[sourceRootPath] ?? []),
                    fileSize: Int64(values?.fileSize ?? 0),
                    modifiedAt: values?.contentModificationDate
                ))
            }
        }

        return results
    }

    nonisolated static func flattenMediaFiles(
        sourceRoots: [URL],
        targetRoot: URL,
        extensions: Set<String>,
        extraTagsBySourcePath: [String: [String]] = [:],
        skipGeneratedAudioClipFiles: Bool = false,
        deleteTinyGeneratedAudioClipFiles: Bool = false,
        deleteDuplicateFiles: Bool = false
    ) -> [FlattenedResourceFile] {
        let fm = FileManager.default
        try? fm.createDirectory(at: targetRoot, withIntermediateDirectories: true)

        var results: [FlattenedResourceFile] = []
        var retainedFileURLsBySize: [Int64: [URL]] = [:]
        var seenSourceRoots = Set<String>()
        for sourceRoot in sourceRoots where seenSourceRoots.insert(sourceRoot.standardizedFileURL.path).inserted {
            guard directoryExists(sourceRoot) else { continue }
            let sourceRootPath = sourceRoot.standardizedFileURL.path
            let discoveredURLs = fm.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )?.compactMap { $0 as? URL } ?? []
            let urls = discoveredURLs.sorted { lhs, rhs in
                let lhsPriority = flattenMediaFilePriority(for: lhs, targetRoot: targetRoot)
                let rhsPriority = flattenMediaFilePriority(for: rhs, targetRoot: targetRoot)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.standardizedFileURL.path.localizedStandardCompare(rhs.standardizedFileURL.path) == .orderedAscending
            }

            for originalURL in urls {
                guard extensions.contains(originalURL.pathExtension.lowercased()) else { continue }
                let values = try? originalURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                guard values?.isRegularFile == true else { continue }
                let fileSize = Int64(values?.fileSize ?? 0)

                if skipGeneratedAudioClipFiles,
                   isGeneratedAudioClipFile(originalURL) {
                    if deleteTinyGeneratedAudioClipFiles,
                       fileSize <= tinyGeneratedAudioClipByteLimit {
                        try? fm.removeItem(at: originalURL)
                    }
                    continue
                }

                let parentTags = resourceFolderTags(for: originalURL, under: sourceRoot)
                let extraTags = extraTagsBySourcePath[sourceRootPath] ?? []
                if deleteDuplicateFiles,
                   let duplicateURL = exactDuplicateMediaFile(
                    of: originalURL,
                    fileSize: fileSize,
                    retainedFileURLsBySize: retainedFileURLsBySize
                   ) {
                    mergeFlattenedResourceTags(parentTags + extraTags, for: duplicateURL, in: &results)
                    try? fm.removeItem(at: originalURL)
                    continue
                }

                let targetURL = flattenedDestinationURL(for: originalURL, targetRoot: targetRoot)
                let finalURL: URL
                if originalURL.standardizedFileURL.path == targetURL.standardizedFileURL.path {
                    finalURL = originalURL
                } else {
                    try? fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    do {
                        try fm.moveItem(at: originalURL, to: targetURL)
                        finalURL = targetURL
                    } catch {
                        finalURL = originalURL
                    }
                }

                if deleteDuplicateFiles,
                   let duplicateURL = exactDuplicateMediaFile(
                    of: finalURL,
                    fileSize: fileSize,
                    retainedFileURLsBySize: retainedFileURLsBySize
                   ) {
                    mergeFlattenedResourceTags(parentTags + extraTags, for: duplicateURL, in: &results)
                    try? fm.removeItem(at: finalURL)
                    continue
                }

                results.append(FlattenedResourceFile(
                    url: finalURL,
                    tags: parentTags + extraTags,
                    fileSize: fileSize,
                    modifiedAt: values?.contentModificationDate
                ))
                retainedFileURLsBySize[fileSize, default: []].append(finalURL)
            }

            removeEmptyDirectories(under: sourceRoot, preserving: [targetRoot, sourceRoot])
        }
        return results
    }

    nonisolated static func flattenMediaFilePriority(for url: URL, targetRoot: URL) -> Int {
        let targetPath = targetRoot.standardizedFileURL.path
        let parentPath = url.deletingLastPathComponent().standardizedFileURL.path
        if parentPath == targetPath { return 0 }

        let path = url.standardizedFileURL.path
        let targetPrefix = targetPath.hasSuffix("/") ? targetPath : targetPath + "/"
        return path.hasPrefix(targetPrefix) ? 1 : 2
    }

    nonisolated static func exactDuplicateMediaFile(
        of url: URL,
        fileSize: Int64,
        retainedFileURLsBySize: [Int64: [URL]]
    ) -> URL? {
        let path = url.standardizedFileURL.path
        for candidate in retainedFileURLsBySize[fileSize, default: []] {
            guard candidate.standardizedFileURL.path != path else { continue }
            if FileManager.default.contentsEqual(atPath: url.path, andPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    nonisolated static func mergeFlattenedResourceTags(
        _ tags: [String],
        for url: URL,
        in results: inout [FlattenedResourceFile]
    ) {
        guard !tags.isEmpty else { return }
        let path = url.standardizedFileURL.path
        guard let index = results.firstIndex(where: { $0.url.standardizedFileURL.path == path }) else { return }
        results[index].tags = cleanedResourceTags(results[index].tags + tags)
    }

    nonisolated static func flattenedDestinationURL(for sourceURL: URL, targetRoot: URL) -> URL {
        let fm = FileManager.default
        let directURL = targetRoot.appendingPathComponent(sourceURL.lastPathComponent)
        if sourceURL.deletingLastPathComponent().standardizedFileURL.path == targetRoot.standardizedFileURL.path {
            return sourceURL
        }
        if !fm.fileExists(atPath: directURL.path) {
            return directURL
        }
        if directURL.standardizedFileURL.path == sourceURL.standardizedFileURL.path {
            return directURL
        }

        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var suffix = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            let candidate = targetRoot.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    nonisolated static func resourceAssetTagsURL(in libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent(".lapianbao_asset_tags.json")
    }

    nonisolated static func libraryRelativePath(for url: URL, base libraryURL: URL) -> String {
        let base = libraryURL.standardizedFileURL.path.hasSuffix("/")
            ? libraryURL.standardizedFileURL.path
            : libraryURL.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : url.lastPathComponent
    }

    nonisolated static func loadResourceAssetTags(in libraryURL: URL) -> [String: [String]] {
        let url = resourceAssetTagsURL(in: libraryURL)
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }

        return decoded.mapValues(cleanedResourceTags)
    }

    nonisolated static func saveResourceAssetTags(_ tagsByRelativePath: [String: [String]], in libraryURL: URL) {
        let url = resourceAssetTagsURL(in: libraryURL)
        let cleaned = tagsByRelativePath
            .filter { !$0.value.isEmpty }
            .mapValues(cleanedResourceTags)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cleaned) else { return }
        try? data.write(to: url, options: .atomic)
    }

    nonisolated static func resourceFolderTags(for fileURL: URL, under rootURL: URL) -> [String] {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.deletingLastPathComponent().pathComponents
        guard fileComponents.count > rootComponents.count else { return [] }
        return Array(fileComponents.dropFirst(rootComponents.count))
    }

    nonisolated static func cleanedResourceTags(_ rawTags: [String]) -> [String] {
        var seen = Set<String>()
        return rawTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix(".") }
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    nonisolated static func inferredMusicRole(from url: URL) -> LocalMusicAsset.Role {
        let text = url.deletingPathExtension().lastPathComponent.lowercased()
        let instrumentalHints = ["伴奏", "instrumental", "karaoke", "off vocal", "off-vocal", "纯音乐", "inst"]
        if instrumentalHints.contains(where: { text.contains($0) }) {
            return .instrumental
        }
        return .original
    }

    nonisolated static func isGeneratedAudioClipFile(_ url: URL) -> Bool {
        let stem = url.deletingPathExtension().lastPathComponent
        let pattern = #"_[0-9]{2}-[0-9]{2}(?:-[0-9]{2})?-[0-9]{2}-[0-9]{2}(?:-[0-9]{2})?$"#
        return stem.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    nonisolated static func removeDirectoryIfEmpty(_ url: URL) {
        let fm = FileManager.default
        guard directoryExists(url),
              ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).isEmpty
        else { return }
        try? fm.removeItem(at: url)
    }

    nonisolated static func removeEmptyDirectories(under rootURL: URL, preserving preservedURLs: [URL]) {
        let fm = FileManager.default
        let preservedPaths = Set(preservedURLs.map { $0.standardizedFileURL.path })
        let dirs = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

        for dir in dirs.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            let path = dir.standardizedFileURL.path
            guard !preservedPaths.contains(path) else { continue }
            let values = try? dir.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            if ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).isEmpty {
                try? fm.removeItem(at: dir)
            }
        }
    }

    func removeVideo(_ video: VideoItem) {
        let path = video.url.path
        videos.removeAll { $0.url.path == path }
        if selectedVideo?.url.path == path {
            selectedVideo = nil
            shouldAutoplaySelectedVideo = false
            selectedVideoSelectionID = UUID()
        }
        tagsByVideoPath.removeValue(forKey: path)
        sourceInfoByVideoPath.removeValue(forKey: path)
        sceneCutsByVideoPath.removeValue(forKey: path)
        sceneStripImagesByVideoPath.removeValue(forKey: path)
        sceneThumbnailVersionsByVideoPath.removeValue(forKey: path)
        sceneDetectionProgress.removeValue(forKey: path)
        saveTagsJSON()
        saveSourceInfoJSON()
        saveSceneCutCache()
        scheduleCurrentVideoLibrarySnapshotSave(after: 0.5)
    }

    func addTag(to video: VideoItem) {
        addTag(tagInput, to: video)
        tagInput = ""
    }

    func addTag(_ rawTag: String, to video: VideoItem) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        var tags = tagsByVideoPath[video.url.path, default: []]
        if !tags.contains(tag) {
            tags.append(tag)
            tagsByVideoPath[video.url.path] = tags.sorted()
        }

        saveTagsJSON()
    }

    func removeTag(_ tag: String, from video: VideoItem) {
        var tags = tagsByVideoPath[video.url.path, default: []]
        tags.removeAll { $0 == tag }
        tagsByVideoPath[video.url.path] = tags
        selectedTags.remove(tag)
        saveTagsJSON()
    }

    func toggleTagSelection(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    func renameGlobalTag(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old else { return }

        var updatedTagsByVideoPath = tagsByVideoPath
        for (path, tags) in updatedTagsByVideoPath where tags.contains(old) {
            var updated = tags.filter { $0 != old }
            if !updated.contains(trimmed) { updated.append(trimmed) }
            updatedTagsByVideoPath[path] = updated.sorted()
        }
        tagsByVideoPath = updatedTagsByVideoPath

        if selectedTags.contains(old) {
            selectedTags.remove(old)
            selectedTags.insert(trimmed)
        }
        saveTagsJSON()
    }

    func removeGlobalTag(_ tag: String) {
        var updatedTagsByVideoPath = tagsByVideoPath
        for (path, tags) in updatedTagsByVideoPath where tags.contains(tag) {
            updatedTagsByVideoPath[path] = tags.filter { $0 != tag }
        }
        tagsByVideoPath = updatedTagsByVideoPath
        selectedTags.remove(tag)
        saveTagsJSON()
    }

    // MARK: - JSON 持久化

}
