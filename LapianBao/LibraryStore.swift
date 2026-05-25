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
    let id: String
    let time: Double
    let thumbnailImage: NSImage
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

enum VideoSortOption: String, CaseIterable, Identifiable, Codable {
    case name
    case importDate
    case duration
    case fileSize
    case resolution
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "名称"
        case .importDate: return "导入时间"
        case .duration: return "片长"
        case .fileSize: return "文件大小"
        case .resolution: return "分辨率"
        case .tags: return "标签"
        }
    }
}

enum VideoSortDirection: String, CaseIterable, Identifiable, Codable {
    case ascending
    case descending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending: return "升序"
        case .descending: return "降序"
        }
    }

    var systemImage: String {
        switch self {
        case .ascending: return "arrow.up"
        case .descending: return "arrow.down"
        }
    }
}

struct VideoMetadata: Codable, Equatable {
    var duration: Double?
    var frameRate: Double?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var fileSize: Int64?
    var createdAt: Date?
    var modifiedAt: Date?

    var resolutionText: String? {
        guard let pixelWidth, let pixelHeight, pixelWidth > 0, pixelHeight > 0 else { return nil }
        return "\(pixelWidth)x\(pixelHeight)"
    }

    var frameRateText: String? {
        guard let frameRate, frameRate.isFinite, frameRate > 0 else { return nil }
        return "\(Int(frameRate.rounded())) 帧"
    }
}

struct SampledFrame: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case sceneRepresentative
        case screenshot
    }

    var id: UUID = UUID()
    var videoPath: String
    var videoName: String
    var time: Double
    var sceneIndex: Int?
    var kind: Kind
    var isExported: Bool
    var note: String
    var tags: [String]
    var thumbnailData: Data
    var createdAt: Date = Date()
}

struct AnnotationItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var videoPath: String
    var videoName: String
    var time: Double
    var text: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct AudioClipItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var videoPath: String
    var videoName: String
    var inTime: Double
    var outTime: Double
    var filePath: String?
    var note: String = ""
    var createdAt: Date = Date()
}

struct TranscriptSegment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var videoPath: String
    var start: Double
    var end: Double
    var text: String
}

