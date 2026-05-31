//
//  LibraryStore.swift
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

@MainActor
final class LibraryStore: ObservableObject {
    @Published var libraryURL: URL?
    @Published var videos: [VideoItem] = [] {
        didSet {
            clearVideoSourceCaches()
            refreshFilteredVideos()
        }
    }
    @Published var selectedVideo: VideoItem?
    @Published var selectedVideoSelectionID = UUID()
    var shouldAutoplaySelectedVideo = false
    @Published var selectedTags: Set<String> = [] {
        didSet { refreshFilteredVideos() }
    }
    @Published var tagInput = ""
    @Published var tagsByVideoPath: [String: [String]] = [:] {
        didSet {
            rebuildAllTagsCache()
            clearVideoSourceCaches()
            refreshFilteredVideos()
        }
    }
    @Published var isSidebarVisible = true
    var thumbnailDataByVideoPath: [String: Data] = [:]
    var thumbnailImageByVideoPath: [String: NSImage] = [:]
    var durationByVideoPath: [String: Double] = [:]
    var metadataByVideoPath: [String: VideoMetadata] = [:]
    var sourceInfoByVideoPath: [String: VideoSourceInfo] = [:] {
        didSet { clearVideoSourceCaches() }
    }
    var playbackSupportByVideoPath: [String: VideoPlaybackSupport] = [:]
    @Published var waveformSamplesByVideoPath: [String: [Double]] = [:]
    @Published var frameStripByVideoPath: [String: [Data]] = [:]
    @Published var frameStripImagesByVideoPath: [String: [NSImage]] = [:]
    @Published var sceneStripImagesByVideoPath: [String: [NSImage]] = [:]
    @Published var sceneCutsByVideoPath: [String: [SceneCut]] = [:]
    @Published var sceneCutProgressesByVideoPath: [String: [Double]] = [:]
    @Published var sceneThumbnailVersionsByVideoPath: [String: Int] = [:]
    @Published var sceneDetectionProgress: [String: Double] = [:]
    @Published var sceneBatchJob = TranscriptBatchJob()
    @Published var sampledFrames: [SampledFrame] = [] {
        didSet { rebuildSampledFrameIndexes() }
    }
    @Published var annotations: [AnnotationItem] = [] {
        didSet { rebuildAnnotationIndexes() }
    }
    @Published var audioClips: [AudioClipItem] = [] {
        didSet { rebuildAudioClipIndexes() }
    }
    @Published var audioClipExportProgressByVideoPath: [String: Double] = [:]
    @Published var transcriptSegmentsByVideoPath: [String: [TranscriptSegment]] = [:]
    @Published var transcriptStatusByVideoPath: [String: TranscriptJobStatus] = [:]
    @Published var transcriptBatchJob = TranscriptBatchJob()
    @Published var transcriptExports: [TranscriptExportItem] = []
    @Published var transcriptExportJobs: [String: TranscriptExportJob] = [:]
    @Published var musicsByVideoPath: [String: [MusicRecognitionItem]] = [:] {
        didSet { rebuildMusicIndexes() }
    }
    @Published var localMusicAssets: [LocalMusicAsset] = [] {
        didSet { rebuildMusicIndexes() }
    }
    @Published var localAudioAssets: [LocalAudioAsset] = [] {
        didSet { rebuildAudioClipIndexes() }
    }
    @Published var localMusicWaveformSamplesByPath: [String: [Double]] = [:]
    @Published var localAudioWaveformSamplesByPath: [String: [Double]] = [:]
    @Published var musicDetectionStatusByVideoPath: [String: TranscriptJobStatus] = [:]
    @Published var musicBatchJob = TranscriptBatchJob()
    @Published var musicDownloadBatchJob = TranscriptBatchJob()
    @Published var musicDownloadJobs: [MusicDownloadJob] = [] {
        didSet { saveProjectData() }
    }
    @Published var sortOption: VideoSortOption = VideoSortOption(rawValue: UserDefaults.standard.string(forKey: "videoSortOption") ?? "") ?? .name {
        didSet {
            UserDefaults.standard.set(sortOption.rawValue, forKey: "videoSortOption")
            refreshFilteredVideos()
        }
    }
    @Published var sortDirection: VideoSortDirection = VideoSortDirection(rawValue: UserDefaults.standard.string(forKey: "videoSortDirection") ?? "") ?? .ascending {
        didSet {
            UserDefaults.standard.set(sortDirection.rawValue, forKey: "videoSortDirection")
            refreshFilteredVideos()
        }
    }
    @Published var remoteImportJobs: [RemoteImportJob] = []
    var remoteImportJob: RemoteImportJob? { remoteImportJobs.last }
    @Published var instagramImportEndpoint = UserDefaults.standard.string(forKey: LibraryStore.instagramImportEndpointDefaultsKey) ?? ""
    @Published var downloaderSelfCheckReport = LibraryStore.loadDownloaderSelfCheckReport()

