//
//  LibraryStore+MetadataAndExportHelpers.swift
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
    func loadMetadataIfNeeded(
        for video: VideoItem,
        priority: TaskPriority = .utility,
        allowThumbnailGeneration: Bool = false
    ) {
        let path = video.url.path
        guard containsVideoPath(path) else { return }
        hydrateCachedThumbnailImageIfNeeded(for: path)
        guard needsVideoMetadataWork(for: path, allowThumbnailGeneration: allowThumbnailGeneration) else { return }
        removeQueuedMetadataLoad(for: path)
        guard !thumbnailLoadingPaths.contains(path) else { return }

        let generation = thumbnailLoadGeneration
        let shouldGenerateThumbnail = allowThumbnailGeneration && needsGeneratedVideoThumbnail(for: path)
        thumbnailLoadingPaths.insert(path)
        let task = Task.detached(priority: priority) { [weak self, video, shouldGenerateThumbnail] in
            let path = video.url.path
            async let metadata = Self.makeVideoMetadata(
                for: video.url,
                shouldGenerateThumbnail: shouldGenerateThumbnail
            )
            async let playbackSupport = Self.playbackSupport(for: video.url)
            let videoMetadata = await metadata
            let support = await playbackSupport

            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.thumbnailLoadGeneration == generation,
                      self.thumbnailLoadingPaths.contains(path),
                      self.containsVideoPath(path)
                else { return }
                self.applyVideoMetadata(
                    videoMetadata,
                    playbackSupport: support,
                    for: path
                )
            }
        }
        thumbnailWorkerTasks.append(task)
    }

    func queueMetadataLoadIfNeeded(
        for video: VideoItem,
        allowThumbnailGeneration: Bool = false
    ) {
        let path = video.url.path
        guard containsVideoPath(path) else { return }
        noteTransientMediaAccess(for: path)
        noteThumbnailImageAccess(for: path)
        enqueueCachedThumbnailImageHydrationIfNeeded(for: path)
        guard needsVideoMetadataWork(for: path, allowThumbnailGeneration: allowThumbnailGeneration) else { return }
        guard !thumbnailLoadingPaths.contains(path) else { return }
        guard !queuedMetadataVideoPaths.contains(path) else { return }

        queuedMetadataVideos.append((video: video, allowThumbnailGeneration: allowThumbnailGeneration))
        queuedMetadataVideoPaths.insert(path)
        startQueuedMetadataWorkerIfNeeded()
    }

    func needsVideoMetadata(for path: String) -> Bool {
        metadataByVideoPath[path] == nil || playbackSupportByVideoPath[path] == nil
    }

    func needsGeneratedVideoThumbnail(for path: String) -> Bool {
        thumbnailDataByVideoPath[path] == nil
            && thumbnailImageByVideoPath[path] == nil
            && !thumbnailGenerationFailedPaths.contains(path)
    }

    func needsVideoMetadataWork(for path: String) -> Bool {
        needsVideoMetadata(for: path) || needsGeneratedVideoThumbnail(for: path)
    }

    func needsVideoMetadataWork(for path: String, allowThumbnailGeneration: Bool) -> Bool {
        needsVideoMetadata(for: path) || (allowThumbnailGeneration && needsGeneratedVideoThumbnail(for: path))
    }

    func hydrateCachedThumbnailImageIfNeeded(for path: String) {
        guard thumbnailImageByVideoPath[path] == nil,
              let data = thumbnailDataByVideoPath[path],
              let image = Self.decodedThumbnailImage(from: data)
        else { return }

        thumbnailImageByVideoPath[path] = image
        noteThumbnailImageAccess(for: path)
        thumbnailGenerationFailedPaths.remove(path)
        trimDecodedThumbnailImageCacheIfNeeded()
        scheduleMetadataDisplayRefresh()
    }

    func enqueueCachedThumbnailImageHydrationIfNeeded(for path: String) {
        guard thumbnailImageByVideoPath[path] == nil,
              let data = thumbnailDataByVideoPath[path],
              !thumbnailGenerationFailedPaths.contains(path),
              !pendingCachedThumbnailHydrationPaths.contains(path)
        else { return }

        pendingCachedThumbnailHydrationEntries.append((path: path, data: data))
        pendingCachedThumbnailHydrationPaths.insert(path)
        startCachedThumbnailHydrationWorkerIfNeeded()
    }

    func startCachedThumbnailHydrationWorkerIfNeeded() {
        guard cachedThumbnailHydrationTask == nil else { return }
        guard !pendingCachedThumbnailHydrationEntries.isEmpty else { return }

        let generation = thumbnailLoadGeneration
        cachedThumbnailHydrationTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000)

            while !Task.isCancelled {
                let entries = await MainActor.run { [weak self] in
                    self?.nextCachedThumbnailHydrationBatch(generation: generation, limit: 8) ?? []
                }
                guard !entries.isEmpty else { break }

                let decoded = entries.compactMap { entry -> (path: String, image: NSImage)? in
                    guard let image = Self.decodedThumbnailImage(from: entry.data) else { return nil }
                    return (entry.path, image)
                }

                if !decoded.isEmpty {
                    await MainActor.run { [weak self] in
                        self?.applyCachedThumbnailImageBatch(decoded, generation: generation)
                    }
                }

                try? await Task.sleep(nanoseconds: 28_000_000)
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.thumbnailLoadGeneration == generation else {
                    self.cachedThumbnailHydrationTask = nil
                    return
                }
                self.cachedThumbnailHydrationTask = nil
                if !self.pendingCachedThumbnailHydrationEntries.isEmpty {
                    self.startCachedThumbnailHydrationWorkerIfNeeded()
                }
            }
        }
    }

    func nextCachedThumbnailHydrationBatch(
        generation: Int,
        limit: Int
    ) -> [(path: String, data: Data)] {
        guard thumbnailLoadGeneration == generation else {
            pendingCachedThumbnailHydrationEntries.removeAll()
            pendingCachedThumbnailHydrationPaths.removeAll()
            return []
        }

        var batch: [(path: String, data: Data)] = []
        batch.reserveCapacity(limit)

        while !pendingCachedThumbnailHydrationEntries.isEmpty, batch.count < limit {
            guard let entry = pendingCachedThumbnailHydrationEntries.popLast() else { break }
            pendingCachedThumbnailHydrationPaths.remove(entry.path)
            guard containsVideoPath(entry.path),
                  thumbnailImageByVideoPath[entry.path] == nil,
                  thumbnailDataByVideoPath[entry.path] != nil,
                  !thumbnailGenerationFailedPaths.contains(entry.path)
            else { continue }
            batch.append(entry)
        }

        return batch
    }

    func removeQueuedMetadataLoad(for path: String) {
        guard queuedMetadataVideoPaths.remove(path) != nil else { return }
        queuedMetadataVideos.removeAll { $0.video.url.path == path }
    }

    func startQueuedMetadataWorkerIfNeeded() {
        guard queuedMetadataWorkerTask == nil else { return }
        guard !queuedMetadataVideos.isEmpty else { return }

        let generation = thumbnailLoadGeneration
        queuedMetadataWorkerTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let queuedVideo = await MainActor.run(body: { [weak self] in
                    self?.nextQueuedMetadataVideo(generation: generation)
                }) else {
                    break
                }

                let video = queuedVideo.video
                let path = video.url.path
                let shouldGenerateThumbnail = await MainActor.run { [weak self] in
                    guard queuedVideo.allowThumbnailGeneration else { return false }
                    return self?.needsGeneratedVideoThumbnail(for: path) ?? false
                }
                async let metadata = Self.makeVideoMetadata(
                    for: video.url,
                    shouldGenerateThumbnail: shouldGenerateThumbnail
                )
                async let playbackSupport = Self.playbackSupport(for: video.url)
                let videoMetadata = await metadata
                let support = await playbackSupport

                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.thumbnailLoadGeneration == generation,
                          self.thumbnailLoadingPaths.contains(path),
                          self.containsVideoPath(path)
                    else { return }
                    self.applyVideoMetadata(
                        videoMetadata,
                        playbackSupport: support,
                        for: path
                    )
                }
            }

            await MainActor.run { [weak self] in
                guard let self, self.thumbnailLoadGeneration == generation else { return }
                self.queuedMetadataWorkerTask = nil
                if !self.queuedMetadataVideos.isEmpty {
                    self.startQueuedMetadataWorkerIfNeeded()
                }
            }
        }
    }

    func nextQueuedMetadataVideo(generation: Int) -> (video: VideoItem, allowThumbnailGeneration: Bool)? {
        guard thumbnailLoadGeneration == generation else {
            queuedMetadataVideos.removeAll()
            queuedMetadataVideoPaths.removeAll()
            return nil
        }

        while let queuedVideo = queuedMetadataVideos.popLast() {
            let video = queuedVideo.video
            let path = video.url.path
            queuedMetadataVideoPaths.remove(path)
            guard containsVideoPath(path) else { continue }
            enqueueCachedThumbnailImageHydrationIfNeeded(for: path)
            guard needsVideoMetadataWork(
                for: path,
                allowThumbnailGeneration: queuedVideo.allowThumbnailGeneration
            ) else { continue }
            guard !thumbnailLoadingPaths.contains(path) else { continue }

            thumbnailLoadingPaths.insert(path)
            return queuedVideo
        }

        return nil
    }

    func loadThumbnails(
        for videos: [VideoItem],
        workerCount: Int = 3,
        allowThumbnailGeneration: Bool = false
    ) {
        thumbnailWorkerTasks.forEach { $0.cancel() }
        thumbnailWorkerTasks.removeAll()
        queuedMetadataWorkerTask?.cancel()
        queuedMetadataWorkerTask = nil
        queuedMetadataVideos.removeAll()
        queuedMetadataVideoPaths.removeAll()
        cachedThumbnailHydrationTask?.cancel()
        cachedThumbnailHydrationTask = nil
        pendingCachedThumbnailHydrationEntries.removeAll()
        pendingCachedThumbnailHydrationPaths.removeAll()
        metadataRefreshTask?.cancel()
        metadataRefreshTask = nil
        metadataDisplayRefreshTask?.cancel()
        metadataDisplayRefreshTask = nil
        thumbnailLoadingPaths.removeAll()
        thumbnailLoadGeneration += 1
        let libraryPaths = Set(self.videos.map { $0.url.path })
        thumbnailGenerationFailedPaths.formIntersection(libraryPaths)
        metadataByVideoPath.merge(
            Self.fileResourceMetadataByPath(for: videos, preserving: metadataByVideoPath)
        ) { _, new in new }
        let preservedThumbnailData = thumbnailDataByVideoPath.filter { libraryPaths.contains($0.key) }
        let preservedThumbnailImages = thumbnailImageByVideoPath.filter { libraryPaths.contains($0.key) }
        let preservedDurations = durationByVideoPath.filter { libraryPaths.contains($0.key) }
        let preservedPlaybackSupport = playbackSupportByVideoPath.filter { libraryPaths.contains($0.key) }
        waveformTasks.values.forEach { $0.cancel() }
        waveformTasks.removeAll()
        audioClipWaveformTasks.values.forEach { $0.cancel() }
        audioClipWaveformTasks.removeAll()
        frameStripTasks.values.forEach { $0.cancel() }
        frameStripTasks.removeAll()
        sceneDetectionTasks.values.forEach { $0.cancel() }
        sceneDetectionTasks.removeAll()
        sceneThumbnailHydrationTasks.values.forEach { $0.cancel() }
        sceneThumbnailHydrationTasks.removeAll()
        sceneThumbnailHydrationNeeded.removeAll()

        objectWillChange.send()
        thumbnailDataByVideoPath = preservedThumbnailData
        thumbnailImageByVideoPath = preservedThumbnailImages
        thumbnailImageAccessTickByPath = thumbnailImageAccessTickByPath.filter { libraryPaths.contains($0.key) }
        durationByVideoPath = preservedDurations
        playbackSupportByVideoPath = preservedPlaybackSupport
        waveformSamplesByVideoPath.removeAll()
        frameStripByVideoPath.removeAll()
        frameStripImagesByVideoPath.removeAll()
        sceneStripImagesByVideoPath.removeAll()
        sceneCutsByVideoPath.removeAll()
        sceneCutProgressesByVideoPath.removeAll()
        sceneThumbnailVersionsByVideoPath.removeAll()
        sceneDetectionProgress.removeAll()
        sceneDetectionErrorByVideoPath.removeAll()

        let videosToLoad = videos.filter {
            needsVideoMetadataWork(
                for: $0.url.path,
                allowThumbnailGeneration: allowThumbnailGeneration
            )
        }

        guard !videosToLoad.isEmpty, workerCount > 0 else { return }
        let generation = thumbnailLoadGeneration
        let queue = VideoMetadataQueue(videos: videosToLoad)
        thumbnailLoadingPaths = Set(videosToLoad.map { $0.url.path })

        for _ in 0..<min(max(1, workerCount), videosToLoad.count) {
            let task = Task.detached(priority: .utility) { [weak self, queue] in
                while !Task.isCancelled {
                    guard let video = await queue.next() else { break }
                    let path = video.url.path
                    let shouldGenerateThumbnail = await MainActor.run { [weak self] in
                        guard allowThumbnailGeneration else { return false }
                        return self?.needsGeneratedVideoThumbnail(for: path) ?? false
                    }
                    async let metadata = Self.makeVideoMetadata(
                        for: video.url,
                        shouldGenerateThumbnail: shouldGenerateThumbnail
                    )
                    async let playbackSupport = Self.playbackSupport(for: video.url)
                    let videoMetadata = await metadata
                    let support = await playbackSupport

                    guard !Task.isCancelled else { break }
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.thumbnailLoadGeneration == generation,
                              self.thumbnailLoadingPaths.contains(path)
                        else { return }
                        self.applyVideoMetadata(
                            videoMetadata,
                            playbackSupport: support,
                            for: path
                        )
                    }
                }
            }
            thumbnailWorkerTasks.append(task)
        }
    }

    func scheduleDeferredMetadataLoad(
        for videos: [VideoItem],
        after delay: TimeInterval,
        workerCount: Int,
        allowThumbnailGeneration: Bool = false
    ) {
        guard !videos.isEmpty, workerCount > 0 else { return }
        let generation = thumbnailLoadGeneration
        let delayNanoseconds = UInt64(max(0, delay) * 1_000_000_000)

        let task = Task.detached(priority: .utility) { [weak self, videos] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled else { return }
            }

            let queuedVideos = await MainActor.run { [weak self] in
                guard let self, self.thumbnailLoadGeneration == generation else { return [VideoItem]() }
                let livePaths = Set(self.videos.map { $0.url.path })
                let queued = videos.filter { video in
                    let path = video.url.path
                    guard livePaths.contains(path) else { return false }
                    guard self.needsVideoMetadataWork(
                        for: path,
                        allowThumbnailGeneration: allowThumbnailGeneration
                    ) else { return false }
                    return !self.thumbnailLoadingPaths.contains(path) && !self.queuedMetadataVideoPaths.contains(path)
                }
                self.thumbnailLoadingPaths.formUnion(queued.map { $0.url.path })
                return queued
            }

            guard !queuedVideos.isEmpty else { return }
            let queue = VideoMetadataQueue(videos: queuedVideos)
            let workerTotal = min(max(1, workerCount), queuedVideos.count)

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<workerTotal {
                    group.addTask { [weak self, queue] in
                        while !Task.isCancelled {
                            guard let video = await queue.next() else { break }
                            let path = video.url.path
                            let shouldGenerateThumbnail = await MainActor.run { [weak self] in
                                guard allowThumbnailGeneration else { return false }
                                return self?.needsGeneratedVideoThumbnail(for: path) ?? false
                            }
                            async let metadata = Self.makeVideoMetadata(
                                for: video.url,
                                shouldGenerateThumbnail: shouldGenerateThumbnail
                            )
                            async let playbackSupport = Self.playbackSupport(for: video.url)
                            let videoMetadata = await metadata
                            let support = await playbackSupport

                            guard !Task.isCancelled else { break }
                            await MainActor.run { [weak self] in
                                guard let self,
                                      self.thumbnailLoadGeneration == generation,
                                      self.thumbnailLoadingPaths.contains(path),
                                      self.containsVideoPath(path)
                                else { return }
                                self.applyVideoMetadata(
                                    videoMetadata,
                                    playbackSupport: support,
                                    for: path
                                )
                            }
                        }
                    }
                }
            }
        }

        thumbnailWorkerTasks.append(task)
    }

    func scheduleCachedThumbnailImageHydration(
        for videos: [VideoItem],
        after delay: TimeInterval,
        batchSize: Int = 12
    ) {
        let entries: [(path: String, data: Data)] = videos.compactMap { video in
            let path = video.url.path
            guard thumbnailImageByVideoPath[path] == nil,
                  let data = thumbnailDataByVideoPath[path],
                  !thumbnailGenerationFailedPaths.contains(path)
            else { return nil }
            return (path, data)
        }
        guard !entries.isEmpty else { return }

        let generation = thumbnailLoadGeneration
        let delayNanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        let batchSize = max(1, batchSize)

        let task = Task.detached(priority: .utility) { [weak self, entries] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled else { return }
            }

            var batch: [(path: String, image: NSImage)] = []
            for entry in entries {
                guard !Task.isCancelled else { return }
                guard let image = Self.decodedThumbnailImage(from: entry.data) else { continue }
                batch.append((entry.path, image))

                if batch.count >= batchSize {
                    let readyBatch = batch
                    batch.removeAll(keepingCapacity: true)
                    await MainActor.run { [weak self] in
                        self?.applyCachedThumbnailImageBatch(readyBatch, generation: generation)
                    }
                    try? await Task.sleep(nanoseconds: 28_000_000)
                }
            }

            guard !batch.isEmpty else { return }
            let finalBatch = batch
            await MainActor.run { [weak self] in
                self?.applyCachedThumbnailImageBatch(finalBatch, generation: generation)
            }
        }

        thumbnailWorkerTasks.append(task)
    }

    func scheduleCachedThumbnailDataRestore(in libraryURL: URL, after delay: TimeInterval) {
        let generation = thumbnailLoadGeneration
        let libraryPath = libraryURL.path
        let delayNanoseconds = UInt64(max(0, delay) * 1_000_000_000)

        let task = Task.detached(priority: .utility) { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled else { return }
            }

            guard let restored = Self.loadCachedVideoOrganization(
                in: libraryURL,
                includeThumbnailData: true
            ), !restored.thumbnailDataByPath.isEmpty else { return }

            await MainActor.run { [weak self] in
                guard let self,
                      self.thumbnailLoadGeneration == generation,
                      self.libraryURL?.path == libraryPath
                else { return }

                self.applyCachedThumbnailData(restored.thumbnailDataByPath, generation: generation)
                let hydrationVideos = self.filteredVideos.isEmpty ? self.videos : self.filteredVideos
                self.scheduleCachedThumbnailImageHydration(
                    for: Array(hydrationVideos.prefix(Self.launchCachedThumbnailHydrationLimit)),
                    after: 0,
                    batchSize: 8
                )
            }
        }

        thumbnailWorkerTasks.append(task)
    }

    func prewarmCachedThumbnailImages(for videos: [VideoItem]) {
        var seenPaths = Set<String>()
        let uniqueVideos = videos.filter { seenPaths.insert($0.url.path).inserted }
        guard !uniqueVideos.isEmpty else { return }

        scheduleCachedThumbnailImageHydration(for: uniqueVideos, after: 0, batchSize: 10)

        let missingDataPaths = Set(uniqueVideos.map(\.url.path).filter {
            thumbnailDataByVideoPath[$0] == nil && thumbnailImageByVideoPath[$0] == nil
        })
        guard !missingDataPaths.isEmpty, let libraryURL else { return }

        let generation = thumbnailLoadGeneration
        let libraryPath = libraryURL.path
        let task = Task.detached(priority: .utility) { [weak self, uniqueVideos, missingDataPaths] in
            guard let restored = Self.loadCachedVideoOrganization(
                in: libraryURL,
                includeThumbnailData: true
            ), !restored.thumbnailDataByPath.isEmpty else { return }

            let requestedData = restored.thumbnailDataByPath.filter { missingDataPaths.contains($0.key) }
            guard !requestedData.isEmpty else { return }

            await MainActor.run { [weak self] in
                guard let self,
                      self.thumbnailLoadGeneration == generation,
                      self.libraryURL?.path == libraryPath
                else { return }

                self.applyCachedThumbnailData(requestedData, generation: generation)
                self.scheduleCachedThumbnailImageHydration(for: uniqueVideos, after: 0, batchSize: 10)
            }
        }

        thumbnailWorkerTasks.append(task)
    }

    func applyCachedThumbnailData(_ dataByPath: [String: Data], generation: Int) {
        guard thumbnailLoadGeneration == generation else { return }

        var didUpdate = false
        for (path, data) in dataByPath {
            guard containsVideoPath(path) else { continue }
            if thumbnailDataByVideoPath[path] == nil {
                thumbnailDataByVideoPath[path] = data
                didUpdate = true
            }
            thumbnailGenerationFailedPaths.remove(path)
        }

        if didUpdate {
            scheduleMetadataDisplayRefresh()
        }
    }

    func applyCachedThumbnailImageBatch(
        _ batch: [(path: String, image: NSImage)],
        generation: Int
    ) {
        guard thumbnailLoadGeneration == generation else { return }
        var didUpdate = false

        for item in batch {
            guard containsVideoPath(item.path),
                  thumbnailImageByVideoPath[item.path] == nil,
                  thumbnailDataByVideoPath[item.path] != nil
            else { continue }
            thumbnailImageByVideoPath[item.path] = item.image
            noteThumbnailImageAccess(for: item.path)
            didUpdate = true
        }

        if didUpdate {
            trimDecodedThumbnailImageCacheIfNeeded()
            scheduleMetadataDisplayRefresh()
        }
    }

    func applyVideoMetadata(
        _ videoMetadata: (
            thumbnailData: Data?,
            thumbnailImage: NSImage?,
            duration: Double?,
            metadata: VideoMetadata,
            thumbnailGenerationAttempted: Bool
        ),
        playbackSupport: VideoPlaybackSupport,
        for path: String
    ) {
        if let data = videoMetadata.thumbnailData {
            thumbnailDataByVideoPath[path] = data
            if let image = videoMetadata.thumbnailImage ?? Self.decodedThumbnailImage(from: data) {
                thumbnailImageByVideoPath[path] = image
                noteThumbnailImageAccess(for: path)
            }
            thumbnailGenerationFailedPaths.remove(path)
            updateSceneStripImages(for: path)
        } else if videoMetadata.thumbnailGenerationAttempted {
            thumbnailGenerationFailedPaths.insert(path)
        }

        if let duration = videoMetadata.duration {
            durationByVideoPath[path] = duration
            if let cuts = sceneCutsByVideoPath[path] {
                sceneCutProgressesByVideoPath[path] = Self.normalizedSceneCutProgresses(
                    from: cuts.map(\.time),
                    duration: duration
                )
            }
        }

        metadataByVideoPath[path] = videoMetadata.metadata
        playbackSupportByVideoPath[path] = playbackSupport
        thumbnailLoadingPaths.remove(path)
        trimDecodedThumbnailImageCacheIfNeeded()

        if sortOption.dependsOnMetadata {
            scheduleMetadataDependentRefresh()
        }

        scheduleMetadataDisplayRefresh()
        scheduleCurrentVideoLibrarySnapshotSave(after: 2.0)
    }

    func containsVideoPath(_ path: String) -> Bool {
        videoPathSet.contains(path)
    }

    func noteThumbnailImageAccess(for path: String) {
        thumbnailImageAccessTick += 1
        thumbnailImageAccessTickByPath[path] = thumbnailImageAccessTick
    }

    func trimDecodedThumbnailImageCacheIfNeeded() {
        let limit = Self.maxDecodedLibraryThumbnailImages
        guard thumbnailImageByVideoPath.count > limit else { return }

        let overflow = thumbnailImageByVideoPath.count - limit
        let pathsToRemove = thumbnailImageByVideoPath.keys
            .sorted {
                thumbnailImageAccessTickByPath[$0, default: 0] < thumbnailImageAccessTickByPath[$1, default: 0]
            }
            .prefix(overflow)

        for path in pathsToRemove {
            thumbnailImageByVideoPath.removeValue(forKey: path)
            thumbnailImageAccessTickByPath.removeValue(forKey: path)
        }
    }

    func scheduleMetadataDisplayRefresh() {
        guard metadataDisplayRefreshTask == nil else { return }

        metadataDisplayRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.metadataDisplayRefreshIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            metadataDisplayRefreshTask = nil
            objectWillChange.send()
        }
    }

    nonisolated static func fileResourceMetadataByPath(
        for videos: [VideoItem],
        preserving existing: [String: VideoMetadata]
    ) -> [String: VideoMetadata] {
        Dictionary(uniqueKeysWithValues: videos.map { video in
            let path = video.url.path
            return (path, fileResourceMetadata(for: video.url, preserving: existing[path]))
        })
    }

    nonisolated static func fileResourceMetadata(
        for url: URL,
        preserving existing: VideoMetadata? = nil
    ) -> VideoMetadata {
        let resourceValues = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ])
        let createdAt = resourceValues?.creationDate ?? resourceValues?.contentModificationDate

        return VideoMetadata(
            duration: existing?.duration,
            frameRate: existing?.frameRate,
            pixelWidth: existing?.pixelWidth,
            pixelHeight: existing?.pixelHeight,
            fileSize: resourceValues?.fileSize.map(Int64.init) ?? existing?.fileSize,
            createdAt: createdAt ?? existing?.createdAt,
            modifiedAt: resourceValues?.contentModificationDate ?? existing?.modifiedAt
        )
    }

    nonisolated static func playbackSupport(for url: URL) async -> VideoPlaybackSupport {
        let asset = AVURLAsset(url: url)

        do {
            async let isPlayable = asset.load(.isPlayable)
            async let videoTracks = asset.loadTracks(withMediaType: .video)

            guard try await !videoTracks.isEmpty else {
                return .unsupported("这个文件暂无可播放的视频轨道")
            }

            guard try await isPlayable else {
                return .unsupported("macOS 系统播放器不支持这个容器或编码")
            }

            return .playable
        } catch {
            return .unsupported(error.localizedDescription)
        }
    }

    nonisolated static func makeVideoMetadata(
        for url: URL,
        shouldGenerateThumbnail: Bool = true
    ) async -> (
        thumbnailData: Data?,
        thumbnailImage: NSImage?,
        duration: Double?,
        metadata: VideoMetadata,
        thumbnailGenerationAttempted: Bool
    ) {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            async let duration = durationSeconds(for: asset)
            let specs = await videoSpecs(for: asset)
            let durationValue = await duration
            let resourceValues = try? url.resourceValues(forKeys: [
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey
            ])

            func metadata(with durationValue: Double?) -> VideoMetadata {
                return VideoMetadata(
                    duration: durationValue,
                    frameRate: specs.frameRate,
                    pixelWidth: specs.pixelWidth,
                    pixelHeight: specs.pixelHeight,
                    fileSize: resourceValues?.fileSize.map(Int64.init),
                    createdAt: resourceValues?.creationDate ?? resourceValues?.contentModificationDate,
                    modifiedAt: resourceValues?.contentModificationDate
                )
            }

            guard shouldGenerateThumbnail else {
                return (nil, nil, durationValue, metadata(with: durationValue), false)
            }

            guard specs.pixelWidth != nil,
                  specs.pixelHeight != nil,
                  let durationValue,
                  durationValue.isFinite,
                  durationValue > 0
            else {
                return (nil, nil, durationValue, metadata(with: durationValue), true)
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

            var bestCandidate: (data: Data, image: NSImage, score: Double)?
            for seconds in metadataThumbnailCandidateTimes(duration: durationValue) {
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                guard let candidate = await thumbnailCandidate(from: generator, at: time) else { continue }

                if candidate.score > (bestCandidate?.score ?? -1) {
                    bestCandidate = candidate
                }

                if candidate.score > 0.18 {
                    return (candidate.data, candidate.image, durationValue, metadata(with: durationValue), true)
                }
            }

            return (
                bestCandidate?.data,
                bestCandidate?.image,
                durationValue,
                metadata(with: durationValue),
                true
            )
        }.value
    }

    nonisolated static func metadataThumbnailCandidateTimes(duration: Double) -> [Double] {
        let duration = max(0, duration)
        guard duration > 0 else { return [] }

        let rawCandidates = [
            min(1.0, duration * 0.12),
            min(2.5, duration * 0.28),
            min(5.0, duration * 0.50),
            min(8.0, duration * 0.72),
            0.1
        ]

        var seen = Set<Int>()
        return rawCandidates.compactMap { raw in
            let seconds = min(max(0, raw), max(0, duration - 0.05))
            let key = Int((seconds * 1000).rounded())
            guard seen.insert(key).inserted else { return nil }
            return seconds
        }
    }

    nonisolated static func durationSeconds(for asset: AVURLAsset) async -> Double? {
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    nonisolated static func musicGenreTags(for asset: AVURLAsset, title: String) async -> [String] {
        let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
        var rawTags: [String] = []

        for format in formats {
            guard let items = try? await asset.loadMetadata(for: format) else { continue }
            for item in items {
                guard let text = await musicGenreText(from: item) else { continue }
                rawTags.append(contentsOf: splitMusicGenreText(text))
            }
        }

        return MusicRecognitionItem.cleanedGenreTags(rawTags, title: title)
    }

    nonisolated static func musicGenreText(from item: AVMetadataItem) async -> String? {
        let keyText: String
        if let key = item.key as? String {
            keyText = key
        } else if let key = item.key {
            keyText = String(describing: key)
        } else {
            keyText = ""
        }

        let searchableKey = [
            item.identifier?.rawValue ?? "",
            item.commonKey?.rawValue ?? "",
            keyText
        ]
        .joined(separator: " ")
        .lowercased()

        guard searchableKey.contains("genre")
            || searchableKey.contains("contenttype")
            || searchableKey.contains("tcon")
        else {
            return nil
        }

        if let stringValue = try? await item.load(.stringValue) {
            return stringValue
        }
        if let dataValue = try? await item.load(.dataValue),
           let stringValue = String(data: dataValue, encoding: .utf8) {
            return stringValue
        }
        if let value = try? await item.load(.value) {
            return String(describing: value)
        }
        return nil
    }

    nonisolated static func splitMusicGenreText(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ",，/、;；|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func videoSpecs(for asset: AVURLAsset) async -> (frameRate: Double?, pixelWidth: Int?, pixelHeight: Int?) {
        guard
            let tracks = try? await asset.loadTracks(withMediaType: .video),
            let track = tracks.first
        else { return (nil, nil, nil) }

        let frameRate = (try? await track.load(.nominalFrameRate)).map(Double.init)
        let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let transformed = naturalSize.applying(transform)
        let width = Int(abs(transformed.width).rounded())
        let height = Int(abs(transformed.height).rounded())
        return (frameRate, width > 0 ? width : nil, height > 0 ? height : nil)
    }

    nonisolated static func thumbnailCandidate(
        from generator: AVAssetImageGenerator,
        at time: CMTime
    ) async -> (data: Data, image: NSImage, score: Double)? {
        await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, _ in
                guard result == .succeeded, let image else {
                    continuation.resume(returning: nil)
                    return
                }

                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) else {
                    continuation.resume(returning: nil)
                    return
                }
                let thumbnailImage = decodedThumbnailImage(from: data) ?? NSImage(
                    cgImage: image,
                    size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height))
                )

                continuation.resume(returning: (data, thumbnailImage, imageContentScore(image)))
            }
        }
    }

    nonisolated static func decodedThumbnailImage(from data: Data) -> NSImage? {
        let options: CFDictionary = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary

        guard
            let source = CGImageSourceCreateWithData(data as CFData, options),
            let image = CGImageSourceCreateImageAtIndex(source, 0, options)
        else {
            return NSImage(data: data)
        }

        return NSImage(
            cgImage: image,
            size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height))
        )
    }

    nonisolated static func imageContentScore(_ image: CGImage) -> Double {
        let width = 24
        let height = 24
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        return pixels.withUnsafeMutableBytes { rawBuffer in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return 0
            }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            var total = 0.0
            var totalSquared = 0.0
            var brightPixels = 0
            let count = width * height
            let byteCount = bytesPerRow * height

            for offset in stride(from: 0, to: byteCount, by: 4) {
                let r = Double(rawBuffer[offset]) / 255.0
                let g = Double(rawBuffer[offset + 1]) / 255.0
                let b = Double(rawBuffer[offset + 2]) / 255.0
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                total += luma
                totalSquared += luma * luma

                if luma > 0.12 {
                    brightPixels += 1
                }
            }

            let average = total / Double(count)
            let variance = max(0, totalSquared / Double(count) - average * average)
            let visibleRatio = Double(brightPixels) / Double(count)
            return average * 0.48 + sqrt(variance) * 0.32 + visibleRatio * 0.20
        }
    }

    nonisolated static func renderFrameData(for url: URL, at seconds: Double) async -> Data? {
        await Task.detached(priority: .utility) {
            guard let image = await renderFrameImageSynchronously(for: url, at: seconds) else { return nil }
            return jpegData(from: image)
        }.value
    }

    nonisolated static func renderFrameImage(for url: URL, at seconds: Double) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            await renderFrameImageSynchronously(for: url, at: seconds)
        }.value
    }

    nonisolated static func renderFrameImageSynchronously(for url: URL, at seconds: Double) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 4096, height: 4096)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)
        return await sceneThumbnailImage(from: generator, at: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
    }

    nonisolated static func jpegData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }

    nonisolated static func frameDragItemProvider(
        videoURL: URL,
        videoName: String,
        time: Double,
        kind: SampledFrame.Kind?,
        fallbackData: Data?
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        let filename = frameDragFilename(videoName: videoName, time: time, kind: kind)
        provider.suggestedName = filename

        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.jpeg.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            let progress = Progress(totalUnitCount: 1)
            Task.detached(priority: .userInitiated) {
                do {
                    let fileURL = try await Self.renderFrameDragFile(
                        videoURL: videoURL,
                        videoName: videoName,
                        time: time,
                        kind: kind,
                        fallbackData: fallbackData
                    )
                    progress.completedUnitCount = 1
                    completion(fileURL, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return progress
        }

        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.jpeg.identifier,
            visibility: .all
        ) { completion in
            let progress = Progress(totalUnitCount: 1)
            Task.detached(priority: .userInitiated) {
                guard let data = await Self.fullResolutionJPEGData(for: videoURL, at: time) ?? fallbackData else {
                    completion(nil, Self.frameDragError())
                    return
                }
                progress.completedUnitCount = 1
                completion(data, nil)
            }
            return progress
        }

        return provider
    }

    nonisolated static func renderFrameDragFile(
        videoURL: URL,
        videoName: String,
        time: Double,
        kind: SampledFrame.Kind?,
        fallbackData: Data?
    ) async throws -> URL {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapianBaoDragExports", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        Self.cleanOldFrameDragExports(in: folderURL)

        let fileURL = folderURL.appendingPathComponent(Self.frameDragFilename(videoName: videoName, time: time, kind: kind))
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }

        guard let data = await Self.fullResolutionJPEGData(for: videoURL, at: time) ?? fallbackData else {
            throw Self.frameDragError()
        }

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    nonisolated static func fullResolutionJPEGData(for url: URL, at seconds: Double) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)

        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        guard let image = await generatedCGImage(from: generator, at: time) else { return nil }

        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.96])
    }

    nonisolated static func generatedCGImage(from generator: AVAssetImageGenerator, at time: CMTime) async -> CGImage? {
        await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, _ in
                guard result == .succeeded, let image else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    nonisolated static func frameDragFilename(videoName: String, time: Double, kind: SampledFrame.Kind?) -> String {
        let suffix: String
        switch kind {
        case .screenshot:
            suffix = "screenshot"
        case .sceneRepresentative:
            suffix = "scene"
        case nil:
            suffix = "frame"
        }

        let milliseconds = Int((max(0, time) * 1000).rounded()) % 1000
        return "\(safeFileStem(videoName))_\(fileTimecode(time))-\(String(format: "%03d", milliseconds))_\(suffix)_fullres.jpg"
    }

    nonisolated static func cleanOldFrameDragExports(in folderURL: URL) {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for fileURL in fileURLs {
            let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            if modifiedAt < cutoff {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    nonisolated static func frameDragError() -> NSError {
        NSError(
            domain: "LapianBao.FrameDragExport",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "无法导出这张画面"]
        )
    }

    func saveImageExport(data: Data, video: VideoItem, time: Double, preferredExtension: String) -> URL? {
        let folder = imageExportDestination(for: video)
        let baseName = "\(Self.compactFileStem(video.name, maxLength: 96))_\(Self.fileTimecode(time))"
        let outputURL = Self.uniqueExportURL(
            in: folder,
            baseName: baseName,
            preferredExtension: preferredExtension
        )
        do {
            try data.write(to: outputURL, options: .atomic)
            return outputURL
        } catch {
            NSLog("LapianBao image export failed: %@ -> %@", outputURL.path, String(describing: error))
            return nil
        }
    }

    func imageExportDestination(for video: VideoItem) -> URL {
        let folder = libraryURL.map {
            Self.mediaFolder(in: $0, named: Self.imageExportFolderName)
        } ?? video.url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func imageExportURL(for frame: SampledFrame) -> URL? {
        imageExportURLs(for: frame).first ?? restoreImageExportFileIfNeeded(for: frame)
    }

    func imageExportURLs(for frame: SampledFrame) -> [URL] {
        let video = VideoItem(url: URL(fileURLWithPath: frame.videoPath))
        let folder = imageExportDestination(for: video)
        return imageExportURLs(in: folder, baseName: imageExportBaseName(for: frame))
    }

    func restoreImageExportFileIfNeeded(for frame: SampledFrame) -> URL? {
        let video = VideoItem(url: URL(fileURLWithPath: frame.videoPath))
        let folder = imageExportDestination(for: video)
        let url = folder.appendingPathComponent("\(imageExportBaseName(for: frame)).jpg")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        do {
            try frame.thumbnailData.write(to: url, options: .atomic)
            return url
        } catch {
            NSLog("LapianBao failed to restore image export from thumbnail data: %@ %@", url.path, String(describing: error))
            return nil
        }
    }

    func imageExportBaseName(for frame: SampledFrame) -> String {
        "\(Self.compactFileStem(frame.videoName, maxLength: 96))_\(Self.fileTimecode(frame.time))"
    }

    func imageExportURLs(in folder: URL, baseName: String) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { url in
                let stem = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension.lowercased()
                return Self.imageExportFileExtensions.contains(ext) && (stem == baseName || stem.hasPrefix("\(baseName)-"))
            }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return leftDate > rightDate
            }
    }

    nonisolated static var imageExportFileExtensions: Set<String> {
        ["jpg", "jpeg", "png", "heic", "tif", "tiff", "webp"]
    }

    nonisolated static func generatedImageExportBaseName(for url: URL) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent
        let pattern = #"^(.+_[0-9]{2}-[0-9]{2}(?:-[0-9]{2})?)(?:-[0-9]+)?$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: stem,
                range: NSRange(stem.startIndex..<stem.endIndex, in: stem)
            ),
            let range = Range(match.range(at: 1), in: stem)
        else {
            return nil
        }
        return String(stem[range])
    }

    nonisolated static func uniqueExportURL(in folder: URL, baseName: String, preferredExtension: String) -> URL {
        let cleanExtension = preferredExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let fileExtension = cleanExtension.isEmpty ? "jpg" : cleanExtension
        var candidate = folder.appendingPathComponent("\(baseName).\(fileExtension)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName)-\(suffix).\(fileExtension)")
            suffix += 1
        }
        return candidate
    }

    nonisolated static func compactFileStem(_ name: String, maxLength: Int) -> String {
        let stem = safeFileStem(name)
        guard stem.count > maxLength else { return stem }
        let end = stem.suffix(12)
        let prefixCount = max(1, maxLength - end.count - 1)
        return "\(stem.prefix(prefixCount))-\(end)"
    }

    func writeFrameIndex() {
        guard let libraryURL else { return }
        let folder = Self.mediaFolder(in: libraryURL, named: Self.imageExportFolderName)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let frames = sampledFrames.sorted {
            if $0.videoName == $1.videoName { return $0.time < $1.time }
            return $0.videoName.localizedStandardCompare($1.videoName) == .orderedAscending
        }
        let lines = frames.enumerated().map { index, frame in
            let kind = frame.kind == .screenshot ? "截图" : "场景代表帧"
            return "\(index + 1). \(frame.videoName) · \(Self.clockText(frame.time)) · \(kind)"
        }
        let body = lines.isEmpty ? "暂无导出图片。\n" : lines.joined(separator: "\n") + "\n"
        let markdown = "# 拉片宝图片导出索引\n\n" + body
        try? markdown.write(to: folder.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
    }

    nonisolated enum AudioClipExportError: LocalizedError {
        case libraryMissing
        case noAudioTrack
        case exporterUnavailable
        case emptyOutput
        case ffmpegMissing
        case ffmpegFailed(String)
        case avFoundationFailed(String)

        var errorDescription: String? {
            switch self {
            case .libraryMissing:
                return "请先打开一个素材库文件夹"
            case .noAudioTrack:
                return "这个视频没有可导出的音轨"
            case .exporterUnavailable:
                return "系统音频导出器不可用"
            case .emptyOutput:
                return "声音文件导出为空"
            case .ffmpegMissing:
                return "系统导出失败，且找不到 ffmpeg"
            case let .ffmpegFailed(message):
                return message.isEmpty ? "ffmpeg 导出声音失败" : message
            case let .avFoundationFailed(message):
                return message.isEmpty ? "系统导出声音失败" : message
            }
        }
    }

    nonisolated static func exportAudioClipFile(video: VideoItem, videoName: String, start: Double, end: Double, libraryURL: URL?) async throws -> URL {
        try await Task.detached(priority: .utility) {
            guard let libraryURL else { throw AudioClipExportError.libraryMissing }
            let folder = mediaFolder(in: libraryURL, named: soundEffectExportFolderName)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let baseName = "\(compactFileStem(videoName, maxLength: 96))_\(fileTimecode(start))-\(fileTimecode(end))"
            let outputURL = uniqueExportURL(in: folder, baseName: baseName, preferredExtension: "m4a")

            let asset = AVURLAsset(url: video.url)
            let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
            guard audioTracks?.isEmpty == false else { throw AudioClipExportError.noAudioTrack }

            do {
                try await exportAudioClipWithAVFoundation(asset: asset, outputURL: outputURL, start: start, end: end)
                return outputURL
            } catch let exportError as AudioClipExportError {
                try? FileManager.default.removeItem(at: outputURL)
                switch exportError {
                case .exporterUnavailable, .emptyOutput, .avFoundationFailed:
                    break
                default:
                    throw exportError
                }
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
            }

            try exportAudioClipWithFFmpeg(videoURL: video.url, outputURL: outputURL, start: start, end: end)
            return outputURL
        }.value
    }

    nonisolated static func exportAudioClipWithAVFoundation(
        asset: AVURLAsset,
        outputURL: URL,
        start: Double,
        end: Double
    ) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioClipExportError.exporterUnavailable
        }
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: max(0, start), preferredTimescale: 600),
            duration: CMTime(seconds: max(0.01, end - start), preferredTimescale: 600)
        )

        do {
            try await session.export(to: outputURL, as: .m4a)
        } catch {
            throw AudioClipExportError.avFoundationFailed(error.localizedDescription)
        }
        guard audioExportFileIsUsable(outputURL) else {
            throw AudioClipExportError.emptyOutput
        }
    }

    nonisolated static func exportAudioClipWithFFmpeg(
        videoURL: URL,
        outputURL: URL,
        start: Double,
        end: Double
    ) throws {
        guard let ffmpegURL = ffmpegExecutableURL() else {
            throw AudioClipExportError.ffmpegMissing
        }

        let duration = max(0.01, end - start)
        let result = ExternalProcessRunner.run(
            executableURL: ffmpegURL,
            arguments: [
                "-y",
                "-hide_banner",
                "-loglevel", "error",
                "-i", videoURL.path,
                "-ss", String(format: "%.3f", max(0, start)),
                "-t", String(format: "%.3f", duration),
                "-vn",
                "-map", "0:a:0",
                "-c:a", "aac",
                "-b:a", "192k",
                "-movflags", "+faststart",
                outputURL.path
            ],
            qualityOfService: .utility
        )

        guard result.succeeded else {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioClipExportError.ffmpegFailed(
                result.errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard audioExportFileIsUsable(outputURL) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioClipExportError.emptyOutput
        }
    }

    nonisolated static func audioExportFileIsUsable(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return (values?.fileSize ?? 0) > 0
    }

    nonisolated static func ffmpegExecutableURL() -> URL? {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        return paths
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    nonisolated static func runWhisperTranscription(
        video: VideoItem,
        videoName: String,
        libraryURL: URL?,
        progressCallback: (@Sendable (Double, String) -> Void)? = nil,
        processRegistry: ToolProcessRegistry? = nil
    ) async throws -> [TranscriptSegment] {
        let task = Task.detached(priority: .utility) {
            progressCallback?(0.01, "准备字幕分析")
            guard let scriptURL = localToolURL(
                relativePath: "Tools/transcribe_with_whisper.sh",
                mustBeExecutable: true
            ) else {
                throw NSError(domain: "LapianBao", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到本地 Whisper 转写脚本"])
            }

            let baseFolder = (libraryURL ?? video.url.deletingLastPathComponent())
                .appendingPathComponent("LapianBaoExports", isDirectory: true)
                .appendingPathComponent("Transcripts", isDirectory: true)
            try FileManager.default.createDirectory(at: baseFolder, withIntermediateDirectories: true)
            let outputBase = baseFolder.appendingPathComponent(safeFileStem(videoName))

            let process = Process()
            process.executableURL = scriptURL
            process.arguments = [video.url.path, outputBase.path, "auto"]

            var environment = ProcessInfo.processInfo.environment
            let extraPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = [environment["PATH"], extraPath]
                .compactMap { $0 }
                .joined(separator: ":")
            process.environment = environment

            let logURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("LapianBao-whisper-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let logHandle = try FileHandle(forWritingTo: logURL)
            defer {
                try? logHandle.close()
                try? FileManager.default.removeItem(at: logURL)
            }
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            let outputCollector = PipeLineCollector()
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                try? logHandle.write(contentsOf: chunk)
                for line in outputCollector.append(chunk) {
                    if let update = parseWhisperProgressUpdate(line) {
                        progressCallback?(update.progress, update.message)
                    }
                }
            }
            try Task.checkCancellation()
            try process.run()
            processRegistry?.set(process)
            process.waitUntilExit()
            processRegistry?.set(nil)
            outputPipe.fileHandleForReading.readabilityHandler = nil
            let remainingOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if !remainingOutput.isEmpty {
                try? logHandle.write(contentsOf: remainingOutput)
            }
            for line in outputCollector.finish(with: remainingOutput) {
                if let update = parseWhisperProgressUpdate(line) {
                    progressCallback?(update.progress, update.message)
                }
            }

            try Task.checkCancellation()
            guard process.terminationStatus == 0 else {
                let logData = (try? Data(contentsOf: logURL)) ?? Data()
                let fullMessage = String(data: logData, encoding: .utf8) ?? "本地转写失败"
                let message = trimmedProcessLog(fullMessage, fallback: "本地转写失败")
                throw NSError(domain: "LapianBao", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
            }

            let jsonURL = outputBase.appendingPathExtension("json")
            progressCallback?(0.98, "载入字幕结果")
            let data = try Data(contentsOf: jsonURL)
            let segments = try parseWhisperSegments(data: data, videoPath: video.url.path)
            let cleanedSegments = cleanTranscriptSegments(segments)
            progressCallback?(1.0, "字幕分析完成")
            return cleanedSegments
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
            processRegistry?.cancelRunningProcess()
        }
    }

    nonisolated struct WhisperProgressUpdate: Sendable {
        let progress: Double
        let message: String
    }

    nonisolated static func parseWhisperProgressUpdate(_ line: String) -> WhisperProgressUpdate? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("LPB_PROGRESS") {
            let parts = trimmed.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count >= 2, let value = Double(parts[1]) else { return nil }
            let message = parts.count >= 3 ? parts[2] : "字幕分析中"
            return WhisperProgressUpdate(progress: normalizedProgress(value), message: message)
        }

        guard let percent = parsePercentValue(from: trimmed) else { return nil }
        return WhisperProgressUpdate(
            progress: min(0.94, 0.18 + normalizedProgress(percent / 100) * 0.76),
            message: "本地 Whisper 转写"
        )
    }

    nonisolated static func parsePercentValue(from line: String) -> Double? {
        let normalized = line.replacingOccurrences(of: "％", with: "%")
        guard let percentRange = normalized.range(of: "%", options: .backwards) else { return nil }
        let prefix = normalized[..<percentRange.lowerBound]
        let chars = Array(prefix)
        var start = chars.count

        while start > 0 {
            let char = chars[start - 1]
            if char.isNumber || char == "." {
                start -= 1
            } else {
                break
            }
        }

        guard start < chars.count else { return nil }
        return Double(String(chars[start...]))
    }

    nonisolated static func trimmedProcessLog(_ message: String, fallback: String) -> String {
        let lines = message
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let tail = lines.suffix(12).joined(separator: "\n")
        return tail.isEmpty ? fallback : tail
    }

    nonisolated struct WhisperOutput: Decodable {
        let transcription: [WhisperSegment]?
        let segments: [WhisperSegment]?
    }

    nonisolated struct WhisperSegment: Decodable {
        let timestamps: WhisperTimestamps?
        let offsets: WhisperOffsets?
        let text: String?
        let start: Double?
        let end: Double?
    }

    nonisolated struct WhisperTimestamps: Decodable {
        let from: String?
        let to: String?
    }

    nonisolated struct WhisperOffsets: Decodable {
        let from: Int?
        let to: Int?
    }

    nonisolated static func parseWhisperSegments(data: Data, videoPath: String) throws -> [TranscriptSegment] {
        let output = try JSONDecoder().decode(WhisperOutput.self, from: data)
        let rawSegments = output.transcription ?? output.segments ?? []
        return rawSegments.compactMap { segment in
            let start = segment.start
                ?? segment.offsets?.from.map { Double($0) / 1000.0 }
                ?? segment.timestamps?.from.flatMap(parseTimestamp)
                ?? 0
            let end = segment.end
                ?? segment.offsets?.to.map { Double($0) / 1000.0 }
                ?? segment.timestamps?.to.flatMap(parseTimestamp)
                ?? start
            let text = segment.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(videoPath: videoPath, start: start, end: end, text: text)
        }
    }

    nonisolated static func cleanTranscriptSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var cleaned: [TranscriptSegment] = []
        var recentOccurrences: [String: [Double]] = [:]
        var totalOccurrences: [String: Int] = [:]
        let rollingWindow: Double = 180

        for rawSegment in segments.sorted(by: { $0.start < $1.start }) {
            var segment = rawSegment
            segment.text = collapseRepeatedSentences(in: segment.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segment.text.isEmpty else { continue }
            guard segment.end > segment.start else { continue }

            let key = transcriptRepeatKey(segment.text)
            guard key.count >= 2 else { continue }

            if let last = cleaned.last,
               transcriptRepeatKey(last.text) == key,
               segment.start - last.end <= 2.0 {
                cleaned[cleaned.count - 1].end = max(last.end, segment.end)
                continue
            }

            let recent = recentOccurrences[key, default: []]
                .filter { segment.start - $0 <= rollingWindow }
            let total = totalOccurrences[key, default: 0]
            let repeatedInShortWindow = key.count >= 6 && recent.count >= 2
            let repeatedTooOften = key.count >= 4 && total >= 4
            if repeatedInShortWindow || repeatedTooOften {
                recentOccurrences[key] = recent + [segment.start]
                totalOccurrences[key] = total + 1
                continue
            }

            recentOccurrences[key] = recent + [segment.start]
            totalOccurrences[key] = total + 1
            cleaned.append(segment)
        }

        return mergeShortGaps(cleaned)
    }

    nonisolated static func mergeShortGaps(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var merged: [TranscriptSegment] = []
        for segment in segments {
            guard let last = merged.last else {
                merged.append(segment)
                continue
            }

            let sameVideo = last.videoPath == segment.videoPath
            let close = segment.start - last.end <= 0.25
            let combinedText = "\(last.text)\(segment.text)"
            if sameVideo, close, combinedText.count <= 42 {
                var updated = last
                updated.end = max(last.end, segment.end)
                updated.text = "\(last.text) \(segment.text)"
                merged[merged.count - 1] = updated
            } else {
                merged.append(segment)
            }
        }
        return merged
    }

    nonisolated static func collapseRepeatedSentences(in text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        var result: [String] = []
        let pattern = #"[^。！？!?;；，,]+[。！？!?;；，,]?"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            for match in regex.matches(in: normalized, range: range) {
                guard let textRange = Range(match.range, in: normalized) else { continue }
                let sentence = String(normalized[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sentence.isEmpty else { continue }
                if result.last.map(transcriptRepeatKey) == transcriptRepeatKey(sentence) {
                    continue
                }
                result.append(sentence)
            }
        }

        return result.isEmpty ? normalized : result.joined(separator: " ")
    }

    nonisolated static func transcriptRepeatKey(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[[:punct:][:symbol:]，。！？；：“”‘’、（）《》【】—…·]"#, with: "", options: .regularExpression)
    }

    nonisolated static func parseTimestamp(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return nil }
        let seconds = Double(parts.last ?? "") ?? 0
        let minutes = Double(parts.dropLast().last ?? "") ?? 0
        let hours = parts.count > 2 ? (Double(parts.first ?? "") ?? 0) : 0
        return hours * 3600 + minutes * 60 + seconds
    }

    nonisolated static func safeFileStem(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = name.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "video" : sanitized
    }

    nonisolated static func fileTimecode(_ seconds: Double) -> String {
        clockText(seconds).replacingOccurrences(of: ":", with: "-")
    }

    nonisolated static func clockText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    nonisolated static func makeWaveformSamples(
        for url: URL,
        sampleCount: Int,
        start: Double? = nil,
        end: Double? = nil,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async -> [Double]? {
        let task = Task<[Double]?, Never>.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            guard
                let tracks = try? await asset.loadTracks(withMediaType: .audio),
                let track = tracks.first,
                let reader = try? AVAssetReader(asset: asset)
            else {
                return nil
            }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsBigEndianKey: false
            ]

            let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else { return nil }
            reader.add(output)

            if let start, let end, end > start {
                reader.timeRange = CMTimeRange(
                    start: CMTime(seconds: max(0, start), preferredTimescale: 600),
                    duration: CMTime(seconds: max(0.01, end - start), preferredTimescale: 600)
                )
            }

            guard reader.startReading() else { return nil }

            var peaks: [Double] = []
            var currentPeak = 0.0
            var samplesInWindow = 0
            let windowSize = 512
            let loadedDuration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
            let progressStart = max(0, start ?? 0)
            let progressEnd: Double
            if let end, end > progressStart {
                progressEnd = end
            } else if loadedDuration.isFinite, loadedDuration > progressStart {
                progressEnd = loadedDuration
            } else {
                progressEnd = progressStart
            }
            let progressDuration = max(0, progressEnd - progressStart)
            var lastReportedProgress = -1.0

            func reportProgress(_ value: Double) {
                guard let progressHandler else { return }
                let progress = min(1, max(0, value))
                guard progress >= 1 || progress - lastReportedProgress >= 0.01 else { return }
                lastReportedProgress = progress
                progressHandler(progress)
            }

            reportProgress(0)

            while !Task.isCancelled,
                  reader.status == .reading,
                  let sampleBuffer = output.copyNextSampleBuffer() {
                if progressDuration > 0 {
                    let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                    let sampleDuration = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer))
                    let bufferEnd = timestamp + (sampleDuration.isFinite ? sampleDuration : 0)
                    if bufferEnd.isFinite {
                        reportProgress(min(0.98, (bufferEnd - progressStart) / progressDuration))
                    }
                }

                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
                let byteCount = CMBlockBufferGetDataLength(blockBuffer)
                guard byteCount > 0 else { continue }

                var data = Data(count: byteCount)
                let copyResult = data.withUnsafeMutableBytes { buffer -> OSStatus in
                    guard let destination = buffer.baseAddress else { return -1 }
                    return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: byteCount, destination: destination)
                }

                guard copyResult == noErr else { continue }

                forEachFloat32Sample(in: data) { sample in
                    currentPeak = max(currentPeak, min(1, Double(abs(sample))))
                    samplesInWindow += 1

                    if samplesInWindow >= windowSize {
                        peaks.append(currentPeak)
                        currentPeak = 0
                        samplesInWindow = 0
                    }
                }
            }

            if Task.isCancelled {
                reader.cancelReading()
                return nil
            }

            if samplesInWindow > 0 {
                peaks.append(currentPeak)
            }

            guard !peaks.isEmpty else { return nil }
            let samples = downsample(peaks, to: sampleCount)
            reportProgress(1)
            return samples
        }

        return await withTaskCancellationHandler(operation: {
            await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    nonisolated static func forEachFloat32Sample(in data: Data, _ body: (Float32) -> Void) {
        let sampleStride = MemoryLayout<Float32>.stride
        data.withUnsafeBytes { rawBuffer in
            let usableByteCount = rawBuffer.count - (rawBuffer.count % sampleStride)
            guard usableByteCount >= sampleStride else { return }

            for offset in stride(from: 0, to: usableByteCount, by: sampleStride) {
                var sample: Float32 = 0
                withUnsafeMutableBytes(of: &sample) { destination in
                    let source = UnsafeRawBufferPointer(rebasing: rawBuffer[offset..<(offset + sampleStride)])
                    destination.copyBytes(from: source)
                }
                body(sample)
            }
        }
    }

    nonisolated static func downsample(_ peaks: [Double], to sampleCount: Int) -> [Double] {
        guard sampleCount > 0 else { return [] }

        let maxPeak = max(peaks.max() ?? 0, 0.0001)
        return (0..<sampleCount).map { index in
            let start = Int(Double(index) * Double(peaks.count) / Double(sampleCount))
            let rawEnd = Int(Double(index + 1) * Double(peaks.count) / Double(sampleCount))
            let end = min(max(start + 1, rawEnd), peaks.count)
            let value = peaks[start..<end].max() ?? 0
            return sqrt(min(1, value / maxPeak))
        }
    }

}