enum TranscriptJobStatus: Equatable {
    case idle
    case running(String)
    case failed(String)
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
        case transcoding          // VP9/AV1 → H.264 后处理阶段
        case succeeded(String)
        case failed(String)
    }

    let id = UUID()
    let sourceURL: URL
    let platform: String
    var status: Status
    var downloadProgress: Double? // nil = 不确定；0.0–1.0 = 已知进度
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
    @Published var thumbnailImageByVideoPath: [String: NSImage] = [:]
    @Published var durationByVideoPath: [String: Double] = [:]
    @Published var metadataByVideoPath: [String: VideoMetadata] = [:]
    @Published var playbackSupportByVideoPath: [String: VideoPlaybackSupport] = [:]
    @Published var waveformSamplesByVideoPath: [String: [Double]] = [:]
    @Published var frameStripByVideoPath: [String: [Data]] = [:]
    @Published var frameStripImagesByVideoPath: [String: [NSImage]] = [:]
    @Published var sceneCutsByVideoPath: [String: [SceneCut]] = [:]
    @Published var sceneCutProgressesByVideoPath: [String: [Double]] = [:]
    @Published var sceneDetectionProgress: [String: Double] = [:]
    @Published var sampledFrames: [SampledFrame] = []
    @Published var annotations: [AnnotationItem] = []
    @Published var audioClips: [AudioClipItem] = []
    @Published var transcriptSegmentsByVideoPath: [String: [TranscriptSegment]] = [:]
    @Published var transcriptStatusByVideoPath: [String: TranscriptJobStatus] = [:]
    @Published var sortOption: VideoSortOption = VideoSortOption(rawValue: UserDefaults.standard.string(forKey: "videoSortOption") ?? "") ?? .name {
        didSet { UserDefaults.standard.set(sortOption.rawValue, forKey: "videoSortOption") }
    }
    @Published var sortDirection: VideoSortDirection = VideoSortDirection(rawValue: UserDefaults.standard.string(forKey: "videoSortDirection") ?? "") ?? .ascending {
        didSet { UserDefaults.standard.set(sortDirection.rawValue, forKey: "videoSortDirection") }
    }
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

    private struct ProjectDataFile: Codable {
        var sampledFrames: [SampledFrame]
        var annotations: [AnnotationItem]
        var audioClips: [AudioClipItem]
        var transcripts: [String: [TranscriptSegment]]
    }

    private var thumbnailTasks: [String: Task<Void, Never>] = [:]
    private var waveformTasks: [String: Task<Void, Never>] = [:]
    private var frameStripTasks: [String: Task<Void, Never>] = [:]
    private var sceneDetectionTasks: [String: Task<Void, Never>] = [:]
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
        let scopedVideos: [VideoItem]
        if selectedTags.isEmpty {
            scopedVideos = videos
        } else {
            scopedVideos = videos.filter { video in
                let videoTags = tagsByVideoPath[video.url.path, default: []]
                return selectedTags.allSatisfy { videoTags.contains($0) }
            }
        }

        return scopedVideos.sorted { lhs, rhs in
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

    private func compareDates(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        compareNumbers(lhs?.timeIntervalSince1970, rhs?.timeIntervalSince1970)
    }

    private func compareNumbers<T: BinaryInteger>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        compareNumbers(lhs.map(Double.init), rhs.map(Double.init))
    }

    private func compareNumbers(_ lhs: Double?, _ rhs: Double?) -> ComparisonResult {
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
        sampledFrames.sorted {
            if $0.videoName == $1.videoName { return $0.time < $1.time }
            return $0.videoName.localizedStandardCompare($1.videoName) == .orderedAscending
        }
    }

    func sampledFrames(for video: VideoItem) -> [SampledFrame] {
        sampledFrames
            .filter { $0.videoPath == video.url.path }
            .sorted { $0.time < $1.time }
    }

    func annotations(for video: VideoItem) -> [AnnotationItem] {
        annotations
            .filter { $0.videoPath == video.url.path }
            .sorted { $0.time < $1.time }
    }

    func audioClips(for video: VideoItem) -> [AudioClipItem] {
        audioClips
            .filter { $0.videoPath == video.url.path }
            .sorted { $0.inTime < $1.inTime }
    }

    func selectedVideo(for path: String) -> VideoItem? {
        videos.first { $0.url.path == path }
    }

    func selectVideo(path: String) {
        guard let video = selectedVideo(for: path) else { return }
        selectedVideo = video
    }

    func setSort(option: VideoSortOption) {
        sortOption = option
    }

    func setSort(direction: VideoSortDirection) {
        sortDirection = direction
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
                sourceURL: URL(string: "https://example.com")!,
                platform: "未知平台",
                status: .failed("请输入有效链接")
            )
            return
        }

        guard let platform = Self.platformName(for: sourceURL) else {
            remoteImportJob = RemoteImportJob(
                sourceURL: sourceURL,
                platform: "未知平台",
                status: .failed("暂不支持该平台，目前支持 Instagram、YouTube、小红书、Bilibili 和抖音")
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

        // 进度回调：yt-dlp 每行输出一次，跳回主线程更新 UI
        let progressCallback: @Sendable (Double) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard case .importing = self?.remoteImportJob?.status else { return }
                self?.remoteImportJob?.downloadProgress = progress
            }
        }
        // 转码回调：下载结束、VP9→H.264 转码即将开始时触发
        let transcodingCallback: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                self?.remoteImportJob?.status = .transcoding
                self?.remoteImportJob?.downloadProgress = nil
            }
        }

        Task { [weak self] in
            do {
                let outputURL = try await Self.downloadVideo(
                    from: sourceURL,
                    into: libraryURL,
                    platform: platform,
                    endpoint: endpoint,
                    progressCallback: progressCallback,
                    transcodingCallback: transcodingCallback
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
        if host == "instagram.com" || host == "www.instagram.com"
            || host == "m.instagram.com" || host == "instagr.am" {
            return "Instagram"
        }
        if host.contains("xiaohongshu.com") || host.contains("xhslink.com") {
            return "小红书"
        }
        if host == "youtube.com" || host == "www.youtube.com"
            || host == "m.youtube.com" || host == "youtu.be"
            || host == "music.youtube.com" {
            return "YouTube"
        }
        if host.contains("bilibili.com") || host == "b23.tv" {
            return "Bilibili"
        }
        if host.contains("douyin.com") || host == "v.douyin.com"
            || host.contains("tiktok.com") || host == "vm.tiktok.com" {
            return "抖音"
        }
        return nil
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
        frameStripImagesByVideoPath = [:]
        sceneCutProgressesByVideoPath = [:]
        frameStripTasks.values.forEach { $0.cancel() }
        frameStripTasks.removeAll()
        loadTagsJSON()
        loadProjectData()
        loadThumbnails(for: videos)
        loadSceneCutCache()
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

    private func projectDataURL() -> URL? {
        libraryURL?.appendingPathComponent(".lapianbao_project.json")
    }

    private func saveProjectData() {
        guard let url = projectDataURL() else { return }
        let dataFile = ProjectDataFile(
            sampledFrames: sampledFrames,
            annotations: annotations,
            audioClips: audioClips,
            transcripts: transcriptSegmentsByVideoPath
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(dataFile) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadProjectData() {
        guard
            let url = projectDataURL(),
            let data = try? Data(contentsOf: url)
        else {
            sampledFrames = []
            annotations = []
            audioClips = []
            transcriptSegmentsByVideoPath = [:]
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(ProjectDataFile.self, from: data) else { return }
        sampledFrames = decoded.sampledFrames
        annotations = decoded.annotations
        audioClips = decoded.audioClips
        transcriptSegmentsByVideoPath = decoded.transcripts
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
            self?.frameStripImagesByVideoPath[path] = frames.compactMap { NSImage(data: $0) }
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

            self?.setSceneCuts(cuts, for: path)
            self?.storeSceneCutCache(for: video, cuts: cuts)
            self?.sceneDetectionProgress[path] = nil
            self?.sceneDetectionTasks[path] = nil
        }
    }

    func loadCachedSceneCuts(for video: VideoItem) {
        let path = video.url.path
        guard
            sceneCutsByVideoPath[path] == nil,
            sceneDetectionTasks[path] == nil,
            let cachedEntry = validCachedSceneCutEntry(for: video)
        else { return }

        sceneDetectionTasks[path] = Task { [weak self] in
            let cuts = await Self.sceneCuts(from: cachedEntry.cutTimes, for: video.url)
            guard !Task.isCancelled else {
                self?.sceneDetectionTasks[path] = nil
                return
            }

            self?.setSceneCuts(cuts, for: path)
            self?.sceneDetectionTasks[path] = nil
        }
    }

    private func setSceneCuts(_ cuts: [SceneCut], for path: String) {
        sceneCutsByVideoPath[path] = cuts
        sceneCutProgressesByVideoPath[path] = Self.normalizedSceneCutProgresses(
            from: cuts.map(\.time),
            duration: durationByVideoPath[path] ?? 0
        )
    }

    func addAnnotation(video: VideoItem, time: Double, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        annotations.append(AnnotationItem(
            videoPath: video.url.path,
            videoName: video.name,
            time: max(0, time),
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

    func markSceneFrameExported(video: VideoItem, cut: SceneCut, sceneIndex: Int?) {
        if let index = sampledFrames.firstIndex(where: {
            $0.videoPath == video.url.path &&
            abs($0.time - cut.time) < 0.02 &&
            $0.kind == .sceneRepresentative
        }) {
            sampledFrames[index].isExported = true
        } else {
            sampledFrames.append(SampledFrame(
                videoPath: video.url.path,
                videoName: video.name,
                time: cut.time,
                sceneIndex: sceneIndex,
                kind: .sceneRepresentative,
                isExported: true,
                note: "",
                tags: [],
                thumbnailData: Self.jpegData(from: cut.thumbnailImage) ?? Data()
            ))
        }
        sampledFrames.sort { $0.time < $1.time }
        if let data = Self.jpegData(from: cut.thumbnailImage) {
            saveImageExport(data: data, video: video, time: cut.time, preferredExtension: "jpg")
        }
        saveProjectData()
    }

    func captureCurrentFrame(video: VideoItem, time: Double) {
        Task { [weak self] in
            guard let data = await Self.renderFrameData(for: video.url, at: time) else { return }
            self?.sampledFrames.append(SampledFrame(
                videoPath: video.url.path,
                videoName: video.name,
                time: max(0, time),
                sceneIndex: self?.sceneIndex(for: video, at: time),
                kind: .screenshot,
                isExported: true,
                note: "",
                tags: [],
                thumbnailData: data
            ))
            self?.sampledFrames.sort {
                if $0.videoPath == $1.videoPath { return $0.time < $1.time }
                return $0.videoName < $1.videoName
            }
            self?.saveImageExport(data: data, video: video, time: time, preferredExtension: "jpg")
            self?.saveProjectData()
        }
    }

    func exportAudioClip(video: VideoItem, inTime: Double, outTime: Double) {
        let start = max(0, min(inTime, outTime))
        let end = max(inTime, outTime)
        guard end - start > 0.05 else { return }
        let videoName = video.name

        Task { [weak self] in
            let outputURL = await Self.exportAudioClipFile(video: video, videoName: videoName, start: start, end: end, libraryURL: self?.libraryURL)
            self?.audioClips.append(AudioClipItem(
                videoPath: video.url.path,
                videoName: videoName,
                inTime: start,
                outTime: end,
                filePath: outputURL?.path
            ))
            self?.saveProjectData()
        }
    }

    func transcribe(video: VideoItem) {
        let path = video.url.path
        if case .running = transcriptStatusByVideoPath[path] { return }
        transcriptStatusByVideoPath[path] = .running("提取音频并本地转写")
        let videoName = video.name

        Task { [weak self] in
            do {
                let segments = try await Self.runWhisperTranscription(video: video, videoName: videoName, libraryURL: self?.libraryURL)
                self?.transcriptSegmentsByVideoPath[path] = segments
                self?.transcriptStatusByVideoPath[path] = .idle
                self?.saveProjectData()
            } catch {
                self?.transcriptStatusByVideoPath[path] = .failed(error.localizedDescription)
            }
        }
    }

    func exportTranscriptMarkdown(video: VideoItem) {
        guard let libraryURL else { return }
        let segments = transcriptSegmentsByVideoPath[video.url.path, default: []]
        guard !segments.isEmpty else { return }
        let folder = libraryURL
            .appendingPathComponent("LapianBaoExports", isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(Self.safeFileStem(video.name))-transcript.md")
        let body = segments.map { "[\(Self.clockText($0.start))] \($0.text)" }.joined(separator: "\n")
        let md = "# \(video.name)\n\n## 原脚本\n\n\(body)\n"
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }

    private func sceneIndex(for video: VideoItem, at time: Double) -> Int? {
        guard let cuts = sceneCutsByVideoPath[video.url.path], !cuts.isEmpty else { return nil }
        return cuts.lastIndex { $0.time <= time }
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
            var lastReportedProgress = 0.03

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
                if progress - lastReportedProgress >= 0.01 || progress >= 0.995 {
                    progressCallback(progress)
                    lastReportedProgress = progress
                }
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
        process.qualityOfService = .utility
        process.arguments = [
            transNetScriptPath,
            url.path,
            "--threshold",
            "0.35",
            "--device",
            "cpu"
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["OMP_NUM_THREADS"] = "2"
        environment["OPENBLAS_NUM_THREADS"] = "2"
        environment["MKL_NUM_THREADS"] = "2"
        environment["VECLIB_MAXIMUM_THREADS"] = "2"
        environment["NUMEXPR_NUM_THREADS"] = "2"
        process.environment = environment

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
        generator.maximumSize = CGSize(width: 200, height: 113)
        // 从切点之后取帧，保证拿到新场景的首帧而非旧场景末帧
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let orderedCutTimes = stableSceneCutTimes(from: cutTimes)
        var cuts: [SceneCut] = []
        cuts.reserveCapacity(orderedCutTimes.count)

        for (index, time) in orderedCutTimes.enumerated() {
            // 切点时刻 + 80ms，确保落在新场景内
            let targetTime = CMTime(seconds: max(0, time + 0.08), preferredTimescale: 600)
            guard let image = await sceneThumbnailImage(from: generator, at: targetTime) else {
                continue
            }

            cuts.append(SceneCut(
                id: sceneCutID(index: index, time: time),
                time: time,
                thumbnailImage: image
            ))
        }

        return cuts
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

    nonisolated private static func normalizedSceneCutProgresses(from cutTimes: [Double], duration: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        return cutTimes.map { min(1, max(0, $0 / duration)) }
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

    nonisolated private static func stableSceneCutTimes(from cutTimes: [Double]) -> [Double] {
        var result: [Double] = []
        var previous: Double?

        for time in cutTimes.map({ max(0, ($0 * 1000).rounded() / 1000) }).sorted() {
            guard previous.map({ abs(time - $0) > 0.001 }) ?? true else { continue }
            result.append(time)
            previous = time
        }

        return result
    }

    nonisolated private static func sceneCutID(index: Int, time: Double) -> String {
        let milliseconds = Int((time * 1000).rounded())
        return "scene-\(String(format: "%04d", index + 1))-\(milliseconds)"
    }

    nonisolated private static func sceneThumbnailImage(from generator: AVAssetImageGenerator, at time: CMTime) async -> NSImage? {
        await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, _ in
                guard result == .succeeded, let image else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                ))
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
                return "下载失败：请检查网络连接，或在高级设置中配置自定义 API。"
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

    // MARK: - 统一下载入口

    nonisolated private static func downloadVideo(
        from sourceURL: URL,
        into libraryURL: URL,
        platform: String,
        endpoint: String,
        progressCallback: (@Sendable (Double) -> Void)? = nil,
        transcodingCallback: (@Sendable () -> Void)? = nil
    ) async throws -> URL {
        let safeFolder = platform.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let destinationDirectory = libraryURL
            .appendingPathComponent("Imports", isDirectory: true)
            .appendingPathComponent(safeFolder.isEmpty ? "Other" : safeFolder, isDirectory: true)

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        var rawURL: URL?

        // 1. yt-dlp（YouTube / Bilibili / 抖音完美，Instagram / 小红书公开内容也能用）
        if rawURL == nil, let ytdlp = localYTDLPURL(),
           let result = try? await runYTDLPOnce(
               executableURL: ytdlp,
               sourceURL: sourceURL,
               destinationDirectory: destinationDirectory,
               progressCallback: progressCallback
           ) {
            rawURL = result
        }

        // 2. 小红书：原生页面解析（yt-dlp 对需要登录的内容失效时接手）
        if rawURL == nil, platform == "小红书",
           let result = try? await downloadXiaoHongShuNative(
               from: sourceURL,
               destinationDirectory: destinationDirectory
           ) {
            rawURL = result
        }

        // 3. 用户自定义 API
        if rawURL == nil, !endpoint.isEmpty,
           let result = try? await importViaConfiguredAPI(
               sourceURL: sourceURL,
               endpoint: endpoint,
               destinationDirectory: destinationDirectory
           ) {
            rawURL = result
        }

        // 4. cobalt.tools 兜底（对 Instagram / YouTube 有效，需要服务可用）
        if rawURL == nil,
           let result = try? await importViaCobalt(sourceURL: sourceURL, destinationDirectory: destinationDirectory) {
            rawURL = result
        }

        guard let downloadedURL = rawURL else {
            throw RemoteImportError.downloaderFailed("所有下载方式均失败，请确认链接是否可公开访问")
        }

        // 后处理：VP9 / AV1 在 MP4 容器中不被 macOS AVFoundation 支持，转码为 H.264
        return await transcodeToH264IfNeeded(downloadedURL, willTranscodeCallback: transcodingCallback) ?? downloadedURL
    }

    // MARK: - VP9/AV1 → H.264 转码（解决 macOS 播放兼容性）

    nonisolated private static func transcodeToH264IfNeeded(
        _ url: URL,
        willTranscodeCallback: (@Sendable () -> Void)? = nil
    ) async -> URL? {
        await Task.detached(priority: .utility) {
            let ffprobePath = "/opt/homebrew/bin/ffprobe"
            guard FileManager.default.isExecutableFile(atPath: ffprobePath) else { return nil }

            // 用 ffprobe 探测视频流编码
            let probeProcess = Process()
            probeProcess.executableURL = URL(fileURLWithPath: ffprobePath)
            probeProcess.arguments = [
                "-v", "quiet",
                "-select_streams", "v:0",
                "-show_entries", "stream=codec_name",
                "-of", "default=noprint_wrappers=1:nokey=1",
                url.path
            ]
            let probePipe = Pipe()
            probeProcess.standardOutput = probePipe
            probeProcess.standardError = Pipe()

            guard (try? probeProcess.run()) != nil else { return nil }
            probeProcess.waitUntilExit()

            let codec = (String(
                data: probePipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            // macOS AVFoundation 在 MP4 容器中不支持 VP9 / AV1 / VP8
            let unsupported = ["vp9", "vp09", "av1", "av01", "vp8"]
            guard unsupported.contains(codec) else { return nil }

            // 通知 UI 进入转码阶段
            willTranscodeCallback?()

            // 找 ffmpeg
            let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
            guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else { return nil }

            // 先输出到临时文件，避免和原文件重名冲突
            let stem = url.deletingPathExtension().lastPathComponent
            let tmpURL = url.deletingLastPathComponent()
                .appendingPathComponent("\(stem)-transcoding-tmp.mp4")

            let ffmpegProcess = Process()
            ffmpegProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            ffmpegProcess.environment = env
            ffmpegProcess.arguments = [
                "-i", url.path,
                "-c:v", "libx264",
                "-crf", "23",
                "-preset", "fast",
                "-c:a", "aac",
                "-b:a", "192k",
                "-movflags", "+faststart",
                "-y",
                tmpURL.path
            ]
            ffmpegProcess.standardOutput = Pipe()
            ffmpegProcess.standardError = Pipe()

            guard (try? ffmpegProcess.run()) != nil else { return nil }
            ffmpegProcess.waitUntilExit()

            guard
                ffmpegProcess.terminationStatus == 0,
                FileManager.default.fileExists(atPath: tmpURL.path)
            else {
                try? FileManager.default.removeItem(at: tmpURL)
                return nil
            }

            // 删除原 VP9 文件，把临时文件重命名回原名
            try? FileManager.default.removeItem(at: url)
            let finalURL = url.deletingLastPathComponent()
                .appendingPathComponent("\(stem).mp4")
            if (try? FileManager.default.moveItem(at: tmpURL, to: finalURL)) != nil {
                return finalURL
            }
            return tmpURL
        }.value
    }

    // MARK: - 小红书原生解析器

    nonisolated private static func downloadXiaoHongShuNative(
        from sourceURL: URL,
        destinationDirectory: URL
    ) async throws -> URL {
        // 解析 note ID（去掉 query string）
        let noteId = sourceURL.lastPathComponent.components(separatedBy: "?").first
            ?? sourceURL.lastPathComponent

        // 抓取页面
        var req = URLRequest(url: sourceURL)
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("https://www.xiaohongshu.com", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 30

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else {
            throw RemoteImportError.downloaderFailed("小红书页面读取失败")
        }

        // 提取 window.__INITIAL_STATE__=...;
        guard let stateStart = html.range(of: "window.__INITIAL_STATE__=") else {
            throw RemoteImportError.downloaderFailed("未找到视频数据，该笔记可能需要登录才能查看")
        }
        let afterEquals = html[stateStart.upperBound...]
        // 找到第一个换行或 </script> 之前
        let jsonRaw: String
        if let newline = afterEquals.firstIndex(of: "\n") {
            jsonRaw = String(afterEquals[..<newline])
        } else {
            jsonRaw = String(afterEquals.prefix(512_000))
        }
        var jsonStr = jsonRaw
        if jsonStr.hasSuffix(";") { jsonStr.removeLast() }

        guard
            let jsonData = jsonStr.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let noteSection = root["note"] as? [String: Any],
            let detailMap = noteSection["noteDetailMap"] as? [String: Any],
            let entry = detailMap[noteId] as? [String: Any],
            let noteObj = entry["note"] as? [String: Any],
            let videoObj = noteObj["video"] as? [String: Any]
        else {
            throw RemoteImportError.downloaderFailed("小红书：未找到视频信息，该笔记可能不是视频或需要登录")
        }

        // 优先：原画直链
        var videoURL: URL?
        if let consumer = videoObj["consumer"] as? [String: Any],
           let key = consumer["originVideoKey"] as? String, !key.isEmpty {
            videoURL = URL(string: "https://sns-video-bd.xhscdn.com/\(key)")
        }

        // 回退：stream 格式（h264 > h265 > av1）
        if videoURL == nil,
           let media = videoObj["media"] as? [String: Any],
           let stream = media["stream"] as? [String: Any] {
            for codec in ["h264", "h265", "av1"] {
                if let list = stream[codec] as? [[String: Any]],
                   let first = list.first,
                   let masterUrl = first["masterUrl"] as? String,
                   let u = URL(string: masterUrl) {
                    videoURL = u
                    break
                }
            }
        }

        guard let downloadURL = videoURL else {
            throw RemoteImportError.downloaderFailed("小红书：找不到视频下载地址，该视频可能仅限好友可见")
        }

        // 下载视频文件
        var dlReq = URLRequest(url: downloadURL)
        dlReq.setValue("https://www.xiaohongshu.com", forHTTPHeaderField: "Referer")
        dlReq.timeoutInterval = 180

        let (videoData, videoResp) = try await URLSession.shared.data(for: dlReq)
        guard
            let http = videoResp as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            !videoData.isEmpty
        else {
            throw RemoteImportError.downloadFailed
        }

        let outputURL = destinationDirectory.appendingPathComponent("xiaohongshu-\(noteId).mp4")
        try videoData.write(to: outputURL, options: .atomic)
        return outputURL
    }

    nonisolated private static func localYTDLPURL() -> URL? {
        [
            // miniconda 版优先：Python 3.13，pyexpat 正常，Instagram/YouTube 均可用
            "/opt/miniconda3/bin/yt-dlp",
            "/opt/anaconda3/bin/yt-dlp",
            // Homebrew 版（Python 3.14 在部分 macOS 上 pyexpat 有兼容问题，作为备选）
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map(URL.init(fileURLWithPath:))
    }

    nonisolated private static func runYTDLPOnce(
        executableURL: URL,
        sourceURL: URL,
        destinationDirectory: URL,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executableURL

            // 确保 yt-dlp 能找到 ffmpeg（App 启动时没有完整 PATH）
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            process.environment = env

            process.arguments = [
                "--no-playlist",
                "-f", "bestvideo+bestaudio/best",
                "--merge-output-format", "mp4",
                "--ffmpeg-location", "/opt/homebrew/bin",
                "--progress",   // 非 TTY 环境也强制输出进度
                "--newline",    // 每次进度更新输出新行，便于实时解析
                "--no-colors",  // 去掉 ANSI 转义码，方便文本解析
                "--paths", destinationDirectory.path,
                "-o", "%(uploader|instagram)s-%(id)s.%(ext)s",
                "--print", "after_move:filepath",
                sourceURL.absoluteString
            ]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // 实时读取 stderr 解析进度（yt-dlp 进度输出到 stderr）
            // 用 @unchecked Sendable 类封装可变状态，避免 Swift 6 并发警告
            final class StderrCollector: @unchecked Sendable {
                private let lock = NSLock()
                private var buffer = Data()
                func append(_ data: Data) {
                    lock.lock(); defer { lock.unlock() }
                    buffer.append(data)
                }
                var data: Data {
                    lock.lock(); defer { lock.unlock() }
                    return buffer
                }
            }
            let collector = StderrCollector()

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                collector.append(chunk)
                if let text = String(data: chunk, encoding: .utf8) {
                    for line in text.components(separatedBy: .newlines) {
                        if let p = parseYTDLPProgressLine(line) {
                            progressCallback?(p)
                        }
                    }
                }
            }

            try process.run()
            process.waitUntilExit()

            // nil 掉 handler（内部会等当前 handler 执行完毕），再排空剩余数据
            errorPipe.fileHandleForReading.readabilityHandler = nil
            collector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let errorOutput = String(data: collector.data, encoding: .utf8) ?? ""

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

    /// 解析 yt-dlp 进度行，如 "[download]  45.6% of 1.23MiB at 2.34MiB/s ETA 00:12"
    nonisolated private static func parseYTDLPProgressLine(_ line: String) -> Double? {
        guard line.contains("[download]"), line.contains("%") else { return nil }
        // 忽略 "Destination:" 等非进度行
        guard !line.contains("Destination:"),
              !line.contains("already been downloaded"),
              !line.contains("Merging") else { return nil }
        let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for token in tokens where token.hasSuffix("%") {
            if let value = Double(token.dropLast()), value >= 0 {
                return min(1.0, value / 100.0)
            }
        }
        return nil
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

    // MARK: - cobalt.tools 内置备用下载

    nonisolated private struct CobaltRequest: Encodable {
        let url: String
    }

    nonisolated private struct CobaltResponse: Decodable {
        let status: String
        let url: URL?
        let filename: String?
        let picker: [CobaltPickerItem]?

        struct CobaltPickerItem: Decodable {
            let type: String?
            let url: URL
        }
    }

    nonisolated private static func importViaCobalt(
        sourceURL: URL,
        destinationDirectory: URL
    ) async throws -> URL {
        guard let cobaltEndpoint = URL(string: "https://api.cobalt.tools/") else {
            throw RemoteImportError.downloaderMissing
        }

        var request = URLRequest(url: cobaltEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(
            CobaltRequest(url: sourceURL.absoluteString)
        )

        let (data, httpResp) = try await URLSession.shared.data(for: request)
        guard
            let resp = httpResp as? HTTPURLResponse,
            (200..<300).contains(resp.statusCode)
        else {
            throw RemoteImportError.downloaderFailed("cobalt.tools 无法处理该链接，请安装 yt-dlp 后重试")
        }

        let cobalt = try JSONDecoder().decode(CobaltResponse.self, from: data)

        let downloadURL: URL
        switch cobalt.status {
        case "redirect", "tunnel", "stream":
            guard let u = cobalt.url else { throw RemoteImportError.invalidAPIResponse }
            downloadURL = u
        case "picker":
            // 多媒体帖子：优先取第一个视频，否则取第一项
            guard let item = cobalt.picker?.first(where: { $0.type == "video" })
                          ?? cobalt.picker?.first
            else { throw RemoteImportError.invalidAPIResponse }
            downloadURL = item.url
        default:
            throw RemoteImportError.downloaderFailed("cobalt.tools 无法解析该链接，请安装 yt-dlp 后重试")
        }

        let fallbackName = downloadURL.lastPathComponent.isEmpty
            ? "instagram-\(UUID().uuidString).mp4"
            : downloadURL.lastPathComponent
        let filename = sanitizedFilename(cobalt.filename ?? fallbackName)
        let outputURL = destinationDirectory.appendingPathComponent(filename)

        let (videoData, videoResp) = try await URLSession.shared.data(from: downloadURL)
        guard
            let vResp = videoResp as? HTTPURLResponse,
            (200..<300).contains(vResp.statusCode),
            !videoData.isEmpty
        else { throw RemoteImportError.downloadFailed }

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
        thumbnailDataByVideoPath.removeAll()
        thumbnailImageByVideoPath.removeAll()
        durationByVideoPath.removeAll()
        metadataByVideoPath.removeAll()
        playbackSupportByVideoPath.removeAll()
        waveformSamplesByVideoPath.removeAll()
        frameStripByVideoPath.removeAll()
        frameStripImagesByVideoPath.removeAll()
        sceneCutsByVideoPath.removeAll()
        sceneCutProgressesByVideoPath.removeAll()
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
                    self?.thumbnailImageByVideoPath[path] = NSImage(data: data)
                }

                if let duration = videoMetadata.duration {
                    self?.durationByVideoPath[path] = duration
                    if let cuts = self?.sceneCutsByVideoPath[path] {
                        self?.sceneCutProgressesByVideoPath[path] = Self.normalizedSceneCutProgresses(
                            from: cuts.map(\.time),
                            duration: duration
                        )
                    }
                }

                self?.metadataByVideoPath[path] = videoMetadata.metadata
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

    nonisolated private static func makeVideoMetadata(for url: URL) async -> (thumbnailData: Data?, duration: Double?, metadata: VideoMetadata) {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            async let duration = durationSeconds(for: asset)
            let specs = await videoSpecs(for: asset)
            let resourceValues = try? url.resourceValues(forKeys: [
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey
            ])

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360)

            func metadata(with durationValue: Double?) -> VideoMetadata {
                return VideoMetadata(
                    duration: durationValue,
                    frameRate: specs.frameRate,
                    pixelWidth: specs.pixelWidth,
                    pixelHeight: specs.pixelHeight,
                    fileSize: resourceValues?.fileSize.map(Int64.init),
                    createdAt: resourceValues?.creationDate,
                    modifiedAt: resourceValues?.contentModificationDate
                )
            }

            var bestCandidate: (data: Data, score: Double)?
            for seconds in [1.0, 2.0, 3.0, 5.0, 8.0, 13.0, 0.5, 0.1, 0.0] {
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                guard let candidate = await thumbnailCandidate(from: generator, at: time) else { continue }

                if candidate.score > (bestCandidate?.score ?? -1) {
                    bestCandidate = candidate
                }

                if candidate.score > 0.18 {
                    let durationValue = await duration
                    return (candidate.data, durationValue, metadata(with: durationValue))
                }
            }

            let durationValue = await duration
            return (bestCandidate?.data, durationValue, metadata(with: durationValue))
        }.value
    }

    nonisolated private static func durationSeconds(for asset: AVURLAsset) async -> Double? {
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    nonisolated private static func videoSpecs(for asset: AVURLAsset) async -> (frameRate: Double?, pixelWidth: Int?, pixelHeight: Int?) {
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

    nonisolated private static func renderFrameData(for url: URL, at seconds: Double) async -> Data? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 720)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)
            guard let image = await sceneThumbnailImage(from: generator, at: CMTime(seconds: max(0, seconds), preferredTimescale: 600)) else { return nil }
            return jpegData(from: image)
        }.value
    }

    nonisolated private static func jpegData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }

    private func saveImageExport(data: Data, video: VideoItem, time: Double, preferredExtension: String) {
        guard let libraryURL else { return }
        let folder = libraryURL
            .appendingPathComponent("LapianBaoExports", isDirectory: true)
            .appendingPathComponent(Self.safeFileStem(video.name), isDirectory: true)
            .appendingPathComponent("selected-frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let existingCount = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.count ?? 0
        let filename = String(format: "%03d_%@.%@", existingCount + 1, Self.fileTimecode(time), preferredExtension)
        try? data.write(to: folder.appendingPathComponent(filename), options: .atomic)
        writeFrameIndex(in: folder, video: video)
    }

    private func writeFrameIndex(in folder: URL, video: VideoItem) {
        let frames = sampledFrames(for: video)
        let lines = frames.enumerated().map { index, frame in
            "\(index + 1). \(Self.clockText(frame.time)) · \(frame.kind == .screenshot ? "截图" : "场景代表帧")"
        }
        let md = "# \(video.name)\n\n" + lines.joined(separator: "\n") + "\n"
        try? md.write(to: folder.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
    }

    nonisolated private static func exportAudioClipFile(video: VideoItem, videoName: String, start: Double, end: Double, libraryURL: URL?) async -> URL? {
        await Task.detached(priority: .utility) {
            guard let libraryURL else { return nil }
            let folder = libraryURL
                .appendingPathComponent("LapianBaoExports", isDirectory: true)
                .appendingPathComponent("Audio", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let outputURL = folder.appendingPathComponent("\(safeFileStem(videoName))_\(fileTimecode(start))-\(fileTimecode(end)).m4a")
            try? FileManager.default.removeItem(at: outputURL)

            let asset = AVURLAsset(url: video.url)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return nil }
            session.outputURL = outputURL
            session.outputFileType = .m4a
            session.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )

            await session.export()
            return session.status == .completed ? outputURL : nil
        }.value
    }

    nonisolated private static func runWhisperTranscription(video: VideoItem, videoName: String, libraryURL: URL?) async throws -> [TranscriptSegment] {
        try await Task.detached(priority: .utility) {
            let scriptPath = "/Users/zhengshihong/Downloads/Newtybei知识库/进行项目/拉片宝/LapianBao/Tools/transcribe_with_whisper.sh"
            guard FileManager.default.isExecutableFile(atPath: scriptPath) else {
                throw NSError(domain: "LapianBao", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到本地 Whisper 转写脚本"])
            }

            let baseFolder = (libraryURL ?? video.url.deletingLastPathComponent())
                .appendingPathComponent("LapianBaoExports", isDirectory: true)
                .appendingPathComponent("Transcripts", isDirectory: true)
            try FileManager.default.createDirectory(at: baseFolder, withIntermediateDirectories: true)
            let outputBase = baseFolder.appendingPathComponent(safeFileStem(videoName))

            let process = Process()
            process.executableURL = URL(fileURLWithPath: scriptPath)
            process.arguments = [video.url.path, outputBase.path, "auto"]
            process.standardOutput = Pipe()
            let errorPipe = Pipe()
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "本地转写失败"
                throw NSError(domain: "LapianBao", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
            }

            let jsonURL = outputBase.appendingPathExtension("json")
            let data = try Data(contentsOf: jsonURL)
            return try parseWhisperSegments(data: data, videoPath: video.url.path)
        }.value
    }

    nonisolated private struct WhisperOutput: Decodable {
        let transcription: [WhisperSegment]?
        let segments: [WhisperSegment]?
    }

    nonisolated private struct WhisperSegment: Decodable {
        let timestamps: WhisperTimestamps?
        let offsets: WhisperOffsets?
        let text: String?
        let start: Double?
        let end: Double?
    }

    nonisolated private struct WhisperTimestamps: Decodable {
        let from: String?
        let to: String?
    }

    nonisolated private struct WhisperOffsets: Decodable {
        let from: Int?
        let to: Int?
    }

    nonisolated private static func parseWhisperSegments(data: Data, videoPath: String) throws -> [TranscriptSegment] {
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

    nonisolated private static func parseTimestamp(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return nil }
        let seconds = Double(parts.last ?? "") ?? 0
        let minutes = Double(parts.dropLast().last ?? "") ?? 0
        let hours = parts.count > 2 ? (Double(parts.first ?? "") ?? 0) : 0
        return hours * 3600 + minutes * 60 + seconds
    }

    nonisolated private static func safeFileStem(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = name.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "video" : sanitized
    }

    nonisolated private static func fileTimecode(_ seconds: Double) -> String {
        clockText(seconds).replacingOccurrences(of: ":", with: "-")
    }

    nonisolated private static func clockText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
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