    let lastLibraryPathKey = "lastLibraryPath"
    let lastLibraryBookmarkKey = "lastLibraryBookmark"
    let defaultLibraryPath = "/Users/zhengshihong/Downloads/通用资源/素材库"
    let videoExtensions = LibraryStore.supportedVideoExtensions
    struct SceneCutCacheFile: Codable {
        var detectorVersion: String
        var entries: [String: SceneCutCacheEntry]
    }

    struct SceneCutCacheEntry: Codable {
        var detectorVersion: String
        var videoID: String
        var relativePath: String
        var fileSize: Int64
        var modificationTime: Double
        var duration: Double?
        var cutTimes: [Double]
        var thumbnailData: [Data]? = nil
        var sceneIDs: [String]
        var generatedAt: Date
    }

    nonisolated struct ITunesSearchResponse: Decodable, Sendable {
        var results: [ITunesSongResult]
    }

    nonisolated struct ITunesSongResult: Decodable, Sendable {
        var kind: String?
        var artistName: String?
        var primaryGenreName: String?
    }

    nonisolated struct AppleMusicSearchResponse: Decodable, Sendable {
        var results: [AppleMusicSearchResult]
    }

    struct TranscriptSceneBlock: Sendable {
        var index: Int
        var start: Double
        var end: Double
        var subtitles: [TranscriptSegment]
    }

    nonisolated struct LocalWaveformCacheFile: Codable, Sendable {
        var version: Int
        var generatedAt: Date
        var entries: [LocalWaveformCacheEntry]
    }

    nonisolated struct LocalWaveformCacheEntry: Codable, Equatable, Sendable {
        var kind: String
        var relativePath: String
        var fileIdentity: String?
        var fileSize: Int64
        var modificationTime: Double?
        var sampleCount: Int
        var samples: [Double]
    }

    nonisolated struct LocalWaveformHydrationResult: Sendable {
        var retainedCache: [String: LocalWaveformCacheEntry]
        var hydratedMusic: [String: [Double]]
        var hydratedAudio: [String: [Double]]
    }

    nonisolated enum ResourceLibraryRefreshMode: Equatable, Sendable {
        case cachedOnly
        case deferred
        case immediate
    }

