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

    func rebuildAllTagsCache() {
        allTagsCache = Array(Set(tagsByVideoPath.values.flatMap { $0 })).sorted()
    }

    func clearVideoSourceCaches() {
        videoSourcePlatformCache.removeAll()
        videoSourceTitleCache.removeAll()
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
        musicTagsCache = Array(Set(recognizedTags + localMusicAssets.flatMap(\.tags))).sorted()
    }

    func refreshFilteredVideos() {
        let scopedVideos: [VideoItem]
        if selectedTags.isEmpty {
            scopedVideos = videos
        } else {
            scopedVideos = videos.filter { video in
                let videoTags = tagsByVideoPath[video.url.path, default: []]
                return selectedTags.allSatisfy { videoTags.contains($0) }
            }
        }

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
                let leftTags = tagsByVideoPath[lhs.url.path, default: []].joined(separator: " ")
                let rightTags = tagsByVideoPath[rhs.url.path, default: []].joined(separator: " ")
                result = leftTags.localizedStandardCompare(rightTags)
            }

            if result == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return sortDirection == .ascending ? result == .orderedAscending : result == .orderedDescending
        }
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
            return cached
        }
        guard let image = NSImage(data: frame.thumbnailData) else { return nil }
        sampledFrameThumbnailImageByID[frame.id] = image
        return image
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

        let provider = NSItemProvider()
        provider.suggestedName = fileURL.lastPathComponent
        let typeIdentifier = UTType(filenameExtension: fileURL.pathExtension)?.identifier ?? UTType.audio.identifier

        provider.registerFileRepresentation(
            forTypeIdentifier: typeIdentifier,
            fileOptions: .openInPlace,
            visibility: .all
        ) { completion in
            let progress = Progress(totalUnitCount: 1)
            progress.completedUnitCount = 1
            completion(fileURL, true, nil)
            return progress
        }

        provider.registerObject(fileURL as NSURL, visibility: .all)
        return provider
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
            applyResourceLibrarySnapshot(cachedSnapshot, libraryPath: libraryPath)
        } else if refreshMode != .cachedOnly {
            hasCachedSnapshot = !loadCachedSnapshotSynchronously
            Task.detached(priority: .utility) { [weak self, libraryURL, libraryPath] in
                let snapshot = Self.loadCachedResourceLibrarySnapshot(in: libraryURL)
                    ?? Self.quickResourceLibrarySnapshot(in: libraryURL)
                await MainActor.run { [weak self] in
                    self?.applyResourceLibrarySnapshot(snapshot, libraryPath: libraryPath)
                }
            }
        }

        guard refreshMode != .cachedOnly else { return }

        if !forceFullScan,
           resourceLibraryScanTask != nil,
           resourceLibraryScanTaskLibraryPath == libraryPath {
            return
        }

        if !forceFullScan,
           let lastFullScanAt = lastResourceLibraryFullScanAtByPath[libraryPath],
           Date().timeIntervalSince(lastFullScanAt) < Self.resourceLibraryFullScanCooldown {
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
        resourceLibraryScanTask = Task.detached(priority: priority) { [weak self, libraryURL, libraryPath, delay, scanGeneration] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }
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
            }
        }
    }

    func applyResourceLibrarySnapshot(_ snapshot: ResourceLibrarySnapshot, libraryPath: String) {
        guard let libraryURL, libraryURL.path == libraryPath else { return }
        let musicPaths = Set(snapshot.music.map(\.filePath))
        let audioPaths = Set(snapshot.audio.map(\.filePath))
        knownLocalResourcePaths = musicPaths.union(audioPaths)
        hydrateLocalWaveformCaches(from: snapshot, libraryURL: libraryURL)

        let musicChanged = localMusicAssets != snapshot.music
        let audioChanged = localAudioAssets != snapshot.audio
        if musicChanged {
            localMusicAssets = snapshot.music
        }
        if audioChanged {
            localAudioAssets = snapshot.audio
        }

        if musicChanged || audioChanged {
            pruneLocalWaveformCaches(musicPaths: musicPaths, audioPaths: audioPaths)
            cleanupInvalidGeneratedAudioClipRecords()
            reconcileMusicDownloadJobsWithLocalAssets(snapshot.music)
        }
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
        guard !assets.isEmpty else { return }
        var assetsByFilename: [String: String] = [:]
        for asset in assets {
            let filename = URL(fileURLWithPath: asset.filePath).lastPathComponent
            assetsByFilename[filename] = assetsByFilename[filename] ?? asset.filePath
        }

        var didChange = false
        for index in musicDownloadJobs.indices {
            guard let oldPath = musicDownloadJobs[index].filePath,
                  !FileManager.default.fileExists(atPath: oldPath)
            else { continue }

            let filename = URL(fileURLWithPath: oldPath).lastPathComponent
            guard let newPath = assetsByFilename[filename],
                  FileManager.default.fileExists(atPath: newPath)
            else { continue }

            musicDownloadJobs[index].filePath = newPath
            didChange = true
        }

        if didChange {
            saveProjectData()
        }
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
        loadMetadataIfNeeded(for: video)
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

    func startDailyDownloaderSelfCheckIfNeeded() {
        startDailyExternalServiceSelfCheckIfNeeded()
    }

    func startDailyExternalServiceSelfCheckIfNeeded() {
        guard !Self.isDownloaderSelfCheckFresh(downloaderSelfCheckReport) else { return }
        startExternalServiceSelfCheck(force: false)
    }

    func startDownloaderSelfCheck(force: Bool = true) {
        startExternalServiceSelfCheck(force: force)
    }

    func startExternalServiceSelfCheck(force: Bool = true) {
        guard downloaderSelfCheckTask == nil else { return }
        guard force || !Self.isDownloaderSelfCheckFresh(downloaderSelfCheckReport) else { return }

        let startedAt = Date()
        updateDownloaderSelfCheckReport(DownloaderSelfCheckReport(
            status: .running,
            checkedAt: startedAt,
            message: "正在自检外部服务"
        ))

        downloaderSelfCheckTask = Task { [weak self] in
            let report = await Self.runDownloaderSelfCheck(startedAt: startedAt)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updateDownloaderSelfCheckReport(report)
                self.downloaderSelfCheckTask = nil
            }
        }
    }

    func prepareExternalServiceWork() {
        startExternalServiceSelfCheckPreflightIfNeeded()
    }

    func startExternalServiceSelfCheckPreflightIfNeeded() {
        guard downloaderSelfCheckTask == nil else { return }
        if let lastExternalSelfCheckPreflightAt,
           Date().timeIntervalSince(lastExternalSelfCheckPreflightAt) < Self.externalSelfCheckPreflightCooldown {
            return
        }
        guard !Self.isDownloaderSelfCheckFresh(downloaderSelfCheckReport) else { return }
        lastExternalSelfCheckPreflightAt = Date()
        startExternalServiceSelfCheck(force: false)
    }

    func updateDownloaderSelfCheckReport(_ report: DownloaderSelfCheckReport) {
        downloaderSelfCheckReport = report
        Self.saveDownloaderSelfCheckReport(report)
    }

    func loadLastLibrary() {
        guard libraryURL == nil else { return }
        guard let url = lastLibraryURLForLoading() else { return }
        scanVideos(in: url)
    }

}
