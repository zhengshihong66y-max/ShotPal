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
struct VideoLibrarySidebarMetrics: Equatable {
    var platforms: [String] = []
    var authors: [String] = []
    var platformCounts: [String: Int] = [:]
    var authorCounts: [String: Int] = [:]
    var tagCountsByKey: [String: Int] = [:]
}

struct AccountCookieSummary: Equatable, Sendable {
    var instagramCookieCount = 0
    var xiaohongshuCookieCount = 0
    var youtubeCookieCount = 0
    var bilibiliCookieCount = 0
    var douyinCookieCount = 0
    var hasInstagramSession = false
    var hasXiaohongshuSession = false
    var hasYouTubeSession = false
    var hasBilibiliSession = false
    var hasDouyinSession = false
    var updatedAt: Date?

    var hasAnySession: Bool {
        hasInstagramSession
            || hasXiaohongshuSession
            || hasYouTubeSession
            || hasBilibiliSession
            || hasDouyinSession
    }

    var detailText: String {
        let instagram = hasInstagramSession ? "Instagram 已登录" : "Instagram 未登录"
        let xiaohongshu = hasXiaohongshuSession ? "小红书已登录" : "小红书未登录"
        let youtube = hasYouTubeSession ? "YouTube 已登录" : "YouTube 未登录"
        let bilibili = hasBilibiliSession ? "Bilibili 已登录" : "Bilibili 未登录"
        let douyin = hasDouyinSession ? "抖音已登录" : "抖音未登录"
        return "\(instagram) · \(xiaohongshu) · \(youtube) · \(bilibili) · \(douyin)"
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published var libraryURL: URL?
    @Published var libraryScanProgress: LibraryScanProgress?
    @Published var videos: [VideoItem] = [] {
        didSet {
            videoByPath = Dictionary(videos.map { ($0.url.path, $0) }, uniquingKeysWith: { current, _ in current })
            videoPathSet = Set(videos.map { $0.url.path })
            rebuildAllTagsCache()
            clearVideoSourceCaches()
            markLibrarySidebarMetricsDirty()
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
            markLibrarySidebarMetricsDirty()
            refreshFilteredVideos()
        }
    }
    @Published var isSidebarVisible = true
    var thumbnailDataByVideoPath: [String: Data] = [:]
    var thumbnailImageByVideoPath: [String: NSImage] = [:]
    @Published var thumbnailImageRevisionByVideoPath: [String: Int] = [:]
    var durationByVideoPath: [String: Double] = [:]
    var metadataByVideoPath: [String: VideoMetadata] = [:] {
        didSet { markLibraryPresentationDirty() }
    }
    var sourceInfoByVideoPath: [String: VideoSourceInfo] = [:] {
        didSet {
            objectWillChange.send()
            clearVideoSourceCaches()
            rebuildAllTagsCache()
            markLibrarySidebarMetricsDirty()
            markLibraryPresentationDirty()
        }
    }
    @Published var librarySidebarMetrics = VideoLibrarySidebarMetrics()
    var librarySidebarMetricsRebuildDeferralDepth = 0
    var needsLibrarySidebarMetricsRebuild = false
    var playbackSupportByVideoPath: [String: VideoPlaybackSupport] = [:]
    @Published var waveformSamplesByVideoPath: [String: [Double]] = [:]
    @Published var frameStripByVideoPath: [String: [Data]] = [:]
    @Published var frameStripImagesByVideoPath: [String: [NSImage]] = [:]
    @Published var sceneStripImagesByVideoPath: [String: [NSImage]] = [:]
    @Published var sceneCutsByVideoPath: [String: [SceneCut]] = [:]
    @Published var sceneCutProgressesByVideoPath: [String: [Double]] = [:]
    @Published var sceneThumbnailVersionsByVideoPath: [String: Int] = [:]
    @Published var sceneDetectionProgress: [String: Double] = [:]
    @Published var sceneDetectionErrorByVideoPath: [String: String] = [:]
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
    @Published var audioClipExportErrorByVideoPath: [String: String] = [:]
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
    @Published var localImageAssets: [LocalImageAsset] = []
    @Published var localMusicWaveformSamplesByPath: [String: [Double]] = [:]
    @Published var localMusicWaveformRenderingPaths = Set<String>()
    @Published var localMusicWaveformQueuedPaths = Set<String>()
    @Published var localMusicWaveformProgressByPath: [String: Double] = [:]
    @Published var musicDownloadWaveformProgressByID: [UUID: Double] = [:]
    @Published var isHydratingLocalWaveformCache = false
    @Published var localAudioWaveformSamplesByPath: [String: [Double]] = [:]
    @Published var musicFileDurationsByPath: [String: Double] = [:]
    @Published var musicDetectionStatusByVideoPath: [String: TranscriptJobStatus] = [:]
    @Published var musicDownloadBatchJob = TranscriptBatchJob()
    @Published var activeMusicPreviewJobID: UUID?
    @Published var focusedMusicPreviewJobID: UUID?
    @Published var musicDownloadJobs: [MusicDownloadJob] = [] {
        didSet { saveProjectData() }
    }
    @Published var sortOption: VideoSortOption = VideoSortOption(rawValue: AppSettings.videoSortOptionRawValue ?? "") ?? .name {
        didSet {
            AppSettings.videoSortOptionRawValue = sortOption.rawValue
            refreshFilteredVideos()
        }
    }
    @Published var sortDirection: VideoSortDirection = VideoSortDirection(rawValue: AppSettings.videoSortDirectionRawValue ?? "") ?? .ascending {
        didSet {
            AppSettings.videoSortDirectionRawValue = sortDirection.rawValue
            refreshFilteredVideos()
        }
    }
    @Published var remoteImportJobs: [RemoteImportJob] = []
    var remoteImportJob: RemoteImportJob? { remoteImportJobs.last }
    @Published var instagramImportEndpoint = AppSettings.instagramImportEndpoint
    @Published var downloaderSelfCheckReport = LibraryStore.loadDownloaderSelfCheckReport()
    @Published var accountCookieSummary = AccountCookieSummary()
    @Published var isRefreshingAccountCookieSummary = false
    @Published var isClearingAccountCookies = false

    var musicPreviewKeyboardTargetJobID: UUID? {
        activeMusicPreviewJobID ?? focusedMusicPreviewJobID
    }

    func activateMusicPreviewJob(_ id: UUID) {
        activeMusicPreviewJobID = id
        focusedMusicPreviewJobID = id
    }

    func pauseMusicPreviewJob(_ id: UUID?) {
        guard activeMusicPreviewJobID == id else { return }
        activeMusicPreviewJobID = nil
    }

    func clearMusicPreviewJob(_ id: UUID?) {
        guard let id else { return }
        if activeMusicPreviewJobID == id {
            activeMusicPreviewJobID = nil
        }
        if focusedMusicPreviewJobID == id {
            focusedMusicPreviewJobID = nil
        }
    }

    let defaultLibraryPath = AppSettings.defaultLibraryPath
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
        var trackTimeMillis: Double?
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
    var queuedMetadataVideos: [(video: VideoItem, allowThumbnailGeneration: Bool)] = []
    var queuedMetadataVideoPaths = Set<String>()
    var queuedMetadataWorkerTask: Task<Void, Never>?
    var pendingCachedThumbnailHydrationEntries: [(path: String, data: Data)] = []
    var pendingCachedThumbnailHydrationPaths = Set<String>()
    var cachedThumbnailHydrationTask: Task<Void, Never>?
    var metadataDisplayRefreshTask: Task<Void, Never>?
    var videoPathSet = Set<String>()
    var thumbnailImageAccessTickByPath: [String: Int] = [:]
    var thumbnailImageAccessTick = 0
    var allTagsCache: [String] = []
    var videoByPath: [String: VideoItem] = [:]
    var videoTagsByPathCache: [String: [String]] = [:]
    var videoTagSetsByPathCache: [String: Set<String>] = [:]
    var videoPathsByTagCache: [String: Set<String>] = [:]
    var videoTagSortKeyByPathCache: [String: String] = [:]
    var videoSourcePlatformCache: [String: String?] = [:]
    var videoSourceAuthorCache: [String: String?] = [:]
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
    var localMusicWaveformTasks: [String: Task<Void, Never>] = [:]
    var queuedLocalMusicWaveformAssets: [LocalMusicAsset] = []
    var musicFileDurationTasks: [String: Task<Void, Never>] = [:]
    var frameStripTasks: [String: Task<Void, Never>] = [:]
    var frameStripEmptyRetryCountsByPath: [String: Int] = [:]
    var sceneDetectionTasks: [String: Task<Void, Never>] = [:]
    var sceneThumbnailHydrationTasks: [String: Task<Void, Never>] = [:]
    var sceneThumbnailHydrationNeeded = Set<String>()
    var transcriptBatchTask: Task<Void, Never>?
    var isTranscriptBatchPaused = false
    var sceneBatchTask: Task<Void, Never>?
    var isSceneBatchPaused = false
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
    var resourceLibrarySnapshotLibraryPath: String?
    var lastResourceLibraryFullScanAtByPath: [String: Date] = [:]
    var libraryScanTask: Task<Void, Never>?
    var libraryScanGeneration = 0
    var isPresentingInitialLibraryPicker = false
    @Published var knownLocalResourcePaths = Set<String>()
    var pendingVideoPathRemap: [String: String] = [:]
    var pendingVideoFolderTagsByPath: [String: [String]] = [:]
    var remoteImportTasks: [UUID: Task<Void, Never>] = [:]
    var remoteImportProcesses: [UUID: Process] = [:]
    var scopedLibraryURL: URL?
    var sceneCutCache: [String: SceneCutCacheEntry] = [:]
    var filteredVideos: [VideoItem] = []
    var libraryPresentationRevision = 0
    var libraryBrowserProjectionCache: LibraryBrowserProjectionCache?
    var collectedFramesCache: [SampledFrame] = []
    var sampledFramesByVideoPath: [String: [SampledFrame]] = [:]
    var sampledFrameByID: [UUID: SampledFrame] = [:]
    var frameTagsCache: [String] = []
    var sampledFrameThumbnailImageByID: [UUID: NSImage] = [:]
    var sampledFrameThumbnailImageAccessTickByID: [UUID: Int] = [:]
    var sampledFrameThumbnailImageAccessTick = 0
    var annotationsByVideoPath: [String: [AnnotationItem]] = [:]
    var audioClipsByVideoPath: [String: [AudioClipItem]] = [:]
    var audioTagsCache: [String] = []
    var musicTagsCache: [String] = []
    var projectSaveTask: Task<Void, Never>?
    var projectSaveSequence = 0
    var projectLoadTask: Task<Void, Never>?
    var projectLoadGeneration = 0
    @Published var projectDataLoadState: ProjectDataLoadState = .idle
    var projectDataDirty = false
    var startupAutomationLibraryPath: String?
    var metadataRefreshTask: Task<Void, Never>?
    var videoLibrarySnapshotSaveTask: Task<Void, Never>?
    var videoLibrarySnapshotNeedsSave = false
    var transientMediaCacheAccessTickByPath: [String: Int] = [:]
    var transientMediaCacheAccessTick = 0
    var transientMediaCacheTrimTask: Task<Void, Never>?
    var transcriptTasks: [String: Task<Void, Never>] = [:]

    nonisolated static let sceneDetectorVersion = "transnetv2+hardcut-rescue@2026-05-25.1"
    nonisolated static let waveformSampleCount = 4096
    nonisolated static let audioClipWaveformSampleCount = 96
    nonisolated static let audioClipWaveformVersion = AudioClipItem.currentWaveformVersion
    nonisolated static let musicWaveformSampleCount = 720
    nonisolated static let localMusicWaveformSampleCount = 144
    nonisolated static let localAudioWaveformSampleCount = 96
    nonisolated static let localMusicWaveformWorkerCount = 2
    nonisolated static let audioClipWaveformWorkerCount = 1
    nonisolated static let localWaveformCacheVersion = 2
    nonisolated static let launchMetadataPrefetchLimit = 0
    nonisolated static let launchMetadataWorkerCount = 1
    nonisolated static let launchBackgroundMetadataPrefetchDelay: TimeInterval = 45.0
    nonisolated static let launchCachedThumbnailHydrationDelay: TimeInterval = 1.5
    nonisolated static let launchCachedThumbnailDataRestoreDelay: TimeInterval = 0.8
    nonisolated static let launchCachedThumbnailHydrationLimit = 48
    nonisolated static let launchInitialVideoSelectionDelay: TimeInterval = 2.0
    nonisolated static let metadataDisplayRefreshIntervalNanoseconds: UInt64 = 180_000_000
    nonisolated static let maxDecodedLibraryThumbnailImages = 180
    nonisolated static let maxResidentWaveformVideoCaches = 12
    nonisolated static let maxResidentFrameStripVideoCaches = 10
    nonisolated static let maxResidentSceneCutVideoCaches = 10
    nonisolated static let sceneCachedThumbnailEagerDecodeLimit = 48
    nonisolated static let frameStripEmptyRetryLimit = 2
    nonisolated static let frameStripEmptyRetryDelay: TimeInterval = 1.4
    nonisolated static let maxDecodedSampledFrameImages = 240
    nonisolated static let transientMediaCacheTrimDelay: TimeInterval = 2.5
    nonisolated static let launchVideoReconcileDelay: TimeInterval = 12.0
    nonisolated static let videoLibraryCacheVersion = 2
    nonisolated static let cachedResourceLibraryFullScanDelay: TimeInterval = 45.0
    nonisolated static let uncachedResourceLibraryFullScanDelay: TimeInterval = 3.0
    nonisolated static let resourceLibraryFullScanCooldown: TimeInterval = 180.0
    nonisolated static let placeholderRemoteImportURL = URL(fileURLWithPath: "/invalid-remote-import-url")
    nonisolated static let tinyGeneratedAudioClipByteLimit: Int64 = 64 * 1024
    nonisolated static let supportedVideoExtensions = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]
    nonisolated static let supportedAudioExtensions = ["m4a", "mp3", "wav", "aac", "aif", "aiff", "flac", "opus", "ogg", "caf", "webm"]
    nonisolated static let supportedImageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tiff", "tif"]

    nonisolated static let unknownSourcePlatformName = "其他"
    nonisolated static let knownSourcePlatforms = ["Instagram", "YouTube", "小红书", "Bilibili", "抖音", unknownSourcePlatformName]
    nonisolated static let downloaderNightlyExecutableURL = "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp"
    nonisolated static let downloaderNightlyMacOSURL = "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_macos"
    nonisolated static let externalSelfCheckPreflightCooldown: TimeInterval = 60 * 60
    nonisolated static let instagramSavedCollectionURLString = "https://www.instagram.com/"
    nonisolated static let xiaohongshuSavedCollectionURLString = "https://www.xiaohongshu.com/explore"

    nonisolated static func normalizedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }

}
