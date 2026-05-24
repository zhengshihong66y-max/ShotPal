//
//  LibraryStore.swift
//  LapianBao
//
//  Created by 郑士泓 on 2026/5/24.
//

import AppKit
import AVFoundation
import Combine
import Foundation

struct SceneCut: Identifiable {
    let id = UUID()
    let time: Double
    let thumbnailData: Data
}

struct VideoItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    var folder: String {
        url.deletingLastPathComponent().lastPathComponent
    }

    var fileExtension: String {
        url.pathExtension.uppercased()
    }
}

enum VideoPlaybackSupport: Equatable {
    case playable
    case unsupported(String)

    var message: String? {
        if case let .unsupported(message) = self {
            return message
        }
        return nil
    }
}

struct RemoteImportJob: Identifiable, Equatable {
    enum Status: Equatable {
        case idle
        case importing
        case succeeded(String)
        case failed(String)
    }

    let id = UUID()
    let sourceURL: URL
    let platform: String
    var status: Status
}

struct SceneIndexingStatus: Equatable {
    var isRunning = false
    var completed = 0
    var total = 0
    var currentVideoName: String?

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

nonisolated private final class SceneDetectionProcessRegistry: @unchecked Sendable {
    static let shared = SceneDetectionProcessRegistry()

    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process?) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func cancelRunningProcess() {
        lock.lock()
        let process = process
        self.process = nil
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published var libraryURL: URL?
    @Published var videos: [VideoItem] = []
    @Published var selectedVideo: VideoItem?
    @Published var selectedTags: Set<String> = []
    @Published var tagInput = ""
    @Published var tagsByVideoPath: [String: [String]] = [:]
    @Published var isSidebarVisible = true
    @Published var thumbnailDataByVideoPath: [String: Data] = [:]
    @Published var durationByVideoPath: [String: Double] = [:]
    @Published var playbackSupportByVideoPath: [String: VideoPlaybackSupport] = [:]
    @Published var waveformSamplesByVideoPath: [String: [Double]] = [:]
    @Published var frameStripByVideoPath: [String: [Data]] = [:]
    @Published var sceneCutsByVideoPath: [String: [SceneCut]] = [:]
    @Published var sceneDetectionProgress: [String: Double] = [:]
    @Published var sceneIndexingStatus = SceneIndexingStatus()
    @Published var remoteImportJob: RemoteImportJob?
    @Published var instagramImportEndpoint = UserDefaults.standard.string(forKey: "instagramImportEndpoint") ?? ""

    private let lastLibraryPathKey = "lastLibraryPath"
    private let lastLibraryBookmarkKey = "lastLibraryBookmark"
    private let instagramImportEndpointKey = "instagramImportEndpoint"
    private let defaultLibraryPath = "/Users/zhengshihong/Downloads/通用资源/视觉/视频"
    private let videoExtensions = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]
    private struct SceneCutCacheFile: Codable {
        var detectorVersion: String
        var entries: [String: SceneCutCacheEntry]
    }

    private struct SceneCutCacheEntry: Codable {
        var detectorVersion: String
        var videoID: String
        var relativePath: String
        var fileSize: Int64
        var modificationTime: Double
        var duration: Double?
        var cutTimes: [Double]
        var sceneIDs: [String]
        var generatedAt: Date
    }

    private var thumbnailTasks: [String: Task<Void, Never>] = [:]
    private var waveformTasks: [String: Task<Void, Never>] = [:]
    private var frameStripTasks: [String: Task<Void, Never>] = [:]
    private var sceneDetectionTasks: [String: Task<Void, Never>] = [:]
    private var sceneIndexingTask: Task<Void, Never>?
    private var scopedLibraryURL: URL?
    private var sceneCutCache: [String: SceneCutCacheEntry] = [:]

    nonisolated private static let transNetPythonPath = "/Users/zhengshihong/Downloads/Newtybei知识库/进行项目/拉片宝/LapianBao/Tools/transnet-env/bin/python"
    nonisolated private static let transNetScriptPath = "/Users/zhengshihong/Downloads/Newtybei知识库/进行项目/拉片宝/LapianBao/Tools/detect_scene_cuts_transnet.py"
    nonisolated private static let sceneDetectorVersion = "transnetv2+hardcut-rescue@2026-05-24.2"

    var allTags: [String] {
        let tags = tagsByVideoPath.values.flatMap { $0 }
        return Array(Set(tags)).sorted()
    }

    var filteredVideos: [VideoItem] {
        guard !selectedTags.isEmpty else { return videos }
        return videos.filter { video in
            let videoTags = tagsByVideoPath[video.url.path, default: []]
            return selectedTags.allSatisfy { videoTags.contains($0) }
        }
    }