    var thumbnailWorkerTasks: [Task<Void, Never>] = []
    var thumbnailLoadingPaths = Set<String>()
    var thumbnailGenerationFailedPaths = Set<String>()
    var thumbnailLoadGeneration = 0
    var queuedMetadataVideos: [VideoItem] = []
    var queuedMetadataVideoPaths = Set<String>()
    var queuedMetadataWorkerTask: Task<Void, Never>?
    var metadataDisplayRefreshTask: Task<Void, Never>?
    var allTagsCache: [String] = []
    var videoSourcePlatformCache: [String: String?] = [:]
    var videoSourceTitleCache: [String: String?] = [:]
    var waveformTasks: [String: Task<Void, Never>] = [:]
    var audioClipWaveformTasks: [UUID: Task<Void, Never>] = [:]
    var pendingAudioClipWaveformIDs: [UUID] = []
    var pendingAudioClipWaveformIDSet = Set<UUID>()
    var localWaveformCacheByKey: [String: LocalWaveformCacheEntry] = [:]
    var localWaveformCacheLibraryPath: String?
    var localWaveformCacheHydrationTask: Task<Void, Never>?
    var localWaveformCacheSaveTask: Task<Void, Never>?
    var localWaveformCacheNeedsSave = false
    var frameStripTasks: [String: Task<Void, Never>] = [:]
    var sceneDetectionTasks: [String: Task<Void, Never>] = [:]
    var sceneThumbnailHydrationTasks: [String: Task<Void, Never>] = [:]
    var sceneThumbnailHydrationNeeded = Set<String>()
    var transcriptBatchTask: Task<Void, Never>?
    var isTranscriptBatchPaused = false
    var sceneBatchTask: Task<Void, Never>?
    var isSceneBatchPaused = false
    var musicBatchTask: Task<Void, Never>?
    var isMusicBatchPaused = false
    var musicDetectionTasks: [String: Task<Void, Never>] = [:]
    var localMusicRecognitionTask: Task<Void, Never>?
    var musicDownloadBatchTask: Task<Void, Never>?
    var musicDownloadTasks: [UUID: Task<Void, Never>] = [:]
    var musicTagEnrichmentTasks: [String: Task<Void, Never>] = [:]
    var downloaderSelfCheckTask: Task<Void, Never>?
    var lastExternalSelfCheckPreflightAt: Date?
    var resourceLibraryScanTask: Task<Void, Never>?
    var resourceLibraryScanTaskLibraryPath: String?
    var resourceLibraryScanGeneration = 0
    var lastResourceLibraryFullScanAtByPath: [String: Date] = [:]
    var knownLocalResourcePaths = Set<String>()
    var pendingVideoPathRemap: [String: String] = [:]
    var pendingVideoFolderTagsByPath: [String: [String]] = [:]
    var remoteImportTasks: [UUID: Task<Void, Never>] = [:]
    var remoteImportProcesses: [UUID: Process] = [:]
    var scopedLibraryURL: URL?
    var sceneCutCache: [String: SceneCutCacheEntry] = [:]
    var filteredVideos: [VideoItem] = []
    var collectedFramesCache: [SampledFrame] = []
    var sampledFramesByVideoPath: [String: [SampledFrame]] = [:]
    var sampledFrameByID: [UUID: SampledFrame] = [:]
    var frameTagsCache: [String] = []
    var sampledFrameThumbnailImageByID: [UUID: NSImage] = [:]
    var annotationsByVideoPath: [String: [AnnotationItem]] = [:]
    var audioClipsByVideoPath: [String: [AudioClipItem]] = [:]
    var audioTagsCache: [String] = []
    var musicTagsCache: [String] = []
    var projectSaveTask: Task<Void, Never>?
    var projectSaveSequence = 0
    var projectLoadTask: Task<Void, Never>?
    var projectLoadGeneration = 0
    var projectDataLoadState: ProjectDataLoadState = .idle
    var projectDataDirty = false
    var startupAutomationLibraryPath: String?
    var metadataRefreshTask: Task<Void, Never>?
    var videoLibrarySnapshotSaveTask: Task<Void, Never>?
    var videoLibrarySnapshotNeedsSave = false

