//
//  LibraryStore+TimelineMedia.swift
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
    nonisolated struct MusicLookupMetadata: Sendable {
        var tags: [String]
        var duration: Double
    }

    func loadWaveform(for video: VideoItem) {
        let path = video.url.path
        noteTransientMediaAccess(for: path)
        guard waveformTasks[path] == nil else { return }
        if let samples = waveformSamplesByVideoPath[path], samples.count >= Self.waveformSampleCount {
            return
        }

        waveformTasks[path] = Task { [weak self] in
            let samples = await Self.makeWaveformSamples(for: video.url, sampleCount: Self.waveformSampleCount) ?? []
            guard !Task.isCancelled else { return }

            self?.noteTransientMediaAccess(for: path)
            self?.waveformSamplesByVideoPath[path] = samples
            self?.waveformTasks[path] = nil
            PerformanceDiagnostics.mark("waveform ready", path: path)
        }
    }

    func seedMusicFileDurations(from assets: [LocalMusicAsset]) {
        var durations = musicFileDurationsByPath
        var didChange = false
        for asset in assets where asset.duration.isFinite && asset.duration > 0 {
            let key = Self.normalizedLocalFilePath(asset.filePath)
            if durations[key] != asset.duration {
                durations[key] = asset.duration
                didChange = true
            }
        }
        if didChange {
            musicFileDurationsByPath = durations
        }
    }

    func ensureMusicFileDurationIfNeeded(filePath: String, knownDuration: Double? = nil) {
        let key = Self.normalizedLocalFilePath(filePath)

        if let knownDuration, knownDuration.isFinite, knownDuration > 0 {
            if musicFileDurationsByPath[key] != knownDuration {
                musicFileDurationsByPath[key] = knownDuration
            }
            return
        }

        if let duration = musicFileDurationsByPath[key], duration.isFinite, duration > 0 {
            return
        }
        guard musicFileDurationTasks[key] == nil,
              FileManager.default.fileExists(atPath: filePath)
        else { return }

        let fileURL = URL(fileURLWithPath: filePath)
        musicFileDurationTasks[key] = Task.detached(priority: .utility) { [weak self, key, fileURL] in
            let asset = AVURLAsset(url: fileURL)
            let duration = await Self.durationSeconds(for: asset) ?? 0
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.musicFileDurationTasks[key] = nil
                guard duration.isFinite, duration > 0,
                      FileManager.default.fileExists(atPath: fileURL.path)
                else { return }
                self.musicFileDurationsByPath[key] = duration
            }
        }
    }

    func loadAudioClipWaveformIfNeeded(_ clip: AudioClipItem) {
        guard !hasCurrentAudioClipWaveform(clip),
              audioClipWaveformTasks[clip.id] == nil
        else { return }

        if pendingAudioClipWaveformIDSet.contains(clip.id) {
            return
        }

        pendingAudioClipWaveformIDs.append(clip.id)
        pendingAudioClipWaveformIDSet.insert(clip.id)
        startQueuedAudioClipWaveforms()
    }

    func hasCurrentAudioClipWaveform(_ clip: AudioClipItem) -> Bool {
        clip.waveformVersion == Self.audioClipWaveformVersion
            && clip.waveformSamples != nil
    }

    func startQueuedAudioClipWaveforms() {
        while audioClipWaveformTasks.count < Self.audioClipWaveformWorkerCount,
              !pendingAudioClipWaveformIDs.isEmpty {
            let clipID = pendingAudioClipWaveformIDs.removeFirst()
            pendingAudioClipWaveformIDSet.remove(clipID)

            guard let clip = audioClips.first(where: { $0.id == clipID }),
                  !hasCurrentAudioClipWaveform(clip),
                  audioClipWaveformTasks[clipID] == nil
            else { continue }

            let clipFileURL = audioClipFileURL(for: clip)
            let url = clipFileURL ?? URL(fileURLWithPath: clip.videoPath)
            let start = clipFileURL == nil ? clip.inTime : nil
            let end = clipFileURL == nil ? clip.outTime : nil

            let task = Task.detached(priority: .utility) { [weak self, clipID, url, start, end] in
                let samples = await Self.makeWaveformSamples(
                    for: url,
                    sampleCount: Self.audioClipWaveformSampleCount,
                    start: start,
                    end: end
                ) ?? []
                guard !Task.isCancelled else { return }

                await MainActor.run { [weak self] in
                    self?.finishAudioClipWaveform(id: clipID, samples: samples)
                }
            }
            audioClipWaveformTasks[clipID] = task
        }
    }

    func finishAudioClipWaveform(id: UUID, samples: [Double]) {
        guard audioClipWaveformTasks[id] != nil else { return }
        audioClipWaveformTasks[id] = nil
        setAudioClipWaveform(id: id, samples: samples)
        startQueuedAudioClipWaveforms()
    }

    func hydrateLocalWaveformCaches(from snapshot: ResourceLibrarySnapshot, libraryURL: URL) {
        let libraryPath = libraryURL.path
        let shouldLoadCache = localWaveformCacheLibraryPath != libraryPath || localWaveformCacheByKey.isEmpty
        let currentCache = localWaveformCacheByKey

        if localWaveformCacheLibraryPath != libraryPath {
            localWaveformCacheSaveTask?.cancel()
            localWaveformCacheSaveTask = nil
            localWaveformCacheNeedsSave = false
            localWaveformCacheByKey = [:]
            localWaveformCacheLibraryPath = libraryPath
        }

        localWaveformCacheHydrationTask?.cancel()
        localWaveformCacheHydrationTask = Task.detached(priority: .utility) { [weak self, snapshot, libraryURL, libraryPath, shouldLoadCache, currentCache] in
            let cache = shouldLoadCache ? Self.loadLocalWaveformCache(in: libraryURL) : currentCache
            let result = Self.localWaveformHydrationResult(
                from: snapshot,
                libraryURL: libraryURL,
                cacheByKey: cache
            )
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self, self.libraryURL?.path == libraryPath else { return }
                self.localWaveformCacheHydrationTask = nil

                if self.localMusicWaveformSamplesByPath != result.hydratedMusic {
                    self.localMusicWaveformSamplesByPath = result.hydratedMusic
                }
                if self.localAudioWaveformSamplesByPath != result.hydratedAudio {
                    self.localAudioWaveformSamplesByPath = result.hydratedAudio
                }
                if self.localWaveformCacheByKey != result.retainedCache {
                    self.localWaveformCacheByKey = result.retainedCache
                    if cache != result.retainedCache {
                        self.scheduleLocalWaveformCacheSave()
                    }
                }
            }
        }
    }

    func ensureLocalMusicWaveformIfNeeded(_ asset: LocalMusicAsset) {
        let path = asset.filePath
        if localMusicWaveformSamplesByPath[path]?.count == Self.localMusicWaveformSampleCount {
            return
        }
        guard localMusicWaveformTasks[path] == nil,
              FileManager.default.fileExists(atPath: path)
        else { return }

        let fileURL = URL(fileURLWithPath: path)
        let libraryURL = libraryURL
        let fileSize = asset.fileSize
        let modifiedAt = asset.modifiedAt

        localMusicWaveformTasks[path] = Task.detached(priority: .utility) { [weak self, fileURL, path, libraryURL, fileSize, modifiedAt] in
            let samples = await Self.makeWaveformSamples(
                for: fileURL,
                sampleCount: Self.localMusicWaveformSampleCount
            ) ?? []
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.localMusicWaveformTasks[path] = nil

                guard let currentAsset = self.localMusicAssets.first(where: { $0.filePath == path }),
                      currentAsset.fileSize == fileSize,
                      currentAsset.modifiedAt == modifiedAt
                else { return }

                self.localMusicWaveformSamplesByPath[path] = samples
                guard samples.count == Self.localMusicWaveformSampleCount,
                      let libraryURL,
                      self.libraryURL?.path == libraryURL.path
                else { return }

                let relativePath = Self.libraryRelativePath(for: fileURL, base: libraryURL)
                let key = Self.localWaveformCacheKey(kind: "music", relativePath: relativePath)
                self.localWaveformCacheByKey[key] = LocalWaveformCacheEntry(
                    kind: "music",
                    relativePath: relativePath,
                    fileIdentity: Self.localWaveformFileIdentity(for: fileURL),
                    fileSize: fileSize,
                    modificationTime: Self.localWaveformModificationTime(modifiedAt),
                    sampleCount: Self.localMusicWaveformSampleCount,
                    samples: samples
                )
                self.scheduleLocalWaveformCacheSave()
            }
        }
    }

    nonisolated static func localWaveformHydrationResult(
        from snapshot: ResourceLibrarySnapshot,
        libraryURL: URL,
        cacheByKey: [String: LocalWaveformCacheEntry]
    ) -> LocalWaveformHydrationResult {
        var retainedCache: [String: LocalWaveformCacheEntry] = [:]
        var hydratedMusic: [String: [Double]] = [:]
        var hydratedAudio: [String: [Double]] = [:]
        let cacheByIdentity = localWaveformIdentityCacheIndex(cacheByKey)

        for asset in snapshot.music {
            let assetURL = URL(fileURLWithPath: asset.filePath)
            let relativePath = libraryRelativePath(for: assetURL, base: libraryURL)
            let key = localWaveformCacheKey(kind: "music", relativePath: relativePath)
            guard let entry = matchLocalWaveformCacheEntry(
                entriesByKey: cacheByKey,
                entriesByIdentity: cacheByIdentity,
                kind: "music",
                relativePath: relativePath,
                fileIdentity: localWaveformFileIdentity(for: assetURL),
                fileSize: asset.fileSize,
                modifiedAt: asset.modifiedAt,
                sampleCount: localMusicWaveformSampleCount
            )
            else { continue }

            retainedCache[key] = entry
            hydratedMusic[asset.filePath] = entry.samples
        }

        for asset in snapshot.audio {
            let assetURL = URL(fileURLWithPath: asset.filePath)
            let relativePath = libraryRelativePath(for: assetURL, base: libraryURL)
            let key = localWaveformCacheKey(kind: "audio", relativePath: relativePath)
            guard let entry = matchLocalWaveformCacheEntry(
                entriesByKey: cacheByKey,
                entriesByIdentity: cacheByIdentity,
                kind: "audio",
                relativePath: relativePath,
                fileIdentity: localWaveformFileIdentity(for: assetURL),
                fileSize: asset.fileSize,
                modifiedAt: asset.modifiedAt,
                sampleCount: localAudioWaveformSampleCount
            )
            else { continue }

            retainedCache[key] = entry
            hydratedAudio[asset.filePath] = entry.samples
        }

        return LocalWaveformHydrationResult(
            retainedCache: retainedCache,
            hydratedMusic: hydratedMusic,
            hydratedAudio: hydratedAudio
        )
    }

    func scheduleLocalWaveformCacheSave() {
        guard let libraryURL else { return }
        localWaveformCacheNeedsSave = true
        guard localWaveformCacheSaveTask == nil else { return }
        let libraryPath = libraryURL.path

        localWaveformCacheSaveTask = Task.detached(priority: .utility) { [weak self, libraryURL, libraryPath] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }

                let entriesByKey = await MainActor.run { [weak self] () -> [String: LocalWaveformCacheEntry]? in
                    guard let self, self.libraryURL?.path == libraryPath else { return nil }
                    self.localWaveformCacheNeedsSave = false
                    return self.localWaveformCacheByKey
                }
                guard let entriesByKey else { return }
                Self.saveLocalWaveformCache(entriesByKey, in: libraryURL)

                let shouldContinue = await MainActor.run { [weak self] () -> Bool in
                    guard let self, self.libraryURL?.path == libraryPath else { return false }
                    if self.localWaveformCacheNeedsSave {
                        return true
                    }
                    self.localWaveformCacheSaveTask = nil
                    return false
                }
                if !shouldContinue { return }
            }
        }
    }

    nonisolated static func localWaveformCacheURL(in libraryURL: URL) -> URL {
        ProjectRepository.localWaveformsURL(in: libraryURL)
    }

    nonisolated static func localWaveformCacheKey(kind: String, relativePath: String) -> String {
        "\(kind)|\(relativePath)"
    }

    nonisolated static func localWaveformIdentityCacheKey(kind: String, fileIdentity: String) -> String {
        "\(kind)|\(fileIdentity)"
    }

    nonisolated static func localWaveformFileIdentity(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber
        else { return nil }
        return "\(device.int64Value):\(inode.uint64Value)"
    }

    nonisolated static func localWaveformIdentityCacheIndex(
        _ entriesByKey: [String: LocalWaveformCacheEntry]
    ) -> [String: LocalWaveformCacheEntry] {
        var entriesByIdentity: [String: LocalWaveformCacheEntry] = [:]
        for entry in entriesByKey.values {
            guard let fileIdentity = entry.fileIdentity else { continue }
            entriesByIdentity[localWaveformIdentityCacheKey(kind: entry.kind, fileIdentity: fileIdentity)] = entry
        }
        return entriesByIdentity
    }

    nonisolated static func matchLocalWaveformCacheEntry(
        entriesByKey: [String: LocalWaveformCacheEntry],
        entriesByIdentity: [String: LocalWaveformCacheEntry],
        kind: String,
        relativePath: String,
        fileIdentity: String?,
        fileSize: Int64,
        modifiedAt: Date?,
        sampleCount: Int
    ) -> LocalWaveformCacheEntry? {
        let pathKey = localWaveformCacheKey(kind: kind, relativePath: relativePath)
        if var entry = entriesByKey[pathKey],
           isValidLocalWaveformCacheEntry(
               entry,
               kind: kind,
               relativePath: relativePath,
               fileSize: fileSize,
               modifiedAt: modifiedAt,
               sampleCount: sampleCount
           ) {
            if entry.fileIdentity == nil {
                entry.fileIdentity = fileIdentity
            }
            return entry
        }

        guard let fileIdentity,
              var entry = entriesByIdentity[localWaveformIdentityCacheKey(kind: kind, fileIdentity: fileIdentity)],
              isValidLocalWaveformCacheEntry(
                  entry,
                  kind: kind,
                  relativePath: nil,
                  fileSize: fileSize,
                  modifiedAt: modifiedAt,
                  sampleCount: sampleCount
              )
        else { return nil }

        entry.relativePath = relativePath
        entry.fileIdentity = fileIdentity
        return entry
    }

    nonisolated static func loadLocalWaveformCache(in libraryURL: URL) -> [String: LocalWaveformCacheEntry] {
        let url = localWaveformCacheURL(in: libraryURL)
        guard
            let cache = ProjectRepository.readJSON(LocalWaveformCacheFile.self, from: url),
            cache.version == localWaveformCacheVersion
        else { return [:] }

        var entriesByKey: [String: LocalWaveformCacheEntry] = [:]
        for entry in cache.entries {
            entriesByKey[localWaveformCacheKey(kind: entry.kind, relativePath: entry.relativePath)] = entry
        }
        return entriesByKey
    }

    nonisolated static func saveLocalWaveformCache(
        _ entriesByKey: [String: LocalWaveformCacheEntry],
        in libraryURL: URL
    ) {
        let entries = entriesByKey.values.sorted {
            if $0.kind == $1.kind {
                return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
            return $0.kind < $1.kind
        }
        let cache = LocalWaveformCacheFile(
            version: localWaveformCacheVersion,
            generatedAt: Date(),
            entries: entries
        )
        try? ProjectRepository.writeJSON(
            cache,
            to: localWaveformCacheURL(in: libraryURL),
            encoder: ProjectRepository.prettySortedEncoder
        )
    }

    nonisolated static func isValidLocalWaveformCacheEntry(
        _ entry: LocalWaveformCacheEntry,
        kind: String,
        relativePath: String?,
        fileSize: Int64,
        modifiedAt: Date?,
        sampleCount: Int
    ) -> Bool {
        entry.kind == kind
            && entry.fileSize == fileSize
            && entry.sampleCount == sampleCount
            && entry.samples.count == sampleCount
            && (relativePath == nil || entry.relativePath == relativePath)
            && localWaveformModificationTimeMatches(entry.modificationTime, modifiedAt)
    }

    nonisolated static func localWaveformModificationTime(_ date: Date?) -> Double? {
        date?.timeIntervalSinceReferenceDate
    }

    nonisolated static func localWaveformModificationTimeMatches(_ cached: Double?, _ currentDate: Date?) -> Bool {
        let current = localWaveformModificationTime(currentDate)
        switch (cached, current) {
        case (.none, .none):
            return true
        case let (.some(lhs), .some(rhs)):
            return abs(lhs - rhs) < 0.01
        default:
            return false
        }
    }

    func setAudioClipWaveform(id: UUID, samples: [Double]) {
        guard let index = audioClips.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        audioClips[index].waveformSamples = samples
        audioClips[index].waveformVersion = Self.audioClipWaveformVersion
        saveProjectData()
    }

    func loadFrameStrip(for video: VideoItem) {
        let path = video.url.path
        noteTransientMediaAccess(for: path)
        if let frames = frameStripByVideoPath[path], !frames.isEmpty,
           let images = frameStripImagesByVideoPath[path], !images.isEmpty {
            return
        }
        guard frameStripTasks[path] == nil else { return }

        frameStripTasks[path] = Task { [weak self] in
            let frames = await Self.makeFrameStrip(for: video.url)
            guard !Task.isCancelled else { return }

            guard let self else { return }
            self.noteTransientMediaAccess(for: path)
            self.frameStripTasks[path] = nil

            guard !frames.isEmpty else {
                self.finishEmptyFrameStripLoad(for: video, path: path, reason: "empty")
                return
            }

            let images = frames.compactMap { NSImage(data: $0) }
            guard !images.isEmpty else {
                self.finishEmptyFrameStripLoad(for: video, path: path, reason: "decode-empty")
                return
            }

            self.frameStripEmptyRetryCountsByPath.removeValue(forKey: path)
            self.frameStripByVideoPath[path] = frames
            self.frameStripImagesByVideoPath[path] = images
            self.updateSceneStripImages(for: path)
            PerformanceDiagnostics.mark("frame strip ready", path: path)
        }
    }

    func finishEmptyFrameStripLoad(for video: VideoItem, path: String, reason: String) {
        frameStripByVideoPath.removeValue(forKey: path)
        frameStripImagesByVideoPath.removeValue(forKey: path)
        updateSceneStripImages(for: path)
        PerformanceDiagnostics.mark("frame strip \(reason)", path: path)

        let retryCount = frameStripEmptyRetryCountsByPath[path, default: 0]
        guard retryCount < Self.frameStripEmptyRetryLimit else { return }
        frameStripEmptyRetryCountsByPath[path] = retryCount + 1
        scheduleFrameStripRetry(for: video, delay: Self.frameStripEmptyRetryDelay * Double(retryCount + 1))
    }

    func scheduleFrameStripRetry(for video: VideoItem, delay: TimeInterval) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.loadFrameStrip(for: video)
        }
    }

    nonisolated static func makeFrameStrip(for url: URL, count: Int = 16) async -> [Data] {
        let frameTask = Task.detached(priority: .utility) { () -> [Data] in
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration) else { return [] }
            let totalSeconds = CMTimeGetSeconds(duration)
            guard totalSeconds.isFinite, totalSeconds > 0 else { return [] }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 120, height: 68)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

            var results: [(index: Int, data: Data)] = []

            for i in 0..<count {
                let seconds = totalSeconds * (Double(i) + 0.5) / Double(count)
                let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
                let data: Data? = await withCheckedContinuation { continuation in
                    generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { _, image, _, result, _ in
                        guard result == .succeeded, let image else {
                            continuation.resume(returning: nil)
                            return
                        }
                        let bitmap = NSBitmapImageRep(cgImage: image)
                        let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
                        continuation.resume(returning: jpegData)
                    }
                }
                if let data {
                    results.append((index: i, data: data))
                }
            }

            return results.sorted { $0.index < $1.index }.map(\.data)
        }
        return await frameTask.value
    }

    func detectSceneCuts(for video: VideoItem, force: Bool = false) {
        let path = video.url.path
        if !force {
            loadCachedSceneCuts(for: video)
        }
        guard
            sceneDetectionTasks[path] == nil,
            sceneDetectionProgress[path] == nil
        else { return }
        guard force || sceneCutsByVideoPath[path] == nil else { return }

        if force {
            sceneThumbnailHydrationTasks[path]?.cancel()
            sceneThumbnailHydrationTasks[path] = nil
            sceneThumbnailHydrationNeeded.remove(path)
        }

        sceneDetectionErrorByVideoPath.removeValue(forKey: path)
        sceneDetectionProgress[path] = 0.0

        sceneDetectionTasks[path] = Task { [weak self] in
            do {
                let cuts = try await Self.performSceneDetection(for: video.url) { progress in
                    Task { @MainActor in
                        self?.sceneDetectionProgress[path] = Self.normalizedProgress(progress)
                    }
                }

                guard !Task.isCancelled else {
                    self?.sceneDetectionProgress[path] = nil
                    self?.sceneDetectionTasks[path] = nil
                    return
                }

                self?.finishSceneDetection(for: video, cuts: cuts)
                self?.sceneDetectionProgress[path] = nil
                self?.sceneDetectionTasks[path] = nil
            } catch is CancellationError {
                self?.sceneDetectionProgress[path] = nil
                self?.sceneDetectionTasks[path] = nil
            } catch {
                self?.sceneDetectionErrorByVideoPath[path] = Self.sceneDetectionErrorMessage(error)
                self?.sceneDetectionProgress[path] = nil
                self?.sceneDetectionTasks[path] = nil
                return
            }
        }
    }

    nonisolated static func sceneDetectionErrorMessage(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }

    func finishSceneDetection(for video: VideoItem, cuts: [SceneCut]) {
        let path = video.url.path
        sceneDetectionErrorByVideoPath.removeValue(forKey: path)
        setSceneCuts(cuts, for: path)
        storeSceneCutCache(for: video, cuts: cuts)
    }

    func deleteSceneRecognition(for video: VideoItem) {
        let path = video.url.path
        sceneDetectionTasks[path]?.cancel()
        sceneDetectionTasks[path] = nil
        sceneThumbnailHydrationTasks[path]?.cancel()
        sceneThumbnailHydrationTasks[path] = nil
        sceneThumbnailHydrationNeeded.remove(path)
        sceneCutsByVideoPath.removeValue(forKey: path)
        sceneStripImagesByVideoPath.removeValue(forKey: path)
        sceneCutProgressesByVideoPath.removeValue(forKey: path)
        sceneThumbnailVersionsByVideoPath.removeValue(forKey: path)
        sceneDetectionProgress.removeValue(forKey: path)
        sceneDetectionErrorByVideoPath.removeValue(forKey: path)
        sceneCutCache.removeValue(forKey: relativeVideoPath(for: video.url))
        saveSceneCutCache()
    }

    func startSceneBatch(onlyMissing: Bool = true) {
        guard sceneBatchTask == nil else { return }
        let queue = videos.filter { video in
            if onlyMissing {
                return !hasSceneRecognitionResult(for: video)
            }
            return true
        }
        guard !queue.isEmpty else {
            sceneBatchJob = TranscriptBatchJob(status: .completed, total: 0, completed: 0, progress: 1)
            return
        }

        isSceneBatchPaused = false
        sceneBatchJob = TranscriptBatchJob(status: .running, total: queue.count, completed: 0, progress: 0)
        sceneBatchTask = Task { [weak self] in
            guard let self else { return }
            var completed = 0

            for video in queue {
                while await MainActor.run(body: { self.isSceneBatchPaused }) {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                if Task.isCancelled { break }

                let path = video.url.path
                await MainActor.run {
                    self.sceneBatchJob.status = .running
                    self.sceneBatchJob.currentVideoPath = path
                    self.sceneBatchJob.currentVideoName = video.name
                    self.sceneDetectionErrorByVideoPath.removeValue(forKey: path)
                    self.sceneDetectionProgress[path] = 0
                    self.updateSceneBatchProgress(completed: completed, currentProgress: 0)
                }

                do {
                    let cuts = try await Self.performSceneDetection(for: video.url) { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.sceneDetectionProgress[path] = Self.normalizedProgress(progress)
                            self?.updateSceneBatchProgress(completed: completed, currentProgress: progress)
                        }
                    }

                    completed += 1
                    await MainActor.run {
                        self.finishSceneDetection(for: video, cuts: cuts)
                        self.sceneDetectionProgress[path] = nil
                        self.updateSceneBatchProgress(completed: completed, currentProgress: 0)
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.sceneDetectionProgress[path] = nil
                    }
                    break
                } catch {
                    completed += 1
                    await MainActor.run {
                        self.sceneDetectionErrorByVideoPath[path] = Self.sceneDetectionErrorMessage(error)
                        self.sceneDetectionProgress[path] = nil
                        self.updateSceneBatchProgress(completed: completed, currentProgress: 0)
                    }
                }
            }

            await MainActor.run {
                self.sceneBatchTask = nil
                if self.sceneBatchJob.completed >= self.sceneBatchJob.total {
                    self.sceneBatchJob.status = .completed
                    self.sceneBatchJob.currentVideoPath = nil
                    self.sceneBatchJob.currentVideoName = nil
                    self.sceneBatchJob.progress = 1
                }
            }
        }
    }

    func resumeSceneBatch() {
        guard sceneBatchTask != nil else { return }
        isSceneBatchPaused = false
        sceneBatchJob.status = .running
    }

    func updateSceneBatchProgress(completed: Int, currentProgress: Double) {
        let total = max(1, sceneBatchJob.total)
        sceneBatchJob.completed = completed
        sceneBatchJob.progress = Self.normalizedProgress((Double(completed) + Self.normalizedProgress(currentProgress)) / Double(total))
    }

    func loadCachedSceneCuts(for video: VideoItem) {
        let path = video.url.path
        noteTransientMediaAccess(for: path)
        guard
            sceneCutsByVideoPath[path] == nil,
            sceneDetectionTasks[path] == nil,
            let cachedEntry = validCachedSceneCutEntry(for: video)
        else { return }

        let placeholder = thumbnailImageByVideoPath[path] ?? Self.scenePlaceholderImage()
        let cachedCuts = Self.cachedSceneCuts(from: cachedEntry, placeholderImage: placeholder)
        setSceneCuts(cachedCuts.cuts, for: path, needsThumbnailHydration: cachedCuts.needsThumbnailHydration)
    }

    func hydrateSceneThumbnailsIfNeeded(for video: VideoItem) {
        let path = video.url.path
        noteTransientMediaAccess(for: path)
        guard
            sceneThumbnailHydrationNeeded.contains(path),
            sceneThumbnailHydrationTasks[path] == nil,
            let cachedEntry = validCachedSceneCutEntry(for: video),
            !cachedEntry.cutTimes.isEmpty
        else { return }

        bumpSceneThumbnailVersion(for: path)
        sceneThumbnailHydrationTasks[path] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else {
                self?.sceneThumbnailHydrationTasks[path] = nil
                self?.bumpSceneThumbnailVersion(for: path)
                return
            }

            let cuts = await Self.sceneCuts(from: cachedEntry.cutTimes, for: video.url)
            guard !Task.isCancelled else {
                self?.sceneThumbnailHydrationTasks[path] = nil
                self?.bumpSceneThumbnailVersion(for: path)
                return
            }
            guard !cuts.isEmpty else {
                self?.sceneThumbnailHydrationNeeded.remove(path)
                self?.sceneThumbnailHydrationTasks[path] = nil
                self?.bumpSceneThumbnailVersion(for: path)
                return
            }

            self?.setSceneCuts(cuts, for: path)
            self?.storeSceneCutCache(for: video, cuts: cuts)
            self?.sceneThumbnailHydrationTasks[path] = nil
            self?.bumpSceneThumbnailVersion(for: path)
        }
    }

    func cancelSceneThumbnailHydration(for video: VideoItem) {
        let path = video.url.path
        sceneThumbnailHydrationTasks[path]?.cancel()
        sceneThumbnailHydrationTasks[path] = nil
        bumpSceneThumbnailVersion(for: path)
    }

    func cancelAllSceneThumbnailHydration() {
        sceneThumbnailHydrationTasks.values.forEach { $0.cancel() }
        sceneThumbnailHydrationTasks.removeAll()
        for path in sceneThumbnailHydrationNeeded {
            bumpSceneThumbnailVersion(for: path)
        }
    }

    static func lightweightSceneCuts(from cutTimes: [Double], placeholderImage: NSImage) -> [SceneCut] {
        stableSceneCutTimes(from: cutTimes).enumerated().map { index, time in
            SceneCut(
                id: sceneCutID(index: index, time: time),
                time: time,
                thumbnailImage: placeholderImage,
                isPlaceholder: true
            )
        }
    }

    nonisolated static func cachedSceneCuts(
        from entry: SceneCutCacheEntry,
        placeholderImage: NSImage
    ) -> (cuts: [SceneCut], needsThumbnailHydration: Bool) {
        var needsThumbnailHydration = false
        let payloads = orderedCachedSceneCutPayloads(from: entry)

        let cuts = payloads.enumerated().map { index, payload in
            if let data = payload.thumbnailData,
               let image = NSImage(data: data) {
                return SceneCut(
                    id: sceneCutID(index: index, time: payload.time),
                    time: payload.time,
                    thumbnailImage: image
                )
            }

            needsThumbnailHydration = true
            return SceneCut(
                id: sceneCutID(index: index, time: payload.time),
                time: payload.time,
                thumbnailImage: placeholderImage,
                isPlaceholder: true
            )
        }

        return (cuts, needsThumbnailHydration)
    }

    nonisolated static func orderedCachedSceneCutPayloads(
        from entry: SceneCutCacheEntry
    ) -> [(time: Double, thumbnailData: Data?)] {
        let thumbnails = entry.thumbnailData ?? []
        let rawPayloads = entry.cutTimes.enumerated().compactMap { index, rawTime -> (time: Double, thumbnailData: Data?)? in
            guard rawTime.isFinite else { return nil }
            let time = max(0, (rawTime * 1000).rounded() / 1000)
            return (time, index < thumbnails.count ? thumbnails[index] : nil)
        }
        .sorted { $0.time < $1.time }

        var payloads: [(time: Double, thumbnailData: Data?)] = []
        var previous: Double?
        for payload in rawPayloads {
            guard previous.map({ payload.time - $0 >= 0.3 }) ?? true else { continue }
            payloads.append(payload)
            previous = payload.time
        }

        return payloads
    }

    nonisolated static func scenePlaceholderImage() -> NSImage {
        let width = 200
        let height = 113
        let size = NSSize(width: width, height: height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return NSImage(size: size)
        }

        context.setFillColor(CGColor(gray: 0.16, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            return NSImage(size: size)
        }
        return NSImage(cgImage: image, size: size)
    }

    func setSceneCuts(
        _ cuts: [SceneCut],
        for path: String,
        needsThumbnailHydration: Bool = false
    ) {
        noteTransientMediaAccess(for: path)
        sceneDetectionErrorByVideoPath.removeValue(forKey: path)
        sceneCutsByVideoPath[path] = cuts
        let shouldHydrateThumbnails = needsThumbnailHydration || cuts.contains { $0.isPlaceholder }
        if shouldHydrateThumbnails {
            sceneThumbnailHydrationNeeded.insert(path)
        } else {
            sceneThumbnailHydrationNeeded.remove(path)
        }
        updateSceneStripImages(for: path)
        bumpSceneThumbnailVersion(for: path)
        let progresses = Self.normalizedSceneCutProgresses(
            from: cuts.map(\.time),
            duration: durationByVideoPath[path] ?? 0
        )
        if cuts.isEmpty || !progresses.isEmpty {
            sceneCutProgressesByVideoPath[path] = progresses
        } else {
            sceneCutProgressesByVideoPath.removeValue(forKey: path)
        }
        PerformanceDiagnostics.mark("scene cuts set", path: path)
    }

    func updateSceneStripImages(for path: String) {
        guard let cuts = sceneCutsByVideoPath[path], !cuts.isEmpty else {
            sceneStripImagesByVideoPath.removeValue(forKey: path)
            bumpSceneThumbnailVersion(for: path)
            return
        }

        let cutImages = cuts.compactMap { displaySceneCutImage(for: path, cut: $0) }
        guard cutImages.count == cuts.count else {
            sceneStripImagesByVideoPath.removeValue(forKey: path)
            bumpSceneThumbnailVersion(for: path)
            return
        }

        if cuts.first.map({ $0.time <= 0.001 }) == true {
            sceneStripImagesByVideoPath[path] = cutImages
            bumpSceneThumbnailVersion(for: path)
            return
        }

        guard let firstFrame = frameStripImagesByVideoPath[path]?.first ?? thumbnailImageByVideoPath[path] else {
            sceneStripImagesByVideoPath.removeValue(forKey: path)
            bumpSceneThumbnailVersion(for: path)
            return
        }
        sceneStripImagesByVideoPath[path] = [firstFrame] + cutImages
        bumpSceneThumbnailVersion(for: path)
    }

    func sceneThumbnailsNeedHydration(for video: VideoItem) -> Bool {
        sceneThumbnailHydrationNeeded.contains(video.url.path)
    }

    func isHydratingSceneThumbnails(for video: VideoItem) -> Bool {
        sceneThumbnailHydrationTasks[video.url.path] != nil
    }

    func displaySceneCutImage(for video: VideoItem, cut: SceneCut) -> NSImage? {
        displaySceneCutImage(for: video.url.path, cut: cut)
    }

    func displaySceneCutImage(for path: String, cut: SceneCut) -> NSImage? {
        guard cut.isPlaceholder else { return cut.thumbnailImage }
        return approximateFrameStripImage(for: path, at: cut.time)
            ?? thumbnailImageByVideoPath[path]
    }

    func approximateFrameStripImage(for path: String, at time: Double) -> NSImage? {
        guard let images = frameStripImagesByVideoPath[path], !images.isEmpty else { return nil }
        let duration = durationByVideoPath[path] ?? 0
        guard duration > 0, images.count > 1 else { return images.first }
        let progress = min(1, max(0, time / duration))
        let index = min(images.count - 1, max(0, Int((progress * Double(images.count - 1)).rounded())))
        return images[index]
    }

    func bumpSceneThumbnailVersion(for path: String) {
        sceneThumbnailVersionsByVideoPath[path, default: 0] += 1
    }

    func addAnnotation(video: VideoItem, time: Double, text: String, kind: AnnotationItem.Kind = .frame) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        annotations.append(AnnotationItem(
            videoPath: video.url.path,
            videoName: video.name,
            time: max(0, time),
            kind: kind,
            text: trimmed
        ))
        saveProjectData()
    }

    func updateAnnotation(_ annotation: AnnotationItem, text: String) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        annotations[index].updatedAt = Date()
        saveProjectData()
    }

    func deleteAnnotation(_ annotation: AnnotationItem) {
        annotations.removeAll { $0.id == annotation.id }
        saveProjectData()
    }

    @discardableResult
    func deleteSampledFrame(_ frame: SampledFrame) -> Bool {
        let fileURLs = imageExportURLsToDelete(for: frame, excludingFrameIDs: [frame.id])
        for url in fileURLs {
            guard trashLibraryFileIfPresent(url, context: "sampled frame export") else { return false }
        }

        sampledFrames.removeAll { $0.id == frame.id }
        writeFrameIndex()
        saveProjectData()
        return true
    }

    @discardableResult
    func deleteAudioClip(_ clip: AudioClipItem) -> Bool {
        guard trashLibraryFileIfPresent(audioClipFileURL(for: clip), context: "audio clip export") else { return false }

        audioClipWaveformTasks[clip.id]?.cancel()
        audioClipWaveformTasks[clip.id] = nil
        pendingAudioClipWaveformIDSet.remove(clip.id)
        pendingAudioClipWaveformIDs.removeAll { $0 == clip.id }
        audioClips.removeAll { $0.id == clip.id }
        saveProjectData()
        return true
    }

    @discardableResult
    func trashLibraryFileIfPresent(_ url: URL?, context: String) -> Bool {
        guard let url else { return true }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return true }

        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            NSLog("LapianBao failed to move %@ to Trash: %@ %@", context, url.path, String(describing: error))
            return false
        }
    }

    func imageExportURLsToDelete(for frame: SampledFrame, excludingFrameIDs excludedFrameIDs: Set<UUID>) -> [URL] {
        let baseName = imageExportBaseName(for: frame)
        let matchingURLs = imageExportURLs(for: frame)
        guard !matchingURLs.isEmpty else { return [] }

        let remainingRecordCount = sampledFrames.filter {
            !excludedFrameIDs.contains($0.id) && imageExportBaseName(for: $0) == baseName
        }.count
        guard matchingURLs.count > remainingRecordCount else { return [] }

        return Array(matchingURLs.prefix(matchingURLs.count - remainingRecordCount))
    }

    func addFrameTag(_ rawTag: String, to frame: SampledFrame) {
        updateFrameTags(frame) { tags in
            appendTag(rawTag, to: &tags)
        }
    }

    func removeFrameTag(_ tag: String, from frame: SampledFrame) {
        updateFrameTags(frame) { tags in
            tags.removeAll { $0 == tag }
        }
    }

    @discardableResult
    func removeFrameTagOrDeleteIfEmpty(_ tag: String, from frame: SampledFrame) -> Bool {
        let currentFrame = sampledFrame(id: frame.id) ?? frame
        guard currentFrame.tags.contains(tag) else { return false }

        let remainingTags = currentFrame.tags.filter { $0 != tag }
        guard remainingTags.isEmpty else {
            removeFrameTag(tag, from: currentFrame)
            return false
        }

        return deleteSampledFrame(currentFrame)
    }

    func addAudioTag(_ rawTag: String, to clip: AudioClipItem) {
        updateAudioTags(clip) { tags in
            appendTag(rawTag, to: &tags)
        }
    }

    func removeAudioTag(_ tag: String, from clip: AudioClipItem) {
        updateAudioTags(clip) { tags in
            tags.removeAll { $0 == tag }
        }
    }

    func addMusicTag(_ rawTag: String, to song: MusicRecognitionItem, in videoPath: String) {
        updateMusicTags(song, in: videoPath) { tags in
            appendTag(rawTag, to: &tags)
        }
    }

    func removeMusicTag(_ tag: String, from song: MusicRecognitionItem, in videoPath: String) {
        updateMusicTags(song, in: videoPath) { tags in
            tags.removeAll { $0 == tag }
        }
    }

    func addLocalAudioTag(_ rawTag: String, to asset: LocalAudioAsset) {
        updateLocalAudioTags(asset) { tags in
            appendTag(rawTag, to: &tags)
        }
    }

    func removeLocalAudioTag(_ tag: String, from asset: LocalAudioAsset) {
        updateLocalAudioTags(asset) { tags in
            tags.removeAll { $0 == tag }
        }
    }

    func addLocalMusicTag(_ rawTag: String, to asset: LocalMusicAsset) {
        updateLocalMusicTags(asset) { tags in
            appendTag(rawTag, to: &tags)
        }
    }

    func removeLocalMusicTag(_ tag: String, from asset: LocalMusicAsset) {
        updateLocalMusicTags(asset) { tags in
            tags.removeAll { $0 == tag }
        }
    }

    func enrichMusicTagsIfNeeded(includeLocalAssets: Bool = true) {
        sanitizeMusicTagsIfNeeded()

        enrichRecognizedMusicTagsIfNeeded()
        if includeLocalAssets {
            enrichLocalMusicAssetTagsIfNeeded()
        }
    }

    func enrichRecognizedMusicTagsIfNeeded() {
        let candidates = musicsByVideoPath.flatMap { path, songs in
            songs.map { (path: path, song: $0) }
        }

        for candidate in candidates where shouldEnrichMusicTags(candidate.song) {
            let key = musicTagEnrichmentKey(for: candidate.song, in: candidate.path)
            guard musicTagEnrichmentTasks[key] == nil else { continue }

            musicTagEnrichmentTasks[key] = Task { [weak self] in
                let metadata = await Self.lookupMusicMetadata(title: candidate.song.title, artist: candidate.song.artist)
                await MainActor.run {
                    defer { self?.musicTagEnrichmentTasks[key] = nil }
                    guard !metadata.tags.isEmpty || metadata.duration > 0 else { return }
                    self?.mergeMusicMetadata(metadata, into: candidate.song, in: candidate.path)
                }
            }
        }
    }

    func enrichLocalMusicAssetTagsIfNeeded() {
        for asset in localMusicAssets {
            guard let seed = localMusicEnrichmentSeed(for: asset),
                  shouldEnrichLocalMusicAsset(asset, seed: seed)
            else { continue }

            let key = localMusicTagEnrichmentKey(for: asset, title: seed.title, artist: seed.artist)
            guard musicTagEnrichmentTasks[key] == nil else { continue }

            musicTagEnrichmentTasks[key] = Task { [weak self] in
                let metadata = await Self.lookupMusicMetadata(title: seed.title, artist: seed.artist)
                await MainActor.run {
                    defer { self?.musicTagEnrichmentTasks[key] = nil }
                    guard !metadata.tags.isEmpty || metadata.duration > 0 else { return }
                    self?.mergeLocalMusicMetadata(
                        metadata,
                        into: asset,
                        title: seed.title,
                        artist: seed.artist
                    )
                }
            }
        }
    }

    func localMusicEnrichmentSeed(
        for asset: LocalMusicAsset
    ) -> (title: String, artist: String, tags: [String])? {
        if let song = musicsByVideoPath[asset.filePath, default: []].first(where: Self.hasRecognizedTitleAndArtist)
            ?? musicsByVideoPath[asset.filePath, default: []].first(where: {
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
            return (
                song.title.trimmingCharacters(in: .whitespacesAndNewlines),
                song.artist.trimmingCharacters(in: .whitespacesAndNewlines),
                song.tags
            )
        }

        let normalizedPath = Self.normalizedLocalFilePath(asset.filePath)
        if let job = musicDownloadJobs.last(where: { job in
            guard let filePath = job.filePath,
                  Self.normalizedLocalFilePath(filePath) == normalizedPath
            else { return false }
            return completedMusicDownloadFileURL(for: job) != nil || FileManager.default.fileExists(atPath: filePath)
        }),
           let song = Self.musicRecognitionItem(fromSongKey: job.songKey, tags: asset.tags) {
            return (
                song.title.trimmingCharacters(in: .whitespacesAndNewlines),
                song.artist.trimmingCharacters(in: .whitespacesAndNewlines),
                song.tags
            )
        }

        let title = asset.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return (title, "", asset.tags)
    }

    func shouldEnrichLocalMusicAsset(
        _ asset: LocalMusicAsset,
        seed: (title: String, artist: String, tags: [String])
    ) -> Bool {
        guard !seed.title.isEmpty || !seed.artist.isEmpty else { return false }
        let existingGenreTags = MusicRecognitionItem.cleanedMusicTags(
            asset.tags + seed.tags,
            title: seed.title,
            artist: seed.artist
        )
        return existingGenreTags.isEmpty ||
            MusicRecognitionItem.hasOnlyFallbackMusicTag(existingGenreTags) ||
            MusicRecognitionItem.hasOnlyDefaultMusicGenreTag(existingGenreTags) ||
            asset.duration <= 0
    }

    func localMusicTagEnrichmentKey(for asset: LocalMusicAsset, title: String, artist: String) -> String {
        "\(asset.filePath)|local|\(title)|\(artist)"
    }

    func mergeMusicMetadata(
        _ metadata: MusicLookupMetadata,
        into song: MusicRecognitionItem,
        in videoPath: String
    ) {
        guard var songs = musicsByVideoPath[videoPath],
              let index = songs.firstIndex(where: { Self.musicItemsMatch($0, song) })
        else { return }

        var updated = songs[index]
        if !metadata.tags.isEmpty {
            updated.tags = MusicRecognitionItem.cleanedMusicTags(
                updated.tags + metadata.tags,
                title: updated.title,
                artist: updated.artist
            )
        }
        if updated.duration <= 0, metadata.duration.isFinite, metadata.duration > 0 {
            updated.duration = metadata.duration
        }

        guard updated != songs[index] else { return }
        songs[index] = updated
        musicsByVideoPath[videoPath] = songs
        saveProjectData()
    }

    func mergeLocalMusicMetadata(
        _ metadata: MusicLookupMetadata,
        into asset: LocalMusicAsset,
        title: String,
        artist: String
    ) {
        var didSaveProjectData = false

        if let index = localMusicAssets.firstIndex(where: { $0.filePath == asset.filePath }) {
            var updatedAssets = localMusicAssets
            var updated = updatedAssets[index]

            if !metadata.tags.isEmpty {
                updated.tags = MusicRecognitionItem.cleanedMusicTags(
                    updated.tags + metadata.tags,
                    title: title,
                    artist: artist
                )
            }
            if updated.duration <= 0, metadata.duration.isFinite, metadata.duration > 0 {
                updated.duration = metadata.duration
                musicFileDurationsByPath[Self.normalizedLocalFilePath(updated.filePath)] = metadata.duration
            }

            if updated != updatedAssets[index] {
                updatedAssets[index] = updated
                localMusicAssets = updatedAssets
                persistLocalResourceAssetTags(path: updated.filePath, tags: updated.tags)
                didSaveProjectData = true
            }
        }

        guard var songs = musicsByVideoPath[asset.filePath] else {
            if !didSaveProjectData {
                saveProjectData()
            }
            return
        }

        var didUpdateSongs = false
        for index in songs.indices where Self.musicItem(songs[index], matchesTitle: title, artist: artist) {
            var updated = songs[index]
            if !metadata.tags.isEmpty {
                updated.tags = MusicRecognitionItem.cleanedMusicTags(
                    updated.tags + metadata.tags,
                    title: updated.title,
                    artist: updated.artist
                )
            }
            if updated.duration <= 0, metadata.duration.isFinite, metadata.duration > 0 {
                updated.duration = metadata.duration
            }
            if updated != songs[index] {
                songs[index] = updated
                didUpdateSongs = true
            }
        }

        if didUpdateSongs {
            musicsByVideoPath[asset.filePath] = songs
            saveProjectData()
        } else if !didSaveProjectData {
            saveProjectData()
        }
    }

    func updateFrameTags(_ frame: SampledFrame, mutate: (inout [String]) -> Void) {
        guard let index = sampledFrames.firstIndex(where: { $0.id == frame.id }) else { return }
        var tags = sampledFrames[index].tags
        mutate(&tags)
        sampledFrames[index].tags = tags.sorted()
        writeFrameIndex()
        saveProjectData()
    }

    func updateAudioTags(_ clip: AudioClipItem, mutate: (inout [String]) -> Void) {
        guard let index = audioClips.firstIndex(where: { $0.id == clip.id }) else { return }
        var tags = audioClips[index].tags
        mutate(&tags)
        audioClips[index].tags = tags.sorted()
        saveProjectData()
    }

    func updateMusicTags(_ song: MusicRecognitionItem, in videoPath: String, mutate: (inout [String]) -> Void) {
        guard var songs = musicsByVideoPath[videoPath],
              let index = songs.firstIndex(where: { Self.musicItemsMatch($0, song) })
        else { return }

        var tags = songs[index].tags
        mutate(&tags)
        songs[index].tags = MusicRecognitionItem.cleanedMusicTags(
            tags,
            title: songs[index].title,
            artist: songs[index].artist
        )
        musicsByVideoPath[videoPath] = songs
        saveProjectData()
    }

    func updateLocalAudioTags(_ asset: LocalAudioAsset, mutate: (inout [String]) -> Void) {
        guard let index = localAudioAssets.firstIndex(where: { $0.filePath == asset.filePath }) else { return }
        var updatedAssets = localAudioAssets
        var tags = updatedAssets[index].tags
        mutate(&tags)
        updatedAssets[index].tags = Self.cleanedResourceTags(tags)
        guard updatedAssets[index].tags != localAudioAssets[index].tags else { return }
        localAudioAssets = updatedAssets
        persistLocalResourceAssetTags(path: asset.filePath, tags: updatedAssets[index].tags)
    }

    func updateLocalMusicTags(_ asset: LocalMusicAsset, mutate: (inout [String]) -> Void) {
        guard let index = localMusicAssets.firstIndex(where: { $0.filePath == asset.filePath }) else { return }
        var updatedAssets = localMusicAssets
        var tags = updatedAssets[index].tags
        mutate(&tags)
        updatedAssets[index].tags = MusicRecognitionItem.cleanedMusicTags(
            tags,
            title: updatedAssets[index].title
        )
        guard updatedAssets[index].tags != localMusicAssets[index].tags else { return }
        localMusicAssets = updatedAssets
        persistLocalResourceAssetTags(path: asset.filePath, tags: updatedAssets[index].tags)
    }

    func persistLocalResourceAssetTags(path: String, tags: [String]) {
        guard let libraryURL else {
            saveProjectData()
            return
        }

        let relativePath = Self.libraryRelativePath(for: URL(fileURLWithPath: path), base: libraryURL)
        var assetTags = Self.loadResourceAssetTags(in: libraryURL)
        if tags.isEmpty {
            assetTags.removeValue(forKey: relativePath)
        } else {
            assetTags[relativePath] = tags
        }
        Self.saveResourceAssetTags(assetTags, in: libraryURL)

        let snapshot = ResourceLibrarySnapshot(music: localMusicAssets, audio: localAudioAssets)
        Self.saveCachedResourceLibrarySnapshot(snapshot, in: libraryURL)
        Task.detached(priority: .background) {
            ResourceLibrarySQLite.write(libraryURL: libraryURL, music: snapshot.music, audio: snapshot.audio)
        }
        saveProjectData()
    }

    func shouldEnrichMusicTags(_ song: MusicRecognitionItem) -> Bool {
        let displayTags = song.displayTags
        return !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (
                displayTags.isEmpty ||
                MusicRecognitionItem.hasOnlyFallbackMusicTag(displayTags) ||
                MusicRecognitionItem.hasOnlyDefaultMusicGenreTag(displayTags) ||
                song.duration <= 0
            )
    }

    func sanitizeMusicTagsIfNeeded() {
        var didChange = false
        var didChangeLocalMusicAssets = false
        var updatedMusics = musicsByVideoPath
        var updatedLocalMusicAssets = localMusicAssets

        for (path, songs) in musicsByVideoPath {
            let cleanedSongs = songs.map { song -> MusicRecognitionItem in
                var cleanedSong = song
                cleanedSong.tags = MusicRecognitionItem.cleanedMusicTags(
                    song.tags,
                    title: song.title,
                    artist: song.artist
                )
                return cleanedSong
            }

            if cleanedSongs != songs {
                updatedMusics[path] = cleanedSongs
                didChange = true
            }
        }

        for index in updatedLocalMusicAssets.indices {
            let cleanedTags = MusicRecognitionItem.cleanedMusicTags(
                updatedLocalMusicAssets[index].tags,
                title: updatedLocalMusicAssets[index].title
            )
            if updatedLocalMusicAssets[index].tags != cleanedTags {
                updatedLocalMusicAssets[index].tags = cleanedTags
                didChange = true
                didChangeLocalMusicAssets = true
            }
        }

        guard didChange else { return }
        musicsByVideoPath = updatedMusics
        localMusicAssets = updatedLocalMusicAssets
        if didChangeLocalMusicAssets, let libraryURL {
            var assetTags = Self.loadResourceAssetTags(in: libraryURL)
            for asset in updatedLocalMusicAssets {
                let relativePath = Self.libraryRelativePath(
                    for: URL(fileURLWithPath: asset.filePath),
                    base: libraryURL
                )
                if asset.tags.isEmpty {
                    assetTags.removeValue(forKey: relativePath)
                } else {
                    assetTags[relativePath] = asset.tags
                }
            }
            Self.saveResourceAssetTags(assetTags, in: libraryURL)

            let snapshot = ResourceLibrarySnapshot(music: updatedLocalMusicAssets, audio: localAudioAssets)
            Self.saveCachedResourceLibrarySnapshot(snapshot, in: libraryURL)
            Task.detached(priority: .background) {
                ResourceLibrarySQLite.write(libraryURL: libraryURL, music: snapshot.music, audio: snapshot.audio)
            }
        }
        saveProjectData()
    }

    func musicTagEnrichmentKey(for song: MusicRecognitionItem, in videoPath: String) -> String {
        "\(videoPath)|\(song.title)|\(song.artist)"
    }

    nonisolated static func musicItemsMatch(_ lhs: MusicRecognitionItem, _ rhs: MusicRecognitionItem) -> Bool {
        lhs.id == rhs.id
            || (
                lhs.title == rhs.title
                    && lhs.artist == rhs.artist
                    && abs(lhs.detectedAt - rhs.detectedAt) < 0.001
            )
    }

    nonisolated static func musicItems(
        _ songs: [MusicRecognitionItem],
        preservingTagsFrom existingSongs: [MusicRecognitionItem]
    ) -> [MusicRecognitionItem] {
        songs.map { musicItem($0, preservingTagsFrom: existingSongs) }
    }

    nonisolated static func musicItem(
        _ song: MusicRecognitionItem,
        preservingTagsFrom existingSongs: [MusicRecognitionItem]
    ) -> MusicRecognitionItem {
        var updated = song
        if let existing = existingSongs.first(where: { sameRecognizedSong($0, song) }) {
            updated.tags = song.tags + existing.tags
            if updated.duration <= 0, existing.duration.isFinite, existing.duration > 0 {
                updated.duration = existing.duration
            }
        }
        updated.tags = MusicRecognitionItem.cleanedMusicTags(
            updated.tags,
            title: updated.title,
            artist: updated.artist
        )
        return updated
    }

    nonisolated static func sameRecognizedSong(_ lhs: MusicRecognitionItem, _ rhs: MusicRecognitionItem) -> Bool {
        lhs.title.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(
            rhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        ) == .orderedSame
            && lhs.artist.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(
                rhs.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            ) == .orderedSame
    }

    nonisolated static func hasRecognizedTitleAndArtist(_ song: MusicRecognitionItem) -> Bool {
        !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !song.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated static func musicItem(
        _ song: MusicRecognitionItem,
        matchesTitle title: String,
        artist: String
    ) -> Bool {
        let expectedTitle = normalizedSearch(title)
        guard !expectedTitle.isEmpty, normalizedSearch(song.title) == expectedTitle else {
            return false
        }

        let expectedArtist = normalizedSearch(artist)
        return expectedArtist.isEmpty || normalizedSearch(song.artist) == expectedArtist
    }

    nonisolated static func lookupMusicTags(title: String, artist: String) async -> [String] {
        await lookupMusicMetadata(title: title, artist: artist).tags
    }

    nonisolated static func lookupMusicMetadata(title: String, artist: String) async -> MusicLookupMetadata {
        let query = "\(artist) \(title)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              var components = URLComponents(string: "https://itunes.apple.com/search")
        else { return MusicLookupMetadata(tags: [], duration: 0) }

        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components.url else { return MusicLookupMetadata(tags: [], duration: 0) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return MusicLookupMetadata(tags: [], duration: 0)
            }
            let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard let result = decoded.results.first(where: { $0.kind == "song" }) else {
                return MusicLookupMetadata(tags: [], duration: 0)
            }
            let tags = MusicRecognitionItem.cleanedGenreTags(
                [result.primaryGenreName ?? ""],
                title: title,
                artist: result.artistName ?? artist
            )
            let duration = (result.trackTimeMillis ?? 0) / 1000
            return MusicLookupMetadata(
                tags: tags,
                duration: duration.isFinite && duration > 0 ? duration : 0
            )
        } catch {
            return MusicLookupMetadata(tags: [], duration: 0)
        }
    }

    nonisolated static func searchAppleMusic(query: String) async throws -> [AppleMusicSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: "https://itunes.apple.com/search")
        else { return [] }

        components.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "country", value: "CN"),
            URLQueryItem(name: "lang", value: "zh_cn")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return []
        }
        let decoded = try JSONDecoder().decode(AppleMusicSearchResponse.self, from: data)
        var seen = Set<Int>()
        return decoded.results
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { seen.insert($0.trackID).inserted }
    }

    func appendTag(_ rawTag: String, to tags: inout [String]) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
    }

}