    func loadLastLibrary() {
        guard libraryURL == nil else { return }

        if let defaultURL = defaultLibraryURL() {
            UserDefaults.standard.set(defaultURL.path, forKey: lastLibraryPathKey)
            scanVideos(in: defaultURL)
            return
        }

        if let bookmarkedURL = restoreLastLibraryBookmark() {
            scanVideos(in: bookmarkedURL)
            return
        }

        guard
            let path = UserDefaults.standard.string(forKey: lastLibraryPathKey),
            FileManager.default.fileExists(atPath: path)
        else { return }

        scanVideos(in: URL(fileURLWithPath: path))
    }

    private func defaultLibraryURL() -> URL? {
        let url = URL(fileURLWithPath: defaultLibraryPath)
        return isExistingDirectory(url) ? url : nil
    }

    private func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "打开文件夹"
        panel.prompt = "打开"

        if panel.runModal() == .OK, let url = panel.url {
            persistLibraryAccess(for: url)
            scanVideos(in: url)
        }
    }

    func saveInstagramImportEndpoint(_ endpoint: String) {
        instagramImportEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(instagramImportEndpoint, forKey: instagramImportEndpointKey)
    }

    func importRemoteVideo(from rawURL: String) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sourceURL = URL(string: trimmed) else {
            remoteImportJob = RemoteImportJob(
                sourceURL: URL(string: "https://instagram.com")!,
                platform: "未知平台",
                status: .failed("请输入有效链接")
            )
            return
        }

        guard let platform = Self.platformName(for: sourceURL), Self.isInstagramURL(sourceURL) else {
            remoteImportJob = RemoteImportJob(
                sourceURL: sourceURL,
                platform: Self.platformName(for: sourceURL) ?? "未知平台",
                status: .failed("当前只接入了 Instagram 下载器")
            )
            return
        }

        guard let libraryURL else {
            remoteImportJob = RemoteImportJob(
                sourceURL: sourceURL,
                platform: platform,
                status: .failed("请先打开一个素材库文件夹")
            )
            return
        }

        let endpoint = instagramImportEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        remoteImportJob = RemoteImportJob(sourceURL: sourceURL, platform: platform, status: .importing)

        Task { [weak self] in
            do {
                let outputURL = try await Self.downloadInstagramVideo(
                    from: sourceURL,
                    into: libraryURL,
                    endpoint: endpoint
                )

                guard !Task.isCancelled else { return }
                self?.remoteImportJob = RemoteImportJob(
                    sourceURL: sourceURL,
                    platform: platform,
                    status: .succeeded(outputURL.lastPathComponent)
                )
                self?.scanVideos(in: libraryURL)
                if let importedVideo = self?.videos.first(where: { $0.url.path == outputURL.path }) {
                    self?.selectedVideo = importedVideo
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.remoteImportJob = RemoteImportJob(
                    sourceURL: sourceURL,
                    platform: platform,
                    status: .failed(error.localizedDescription)
                )
            }
        }
    }

    static func platformName(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if host == "instagram.com"
            || host == "www.instagram.com"
            || host == "m.instagram.com"
            || host == "instagr.am" {
            return "Instagram"
        }
        if host.contains("xiaohongshu.com") || host.contains("xhslink.com") {
            return "小红书"
        }
        return nil
    }

    private static func isInstagramURL(_ url: URL) -> Bool {
        platformName(for: url) == "Instagram"
    }

    private func persistLibraryAccess(for folder: URL) {
        stopAccessingScopedLibrary()

        do {
            let bookmarkData = try folder.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: lastLibraryBookmarkKey)
            UserDefaults.standard.set(folder.path, forKey: lastLibraryPathKey)

            if folder.startAccessingSecurityScopedResource() {
                scopedLibraryURL = folder
            }
        } catch {
            UserDefaults.standard.set(folder.path, forKey: lastLibraryPathKey)
        }
    }

    private func restoreLastLibraryBookmark() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: lastLibraryBookmarkKey) else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            guard FileManager.default.fileExists(atPath: url.path) else { return nil }

            stopAccessingScopedLibrary()
            if url.startAccessingSecurityScopedResource() {
                scopedLibraryURL = url
            }

            if isStale {
                persistLibraryAccess(for: url)
            } else {
                UserDefaults.standard.set(url.path, forKey: lastLibraryPathKey)
            }

            return url
        } catch {
            UserDefaults.standard.removeObject(forKey: lastLibraryBookmarkKey)
            return nil
        }
    }

    private func stopAccessingScopedLibrary() {
        scopedLibraryURL?.stopAccessingSecurityScopedResource()
        scopedLibraryURL = nil
    }

    func scanVideos(in folder: URL) {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let urls = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

        libraryURL = folder
        UserDefaults.standard.set(folder.path, forKey: lastLibraryPathKey)

        videos = urls
            .filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            .map(VideoItem.init(url:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        selectedVideo = videos.first
        selectedTags = []
        tagsByVideoPath = [:]
        frameStripByVideoPath = [:]
        frameStripTasks.values.forEach { $0.cancel() }
        frameStripTasks.removeAll()
        loadTagsJSON()
        loadThumbnails(for: videos)
        loadSceneCutCache()
        startBackgroundSceneIndexing()
    }

    func addTag(to video: VideoItem) {
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }

        var tags = tagsByVideoPath[video.url.path, default: []]
        if !tags.contains(tag) {
            tags.append(tag)
            tagsByVideoPath[video.url.path] = tags.sorted()
        }

        tagInput = ""
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

        for (path, tags) in tagsByVideoPath where tags.contains(old) {
            var updated = tags.filter { $0 != old }
            if !updated.contains(trimmed) { updated.append(trimmed) }
            tagsByVideoPath[path] = updated.sorted()
        }

        if selectedTags.contains(old) {
            selectedTags.remove(old)
            selectedTags.insert(trimmed)
        }
        saveTagsJSON()
    }

    func removeGlobalTag(_ tag: String) {
        for (path, tags) in tagsByVideoPath where tags.contains(tag) {
            tagsByVideoPath[path] = tags.filter { $0 != tag }
        }
        selectedTags.remove(tag)
        saveTagsJSON()
    }

    // MARK: - JSON 持久化

    private func tagsJSONURL() -> URL? {
        guard let libraryURL else { return nil }
        return libraryURL.appendingPathComponent(".lapianbaotags.json")
    }

    func saveTagsJSON() {
        guard let url = tagsJSONURL(), let libraryURL else { return }
        let base = libraryURL.path.hasSuffix("/") ? libraryURL.path : libraryURL.path + "/"
        var relative: [String: [String]] = [:]
        for (absPath, tags) in tagsByVideoPath where !tags.isEmpty {
            let key = absPath.hasPrefix(base) ? String(absPath.dropFirst(base.count)) : absPath
            relative[key] = tags
        }
        if let data = try? JSONEncoder().encode(relative) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func loadTagsJSON() {
        guard let url = tagsJSONURL(), let libraryURL else { return }
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }

        let base = libraryURL.path.hasSuffix("/") ? libraryURL.path : libraryURL.path + "/"
        for (key, tags) in decoded where !tags.isEmpty {
            let absPath = key.hasPrefix("/") ? key : base + key
            tagsByVideoPath[absPath] = tags
        }
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    func loadWaveform(for video: VideoItem) {
        let path = video.url.path
        guard waveformSamplesByVideoPath[path] == nil, waveformTasks[path] == nil else { return }

        waveformTasks[path] = Task { [weak self] in
            let samples = await Self.makeWaveformSamples(for: video.url, sampleCount: 180) ?? []
            guard !Task.isCancelled else { return }

            self?.waveformSamplesByVideoPath[path] = samples
            self?.waveformTasks[path] = nil
        }
    }

    func loadFrameStrip(for video: VideoItem) {
        let path = video.url.path
        guard frameStripByVideoPath[path] == nil, frameStripTasks[path] == nil else { return }

        frameStripTasks[path] = Task { [weak self] in
            let frames = await Self.makeFrameStrip(for: video.url)
            guard !Task.isCancelled else { return }

            self?.frameStripByVideoPath[path] = frames
            self?.frameStripTasks[path] = nil
        }
    }

    nonisolated private static func makeFrameStrip(for url: URL, count: Int = 16) async -> [Data] {
        await Task.detached(priority: .utility) {
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
        }.value
    }

    func detectSceneCuts(for video: VideoItem) {
        let path = video.url.path
        guard sceneDetectionTasks[path] == nil, sceneDetectionProgress[path] == nil else { return }

        sceneDetectionProgress[path] = 0.0

        sceneDetectionTasks[path] = Task { [weak self] in
            let cuts = await Self.performSceneDetection(for: video.url) { progress in
                Task { @MainActor in
                    self?.sceneDetectionProgress[path] = progress
                }
            }

            guard !Task.isCancelled else {
                self?.sceneDetectionProgress[path] = nil
                self?.sceneDetectionTasks[path] = nil
                return
            }

            self?.sceneCutsByVideoPath[path] = cuts
            self?.storeSceneCutCache(for: video, cuts: cuts)
            self?.sceneDetectionProgress[path] = nil
            self?.sceneDetectionTasks[path] = nil
        }
    }

    func stopSceneIndexing() {
        sceneIndexingTask?.cancel()
        sceneIndexingTask = nil
        SceneDetectionProcessRegistry.shared.cancelRunningProcess()
        sceneIndexingStatus = SceneIndexingStatus()
        sceneDetectionProgress.removeAll()
    }

    private func sceneCutCacheURL() -> URL? {
        libraryURL?.appendingPathComponent(".lapianbao_scene_cuts.json")
    }

    private func loadSceneCutCache() {
        guard
            let url = sceneCutCacheURL(),
            let data = try? Data(contentsOf: url),
            let cache = try? JSONDecoder().decode(SceneCutCacheFile.self, from: data)
        else {
            sceneCutCache = [:]
            return
        }

        sceneCutCache = cache.entries
    }

    private func saveSceneCutCache() {
        guard let url = sceneCutCacheURL() else { return }

        let cache = SceneCutCacheFile(
            detectorVersion: Self.sceneDetectorVersion,
            entries: sceneCutCache
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(cache)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private func startBackgroundSceneIndexing() {
        sceneIndexingTask?.cancel()
        SceneDetectionProcessRegistry.shared.cancelRunningProcess()

        let videosToIndex = videos
        sceneIndexingStatus = SceneIndexingStatus(
            isRunning: !videosToIndex.isEmpty,
            completed: 0,
            total: videosToIndex.count,
            currentVideoName: nil
        )
        sceneIndexingTask = Task { [weak self] in
            var completed = 0

            for video in videosToIndex {
                guard !Task.isCancelled else {
                    self?.sceneIndexingStatus = SceneIndexingStatus()
                    return
                }

                self?.sceneIndexingStatus = SceneIndexingStatus(
                    isRunning: true,
                    completed: completed,
                    total: videosToIndex.count,
                    currentVideoName: video.name
                )

                await self?.loadOrDetectSceneCuts(for: video)

                guard !Task.isCancelled else {
                    self?.sceneIndexingStatus = SceneIndexingStatus()
                    return
                }

                completed += 1
                self?.sceneIndexingStatus = SceneIndexingStatus(
                    isRunning: true,
                    completed: completed,
                    total: videosToIndex.count,
                    currentVideoName: video.name
                )
            }

            self?.sceneIndexingStatus = SceneIndexingStatus(
                isRunning: false,
                completed: completed,
                total: videosToIndex.count,
                currentVideoName: nil
            )
            self?.sceneIndexingTask = nil
        }
    }

    private func loadOrDetectSceneCuts(for video: VideoItem) async {
        guard !Task.isCancelled else { return }

        let path = video.url.path
        guard sceneDetectionTasks[path] == nil else { return }

        if let cachedEntry = validCachedSceneCutEntry(for: video) {
            if sceneCutsByVideoPath[path] == nil {
                let cuts = await Self.sceneCuts(from: cachedEntry.cutTimes, for: video.url)
                guard !Task.isCancelled else { return }
                sceneCutsByVideoPath[path] = cuts
            }
            return
        }

        sceneDetectionProgress[path] = 0.0
        let cuts = await Self.performSceneDetection(for: video.url) { [weak self] progress in
            Task { @MainActor in
                guard self?.sceneIndexingTask?.isCancelled != true else { return }
                self?.sceneDetectionProgress[path] = progress
            }
        }

        guard !Task.isCancelled else {
            sceneDetectionProgress[path] = nil
            return
        }

        sceneCutsByVideoPath[path] = cuts
        storeSceneCutCache(for: video, cuts: cuts)
        sceneDetectionProgress[path] = nil
    }

    private func validCachedSceneCutEntry(for video: VideoItem) -> SceneCutCacheEntry? {
        let key = relativeVideoPath(for: video.url)
        guard
            let entry = sceneCutCache[key],
            entry.detectorVersion == Self.sceneDetectorVersion,
            entry.relativePath == key,
            entry.cutTimes.isEmpty == false,
            let signature = videoFileSignature(for: video.url)
        else { return nil }

        guard
            entry.fileSize == signature.fileSize,
            abs(entry.modificationTime - signature.modificationTime) < 1.0
        else { return nil }

        return entry
    }

    private func storeSceneCutCache(for video: VideoItem, cuts: [SceneCut]) {
        guard let signature = videoFileSignature(for: video.url), !cuts.isEmpty else { return }

        let relativePath = relativeVideoPath(for: video.url)
        let cutTimes = cuts
            .map { round($0.time * 1000) / 1000 }
            .sorted()

        sceneCutCache[relativePath] = SceneCutCacheEntry(
            detectorVersion: Self.sceneDetectorVersion,
            videoID: stableVideoID(for: relativePath),
            relativePath: relativePath,
            fileSize: signature.fileSize,
            modificationTime: signature.modificationTime,
            duration: durationByVideoPath[video.url.path],
            cutTimes: cutTimes,
            sceneIDs: cutTimes.indices.map { sceneID(for: relativePath, index: $0) },
            generatedAt: Date()
        )
        saveSceneCutCache()
    }

    private func videoFileSignature(for url: URL) -> (fileSize: Int64, modificationTime: Double)? {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let fileSize = values.fileSize,
            let modificationDate = values.contentModificationDate
        else { return nil }

        return (Int64(fileSize), modificationDate.timeIntervalSince1970)
    }

    private func relativeVideoPath(for url: URL) -> String {
        guard let libraryURL else { return url.lastPathComponent }

        let libraryPath = libraryURL.standardizedFileURL.path
        let videoPath = url.standardizedFileURL.path
        let prefix = libraryPath.hasSuffix("/") ? libraryPath : libraryPath + "/"
        guard videoPath.hasPrefix(prefix) else { return url.lastPathComponent }

        return String(videoPath.dropFirst(prefix.count))
    }

    private func stableVideoID(for relativePath: String) -> String {
        "video-\(Self.fnv1a64(relativePath))"
    }

    private func sceneID(for relativePath: String, index: Int) -> String {
        "\(stableVideoID(for: relativePath))-scene-\(String(format: "%04d", index + 1))"
    }

    nonisolated private static func performSceneDetection(
        for url: URL,
        progressCallback: @escaping (Double) -> Void
    ) async -> [SceneCut] {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)

            guard let duration = try? await asset.load(.duration) else { return [] }
            let totalSeconds = CMTimeGetSeconds(duration)
            guard totalSeconds.isFinite, totalSeconds > 0 else { return [] }

            progressCallback(0.03)
            if let transNetCutTimes = runTransNetSceneDetection(for: url), !transNetCutTimes.isEmpty {
                progressCallback(0.82)
                let cuts = await makeSceneCuts(for: asset, cutTimes: transNetCutTimes)
                progressCallback(1.0)
                return cuts
            }

            guard
                let tracks = try? await asset.loadTracks(withMediaType: .video),
                let videoTrack = tracks.first,
                let reader = try? AVAssetReader(asset: asset)
            else { return [] }

            let frameRate = Double((try? await videoTrack.load(.nominalFrameRate)) ?? 24)
            let minimumSceneLength = max(0.12, 4.0 / max(1.0, frameRate))
            let fingerprintWidth = 48
            let fingerprintHeight = 27

            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: fingerprintWidth,
                kCVPixelBufferHeightKey as String: fingerprintHeight
            ]

            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else { return [] }
            reader.add(output)
            guard reader.startReading() else { return [] }

            var previousFingerprint: SceneFingerprint?
            var changes: [SceneChange] = []

            while reader.status == .reading {
                guard let sampleBuffer = output.copyNextSampleBuffer() else { break }

                let timestamp = CMTimeGetSeconds(sampleBuffer.presentationTimeStamp)

                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

                let fingerprint = extractSceneFingerprint(
                    from: pixelBuffer,
                    width: fingerprintWidth,
                    height: fingerprintHeight
                )

                if let previousFingerprint {
                    let score = sceneChangeScore(from: previousFingerprint, to: fingerprint)
                    changes.append(SceneChange(time: timestamp, score: score))
                }

                previousFingerprint = fingerprint

                let progress = min(1.0, timestamp / totalSeconds)
                progressCallback(progress)
            }

            let cutTimes = selectSceneCutTimes(from: changes, minimumSceneLength: minimumSceneLength)
            guard !cutTimes.isEmpty else { return [] }

            return await makeSceneCuts(for: asset, cutTimes: cutTimes)
        }.value
    }

    nonisolated private struct TransNetDetectionResult: Decodable {
        let cutTimes: [Double]

        private enum CodingKeys: String, CodingKey {
            case cutTimes = "cut_times"
        }
    }

    nonisolated private static func runTransNetSceneDetection(for url: URL) -> [Double]? {
        let fileManager = FileManager.default
        guard
            fileManager.isExecutableFile(atPath: transNetPythonPath),
            fileManager.fileExists(atPath: transNetScriptPath)
        else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: transNetPythonPath)
        process.arguments = [
            transNetScriptPath,
            url.path,
            "--threshold",
            "0.35",
            "--device",
            "cpu"
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            SceneDetectionProcessRegistry.shared.set(process)
            process.waitUntilExit()
            SceneDetectionProcessRegistry.shared.set(nil)
        } catch {
            SceneDetectionProcessRegistry.shared.set(nil)
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let result = try? JSONDecoder().decode(TransNetDetectionResult.self, from: outputData),
            !result.cutTimes.isEmpty
        else { return nil }

        return result.cutTimes
            .map { max(0, $0) }
            .sorted()
    }

    nonisolated private static func makeSceneCuts(for asset: AVAsset, cutTimes: [Double]) async -> [SceneCut] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)
        // 从切点之后取帧，保证拿到新场景的首帧而非旧场景末帧
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var cuts: [SceneCut] = []
        for time in cutTimes {
            // 切点时刻 + 80ms，确保落在新场景内
            let targetTime = CMTime(seconds: max(0, time + 0.08), preferredTimescale: 600)
            let image = await thumbnailImage(from: generator, at: targetTime)
            guard let imageData = image else { continue }
            cuts.append(SceneCut(time: time, thumbnailData: imageData))
        }

        return cuts.sorted { $0.time < $1.time }
    }

    nonisolated private static func sceneCuts(from cutTimes: [Double], for url: URL) async -> [SceneCut] {
        let asset = AVURLAsset(url: url)
        return await makeSceneCuts(for: asset, cutTimes: cutTimes)
    }

    nonisolated private static func fnv1a64(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private struct SceneFingerprint {
        let luma: [Double]
        let histogram: [Double]
        let edges: [Double]
        let contrast: Double
    }

    private struct SceneChange {
        let time: Double
        let score: Double
    }

    nonisolated private static func extractSceneFingerprint(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> SceneFingerprint {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return SceneFingerprint(
                luma: [Double](repeating: 0, count: width * height),
                histogram: [Double](repeating: 0, count: 64),
                edges: [Double](repeating: 0, count: width * height),
                contrast: 0
            )
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)

        let pixelCount = width * height
        var luma = [Double](repeating: 0, count: width * height)
        var histogram = [Double](repeating: 0, count: 64)
        var lumaSum = 0.0

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let b = Double(pointer[offset]) / 255.0
                let g = Double(pointer[offset + 1]) / 255.0
                let r = Double(pointer[offset + 2]) / 255.0
                let value = 0.2126 * r + 0.7152 * g + 0.0722 * b
                luma[y * width + x] = value
                lumaSum += value

                let rBin = min(3, Int(r * 4))
                let gBin = min(3, Int(g * 4))
                let bBin = min(3, Int(b * 4))
                histogram[rBin * 16 + gBin * 4 + bBin] += 1
            }
        }

        let normalizer = max(1.0, Double(pixelCount))
        for index in histogram.indices {
            histogram[index] /= normalizer
        }

        let meanLuma = lumaSum / normalizer
        let contrast = luma.reduce(0.0) { $0 + abs($1 - meanLuma) } / normalizer

        let edges = extractEdges(from: luma, width: width, height: height)

        return SceneFingerprint(luma: luma, histogram: histogram, edges: edges, contrast: contrast)
    }

    nonisolated private static func sceneChangeScore(from previous: SceneFingerprint, to current: SceneFingerprint) -> Double {
        let frameSize = min(previous.luma.count, current.luma.count)
        guard frameSize > 0 else { return 0 }

        var lumaDifference = 0.0
        for index in 0..<frameSize {
            lumaDifference += abs(current.luma[index] - previous.luma[index])
        }
        lumaDifference /= Double(frameSize)

        var histogramDifference = 0.0
        for index in previous.histogram.indices {
            histogramDifference += abs(current.histogram[index] - previous.histogram[index])
        }
        histogramDifference *= 0.5

        let edgeSize = min(previous.edges.count, current.edges.count)
        var edgeDifference = 0.0
        if edgeSize > 0 {
            for index in 0..<edgeSize {
                edgeDifference += abs(current.edges[index] - previous.edges[index])
            }
            edgeDifference /= Double(edgeSize)
        }

        let contrastDifference = abs(current.contrast - previous.contrast)
        return lumaDifference * 0.38 + histogramDifference * 0.32 + edgeDifference * 0.22 + contrastDifference * 0.08
    }

    nonisolated private static func extractEdges(from luma: [Double], width: Int, height: Int) -> [Double] {
        guard width > 2, height > 2, luma.count == width * height else {
            return [Double](repeating: 0, count: width * height)
        }

        var edges = [Double](repeating: 0, count: width * height)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let left = luma[y * width + x - 1]
                let right = luma[y * width + x + 1]
                let top = luma[(y - 1) * width + x]
                let bottom = luma[(y + 1) * width + x]
                edges[y * width + x] = min(1.0, abs(right - left) + abs(bottom - top))
            }
        }
        return edges
    }

    nonisolated private static func selectSceneCutTimes(from changes: [SceneChange], minimumSceneLength: Double) -> [Double] {
        guard !changes.isEmpty else { return [0.0] }

        let scores = changes.map(\.score).sorted()
        let medianScore = median(ofSortedValues: scores)
        let deviations = scores.map { abs($0 - medianScore) }.sorted()
        let medianDeviation = median(ofSortedValues: deviations)
        let upperQuartile = percentile(ofSortedValues: scores, percentile: 0.75)
        let threshold = max(0.08, max(medianScore + max(0.018, medianDeviation * 4.0), upperQuartile * 1.35))
        let peakWindow = 2

        var selected: [SceneChange] = []
        for index in changes.indices {
            let change = changes[index]
            guard change.score >= threshold else { continue }

            let lowerBound = max(changes.startIndex, index - peakWindow)
            let upperBound = min(changes.index(before: changes.endIndex), index + peakWindow)
            var isLocalPeak = true
            for neighborIndex in lowerBound...upperBound where neighborIndex != index {
                if changes[neighborIndex].score > change.score {
                    isLocalPeak = false
                    break
                }
            }
            guard isLocalPeak else { continue }

            if let last = selected.last, change.time - last.time < minimumSceneLength {
                if change.score > last.score {
                    selected[selected.count - 1] = change
                }
            } else {
                selected.append(change)
            }
        }

        return ([0.0] + selected.map(\.time)).sorted()
    }

    nonisolated private static func median(ofSortedValues values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    nonisolated private static func percentile(ofSortedValues values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let clampedPercentile = min(1, max(0, percentile))
        let position = clampedPercentile * Double(values.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        guard lowerIndex != upperIndex else { return values[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        return values[lowerIndex] * (1 - fraction) + values[upperIndex] * fraction
    }

    nonisolated private static func thumbnailImage(from generator: AVAssetImageGenerator, at time: CMTime) async -> Data? {
        await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, _ in
                guard result == .succeeded, let image else {
                    continuation.resume(returning: nil)
                    return
                }
                let bitmap = NSBitmapImageRep(cgImage: image)
                let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78])
                continuation.resume(returning: data)
            }
        }
    }

    nonisolated private enum RemoteImportError: LocalizedError {
        case downloaderMissing
        case downloaderFailed(String)
        case invalidAPIEndpoint
        case invalidAPIResponse
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .downloaderMissing:
                return "没有找到 yt-dlp。请先安装 yt-dlp，或配置一个 Instagram 下载 API。"
            case let .downloaderFailed(message):
                return message.isEmpty ? "Instagram 下载失败" : message
            case .invalidAPIEndpoint:
                return "Instagram 下载 API 地址无效"
            case .invalidAPIResponse:
                return "Instagram 下载 API 返回格式不正确"
            case .downloadFailed:
                return "下载远程视频文件失败"
            }
        }
    }

    nonisolated private struct InstagramImportAPIRequest: Encodable {
        let url: String
    }

    nonisolated private struct InstagramImportAPIResponse: Decodable {
        let downloadURL: URL
        let filename: String?

        private enum CodingKeys: String, CodingKey {
            case downloadURL = "download_url"
            case filename
        }
    }

    nonisolated private static func downloadInstagramVideo(
        from sourceURL: URL,
        into libraryURL: URL,
        endpoint: String
    ) async throws -> URL {
        let destinationDirectory = libraryURL
            .appendingPathComponent("Imports", isDirectory: true)
            .appendingPathComponent("Instagram", isDirectory: true)

        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        if let downloaderURL = localYTDLPURL() {
            return try await runYTDLP(
                executableURL: downloaderURL,
                sourceURL: sourceURL,
                destinationDirectory: destinationDirectory
            )
        }

        guard !endpoint.isEmpty else {
            throw RemoteImportError.downloaderMissing
        }

        return try await importViaConfiguredAPI(
            sourceURL: sourceURL,
            endpoint: endpoint,
            destinationDirectory: destinationDirectory
        )
    }

    nonisolated private static func localYTDLPURL() -> URL? {
        [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map(URL.init(fileURLWithPath:))
    }

    nonisolated private static func runYTDLP(
        executableURL: URL,
        sourceURL: URL,
        destinationDirectory: URL
    ) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = [
                "--no-playlist",
                "--paths",
                destinationDirectory.path,
                "-o",
                "%(uploader|instagram)s-%(id)s.%(ext)s",
                "--print",
                "after_move:filepath",
                sourceURL.absoluteString
            ]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let errorOutput = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            guard process.terminationStatus == 0 else {
                throw RemoteImportError.downloaderFailed(errorOutput)
            }

            let outputPath = output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .last?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard
                let outputPath,
                !outputPath.isEmpty,
                FileManager.default.fileExists(atPath: outputPath)
            else {
                throw RemoteImportError.downloaderFailed(errorOutput)
            }

            return URL(fileURLWithPath: outputPath)
        }.value
    }

    nonisolated private static func importViaConfiguredAPI(
        sourceURL: URL,
        endpoint: String,
        destinationDirectory: URL
    ) async throws -> URL {
        guard let endpointURL = URL(string: endpoint) else {
            throw RemoteImportError.invalidAPIEndpoint
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            InstagramImportAPIRequest(url: sourceURL.absoluteString)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw RemoteImportError.invalidAPIResponse
        }

        let resolved = try JSONDecoder().decode(InstagramImportAPIResponse.self, from: data)
        let remoteFilename = resolved.filename?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = resolved.downloadURL.lastPathComponent.isEmpty
            ? "instagram-\(UUID().uuidString).mp4"
            : resolved.downloadURL.lastPathComponent
        let filename = sanitizedFilename(remoteFilename?.isEmpty == false ? remoteFilename! : fallbackName)
        let outputURL = destinationDirectory.appendingPathComponent(filename)

        let (videoData, videoResponse) = try await URLSession.shared.data(from: resolved.downloadURL)
        guard
            let httpResponse = videoResponse as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            !videoData.isEmpty
        else {
            throw RemoteImportError.downloadFailed
        }

        try videoData.write(to: outputURL, options: .atomic)
        return outputURL
    }

    nonisolated private static func sanitizedFilename(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let components = name.components(separatedBy: forbidden)
        let sanitized = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "instagram-\(UUID().uuidString).mp4" : sanitized
    }

    private func loadThumbnails(for videos: [VideoItem]) {
        thumbnailTasks.values.forEach { $0.cancel() }
        thumbnailTasks.removeAll()
        waveformTasks.values.forEach { $0.cancel() }
        waveformTasks.removeAll()
        frameStripTasks.values.forEach { $0.cancel() }
        frameStripTasks.removeAll()
        sceneDetectionTasks.values.forEach { $0.cancel() }
        sceneDetectionTasks.removeAll()
        sceneIndexingTask?.cancel()
        sceneIndexingTask = nil
        thumbnailDataByVideoPath.removeAll()
        durationByVideoPath.removeAll()
        playbackSupportByVideoPath.removeAll()
        waveformSamplesByVideoPath.removeAll()
        frameStripByVideoPath.removeAll()
        sceneCutsByVideoPath.removeAll()
        sceneDetectionProgress.removeAll()

        for video in videos {
            let path = video.url.path
            thumbnailTasks[path] = Task { [weak self] in
                async let metadata = Self.makeVideoMetadata(for: video.url)
                async let playbackSupport = Self.playbackSupport(for: video.url)
                let videoMetadata = await metadata
                guard !Task.isCancelled else { return }

                if let data = videoMetadata.thumbnailData {
                    self?.thumbnailDataByVideoPath[path] = data
                }

                if let duration = videoMetadata.duration {
                    self?.durationByVideoPath[path] = duration
                }

                self?.playbackSupportByVideoPath[path] = await playbackSupport
                self?.thumbnailTasks[path] = nil
            }
        }
    }

    nonisolated private static func playbackSupport(for url: URL) async -> VideoPlaybackSupport {
        let asset = AVURLAsset(url: url)

        do {
            async let isPlayable = asset.load(.isPlayable)
            async let videoTracks = asset.loadTracks(withMediaType: .video)

            guard try await !videoTracks.isEmpty else {
                return .unsupported("这个文件没有可播放的视频轨道")
            }

            guard try await isPlayable else {
                return .unsupported("macOS 系统播放器不支持这个容器或编码")
            }

            return .playable
        } catch {
            return .unsupported(error.localizedDescription)
        }
    }

    nonisolated private static func makeVideoMetadata(for url: URL) async -> (thumbnailData: Data?, duration: Double?) {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            async let duration = durationSeconds(for: asset)

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360)

            var bestCandidate: (data: Data, score: Double)?
            for seconds in [1.0, 2.0, 3.0, 5.0, 8.0, 13.0, 0.5, 0.1, 0.0] {
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                guard let candidate = await thumbnailCandidate(from: generator, at: time) else { continue }

                if candidate.score > (bestCandidate?.score ?? -1) {
                    bestCandidate = candidate
                }

                if candidate.score > 0.18 {
                    return (candidate.data, await duration)
                }
            }

            return (bestCandidate?.data, await duration)
        }.value
    }

    nonisolated private static func durationSeconds(for asset: AVURLAsset) async -> Double? {
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    nonisolated private static func thumbnailCandidate(
        from generator: AVAssetImageGenerator,
        at time: CMTime
    ) async -> (data: Data, score: Double)? {
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

                continuation.resume(returning: (data, imageContentScore(image)))
            }
        }
    }

    nonisolated private static func imageContentScore(_ image: CGImage) -> Double {
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

    nonisolated private static func makeWaveformSamples(for url: URL, sampleCount: Int) async -> [Double]? {
        await Task.detached(priority: .utility) {
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
            guard reader.startReading() else { return nil }

            var peaks: [Double] = []
            var currentPeak = 0.0
            var samplesInWindow = 0
            let windowSize = 2048

            while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
                let byteCount = CMBlockBufferGetDataLength(blockBuffer)
                guard byteCount > 0 else { continue }

                var data = Data(count: byteCount)
                let copyResult = data.withUnsafeMutableBytes { buffer -> OSStatus in
                    guard let destination = buffer.baseAddress else { return -1 }
                    return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: byteCount, destination: destination)
                }

                guard copyResult == noErr else { continue }

                data.withUnsafeBytes { rawBuffer in
                    let floatSamples = rawBuffer.bindMemory(to: Float32.self)
                    for sample in floatSamples {
                        currentPeak = max(currentPeak, min(1, Double(abs(sample))))
                        samplesInWindow += 1

                        if samplesInWindow >= windowSize {
                            peaks.append(currentPeak)
                            currentPeak = 0
                            samplesInWindow = 0
                        }
                    }
                }
            }

            if samplesInWindow > 0 {
                peaks.append(currentPeak)
            }

            guard !peaks.isEmpty else { return nil }
            return downsample(peaks, to: sampleCount)
        }.value
    }

    nonisolated private static func downsample(_ peaks: [Double], to sampleCount: Int) -> [Double] {
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