    nonisolated static let transNetPythonPath = "/Users/zhengshihong/Downloads/Newtybei知识库/进行项目/拉片宝/LapianBao/Tools/transnet-env/bin/python"
    nonisolated static let transNetScriptPath = "/Users/zhengshihong/Downloads/Newtybei知识库/进行项目/拉片宝/LapianBao/Tools/detect_scene_cuts_transnet.py"
    nonisolated static let sceneDetectorVersion = "transnetv2+hardcut-rescue@2026-05-25.1"
    nonisolated static let waveformSampleCount = 4096
    nonisolated static let audioClipWaveformSampleCount = 96
    nonisolated static let audioClipWaveformVersion = AudioClipItem.currentWaveformVersion
    nonisolated static let musicWaveformSampleCount = 180
    nonisolated static let localMusicWaveformSampleCount = 144
    nonisolated static let localAudioWaveformSampleCount = 96
    nonisolated static let audioClipWaveformWorkerCount = 1
    nonisolated static let localWaveformCacheVersion = 1
    nonisolated static let launchMetadataPrefetchLimit = 12
    nonisolated static let launchMetadataWorkerCount = 1
    nonisolated static let launchBackgroundMetadataPrefetchDelay: TimeInterval = 45.0
    nonisolated static let metadataDisplayRefreshIntervalNanoseconds: UInt64 = 33_000_000
    nonisolated static let launchVideoReconcileDelay: TimeInterval = 3.0
    nonisolated static let videoLibraryCacheVersion = 2
    nonisolated static let cachedResourceLibraryFullScanDelay: TimeInterval = 45.0
    nonisolated static let uncachedResourceLibraryFullScanDelay: TimeInterval = 3.0
    nonisolated static let resourceLibraryFullScanCooldown: TimeInterval = 180.0
    nonisolated static let placeholderRemoteImportURL = URL(fileURLWithPath: "/invalid-remote-import-url")
    nonisolated static let tinyGeneratedAudioClipByteLimit: Int64 = 64 * 1024
    nonisolated static let supportedVideoExtensions = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]
    nonisolated static let supportedAudioExtensions = ["m4a", "mp3", "wav", "aac", "aif", "aiff", "flac", "opus", "ogg", "caf", "webm"]
    nonisolated static let supportedImageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tiff", "tif"]

    nonisolated static let musicPythonPath = "/Users/zhengshihong/Downloads/Newtybei知识库/进行项目/拉片宝/LapianBao/Tools/music-env/bin/python3"
    nonisolated static let musicScriptPath = "/Users/zhengshihong/Downloads/Newtybei知识库/进行项目/拉片宝/LapianBao/Tools/detect_music.py"
    nonisolated static let exportRootFolderName = "LapianBaoExports"
    nonisolated static let videoFolderName = "视频"
    nonisolated static let imageExportFolderName = "图片"
    nonisolated static let soundEffectExportFolderName = "音频"
    nonisolated static let legacySoundEffectExportFolderName = "音效"
    nonisolated static let transcriptExportFolderName = "字幕"
    nonisolated static let musicExportFolderName = "音乐"
    nonisolated static let knownSourcePlatforms = ["Instagram", "YouTube", "小红书", "Bilibili", "抖音"]
    nonisolated static let autoSceneBatchKey = "autoStartSceneBatch"
    nonisolated static let autoTranscriptBatchKey = "autoStartTranscriptBatch"
    nonisolated static let autoMusicDownloadBatchKey = "autoStartMusicDownloadBatch"
    nonisolated static let instagramImportEndpointDefaultsKey = "instagramImportEndpoint"
    nonisolated static let downloaderSelfCheckReportKey = "downloaderSelfCheckReport"
    nonisolated static let downloaderSelfCheckProbeURL = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
    nonisolated static let downloaderNightlyMacOSURL = "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_macos"
    nonisolated static let externalSelfCheckPreflightCooldown: TimeInterval = 60 * 60
    nonisolated static let instagramSavedCollectionURLString = "https://www.instagram.com/newtybeibei/saved/all-posts/"
    nonisolated static let xiaohongshuSavedCollectionURLString = "https://www.xiaohongshu.com/user/profile/5eb7bea7000000000100540d?tab=fav&subTab=note"

    nonisolated static func normalizedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }

    nonisolated static func exportFolder(in libraryURL: URL, named folderName: String) -> URL {
        libraryURL
            .appendingPathComponent(exportRootFolderName, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    nonisolated static func mediaFolder(in libraryURL: URL, named folderName: String) -> URL {
        libraryURL.appendingPathComponent(folderName, isDirectory: true)
    }

    nonisolated static func ensureMediaFolders(in libraryURL: URL) {
        for folderName in [videoFolderName, musicExportFolderName, soundEffectExportFolderName, imageExportFolderName] {
            try? FileManager.default.createDirectory(
                at: mediaFolder(in: libraryURL, named: folderName),
                withIntermediateDirectories: true
            )
        }
    }

    nonisolated static func ensureExportFolders(in libraryURL: URL) {
        for folderName in [imageExportFolderName, soundEffectExportFolderName, transcriptExportFolderName, musicExportFolderName] {
            try? FileManager.default.createDirectory(
                at: exportFolder(in: libraryURL, named: folderName),
                withIntermediateDirectories: true
            )
        }
    }

    nonisolated static func localToolURL(
        relativePath: String,
        fallbackPath: String,
        mustBeExecutable: Bool = false,
        sourceFilePath: String = #filePath
    ) -> URL? {
        let fm = FileManager.default
        let sourceRoot = URL(fileURLWithPath: sourceFilePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let currentDirectory = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)

        let candidates = [
            URL(fileURLWithPath: fallbackPath),
            sourceRoot.appendingPathComponent(relativePath),
            currentDirectory.appendingPathComponent(relativePath)
        ]

        var checkedPaths = Set<String>()
        for url in candidates where checkedPaths.insert(url.path).inserted {
            if mustBeExecutable {
                if fm.isExecutableFile(atPath: url.path) { return url }
            } else if fm.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

}
