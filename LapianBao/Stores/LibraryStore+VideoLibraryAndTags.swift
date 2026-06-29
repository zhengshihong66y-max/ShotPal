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
import ImageIO
import UniformTypeIdentifiers

extension LibraryStore {
    func scanVideos(in folder: URL) {
        libraryScanTask?.cancel()
        libraryScanGeneration += 1
        let scanGeneration = libraryScanGeneration
        let libraryPath = folder.path

        if restoreRecognizedLibraryIfAvailable(in: folder, scanGeneration: scanGeneration) {
            return
        }

        libraryScanProgress = LibraryScanProgress(message: "正在扫描素材结构", completed: 0, total: 1)

        libraryScanTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let organized = await Task.detached(priority: .userInitiated) {
                Self.organizeVideoFiles(in: folder)
            }.value
            guard !Task.isCancelled,
                  self.libraryScanGeneration == scanGeneration
            else { return }

            self.applyScannedVideos(
                in: folder,
                urls: organized.urls,
                deferProjectDataLoad: false,
                selectFirstVideo: false,
                metadataPrefetchLimit: 0,
                metadataWorkerCount: 0,
                videoPathRemap: organized.pathRemap,
                videoFolderTagsByPath: organized.folderTagsByPath,
                scanResources: false
            )

            await self.preloadScannedVideoMetadata(
                videos: self.videos,
                libraryPath: libraryPath,
                scanGeneration: scanGeneration
            )
            guard !Task.isCancelled,
                  self.libraryScanGeneration == scanGeneration,
                  self.libraryURL?.path == libraryPath
            else { return }

            self.libraryScanProgress = LibraryScanProgress(message: "正在识别音乐素材", completed: 0, total: 1)
            let snapshot = await Self.scanResourceLibrarySnapshot(in: folder)
            guard !Task.isCancelled,
                  self.libraryScanGeneration == scanGeneration,
                  self.libraryURL?.path == libraryPath
            else { return }

            self.applyResourceLibrarySnapshot(snapshot, libraryPath: libraryPath)
            self.lastResourceLibraryFullScanAtByPath[libraryPath] = Date()
            self.resourceLibraryScanTask?.cancel()
            self.resourceLibraryScanTask = nil
            self.resourceLibraryScanTaskLibraryPath = nil

            await self.prewarmInitialMusicCachesForLibraryScan(
                libraryPath: libraryPath,
                scanGeneration: scanGeneration
            )
            guard !Task.isCancelled,
                  self.libraryScanGeneration == scanGeneration,
                  self.libraryURL?.path == libraryPath
            else { return }

            self.flushCurrentVideoLibrarySnapshot()

            self.libraryScanProgress = LibraryScanProgress(message: "素材库扫描完成", completed: 1, total: 1)
            try? await Task.sleep(nanoseconds: 450_000_000)
            if self.libraryScanGeneration == scanGeneration {
                self.libraryScanProgress = nil
                self.libraryScanTask = nil
            }
        }
    }

    func restoreRecognizedLibraryIfAvailable(in folder: URL, scanGeneration: Int) -> Bool {
        let cachedVideos = Self.loadCachedVideoOrganization(in: folder, includeThumbnailData: false)
        let cachedResources = Self.loadCachedResourceLibrarySnapshot(in: folder)
        guard cachedVideos != nil || cachedResources != nil else { return false }

        let organization = cachedVideos ?? VideoOrganizationResult(urls: [], pathRemap: [:], folderTagsByPath: [:])
        libraryScanProgress = nil
        applyScannedVideos(
            in: folder,
            urls: organization.urls,
            deferProjectDataLoad: true,
            projectDataLoadDelay: 0,
            selectFirstVideo: false,
            metadataPrefetchLimit: Self.launchMetadataPrefetchLimit,
            metadataWorkerCount: Self.launchMetadataWorkerCount,
            metadataBackgroundPrefetchDelay: nil,
            videoPathRemap: organization.pathRemap,
            videoFolderTagsByPath: organization.folderTagsByPath,
            cachedMetadataByPath: organization.metadataByPath,
            cachedThumbnailDataByPath: organization.thumbnailDataByPath,
            cachedPlaybackSupportByPath: organization.playbackSupportByPath,
            decodeCachedThumbnailsImmediately: false,
            scanResources: false
        )

        if let cachedResources {
            applyResourceLibrarySnapshot(cachedResources, libraryPath: folder.path)
        } else {
            scanResourceLibrary(refreshMode: .cachedOnly, loadCachedSnapshotSynchronously: true)
        }

        libraryScanProgress = LibraryScanProgress(message: "正在检查音乐缓存", completed: 0, total: 1)
        libraryScanTask = Task { @MainActor [weak self] in
            guard let self,
                  self.libraryScanGeneration == scanGeneration,
                  self.libraryURL?.path == folder.path
            else { return }

            if cachedResources == nil {
                self.libraryScanProgress = LibraryScanProgress(message: "正在识别音乐素材", completed: 0, total: 1)
                let snapshot = await Self.scanResourceLibrarySnapshot(in: folder)
                guard !Task.isCancelled,
                      self.libraryScanGeneration == scanGeneration,
                      self.libraryURL?.path == folder.path
                else { return }

                self.applyResourceLibrarySnapshot(snapshot, libraryPath: folder.path)
                self.lastResourceLibraryFullScanAtByPath[folder.path] = Date()
                self.resourceLibraryScanTask?.cancel()
                self.resourceLibraryScanTask = nil
                self.resourceLibraryScanTaskLibraryPath = nil
            }

            await self.prewarmInitialMusicCachesForLibraryScan(
                libraryPath: folder.path,
                scanGeneration: scanGeneration,
                generateMissingSamples: false,
                prewarmRenderedImages: false
            )
            guard !Task.isCancelled,
                  self.libraryScanGeneration == scanGeneration,
                  self.libraryURL?.path == folder.path
            else { return }

            self.flushCurrentVideoLibrarySnapshot()
            self.libraryScanProgress = LibraryScanProgress(message: "素材库扫描完成", completed: 1, total: 1)
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard self.libraryScanGeneration == scanGeneration else { return }
            self.libraryScanProgress = nil
            self.libraryScanTask = nil
            self.scheduleRecognizedLibraryReconcile(in: folder, scanGeneration: scanGeneration)
        }
        return true
    }

    func scheduleRecognizedLibraryReconcile(in folder: URL, scanGeneration: Int) {
        let libraryPath = folder.path
        libraryScanTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.launchVideoReconcileDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            let organized = await Task.detached(priority: .utility) {
                Self.organizeVideoFiles(in: folder)
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.libraryScanGeneration == scanGeneration,
                  self.libraryURL?.path == libraryPath
            else { return }

            let selectedPath = self.selectedVideo?.url.path
            let selectedTags = self.selectedTags
            self.applyScannedVideos(
                in: folder,
                urls: organized.urls,
                deferProjectDataLoad: true,
                projectDataLoadDelay: 0,
                selectFirstVideo: false,
                metadataPrefetchLimit: Self.launchMetadataPrefetchLimit,
                metadataWorkerCount: Self.launchMetadataWorkerCount,
                metadataBackgroundPrefetchDelay: Self.launchBackgroundMetadataPrefetchDelay,
                videoPathRemap: organized.pathRemap,
                videoFolderTagsByPath: organized.folderTagsByPath,
                cachedMetadataByPath: organized.metadataByPath,
                cachedThumbnailDataByPath: organized.thumbnailDataByPath,
                cachedPlaybackSupportByPath: organized.playbackSupportByPath,
                preservedSelectionPath: selectedPath,
                preservedSelectedTags: selectedTags,
                scanResources: false
            )
            self.scanResourceLibrary(refreshMode: .deferred, loadCachedSnapshotSynchronously: false)
            if self.libraryScanGeneration == scanGeneration {
                self.libraryScanTask = nil
            }
        }
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
        selectFirstVideo: Bool = false,
        metadataPrefetchLimit: Int? = nil,
        metadataWorkerCount: Int = 3,
        metadataBackgroundPrefetchDelay: TimeInterval? = nil,
        videoPathRemap: [String: String] = [:],
        videoFolderTagsByPath: [String: [String]] = [:],
        cachedMetadataByPath: [String: VideoMetadata] = [:],
        cachedThumbnailDataByPath: [String: Data] = [:],
        cachedPlaybackSupportByPath: [String: VideoPlaybackSupport] = [:],
        preservedSelectionPath: String? = nil,
        preservedSelectedTags: Set<String>? = nil,
        decodeCachedThumbnailsImmediately: Bool = false,
        scanResources: Bool = true
    ) {
        beginLibrarySidebarMetricsBatch()
        defer { endLibrarySidebarMetricsBatch() }

        flushProjectDataSave()
        projectLoadTask?.cancel()
        projectLoadTask = nil
        projectDataLoadState = .idle
        projectDataDirty = false
        startupAutomationLibraryPath = nil
        libraryURL = folder
        AppSettings.lastLibraryPath = folder.path
        Self.ensureMediaFolders(in: folder)
        pendingVideoPathRemap = videoPathRemap
        pendingVideoFolderTagsByPath = videoFolderTagsByPath

        let scannedVideos = urls
            .filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            .map(VideoItem.init(url:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let previousMetadataByPath = metadataByVideoPath
        let previousThumbnailDataByPath = thumbnailDataByVideoPath
        let previousThumbnailImageByPath = thumbnailImageByVideoPath
        let previousPlaybackSupportByPath = playbackSupportByVideoPath
        let metadataVideos = metadataPrefetchLimit.map {
            Array(scannedVideos.prefix(max(0, $0)))
        } ?? scannedVideos
        metadataByVideoPath = Self.fileResourceMetadataByPath(for: scannedVideos, preserving: previousMetadataByPath)
        hydrateCachedVideoRenderState(
            for: scannedVideos,
            previousMetadataByPath: previousMetadataByPath,
            previousThumbnailDataByPath: previousThumbnailDataByPath,
            previousThumbnailImageByPath: previousThumbnailImageByPath,
            previousPlaybackSupportByPath: previousPlaybackSupportByPath,
            cachedMetadataByPath: cachedMetadataByPath,
            cachedThumbnailDataByPath: cachedThumbnailDataByPath,
            cachedPlaybackSupportByPath: cachedPlaybackSupportByPath,
            decodeCachedThumbnailsImmediately: decodeCachedThumbnailsImmediately
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
        persistedVideoTagPaths.removeAll()
        sourceInfoByVideoPath = [:]
        frameStripByVideoPath = [:]
        frameStripImagesByVideoPath = [:]
        sceneStripImagesByVideoPath = [:]
        sceneCutProgressesByVideoPath = [:]
        sceneThumbnailVersionsByVideoPath = [:]
        sceneDetectionErrorByVideoPath = [:]
        transientMediaCacheTrimTask?.cancel()
        transientMediaCacheTrimTask = nil
        transientMediaCacheAccessTickByPath.removeAll()
        transcriptTasks.values.forEach { $0.cancel() }
        transcriptTasks.removeAll()
        transcriptBatchTask?.cancel()
        transcriptBatchTask = nil
        isTranscriptBatchPaused = false
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
        loadThumbnails(for: metadataVideos, workerCount: metadataWorkerCount, allowThumbnailGeneration: false)
        if !decodeCachedThumbnailsImmediately {
            scheduleCachedThumbnailImageHydration(
                for: Array(scannedVideos.prefix(Self.launchCachedThumbnailHydrationLimit)),
                after: Self.launchCachedThumbnailHydrationDelay
            )
        }
        if deferProjectDataLoad && cachedThumbnailDataByPath.isEmpty {
            scheduleCachedThumbnailDataRestore(in: folder, after: Self.launchCachedThumbnailDataRestoreDelay)
        }
        if let metadataBackgroundPrefetchDelay,
           let metadataPrefetchLimit,
           videos.count > metadataPrefetchLimit {
            scheduleDeferredMetadataLoad(
                for: Array(videos.dropFirst(max(0, metadataPrefetchLimit))),
                after: metadataBackgroundPrefetchDelay,
                workerCount: 1,
                allowThumbnailGeneration: false
            )
        }
        loadSceneCutCache()
        if scanResources {
            scanResourceLibrary(
                refreshMode: deferProjectDataLoad ? .cachedOnly : .deferred,
                loadCachedSnapshotSynchronously: !deferProjectDataLoad
            )
        }
        scheduleCurrentVideoLibrarySnapshotSave(after: 1.0)
    }

    func preloadScannedVideoMetadata(
        videos: [VideoItem],
        libraryPath: String,
        scanGeneration: Int
    ) async {
        let total = videos.count
        guard total > 0 else {
            libraryScanProgress = LibraryScanProgress(message: "没有发现视频素材", completed: 1, total: 1)
            return
        }

        libraryScanProgress = LibraryScanProgress(message: "正在识别视频元数据 · 0/\(total)", completed: 0, total: total)
        let paths = Set(videos.map(\.url.path))
        thumbnailLoadingPaths.formUnion(paths)
        let metadataGeneration = thumbnailLoadGeneration
        let queue = VideoMetadataQueue(videos: videos)
        let workerCount = min(4, total)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<workerCount {
                group.addTask { [weak self, queue, paths] in
                    while !Task.isCancelled {
                        guard let video = await queue.next() else { break }
                        let path = video.url.path
                        async let metadata = Self.makeVideoMetadata(
                            for: video.url,
                            shouldGenerateThumbnail: true
                        )
                        async let playbackSupport = Self.playbackSupport(for: video.url)
                        let videoMetadata = await metadata
                        let support = await playbackSupport

                        guard !Task.isCancelled else { break }
                        await MainActor.run { [weak self] in
                            guard let self,
                                  self.libraryScanGeneration == scanGeneration,
                                  self.thumbnailLoadGeneration == metadataGeneration,
                                  self.libraryURL?.path == libraryPath,
                                  self.containsVideoPath(path)
                            else { return }

                            self.applyVideoMetadata(
                                videoMetadata,
                                playbackSupport: support,
                                for: path
                            )
                            let remaining = self.thumbnailLoadingPaths.intersection(paths).count
                            let completed = total - remaining
                            self.libraryScanProgress = LibraryScanProgress(
                                message: "正在识别视频元数据 · \(completed)/\(total)",
                                completed: completed,
                                total: total
                            )
                        }
                    }
                }
            }
        }
    }

    func hydrateCachedVideoRenderState(
        for scannedVideos: [VideoItem],
        previousMetadataByPath: [String: VideoMetadata],
        previousThumbnailDataByPath: [String: Data],
        previousThumbnailImageByPath: [String: NSImage],
        previousPlaybackSupportByPath: [String: VideoPlaybackSupport],
        cachedMetadataByPath: [String: VideoMetadata],
        cachedThumbnailDataByPath: [String: Data],
        cachedPlaybackSupportByPath: [String: VideoPlaybackSupport],
        decodeCachedThumbnailsImmediately: Bool
    ) {
        let scannedPaths = Set(scannedVideos.map { $0.url.path })
        thumbnailDataByVideoPath = previousThumbnailDataByPath.filter { scannedPaths.contains($0.key) }
        thumbnailImageByVideoPath = decodeCachedThumbnailsImmediately
            ? thumbnailDataByVideoPath.compactMapValues(Self.decodedThumbnailImage(from:))
            : previousThumbnailImageByPath.filter { scannedPaths.contains($0.key) }
        thumbnailImageRevisionByVideoPath = thumbnailImageRevisionByVideoPath.filter { scannedPaths.contains($0.key) }
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
                if decodeCachedThumbnailsImmediately,
                   let image = Self.decodedThumbnailImage(from: thumbnailData) {
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

    nonisolated struct CachedVideoLibrarySummary: Decodable, Sendable {
        var version: Int
        var entries: [CachedVideoSummaryEntry]
    }

    nonisolated struct CachedVideoSummaryEntry: Decodable, Sendable {
        var relativePath: String
        var folderTags: [String]
        var metadata: VideoMetadata?
        var playbackSupport: VideoPlaybackSupport?
    }

    nonisolated static func organizeVideoFiles(in folder: URL) -> VideoOrganizationResult {
        ensureMediaFolders(in: folder)

        let videoRoot = mediaFolder(in: folder, named: videoFolderName)
        let legacyVideoRoot = mediaFolder(in: folder, named: legacyVideoFolderName)

        var urls: [URL] = []
        var folderTagsByPath: [String: [String]] = [:]

        for originalURL in allVideoCandidateURLs(in: folder) {
            guard !isVideoLibraryExcludedURL(originalURL, libraryURL: folder) else { continue }

            let folderTags = videoFolderTags(
                for: originalURL,
                libraryURL: folder,
                videoRoot: videoRoot,
                legacyVideoRoot: legacyVideoRoot
            )
            if !folderTags.isEmpty {
                folderTagsByPath[originalURL.path] = folderTags
            }
            urls.append(originalURL)
        }

        urls = urls
            .filter { supportedVideoExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        let result = VideoOrganizationResult(urls: urls, pathRemap: [:], folderTagsByPath: folderTagsByPath)
        saveCachedVideoOrganization(result, in: folder)
        return result
    }

    nonisolated static func videoURLs(in folder: URL) -> [URL] {
        organizeVideoFiles(in: folder).urls
    }

    nonisolated static func quickVideoOrganizationSnapshot(in folder: URL) -> VideoOrganizationResult {
        ensureMediaFolders(in: folder)

        let videoRoot = mediaFolder(in: folder, named: videoFolderName)
        let legacyVideoRoot = mediaFolder(in: folder, named: legacyVideoFolderName)
        var urls: [URL] = []
        var folderTagsByPath: [String: [String]] = [:]

        for originalURL in quickVideoSnapshotCandidateURLs(in: folder) {
            guard !isVideoLibraryExcludedURL(originalURL, libraryURL: folder) else { continue }

            let folderTags = videoFolderTags(
                for: originalURL,
                libraryURL: folder,
                videoRoot: videoRoot,
                legacyVideoRoot: legacyVideoRoot
            )
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
        allVideoCandidateURLs(in: folder)
    }

    nonisolated static func videoLibraryCacheURL(in libraryURL: URL) -> URL {
        ProjectRepository.videoCacheURL(in: libraryURL)
    }

    nonisolated static func loadCachedVideoLibrary(in libraryURL: URL) -> CachedVideoLibrary? {
        let url = videoLibraryCacheURL(in: libraryURL)
        guard
            let cache = ProjectRepository.readJSON(
                CachedVideoLibrary.self,
                from: url,
                decoder: ProjectRepository.makeDecoder(dateDecodingStrategy: .iso8601)
            ),
            cache.version == videoLibraryCacheVersion
        else { return nil }
        return cache
    }

    nonisolated static func loadCachedVideoLibrarySummary(in libraryURL: URL) -> CachedVideoLibrarySummary? {
        let url = videoLibraryCacheURL(in: libraryURL)
        guard
            let cache = ProjectRepository.readJSON(
                CachedVideoLibrarySummary.self,
                from: url,
                decoder: ProjectRepository.makeDecoder(dateDecodingStrategy: .iso8601)
            ),
            cache.version == videoLibraryCacheVersion
        else { return nil }
        return cache
    }

    nonisolated static func loadCachedVideoOrganization(
        in libraryURL: URL,
        includeThumbnailData: Bool = true
    ) -> VideoOrganizationResult? {
        if includeThumbnailData {
            guard let cache = loadCachedVideoLibrary(in: libraryURL) else { return nil }
            return videoOrganizationResult(from: cache.entries, libraryURL: libraryURL)
        }
        guard let cache = loadCachedVideoLibrarySummary(in: libraryURL) else { return nil }
        return videoOrganizationResult(from: cache.entries, libraryURL: libraryURL)
    }

    nonisolated static func videoOrganizationResult(
        from entries: [CachedVideoEntry],
        libraryURL: URL
    ) -> VideoOrganizationResult? {
        let fm = FileManager.default
        var urls: [URL] = []
        var folderTagsByPath: [String: [String]] = [:]
        var metadataByPath: [String: VideoMetadata] = [:]
        var thumbnailDataByPath: [String: Data] = [:]
        var playbackSupportByPath: [String: VideoPlaybackSupport] = [:]
        for entry in entries {
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

        if !entries.isEmpty && urls.isEmpty {
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

    nonisolated static func videoOrganizationResult(
        from entries: [CachedVideoSummaryEntry],
        libraryURL: URL
    ) -> VideoOrganizationResult? {
        let fm = FileManager.default
        var urls: [URL] = []
        var folderTagsByPath: [String: [String]] = [:]
        var metadataByPath: [String: VideoMetadata] = [:]
        var playbackSupportByPath: [String: VideoPlaybackSupport] = [:]
        for entry in entries {
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
                if let playbackSupport = entry.playbackSupport {
                    playbackSupportByPath[path] = playbackSupport
                }
            }
        }

        if !entries.isEmpty && urls.isEmpty {
            return nil
        }

        let displayURLs = preferredVideoDisplayURLs(from: urls, libraryURL: libraryURL)

        return VideoOrganizationResult(
            urls: displayURLs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending },
            pathRemap: [:],
            folderTagsByPath: folderTagsByPath,
            metadataByPath: metadataByPath,
            thumbnailDataByPath: [:],
            playbackSupportByPath: playbackSupportByPath
        )
    }

    nonisolated static func preferredVideoDisplayURLs(from urls: [URL], libraryURL: URL) -> [URL] {
        var seenPaths = Set<String>()

        return urls.filter { url in
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
        try? ProjectRepository.writeJSON(
            cache,
            to: videoLibraryCacheURL(in: libraryURL),
            encoder: ProjectRepository.makeEncoder(
                outputFormatting: [.prettyPrinted, .sortedKeys],
                dateEncodingStrategy: .iso8601
            )
        )
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
            mediaFolder(in: libraryURL, named: transcriptExportFolderName),
            mediaFolder(in: libraryURL, named: legacyMusicExportFolderName),
            mediaFolder(in: libraryURL, named: legacyAudioExportFolderName),
            mediaFolder(in: libraryURL, named: legacySoundEffectExportFolderName),
            mediaFolder(in: libraryURL, named: legacyImageExportFolderName),
            mediaFolder(in: libraryURL, named: legacyTranscriptExportFolderName),
            legacyExportFolder(in: libraryURL, named: musicExportFolderName),
            legacyExportFolder(in: libraryURL, named: legacyMusicExportFolderName),
            legacyExportFolder(in: libraryURL, named: soundEffectExportFolderName),
            legacyExportFolder(in: libraryURL, named: legacySoundEffectExportFolderName),
            legacyExportFolder(in: libraryURL, named: imageExportFolderName),
            legacyExportFolder(in: libraryURL, named: legacyImageExportFolderName),
            legacyExportFolder(in: libraryURL, named: transcriptExportFolderName),
            legacyExportFolder(in: libraryURL, named: legacyTranscriptExportFolderName)
        ].map { $0.standardizedFileURL.path.hasSuffix("/") ? $0.standardizedFileURL.path : $0.standardizedFileURL.path + "/" }

        return excludedRoots.contains { path.hasPrefix($0) }
    }

    nonisolated static func videoFolderTags(
        for url: URL,
        libraryURL: URL,
        videoRoot: URL,
        legacyVideoRoot: URL? = nil
    ) -> [String] {
        let parentURL = url.deletingLastPathComponent().standardizedFileURL
        let parentPath = parentURL.path
        let videoRootPath = videoRoot.standardizedFileURL.path
        let legacyVideoRootPath = legacyVideoRoot?.standardizedFileURL.path
        let libraryPath = libraryURL.standardizedFileURL.path

        let rawTags: [String]
        if parentPath.hasPrefix(videoRootPath + "/") {
            rawTags = resourceFolderTags(for: url, under: videoRoot)
        } else if let legacyVideoRoot,
                  let legacyVideoRootPath,
                  parentPath.hasPrefix(legacyVideoRootPath + "/") {
            rawTags = resourceFolderTags(for: url, under: legacyVideoRoot)
        } else if parentPath == libraryPath {
            rawTags = []
        } else {
            rawTags = resourceFolderTags(for: url, under: libraryURL)
        }

        let ignored = Set([
            videoFolderName,
            imageExportFolderName,
            soundEffectExportFolderName,
            transcriptExportFolderName,
            musicExportFolderName,
            legacyVideoFolderName,
            legacyImageExportFolderName,
            legacyAudioExportFolderName,
            legacySoundEffectExportFolderName,
            legacyTranscriptExportFolderName,
            legacyMusicExportFolderName,
            exportRootFolderName,
            "Imports", "Import", "import", "download", "downloads", "Downloaded Video", "Downloaded Videos"
        ])
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
            "instrumental", "karaoke", "伴奏", "off vocal", "off-vocal",
            "backing track", "accompaniment", "minus one", "no vocal", "without vocal", "without vocals",
            "无人声", "纯音乐"
        ]
        if musicHints.contains(where: { name.contains($0) }) {
            return musicExportFolderName
        }

        return nil
    }

    nonisolated struct ResourceLibrarySnapshot: Codable, Sendable {
        var music: [LocalMusicAsset]
        var audio: [LocalAudioAsset]
        var images: [LocalImageAsset]

        init(music: [LocalMusicAsset], audio: [LocalAudioAsset], images: [LocalImageAsset] = []) {
            self.music = music
            self.audio = audio
            self.images = images
        }

        private enum CodingKeys: String, CodingKey {
            case music
            case audio
            case images
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            music = try container.decodeIfPresent([LocalMusicAsset].self, forKey: .music) ?? []
            audio = try container.decodeIfPresent([LocalAudioAsset].self, forKey: .audio) ?? []
            images = try container.decodeIfPresent([LocalImageAsset].self, forKey: .images) ?? []
        }
    }

    nonisolated static func resourceLibraryCacheURL(in libraryURL: URL) -> URL {
        ProjectRepository.resourceCacheURL(in: libraryURL)
    }

    nonisolated static func loadCachedResourceLibrarySnapshot(in libraryURL: URL) -> ResourceLibrarySnapshot? {
        let url = resourceLibraryCacheURL(in: libraryURL)
        return ProjectRepository.readJSON(ResourceLibrarySnapshot.self, from: url)
    }

    nonisolated static func saveCachedResourceLibrarySnapshot(_ snapshot: ResourceLibrarySnapshot, in libraryURL: URL) {
        try? ProjectRepository.writeJSON(
            snapshot,
            to: resourceLibraryCacheURL(in: libraryURL),
            encoder: ProjectRepository.prettySortedEncoder
        )
    }

    nonisolated static func quickResourceLibrarySnapshot(in libraryURL: URL) -> ResourceLibrarySnapshot {
        ensureMediaFolders(in: libraryURL)

        let audioRoot = mediaFolder(in: libraryURL, named: soundEffectExportFolderName)
        let legacyAudioRoot = mediaFolder(in: libraryURL, named: legacyAudioExportFolderName)
        let legacyExportAudioRoot = legacyExportFolder(in: libraryURL, named: legacySoundEffectExportFolderName)
        let persistedAssetTags = loadResourceAssetTags(in: libraryURL)

        let musicFiles = collectMediaFiles(
            sourceRoots: [libraryURL],
            extensions: Set(supportedAudioExtensions),
            excludedDirectoryNames: resourceScanExcludedDirectoryNames(excludingMusicFolder: true)
        )
        let audioFiles = collectMediaFiles(
            sourceRoots: [audioRoot, legacyAudioRoot, legacyExportAudioRoot],
            extensions: Set(supportedAudioExtensions + supportedVideoExtensions),
            extraTagsBySourcePath: [legacyExportAudioRoot.path: ["导出"]],
            skipGeneratedAudioClipFiles: true
        )
        let imageFiles = collectMediaFiles(
            sourceRoots: [libraryURL],
            extensions: Set(supportedImageExtensions),
            excludedDirectoryNames: resourceScanExcludedDirectoryNames(excludingMusicFolder: false)
        )

        let music: [LocalMusicAsset] = musicFiles.map { entry in
            let role = inferredMusicRole(from: entry.url)
            let relativePath = libraryRelativePath(for: entry.url, base: libraryURL)
            let title = entry.url.deletingPathExtension().lastPathComponent
            let tags = MusicRecognitionItem.cleanedMusicTags(
                cleanedResourceTags((persistedAssetTags[relativePath] ?? []) + resourceDisplayTags(entry.tags)),
                title: title
            )
            return LocalMusicAsset(
                filePath: entry.url.path,
                title: title,
                fileExtension: entry.url.pathExtension.lowercased(),
                role: role,
                tags: tags,
                duration: 0,
                fileSize: entry.fileSize,
                createdAt: entry.createdAt,
                modifiedAt: entry.modifiedAt
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let audio: [LocalAudioAsset] = audioFiles.map { entry in
            let relativePath = libraryRelativePath(for: entry.url, base: libraryURL)
            let tags = cleanedResourceTags(
                (persistedAssetTags[relativePath] ?? []) +
                resourceDisplayTags(entry.tags)
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

        let images: [LocalImageAsset] = imageFiles.map { entry in
            localImageAsset(
                from: entry,
                libraryURL: libraryURL,
                persistedAssetTags: persistedAssetTags,
                includeDimensions: false
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        return ResourceLibrarySnapshot(music: music, audio: audio, images: images)
    }

    nonisolated static func scanResourceLibrarySnapshot(in libraryURL: URL) async -> ResourceLibrarySnapshot {
        return await Task.detached(priority: .utility) {
            ensureMediaFolders(in: libraryURL)

            let audioRoot = mediaFolder(in: libraryURL, named: soundEffectExportFolderName)
            let legacyAudioRoot = mediaFolder(in: libraryURL, named: legacyAudioExportFolderName)
            let legacyExportAudioRoot = legacyExportFolder(in: libraryURL, named: legacySoundEffectExportFolderName)
            var persistedAssetTags = loadResourceAssetTags(in: libraryURL)

            let musicFiles = collectMediaFiles(
                sourceRoots: [libraryURL],
                extensions: Set(supportedAudioExtensions),
                excludedDirectoryNames: resourceScanExcludedDirectoryNames(excludingMusicFolder: true)
            )
            let audioFiles = collectMediaFiles(
                sourceRoots: [audioRoot, legacyAudioRoot, legacyExportAudioRoot],
                extensions: Set(supportedAudioExtensions + supportedVideoExtensions),
                extraTagsBySourcePath: [legacyExportAudioRoot.path: ["导出"]],
                skipGeneratedAudioClipFiles: true
            )
            let imageFiles = collectMediaFiles(
                sourceRoots: [libraryURL],
                extensions: Set(supportedImageExtensions),
                excludedDirectoryNames: resourceScanExcludedDirectoryNames(excludingMusicFolder: false)
            )

            let liveResourcePaths = Set((musicFiles + audioFiles + imageFiles).map {
                libraryRelativePath(for: $0.url, base: libraryURL)
            })
            persistedAssetTags = persistedAssetTags.filter { relativePath, _ in
                if relativePath.hasPrefix("\(musicExportFolderName)/") ||
                    relativePath.hasPrefix("\(soundEffectExportFolderName)/") {
                    return liveResourcePaths.contains(relativePath)
                }
                return true
            }
            var images: [LocalImageAsset] = []
            images.reserveCapacity(imageFiles.count)
            for entry in imageFiles {
                let relativePath = libraryRelativePath(for: entry.url, base: libraryURL)
                persistedAssetTags[relativePath] = resourceDisplayTags(entry.tags)
                images.append(localImageAsset(
                    from: entry,
                    libraryURL: libraryURL,
                    persistedAssetTags: persistedAssetTags,
                    includeDimensions: true
                ))
            }
            images.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            var music: [LocalMusicAsset] = []
            music.reserveCapacity(musicFiles.count)
            for entry in musicFiles {
                let role = inferredMusicRole(from: entry.url)
                let relativePath = libraryRelativePath(for: entry.url, base: libraryURL)
                let title = entry.url.deletingPathExtension().lastPathComponent
                let asset = AVURLAsset(url: entry.url)
                let fileGenreTags = await musicGenreTags(for: asset, title: title)
                let tags = MusicRecognitionItem.cleanedMusicTags(
                    cleanedResourceTags((persistedAssetTags[relativePath] ?? []) + resourceDisplayTags(entry.tags) + fileGenreTags),
                    title: title
                )
                persistedAssetTags[relativePath] = tags
                let duration = await durationSeconds(for: asset) ?? 0
                let recognizedSong = await Self.appleMusicRecognitionForLocalMusicFile(
                    title: title,
                    duration: duration
                )
                music.append(LocalMusicAsset(
                    filePath: entry.url.path,
                    title: title,
                    fileExtension: entry.url.pathExtension.lowercased(),
                    role: role,
                    tags: tags,
                    duration: duration,
                    fileSize: entry.fileSize,
                    createdAt: entry.createdAt,
                    modifiedAt: entry.modifiedAt,
                    recognizedSong: recognizedSong
                ))
            }
            music.sort { (lhs: LocalMusicAsset, rhs: LocalMusicAsset) in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

            var audio: [LocalAudioAsset] = []
            audio.reserveCapacity(audioFiles.count)
            for entry in audioFiles {
                let relativePath = libraryRelativePath(for: entry.url, base: libraryURL)
                let tags = cleanedResourceTags(
                    (persistedAssetTags[relativePath] ?? []) +
                    resourceDisplayTags(entry.tags)
                )
                persistedAssetTags[relativePath] = tags
                let duration = await durationSeconds(for: AVURLAsset(url: entry.url)) ?? 0
                audio.append(LocalAudioAsset(
                    filePath: entry.url.path,
                    title: entry.url.deletingPathExtension().lastPathComponent,
                    fileExtension: entry.url.pathExtension.lowercased(),
                    tags: tags,
                    duration: duration,
                    fileSize: entry.fileSize,
                    modifiedAt: entry.modifiedAt
                ))
            }
            audio.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            saveResourceAssetTags(persistedAssetTags, in: libraryURL)
            let snapshot = ResourceLibrarySnapshot(music: music, audio: audio, images: images)
            saveCachedResourceLibrarySnapshot(snapshot, in: libraryURL)
            Task.detached(priority: .background) {
                ResourceLibrarySQLite.write(libraryURL: libraryURL, music: music, audio: audio, images: images)
            }
            return snapshot
        }.value
    }

    nonisolated static func appleMusicRecognitionForLocalMusicFile(
        title: String,
        duration: Double
    ) async -> MusicRecognitionItem? {
        let seed = localMusicAppleMusicSeed(from: title)
        guard !seed.query.isEmpty else { return nil }

        do {
            let results = try await searchAppleMusic(query: seed.query)
            guard let result = bestAppleMusicResult(for: seed, duration: duration, results: results) else {
                return nil
            }
            var song = result.asMusicRecognitionItem()
            if duration.isFinite, duration > 0 {
                song.duration = duration
            }
            return song
        } catch {
            return nil
        }
    }

    nonisolated static func localMusicAppleMusicSeed(from rawTitle: String) -> LocalMusicAppleMusicSeed {
        var cleaned = rawTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s*[-_]\s*[A-Za-z0-9_-]{11}$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[_]+"#, with: " ", options: .regularExpression)

        let removablePatterns = [
            #"(?i)\([^)]*(official music video|official video|official audio|music video|lyric video|lyrics|audio|upscaled|remastered|hd|4k)[^)]*\)"#,
            #"(?i)（[^）]*(official music video|official video|official audio|music video|lyric video|lyrics|audio|upscaled|remastered|hd|4k)[^）]*）"#,
            #"(?i)\[[^\]]*(official music video|official video|official audio|music video|lyric video|lyrics|audio|upscaled|remastered|hd|4k)[^\]]*\]"#,
            #"(?i)【[^】]*(official music video|official video|official audio|music video|lyric video|lyrics|audio|upscaled|remastered|hd|4k)[^】]*】"#,
            #"(?i)\b(official music video|official video|official audio|music video|lyric video|lyrics|upscaled|remastered|hd|4k)\b"#
        ]
        for pattern in removablePatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—|｜")))

        let parts = cleaned
            .components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let artist: String
        let title: String
        if parts.count >= 2 {
            artist = parts[0]
            title = parts.dropFirst().joined(separator: " - ")
        } else {
            artist = ""
            title = cleaned
        }
        let query = [artist, title]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        return LocalMusicAppleMusicSeed(query: query, title: title, artist: artist)
    }

    nonisolated static func bestAppleMusicResult(
        for seed: LocalMusicAppleMusicSeed,
        duration: Double,
        results: [AppleMusicSearchResult]
    ) -> AppleMusicSearchResult? {
        results
            .map { result in
                (result: result, score: localMusicAppleMusicMatchScore(result, seed: seed, duration: duration))
            }
            .filter { $0.score >= (seed.artist.isEmpty ? 8 : 10) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.result.trackID < rhs.result.trackID
            }
            .first?
            .result
    }

    nonisolated static func localMusicAppleMusicMatchScore(
        _ result: AppleMusicSearchResult,
        seed: LocalMusicAppleMusicSeed,
        duration: Double
    ) -> Int {
        let seedTitle = localMusicAppleMusicComparableText(seed.title)
        let seedArtist = localMusicAppleMusicComparableText(seed.artist)
        let resultTitle = localMusicAppleMusicComparableText(result.title)
        let resultArtist = localMusicAppleMusicComparableText(result.artist)
        guard !seedTitle.isEmpty, !resultTitle.isEmpty else { return 0 }

        var score = 0
        if resultTitle == seedTitle {
            score += 8
        } else if resultTitle.count >= 3,
                  seedTitle.count >= 3,
                  (resultTitle.contains(seedTitle) || seedTitle.contains(resultTitle)) {
            score += 5
        }

        if !seedArtist.isEmpty, !resultArtist.isEmpty {
            if resultArtist == seedArtist {
                score += 6
            } else if resultArtist.count >= 3,
                      seedArtist.count >= 3,
                      (resultArtist.contains(seedArtist) || seedArtist.contains(resultArtist)) {
                score += 3
            }
        } else if seedArtist.isEmpty {
            score += 1
        }

        if duration.isFinite, duration > 0, result.duration.isFinite, result.duration > 0 {
            let delta = abs(duration - result.duration)
            if delta <= 3 {
                score += 3
            } else if delta <= 12 {
                score += 1
            }
        }
        if !result.artworkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 1
        }
        if !result.appleMusicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 1
        }
        return score
    }

    nonisolated static func localMusicAppleMusicComparableText(_ text: String) -> String {
        var value = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let removablePatterns = [
            #"(?i)\([^)]*(feat\.?|ft\.?|featuring)[^)]*\)"#,
            #"(?i)\[[^\]]*(feat\.?|ft\.?|featuring)[^\]]*\]"#,
            #"(?i)\b(feat\.?|ft\.?|featuring)\b.*$"#,
            #"(?i)\b(official music video|official video|official audio|music video|lyric video|lyrics|audio|upscaled|remastered|hd|4k)\b"#
        ]
        for pattern in removablePatterns {
            value = value.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let alphanumericText = value.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
        return alphanumericText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func localImageAsset(
        from entry: FlattenedResourceFile,
        libraryURL: URL,
        persistedAssetTags: [String: [String]],
        includeDimensions: Bool
    ) -> LocalImageAsset {
        let relativePath = libraryRelativePath(for: entry.url, base: libraryURL)
        let dimensions = includeDimensions ? imageDimensions(for: entry.url) : (width: nil as Int?, height: nil as Int?)
        return LocalImageAsset(
            filePath: entry.url.path,
            title: entry.url.deletingPathExtension().lastPathComponent,
            fileExtension: entry.url.pathExtension.lowercased(),
            tags: cleanedResourceTags((persistedAssetTags[relativePath] ?? []) + resourceDisplayTags(entry.tags)),
            fileSize: entry.fileSize,
            modifiedAt: entry.modifiedAt,
            width: dimensions.width,
            height: dimensions.height
        )
    }

    nonisolated static func imageDimensions(for url: URL) -> (width: Int?, height: Int?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return (nil, nil)
        }
        let width = imagePropertyInt(properties[kCGImagePropertyPixelWidth])
        let height = imagePropertyInt(properties[kCGImagePropertyPixelHeight])
        return (width, height)
    }

    nonisolated static func imagePropertyInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    nonisolated struct FlattenedResourceFile: Sendable {
        var url: URL
        var tags: [String]
        var fileSize: Int64
        var createdAt: Date?
        var modifiedAt: Date?
    }

    nonisolated static func collectMediaFiles(
        sourceRoots: [URL],
        extensions: Set<String>,
        extraTagsBySourcePath: [String: [String]] = [:],
        skipGeneratedAudioClipFiles: Bool = false,
        excludedDirectoryNames: Set<String> = []
    ) -> [FlattenedResourceFile] {
        let fm = FileManager.default
        var results: [FlattenedResourceFile] = []
        var seenSourceRoots = Set<String>()

        for sourceRoot in sourceRoots where seenSourceRoots.insert(sourceRoot.standardizedFileURL.path).inserted {
            guard directoryExists(sourceRoot) else { continue }
            let sourceRootPath = sourceRoot.standardizedFileURL.path
            let urls = fm.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )?.compactMap { $0 as? URL } ?? []

            for url in urls {
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                if isResourceURL(url, underExcludedDirectoryNames: excludedDirectoryNames, sourceRoot: sourceRoot) { continue }
                if skipGeneratedAudioClipFiles, isGeneratedAudioClipFile(url) { continue }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey])
                guard values?.isRegularFile == true else { continue }

                results.append(FlattenedResourceFile(
                    url: url,
                    tags: resourceFolderTags(for: url, under: sourceRoot) + (extraTagsBySourcePath[sourceRootPath] ?? []),
                    fileSize: Int64(values?.fileSize ?? 0),
                    createdAt: values?.creationDate,
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
        excludedDirectoryNames: Set<String> = [],
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
                if isResourceURL(originalURL, underExcludedDirectoryNames: excludedDirectoryNames, sourceRoot: sourceRoot) { continue }
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

    nonisolated static func isResourceURL(
        _ url: URL,
        underExcludedDirectoryNames excludedDirectoryNames: Set<String>,
        sourceRoot: URL
    ) -> Bool {
        guard !excludedDirectoryNames.isEmpty else { return false }
        let sourceRootPath = sourceRoot.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        guard urlPath.hasPrefix(sourceRootPath + "/") else { return false }
        let relativePath = String(urlPath.dropFirst(sourceRootPath.count + 1))
        let components = relativePath.split(separator: "/").map(String.init)
        return components.dropLast().contains { excludedDirectoryNames.contains($0) }
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
        ProjectRepository.resourceAssetTagsURL(in: libraryURL)
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
        guard let decoded = ProjectRepository.readJSON([String: [String]].self, from: url) else { return [:] }

        return decoded.mapValues(cleanedResourceTags)
    }

    nonisolated static func saveResourceAssetTags(_ tagsByRelativePath: [String: [String]], in libraryURL: URL) {
        let url = resourceAssetTagsURL(in: libraryURL)
        let cleaned = tagsByRelativePath
            .filter { !$0.value.isEmpty }
            .mapValues(cleanedResourceTags)
        try? ProjectRepository.writeJSON(cleaned, to: url, encoder: ProjectRepository.prettySortedEncoder)
    }

    nonisolated static func resourceFolderTags(for fileURL: URL, under rootURL: URL) -> [String] {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.deletingLastPathComponent().pathComponents
        guard fileComponents.count > rootComponents.count else { return [] }
        return Array(fileComponents.dropFirst(rootComponents.count))
    }

    nonisolated static func resourceScanExcludedDirectoryNames(excludingMusicFolder: Bool) -> Set<String> {
        var names: Set<String> = [
            videoFolderName,
            imageExportFolderName,
            soundEffectExportFolderName,
            transcriptExportFolderName,
            legacyVideoFolderName,
            legacyImageExportFolderName,
            legacyAudioExportFolderName,
            legacySoundEffectExportFolderName,
            legacyTranscriptExportFolderName,
            exportRootFolderName,
            nonRecognizedMusicPackageFolderName,
            "Imports"
        ]
        if !excludingMusicFolder {
            names.insert(musicExportFolderName)
            names.insert(legacyMusicExportFolderName)
        }
        return names
    }

    nonisolated static func resourceDisplayTags(_ rawTags: [String]) -> [String] {
        let ignored = Set([
            videoFolderName,
            imageExportFolderName,
            soundEffectExportFolderName,
            transcriptExportFolderName,
            musicExportFolderName,
            legacyVideoFolderName,
            legacyImageExportFolderName,
            legacyAudioExportFolderName,
            legacySoundEffectExportFolderName,
            legacyTranscriptExportFolderName,
            legacyMusicExportFolderName,
            exportRootFolderName,
            nonRecognizedMusicPackageFolderName,
            "Imports"
        ])
        return cleanedResourceTags(rawTags).filter { !ignored.contains($0) }
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
        let instrumentalHints = [
            "伴奏", "instrumental", "karaoke", "off vocal", "off-vocal", "纯音乐", "无人声",
            "backing track", "accompaniment", "minus one", "no vocal", "without vocal", "without vocals", "inst"
        ]
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
        guard Self.trashVideoFileIfPresent(at: video.url) else { return }
        let framesToRemove = sampledFrames.filter { $0.videoPath == path }
        let frameIDsToRemove = Set(framesToRemove.map(\.id))
        let clipsToRemove = audioClips.filter { $0.videoPath == path }
        let transcriptExportsToRemove = transcriptExports.filter { $0.videoPath == path }

        for frame in framesToRemove {
            for url in imageExportURLsToDelete(for: frame, excludingFrameIDs: frameIDsToRemove) {
                _ = trashLibraryFileIfPresent(url, context: "video-related image export")
            }
        }
        for clip in clipsToRemove {
            _ = trashLibraryFileIfPresent(audioClipFileURL(for: clip), context: "video-related audio clip export")
        }
        for export in transcriptExportsToRemove {
            _ = trashLibraryFileIfPresent(URL(fileURLWithPath: export.filePath), context: "video-related transcript export")
        }

        videos.removeAll { $0.url.path == path }
        if selectedVideo?.url.path == path {
            selectedVideo = nil
            shouldAutoplaySelectedVideo = false
            selectedVideoSelectionID = UUID()
        }
        removeQueuedMetadataLoad(for: path)
        thumbnailLoadingPaths.remove(path)
        thumbnailGenerationFailedPaths.remove(path)
        metadataByVideoPath.removeValue(forKey: path)
        thumbnailDataByVideoPath.removeValue(forKey: path)
        thumbnailImageByVideoPath.removeValue(forKey: path)
        thumbnailImageRevisionByVideoPath.removeValue(forKey: path)
        thumbnailImageAccessTickByPath.removeValue(forKey: path)
        durationByVideoPath.removeValue(forKey: path)
        playbackSupportByVideoPath.removeValue(forKey: path)
        waveformTasks[path]?.cancel()
        waveformTasks[path] = nil
        waveformSamplesByVideoPath.removeValue(forKey: path)
        frameStripTasks[path]?.cancel()
        frameStripTasks[path] = nil
        frameStripByVideoPath.removeValue(forKey: path)
        frameStripImagesByVideoPath.removeValue(forKey: path)
        tagsByVideoPath.removeValue(forKey: path)
        sourceInfoByVideoPath.removeValue(forKey: path)
        pendingVideoFolderTagsByPath.removeValue(forKey: path)
        pendingVideoPathRemap.removeValue(forKey: path)
        pendingVideoPathRemap = pendingVideoPathRemap.filter { $0.value != path }
        transcriptSegmentsByVideoPath.removeValue(forKey: path)
        transcriptStatusByVideoPath.removeValue(forKey: path)
        transcriptTasks[path]?.cancel()
        transcriptTasks[path] = nil
        transcriptExportJobs.removeValue(forKey: path)
        transcriptExports.removeAll { $0.videoPath == path }
        let removedAudioClipIDs = Set(audioClips.filter { $0.videoPath == path }.map(\.id))
        for clipID in removedAudioClipIDs {
            audioClipWaveformTasks[clipID]?.cancel()
            audioClipWaveformTasks[clipID] = nil
        }
        pendingAudioClipWaveformIDSet.subtract(removedAudioClipIDs)
        pendingAudioClipWaveformIDs.removeAll { removedAudioClipIDs.contains($0) }
        sampledFrames.removeAll { $0.videoPath == path }
        annotations.removeAll { $0.videoPath == path }
        audioClips.removeAll { $0.videoPath == path }
        musicDetectionTasks[path]?.cancel()
        musicDetectionTasks[path] = nil
        for song in musicsByVideoPath[path, default: []] {
            let enrichmentKey = musicTagEnrichmentKey(for: song, in: path)
            musicTagEnrichmentTasks[enrichmentKey]?.cancel()
            musicTagEnrichmentTasks[enrichmentKey] = nil
        }
        musicsByVideoPath.removeValue(forKey: path)
        musicDetectionStatusByVideoPath.removeValue(forKey: path)
        sceneCutsByVideoPath.removeValue(forKey: path)
        sceneStripImagesByVideoPath.removeValue(forKey: path)
        sceneCutProgressesByVideoPath.removeValue(forKey: path)
        sceneThumbnailVersionsByVideoPath.removeValue(forKey: path)
        sceneDetectionProgress.removeValue(forKey: path)
        sceneDetectionErrorByVideoPath.removeValue(forKey: path)
        sceneDetectionTasks[path]?.cancel()
        sceneDetectionTasks[path] = nil
        sceneThumbnailHydrationTasks[path]?.cancel()
        sceneThumbnailHydrationTasks[path] = nil
        sceneThumbnailHydrationNeeded.remove(path)
        transientMediaCacheAccessTickByPath.removeValue(forKey: path)
        sceneCutCache.removeValue(forKey: relativeVideoPath(for: video.url))
        saveTagsJSON()
        saveSourceInfoJSON()
        saveSceneCutCache()
        writeFrameIndex()
        saveProjectData()
        removeEmptyMediaDirectoriesAfterVideoDeletion()
        scheduleCurrentVideoLibrarySnapshotSave(after: 0.5)
    }

    private static func trashVideoFileIfPresent(at url: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return true }

        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            NSLog("LapianBao failed to move video to Trash: %@ %@", url.path, String(describing: error))
            return false
        }
    }

    private func removeEmptyMediaDirectoriesAfterVideoDeletion() {
        guard let libraryURL else { return }

        let videoRoot = Self.mediaFolder(in: libraryURL, named: Self.videoFolderName)
        Self.removeEmptyDirectories(under: videoRoot, preserving: [videoRoot])

        let importsRoot = libraryURL.appendingPathComponent("Imports", isDirectory: true)
        Self.removeEmptyDirectories(under: importsRoot, preserving: [])
        Self.removeDirectoryIfEmpty(importsRoot)
    }

    func addTag(to video: VideoItem) {
        addTag(tagInput, to: video)
        tagInput = ""
    }

    func addTag(_ rawTag: String, to video: VideoItem) {
        let rawTag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTag.isEmpty else { return }
        let path = video.url.path
        guard let tag = subjectiveVideoTags(forPath: path, tags: [rawTag]).first else { return }

        let existingKeys = Set(tagsByVideoPath[path, default: []].compactMap(Self.normalizedSubjectiveTagKey))
        guard let tagKey = Self.normalizedSubjectiveTagKey(tag),
              !existingKeys.contains(tagKey)
        else { return }

        tagsByVideoPath[path] = subjectiveVideoTags(
            forPath: path,
            tags: tagsByVideoPath[path, default: []] + [tag]
        ).sorted()

        saveTagsJSON()
    }

    func removeTag(_ tag: String, from video: VideoItem) {
        guard let tagKey = Self.normalizedSubjectiveTagKey(tag) else { return }

        var updatedTagsByVideoPath = tagsByVideoPath
        let updated = removeVideoTags(matchingKey: tagKey, from: updatedTagsByVideoPath[video.url.path, default: []])
        if updated.isEmpty {
            updatedTagsByVideoPath.removeValue(forKey: video.url.path)
        } else {
            updatedTagsByVideoPath[video.url.path] = updated
        }
        tagsByVideoPath = updatedTagsByVideoPath
        selectedTags = Set(selectedTags.filter { Self.normalizedSubjectiveTagKey($0) != tagKey })
        saveTagsJSON()
    }

    func setSourcePlatform(_ rawPlatform: String, for video: VideoItem) {
        guard let platform = Self.canonicalSourcePlatform(rawPlatform),
              !Self.isUnknownSourcePlatform(platform)
        else { return }

        let path = video.url.path
        let existing = sourceInfoByVideoPath[path]
        let updatedInfo = VideoSourceInfo(
            platform: platform,
            sourceURL: existing.flatMap { Self.usefulSourceURLString($0.sourceURL) },
            authorName: existing?.authorName.flatMap(Self.normalizedSourceAuthorName),
            title: existing?.title.flatMap(Self.normalizedSourceTitle)
        )
        guard updatedInfo != existing else { return }

        sourceInfoByVideoPath[path] = updatedInfo
        saveSourceInfoJSON()
    }

    func toggleTagSelection(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    func renameGlobalTag(_ old: String, to new: String) {
        guard let oldKey = Self.normalizedSubjectiveTagKey(old),
              let newTag = Self.cleanedVideoTagSuggestions([new]).first,
              let newKey = Self.normalizedSubjectiveTagKey(newTag),
              oldKey != newKey || newTag != old
        else { return }

        var updatedTagsByVideoPath = tagsByVideoPath
        for (path, tags) in updatedTagsByVideoPath {
            var didReplaceTag = false
            var hasNewTag = false
            var updated: [String] = []

            for tag in tags {
                guard let tagKey = Self.normalizedSubjectiveTagKey(tag) else {
                    updated.append(tag)
                    continue
                }

                if tagKey == oldKey {
                    didReplaceTag = true
                    continue
                }

                if tagKey == newKey {
                    hasNewTag = true
                }
                updated.append(tag)
            }

            guard didReplaceTag else { continue }

            if !hasNewTag {
                updated.append(newTag)
            }
            updatedTagsByVideoPath[path] = updated.sorted()
        }
        tagsByVideoPath = updatedTagsByVideoPath

        if selectedTags.contains(where: { Self.normalizedSubjectiveTagKey($0) == oldKey }) {
            selectedTags = Set(selectedTags.filter { Self.normalizedSubjectiveTagKey($0) != oldKey })
            selectedTags.insert(newTag)
        }
        saveTagsJSON()
    }

    func removeGlobalTag(_ tag: String) {
        guard let tagKey = Self.normalizedSubjectiveTagKey(tag) else { return }

        var updatedTagsByVideoPath = tagsByVideoPath
        var didRemoveTag = false
        for (path, tags) in updatedTagsByVideoPath {
            let updated = removeVideoTags(matchingKey: tagKey, from: tags)
            if updated.count != tags.count {
                didRemoveTag = true
                if updated.isEmpty {
                    updatedTagsByVideoPath.removeValue(forKey: path)
                } else {
                    updatedTagsByVideoPath[path] = updated
                }
            }
        }
        if didRemoveTag {
            tagsByVideoPath = updatedTagsByVideoPath
        } else {
            rebuildAllTagsCache()
            markLibrarySidebarMetricsDirty()
            refreshFilteredVideos()
            objectWillChange.send()
        }
        selectedTags = Set(selectedTags.filter { Self.normalizedSubjectiveTagKey($0) != tagKey })
        rebuildAllTagsCache()
        markLibrarySidebarMetricsDirty()
        refreshFilteredVideos()
        saveTagsJSON()
    }

    private func removeVideoTags(matchingKey tagKey: String, from tags: [String]) -> [String] {
        tags.filter { Self.normalizedSubjectiveTagKey($0) != tagKey }
    }

    // MARK: - JSON 持久化

}

nonisolated struct LocalMusicAppleMusicSeed: Sendable {
    var query: String
    var title: String
    var artist: String
}
