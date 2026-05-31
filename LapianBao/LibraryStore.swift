//
//  LibraryStore.swift
//  LapianBao
//
//  Created by 郑士泓 on 2026/5/24.
//

import AppKit
import AVFoundation
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

struct SceneCut: Identifiable {
    let id: String
    let time: Double
    let thumbnailImage: NSImage
    let isPlaceholder: Bool

    nonisolated init(id: String, time: Double, thumbnailImage: NSImage, isPlaceholder: Bool = false) {
        self.id = id
        self.time = time
        self.thumbnailImage = thumbnailImage
        self.isPlaceholder = isPlaceholder
    }
}

struct VideoItem: Identifiable, Hashable, Sendable {
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

    var dependsOnMetadata: Bool {
        switch self {
        case .importDate, .duration, .fileSize, .resolution:
            return true
        case .name, .tags:
            return false
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

struct VideoSourceInfo: Codable, Equatable, Sendable {
    var platform: String
    var sourceURL: String?
    var authorName: String?
    var title: String? = nil
}

struct SampledFrame: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
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

struct AnnotationItem: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case frame
        case audio
        case content

        var id: String { rawValue }

        var title: String {
            switch self {
            case .frame: return "画面"
            case .audio: return "声音"
            case .content: return "内容"
            }
        }
    }

    var id: UUID = UUID()
    var videoPath: String
    var videoName: String
    var time: Double
    var kind: Kind = .frame
    var text: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        videoPath: String,
        videoName: String,
        time: Double,
        kind: Kind = .frame,
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.videoPath = videoPath
        self.videoName = videoName
        self.time = time
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, videoPath, videoName, time, kind, text, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        videoPath = try container.decode(String.self, forKey: .videoPath)
        videoName = try container.decode(String.self, forKey: .videoName)
        time = try container.decode(Double.self, forKey: .time)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .frame
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(videoPath, forKey: .videoPath)
        try container.encode(videoName, forKey: .videoName)
        try container.encode(time, forKey: .time)
        try container.encode(kind, forKey: .kind)
        try container.encode(text, forKey: .text)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct AudioClipItem: Identifiable, Codable, Equatable, Sendable {
    nonisolated static let currentWaveformVersion = 2

    var id: UUID = UUID()
    var videoPath: String
    var videoName: String
    var inTime: Double
    var outTime: Double
    var filePath: String?
    var waveformSamples: [Double]?
    var waveformVersion: Int?
    var note: String = ""
    var tags: [String] = []
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        videoPath: String,
        videoName: String,
        inTime: Double,
        outTime: Double,
        filePath: String? = nil,
        waveformSamples: [Double]? = nil,
        waveformVersion: Int? = nil,
        note: String = "",
        tags: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.videoPath = videoPath
        self.videoName = videoName
        self.inTime = inTime
        self.outTime = outTime
        self.filePath = filePath
        self.waveformSamples = waveformSamples
        self.waveformVersion = waveformVersion
        self.note = note
        self.tags = tags
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, videoPath, videoName, inTime, outTime, filePath, waveformSamples, waveformVersion, note, tags, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        videoPath = try container.decode(String.self, forKey: .videoPath)
        videoName = try container.decode(String.self, forKey: .videoName)
        inTime = try container.decode(Double.self, forKey: .inTime)
        outTime = try container.decode(Double.self, forKey: .outTime)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        waveformSamples = try container.decodeIfPresent([Double].self, forKey: .waveformSamples)
        waveformVersion = try container.decodeIfPresent(Int.self, forKey: .waveformVersion)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(videoPath, forKey: .videoPath)
        try container.encode(videoName, forKey: .videoName)
        try container.encode(inTime, forKey: .inTime)
        try container.encode(outTime, forKey: .outTime)
        try container.encodeIfPresent(filePath, forKey: .filePath)
        try container.encodeIfPresent(waveformSamples, forKey: .waveformSamples)
        try container.encodeIfPresent(waveformVersion, forKey: .waveformVersion)
        try container.encode(note, forKey: .note)
        try container.encode(tags, forKey: .tags)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var videoPath: String
    var start: Double
    var end: Double
    var text: String
}

struct TranscriptExportItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var videoPath: String
    var videoName: String
    var filePath: String
    var segmentCount: Int
    var startTime: Double
    var endTime: Double
    var createdAt: Date = Date()
}

struct TranscriptExportJob: Identifiable, Equatable {
    var videoPath: String
    var videoName: String
    var progress: Double
    var errorMessage: String?
    var createdAt: Date = Date()

    var id: String { videoPath }
    var isFailed: Bool { errorMessage != nil }
}

enum TranscriptJobStatus: Equatable {
    case idle
    case running(String)
    case completed
    case failed(String)
}

struct TranscriptBatchJob: Equatable {
    enum Status: Equatable {
        case idle
        case running
        case paused
        case completed
        case failed(String)
    }

    var status: Status = .idle
    var total: Int = 0
    var completed: Int = 0
    var currentVideoPath: String?
    var currentVideoName: String?
    var progress: Double = 0
}

struct ExternalServiceSelfCheckItem: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case succeeded
        case warning
        case failed
    }

    var key: String
    var title: String
    var status: Status
    var message: String

    var id: String { key }
}

struct DownloaderSelfCheckReport: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case idle
        case running
        case succeeded
        case failed
    }

    var status: Status = .idle
    var checkedAt: Date?
    var message: String = "未自检"
    var ytdlpPath: String?
    var ytdlpVersion: String?
    var ffmpegPath: String?
    var youtubeProbeTitle: String?
    var serviceChecks: [ExternalServiceSelfCheckItem] = []

    var isRunning: Bool { status == .running }

    private enum CodingKeys: String, CodingKey {
        case status, checkedAt, message, ytdlpPath, ytdlpVersion, ffmpegPath, youtubeProbeTitle, serviceChecks
    }

    nonisolated init(
        status: Status = .idle,
        checkedAt: Date? = nil,
        message: String = "未自检",
        ytdlpPath: String? = nil,
        ytdlpVersion: String? = nil,
        ffmpegPath: String? = nil,
        youtubeProbeTitle: String? = nil,
        serviceChecks: [ExternalServiceSelfCheckItem] = []
    ) {
        self.status = status
        self.checkedAt = checkedAt
        self.message = message
        self.ytdlpPath = ytdlpPath
        self.ytdlpVersion = ytdlpVersion
        self.ffmpegPath = ffmpegPath
        self.youtubeProbeTitle = youtubeProbeTitle
        self.serviceChecks = serviceChecks
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .idle
        checkedAt = try container.decodeIfPresent(Date.self, forKey: .checkedAt)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? "未自检"
        ytdlpPath = try container.decodeIfPresent(String.self, forKey: .ytdlpPath)
        ytdlpVersion = try container.decodeIfPresent(String.self, forKey: .ytdlpVersion)
        ffmpegPath = try container.decodeIfPresent(String.self, forKey: .ffmpegPath)
        youtubeProbeTitle = try container.decodeIfPresent(String.self, forKey: .youtubeProbeTitle)
        serviceChecks = try container.decodeIfPresent([ExternalServiceSelfCheckItem].self, forKey: .serviceChecks) ?? []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(checkedAt, forKey: .checkedAt)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(ytdlpPath, forKey: .ytdlpPath)
        try container.encodeIfPresent(ytdlpVersion, forKey: .ytdlpVersion)
        try container.encodeIfPresent(ffmpegPath, forKey: .ffmpegPath)
        try container.encodeIfPresent(youtubeProbeTitle, forKey: .youtubeProbeTitle)
        try container.encode(serviceChecks, forKey: .serviceChecks)
    }
}

struct MusicRecognitionItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var artist: String
    var artworkURL: String
    var appleMusicURL: String
    var detectedAt: Double  // seconds into the video where this song was found
    var tags: [String] = []

    nonisolated init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        artworkURL: String,
        appleMusicURL: String,
        detectedAt: Double,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.appleMusicURL = appleMusicURL
        self.detectedAt = detectedAt
        self.tags = Self.cleanedTags(tags.isEmpty ? [artist] : tags)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist
        case artworkURL = "artwork_url"
        case appleMusicURL = "apple_music_url"
        case detectedAt = "detected_at"
        case tags
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
        artworkURL = try container.decodeIfPresent(String.self, forKey: .artworkURL) ?? ""
        appleMusicURL = try container.decodeIfPresent(String.self, forKey: .appleMusicURL) ?? ""
        detectedAt = try container.decodeIfPresent(Double.self, forKey: .detectedAt) ?? 0
        let decodedTags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        tags = Self.cleanedTags(decodedTags.isEmpty ? [artist] : decodedTags)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encode(artworkURL, forKey: .artworkURL)
        try container.encode(appleMusicURL, forKey: .appleMusicURL)
        try container.encode(detectedAt, forKey: .detectedAt)
        try container.encode(tags, forKey: .tags)
    }

    nonisolated static func cleanedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    nonisolated var displayTags: [String] {
        Self.cleanedTags(tags.isEmpty ? [artist] : tags)
    }
}

struct AppleMusicSearchResult: Identifiable, Codable, Equatable, Sendable {
    var trackID: Int
    var title: String
    var artist: String
    var album: String
    var genre: String
    var artworkURL: String
    var appleMusicURL: String
    var duration: Double

    var id: Int { trackID }

    private enum CodingKeys: String, CodingKey {
        case trackID = "trackId"
        case title = "trackName"
        case artist = "artistName"
        case album = "collectionName"
        case genre = "primaryGenreName"
        case artworkURL = "artworkUrl100"
        case appleMusicURL = "trackViewUrl"
        case trackTimeMillis
    }

    init(
        trackID: Int,
        title: String,
        artist: String,
        album: String = "",
        genre: String = "",
        artworkURL: String = "",
        appleMusicURL: String = "",
        duration: Double = 0
    ) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.artworkURL = artworkURL
        self.appleMusicURL = appleMusicURL
        self.duration = duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackID = try container.decodeIfPresent(Int.self, forKey: .trackID) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
        album = try container.decodeIfPresent(String.self, forKey: .album) ?? ""
        genre = try container.decodeIfPresent(String.self, forKey: .genre) ?? ""
        let rawArtwork = try container.decodeIfPresent(String.self, forKey: .artworkURL) ?? ""
        artworkURL = Self.normalizedArtworkURLString(rawArtwork)
        appleMusicURL = try container.decodeIfPresent(String.self, forKey: .appleMusicURL) ?? ""
        let millis = try container.decodeIfPresent(Double.self, forKey: .trackTimeMillis) ?? 0
        duration = millis > 0 ? millis / 1000 : 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trackID, forKey: .trackID)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encode(album, forKey: .album)
        try container.encode(genre, forKey: .genre)
        try container.encode(artworkURL, forKey: .artworkURL)
        try container.encode(appleMusicURL, forKey: .appleMusicURL)
        try container.encode(duration * 1000, forKey: .trackTimeMillis)
    }

    func asMusicRecognitionItem() -> MusicRecognitionItem {
        MusicRecognitionItem(
            title: title,
            artist: artist,
            artworkURL: artworkURL,
            appleMusicURL: appleMusicURL,
            detectedAt: 0,
            tags: MusicRecognitionItem.cleanedTags([artist, genre])
        )
    }

    private static func normalizedArtworkURLString(_ rawURLString: String) -> String {
        var text = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        if text.hasPrefix("//") {
            text = "https:" + text
        } else if text.hasPrefix("http://") {
            text = "https://" + String(text.dropFirst("http://".count))
        }

        return text.replacingOccurrences(
            of: #"(\d+)x(\d+)bb(\.[A-Za-z0-9]+)$"#,
            with: "512x512bb$3",
            options: .regularExpression
        )
    }
}

struct LocalMusicAsset: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case original
        case instrumental
        case unknown

        nonisolated var label: String {
            switch self {
            case .original: return "原曲"
            case .instrumental: return "伴奏"
            case .unknown: return "音乐"
            }
        }
    }

    var filePath: String
    var title: String
    var fileExtension: String
    var role: Role
    var tags: [String]
    var duration: Double
    var fileSize: Int64
    var modifiedAt: Date?

    var id: String { filePath }
}

struct LocalAudioAsset: Identifiable, Codable, Equatable, Sendable {
    var filePath: String
    var title: String
    var fileExtension: String
    var tags: [String]
    var duration: Double
    var fileSize: Int64
    var modifiedAt: Date?

    var id: String { filePath }
}

struct MusicDownloadJob: Identifiable, Codable, Equatable, Sendable {
    enum DownloadType: String, CaseIterable, Codable, Equatable, Sendable {
        case original
        case instrumental

        var label: String { self == .original ? "原曲" : "伴奏" }
        var searchSuffix: String { self == .original ? "" : " instrumental" }
    }

    var id = UUID()
    var songKey: String
    var type: DownloadType
    var status: RemoteImportJob.Status
    var downloadProgress: Double?
    var filePath: String?
    var waveformSamples: [Double]?
    var isPreparingWaveform = false
    var createdAt: Date = Date()

    private enum CodingKeys: String, CodingKey {
        case id, songKey, type, status, statusMessage, downloadProgress, filePath, waveformSamples, isPreparingWaveform, createdAt
    }

    private enum PersistedStatus: String, Codable {
        case idle
        case importing
        case transcoding
        case finalizing
        case paused
        case succeeded
        case failed
    }

    init(
        id: UUID = UUID(),
        songKey: String,
        type: DownloadType,
        status: RemoteImportJob.Status,
        downloadProgress: Double? = nil,
        filePath: String? = nil,
        waveformSamples: [Double]? = nil,
        isPreparingWaveform: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.songKey = songKey
        self.type = type
        self.status = status
        self.downloadProgress = downloadProgress
        self.filePath = filePath
        self.waveformSamples = waveformSamples
        self.isPreparingWaveform = isPreparingWaveform
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        songKey = try container.decode(String.self, forKey: .songKey)
        type = try container.decode(DownloadType.self, forKey: .type)
        downloadProgress = try container.decodeIfPresent(Double.self, forKey: .downloadProgress)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        waveformSamples = try container.decodeIfPresent([Double].self, forKey: .waveformSamples)
        isPreparingWaveform = false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        let persistedStatus = try container.decodeIfPresent(PersistedStatus.self, forKey: .status) ?? .idle
        let message = try container.decodeIfPresent(String.self, forKey: .statusMessage) ?? ""
        switch persistedStatus {
        case .idle:
            status = .idle
        case .importing, .transcoding, .finalizing, .paused:
            status = .paused
        case .succeeded:
            status = .succeeded(message)
        case .failed:
            status = .failed(message)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(songKey, forKey: .songKey)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(downloadProgress, forKey: .downloadProgress)
        try container.encodeIfPresent(filePath, forKey: .filePath)
        try container.encodeIfPresent(waveformSamples, forKey: .waveformSamples)
        try container.encode(false, forKey: .isPreparingWaveform)
        try container.encode(createdAt, forKey: .createdAt)

        switch status {
        case .idle:
            try container.encode(PersistedStatus.idle, forKey: .status)
        case .importing:
            try container.encode(PersistedStatus.importing, forKey: .status)
        case .transcoding:
            try container.encode(PersistedStatus.transcoding, forKey: .status)
        case .finalizing:
            try container.encode(PersistedStatus.finalizing, forKey: .status)
        case .paused:
            try container.encode(PersistedStatus.paused, forKey: .status)
        case let .succeeded(filename):
            try container.encode(PersistedStatus.succeeded, forKey: .status)
            try container.encode(filename, forKey: .statusMessage)
        case let .failed(message):
            try container.encode(PersistedStatus.failed, forKey: .status)
            try container.encode(message, forKey: .statusMessage)
        }
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
    enum Status: Equatable, Sendable {
        case idle
        case importing
        case transcoding          // VP9/AV1 → H.264 后处理阶段
        case finalizing
        case paused
        case succeeded(String)
        case failed(String)
    }

    let id = UUID()
    let sourceURL: URL
    let platform: String
    var status: Status
    var downloadProgress: Double? // nil = 不确定；0.0–1.0 = 已知进度
    var downloadSpeed: String? = nil
    var outputPath: String? = nil
    var thumbnailData: Data? = nil
}

struct InstagramSavedImportResult: Equatable, Sendable {
    var foundCount: Int
    var skippedCount: Int
    var queuedCount: Int
    var queuedLinks: [String]
}

private enum InstagramSavedImportError: LocalizedError {
    case noLibrary
    case noLinks
    case noXiaohongshuVideoLinks
    case chromeCookieUnavailable(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .noLibrary:
            return "请先打开一个素材库文件夹"
        case .noLinks:
            return "没有读到 Instagram 收藏链接，请确认 Chrome 已登录且收藏页可访问"
        case .noXiaohongshuVideoLinks:
            return "没有读到小红书收藏视频，请确认 Chrome 已登录且收藏页里有视频笔记"
        case .chromeCookieUnavailable(let message):
            return message
        case .timedOut:
            return "读取收藏页超时"
        }
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

private actor SceneDetectionGate {
    static let shared = SceneDetectionGate()

    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isRunning {
            isRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard let nextWaiter = waiters.first else {
            isRunning = false
            return
        }

        waiters.removeFirst()
        nextWaiter.resume()
    }
}

nonisolated private final class ToolProcessRegistry: @unchecked Sendable {
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

nonisolated private final class PipeDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

nonisolated private final class PipeLineCollector: @unchecked Sendable {
    private let dataCollector = PipeDataCollector()
    private let lock = NSLock()
    private var pendingText = ""

    func append(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        dataCollector.append(data)
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return [] }

        lock.lock()
        defer { lock.unlock() }

        pendingText += text.replacingOccurrences(of: "\r", with: "\n")
        let parts = pendingText.components(separatedBy: .newlines)
        guard parts.count > 1 else { return [] }

        pendingText = parts.last ?? ""
        return Array(parts.dropLast())
    }

    func finish(with data: Data = Data()) -> [String] {
        var lines = append(data)

        lock.lock()
        if !pendingText.isEmpty {
            lines.append(pendingText)
            pendingText = ""
        }
        lock.unlock()

        return lines
    }

    var data: Data {
        dataCollector.data
    }
}

private actor VideoMetadataQueue {
    private let videos: [VideoItem]
    private var nextIndex = 0

    init(videos: [VideoItem]) {
        self.videos = videos
    }

    func next() -> VideoItem? {
        guard nextIndex < videos.count else { return nil }
        let video = videos[nextIndex]
        nextIndex += 1
        return video
    }
}

nonisolated private struct DownloadProgressUpdate: Sendable {
    var progress: Double?
    var speed: String?
}

nonisolated private struct ProjectDataFile: Codable, Sendable {
    var sampledFrames: [SampledFrame]
    var annotations: [AnnotationItem]
    var audioClips: [AudioClipItem]
    var transcripts: [String: [TranscriptSegment]]
    var transcriptExports: [TranscriptExportItem]?
    var musicsByVideoPath: [String: [MusicRecognitionItem]]? // optional for backward compat
    var musicDownloadJobs: [MusicDownloadJob]? // optional for backward compat
}

nonisolated private enum ResourceLibrarySQLite {
    static func write(libraryURL: URL, music: [LocalMusicAsset], audio: [LocalAudioAsset]) {
        let sqliteURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        guard FileManager.default.isExecutableFile(atPath: sqliteURL.path) else { return }

        let dbURL = libraryURL.appendingPathComponent(".lapianbao.sqlite")
        let process = Process()
        process.executableURL = sqliteURL
        process.arguments = [dbURL.path]
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write(sql(libraryURL: libraryURL, music: music, audio: audio).data(using: .utf8) ?? Data())
            try? inputPipe.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {
            try? inputPipe.fileHandleForWriting.close()
        }
    }

    private static func sql(libraryURL: URL, music: [LocalMusicAsset], audio: [LocalAudioAsset]) -> String {
        var lines: [String] = [
            "PRAGMA journal_mode=WAL;",
            "CREATE TABLE IF NOT EXISTS assets (kind TEXT NOT NULL, path TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, role TEXT NOT NULL, tags TEXT NOT NULL, file_extension TEXT NOT NULL, file_size INTEGER NOT NULL, modified_at REAL, duration REAL NOT NULL);",
            "BEGIN IMMEDIATE;",
            "DELETE FROM assets WHERE kind IN ('music', 'audio', '音乐', '音频');"
        ]

        for item in music {
            lines.append(insertSQL(
                kind: "音乐",
                path: relativePath(item.filePath, base: libraryURL),
                title: item.title,
                role: item.role.rawValue,
                tags: item.tags,
                fileExtension: item.fileExtension,
                fileSize: item.fileSize,
                modifiedAt: item.modifiedAt,
                duration: item.duration
            ))
        }

        for item in audio {
            lines.append(insertSQL(
                kind: "音频",
                path: relativePath(item.filePath, base: libraryURL),
                title: item.title,
                role: "soundEffect",
                tags: item.tags,
                fileExtension: item.fileExtension,
                fileSize: item.fileSize,
                modifiedAt: item.modifiedAt,
                duration: item.duration
            ))
        }

        lines.append("COMMIT;")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func insertSQL(
        kind: String,
        path: String,
        title: String,
        role: String,
        tags: [String],
        fileExtension: String,
        fileSize: Int64,
        modifiedAt: Date?,
        duration: Double
    ) -> String {
        let tagsJSON = (try? String(
            data: JSONEncoder().encode(tags),
            encoding: .utf8
        )) ?? "[]"
        let modifiedValue = modifiedAt.map { "\($0.timeIntervalSince1970)" } ?? "NULL"
        return """
        INSERT OR REPLACE INTO assets (kind, path, title, role, tags, file_extension, file_size, modified_at, duration) VALUES (\(quote(kind)), \(quote(path)), \(quote(title)), \(quote(role)), \(quote(tagsJSON)), \(quote(fileExtension)), \(fileSize), \(modifiedValue), \(duration));
        """
    }

    private static func relativePath(_ path: String, base libraryURL: URL) -> String {
        let base = libraryURL.path.hasSuffix("/") ? libraryURL.path : libraryURL.path + "/"
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    private static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}

private enum ProjectDataLoadState {
    case idle
    case loading
    case loaded
}

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

    private let lastLibraryPathKey = "lastLibraryPath"
    private let lastLibraryBookmarkKey = "lastLibraryBookmark"
    private let defaultLibraryPath = "/Users/zhengshihong/Downloads/通用资源/素材库"
    private let videoExtensions = LibraryStore.supportedVideoExtensions
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

    nonisolated private struct ITunesSearchResponse: Decodable, Sendable {
        var results: [ITunesSongResult]
    }

    nonisolated private struct ITunesSongResult: Decodable, Sendable {
        var kind: String?
        var artistName: String?
        var primaryGenreName: String?
    }

    nonisolated private struct AppleMusicSearchResponse: Decodable, Sendable {
        var results: [AppleMusicSearchResult]
    }

    private struct TranscriptSceneBlock: Sendable {
        var index: Int
        var start: Double
        var end: Double
        var subtitles: [TranscriptSegment]
    }

    private enum LocalWaveformRequest: Hashable, Sendable {
        case music(String)
        case audio(String)

        var path: String {
            switch self {
            case .music(let path), .audio(let path):
                return path
            }
        }

        var sampleCount: Int {
            switch self {
            case .music:
                return LibraryStore.localMusicWaveformSampleCount
            case .audio:
                return LibraryStore.localAudioWaveformSampleCount
            }
        }
    }

    private var thumbnailWorkerTasks: [Task<Void, Never>] = []
    private var thumbnailLoadingPaths = Set<String>()
    private var thumbnailLoadGeneration = 0
    private var allTagsCache: [String] = []
    private var videoSourcePlatformCache: [String: String?] = [:]
    private var videoSourceTitleCache: [String: String?] = [:]
    private var waveformTasks: [String: Task<Void, Never>] = [:]
    private var audioClipWaveformTasks: [UUID: Task<Void, Never>] = [:]
    private var localWaveformTasks: [LocalWaveformRequest: Task<Void, Never>] = [:]
    private var pendingLocalWaveformRequests: [LocalWaveformRequest] = []
    private var pendingLocalWaveformRequestSet = Set<LocalWaveformRequest>()
    private var frameStripTasks: [String: Task<Void, Never>] = [:]
    private var sceneDetectionTasks: [String: Task<Void, Never>] = [:]
    private var sceneThumbnailHydrationTasks: [String: Task<Void, Never>] = [:]
    private var sceneThumbnailHydrationNeeded = Set<String>()
    private var transcriptBatchTask: Task<Void, Never>?
    private var isTranscriptBatchPaused = false
    private var sceneBatchTask: Task<Void, Never>?
    private var isSceneBatchPaused = false
    private var musicBatchTask: Task<Void, Never>?
    private var isMusicBatchPaused = false
    private var musicDetectionTasks: [String: Task<Void, Never>] = [:]
    private var localMusicRecognitionTask: Task<Void, Never>?
    private var musicDownloadBatchTask: Task<Void, Never>?
    private var musicDownloadTasks: [UUID: Task<Void, Never>] = [:]
    private var musicTagEnrichmentTasks: [String: Task<Void, Never>] = [:]
    private var downloaderSelfCheckTask: Task<Void, Never>?
    private var lastExternalSelfCheckPreflightAt: Date?
    private var resourceLibraryScanTask: Task<Void, Never>?
    private var resourceLibraryScanTaskLibraryPath: String?
    private var resourceLibraryScanGeneration = 0
    private var lastResourceLibraryFullScanAtByPath: [String: Date] = [:]
    private var knownLocalResourcePaths = Set<String>()
    private var pendingVideoPathRemap: [String: String] = [:]
    private var pendingVideoFolderTagsByPath: [String: [String]] = [:]
    private var remoteImportTasks: [UUID: Task<Void, Never>] = [:]
    private var remoteImportProcesses: [UUID: Process] = [:]
    private var scopedLibraryURL: URL?
    private var sceneCutCache: [String: SceneCutCacheEntry] = [:]
    private(set) var filteredVideos: [VideoItem] = []
    private var collectedFramesCache: [SampledFrame] = []
    private var sampledFramesByVideoPath: [String: [SampledFrame]] = [:]
    private var sampledFrameByID: [UUID: SampledFrame] = [:]
    private var frameTagsCache: [String] = []
    private var sampledFrameThumbnailImageByID: [UUID: NSImage] = [:]
    private var annotationsByVideoPath: [String: [AnnotationItem]] = [:]
    private var audioClipsByVideoPath: [String: [AudioClipItem]] = [:]
    private var audioTagsCache: [String] = []
    private var musicTagsCache: [String] = []
    private var projectSaveTask: Task<Void, Never>?
    private var projectSaveSequence = 0
    private var projectLoadTask: Task<Void, Never>?
    private var projectLoadGeneration = 0
    private var projectDataLoadState: ProjectDataLoadState = .idle
    private var projectDataDirty = false
    private var startupAutomationLibraryPath: String?
    private var metadataRefreshTask: Task<Void, Never>?

    nonisolated private static let transNetPythonPath = "/Users/zhengshihong/Downloads/Newtybei知识库/进行项目/拉片宝/LapianBao/Tools/transnet-env/bin/python"
    nonisolated private static let transNetScriptPath = "/Users/zhengshihong/Downloads/Newtybei知识库/进行项目/拉片宝/LapianBao/Tools/detect_scene_cuts_transnet.py"
    nonisolated private static let sceneDetectorVersion = "transnetv2+hardcut-rescue@2026-05-25.1"
    nonisolated private static let waveformSampleCount = 4096
    nonisolated private static let audioClipWaveformSampleCount = 96
    nonisolated private static let audioClipWaveformVersion = AudioClipItem.currentWaveformVersion
    nonisolated private static let musicWaveformSampleCount = 180
    nonisolated private static let localMusicWaveformSampleCount = 144
    nonisolated private static let localAudioWaveformSampleCount = 96
    nonisolated private static let localWaveformWorkerCount = 1
    nonisolated private static let launchMetadataPrefetchLimit = 12
    nonisolated private static let launchMetadataWorkerCount = 2
    nonisolated private static let launchBackgroundMetadataPrefetchDelay: TimeInterval = 4.0
    nonisolated private static let launchVideoReconcileDelay: TimeInterval = 3.0
    nonisolated private static let videoLibraryCacheVersion = 1
    nonisolated private static let cachedResourceLibraryFullScanDelay: TimeInterval = 8.0
    nonisolated private static let uncachedResourceLibraryFullScanDelay: TimeInterval = 1.2
    nonisolated private static let resourceLibraryFullScanCooldown: TimeInterval = 45.0
    nonisolated private static let placeholderRemoteImportURL = URL(fileURLWithPath: "/invalid-remote-import-url")
    nonisolated private static let tinyGeneratedAudioClipByteLimit: Int64 = 64 * 1024
    nonisolated private static let supportedVideoExtensions = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]
    nonisolated private static let supportedAudioExtensions = ["m4a", "mp3", "wav", "aac", "aif", "aiff", "flac", "opus", "ogg", "caf", "webm"]
    nonisolated private static let supportedImageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tiff", "tif"]

    nonisolated private static let musicPythonPath = "/Users/zhengshihong/Downloads/Newtybei知识库/进行项目/拉片宝/LapianBao/Tools/music-env/bin/python3"
    nonisolated private static let musicScriptPath = "/Users/zhengshihong/Downloads/Newtybei知识库/进行项目/拉片宝/LapianBao/Tools/detect_music.py"
    nonisolated private static let exportRootFolderName = "LapianBaoExports"
    nonisolated private static let videoFolderName = "视频"
    nonisolated private static let imageExportFolderName = "图片"
    nonisolated private static let soundEffectExportFolderName = "音频"
    nonisolated private static let legacySoundEffectExportFolderName = "音效"
    nonisolated private static let transcriptExportFolderName = "字幕"
    nonisolated private static let musicExportFolderName = "音乐"
    nonisolated private static let knownSourcePlatforms = ["Instagram", "YouTube", "小红书", "Bilibili", "抖音"]
    nonisolated static let autoSceneBatchKey = "autoStartSceneBatch"
    nonisolated static let autoTranscriptBatchKey = "autoStartTranscriptBatch"
    nonisolated static let autoMusicDownloadBatchKey = "autoStartMusicDownloadBatch"
    nonisolated private static let instagramImportEndpointDefaultsKey = "instagramImportEndpoint"
    nonisolated private static let downloaderSelfCheckReportKey = "downloaderSelfCheckReport"
    nonisolated private static let downloaderSelfCheckProbeURL = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
    nonisolated private static let downloaderNightlyMacOSURL = "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_macos"
    nonisolated private static let externalSelfCheckPreflightCooldown: TimeInterval = 60 * 60
    nonisolated private static let instagramSavedCollectionURLString = "https://www.instagram.com/newtybeibei/saved/all-posts/"
    nonisolated private static let xiaohongshuSavedCollectionURLString = "https://www.xiaohongshu.com/user/profile/5eb7bea7000000000100540d?tab=fav&subTab=note"

    nonisolated private static func normalizedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }

    nonisolated private static func exportFolder(in libraryURL: URL, named folderName: String) -> URL {
        libraryURL
            .appendingPathComponent(exportRootFolderName, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    nonisolated private static func mediaFolder(in libraryURL: URL, named folderName: String) -> URL {
        libraryURL.appendingPathComponent(folderName, isDirectory: true)
    }

    nonisolated private static func ensureMediaFolders(in libraryURL: URL) {
        for folderName in [videoFolderName, musicExportFolderName, soundEffectExportFolderName, imageExportFolderName] {
            try? FileManager.default.createDirectory(
                at: mediaFolder(in: libraryURL, named: folderName),
                withIntermediateDirectories: true
            )
        }
    }

    nonisolated private static func ensureExportFolders(in libraryURL: URL) {
        for folderName in [imageExportFolderName, soundEffectExportFolderName, transcriptExportFolderName, musicExportFolderName] {
            try? FileManager.default.createDirectory(
                at: exportFolder(in: libraryURL, named: folderName),
                withIntermediateDirectories: true
            )
        }
    }

    nonisolated private static func localToolURL(
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

    private func rebuildAllTagsCache() {
        allTagsCache = Array(Set(tagsByVideoPath.values.flatMap { $0 })).sorted()
    }

    private func clearVideoSourceCaches() {
        videoSourcePlatformCache.removeAll()
        videoSourceTitleCache.removeAll()
    }

    private func rebuildSampledFrameIndexes() {
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

    private func rebuildAnnotationIndexes() {
        annotationsByVideoPath = Dictionary(grouping: annotations, by: \.videoPath).mapValues {
            $0.sorted { lhs, rhs in
                if abs(lhs.time - rhs.time) > 0.001 { return lhs.time < rhs.time }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    private func rebuildAudioClipIndexes() {
        audioClipsByVideoPath = Dictionary(grouping: audioClips, by: \.videoPath).mapValues {
            $0.sorted { lhs, rhs in
                if abs(lhs.inTime - rhs.inTime) > 0.001 { return lhs.inTime < rhs.inTime }
                return lhs.createdAt < rhs.createdAt
            }
        }
        audioTagsCache = Array(Set(audioClips.flatMap(\.tags) + localAudioAssets.flatMap(\.tags))).sorted()
    }

    private func rebuildMusicIndexes() {
        let recognizedTags = musicsByVideoPath.values.flatMap { songs in
            songs.flatMap(\.displayTags)
        }
        musicTagsCache = Array(Set(recognizedTags + localMusicAssets.flatMap(\.tags))).sorted()
    }

    private func refreshFilteredVideos() {
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

    private func scheduleMetadataDependentRefresh() {
        metadataRefreshTask?.cancel()
        metadataRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            objectWillChange.send()
            refreshFilteredVideos()
            metadataRefreshTask = nil
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

    private func localResourceFileExists(at path: String) -> Bool {
        if knownLocalResourcePaths.contains(path) {
            return true
        }
        return FileManager.default.fileExists(atPath: path)
    }

    func scanResourceLibrary(forceFullScan: Bool = false) {
        guard let libraryURL else { return }
        let libraryPath = libraryURL.path
        var hasCachedSnapshot = false
        if let cachedSnapshot = Self.loadCachedResourceLibrarySnapshot(in: libraryURL) {
            hasCachedSnapshot = true
            applyResourceLibrarySnapshot(cachedSnapshot, libraryPath: libraryPath)
        } else {
            Task.detached(priority: .userInitiated) { [weak self, libraryURL, libraryPath] in
                let snapshot = Self.quickResourceLibrarySnapshot(in: libraryURL)
                await MainActor.run { [weak self] in
                    self?.applyResourceLibrarySnapshot(snapshot, libraryPath: libraryPath)
                }
            }
        }

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
        let delay = forceFullScan
            ? 0
            : (hasCachedSnapshot ? Self.cachedResourceLibraryFullScanDelay : Self.uncachedResourceLibraryFullScanDelay)
        resourceLibraryScanTask = Task { [weak self, libraryURL, libraryPath, delay, scanGeneration] in
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

    private func applyResourceLibrarySnapshot(_ snapshot: ResourceLibrarySnapshot, libraryPath: String) {
        guard libraryURL?.path == libraryPath else { return }
        let musicPaths = Set(snapshot.music.map(\.filePath))
        let audioPaths = Set(snapshot.audio.map(\.filePath))
        knownLocalResourcePaths = musicPaths.union(audioPaths)

        let musicChanged = localMusicAssets != snapshot.music
        let audioChanged = localAudioAssets != snapshot.audio
        if musicChanged {
            localMusicAssets = snapshot.music
        }
        if audioChanged {
            localAudioAssets = snapshot.audio
        }

        guard musicChanged || audioChanged else { return }

        pruneLocalWaveformCaches(musicPaths: musicPaths, audioPaths: audioPaths)
        cleanupInvalidGeneratedAudioClipRecords()
        reconcileMusicDownloadJobsWithLocalAssets(snapshot.music)
    }

    private func pruneLocalWaveformCaches(musicPaths: Set<String>, audioPaths: Set<String>) {
        localMusicWaveformSamplesByPath = localMusicWaveformSamplesByPath.filter { musicPaths.contains($0.key) }
        localAudioWaveformSamplesByPath = localAudioWaveformSamplesByPath.filter { audioPaths.contains($0.key) }

        pendingLocalWaveformRequests.removeAll { request in
            let shouldRemove = !isLocalWaveformRequestValid(request, musicPaths: musicPaths, audioPaths: audioPaths)
            if shouldRemove {
                pendingLocalWaveformRequestSet.remove(request)
            }
            return shouldRemove
        }

        let invalidActiveRequests = localWaveformTasks.keys.filter {
            !isLocalWaveformRequestValid($0, musicPaths: musicPaths, audioPaths: audioPaths)
        }
        for request in invalidActiveRequests {
            localWaveformTasks[request]?.cancel()
            localWaveformTasks[request] = nil
        }

        startQueuedLocalWaveforms()
    }

    private func isLocalWaveformRequestValid(
        _ request: LocalWaveformRequest,
        musicPaths: Set<String>,
        audioPaths: Set<String>
    ) -> Bool {
        switch request {
        case .music(let path):
            return musicPaths.contains(path)
        case .audio(let path):
            return audioPaths.contains(path)
        }
    }

    private func cleanupInvalidGeneratedAudioClipRecords() {
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

    private func reconcileMusicDownloadJobsWithLocalAssets(_ assets: [LocalMusicAsset]) {
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

    private func startExternalServiceSelfCheckPreflightIfNeeded() {
        guard downloaderSelfCheckTask == nil else { return }
        if let lastExternalSelfCheckPreflightAt,
           Date().timeIntervalSince(lastExternalSelfCheckPreflightAt) < Self.externalSelfCheckPreflightCooldown {
            return
        }
        guard !Self.isDownloaderSelfCheckFresh(downloaderSelfCheckReport) else { return }
        lastExternalSelfCheckPreflightAt = Date()
        startExternalServiceSelfCheck(force: false)
    }

    private func updateDownloaderSelfCheckReport(_ report: DownloaderSelfCheckReport) {
        downloaderSelfCheckReport = report
        Self.saveDownloaderSelfCheckReport(report)
    }

    func loadLastLibrary() {
        guard libraryURL == nil else { return }
        guard let url = lastLibraryURLForLoading() else { return }
        scanVideos(in: url)
    }

    func loadLastLibraryForLaunch() {
        guard libraryURL == nil else { return }
        guard let url = lastLibraryURLForLoading() else { return }

        if let cached = Self.loadCachedVideoOrganization(in: url) {
            applyScannedVideos(
                in: url,
                urls: cached.urls,
                deferProjectDataLoad: true,
                projectDataLoadDelay: 0,
                metadataPrefetchLimit: Self.launchMetadataPrefetchLimit,
                metadataWorkerCount: Self.launchMetadataWorkerCount,
                metadataBackgroundPrefetchDelay: Self.launchBackgroundMetadataPrefetchDelay,
                videoPathRemap: cached.pathRemap,
                videoFolderTagsByPath: cached.folderTagsByPath
            )
            reconcileVideoLibraryAfterLaunch(in: url, after: Self.launchVideoReconcileDelay)
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            let quickSnapshot = Self.quickVideoOrganizationSnapshot(in: url)
            await MainActor.run { [weak self] in
                guard let store = self, store.libraryURL == nil else { return }
                store.applyScannedVideos(
                    in: url,
                    urls: quickSnapshot.urls,
                    deferProjectDataLoad: true,
                    projectDataLoadDelay: 0,
                    metadataPrefetchLimit: Self.launchMetadataPrefetchLimit,
                    metadataWorkerCount: Self.launchMetadataWorkerCount,
                    metadataBackgroundPrefetchDelay: Self.launchBackgroundMetadataPrefetchDelay,
                    videoPathRemap: quickSnapshot.pathRemap,
                    videoFolderTagsByPath: quickSnapshot.folderTagsByPath
                )
            }

            try? await Task.sleep(nanoseconds: UInt64(Self.launchVideoReconcileDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let organized = Self.organizeVideoFiles(in: url)
            await MainActor.run { [weak self] in
                guard let store = self,
                      store.libraryURL?.path == url.path
                else { return }
                let selectedPath = store.selectedVideo?.url.path
                let selectedTags = store.selectedTags
                store.applyScannedVideos(
                    in: url,
                    urls: organized.urls,
                    deferProjectDataLoad: true,
                    projectDataLoadDelay: 0,
                    selectFirstVideo: selectedPath == nil,
                    metadataPrefetchLimit: Self.launchMetadataPrefetchLimit,
                    metadataWorkerCount: Self.launchMetadataWorkerCount,
                    metadataBackgroundPrefetchDelay: Self.launchBackgroundMetadataPrefetchDelay,
                    videoPathRemap: organized.pathRemap,
                    videoFolderTagsByPath: organized.folderTagsByPath,
                    preservedSelectionPath: selectedPath,
                    preservedSelectedTags: selectedTags
                )
            }
        }
    }

    private func reconcileVideoLibraryAfterLaunch(in url: URL, after delay: TimeInterval) {
        Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let organized = Self.organizeVideoFiles(in: url)
            await MainActor.run { [weak self] in
                guard let store = self,
                      store.libraryURL?.path == url.path
                else { return }
                let selectedPath = store.selectedVideo?.url.path
                let selectedTags = store.selectedTags
                store.applyScannedVideos(
                    in: url,
                    urls: organized.urls,
                    deferProjectDataLoad: true,
                    projectDataLoadDelay: 0,
                    selectFirstVideo: selectedPath == nil,
                    metadataPrefetchLimit: Self.launchMetadataPrefetchLimit,
                    metadataWorkerCount: Self.launchMetadataWorkerCount,
                    metadataBackgroundPrefetchDelay: Self.launchBackgroundMetadataPrefetchDelay,
                    videoPathRemap: organized.pathRemap,
                    videoFolderTagsByPath: organized.folderTagsByPath,
                    preservedSelectionPath: selectedPath,
                    preservedSelectedTags: selectedTags
                )
            }
        }
    }

    private func lastLibraryURLForLoading() -> URL? {
        if let bookmarkedURL = restoreLastLibraryBookmark() {
            return bookmarkedURL
        }

        if
            let path = UserDefaults.standard.string(forKey: lastLibraryPathKey),
            FileManager.default.fileExists(atPath: path)
        {
            return URL(fileURLWithPath: path)
        }

        if let defaultURL = defaultLibraryURL() {
            UserDefaults.standard.set(defaultURL.path, forKey: lastLibraryPathKey)
            return defaultURL
        }

        return nil
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
        UserDefaults.standard.set(instagramImportEndpoint, forKey: Self.instagramImportEndpointDefaultsKey)
    }

    func importRemoteVideo(from rawURL: String) {
        importRemoteVideos(from: rawURL)
    }

    func clearFinishedRemoteImports() {
        remoteImportJobs.removeAll { job in
            switch job.status {
            case .succeeded, .failed:
                return true
            default:
                return false
            }
        }
    }

    func pauseRemoteImportJob(id: UUID) {
        remoteImportTasks[id]?.cancel()
        remoteImportTasks[id] = nil
        remoteImportProcesses[id]?.terminate()
        remoteImportProcesses[id] = nil
        updateRemoteImportJob(id: id) { job in
            job.status = .paused
            job.downloadSpeed = nil
        }
    }

    func resumeRemoteImportJob(id: UUID) {
        guard let job = remoteImportJobs.first(where: { $0.id == id }) else { return }
        remoteImportJobs.removeAll { $0.id == id }
        enqueueRemoteImport(from: job.sourceURL.absoluteString, initialThumbnailData: job.thumbnailData)
    }

    func deleteRemoteImportJob(id: UUID) {
        remoteImportTasks[id]?.cancel()
        remoteImportTasks[id] = nil
        remoteImportProcesses[id]?.terminate()
        remoteImportProcesses[id] = nil

        if let job = remoteImportJobs.first(where: { $0.id == id }),
           let outputPath = job.outputPath,
           let video = selectedVideo(for: outputPath) {
            removeVideo(video)
        }
        remoteImportJobs.removeAll { $0.id == id }
    }

    func jumpToRemoteImportJob(id: UUID) {
        guard
            let job = remoteImportJobs.first(where: { $0.id == id }),
            let outputPath = job.outputPath
        else { return }
        selectVideo(path: outputPath, autoplay: false)
    }

    func importRemoteVideos(from rawText: String) {
        let inputs = Self.remoteImportURLs(from: rawText)
        guard !inputs.isEmpty else {
            remoteImportJobs.append(RemoteImportJob(
                sourceURL: Self.placeholderRemoteImportURL,
                platform: "未知平台",
                status: .failed("请输入至少一个有效链接")
            ))
            return
        }

        for rawURL in inputs {
            enqueueRemoteImport(from: rawURL)
        }
    }

    func importLatestInstagramSavedFromChrome(limit: Int = 10) async throws -> InstagramSavedImportResult {
        guard libraryURL != nil else {
            throw InstagramSavedImportError.noLibrary
        }
        startExternalServiceSelfCheckPreflightIfNeeded()

        let discoveredLinks = try await Self.fetchLatestInstagramSavedLinksFromChrome(limit: limit)
        let alreadyQueuedOrImported = queuedOrImportedInstagramSourceURLs()
        let linksToImport = discoveredLinks.filter { !alreadyQueuedOrImported.contains($0) }

        for link in linksToImport {
            enqueueRemoteImport(from: link)
        }

        return InstagramSavedImportResult(
            foundCount: discoveredLinks.count,
            skippedCount: discoveredLinks.count - linksToImport.count,
            queuedCount: linksToImport.count,
            queuedLinks: linksToImport
        )
    }

    func importLatestXiaohongshuSavedVideosFromChrome(limit: Int = 10) async throws -> InstagramSavedImportResult {
        guard libraryURL != nil else {
            throw InstagramSavedImportError.noLibrary
        }
        startExternalServiceSelfCheckPreflightIfNeeded()

        let discoveredLinks = try await Self.fetchLatestXiaohongshuSavedVideoLinksFromChrome(limit: limit)
        let alreadyQueuedOrImported = queuedOrImportedXiaohongshuSourceURLs()
        let linksToImport = discoveredLinks.filter { !alreadyQueuedOrImported.contains($0) }

        for link in linksToImport {
            enqueueRemoteImport(from: link)
        }

        return InstagramSavedImportResult(
            foundCount: discoveredLinks.count,
            skippedCount: discoveredLinks.count - linksToImport.count,
            queuedCount: linksToImport.count,
            queuedLinks: linksToImport
        )
    }

    private func queuedOrImportedInstagramSourceURLs() -> Set<String> {
        var urls = Set<String>()

        for info in sourceInfoByVideoPath.values {
            if let sourceURL = info.sourceURL,
               let normalized = Self.normalizedInstagramContentURL(sourceURL) {
                urls.insert(normalized)
            }
        }

        for job in remoteImportJobs where Self.remoteImportJobCountsAsQueuedOrImported(job.status) {
            if let normalized = Self.normalizedInstagramContentURL(job.sourceURL.absoluteString) {
                urls.insert(normalized)
            }
        }

        return urls
    }

    private func queuedOrImportedXiaohongshuSourceURLs() -> Set<String> {
        var urls = Set<String>()

        for info in sourceInfoByVideoPath.values {
            if let sourceURL = info.sourceURL,
               let normalized = Self.normalizedXiaohongshuNoteURL(sourceURL) {
                urls.insert(normalized)
            }
        }

        for job in remoteImportJobs where Self.remoteImportJobCountsAsQueuedOrImported(job.status) {
            if let normalized = Self.normalizedXiaohongshuNoteURL(job.sourceURL.absoluteString) {
                urls.insert(normalized)
            }
        }

        return urls
    }

    private func enqueueRemoteImport(from rawURL: String, initialThumbnailData: Data? = nil) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sourceURL = URL(string: trimmed) else {
            remoteImportJobs.append(RemoteImportJob(
                sourceURL: Self.placeholderRemoteImportURL,
                platform: "未知平台",
                status: .failed("请输入有效链接")
            ))
            return
        }

        guard let platform = Self.platformName(for: sourceURL) else {
            remoteImportJobs.append(RemoteImportJob(
                sourceURL: sourceURL,
                platform: "未知平台",
                status: .failed("暂不支持该平台，目前支持 Instagram、YouTube、小红书、Bilibili 和抖音")
            ))
            return
        }

        guard let libraryURL else {
            remoteImportJobs.append(RemoteImportJob(
                sourceURL: sourceURL,
                platform: platform,
                status: .failed("请先打开一个素材库文件夹")
            ))
            return
        }

        let endpoint = instagramImportEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let job = RemoteImportJob(
            sourceURL: sourceURL,
            platform: platform,
            status: .importing,
            thumbnailData: initialThumbnailData
        )
        remoteImportJobs.append(job)
        let jobID = job.id

        if initialThumbnailData == nil {
            loadRemoteImportThumbnail(for: jobID, sourceURL: sourceURL)
        }

        // 进度回调：yt-dlp 每行输出一次，跳回主线程更新 UI
        let progressCallback: @Sendable (Double?, String?) -> Void = { [weak self] progress, speed in
            Task { @MainActor [weak self] in
                self?.updateRemoteImportJob(id: jobID) { job in
                    guard case .importing = job.status else { return }
                    job.downloadProgress = progress.map(Self.normalizedProgress)
                    if progress == nil {
                        job.downloadSpeed = nil
                    } else if let speed, !speed.isEmpty {
                        job.downloadSpeed = speed
                    }
                }
            }
        }
        // 转码回调：下载结束、VP9→H.264 转码即将开始时触发
        let transcodingCallback: @Sendable (Double?) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.updateRemoteImportJob(id: jobID) { job in
                    job.status = .transcoding
                    job.downloadProgress = progress.map(Self.normalizedProgress)
                    job.downloadSpeed = nil
                }
            }
        }
        let finalizingCallback: @Sendable (Double) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateRemoteImportJob(id: jobID) { job in
                    job.status = .finalizing
                    job.downloadProgress = nil
                    job.downloadSpeed = nil
                }
            }
        }
        let processCallback: @Sendable (Process?) -> Void = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.remoteImportProcesses[jobID] = process
            }
        }

        let task = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.remoteImportTasks[jobID] = nil
                    self?.remoteImportProcesses[jobID] = nil
                }
            }
            do {
                await MainActor.run { [weak self] in
                    self?.startExternalServiceSelfCheckPreflightIfNeeded()
                }
                let downloadedVideo = try await Self.downloadVideo(
                    from: sourceURL,
                    into: libraryURL,
                    platform: platform,
                    endpoint: endpoint,
                    progressCallback: progressCallback,
                    transcodingCallback: transcodingCallback,
                    finalizingCallback: finalizingCallback,
                    processCallback: processCallback
                )
                let outputURL = downloadedVideo.url

                guard !Task.isCancelled else { return }
                self?.updateRemoteImportJob(id: jobID) { job in
                    job.status = .succeeded(outputURL.lastPathComponent)
                    job.downloadProgress = 1
                    job.downloadSpeed = nil
                    job.outputPath = outputURL.path
                }
                self?.recordImportedVideoSource(
                    videoURL: outputURL,
                    sourceURL: sourceURL,
                    platform: platform,
                    authorName: downloadedVideo.authorName,
                    sourceTitle: downloadedVideo.sourceTitle
                )
                self?.scanVideos(in: libraryURL)
                if let importedVideo = self?.videos.first(where: { $0.url.path == outputURL.path }) {
                    self?.addImportTags(to: importedVideo, platform: platform, authorName: downloadedVideo.authorName)
                    self?.selectVideo(importedVideo, autoplay: false)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.updateRemoteImportJob(id: jobID) { job in
                    job.status = .failed(error.localizedDescription)
                    job.downloadProgress = nil
                    job.downloadSpeed = nil
                }
            }
        }
        remoteImportTasks[jobID] = task
    }

    private func updateRemoteImportJob(id: UUID, mutate: (inout RemoteImportJob) -> Void) {
        guard let index = remoteImportJobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&remoteImportJobs[index])
    }

    private func addImportTags(to video: VideoItem, platform: String, authorName: String?) {
        addImportTags(toPath: video.url.path, platform: platform, authorName: authorName)
    }

    private func addImportTags(toPath path: String, platform: String?, authorName: String?) {
        var tags = tagsByVideoPath[path, default: []]
        let candidates = [platform, authorName]
            .compactMap { $0 }
            .compactMap(Self.normalizedImportTag)

        for tag in candidates where !tags.contains(tag) {
            tags.append(tag)
        }
        tagsByVideoPath[path] = tags.sorted()
        saveTagsJSON()
    }

    private func recordImportedVideoSource(
        videoURL: URL,
        sourceURL: URL,
        platform: String,
        authorName: String?,
        sourceTitle: String?
    ) {
        let normalizedPlatform = Self.normalizedImportTag(platform) ?? platform
        let normalizedAuthor = authorName.flatMap(Self.normalizedImportTag)
        let normalizedTitle = sourceTitle.flatMap(Self.normalizedSourceTitle)
        sourceInfoByVideoPath[videoURL.path] = VideoSourceInfo(
            platform: normalizedPlatform,
            sourceURL: sourceURL.absoluteString,
            authorName: normalizedAuthor,
            title: normalizedTitle
        )
        saveSourceInfoJSON()
        addImportTags(toPath: videoURL.path, platform: normalizedPlatform, authorName: normalizedAuthor)
    }

    nonisolated private static func normalizedImportTag(_ rawValue: String) -> String? {
        let tag = stripTrailingSourceID(normalizedSpaces(rawValue))
            .trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        guard !tag.isEmpty, tag.count <= 64 else { return nil }
        guard URL(string: tag)?.scheme == nil else { return nil }
        return tag
    }

    private func loadRemoteImportThumbnail(for jobID: UUID, sourceURL: URL) {
        Task { [weak self] in
            guard
                let thumbnailData = await Self.remoteThumbnailData(for: sourceURL),
                !Task.isCancelled
            else { return }

            await MainActor.run { [weak self] in
                self?.updateRemoteImportJob(id: jobID) { job in
                    job.thumbnailData = thumbnailData
                }
            }
        }
    }

    nonisolated private static func remoteImportURLs(from text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，"))
        var seen = Set<String>()
        return text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
            .filter { seen.insert($0).inserted }
    }

    nonisolated private static func normalizedInstagramContentURL(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let content = instagramContentParts(from: url)
        else { return nil }

        let baseURLString = "https://www.instagram.com/\(content.type)/\(content.shortcode)/"
        if content.type == "p",
           let itemIndex = instagramCarouselItemIndex(from: url),
           itemIndex > 1 {
            return "\(baseURLString)?img_index=\(itemIndex)"
        }
        return baseURLString
    }

    nonisolated private static func instagramContentParts(from url: URL) -> (type: String, shortcode: String)? {
        guard
            let host = url.host?.lowercased(),
            host == "instagram.com" || host.hasSuffix(".instagram.com") || host == "instagr.am" || host.hasSuffix(".instagr.am")
        else { return nil }

        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }

        var contentType = parts[0].lowercased()
        if contentType == "reels" {
            contentType = "reel"
        }
        guard contentType == "reel" || contentType == "p" else { return nil }

        let shortcode = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shortcode.isEmpty else { return nil }
        return (contentType, shortcode)
    }

    nonisolated private static func instagramBaseContentURL(from url: URL) -> URL? {
        guard let content = instagramContentParts(from: url) else { return nil }
        return URL(string: "https://www.instagram.com/\(content.type)/\(content.shortcode)/")
    }

    nonisolated private static func instagramCarouselItemURLString(baseURL: URL, itemIndex: Int) -> String {
        guard itemIndex > 1 else {
            return instagramBaseContentURL(from: baseURL)?.absoluteString ?? baseURL.absoluteString
        }
        let baseURLString = instagramBaseContentURL(from: baseURL)?.absoluteString ?? baseURL.absoluteString
        return "\(baseURLString)?img_index=\(itemIndex)"
    }

    nonisolated private static func instagramCarouselItemIndex(from url: URL) -> Int? {
        guard let content = instagramContentParts(from: url),
              content.type == "p",
              let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }

        for item in queryItems where item.name == "img_index" || item.name == "lapianbao_item" {
            if let rawValue = item.value,
               let value = Int(rawValue),
               value > 0 {
                return value
            }
        }
        return nil
    }

    nonisolated private static func ytdlpSourceURL(for sourceURL: URL) -> URL {
        instagramCarouselItemIndex(from: sourceURL) == nil
            ? sourceURL
            : (instagramBaseContentURL(from: sourceURL) ?? sourceURL)
    }

    nonisolated private static func ytdlpPlaylistSelectionArguments(for sourceURL: URL) -> [String] {
        guard let itemIndex = instagramCarouselItemIndex(from: sourceURL) else {
            return ["--no-playlist"]
        }
        return ["--yes-playlist", "--playlist-items", "\(itemIndex)"]
    }

    nonisolated private static func normalizedXiaohongshuNoteURL(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased()
        else { return nil }

        if host.contains("xhslink.com") {
            return trimmed
        }

        guard host == "xiaohongshu.com" || host.hasSuffix(".xiaohongshu.com") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let noteID: String?
        if parts.count >= 2, parts[0] == "explore" || parts[0] == "search_result" {
            noteID = parts[1]
        } else if parts.count >= 3, parts[0] == "discovery", parts[1] == "item" {
            noteID = parts[2]
        } else {
            noteID = nil
        }

        guard let noteID,
              !noteID.isEmpty,
              noteID != "undefined",
              noteID != "null"
        else { return nil }

        return "https://www.xiaohongshu.com/explore/\(noteID)"
    }

    nonisolated private static func remoteImportJobCountsAsQueuedOrImported(_ status: RemoteImportJob.Status) -> Bool {
        switch status {
        case .importing, .transcoding, .finalizing, .paused, .succeeded:
            return true
        case .idle, .failed:
            return false
        }
    }

    nonisolated private struct CurlFetchResult: Sendable {
        var statusCode: Int
        var data: Data
    }

    nonisolated private struct InstagramSavedFeedResponse: Decodable {
        var items: [InstagramSavedFeedItem]
    }

    nonisolated private struct InstagramSavedFeedItem: Decodable {
        var media: InstagramSavedMedia?
        var item: InstagramSavedMedia?
        var carouselMedia: [InstagramSavedMedia]?

        var bestMedia: InstagramSavedMedia? {
            media ?? item ?? carouselMedia?.first
        }

        private enum CodingKeys: String, CodingKey {
            case media, item
            case carouselMedia = "carousel_media"
        }
    }

    nonisolated private struct InstagramSavedMedia: Decodable {
        var code: String?
        var mediaType: Int?
        var productType: String?
        var carouselMedia: [InstagramSavedMedia]?
        var videoVersions: [InstagramSavedVideoVersion]?

        var isLikelyVideo: Bool {
            if mediaType == 2 { return true }
            if videoVersions?.isEmpty == false { return true }
            let loweredProductType = productType?.lowercased() ?? ""
            return loweredProductType.contains("clips") || loweredProductType.contains("reel")
        }

        private enum CodingKeys: String, CodingKey {
            case code
            case mediaType = "media_type"
            case productType = "product_type"
            case carouselMedia = "carousel_media"
            case videoVersions = "video_versions"
        }
    }

    nonisolated private struct InstagramSavedVideoVersion: Decodable {
        var url: String?
    }

    nonisolated private static func withExportedChromeCookies<T>(
        seedURLString: String,
        _ body: (URL) throws -> T
    ) throws -> T {
        guard let ytdlp = localYTDLPURL() else {
            throw InstagramSavedImportError.chromeCookieUnavailable("未找到 yt-dlp，无法读取 Chrome Cookie")
        }

        let cookieURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lapianbao-chrome-cookies-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: cookieURL) }

        let exportResult = runDownloaderSelfCheckProcess(
            executableURL: ytdlp,
            arguments: [
                "--cookies-from-browser", "chrome",
                "--cookies", cookieURL.path,
                "--skip-download",
                "--simulate",
                "--no-warnings",
                seedURLString
            ],
            timeout: 28
        )
        guard exportResult.succeeded,
              FileManager.default.fileExists(atPath: cookieURL.path),
              ((try? cookieURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        else {
            throw InstagramSavedImportError.chromeCookieUnavailable(
                selfCheckFailureMessage(from: exportResult, fallback: "无法导出 Chrome Cookie")
            )
        }

        return try body(cookieURL)
    }

    nonisolated private static func runCurlFetch(
        urlString: String,
        cookieFileURL: URL,
        headers: [(String, String)] = [],
        timeout: TimeInterval
    ) throws -> CurlFetchResult {
        guard let curl = localCurlURL() else {
            throw InstagramSavedImportError.chromeCookieUnavailable("未找到 curl，无法读取网页")
        }

        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lapianbao-curl-body-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        let process = Process()
        process.executableURL = curl
        var arguments = [
            "--location",
            "--silent",
            "--show-error",
            "--compressed",
            "--max-time", String(Int(max(1, timeout).rounded(.up))),
            "--cookie", cookieFileURL.path,
            "--output", bodyURL.path,
            "--write-out", "%{http_code}"
        ]
        for (name, value) in headers {
            arguments += ["--header", "\(name): \(value)"]
        }
        arguments.append(urlString)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputCollector = PipeDataCollector()
        let errorCollector = PipeDataCollector()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputCollector.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorCollector.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw InstagramSavedImportError.chromeCookieUnavailable("无法启动 curl：\(error.localizedDescription)")
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout + 2) == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw InstagramSavedImportError.timedOut
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        guard process.terminationStatus == 0 else {
            let errorText = String(data: errorCollector.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw InstagramSavedImportError.chromeCookieUnavailable(errorText.isEmpty ? "curl 请求失败" : errorText)
        }

        let statusText = String(data: outputCollector.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let data = (try? Data(contentsOf: bodyURL)) ?? Data()
        return CurlFetchResult(statusCode: Int(statusText) ?? 0, data: data)
    }

    nonisolated private static func instagramVideoLinks(fromSavedMedia media: InstagramSavedMedia) -> [String] {
        var links: [String] = []

        if let carouselMedia = media.carouselMedia, !carouselMedia.isEmpty {
            for (offset, item) in carouselMedia.enumerated() where item.isLikelyVideo {
                guard let parentCode = media.code ?? item.code else { continue }
                let baseURL = URL(string: "https://www.instagram.com/p/\(parentCode)/")
                if let baseURL {
                    links.append(instagramCarouselItemURLString(baseURL: baseURL, itemIndex: offset + 1))
                }
            }
        }

        if media.isLikelyVideo, let code = media.code {
            let type = media.productType?.lowercased().contains("clips") == true ? "reel" : "p"
            links.append("https://www.instagram.com/\(type)/\(code)/")
        }

        var seen = Set<String>()
        return links.filter { seen.insert($0).inserted }
    }

    nonisolated private static func xiaohongshuVideoLinks(fromSavedHTML html: String, limit: Int) -> [String] {
        let normalizedHTML = html
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
        let nsString = normalizedHTML as NSString
        let patterns = [
            #"(?://www\.xiaohongshu\.com)?/(?:explore|search_result)/([A-Za-z0-9]+)"#,
            #"(?://www\.xiaohongshu\.com)?/discovery/item/([A-Za-z0-9]+)"#
        ]

        var candidates: [(url: String, isVideo: Bool)] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(
                in: normalizedHTML,
                options: [],
                range: NSRange(location: 0, length: nsString.length)
            )
            for match in matches where match.numberOfRanges > 1 {
                let idRange = match.range(at: 1)
                guard idRange.location != NSNotFound else { continue }
                let noteID = nsString.substring(with: idRange)
                guard !noteID.isEmpty,
                      noteID != "undefined",
                      noteID != "null"
                else { continue }
                candidates.append((
                    url: "https://www.xiaohongshu.com/explore/\(noteID)",
                    isVideo: xiaohongshuSnippetLooksLikeVideo(in: nsString, near: match.range.location)
                ))
            }
        }

        var seen = Set<String>()
        let videoLinks = candidates.filter(\.isVideo).map(\.url)
        let fallbackLinks = videoLinks.isEmpty ? candidates.map(\.url) : videoLinks
        return fallbackLinks
            .filter { seen.insert($0).inserted }
            .prefix(max(1, limit))
            .map { $0 }
    }

    nonisolated private static func xiaohongshuSnippetLooksLikeVideo(in html: NSString, near location: Int) -> Bool {
        let start = max(0, location - 2200)
        let end = min(html.length, location + 3600)
        guard end > start else { return false }
        let snippet = html.substring(with: NSRange(location: start, length: end - start)).lowercased()
        return [
            #""type":"video""#,
            #""note_type":"video""#,
            #""notetype":"video""#,
            "video_info",
            "videoinfo",
            "video_url",
            "xgplayer",
            "player-container"
        ].contains { snippet.contains($0) }
    }

    nonisolated private static func fetchLatestInstagramSavedLinksFromChrome(limit: Int) async throws -> [String] {
        let clampedLimit = min(max(limit, 1), 50)
        return try await Task.detached(priority: .userInitiated) {
            try fetchLatestInstagramSavedLinksFromChromeCookies(limit: clampedLimit)
        }.value
    }

    nonisolated private static func fetchLatestInstagramSavedLinksFromChromeCookies(limit: Int) throws -> [String] {
        try withExportedChromeCookies(seedURLString: "https://www.instagram.com/") { cookieURL in
            let result = try runCurlFetch(
                urlString: "https://www.instagram.com/api/v1/feed/saved/?count=\(limit)",
                cookieFileURL: cookieURL,
                headers: [
                    ("accept", "*/*"),
                    ("x-ig-app-id", "936619743392459"),
                    ("x-ig-www-claim", "0"),
                    ("x-requested-with", "XMLHttpRequest"),
                    ("user-agent", "Instagram 333.0.0.42.91 Android")
                ],
                timeout: 24
            )

            guard (200..<300).contains(result.statusCode) else {
                throw InstagramSavedImportError.chromeCookieUnavailable("无法读取 Instagram 收藏接口（HTTP \(result.statusCode)）")
            }

            let response = try JSONDecoder().decode(InstagramSavedFeedResponse.self, from: result.data)
            var seen = Set<String>()
            var links: [String] = []

            for item in response.items.prefix(limit) {
                guard let media = item.bestMedia else { continue }
                for link in instagramVideoLinks(fromSavedMedia: media) {
                    let normalized = normalizedInstagramContentURL(link) ?? link
                    if seen.insert(normalized).inserted {
                        links.append(normalized)
                    }
                }
            }

            guard !links.isEmpty else {
                throw InstagramSavedImportError.noLinks
            }
            return links
        }
    }

    nonisolated private static func expandedInstagramCarouselVideoLinks(_ links: [String]) -> [String] {
        guard let ytdlp = localYTDLPURL() else { return links }

        var seen = Set<String>()
        var expandedLinks: [String] = []
        for link in links {
            let normalizedLink = normalizedInstagramContentURL(link) ?? link
            let replacementLinks: [String]
            if let url = URL(string: normalizedLink),
               let content = instagramContentParts(from: url),
               content.type == "p",
               let videoLinks = instagramPostVideoItemLinks(executableURL: ytdlp, sourceURL: url) {
                replacementLinks = videoLinks
            } else {
                replacementLinks = [normalizedLink]
            }

            for replacementLink in replacementLinks {
                let normalizedReplacement = normalizedInstagramContentURL(replacementLink) ?? replacementLink
                if seen.insert(normalizedReplacement).inserted {
                    expandedLinks.append(normalizedReplacement)
                }
            }
        }
        return expandedLinks
    }

    nonisolated private static func instagramPostVideoItemLinks(executableURL: URL, sourceURL: URL) -> [String]? {
        guard let baseURL = instagramBaseContentURL(from: sourceURL) else { return nil }

        var info: YTDLPVideoInfo?
        for attempt in ytdlpArgumentAttempts(for: baseURL) {
            info = fetchYTDLPInstagramPlaylistInfo(
                executableURL: executableURL,
                sourceURL: baseURL,
                extraArguments: attempt.arguments
            )
            if info?.entries?.isEmpty == false {
                break
            }
        }

        guard let info else { return nil }

        if let entries = info.entries,
           !entries.isEmpty {
            return entries.enumerated().compactMap { offset, entry -> String? in
                guard entry.isLikelyVideo else { return nil }
                let itemIndex = entry.playlistIndex ?? offset + 1
                return instagramCarouselItemURLString(baseURL: baseURL, itemIndex: itemIndex)
            }
        }

        return info.isLikelyVideo ? [baseURL.absoluteString] : []
    }

    nonisolated private static func fetchYTDLPInstagramPlaylistInfo(
        executableURL: URL,
        sourceURL: URL,
        extraArguments: [String] = []
    ) -> YTDLPVideoInfo? {
        let process = Process()
        process.executableURL = executableURL
        process.environment = downloaderProcessEnvironment()
        process.arguments = [
            "--yes-playlist",
            "--skip-download",
            "--dump-single-json",
            "--no-warnings",
            "--user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        ] + ytdlpProbeNetworkArguments(isYouTube: false) + extraArguments + [
            sourceURL.absoluteString
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputCollector = PipeDataCollector()
        let errorCollector = PipeDataCollector()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputCollector.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorCollector.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 18) == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        guard process.terminationStatus == 0 else { return nil }
        return try? JSONDecoder().decode(YTDLPVideoInfo.self, from: outputCollector.data)
    }

    nonisolated private static func fetchLatestXiaohongshuSavedVideoLinksFromChrome(limit: Int) async throws -> [String] {
        let clampedLimit = min(max(limit, 1), 50)
        return try await Task.detached(priority: .userInitiated) {
            try fetchLatestXiaohongshuSavedVideoLinksFromChromeCookies(limit: clampedLimit)
        }.value
    }

    nonisolated private static func fetchLatestXiaohongshuSavedVideoLinksFromChromeCookies(limit: Int) throws -> [String] {
        try withExportedChromeCookies(seedURLString: "https://www.xiaohongshu.com/") { cookieURL in
            let result = try runCurlFetch(
                urlString: xiaohongshuSavedCollectionURLString,
                cookieFileURL: cookieURL,
                headers: [
                    ("accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"),
                    ("referer", "https://www.xiaohongshu.com/"),
                    ("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36")
                ],
                timeout: 24
            )

            guard (200..<300).contains(result.statusCode),
                  let html = String(data: result.data, encoding: .utf8)
            else {
                throw InstagramSavedImportError.chromeCookieUnavailable("无法读取小红书收藏页（HTTP \(result.statusCode)）")
            }

            let links = xiaohongshuVideoLinks(fromSavedHTML: html, limit: limit)
            guard !links.isEmpty else {
                throw InstagramSavedImportError.noXiaohongshuVideoLinks
            }
            return links
        }
    }

    nonisolated static func platformName(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if host.contains("instagram.com") || host.contains("instagr.am")
            || host.contains("sssinstagram.com") || host.contains("cdninstagram.com") {
            return "Instagram"
        }
        if host.contains("xiaohongshu.com") || host.contains("xhslink.com") {
            return "小红书"
        }
        if host == "youtube.com" || host == "www.youtube.com"
            || host == "m.youtube.com" || host == "youtu.be"
            || host == "music.youtube.com" || host.contains("googlevideo.com") {
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
        let organized = Self.organizeVideoFiles(in: folder)
        applyScannedVideos(
            in: folder,
            urls: organized.urls,
            deferProjectDataLoad: false,
            videoPathRemap: organized.pathRemap,
            videoFolderTagsByPath: organized.folderTagsByPath
        )
    }

    private func applyScannedVideos(in folder: URL, urls: [URL]) {
        applyScannedVideos(
            in: folder,
            urls: urls,
            deferProjectDataLoad: false,
            videoPathRemap: [:],
            videoFolderTagsByPath: [:]
        )
    }

    private func applyScannedVideos(
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

        videos = urls
            .filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            .map(VideoItem.init(url:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

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
        ensureVideoSourceInfoAndTags()
        if deferProjectDataLoad {
            loadProjectDataDeferred(after: projectDataLoadDelay)
        } else {
            loadProjectData()
        }
        let metadataVideos = metadataPrefetchLimit.map { Array(videos.prefix(max(0, $0))) } ?? videos
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
        scanResourceLibrary()
    }

    nonisolated private struct VideoOrganizationResult: Sendable {
        var urls: [URL]
        var pathRemap: [String: String]
        var folderTagsByPath: [String: [String]]
    }

    nonisolated private struct CachedVideoLibrary: Codable, Sendable {
        var version: Int
        var generatedAt: Date
        var entries: [CachedVideoEntry]
    }

    nonisolated private struct CachedVideoEntry: Codable, Sendable {
        var relativePath: String
        var folderTags: [String]
    }

    nonisolated private static func organizeVideoFiles(in folder: URL) -> VideoOrganizationResult {
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

    nonisolated private static func videoURLs(in folder: URL) -> [URL] {
        organizeVideoFiles(in: folder).urls
    }

    nonisolated private static func quickVideoOrganizationSnapshot(in folder: URL) -> VideoOrganizationResult {
        ensureMediaFolders(in: folder)

        let videoRoot = mediaFolder(in: folder, named: videoFolderName)
        var urls: [URL] = []
        var folderTagsByPath: [String: [String]] = [:]

        for originalURL in allVideoCandidateURLs(in: folder) {
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

    nonisolated private static func videoLibraryCacheURL(in libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent(".lapianbao_videos_cache.json")
    }

    nonisolated private static func loadCachedVideoOrganization(in libraryURL: URL) -> VideoOrganizationResult? {
        let url = videoLibraryCacheURL(in: libraryURL)
        guard
            let data = try? Data(contentsOf: url),
            let cache = try? JSONDecoder().decode(CachedVideoLibrary.self, from: data),
            cache.version == videoLibraryCacheVersion
        else { return nil }

        let fm = FileManager.default
        var urls: [URL] = []
        var folderTagsByPath: [String: [String]] = [:]
        for entry in cache.entries {
            let fileURL = libraryURL.appendingPathComponent(entry.relativePath)
            guard supportedVideoExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            guard fm.fileExists(atPath: fileURL.path) else { continue }
            urls.append(fileURL)
            if !entry.folderTags.isEmpty {
                folderTagsByPath[fileURL.path] = entry.folderTags
            }
        }

        if !cache.entries.isEmpty && urls.isEmpty {
            return nil
        }

        return VideoOrganizationResult(
            urls: urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending },
            pathRemap: [:],
            folderTagsByPath: folderTagsByPath
        )
    }

    nonisolated private static func saveCachedVideoOrganization(_ result: VideoOrganizationResult, in libraryURL: URL) {
        let entries = result.urls.map { url in
            CachedVideoEntry(
                relativePath: libraryRelativePath(for: url, base: libraryURL),
                folderTags: result.folderTagsByPath[url.path, default: []]
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
        try? data.write(to: videoLibraryCacheURL(in: libraryURL), options: .atomic)
    }

    nonisolated private static func allVideoCandidateURLs(in folder: URL) -> [URL] {
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

    nonisolated private static func isVideoLibraryExcludedURL(_ url: URL, libraryURL: URL) -> Bool {
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

    nonisolated private static func videoFolderTags(for url: URL, libraryURL: URL, videoRoot: URL) -> [String] {
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

    nonisolated private static func audioDestinationFolderName(forVideoContainer url: URL) -> String? {
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

    nonisolated private struct ResourceLibrarySnapshot: Codable, Sendable {
        var music: [LocalMusicAsset]
        var audio: [LocalAudioAsset]
    }

    nonisolated private static func resourceLibraryCacheURL(in libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent(".lapianbao_resource_cache.json")
    }

    nonisolated private static func loadCachedResourceLibrarySnapshot(in libraryURL: URL) -> ResourceLibrarySnapshot? {
        let url = resourceLibraryCacheURL(in: libraryURL)
        guard
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(ResourceLibrarySnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    nonisolated private static func saveCachedResourceLibrarySnapshot(_ snapshot: ResourceLibrarySnapshot, in libraryURL: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: resourceLibraryCacheURL(in: libraryURL), options: .atomic)
    }

    nonisolated private static func quickResourceLibrarySnapshot(in libraryURL: URL) -> ResourceLibrarySnapshot {
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

    nonisolated private static func scanResourceLibrarySnapshot(in libraryURL: URL) async -> ResourceLibrarySnapshot {
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
                extraTagsBySourcePath: [legacyMusicRoot.path: ["导出"]]
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

    nonisolated private struct FlattenedResourceFile: Sendable {
        var url: URL
        var tags: [String]
        var fileSize: Int64
        var modifiedAt: Date?
    }

    nonisolated private static func collectMediaFiles(
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

    nonisolated private static func flattenMediaFiles(
        sourceRoots: [URL],
        targetRoot: URL,
        extensions: Set<String>,
        extraTagsBySourcePath: [String: [String]] = [:],
        skipGeneratedAudioClipFiles: Bool = false,
        deleteTinyGeneratedAudioClipFiles: Bool = false
    ) -> [FlattenedResourceFile] {
        let fm = FileManager.default
        try? fm.createDirectory(at: targetRoot, withIntermediateDirectories: true)

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

                results.append(FlattenedResourceFile(
                    url: finalURL,
                    tags: parentTags + extraTags,
                    fileSize: fileSize,
                    modifiedAt: values?.contentModificationDate
                ))
            }

            removeEmptyDirectories(under: sourceRoot, preserving: [targetRoot, sourceRoot])
        }
        return results
    }

    nonisolated private static func flattenedDestinationURL(for sourceURL: URL, targetRoot: URL) -> URL {
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

    nonisolated private static func resourceAssetTagsURL(in libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent(".lapianbao_asset_tags.json")
    }

    nonisolated private static func libraryRelativePath(for url: URL, base libraryURL: URL) -> String {
        let base = libraryURL.standardizedFileURL.path.hasSuffix("/")
            ? libraryURL.standardizedFileURL.path
            : libraryURL.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : url.lastPathComponent
    }

    nonisolated private static func loadResourceAssetTags(in libraryURL: URL) -> [String: [String]] {
        let url = resourceAssetTagsURL(in: libraryURL)
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }

        return decoded.mapValues(cleanedResourceTags)
    }

    nonisolated private static func saveResourceAssetTags(_ tagsByRelativePath: [String: [String]], in libraryURL: URL) {
        let url = resourceAssetTagsURL(in: libraryURL)
        let cleaned = tagsByRelativePath
            .filter { !$0.value.isEmpty }
            .mapValues(cleanedResourceTags)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cleaned) else { return }
        try? data.write(to: url, options: .atomic)
    }

    nonisolated private static func resourceFolderTags(for fileURL: URL, under rootURL: URL) -> [String] {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.deletingLastPathComponent().pathComponents
        guard fileComponents.count > rootComponents.count else { return [] }
        return Array(fileComponents.dropFirst(rootComponents.count))
    }

    nonisolated private static func cleanedResourceTags(_ rawTags: [String]) -> [String] {
        var seen = Set<String>()
        return rawTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix(".") }
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    nonisolated private static func inferredMusicRole(from url: URL) -> LocalMusicAsset.Role {
        let text = url.deletingPathExtension().lastPathComponent.lowercased()
        let instrumentalHints = ["伴奏", "instrumental", "karaoke", "off vocal", "off-vocal", "纯音乐", "inst"]
        if instrumentalHints.contains(where: { text.contains($0) }) {
            return .instrumental
        }
        return .original
    }

    nonisolated private static func isGeneratedAudioClipFile(_ url: URL) -> Bool {
        let stem = url.deletingPathExtension().lastPathComponent
        let pattern = #"_[0-9]{2}-[0-9]{2}(?:-[0-9]{2})?-[0-9]{2}-[0-9]{2}(?:-[0-9]{2})?$"#
        return stem.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    nonisolated private static func removeDirectoryIfEmpty(_ url: URL) {
        let fm = FileManager.default
        guard directoryExists(url),
              ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).isEmpty
        else { return }
        try? fm.removeItem(at: url)
    }

    nonisolated private static func removeEmptyDirectories(under rootURL: URL, preserving preservedURLs: [URL]) {
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

    private func tagsJSONURL() -> URL? {
        guard let libraryURL else { return nil }
        return libraryURL.appendingPathComponent(".lapianbaotags.json")
    }

    private func sourceInfoJSONURL() -> URL? {
        guard let libraryURL else { return nil }
        return libraryURL.appendingPathComponent(".lapianbao_sources.json")
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

    private func saveSourceInfoJSON() {
        guard let url = sourceInfoJSONURL(), let libraryURL else { return }
        let base = libraryURL.path.hasSuffix("/") ? libraryURL.path : libraryURL.path + "/"
        var relative: [String: VideoSourceInfo] = [:]
        for (absPath, info) in sourceInfoByVideoPath {
            let key = absPath.hasPrefix(base) ? String(absPath.dropFirst(base.count)) : absPath
            relative[key] = info
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(relative) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func projectDataURL() -> URL? {
        libraryURL?.appendingPathComponent(".lapianbao_project.json")
    }

    func flushProjectDataSave() {
        guard projectDataLoadState == .loaded else { return }
        guard projectDataDirty || projectSaveTask != nil else { return }
        projectSaveTask?.cancel()
        projectSaveTask = nil
        guard let url = projectDataURL() else { return }
        if (try? Self.writeProjectData(makeProjectDataFile(), to: url)) != nil {
            projectDataDirty = false
        }
    }

    private func saveProjectData() {
        guard projectDataLoadState == .loaded else { return }
        guard let url = projectDataURL() else { return }
        projectDataDirty = true
        projectSaveSequence += 1
        let sequence = projectSaveSequence
        let dataFile = makeProjectDataFile()

        projectSaveTask?.cancel()
        projectSaveTask = Task.detached(priority: .utility) { [url, dataFile] in
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                try Task.checkCancellation()
                try Self.writeProjectData(dataFile, to: url)
            } catch {
                await MainActor.run { [weak self] in
                    guard self?.projectSaveSequence == sequence else { return }
                    self?.projectSaveTask = nil
                }
                return
            }

            await MainActor.run { [weak self] in
                guard self?.projectSaveSequence == sequence else { return }
                self?.projectSaveTask = nil
                self?.projectDataDirty = false
            }
        }
    }

    private func makeProjectDataFile() -> ProjectDataFile {
        let dataFile = ProjectDataFile(
            sampledFrames: sampledFrames,
            annotations: annotations,
            audioClips: audioClips,
            transcripts: transcriptSegmentsByVideoPath,
            transcriptExports: transcriptExports.isEmpty ? nil : transcriptExports,
            musicsByVideoPath: musicsByVideoPath.isEmpty ? nil : musicsByVideoPath,
            musicDownloadJobs: musicDownloadJobs.isEmpty ? nil : persistedMusicDownloadJobs()
        )
        return dataFile
    }

    nonisolated private static func writeProjectData(_ dataFile: ProjectDataFile, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dataFile)
        try Task.checkCancellation()
        try data.write(to: url, options: .atomic)
    }

    private func loadProjectData() {
        projectLoadTask?.cancel()
        projectLoadTask = nil
        projectLoadGeneration += 1
        projectDataLoadState = .loading
        projectDataDirty = false
        guard
            let url = projectDataURL(),
            let decoded = Self.readProjectData(from: url)
        else {
            clearProjectData()
            projectDataLoadState = .loaded
            runStartupAutomationIfNeeded()
            return
        }
        let shouldPersistMigration = !pendingVideoPathRemap.isEmpty
        let migrated = migrateProjectDataVideoPaths(decoded)
        projectDataLoadState = .loaded
        applyProjectData(migrated)
        projectDataDirty = false
        if shouldPersistMigration {
            saveProjectData()
        }
    }

    private func loadProjectDataDeferred(after delay: TimeInterval = 0) {
        projectLoadTask?.cancel()
        projectLoadGeneration += 1
        let generation = projectLoadGeneration
        let delayNanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        projectDataLoadState = .loading
        projectDataDirty = false
        clearProjectData()
        guard let url = projectDataURL() else {
            projectDataLoadState = .loaded
            return
        }

        let priority: TaskPriority = delayNanoseconds > 0 ? .utility : .userInitiated
        projectLoadTask = Task.detached(priority: priority) { [weak self, url] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled else { return }
            }
            let decoded = Self.readProjectData(from: url)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.projectLoadGeneration == generation else { return }
                if let decoded {
                    let shouldPersistMigration = !self.pendingVideoPathRemap.isEmpty
                    let migrated = self.migrateProjectDataVideoPaths(decoded)
                    self.projectDataLoadState = .loaded
                    self.applyProjectData(migrated)
                    self.projectDataDirty = false
                    if shouldPersistMigration {
                        self.saveProjectData()
                    }
                } else {
                    self.clearProjectData()
                    self.projectDataLoadState = .loaded
                    self.runStartupAutomationIfNeeded()
                    self.projectDataDirty = false
                }
                self.projectLoadTask = nil
            }
        }
    }

    nonisolated private static func readProjectData(from url: URL) -> ProjectDataFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProjectDataFile.self, from: data)
    }

    private func clearProjectData() {
        sampledFrames = []
        annotations = []
        audioClips = []
        transcriptSegmentsByVideoPath = [:]
        transcriptExports = []
        musicsByVideoPath = [:]
        musicDownloadJobs = []
    }

    private func applyProjectData(_ decoded: ProjectDataFile) {
        sampledFrames = decoded.sampledFrames
        annotations = decoded.annotations
        audioClips = decoded.audioClips
        transcriptSegmentsByVideoPath = decoded.transcripts
        transcriptExports = decoded.transcriptExports ?? []
        musicsByVideoPath = decoded.musicsByVideoPath ?? [:]
        musicDownloadJobs = reconciledMusicDownloadJobs(decoded.musicDownloadJobs ?? [])
        enrichMusicTagsIfNeeded()
        hydratePersistedMusicDownloadWaveformsIfNeeded()
        runStartupAutomationIfNeeded()
    }

    private func migrateProjectDataVideoPaths(_ decoded: ProjectDataFile) -> ProjectDataFile {
        guard !pendingVideoPathRemap.isEmpty else { return decoded }

        var migrated = decoded
        migrated.sampledFrames = decoded.sampledFrames.map { frame in
            var item = frame
            item.videoPath = remapVideoPath(item.videoPath)
            return item
        }
        migrated.annotations = decoded.annotations.map { annotation in
            var item = annotation
            item.videoPath = remapVideoPath(item.videoPath)
            return item
        }
        migrated.audioClips = decoded.audioClips.map { clip in
            var item = clip
            item.videoPath = remapVideoPath(item.videoPath)
            return item
        }
        migrated.transcripts = remapVideoPathDictionary(decoded.transcripts).mapValues { segments in
            segments.map { segment in
                var item = segment
                item.videoPath = remapVideoPath(item.videoPath)
                return item
            }
        }
        migrated.transcriptExports = decoded.transcriptExports?.map { export in
            var item = export
            item.videoPath = remapVideoPath(item.videoPath)
            return item
        }
        if let musicsByVideoPath = decoded.musicsByVideoPath {
            migrated.musicsByVideoPath = remapVideoPathDictionary(musicsByVideoPath)
        }
        return migrated
    }

    private func persistedMusicDownloadJobs() -> [MusicDownloadJob] {
        musicDownloadJobs.map { job in
            var persisted = job
            persisted.isPreparingWaveform = false
            if Self.isActiveDownloadStatus(persisted.status) {
                persisted.status = .paused
                persisted.downloadProgress = nil
            }
            return persisted
        }
    }

    private func reconciledMusicDownloadJobs(_ jobs: [MusicDownloadJob]) -> [MusicDownloadJob] {
        jobs.map { job in
            var reconciled = job
            reconciled.isPreparingWaveform = false
            if Self.isActiveDownloadStatus(reconciled.status) {
                reconciled.status = .paused
                reconciled.downloadProgress = nil
            }
            if case .succeeded = reconciled.status,
               let filePath = reconciled.filePath,
               !FileManager.default.fileExists(atPath: filePath) {
                reconciled.status = .failed("下载文件不存在")
                reconciled.downloadProgress = nil
                reconciled.waveformSamples = nil
            }
            return reconciled
        }
    }

    private func hydratePersistedMusicDownloadWaveformsIfNeeded() {
        for job in musicDownloadJobs {
            guard case .succeeded = job.status,
                  job.waveformSamples?.isEmpty != false,
                  let filePath = job.filePath,
                  FileManager.default.fileExists(atPath: filePath)
            else { continue }

            updateMusicDownloadJob(id: job.id) { $0.isPreparingWaveform = true }
            Task { [weak self, jobID = job.id, fileURL = URL(fileURLWithPath: filePath)] in
                let samples = await Self.makeWaveformSamples(
                    for: fileURL,
                    sampleCount: Self.musicWaveformSampleCount
                )
                await MainActor.run {
                    self?.updateMusicDownloadJob(id: jobID) { j in
                        j.waveformSamples = samples ?? []
                        j.isPreparingWaveform = false
                    }
                }
            }
        }
    }

    private func runStartupAutomationIfNeeded() {
        guard projectDataLoadState == .loaded,
              let libraryPath = libraryURL?.path,
              startupAutomationLibraryPath != libraryPath
        else { return }

        startupAutomationLibraryPath = libraryPath
        DispatchQueue.main.async { [weak self] in
            guard let self, self.libraryURL?.path == libraryPath else { return }
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: Self.autoSceneBatchKey) {
                self.startSceneBatch(onlyMissing: true)
            }
            if defaults.bool(forKey: Self.autoTranscriptBatchKey) {
                self.startTranscriptBatch(onlyMissing: true)
            }
            if defaults.bool(forKey: Self.autoMusicDownloadBatchKey) {
                self.startMusicDownloadBatch(types: MusicDownloadJob.DownloadType.allCases)
            }
        }
    }

    func loadTagsJSON() {
        guard let url = tagsJSONURL(), let libraryURL else { return }
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }

        let base = libraryURL.path.hasSuffix("/") ? libraryURL.path : libraryURL.path + "/"
        var loadedTagsByVideoPath = tagsByVideoPath
        for (key, tags) in decoded where !tags.isEmpty {
            let absPath = key.hasPrefix("/") ? key : base + key
            loadedTagsByVideoPath[absPath] = tags
        }
        tagsByVideoPath = loadedTagsByVideoPath
    }

    private func loadSourceInfoJSON() {
        guard let url = sourceInfoJSONURL(), let libraryURL else { return }
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: VideoSourceInfo].self, from: data)
        else { return }

        let base = libraryURL.path.hasSuffix("/") ? libraryURL.path : libraryURL.path + "/"
        var loadedSourceInfoByVideoPath = sourceInfoByVideoPath
        for (key, info) in decoded {
            let absPath = key.hasPrefix("/") ? key : base + key
            loadedSourceInfoByVideoPath[absPath] = info
        }
        sourceInfoByVideoPath = loadedSourceInfoByVideoPath
    }

    private func applyPendingVideoPathMigrationToLoadedMetadata() {
        var shouldSaveTags = false
        var shouldSaveSources = false

        if !pendingVideoPathRemap.isEmpty {
            tagsByVideoPath = remapVideoPathDictionary(tagsByVideoPath)
            sourceInfoByVideoPath = remapVideoPathDictionary(sourceInfoByVideoPath)
            shouldSaveTags = true
            shouldSaveSources = true
        }

        if !pendingVideoFolderTagsByPath.isEmpty {
            var updated = tagsByVideoPath
            for (path, folderTags) in pendingVideoFolderTagsByPath {
                let cleanedTags = Self.cleanedResourceTags(folderTags)
                guard !cleanedTags.isEmpty else { continue }
                var merged = updated[path] ?? []
                var seen = Set(merged)
                for tag in cleanedTags where seen.insert(tag).inserted {
                    merged.append(tag)
                }
                updated[path] = merged
                shouldSaveTags = true
            }
            tagsByVideoPath = updated
        }

        if shouldSaveTags {
            saveTagsJSON()
        }
        if shouldSaveSources {
            saveSourceInfoJSON()
        }
    }

    private func remapVideoPath(_ path: String) -> String {
        pendingVideoPathRemap[path] ?? path
    }

    private func remapVideoPathDictionary<Value>(_ dictionary: [String: Value]) -> [String: Value] {
        guard !pendingVideoPathRemap.isEmpty else { return dictionary }
        var remapped: [String: Value] = [:]
        for (path, value) in dictionary {
            remapped[remapVideoPath(path)] = value
        }
        return remapped
    }

    private struct VideoSourceInference {
        var platform: String?
        var sourceURL: URL?
        var authorName: String?
        var title: String?
    }

    private func ensureVideoSourceInfoAndTags() {
        var updatedTagsByVideoPath = tagsByVideoPath
        var updatedSourceInfoByVideoPath = sourceInfoByVideoPath
        var didChangeTags = false
        var didChangeSourceInfo = false

        for video in videos {
            let path = video.url.path
            var tags = updatedTagsByVideoPath[path, default: []]
            let sourceInfo = updatedSourceInfoByVideoPath[path]
            let inference = inferredVideoSource(for: video, sourceInfo: sourceInfo, tags: tags)
            let normalizedPlatform = inference.platform.flatMap(Self.canonicalSourcePlatform)
            let normalizedAuthor = (sourceInfo?.authorName ?? inference.authorName).flatMap(Self.normalizedImportTag)
            let normalizedTitle = (sourceInfo?.title ?? inference.title).flatMap(Self.normalizedSourceTitle)

            if let normalizedPlatform {
                let sourceURLString = Self.usefulSourceURLString(sourceInfo?.sourceURL)
                    ?? inference.sourceURL?.absoluteString
                let updatedInfo = VideoSourceInfo(
                    platform: normalizedPlatform,
                    sourceURL: sourceURLString,
                    authorName: normalizedAuthor,
                    title: normalizedTitle
                )
                if updatedInfo != sourceInfo {
                    updatedSourceInfoByVideoPath[path] = updatedInfo
                    didChangeSourceInfo = true
                }
            }

            let candidates = [
                normalizedPlatform,
                normalizedAuthor
            ]

            for candidate in candidates.compactMap({ $0 }).compactMap(Self.normalizedImportTag) where !tags.contains(candidate) {
                tags.append(candidate)
            }

            let sortedTags = tags.sorted()
            if sortedTags != updatedTagsByVideoPath[path, default: []] {
                updatedTagsByVideoPath[path] = sortedTags
                didChangeTags = true
            }
        }

        if didChangeSourceInfo {
            sourceInfoByVideoPath = updatedSourceInfoByVideoPath
            saveSourceInfoJSON()
        }
        if didChangeTags {
            tagsByVideoPath = updatedTagsByVideoPath
            saveTagsJSON()
        }
    }

    func videoAuthorName(for video: VideoItem) -> String? {
        sourceInfoByVideoPath[video.url.path]?.authorName
    }

    func videoSourceTitle(for video: VideoItem) -> String? {
        let path = video.url.path
        if let cached = videoSourceTitleCache[path] {
            return cached
        }
        let title = sourceInfoByVideoPath[path]?.title.flatMap(Self.normalizedSourceTitle)
        videoSourceTitleCache[path] = title
        return title
    }

    func videoSourcePlatform(for video: VideoItem) -> String? {
        let path = video.url.path
        if let cached = videoSourcePlatformCache[path] {
            return cached
        }
        let tags = tagsByVideoPath[path, default: []]
        let platform = inferredVideoSource(
            for: video,
            sourceInfo: sourceInfoByVideoPath[path],
            tags: tags
        ).platform
        videoSourcePlatformCache[path] = platform
        return platform
    }

    private func sourceTag(forImportedVideo video: VideoItem) -> String? {
        let components = video.url.pathComponents
        guard
            let importsIndex = components.lastIndex(of: "Imports"),
            components.indices.contains(importsIndex + 1)
        else { return nil }

        let folder = components[importsIndex + 1]
        return Self.canonicalSourcePlatform(folder)
    }

    private func inferredVideoSource(for video: VideoItem, sourceInfo: VideoSourceInfo?, tags: [String]) -> VideoSourceInference {
        let whereFromURLs = Self.whereFromURLs(for: video.url)
        let sourceURLs = Self.uniqueURLs(Self.sourceURLs(from: sourceInfo) + whereFromURLs)
        let importedPlatform = sourceInfo?.platform
        let importedAuthorName = sourceInfo?.authorName
        let platform = [
            importedPlatform.flatMap(Self.canonicalSourcePlatform),
            Self.sourcePlatform(from: sourceURLs),
            sourceTag(forImportedVideo: video),
            Self.sourcePlatform(fromTags: tags),
            Self.sourcePlatform(fromPathComponents: video.url.pathComponents),
            Self.sourcePlatform(fromText: video.name)
        ].compactMap { $0 }.first

        let sourceURL = sourceURLs.first(where: Self.isUsefulSourceURL)
        let authorName = importedAuthorName.flatMap(Self.normalizedImportTag)
            ?? Self.sourceAuthorName(from: sourceURLs, fileName: video.url.lastPathComponent)
        let title = sourceInfo?.title.flatMap(Self.normalizedSourceTitle)
            ?? Self.sourceTitle(from: sourceURLs, fileName: video.url.lastPathComponent)

        return VideoSourceInference(platform: platform, sourceURL: sourceURL, authorName: authorName, title: title)
    }

    nonisolated private static func sourceURLs(from sourceInfo: VideoSourceInfo?) -> [URL] {
        guard
            let sourceURL = sourceInfo?.sourceURL,
            let url = URL(string: sourceURL)
        else { return [] }
        return [url]
    }

    nonisolated private static func sourcePlatform(from urls: [URL]) -> String? {
        for url in urls {
            if let platform = platformName(for: url) {
                return platform
            }
            if let platform = sourcePlatform(fromText: url.absoluteString) {
                return platform
            }
        }
        return nil
    }

    nonisolated private static func sourcePlatform(fromTags tags: [String]) -> String? {
        tags.compactMap(canonicalSourcePlatform).first
    }

    nonisolated private static func sourcePlatform(fromPathComponents components: [String]) -> String? {
        components.compactMap(canonicalSourcePlatform).first
    }

    nonisolated private static func sourcePlatform(fromText text: String) -> String? {
        let lowercased = text.lowercased()
        if lowercased.contains("instagram.com")
            || lowercased.contains("instagr.am")
            || lowercased.contains("sssinstagram") {
            return "Instagram"
        }
        if lowercased.contains("youtube.com") || lowercased.contains("youtu.be") {
            return "YouTube"
        }
        if lowercased.contains("xiaohongshu.com")
            || lowercased.contains("xhslink.com")
            || text.contains("小红书") {
            return "小红书"
        }
        if lowercased.contains("bilibili.com")
            || lowercased.contains("b23.tv")
            || lowercased.contains("bilibili")
            || text.contains("哔哩哔哩")
            || text.contains("B站")
            || text.contains("b站")
            || text.range(of: #"(?<![A-Za-z0-9])BV[0-9A-Za-z]{10}(?![A-Za-z0-9])"#, options: .regularExpression) != nil {
            return "Bilibili"
        }
        if lowercased.contains("douyin.com")
            || lowercased.contains("iesdouyin.com")
            || lowercased.contains("tiktok.com")
            || lowercased.contains("v.douyin.com")
            || text.contains("抖音") {
            return "抖音"
        }
        return nil
    }

    nonisolated private static func canonicalSourcePlatform(_ rawValue: String) -> String? {
        let normalized = normalizedSpaces(rawValue)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-_/@#"))
        guard !normalized.isEmpty else { return nil }

        if let exact = knownSourcePlatforms.first(where: {
            $0.caseInsensitiveCompare(normalized) == .orderedSame
                || importFolderName(for: $0).caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            return exact
        }

        let compact = normalized
            .lowercased()
            .replacingOccurrences(of: #"[\s._-]+"#, with: "", options: .regularExpression)
        switch compact {
        case "instagram", "insta", "ig", "reels", "instagramreels":
            return "Instagram"
        case "youtube", "yt", "youtubecom", "youtu", "youtu.be":
            return "YouTube"
        case "小红书", "xiaohongshu", "xhs", "rednote":
            return "小红书"
        case "bilibili", "bili", "哔哩哔哩", "b站":
            return "Bilibili"
        case "douyin", "抖音", "tiktok", "tik tok":
            return "抖音"
        default:
            return nil
        }
    }

    nonisolated private static func whereFromURLs(for fileURL: URL) -> [URL] {
        let attributeName = "com.apple.metadata:kMDItemWhereFroms"
        let length = getxattr(fileURL.path, attributeName, nil, 0, 0, 0)
        guard length > 0 else { return [] }

        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes { buffer in
            getxattr(fileURL.path, attributeName, buffer.baseAddress, length, 0, 0)
        }
        guard result > 0 else { return [] }

        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let values: [String]
        if let strings = plist as? [String] {
            values = strings
        } else if let string = plist as? String {
            values = [string]
        } else {
            values = []
        }

        return uniqueURLs(values.flatMap(sourceURLs(in:)))
    }

    nonisolated private static func sourceURLs(in text: String) -> [URL] {
        var urls: [URL] = []
        if let url = URL(string: text), url.scheme != nil {
            urls.append(url)
            urls.append(contentsOf: embeddedSourceURLs(in: url))
        }
        return urls
    }

    nonisolated private static func embeddedSourceURLs(in url: URL) -> [URL] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        let sourceQueryNames = Set(["url", "u", "uri", "referer", "referrer", "source", "source_url"])
        return components.queryItems?
            .filter { sourceQueryNames.contains($0.name.lowercased()) }
            .compactMap { $0.value }
            .flatMap(sourceURLs(in:)) ?? []
    }

    nonisolated private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    nonisolated private static func isUsefulSourceURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return platformName(for: url) != nil
            && !host.contains("fbcdn.net")
            && !host.contains("cdninstagram.com")
            && !host.contains("sssinstagram.com")
            && !host.contains("googlevideo.com")
            && url.path != "/"
            && !url.path.isEmpty
    }

    nonisolated private static func usefulSourceURLString(_ rawValue: String?) -> String? {
        guard
            let rawValue,
            let url = URL(string: rawValue),
            isUsefulSourceURL(url)
        else { return nil }
        return rawValue
    }

    nonisolated private static func sourceAuthorName(from urls: [URL], fileName: String) -> String? {
        let queryHints = urls.flatMap { url -> [String] in
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
            return components.queryItems?.compactMap(\.value) ?? []
        }
        let pathHints = urls.flatMap(sourceAuthorHints(from:))
        let hints = [fileName] + queryHints + urls.map(\.absoluteString)
        return hints.lazy.compactMap(firstMentionHandle).first
            ?? pathHints.lazy.compactMap(normalizedImportTag).first
            ?? instagramAuthorID(from: urls)
    }

    nonisolated private static func firstMentionHandle(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.])@([A-Za-z0-9_.]{2,30})"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return normalizedImportTag(String(text[captureRange]))
    }

    nonisolated private static func sourceAuthorHints(from url: URL) -> [String] {
        guard let host = url.host?.lowercased() else { return [] }
        let components = url.path
            .split(separator: "/")
            .map(String.init)
            .map(decodedSourceText)
            .filter { !$0.isEmpty }
        guard let first = components.first else { return [] }

        if host.contains("youtube.com"), first.hasPrefix("@") {
            return [String(first.dropFirst())]
        }
        if host.contains("tiktok.com"), first.hasPrefix("@") {
            return [String(first.dropFirst())]
        }
        if host.contains("instagram.com") || host.contains("instagr.am") {
            let reserved = Set(["p", "reel", "reels", "tv", "stories", "explore", "accounts"])
            if !reserved.contains(first.lowercased()), first.range(of: #"^[A-Za-z0-9_.]{2,30}$"#, options: .regularExpression) != nil {
                return [first]
            }
        }
        return []
    }

    nonisolated private static func instagramAuthorID(from urls: [URL]) -> String? {
        for url in urls {
            let text = decodedSourceText(url.absoluteString)
            let lowercased = text.lowercased()
            guard lowercased.contains("instagram") || lowercased.contains("cdninstagram") else { continue }
            let patterns = [
                #"(?i)(?:^|[?&])vs=(\d{6,})_"#,
                #"(?i)vs%3D(\d{6,})_"#
            ]
            for pattern in patterns {
                guard
                    let regex = try? NSRegularExpression(pattern: pattern),
                    let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                    match.numberOfRanges > 1,
                    let range = Range(match.range(at: 1), in: text)
                else { continue }
                let id = String(text[range])
                return normalizedImportTag("Instagram ID \(id)")
            }
        }
        return nil
    }

    nonisolated private static func sourceTitle(from urls: [URL], fileName: String) -> String? {
        let titleQueryNames = Set([
            "title", "name", "filename", "file", "file_name",
            "video_title", "caption", "desc", "description"
        ])
        var candidates: [String] = []

        for url in urls {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                for item in components.queryItems ?? [] where titleQueryNames.contains(item.name.lowercased()) {
                    guard let value = item.value, !value.isEmpty else { continue }
                    let decoded = decodedSourceText(value)
                    let queryName = item.name.lowercased()
                    if queryName.contains("file") {
                        candidates.append(fileStem(from: decoded))
                    } else if queryName == "desc" || queryName == "description" || queryName == "caption" {
                        candidates.append(cleanImportDescription(decoded))
                    } else {
                        candidates.append(decoded)
                    }
                }
            }

            if platformName(for: url) == nil || isDirectMediaURL(url) {
                let lastComponent = decodedSourceText(url.lastPathComponent)
                if !lastComponent.isEmpty {
                    candidates.append(fileStem(from: lastComponent))
                }
            }
        }

        candidates.append(fileStem(from: fileName))
        return candidates.lazy.compactMap(normalizedSourceTitle).first
    }

    nonisolated private static func normalizedSourceTitle(_ rawValue: String) -> String? {
        let decoded = decodedSourceText(rawValue)
        var title = stripTrailingSourceID(normalizedSpaces(decoded))
        if title.contains("/") || title.contains("\\") {
            title = fileStem(from: title)
        }

        let extensionPattern = #"(?i)\.(mp4|mov|m4v|webm|mkv|avi|m2ts|mts)$"#
        title = title.replacingOccurrences(of: extensionPattern, with: "", options: .regularExpression)
        title = sanitizeImportFileStem(title)

        guard !isGenericImportTitle(title),
              !looksLikeTechnicalSourceTitle(title),
              canonicalSourcePlatform(title) == nil,
              URL(string: title)?.scheme == nil
        else { return nil }

        return compactImportFileStem(title, maxLength: 118)
    }

    nonisolated private static func screenedSourceTitle(
        rawTitle: String?,
        description: String?,
        sourceURL: URL
    ) -> String? {
        if let title = rawTitle.flatMap(normalizedSourceTitle) {
            return title
        }
        if let title = normalizedSourceTitle(cleanImportDescription(description ?? "")) {
            return title
        }
        return nil
    }

    nonisolated private static func isDirectMediaURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "webm", "mkv", "avi", "m2ts", "mts"].contains(ext)
    }

    nonisolated private static func looksLikeTechnicalSourceTitle(_ title: String) -> Bool {
        let lowercased = title.lowercased()
        if lowercased == "imported video"
            || lowercased == "download"
            || lowercased == "downloaded video"
            || lowercased == "media"
            || lowercased == "videoplayback"
            || lowercased == "reel"
            || lowercased == "reels"
            || lowercased == "story" {
            return true
        }
        if lowercased.range(of: #"^instagram-[0-9a-f-]{8,}$"#, options: .regularExpression) != nil {
            return true
        }
        if lowercased.contains("fbcdn.net")
            || lowercased.contains("cdninstagram")
            || lowercased.contains("googlevideo")
            || lowercased.contains("videoplayback") {
            return true
        }

        let compact = title.replacingOccurrences(of: #"[\s._-]+"#, with: "", options: .regularExpression)
        let isAlphanumeric = compact.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil
        let hasDigit = compact.range(of: #"[0-9]"#, options: .regularExpression) != nil
        if compact.count >= 18, isAlphanumeric, hasDigit {
            return true
        }
        if compact.range(of: #"^[0-9]{10,}$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    nonisolated private static func decodedSourceText(_ text: String) -> String {
        var current = text
        for _ in 0..<2 {
            guard let decoded = current.removingPercentEncoding, decoded != current else { break }
            current = decoded
        }
        return current
    }

    nonisolated private static func importFolderName(for platform: String) -> String {
        let safeFolder = platform.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return safeFolder.isEmpty ? "Other" : safeFolder
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    func loadWaveform(for video: VideoItem) {
        let path = video.url.path
        guard waveformTasks[path] == nil else { return }
        if let samples = waveformSamplesByVideoPath[path], samples.count >= Self.waveformSampleCount {
            return
        }

        waveformTasks[path] = Task { [weak self] in
            let samples = await Self.makeWaveformSamples(for: video.url, sampleCount: Self.waveformSampleCount) ?? []
            guard !Task.isCancelled else { return }

            self?.waveformSamplesByVideoPath[path] = samples
            self?.waveformTasks[path] = nil
        }
    }

    func loadAudioClipWaveformIfNeeded(_ clip: AudioClipItem) {
        let hasCurrentWaveform = clip.waveformVersion == Self.audioClipWaveformVersion
            && clip.waveformSamples?.isEmpty == false
        guard !hasCurrentWaveform,
              audioClipWaveformTasks[clip.id] == nil
        else { return }

        let clipID = clip.id
        let clipFileURL = audioClipFileURL(for: clip)
        let url = clipFileURL ?? URL(fileURLWithPath: clip.videoPath)
        let start = clipFileURL == nil ? clip.inTime : nil
        let end = clipFileURL == nil ? clip.outTime : nil
        audioClipWaveformTasks[clipID] = Task { [weak self] in
            let samples = await Self.makeWaveformSamples(
                for: url,
                sampleCount: Self.audioClipWaveformSampleCount,
                start: start,
                end: end
            ) ?? []
            guard !Task.isCancelled else { return }

            self?.setAudioClipWaveform(id: clipID, samples: samples)
            self?.audioClipWaveformTasks[clipID] = nil
        }
    }

    func loadLocalMusicWaveformIfNeeded(_ asset: LocalMusicAsset) {
        enqueueLocalWaveform(.music(asset.filePath))
    }

    func loadLocalAudioWaveformIfNeeded(_ asset: LocalAudioAsset) {
        enqueueLocalWaveform(.audio(asset.filePath))
    }

    func cancelPendingLocalMusicWaveformLoad(for asset: LocalMusicAsset) {
        cancelPendingLocalWaveform(.music(asset.filePath))
    }

    func cancelPendingLocalAudioWaveformLoad(for asset: LocalAudioAsset) {
        cancelPendingLocalWaveform(.audio(asset.filePath))
    }

    func cancelPendingLocalWaveformLoads() {
        pendingLocalWaveformRequests.removeAll()
        pendingLocalWaveformRequestSet.removeAll()
    }

    private func enqueueLocalWaveform(_ request: LocalWaveformRequest) {
        guard !hasLocalWaveformSamples(for: request),
              localWaveformTasks[request] == nil,
              !pendingLocalWaveformRequestSet.contains(request),
              localResourceFileExists(at: request.path)
        else { return }

        pendingLocalWaveformRequests.append(request)
        pendingLocalWaveformRequestSet.insert(request)
        startQueuedLocalWaveforms()
    }

    private func cancelPendingLocalWaveform(_ request: LocalWaveformRequest) {
        guard pendingLocalWaveformRequestSet.remove(request) != nil else { return }
        pendingLocalWaveformRequests.removeAll { $0 == request }
    }

    private func startQueuedLocalWaveforms() {
        while localWaveformTasks.count < Self.localWaveformWorkerCount,
              !pendingLocalWaveformRequests.isEmpty {
            let request = pendingLocalWaveformRequests.removeFirst()
            pendingLocalWaveformRequestSet.remove(request)

            guard !hasLocalWaveformSamples(for: request),
                  localResourceFileExists(at: request.path)
            else { continue }

            let task = Task.detached(priority: .utility) { [weak self, request] in
                let samples = await Self.makeWaveformSamples(
                    for: URL(fileURLWithPath: request.path),
                    sampleCount: request.sampleCount
                ) ?? []
                guard !Task.isCancelled else { return }

                await MainActor.run { [weak self] in
                    self?.finishLocalWaveform(request, samples: samples)
                }
            }
            localWaveformTasks[request] = task
        }
    }

    private func finishLocalWaveform(_ request: LocalWaveformRequest, samples: [Double]) {
        guard localWaveformTasks[request] != nil else { return }
        localWaveformTasks[request] = nil

        switch request {
        case .music(let path):
            if localMusicWaveformSamplesByPath[path] == nil {
                localMusicWaveformSamplesByPath[path] = samples
            }
        case .audio(let path):
            if localAudioWaveformSamplesByPath[path] == nil {
                localAudioWaveformSamplesByPath[path] = samples
            }
        }

        startQueuedLocalWaveforms()
    }

    private func hasLocalWaveformSamples(for request: LocalWaveformRequest) -> Bool {
        switch request {
        case .music(let path):
            return localMusicWaveformSamplesByPath[path] != nil
        case .audio(let path):
            return localAudioWaveformSamplesByPath[path] != nil
        }
    }

    private func setAudioClipWaveform(id: UUID, samples: [Double]) {
        guard let index = audioClips.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        audioClips[index].waveformSamples = samples
        audioClips[index].waveformVersion = Self.audioClipWaveformVersion
        saveProjectData()
    }

    func loadFrameStrip(for video: VideoItem) {
        let path = video.url.path
        guard frameStripByVideoPath[path] == nil, frameStripTasks[path] == nil else { return }

        frameStripTasks[path] = Task { [weak self] in
            let frames = await Self.makeFrameStrip(for: video.url)
            guard !Task.isCancelled else { return }

            self?.frameStripByVideoPath[path] = frames
            self?.frameStripImagesByVideoPath[path] = frames.compactMap { NSImage(data: $0) }
            self?.updateSceneStripImages(for: path)
            self?.frameStripTasks[path] = nil
        }
    }

    nonisolated private static func makeFrameStrip(for url: URL, count: Int = 16) async -> [Data] {
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

    func detectSceneCuts(for video: VideoItem) {
        let path = video.url.path
        guard sceneDetectionTasks[path] == nil, sceneDetectionProgress[path] == nil else { return }

        sceneDetectionProgress[path] = 0.0

        sceneDetectionTasks[path] = Task { [weak self] in
            let cuts = await Self.performSceneDetection(for: video.url) { progress in
                Task { @MainActor in
                    self?.sceneDetectionProgress[path] = Self.normalizedProgress(progress)
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
        sceneCutCache.removeValue(forKey: relativeVideoPath(for: video.url))
        saveSceneCutCache()
    }

    func deleteAllSceneRecognitions() {
        sceneDetectionTasks.values.forEach { $0.cancel() }
        sceneDetectionTasks.removeAll()
        sceneThumbnailHydrationTasks.values.forEach { $0.cancel() }
        sceneThumbnailHydrationTasks.removeAll()
        sceneThumbnailHydrationNeeded.removeAll()
        sceneCutsByVideoPath.removeAll()
        sceneStripImagesByVideoPath.removeAll()
        sceneCutProgressesByVideoPath.removeAll()
        sceneThumbnailVersionsByVideoPath.removeAll()
        sceneDetectionProgress.removeAll()
        sceneCutCache.removeAll()
        saveSceneCutCache()
    }

    func startSceneBatch(onlyMissing: Bool = true) {
        guard sceneBatchTask == nil else { return }
        let queue = videos.filter { video in
            if onlyMissing {
                return sceneCutsByVideoPath[video.url.path] == nil
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
                    self.sceneDetectionProgress[path] = 0
                    self.updateSceneBatchProgress(completed: completed, currentProgress: 0)
                }

                let cuts = await Self.performSceneDetection(for: video.url) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.sceneDetectionProgress[path] = Self.normalizedProgress(progress)
                        self?.updateSceneBatchProgress(completed: completed, currentProgress: progress)
                    }
                }

                completed += 1
                await MainActor.run {
                    self.setSceneCuts(cuts, for: path)
                    self.storeSceneCutCache(for: video, cuts: cuts)
                    self.sceneDetectionProgress[path] = nil
                    self.updateSceneBatchProgress(completed: completed, currentProgress: 0)
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

    func pauseSceneBatch() {
        isSceneBatchPaused = true
        if sceneBatchTask != nil { sceneBatchJob.status = .paused }
    }

    func resumeSceneBatch() {
        guard sceneBatchTask != nil else { return }
        isSceneBatchPaused = false
        sceneBatchJob.status = .running
    }

    func cancelSceneBatch() {
        sceneBatchTask?.cancel()
        sceneBatchTask = nil
        isSceneBatchPaused = false
        sceneBatchJob = TranscriptBatchJob()
    }

    private func updateSceneBatchProgress(completed: Int, currentProgress: Double) {
        let total = max(1, sceneBatchJob.total)
        sceneBatchJob.completed = completed
        sceneBatchJob.progress = Self.normalizedProgress((Double(completed) + Self.normalizedProgress(currentProgress)) / Double(total))
    }

    func loadCachedSceneCuts(for video: VideoItem) {
        let path = video.url.path
        guard
            sceneCutsByVideoPath[path] == nil,
            sceneDetectionTasks[path] == nil,
            let cachedEntry = validCachedSceneCutEntry(for: video)
        else { return }

        if cachedEntry.cutTimes.isEmpty {
            setSceneCuts([], for: path)
            return
        }

        let placeholder = thumbnailImageByVideoPath[path] ?? Self.scenePlaceholderImage()
        setSceneCuts(
            Self.lightweightSceneCuts(from: cachedEntry.cutTimes, placeholderImage: placeholder),
            for: path,
            needsThumbnailHydration: true
        )
    }

    func hydrateSceneThumbnailsIfNeeded(for video: VideoItem) {
        let path = video.url.path
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
                self?.sceneThumbnailHydrationTasks[path] = nil
                self?.bumpSceneThumbnailVersion(for: path)
                return
            }

            self?.setSceneCuts(cuts, for: path)
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

    private static func lightweightSceneCuts(from cutTimes: [Double], placeholderImage: NSImage) -> [SceneCut] {
        stableSceneCutTimes(from: cutTimes).enumerated().map { index, time in
            SceneCut(
                id: sceneCutID(index: index, time: time),
                time: time,
                thumbnailImage: placeholderImage,
                isPlaceholder: true
            )
        }
    }

    private static func scenePlaceholderImage() -> NSImage {
        let size = NSSize(width: 200, height: 113)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    private func setSceneCuts(
        _ cuts: [SceneCut],
        for path: String,
        needsThumbnailHydration: Bool = false
    ) {
        sceneCutsByVideoPath[path] = cuts
        if needsThumbnailHydration {
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
    }

    private func updateSceneStripImages(for path: String) {
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

    private func displaySceneCutImage(for path: String, cut: SceneCut) -> NSImage? {
        guard cut.isPlaceholder else { return cut.thumbnailImage }
        return approximateFrameStripImage(for: path, at: cut.time)
            ?? thumbnailImageByVideoPath[path]
    }

    private func approximateFrameStripImage(for path: String, at time: Double) -> NSImage? {
        guard let images = frameStripImagesByVideoPath[path], !images.isEmpty else { return nil }
        let duration = durationByVideoPath[path] ?? 0
        guard duration > 0, images.count > 1 else { return images.first }
        let progress = min(1, max(0, time / duration))
        let index = min(images.count - 1, max(0, Int((progress * Double(images.count - 1)).rounded())))
        return images[index]
    }

    private func bumpSceneThumbnailVersion(for path: String) {
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

    func deleteSampledFrame(_ frame: SampledFrame) {
        sampledFrames.removeAll { $0.id == frame.id }
        writeFrameIndex()
        saveProjectData()
    }

    func deleteAudioClip(_ clip: AudioClipItem) {
        audioClipWaveformTasks[clip.id]?.cancel()
        audioClipWaveformTasks[clip.id] = nil
        audioClips.removeAll { $0.id == clip.id }
        saveProjectData()
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

    func enrichMusicTagsIfNeeded() {
        let candidates = musicsByVideoPath.flatMap { path, songs in
            songs.map { (path: path, song: $0) }
        }

        for candidate in candidates where shouldEnrichMusicTags(candidate.song) {
            let key = musicTagEnrichmentKey(for: candidate.song, in: candidate.path)
            guard musicTagEnrichmentTasks[key] == nil else { continue }

            musicTagEnrichmentTasks[key] = Task { [weak self] in
                let tags = await Self.lookupMusicTags(title: candidate.song.title, artist: candidate.song.artist)
                await MainActor.run {
                    defer { self?.musicTagEnrichmentTasks[key] = nil }
                    guard !tags.isEmpty else { return }
                    self?.mergeMusicTags(tags, into: candidate.song, in: candidate.path)
                }
            }
        }
    }

    private func updateFrameTags(_ frame: SampledFrame, mutate: (inout [String]) -> Void) {
        guard let index = sampledFrames.firstIndex(where: { $0.id == frame.id }) else { return }
        var tags = sampledFrames[index].tags
        mutate(&tags)
        sampledFrames[index].tags = tags.sorted()
        writeFrameIndex()
        saveProjectData()
    }

    private func updateAudioTags(_ clip: AudioClipItem, mutate: (inout [String]) -> Void) {
        guard let index = audioClips.firstIndex(where: { $0.id == clip.id }) else { return }
        var tags = audioClips[index].tags
        mutate(&tags)
        audioClips[index].tags = tags.sorted()
        saveProjectData()
    }

    private func updateMusicTags(_ song: MusicRecognitionItem, in videoPath: String, mutate: (inout [String]) -> Void) {
        guard var songs = musicsByVideoPath[videoPath],
              let index = songs.firstIndex(where: { Self.musicItemsMatch($0, song) })
        else { return }

        var tags = songs[index].tags
        mutate(&tags)
        songs[index].tags = tags.sorted()
        musicsByVideoPath[videoPath] = songs
        saveProjectData()
    }

    private func mergeMusicTags(_ newTags: [String], into song: MusicRecognitionItem, in videoPath: String) {
        updateMusicTags(song, in: videoPath) { tags in
            tags = MusicRecognitionItem.cleanedTags(tags + newTags)
        }
    }

    private func shouldEnrichMusicTags(_ song: MusicRecognitionItem) -> Bool {
        !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !song.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && song.displayTags.count <= 1
    }

    private func musicTagEnrichmentKey(for song: MusicRecognitionItem, in videoPath: String) -> String {
        "\(videoPath)|\(song.title)|\(song.artist)"
    }

    nonisolated private static func musicItemsMatch(_ lhs: MusicRecognitionItem, _ rhs: MusicRecognitionItem) -> Bool {
        lhs.id == rhs.id
            || (
                lhs.title == rhs.title
                    && lhs.artist == rhs.artist
                    && abs(lhs.detectedAt - rhs.detectedAt) < 0.001
            )
    }

    nonisolated private static func musicItems(
        _ songs: [MusicRecognitionItem],
        preservingTagsFrom existingSongs: [MusicRecognitionItem]
    ) -> [MusicRecognitionItem] {
        songs.map { musicItem($0, preservingTagsFrom: existingSongs) }
    }

    nonisolated private static func musicItem(
        _ song: MusicRecognitionItem,
        preservingTagsFrom existingSongs: [MusicRecognitionItem]
    ) -> MusicRecognitionItem {
        guard let existing = existingSongs.first(where: { sameRecognizedSong($0, song) }) else { return song }
        var updated = song
        updated.tags = Array(Set(song.tags + existing.tags)).sorted()
        return updated
    }

    nonisolated private static func sameRecognizedSong(_ lhs: MusicRecognitionItem, _ rhs: MusicRecognitionItem) -> Bool {
        lhs.title.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(
            rhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        ) == .orderedSame
            && lhs.artist.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(
                rhs.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            ) == .orderedSame
    }

    nonisolated private static func lookupMusicTags(title: String, artist: String) async -> [String] {
        let query = "\(artist) \(title)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              var components = URLComponents(string: "https://itunes.apple.com/search")
        else { return [] }

        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard let result = decoded.results.first(where: { $0.kind == "song" }) else { return [] }
            return MusicRecognitionItem.cleanedTags([
                result.artistName ?? artist,
                result.primaryGenreName ?? ""
            ])
        } catch {
            return []
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

    private func appendTag(_ rawTag: String, to tags: inout [String]) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
    }

    func markSceneFrameExported(video: VideoItem, cut: SceneCut, sceneIndex: Int?) {
        Task { [weak self] in
            let data = await Self.renderFrameData(for: video.url, at: cut.time + 0.08)
                ?? Self.jpegData(from: cut.thumbnailImage)
            guard
                let data,
                self?.saveImageExport(data: data, video: video, time: cut.time, preferredExtension: "jpg") != nil
            else { return }

            if let index = self?.sampledFrames.firstIndex(where: {
                $0.videoPath == video.url.path &&
                abs($0.time - cut.time) < 0.02 &&
                $0.kind == .sceneRepresentative
            }) {
                self?.sampledFrames[index].isExported = true
            } else {
                self?.sampledFrames.append(SampledFrame(
                    videoPath: video.url.path,
                    videoName: video.name,
                    time: cut.time,
                    sceneIndex: sceneIndex,
                    kind: .sceneRepresentative,
                    isExported: true,
                    note: "",
                    tags: [],
                    thumbnailData: data
                ))
            }
            self?.sampledFrames.sort { $0.time < $1.time }
            self?.writeFrameIndex()
            self?.saveProjectData()
        }
    }

    func captureCurrentFrame(video: VideoItem, time: Double) {
        Task { [weak self] in
            guard let data = await Self.renderFrameData(for: video.url, at: time) else { return }
            guard self?.saveImageExport(data: data, video: video, time: time, preferredExtension: "jpg") != nil else { return }

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
            self?.writeFrameIndex()
            self?.saveProjectData()
        }
    }

    func exportAudioClip(video: VideoItem, inTime: Double, outTime: Double) {
        let start = max(0, min(inTime, outTime))
        let end = max(inTime, outTime)
        guard end - start > 0.05 else { return }
        let path = video.url.path
        let videoName = video.name
        guard audioClipExportProgressByVideoPath[path] == nil else { return }
        audioClipExportProgressByVideoPath[path] = 0.05

        Task { [weak self] in
            self?.audioClipExportProgressByVideoPath[path] = 0.18
            let outputURL = await Self.exportAudioClipFile(video: video, videoName: videoName, start: start, end: end, libraryURL: self?.libraryURL)
            self?.audioClipExportProgressByVideoPath[path] = 0.62

            let clip = AudioClipItem(
                videoPath: video.url.path,
                videoName: videoName,
                inTime: start,
                outTime: end,
                filePath: outputURL?.path
            )
            self?.audioClips.append(clip)
            self?.saveProjectData()
            self?.audioClipExportProgressByVideoPath[path] = 0.74

            let samples = await Self.makeWaveformSamples(
                for: video.url,
                sampleCount: Self.audioClipWaveformSampleCount,
                start: start,
                end: end
            ) ?? []
            self?.setAudioClipWaveform(id: clip.id, samples: samples)
            self?.audioClipExportProgressByVideoPath[path] = 1.0
            self?.scanResourceLibrary(forceFullScan: true)
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.audioClipExportProgressByVideoPath[path] = nil
        }
    }

    func transcribe(video: VideoItem) {
        let path = video.url.path
        if case .running = transcriptStatusByVideoPath[path] { return }
        transcriptStatusByVideoPath[path] = .running("准备字幕分析 1%")
        let videoName = video.name
        let progressCallback: @Sendable (Double, String) -> Void = { [weak self] progress, message in
            Task { @MainActor [weak self] in
                self?.updateTranscriptProgress(path: path, progress: progress, message: message)
            }
        }

        Task { [weak self] in
            do {
                let segments = try await Self.runWhisperTranscription(
                    video: video,
                    videoName: videoName,
                    libraryURL: self?.libraryURL,
                    progressCallback: progressCallback
                )
                self?.transcriptSegmentsByVideoPath[path] = segments
                self?.transcriptStatusByVideoPath[path] = .idle
                self?.saveProjectData()
            } catch {
                self?.transcriptStatusByVideoPath[path] = .failed(error.localizedDescription)
            }
        }
    }

    func deleteTranscript(for video: VideoItem) {
        let path = video.url.path
        transcriptSegmentsByVideoPath[path] = nil
        transcriptStatusByVideoPath[path] = .idle
        saveProjectData()
    }

    func deleteAllTranscripts() {
        transcriptSegmentsByVideoPath.removeAll()
        transcriptStatusByVideoPath.removeAll()
        saveProjectData()
    }

    func startTranscriptBatch(onlyMissing: Bool = true) {
        guard transcriptBatchTask == nil else { return }
        let queue = videos.filter { video in
            if onlyMissing {
                return transcriptSegmentsByVideoPath[video.url.path, default: []].isEmpty
            }
            return true
        }
        guard !queue.isEmpty else {
            transcriptBatchJob = TranscriptBatchJob(status: .completed, total: 0, completed: 0, progress: 1)
            return
        }

        isTranscriptBatchPaused = false
        transcriptBatchJob = TranscriptBatchJob(status: .running, total: queue.count, completed: 0, progress: 0)

        transcriptBatchTask = Task { [weak self] in
            guard let self else { return }
            var completed = 0

            for video in queue {
                while await MainActor.run(body: { self.isTranscriptBatchPaused }) {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                if Task.isCancelled { break }

                let path = video.url.path
                await MainActor.run {
                    self.transcriptBatchJob.status = .running
                    self.transcriptBatchJob.currentVideoPath = path
                    self.transcriptBatchJob.currentVideoName = video.name
                    self.updateTranscriptBatchProgress(completed: completed, currentProgress: 0)
                    self.transcriptStatusByVideoPath[path] = .running("准备字幕分析 1%")
                }

                let progressCallback: @Sendable (Double, String) -> Void = { [weak self] progress, message in
                    Task { @MainActor [weak self] in
                        self?.updateTranscriptProgress(path: path, progress: progress, message: message)
                    }
                }

                do {
                    let segments = try await Self.runWhisperTranscription(
                        video: video,
                        videoName: video.name,
                        libraryURL: await MainActor.run { self.libraryURL },
                        progressCallback: progressCallback
                    )
                    completed += 1
                    await MainActor.run {
                        self.transcriptSegmentsByVideoPath[path] = segments
                        self.transcriptStatusByVideoPath[path] = .idle
                        self.updateTranscriptBatchProgress(completed: completed, currentProgress: 0)
                        self.saveProjectData()
                    }
                } catch {
                    completed += 1
                    await MainActor.run {
                        self.transcriptStatusByVideoPath[path] = .failed(error.localizedDescription)
                        self.updateTranscriptBatchProgress(completed: completed, currentProgress: 0)
                    }
                }
            }

            await MainActor.run {
                self.transcriptBatchTask = nil
                if self.transcriptBatchJob.completed >= self.transcriptBatchJob.total {
                    self.transcriptBatchJob.status = .completed
                    self.transcriptBatchJob.currentVideoPath = nil
                    self.transcriptBatchJob.currentVideoName = nil
                    self.transcriptBatchJob.progress = 1
                }
            }
        }
    }

    func pauseTranscriptBatch() {
        isTranscriptBatchPaused = true
        if transcriptBatchTask != nil {
            transcriptBatchJob.status = .paused
        }
    }

    func resumeTranscriptBatch() {
        guard transcriptBatchTask != nil else { return }
        isTranscriptBatchPaused = false
        transcriptBatchJob.status = .running
    }

    func cancelTranscriptBatch() {
        transcriptBatchTask?.cancel()
        transcriptBatchTask = nil
        isTranscriptBatchPaused = false
        transcriptBatchJob = TranscriptBatchJob()
    }

    private func updateTranscriptProgress(path: String, progress: Double, message: String) {
        let normalized = Self.normalizedProgress(progress)
        let currentMessage: String
        let currentProgress: Double
        if case let .running(existingMessage) = transcriptStatusByVideoPath[path] {
            currentMessage = existingMessage
            currentProgress = Self.parsePercentValue(from: existingMessage).map { Self.normalizedProgress($0 / 100) } ?? 0
        } else {
            currentMessage = ""
            currentProgress = 0
        }

        let stableProgress = max(currentProgress, normalized)
        let progressDelta = stableProgress - currentProgress
        let stageChanged = !currentMessage.hasPrefix(message)
        guard stageChanged || progressDelta >= 0.01 || stableProgress >= 0.995 else { return }

        transcriptStatusByVideoPath[path] = .running(
            "\(message) \(Self.progressPercentTextForStatus(stableProgress))"
        )
        if transcriptBatchJob.currentVideoPath == path {
            updateTranscriptBatchProgress(completed: transcriptBatchJob.completed, currentProgress: stableProgress)
        }
    }

    private func updateTranscriptBatchProgress(completed: Int, currentProgress: Double) {
        let total = max(1, transcriptBatchJob.total)
        transcriptBatchJob.completed = completed
        transcriptBatchJob.progress = Self.normalizedProgress((Double(completed) + Self.normalizedProgress(currentProgress)) / Double(total))
    }

    nonisolated private static func progressPercentTextForStatus(_ progress: Double) -> String {
        "\(Int((normalizedProgress(progress) * 100).rounded()))%"
    }

    func detectMusic(for video: VideoItem) {
        let path = video.url.path
        if case .running = musicDetectionStatusByVideoPath[path] { return }
        let existingSongs = musicsByVideoPath[path, default: []]
        musicDetectionStatusByVideoPath[path] = .running("准备中…")

        musicDetectionTasks[path]?.cancel()
        weak let weakSelf = self
        musicDetectionTasks[path] = Task {
            defer {
                Task { @MainActor in
                    weakSelf?.musicDetectionTasks[path] = nil
                }
            }
            do {
                let songs = try await Self.runMusicDetection(
                    videoPath: path,
                    onEvent: { event in
                        await MainActor.run {
                            switch event {
                            case .progress(let msg):
                                weakSelf?.musicDetectionStatusByVideoPath[path] = .running(msg)
                            case .found(let song):
                                let taggedSong = Self.musicItem(song, preservingTagsFrom: existingSongs)
                                var current = weakSelf?.musicsByVideoPath[path] ?? []
                                if !current.contains(where: { $0.title == taggedSong.title && $0.artist == taggedSong.artist }) {
                                    current.append(taggedSong)
                                    weakSelf?.musicsByVideoPath[path] = current
                                }
                            }
                        }
                    }
                )
                weakSelf?.musicsByVideoPath[path] = Self.musicItems(songs, preservingTagsFrom: existingSongs)
                weakSelf?.musicDetectionStatusByVideoPath[path] = .completed
                weakSelf?.saveProjectData()
            } catch is CancellationError {
                weakSelf?.musicsByVideoPath[path] = existingSongs
                weakSelf?.musicDetectionStatusByVideoPath[path] = .idle
            } catch {
                weakSelf?.musicsByVideoPath[path] = existingSongs
                weakSelf?.musicDetectionStatusByVideoPath[path] = .failed(error.localizedDescription)
            }
        }
    }

    func cancelMusicDetection(for video: VideoItem) {
        let path = video.url.path
        musicDetectionTasks[path]?.cancel()
        musicDetectionTasks[path] = nil
        musicDetectionStatusByVideoPath[path] = .idle
    }

    func deleteMusicRecognition(for video: VideoItem) {
        let path = video.url.path
        musicDetectionTasks[path]?.cancel()
        musicDetectionTasks[path] = nil
        musicsByVideoPath.removeValue(forKey: path)
        musicDetectionStatusByVideoPath[path] = .idle
        saveProjectData()
    }

    func deleteAllMusicRecognitions() {
        musicDetectionTasks.values.forEach { $0.cancel() }
        musicDetectionTasks.removeAll()
        musicsByVideoPath.removeAll()
        musicDetectionStatusByVideoPath.removeAll()
        saveProjectData()
    }

    func startMusicBatch(onlyMissing: Bool = true) {
        guard musicBatchTask == nil else { return }
        let queue = videos.filter { video in
            if onlyMissing {
                return musicsByVideoPath[video.url.path, default: []].isEmpty
            }
            return true
        }
        guard !queue.isEmpty else {
            musicBatchJob = TranscriptBatchJob(status: .completed, total: 0, completed: 0, progress: 1)
            return
        }

        isMusicBatchPaused = false
        musicBatchJob = TranscriptBatchJob(status: .running, total: queue.count, completed: 0, progress: 0)
        musicBatchTask = Task { [weak self] in
            guard let self else { return }
            var completed = 0

            for video in queue {
                while await MainActor.run(body: { self.isMusicBatchPaused }) {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                if Task.isCancelled { break }

                let path = video.url.path
                let existingSongs = await MainActor.run {
                    self.musicsByVideoPath[path, default: []]
                }
                await MainActor.run {
                    self.musicBatchJob.status = .running
                    self.musicBatchJob.currentVideoPath = path
                    self.musicBatchJob.currentVideoName = video.name
                    self.musicDetectionStatusByVideoPath[path] = .running("准备中…")
                    self.updateMusicBatchProgress(completed: completed, currentProgress: 0)
                }

                do {
                    let songs = try await Self.runMusicDetection(
                        videoPath: path,
                        onEvent: { event in
                            await MainActor.run {
                                switch event {
                                case .progress(let message):
                                    self.musicDetectionStatusByVideoPath[path] = .running(message)
                                case .found(let song):
                                    let taggedSong = Self.musicItem(song, preservingTagsFrom: existingSongs)
                                    var current = self.musicsByVideoPath[path] ?? []
                                    if !current.contains(where: { $0.title == taggedSong.title && $0.artist == taggedSong.artist }) {
                                        current.append(taggedSong)
                                        self.musicsByVideoPath[path] = current
                                    }
                                }
                            }
                        }
                    )
                    completed += 1
                    await MainActor.run {
                        self.musicsByVideoPath[path] = Self.musicItems(songs, preservingTagsFrom: existingSongs)
                        self.musicDetectionStatusByVideoPath[path] = .completed
                        self.updateMusicBatchProgress(completed: completed, currentProgress: 0)
                        self.saveProjectData()
                    }
                } catch {
                    completed += 1
                    await MainActor.run {
                        self.musicsByVideoPath[path] = existingSongs
                        self.musicDetectionStatusByVideoPath[path] = .failed(error.localizedDescription)
                        self.updateMusicBatchProgress(completed: completed, currentProgress: 0)
                    }
                }
            }

            await MainActor.run {
                self.musicBatchTask = nil
                if self.musicBatchJob.completed >= self.musicBatchJob.total {
                    self.musicBatchJob.status = .completed
                    self.musicBatchJob.currentVideoPath = nil
                    self.musicBatchJob.currentVideoName = nil
                    self.musicBatchJob.progress = 1
                }
            }
        }
    }

    func pauseMusicBatch() {
        isMusicBatchPaused = true
        if musicBatchTask != nil { musicBatchJob.status = .paused }
    }

    func resumeMusicBatch() {
        guard musicBatchTask != nil else { return }
        isMusicBatchPaused = false
        musicBatchJob.status = .running
    }

    func cancelMusicBatch() {
        musicBatchTask?.cancel()
        musicBatchTask = nil
        isMusicBatchPaused = false
        musicBatchJob = TranscriptBatchJob()
    }

    private func updateMusicBatchProgress(completed: Int, currentProgress: Double) {
        let total = max(1, musicBatchJob.total)
        musicBatchJob.completed = completed
        musicBatchJob.progress = Self.normalizedProgress((Double(completed) + Self.normalizedProgress(currentProgress)) / Double(total))
    }

    func recognizeLocalMusicAssetsIfNeeded() {
        guard localMusicRecognitionTask == nil else { return }
        let queue = localMusicRecognitionQueue()
        guard !queue.isEmpty else { return }

        localMusicRecognitionTask = Task { [weak self] in
            guard let self else { return }

            for asset in queue {
                if Task.isCancelled { break }

                let path = asset.filePath
                let shouldSkip = await MainActor.run {
                    self.shouldSkipLocalMusicRecognition(for: asset)
                }
                if shouldSkip { continue }

                let existingSongs = await MainActor.run {
                    self.musicsByVideoPath[path, default: []]
                }

                await MainActor.run {
                    self.musicDetectionStatusByVideoPath[path] = .running("准备中…")
                }

                do {
                    let songs = try await Self.runMusicDetection(
                        videoPath: path,
                        onEvent: { event in
                            await MainActor.run {
                                switch event {
                                case .progress(let message):
                                    self.musicDetectionStatusByVideoPath[path] = .running(message)
                                case .found(let song):
                                    let taggedSong = Self.musicItem(song, preservingTagsFrom: existingSongs)
                                    var current = self.musicsByVideoPath[path] ?? []
                                    if !current.contains(where: { Self.sameRecognizedSong($0, taggedSong) }) {
                                        current.append(taggedSong)
                                        self.musicsByVideoPath[path] = current
                                    }
                                }
                            }
                        }
                    )

                    await MainActor.run {
                        self.musicsByVideoPath[path] = Self.musicItems(songs, preservingTagsFrom: existingSongs)
                        self.musicDetectionStatusByVideoPath[path] = .completed
                        self.saveProjectData()
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.musicsByVideoPath[path] = existingSongs
                        self.musicDetectionStatusByVideoPath[path] = .idle
                    }
                } catch {
                    await MainActor.run {
                        self.musicsByVideoPath[path] = existingSongs
                        self.musicDetectionStatusByVideoPath[path] = .failed(error.localizedDescription)
                    }
                }
            }

            await MainActor.run {
                self.localMusicRecognitionTask = nil
                if !Task.isCancelled {
                    self.recognizeLocalMusicAssetsIfNeeded()
                }
            }
        }
    }

    private func localMusicRecognitionQueue() -> [LocalMusicAsset] {
        localMusicAssets.filter { !shouldSkipLocalMusicRecognition(for: $0) }
    }

    private func shouldSkipLocalMusicRecognition(for asset: LocalMusicAsset) -> Bool {
        let path = asset.filePath
        guard FileManager.default.fileExists(atPath: path) else { return true }
        if musicDetectionTasks[path] != nil { return true }
        if !musicsByVideoPath[path, default: []].isEmpty { return true }

        switch musicDetectionStatusByVideoPath[path] ?? .idle {
        case .running, .completed, .failed:
            return true
        case .idle:
            return false
        }
    }

    func downloadMusic(song: MusicRecognitionItem, type: MusicDownloadJob.DownloadType) {
        startExternalServiceSelfCheckPreflightIfNeeded()
        guard let jobID = prepareMusicDownloadJob(song: song, type: type) else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runMusicDownload(jobID: jobID, song: song, type: type)
        }
        musicDownloadTasks[jobID] = task
    }

    func startMusicDownloadBatch(types: [MusicDownloadJob.DownloadType] = MusicDownloadJob.DownloadType.allCases) {
        guard musicDownloadBatchTask == nil else { return }
        startExternalServiceSelfCheckPreflightIfNeeded()
        guard libraryURL != nil else {
            musicDownloadBatchJob = TranscriptBatchJob(status: .failed("请先打开一个素材库文件夹"), total: 0, completed: 0, progress: 0)
            return
        }

        let queue = musicDownloadBatchQueue(types: types)
        guard !queue.isEmpty else {
            musicDownloadBatchJob = TranscriptBatchJob(status: .completed, total: 0, completed: 0, progress: 1)
            return
        }

        musicDownloadBatchJob = TranscriptBatchJob(status: .running, total: queue.count, completed: 0, progress: 0)
        musicDownloadBatchTask = Task { [weak self] in
            guard let self else { return }
            var completed = 0

            for entry in queue {
                if Task.isCancelled { break }
                let title = entry.song.title.isEmpty ? "未知音乐" : entry.song.title
                self.musicDownloadBatchJob.status = .running
                self.musicDownloadBatchJob.currentVideoName = "\(title) · \(entry.type.label)"
                self.updateMusicDownloadBatchProgress(completed: completed, currentProgress: 0)

                if let jobID = self.prepareMusicDownloadJob(song: entry.song, type: entry.type) {
                    await self.runMusicDownload(jobID: jobID, song: entry.song, type: entry.type)
                }

                completed += 1
                self.updateMusicDownloadBatchProgress(completed: completed, currentProgress: 0)
            }

            self.musicDownloadBatchTask = nil
            if self.musicDownloadBatchJob.completed >= self.musicDownloadBatchJob.total {
                self.musicDownloadBatchJob.status = .completed
                self.musicDownloadBatchJob.currentVideoName = nil
                self.musicDownloadBatchJob.progress = 1
            }
        }
    }

    func cancelMusicDownloads() {
        musicDownloadBatchTask?.cancel()
        musicDownloadBatchTask = nil
        musicDownloadTasks.values.forEach { $0.cancel() }
        musicDownloadTasks.removeAll()
        musicDownloadBatchJob = TranscriptBatchJob()
        for index in musicDownloadJobs.indices where Self.isActiveDownloadStatus(musicDownloadJobs[index].status) {
            musicDownloadJobs[index].status = .paused
            musicDownloadJobs[index].downloadProgress = nil
            musicDownloadJobs[index].isPreparingWaveform = false
        }
    }

    func clearMusicDownloadState() {
        cancelMusicDownloads()
        musicDownloadJobs.removeAll()
        musicDownloadBatchJob = TranscriptBatchJob()
        saveProjectData()
    }

    private func prepareMusicDownloadJob(song: MusicRecognitionItem, type: MusicDownloadJob.DownloadType) -> UUID? {
        guard libraryURL != nil else {
            musicDownloadJobs.append(MusicDownloadJob(
                songKey: musicSongKey(song),
                type: type,
                status: .failed("请先打开一个素材库文件夹")
            ))
            return nil
        }

        let songKey = musicSongKey(song)
        if let existing = latestMusicDownloadJob(songKey: songKey, type: type) {
            if Self.isActiveDownloadStatus(existing.status) {
                return nil
            }
            if isSatisfiedMusicDownload(existing) {
                return nil
            }
        }

        let job = MusicDownloadJob(songKey: songKey, type: type, status: .importing)
        musicDownloadJobs.append(job)
        return job.id
    }

    private func runMusicDownload(jobID: UUID, song: MusicRecognitionItem, type: MusicDownloadJob.DownloadType) async {
        defer {
            musicDownloadTasks.removeValue(forKey: jobID)
        }

        guard let libraryURL else {
            updateMusicDownloadJob(id: jobID) { j in
                j.status = .failed("请先打开一个素材库文件夹")
                j.downloadProgress = nil
                j.isPreparingWaveform = false
            }
            return
        }

        let query = "\(song.artist.isEmpty ? "" : song.artist + " ")\(song.title)\(type.searchSuffix)"
        let progressCallback: @Sendable (Double) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.updateMusicDownloadJob(id: jobID) { j in
                    j.downloadProgress = Self.normalizedProgress(progress)
                }
            }
        }

        do {
            startExternalServiceSelfCheckPreflightIfNeeded()
            let destinationDirectory = Self.mediaFolder(in: libraryURL, named: Self.musicExportFolderName)
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            let outputURL = try await Self.downloadMusicFromYouTube(
                query: query,
                into: destinationDirectory,
                progressCallback: progressCallback
            )
            updateMusicDownloadJob(id: jobID) { j in
                j.status = .succeeded(outputURL.lastPathComponent)
                j.downloadProgress = 1
                j.filePath = outputURL.path
                j.waveformSamples = nil
                j.isPreparingWaveform = true
            }

            let samples = await Self.makeWaveformSamples(
                for: outputURL,
                sampleCount: Self.musicWaveformSampleCount
            )
            updateMusicDownloadJob(id: jobID) { j in
                j.waveformSamples = samples ?? []
                j.isPreparingWaveform = false
            }
            scanResourceLibrary(forceFullScan: true)
        } catch is CancellationError {
            updateMusicDownloadJob(id: jobID) { j in
                j.status = .paused
                j.downloadProgress = nil
                j.isPreparingWaveform = false
            }
        } catch {
            updateMusicDownloadJob(id: jobID) { j in
                j.status = .failed(error.localizedDescription)
                j.downloadProgress = nil
                j.isPreparingWaveform = false
            }
        }
    }

    private func updateMusicDownloadJob(id: UUID, mutate: (inout MusicDownloadJob) -> Void) {
        guard let index = musicDownloadJobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&musicDownloadJobs[index])
        saveProjectData()
    }

    private func updateMusicDownloadBatchProgress(completed: Int, currentProgress: Double) {
        let total = max(1, musicDownloadBatchJob.total)
        musicDownloadBatchJob.completed = completed
        musicDownloadBatchJob.progress = Self.normalizedProgress((Double(completed) + Self.normalizedProgress(currentProgress)) / Double(total))
    }

    private func musicDownloadBatchQueue(types: [MusicDownloadJob.DownloadType]) -> [(song: MusicRecognitionItem, type: MusicDownloadJob.DownloadType)] {
        var uniqueSongs: [MusicRecognitionItem] = []
        var seen = Set<String>()
        for song in musicsByVideoPath.values.flatMap({ $0 }) {
            if seen.insert(musicSongKey(song)).inserted {
                uniqueSongs.append(song)
            }
        }

        return uniqueSongs.flatMap { song in
            types.compactMap { type in
                isMusicDownloadSatisfied(song: song, type: type) ? nil : (song, type)
            }
        }
    }

    private func isMusicDownloadSatisfied(song: MusicRecognitionItem, type: MusicDownloadJob.DownloadType) -> Bool {
        guard let job = latestMusicDownloadJob(songKey: musicSongKey(song), type: type) else { return false }
        return isSatisfiedMusicDownload(job)
    }

    private func isSatisfiedMusicDownload(_ job: MusicDownloadJob) -> Bool {
        guard case .succeeded = job.status,
              let filePath = job.filePath,
              FileManager.default.fileExists(atPath: filePath)
        else { return false }
        return true
    }

    private func latestMusicDownloadJob(songKey: String, type: MusicDownloadJob.DownloadType) -> MusicDownloadJob? {
        musicDownloadJobs.last { $0.songKey == songKey && $0.type == type }
    }

    private func musicSongKey(_ song: MusicRecognitionItem) -> String {
        "\(song.title)|\(song.artist)"
    }

    nonisolated private static func isActiveDownloadStatus(_ status: RemoteImportJob.Status) -> Bool {
        switch status {
        case .importing, .transcoding, .finalizing:
            return true
        default:
            return false
        }
    }

    nonisolated private struct MusicDownloadSource: Sendable {
        let name: String
        let target: String
        var extraArguments: [String] = []
    }

    nonisolated private static func downloadMusicFromYouTube(
        query: String,
        into destinationDirectory: URL,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let processRegistry = ToolProcessRegistry()
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: URL.self) { group in
                group.addTask {
                    try await downloadMusicFromYouTubeSearch(
                        query: query,
                        into: destinationDirectory,
                        processRegistry: processRegistry,
                        progressCallback: progressCallback
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 300_000_000_000)
                    processRegistry.cancelRunningProcess()
                    throw RemoteImportError.downloaderFailed("YouTube 音乐下载超时。通常是网络不可达、YouTube 限速，或当前地区无法访问 YouTube 搜索。")
                }

                guard let result = try await group.next() else {
                    throw RemoteImportError.downloaderFailed("YouTube 音乐下载失败")
                }
                group.cancelAll()
                return result
            }
        } onCancel: {
            processRegistry.cancelRunningProcess()
        }
    }

    nonisolated private static func downloadMusicFromYouTubeSearch(
        query: String,
        into destinationDirectory: URL,
        processRegistry: ToolProcessRegistry,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        progressCallback?(0.02)
        let sources = await musicDownloadSources(for: query)
        var failures: [String] = []

        for (index, source) in sources.enumerated() {
            let sourceStart = Double(index) / Double(max(sources.count, 1))
            let sourceSpan = 1.0 / Double(max(sources.count, 1))
            progressCallback?(min(0.98, max(0.02, sourceStart + 0.02 * sourceSpan)))

            do {
                return try await runMusicYTDLPDownloadWithTimeout(
                    source: source,
                    into: destinationDirectory,
                    processRegistry: processRegistry,
                    progressCallback: { progress in
                        progressCallback?(min(0.98, sourceStart + progress * sourceSpan))
                    }
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append("\(source.name)：\(error.localizedDescription)")
                progressCallback?(min(0.98, sourceStart + sourceSpan))
            }
        }

        throw RemoteImportError.downloaderFailed(
            failures.isEmpty ? "YouTube 搜索下载失败" : failures.suffix(3).joined(separator: "\n")
        )
    }

    nonisolated private static func musicDownloadSources(for query: String) async -> [MusicDownloadSource] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let attempts = ytdlpYouTubeArgumentAttempts()
        func expandedSources(name: String, target: String) -> [MusicDownloadSource] {
            attempts.map { attempt in
                MusicDownloadSource(
                    name: attempt.label.isEmpty ? name : "\(name)（\(attempt.label)）",
                    target: target,
                    extraArguments: attempt.arguments
                )
            }
        }

        var sources: [MusicDownloadSource] = []
        if let firstResultURL = await firstYouTubeSearchResultURL(for: trimmedQuery) {
            sources.append(contentsOf: expandedSources(name: "YouTube 播放页", target: firstResultURL.absoluteString))
        }
        sources.append(contentsOf: expandedSources(name: "YouTube 搜索兜底", target: "ytsearch1:\(trimmedQuery)"))
        return sources
    }

    nonisolated static func firstYouTubeSearchResultURL(for query: String) async -> URL? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        if let ytdlpURL = await firstYouTubeSearchResultURLWithYTDLP(for: trimmedQuery) {
            return ytdlpURL
        }
        return await firstYouTubeSearchResultURLFromSearchPage(for: trimmedQuery)
    }

    nonisolated private static func firstYouTubeSearchResultURLWithYTDLP(for query: String) async -> URL? {
        guard let ytdlp = localYTDLPURL() else { return nil }

        let processRegistry = ToolProcessRegistry()
        return await withTaskCancellationHandler {
            await withTaskGroup(of: URL?.self) { group in
                group.addTask {
                    await runFirstYouTubeSearchResultYTDLP(
                        executableURL: ytdlp,
                        query: query,
                        processRegistry: processRegistry
                    )
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    processRegistry.cancelRunningProcess()
                    return nil
                }

                let result = await group.next() ?? nil
                group.cancelAll()
                return result
            }
        } onCancel: {
            processRegistry.cancelRunningProcess()
        }
    }

    nonisolated private static func runFirstYouTubeSearchResultYTDLP(
        executableURL: URL,
        query: String,
        processRegistry: ToolProcessRegistry
    ) async -> URL? {
        let attempt = ytdlpYouTubeArgumentAttempts().first ?? YTDLPArgumentAttempt(arguments: [])
        return await Task.detached(priority: .utility) { () -> URL? in
            let process = Process()
            process.executableURL = executableURL
            process.environment = downloaderProcessEnvironment()
            var arguments = [
                "--no-playlist",
                "--skip-download",
                "--no-warnings",
                "--default-search", "ytsearch",
                "--print", "%(webpage_url)s",
                "ytsearch1:\(query)"
            ]
            arguments.insert(contentsOf: ytdlpProbeNetworkArguments(isYouTube: true), at: 3)
            arguments.insert(contentsOf: attempt.arguments, at: max(0, arguments.count - 2))
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let outputCollector = PipeDataCollector()
            let errorCollector = PipeDataCollector()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                outputCollector.append(handle.availableData)
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                errorCollector.append(handle.availableData)
            }

            do {
                try process.run()
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                return nil
            }

            processRegistry.set(process)
            process.waitUntilExit()
            processRegistry.set(nil)

            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
            errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

            if Task.isCancelled {
                if process.isRunning { process.terminate() }
                return nil
            }
            guard process.terminationStatus == 0 else { return nil }

            let output = String(data: outputCollector.data, encoding: .utf8) ?? ""
            return firstYouTubeWatchURL(fromYTDLPOutput: output)
        }.value
    }

    nonisolated private static func firstYouTubeSearchResultURLFromSearchPage(for query: String) async -> URL? {
        guard var components = URLComponents(string: "https://www.youtube.com/results") else { return nil }

        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        guard let searchURL = components.url else { return nil }

        var request = URLRequest(url: searchURL)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<400).contains(httpResponse.statusCode) {
                return nil
            }
            guard
                let html = String(data: data, encoding: .utf8),
                let url = firstYouTubeWatchURL(in: html)
            else { return nil }
            return url
        } catch {
            return nil
        }
    }

    nonisolated private static func firstYouTubeWatchURL(fromYTDLPOutput output: String) -> URL? {
        for line in output.split(whereSeparator: \.isNewline) {
            let rawURLString = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = normalizedYouTubeWatchURL(from: rawURLString) {
                return url
            }
        }
        return firstYouTubeWatchURL(in: output)
    }

    nonisolated private static func firstYouTubeWatchURL(in text: String) -> URL? {
        let patterns = [
            #""videoRenderer"\s*:\s*\{\s*"videoId"\s*:\s*"([A-Za-z0-9_-]{11})""#,
            #""videoId"\s*:\s*"([A-Za-z0-9_-]{11})""#,
            #"watch\?v=([A-Za-z0-9_-]{11})"#,
            #"%2Fwatch%3Fv%3D([A-Za-z0-9_-]{11})"#,
            #"/shorts/([A-Za-z0-9_-]{11})"#
        ]
        let nsText = text as NSString
        let searchRange = NSRange(location: 0, length: nsText.length)

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: searchRange) where match.numberOfRanges > 1 {
                let videoID = nsText.substring(with: match.range(at: 1))
                if let url = youTubeWatchURL(videoID: videoID) {
                    return url
                }
            }
        }
        return nil
    }

    nonisolated private static func normalizedYouTubeWatchURL(from rawURLString: String) -> URL? {
        guard
            let url = URL(string: rawURLString),
            let videoID = youTubeVideoID(from: url)
        else { return nil }
        return youTubeWatchURL(videoID: videoID)
    }

    nonisolated private static func youTubeVideoID(from url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if host == "youtu.be",
           let videoID = pathComponents.first,
           isValidYouTubeVideoID(videoID) {
            return videoID
        }

        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }

        if let videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "v" })?
            .value,
           isValidYouTubeVideoID(videoID) {
            return videoID
        }

        for marker in ["shorts", "embed"] {
            if let markerIndex = pathComponents.firstIndex(of: marker) {
                let videoIndex = pathComponents.index(after: markerIndex)
                if pathComponents.indices.contains(videoIndex) {
                    let videoID = pathComponents[videoIndex]
                    if isValidYouTubeVideoID(videoID) {
                        return videoID
                    }
                }
            }
        }
        return nil
    }

    nonisolated private static func youTubeWatchURL(videoID: String) -> URL? {
        guard isValidYouTubeVideoID(videoID) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    nonisolated private static func isValidYouTubeVideoID(_ videoID: String) -> Bool {
        videoID.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
    }

    nonisolated private static func runMusicYTDLPDownloadWithTimeout(
        source: MusicDownloadSource,
        into destinationDirectory: URL,
        processRegistry: ToolProcessRegistry,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                try await runMusicYTDLPDownload(
                    source: source,
                    into: destinationDirectory,
                    processRegistry: processRegistry,
                    progressCallback: progressCallback
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 90_000_000_000)
                processRegistry.cancelRunningProcess()
                throw RemoteImportError.downloaderFailed("\(source.name) 下载超时")
            }

            guard let result = try await group.next() else {
                throw RemoteImportError.downloaderFailed("\(source.name) 下载失败")
            }
            group.cancelAll()
            return result
        }
    }

    nonisolated private static func runMusicYTDLPDownload(
        source: MusicDownloadSource,
        into destinationDirectory: URL,
        processRegistry: ToolProcessRegistry,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await Task.detached(priority: .utility) {
            guard let ytdlp = localYTDLPURL() else {
                throw RemoteImportError.downloaderFailed("未找到 yt-dlp。请先安装 yt-dlp 和 ffmpeg，用于从 YouTube 搜索视频并抽取音频。")
            }

            let startedAt = Date()
            let process = Process()
            process.executableURL = ytdlp
            var env = downloaderProcessEnvironment()
            env["PYTHONUNBUFFERED"] = "1"
            env["PYTHONIOENCODING"] = "utf-8"
            process.environment = env

            var arguments = [
                "--no-playlist",
                "-x",
                "--audio-format", "m4a",
                "--audio-quality", "0",
                "-f", "ba/bestaudio/best",
                "--progress",
                "--newline",
                "--no-colors",
                "--default-search", "ytsearch",
                "--paths", destinationDirectory.path,
                "-o", "%(title).160B-%(id)s.%(ext)s",
                "--print", "after_move:filepath"
            ]
            if let ffmpegDirectoryPath = localFFmpegDirectoryPath() {
                arguments.insert(contentsOf: ["--ffmpeg-location", ffmpegDirectoryPath], at: 6)
            }
            arguments += ytdlpDownloadNetworkArguments(isYouTube: true)
            arguments += source.extraArguments
            arguments.append(source.target)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let outputCollector = PipeLineCollector()
            let errorCollector = PipeLineCollector()
            let progressTracker = YTDLPProgressTracker(
                expectedPartCount: 1,
                downloadCompletionProgress: 0.94,
                postProcessingProgress: 0.98
            )
            let handleProgressLines: @Sendable ([String]) -> Void = { lines in
                for line in lines {
                    if let update = progressTracker.update(from: line),
                       let progress = update.progress {
                        progressCallback?(progress)
                    }
                }
            }

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                handleProgressLines(outputCollector.append(handle.availableData))
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                handleProgressLines(errorCollector.append(handle.availableData))
            }

            try process.run()
            processRegistry.set(process)
            defer {
                processRegistry.set(nil)
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                handleProgressLines(outputCollector.finish(with: outputPipe.fileHandleForReading.readDataToEndOfFile()))
                handleProgressLines(errorCollector.finish(with: errorPipe.fileHandleForReading.readDataToEndOfFile()))
                if Task.isCancelled, process.isRunning {
                    process.terminate()
                }
            }

            process.waitUntilExit()

            if Task.isCancelled {
                processRegistry.cancelRunningProcess()
                throw CancellationError()
            }

            let output = String(data: outputCollector.data, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorCollector.data, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw RemoteImportError.downloaderFailed(
                    conciseYTDLPError(
                        errorOutput,
                        fallback: "\(source.name) 下载失败，请确认网络可访问 YouTube，且已安装 yt-dlp 和 ffmpeg"
                    )
                )
            }

            guard let downloadedURL = downloadedMusicFileURL(
                fromYTDLPOutput: output,
                destinationDirectory: destinationDirectory,
                startedAt: startedAt
            ) else {
                throw RemoteImportError.downloaderFailed(
                    conciseYTDLPError(errorOutput, fallback: "找不到已下载的音频文件")
                )
            }

            return downloadedURL
        }.value
    }

    nonisolated private static func localFFmpegDirectoryPath() -> String? {
        localFFmpegURL()?.deletingLastPathComponent().path
    }

    nonisolated private static func localFFmpegURL() -> URL? {
        [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map(URL.init(fileURLWithPath:))
    }

    nonisolated private static func downloadedMusicFileURL(
        fromYTDLPOutput output: String,
        destinationDirectory: URL,
        startedAt: Date
    ) -> URL? {
        let fm = FileManager.default
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            if fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        let audioExtensions = Set(["m4a", "mp3", "wav", "aac", "opus", "webm"])
        let urls = (try? fm.contentsOfDirectory(
            at: destinationDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true,
                      let modifiedAt = values?.contentModificationDate,
                      modifiedAt >= startedAt.addingTimeInterval(-2) else { return nil }
                return (url, modifiedAt)
            }
            .sorted { $0.1 > $1.1 }
            .first?
            .0
    }

    nonisolated private static func conciseYTDLPError(_ message: String, fallback: String) -> String {
        let lines = message
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return fallback }
        return lines.suffix(6).joined(separator: "\n")
    }

    // MARK: – Music detection helpers

    private enum MusicDetectionEvent: Sendable {
        case progress(String)
        case found(MusicRecognitionItem)
    }

    nonisolated private static func runMusicDetection(
        videoPath: String,
        onEvent: @Sendable @escaping (MusicDetectionEvent) async -> Void
    ) async throws -> [MusicRecognitionItem] {
        let processRegistry = ToolProcessRegistry()
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: [MusicRecognitionItem].self) { group in
                group.addTask {
                    try await runMusicDetectionProcess(
                        videoPath: videoPath,
                        onEvent: onEvent,
                        processRegistry: processRegistry
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 130_000_000_000)
                    processRegistry.cancelRunningProcess()
                    throw MusicDetectionError.timeout
                }

                guard let result = try await group.next() else { return [] }
                group.cancelAll()
                return result
            }
        } onCancel: {
            processRegistry.cancelRunningProcess()
        }
    }

    nonisolated private static func runMusicDetectionProcess(
        videoPath: String,
        onEvent: @Sendable @escaping (MusicDetectionEvent) async -> Void,
        processRegistry: ToolProcessRegistry
    ) async throws -> [MusicRecognitionItem] {
        guard let pythonURL = localToolURL(
            relativePath: "Tools/music-env/bin/python3",
            fallbackPath: musicPythonPath,
            mustBeExecutable: true
        ) else {
            throw MusicDetectionError.envNotSetup
        }
        guard let scriptURL = localToolURL(
            relativePath: "Tools/detect_music.py",
            fallbackPath: musicScriptPath
        ) else {
            throw MusicDetectionError.scriptMissing
        }
        guard FileManager.default.fileExists(atPath: videoPath) else {
            throw MusicDetectionError.videoMissing(videoPath)
        }
        guard FileManager.default.isReadableFile(atPath: videoPath) else {
            throw MusicDetectionError.videoUnreadable(videoPath)
        }

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [scriptURL.path, videoPath]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/opt/miniconda3/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        env["LAPIANBAO_MUSIC_MAX_SEGMENTS"] = env["LAPIANBAO_MUSIC_MAX_SEGMENTS"] ?? "12"
        env["LAPIANBAO_MUSIC_RECOGNIZE_TIMEOUT"] = env["LAPIANBAO_MUSIC_RECOGNIZE_TIMEOUT"] ?? "10"
        env["LAPIANBAO_MUSIC_ITUNES_TIMEOUT"] = env["LAPIANBAO_MUSIC_ITUNES_TIMEOUT"] ?? "3"
        env["LAPIANBAO_MUSIC_FFPROBE_TIMEOUT"] = env["LAPIANBAO_MUSIC_FFPROBE_TIMEOUT"] ?? "12"
        env["LAPIANBAO_MUSIC_FFMPEG_TIMEOUT"] = env["LAPIANBAO_MUSIC_FFMPEG_TIMEOUT"] ?? "12"
        env["LAPIANBAO_MUSIC_TOTAL_TIMEOUT"] = env["LAPIANBAO_MUSIC_TOTAL_TIMEOUT"] ?? "120"
        process.environment = env
        let errorPipe = Pipe()
        process.standardError = errorPipe

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        let errorCollector = PipeDataCollector()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorCollector.append(handle.availableData)
        }

        try process.run()
        processRegistry.set(process)
        defer {
            processRegistry.set(nil)
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
            if Task.isCancelled, process.isRunning {
                process.terminate()
            }
        }

        var songs: [MusicRecognitionItem] = []
        let stream = Self.makeLineStream(pipe: outputPipe)

        for await line in stream {
            if Task.isCancelled {
                processRegistry.cancelRunningProcess()
                throw CancellationError()
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let type = json["type"] as? String
            else { continue }

            switch type {
            case "progress":
                let msg = json["message"] as? String ?? ""
                let val = json["value"] as? Double ?? 0
                let percent = Int((min(1, max(0, val)) * 100).rounded())
                await onEvent(.progress("识别中 \(percent)% · \(msg)"))

            case "found":
                if let songDict = json["song"] as? [String: Any],
                   let song = parseMusicItem(from: songDict) {
                    songs.append(song)
                    await onEvent(.found(song))
                }

            case "done":
                if let arr = json["songs"] as? [[String: Any]] {
                    songs = arr.compactMap { parseMusicItem(from: $0) }
                }

            case "error":
                let msg = json["message"] as? String ?? "识别失败"
                processRegistry.cancelRunningProcess()
                throw MusicDetectionError.scriptError(msg)

            default:
                break
            }
        }

        process.waitUntilExit()
        if Task.isCancelled {
            processRegistry.cancelRunningProcess()
            throw CancellationError()
        }
        if process.terminationStatus != 0 {
            let err = String(data: errorCollector.data, encoding: .utf8) ?? ""
            throw MusicDetectionError.scriptError(err.isEmpty ? "音乐识别脚本退出失败" : err)
        }
        return songs
    }

    nonisolated private static func makeLineStream(pipe: Pipe) -> AsyncStream<String> {
        AsyncStream { continuation in
            let handle = pipe.fileHandleForReading
            final class Buf: @unchecked Sendable { var data = Data() }
            let buf = Buf()

            handle.readabilityHandler = { h in
                let chunk = h.availableData
                guard !chunk.isEmpty else {
                    if !buf.data.isEmpty,
                       let line = String(data: buf.data, encoding: .utf8),
                       !line.isEmpty {
                        continuation.yield(line)
                    }
                    continuation.finish()
                    h.readabilityHandler = nil
                    return
                }
                buf.data.append(chunk)
                while let nlIdx = buf.data.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineSlice = buf.data[buf.data.startIndex..<nlIdx]
                    buf.data.removeSubrange(buf.data.startIndex...nlIdx)
                    if let line = String(data: lineSlice, encoding: .utf8), !line.isEmpty {
                        continuation.yield(line)
                    }
                }
            }

            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }

    nonisolated private static func parseMusicItem(from dict: [String: Any]) -> MusicRecognitionItem? {
        guard let title = dict["title"] as? String, !title.isEmpty else { return nil }
        let artist = dict["artist"] as? String ?? ""
        let tags = dict["tags"] as? [String] ?? [artist, dict["genre"] as? String ?? ""]
        return MusicRecognitionItem(
            title: title,
            artist: artist,
            artworkURL: dict["artwork_url"] as? String ?? "",
            appleMusicURL: dict["apple_music_url"] as? String ?? "",
            detectedAt: dict["detected_at"] as? Double ?? 0,
            tags: tags
        )
    }

    enum MusicDetectionError: LocalizedError {
        case envNotSetup
        case scriptMissing
        case videoMissing(String)
        case videoUnreadable(String)
        case timeout
        case scriptError(String)

        var errorDescription: String? {
            switch self {
            case .envNotSetup:
                return "未检测到音乐识别环境。请在项目目录运行：bash Tools/setup_music_env.sh"
            case .scriptMissing:
                return "未找到音乐识别脚本：Tools/detect_music.py"
            case .videoMissing(let path):
                return "视频文件不存在或无法访问：\(path)"
            case .videoUnreadable(let path):
                return "当前运行环境无法读取视频文件：\(path)。如果这是 Xcode 预览，请重新打开素材库或使用真实 App 运行一次授权。"
            case .timeout:
                return "音乐识别超时，已停止本次识别。可以稍后重试，或换一个更短的视频片段。"
            case .scriptError(let msg):
                return msg
            }
        }
    }

    @discardableResult
    func exportTranscriptMarkdown(video: VideoItem) -> Bool {
        guard let libraryURL else { return false }
        let path = video.url.path
        if let existingJob = transcriptExportJobs[path], !existingJob.isFailed { return true }
        transcriptExportJobs.removeValue(forKey: path)
        let segments = transcriptSegmentsByVideoPath[path, default: []]
        guard !segments.isEmpty else { return false }
        let folder = Self.exportFolder(in: libraryURL, named: Self.transcriptExportFolderName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return false
        }
        let url = folder.appendingPathComponent("\(Self.safeFileStem(video.name))-transcript.md")
        let sceneCutTimes = sceneCutsByVideoPath[path, default: []].map(\.time)
        let duration = durationByVideoPath[path]
        let videoName = video.name
        let videoFileName = video.url.lastPathComponent

        transcriptExportJobs[path] = TranscriptExportJob(
            videoPath: path,
            videoName: videoName,
            progress: 0.04
        )

        Task { [weak self] in
            self?.updateTranscriptExportProgress(path: path, progress: 0.16)
            let md = await Task.detached(priority: .utility) {
                Self.transcriptExportMarkdown(
                    videoName: videoName,
                    videoFileName: videoFileName,
                    segments: segments,
                    sceneCutTimes: sceneCutTimes,
                    duration: duration
                )
            }.value

            self?.updateTranscriptExportProgress(path: path, progress: 0.78)
            let didWrite = await Task.detached(priority: .utility) {
                (try? md.write(to: url, atomically: true, encoding: .utf8)) != nil
            }.value
            guard didWrite else {
                self?.failTranscriptExport(path: path, message: "无法写入字幕 Markdown")
                return
            }

            let startTime = segments.map(\.start).min() ?? 0
            let endTime = segments.map(\.end).max() ?? startTime
            let export = TranscriptExportItem(
                videoPath: path,
                videoName: videoName,
                filePath: url.path,
                segmentCount: segments.count,
                startTime: startTime,
                endTime: endTime
            )

            if let index = self?.transcriptExports.firstIndex(where: { $0.videoPath == path }) {
                self?.transcriptExports[index] = export
            } else {
                self?.transcriptExports.append(export)
            }
            self?.saveProjectData()
            self?.updateTranscriptExportProgress(path: path, progress: 1.0)
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.transcriptExportJobs.removeValue(forKey: path)
        }

        return true
    }

    private func updateTranscriptExportProgress(path: String, progress: Double) {
        guard var job = transcriptExportJobs[path] else { return }
        guard !job.isFailed else { return }
        job.progress = Self.normalizedProgress(progress)
        transcriptExportJobs[path] = job
    }

    private func failTranscriptExport(path: String, message: String) {
        guard var job = transcriptExportJobs[path] else { return }
        job.progress = 1
        job.errorMessage = message
        transcriptExportJobs[path] = job

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { [weak self] in
                if self?.transcriptExportJobs[path]?.errorMessage == message {
                    self?.transcriptExportJobs.removeValue(forKey: path)
                }
            }
        }
    }

    nonisolated private static func transcriptExportMarkdown(
        videoName: String,
        videoFileName: String,
        segments: [TranscriptSegment],
        sceneCutTimes: [Double],
        duration: Double?
    ) -> String {
        let orderedSegments = segments.sorted {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }
        let sceneBlocks = transcriptSceneBlocks(
            segments: orderedSegments,
            sceneCutTimes: sceneCutTimes,
            duration: duration
        )
        let sceneBody = sceneBlocks.map { transcriptSceneMarkdown($0) }.joined(separator: "\n\n")
        let transcriptBody = orderedSegments
            .map { "- [\(clockText($0.start)) - \(clockText($0.end))] \(singleLineMarkdownText($0.text))" }
            .joined(separator: "\n")
        let sceneSource = sceneCutTimes.isEmpty ? "未检测到分镜切点，使用整条时间线作为单个分镜。" : "使用场景识别切点划分分镜。"

        return """
        # \(videoName)

        ## AI 分镜字幕索引

        - 视频文件：\(videoFileName)
        - 分镜数：\(sceneBlocks.count)
        - 字幕段数：\(orderedSegments.count)
        - 时间格式：HH:MM:SS 或 MM:SS
        - 分镜来源：\(sceneSource)

        \(sceneBody)

        ## 原脚本

        \(transcriptBody)
        """
    }

    nonisolated private static func transcriptSceneBlocks(
        segments: [TranscriptSegment],
        sceneCutTimes: [Double],
        duration: Double?
    ) -> [TranscriptSceneBlock] {
        let maxSegmentEnd = segments.map { max($0.start, $0.end) }.max() ?? 0
        let validDuration = duration.map { $0.isFinite && $0 > 0 ? $0 : 0 } ?? 0
        let timelineEnd = max(validDuration, maxSegmentEnd)
        let cutTimes = stableSceneCutTimes(from: sceneCutTimes)
            .filter { $0 > 0 && (timelineEnd <= 0 || $0 < timelineEnd) }
        let finalEnd = max(timelineEnd, cutTimes.last ?? 0, maxSegmentEnd)
        let boundaries = ([0] + cutTimes + [finalEnd]).filter { $0.isFinite }
        let ranges = zip(boundaries.dropLast(), boundaries.dropFirst()).filter { $0.1 >= $0.0 }

        let blocks = ranges.enumerated().map { offset, range in
            let start = range.0
            let end = max(range.1, start)
            let subtitles = segments.filter { transcriptSegment($0, overlapsSceneStart: start, end: end) }
            return TranscriptSceneBlock(index: offset + 1, start: start, end: end, subtitles: subtitles)
        }

        if !blocks.isEmpty { return blocks }
        return [
            TranscriptSceneBlock(
                index: 1,
                start: 0,
                end: max(maxSegmentEnd, 0),
                subtitles: segments
            )
        ]
    }

    nonisolated private static func transcriptSegment(_ segment: TranscriptSegment, overlapsSceneStart start: Double, end: Double) -> Bool {
        let segmentStart = max(0, segment.start)
        let segmentEnd = max(segmentStart, segment.end)
        guard end > start else {
            return segmentStart >= start
        }
        return segmentStart < end && segmentEnd > start
    }

    nonisolated private static func transcriptSceneMarkdown(_ block: TranscriptSceneBlock) -> String {
        let subtitles = block.subtitles
            .map { "- [\(clockText($0.start)) - \(clockText($0.end))] \(singleLineMarkdownText($0.text))" }
            .joined(separator: "\n")
        let subtitleBody = subtitles.isEmpty ? "- 无对应字幕" : subtitles
        return """
        ### 分镜 \(block.index) [\(clockText(block.start)) - \(clockText(block.end))]

        - scene_index: \(block.index)
        - scene_start: \(clockText(block.start))
        - scene_end: \(clockText(block.end))
        - subtitle_count: \(block.subtitles.count)

        \(subtitleBody)
        """
    }

    nonisolated private static func singleLineMarkdownText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
            let signature = videoFileSignature(for: video.url)
        else { return nil }

        guard
            entry.fileSize == signature.fileSize,
            abs(entry.modificationTime - signature.modificationTime) < 1.0
        else { return nil }

        return entry
    }

    private func storeSceneCutCache(for video: VideoItem, cuts: [SceneCut]) {
        guard let signature = videoFileSignature(for: video.url) else { return }

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
        await SceneDetectionGate.shared.acquire()
        defer {
            Task {
                await SceneDetectionGate.shared.release()
            }
        }

        guard !Task.isCancelled else { return [] }

        let detectionTask = Task.detached(priority: .utility) { () -> [SceneCut] in
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
        }
        return await detectionTask.value
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
        environment["OMP_NUM_THREADS"] = "1"
        environment["OPENBLAS_NUM_THREADS"] = "1"
        environment["MKL_NUM_THREADS"] = "1"
        environment["VECLIB_MAXIMUM_THREADS"] = "1"
        environment["NUMEXPR_NUM_THREADS"] = "1"
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputCollector = PipeDataCollector()
        let errorCollector = PipeDataCollector()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputCollector.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorCollector.append(handle.availableData)
        }

        do {
            try process.run()
            SceneDetectionProcessRegistry.shared.set(process)
            process.waitUntilExit()
            SceneDetectionProcessRegistry.shared.set(nil)
        } catch {
            SceneDetectionProcessRegistry.shared.set(nil)
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        guard process.terminationStatus == 0 else { return nil }

        guard
            let result = try? JSONDecoder().decode(TransNetDetectionResult.self, from: outputCollector.data),
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
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.06, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)

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

        return removeDuplicateThumbnailCuts(cuts)
    }

    nonisolated private static func removeDuplicateThumbnailCuts(_ cuts: [SceneCut]) -> [SceneCut] {
        guard cuts.count > 1 else { return cuts }
        var result: [SceneCut] = [cuts[0]]
        for cut in cuts.dropFirst() {
            guard let previousCut = result.last else {
                result.append(cut)
                continue
            }
            if !thumbnailsAreSimilar(previousCut.thumbnailImage, cut.thumbnailImage) {
                result.append(cut)
            }
        }
        return result
    }

    nonisolated private static func thumbnailsAreSimilar(_ a: NSImage, _ b: NSImage) -> Bool {
        let compareSize = CGSize(width: 16, height: 9)
        guard let lumaA = imageLuma(a, size: compareSize),
              let lumaB = imageLuma(b, size: compareSize) else { return false }
        let diff = zip(lumaA, lumaB).reduce(0.0) { $0 + abs($1.0 - $1.1) } / Double(lumaA.count)
        return diff < 0.03
    }

    nonisolated private static func imageLuma(_ image: NSImage, size: CGSize) -> [Double]? {
        let w = Int(size.width), h = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        guard let data = context.data else { return nil }
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        return (0..<w * h).map { i in
            let r = Double(ptr[i * 4]) / 255.0
            let g = Double(ptr[i * 4 + 1]) / 255.0
            let b = Double(ptr[i * 4 + 2]) / 255.0
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
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
            guard previous.map({ time - $0 >= 0.3 }) ?? true else { continue }
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
        guard let image = await generatedCGImage(from: generator, at: time) else { return nil }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
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

    nonisolated private final class RemoteFileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let destinationURL: URL
        private let progressCallback: (@Sendable (Double?, String?) -> Void)?
        private let lock = NSLock()
        private var continuation: CheckedContinuation<URL, Error>?
        private var session: URLSession?
        private var lastSpeedSampleDate = Date()
        private var lastSpeedSampleBytes: Int64 = 0

        init(destinationURL: URL, progressCallback: (@Sendable (Double?, String?) -> Void)?) {
            self.destinationURL = destinationURL
            self.progressCallback = progressCallback
        }

        func download(request: URLRequest) async throws -> URL {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                    lock.lock()
                    self.continuation = continuation
                    let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                    self.session = session
                    let task = session.downloadTask(with: request)
                    lock.unlock()
                    task.resume()
                }
            } onCancel: {
                cancel()
            }
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastSpeedSampleDate)
            let speed: String?
            if elapsed >= 0.45, totalBytesWritten >= lastSpeedSampleBytes {
                let bytesPerSecond = Double(totalBytesWritten - lastSpeedSampleBytes) / elapsed
                speed = Self.formatSpeed(bytesPerSecond)
                lastSpeedSampleDate = now
                lastSpeedSampleBytes = totalBytesWritten
            } else {
                speed = nil
            }
            guard totalBytesExpectedToWrite > 0 else {
                progressCallback?(nil, speed)
                return
            }
            let progress = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
            progressCallback?(progress, speed)
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            guard
                let response = downloadTask.response as? HTTPURLResponse,
                (200 ..< 300).contains(response.statusCode)
            else {
                resume(with: .failure(RemoteImportError.downloadFailed))
                return
            }

            let fileSize = ((try? FileManager.default.attributesOfItem(atPath: location.path)[.size]) as? NSNumber)?.int64Value ?? 0
            guard fileSize > 0 else {
                resume(with: .failure(RemoteImportError.downloadFailed))
                return
            }

            do {
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.moveItem(at: location, to: destinationURL)
                progressCallback?(1, nil)
                resume(with: .success(destinationURL))
            } catch {
                resume(with: .failure(error))
            }
        }

        private static func formatSpeed(_ bytesPerSecond: Double) -> String? {
            guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return nil }
            return ByteCountFormatter.string(
                fromByteCount: Int64(bytesPerSecond.rounded()),
                countStyle: .file
            ) + "/s"
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            if let error {
                resume(with: .failure(error))
            }
        }

        private func cancel() {
            lock.lock()
            let session = self.session
            lock.unlock()
            session?.invalidateAndCancel()
        }

        private func resume(with result: Result<URL, Error>) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            let session = self.session
            self.session = nil
            lock.unlock()

            session?.finishTasksAndInvalidate()
            continuation?.resume(with: result)
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

    nonisolated private struct YTDLPVideoInfo: Decodable {
        var id: String?
        var title: String?
        var description: String?
        var uploader: String?
        var uploaderID: String?
        var channel: String?
        var channelID: String?
        var creator: String?
        var playlistUploader: String?
        var playlistUploaderID: String?
        var artist: String?
        var albumArtist: String?
        var ext: String?
        var vcodec: String?
        var duration: Double?
        var requestedFormats: [YTDLPRequestedFormat]?
        var formats: [YTDLPRequestedFormat]?
        var entries: [YTDLPPlaylistEntry]?

        private enum CodingKeys: String, CodingKey {
            case id, title, description, uploader, channel, creator, artist
            case ext, vcodec, duration, formats
            case uploaderID = "uploader_id"
            case channelID = "channel_id"
            case playlistUploader = "playlist_uploader"
            case playlistUploaderID = "playlist_uploader_id"
            case albumArtist = "album_artist"
            case requestedFormats = "requested_formats"
            case entries
        }

        var bestUploader: String? {
            [
                uploader,
                channel,
                creator,
                playlistUploader,
                artist,
                albumArtist,
                uploaderID,
                channelID,
                playlistUploaderID
            ]
            .compactMap { normalizedImportTag($0 ?? "") }
            .first
        }

        var expectedDownloadPartCount: Int? {
            guard let count = requestedFormats?.count, count > 0 else { return nil }
            return min(max(count, 1), 3)
        }

        var isLikelyVideo: Bool {
            if let duration, duration > 0 {
                return true
            }
            if let vcodec,
               !vcodec.isEmpty,
               vcodec.lowercased() != "none" {
                return true
            }
            if let requestedFormats, !requestedFormats.isEmpty {
                return true
            }
            if let formats, !formats.isEmpty {
                return true
            }
            if let ext = ext?.lowercased(),
               ["mp4", "m4v", "mov", "webm"].contains(ext) {
                return true
            }
            return false
        }
    }

    nonisolated private struct YTDLPRequestedFormat: Decodable {
        var formatID: String?

        private enum CodingKeys: String, CodingKey {
            case formatID = "format_id"
        }
    }

    nonisolated private struct YTDLPPlaylistEntry: Decodable {
        var playlistIndex: Int?
        var ext: String?
        var vcodec: String?
        var duration: Double?
        var requestedFormats: [YTDLPRequestedFormat]?
        var formats: [YTDLPRequestedFormat]?

        private enum CodingKeys: String, CodingKey {
            case playlistIndex = "playlist_index"
            case ext, vcodec, duration
            case requestedFormats = "requested_formats"
            case formats
        }

        var isLikelyVideo: Bool {
            if let duration, duration > 0 {
                return true
            }
            if let vcodec,
               !vcodec.isEmpty,
               vcodec.lowercased() != "none" {
                return true
            }
            if let requestedFormats, !requestedFormats.isEmpty {
                return true
            }
            if let formats, !formats.isEmpty {
                return true
            }
            if let ext = ext?.lowercased(),
               ["mp4", "m4v", "mov", "webm"].contains(ext) {
                return true
            }
            return false
        }
    }

    nonisolated private struct YTDLPDownloaderFailure: LocalizedError {
        var message: String
        var authorName: String?

        var errorDescription: String? {
            message
        }
    }

    nonisolated private struct DownloadedVideoResult: Sendable {
        var url: URL
        var authorName: String?
        var sourceTitle: String? = nil
    }

    nonisolated private final class YTDLPProgressTracker: @unchecked Sendable {
        private let lock = NSLock()
        private let expectedPartCount: Int
        private let downloadCompletionProgress: Double
        private let postProcessingProgress: Double
        private let allowsEstimatedMultipartProgress: Bool
        private let reportsPostProcessingProgress: Bool
        private var partIndex = 0
        private var lastRawProgress = 0.0
        private var lastOverallProgress = 0.0
        private var hasSeenProgress = false

        init(
            expectedPartCount: Int,
            downloadCompletionProgress: Double = 1,
            postProcessingProgress: Double = 1,
            allowsEstimatedMultipartProgress: Bool = true,
            reportsPostProcessingProgress: Bool = true
        ) {
            self.expectedPartCount = max(1, expectedPartCount)
            self.downloadCompletionProgress = LibraryStore.normalizedProgress(downloadCompletionProgress)
            self.postProcessingProgress = LibraryStore.normalizedProgress(postProcessingProgress)
            self.allowsEstimatedMultipartProgress = allowsEstimatedMultipartProgress
            self.reportsPostProcessingProgress = reportsPostProcessingProgress
        }

        func update(from line: String) -> DownloadProgressUpdate? {
            lock.lock()
            defer { lock.unlock() }

            if LibraryStore.isYTDLPPostProcessingLine(line) {
                guard reportsPostProcessingProgress else {
                    return DownloadProgressUpdate(progress: nil, speed: nil)
                }
                lastOverallProgress = max(lastOverallProgress, postProcessingProgress)
                return DownloadProgressUpdate(progress: lastOverallProgress, speed: nil)
            }

            guard let update = LibraryStore.parseYTDLPProgressUpdate(line) else { return nil }
            guard let updateProgress = update.progress else {
                return DownloadProgressUpdate(progress: nil, speed: update.speed)
            }
            let rawProgress = LibraryStore.normalizedProgress(updateProgress)
            if hasSeenProgress,
               rawProgress + 0.12 < lastRawProgress,
               lastRawProgress > 0.65 {
                partIndex += 1
            }

            hasSeenProgress = true
            lastRawProgress = rawProgress

            guard allowsEstimatedMultipartProgress || (expectedPartCount == 1 && partIndex == 0) else {
                return DownloadProgressUpdate(progress: nil, speed: update.speed)
            }

            let partCount = max(expectedPartCount, partIndex + 1)
            let estimatedProgress = (Double(partIndex) + rawProgress) / Double(partCount) * downloadCompletionProgress
            lastOverallProgress = max(lastOverallProgress, min(downloadCompletionProgress, estimatedProgress))
            return DownloadProgressUpdate(progress: lastOverallProgress, speed: update.speed)
        }
    }

    nonisolated private static let genericImportHashtags: Set<String> = [
        "foryou", "fyp", "viral", "edit", "edits", "sfx", "cinematic", "cinematography",
        "filmmaking", "filmmaker", "photography", "videography", "video", "reels", "reel",
        "colorgrading", "colourgrading", "sounddesign"
    ]

    nonisolated private static func downloadVideo(
        from sourceURL: URL,
        into libraryURL: URL,
        platform: String,
        endpoint: String,
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil,
        transcodingCallback: (@Sendable (Double?) -> Void)? = nil,
        finalizingCallback: (@Sendable (Double) -> Void)? = nil,
        processCallback: (@Sendable (Process?) -> Void)? = nil
    ) async throws -> DownloadedVideoResult {
        let destinationDirectory = mediaFolder(in: libraryURL, named: videoFolderName)

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        var rawURL: URL?
        var authorName: String?
        var sourceTitle: String?

        var ytdlpFailure: Error?

        // 1. yt-dlp（YouTube / Bilibili / 抖音完美，Instagram / 小红书公开内容也能用）
        if rawURL == nil, let ytdlp = localYTDLPURL(),
           !Task.isCancelled {
            let attempts = ytdlpArgumentAttempts(for: sourceURL)
            for attempt in attempts {
                do {
                    let result = try await runYTDLPOnce(
                        executableURL: ytdlp,
                        sourceURL: sourceURL,
                        destinationDirectory: destinationDirectory,
                        extraArguments: attempt.arguments,
                        progressCallback: progressCallback,
                        processCallback: processCallback
                    )
                    rawURL = result.url
                    authorName = result.authorName
                    sourceTitle = result.sourceTitle
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if let failure = error as? YTDLPDownloaderFailure {
                        authorName = authorName ?? failure.authorName
                    }
                    ytdlpFailure = error
                }
            }
            if rawURL == nil, let ytdlpFailure, isHardYouTubeYTDLPFailure(ytdlpFailure) {
                throw ytdlpFailure
            }
        }

        // 2. 小红书：原生页面解析（yt-dlp 对需要登录的内容失效时接手）
        if rawURL == nil, platform == "小红书",
           let result = try? await downloadXiaoHongShuNative(
               from: sourceURL,
               destinationDirectory: destinationDirectory,
               progressCallback: progressCallback
           ) {
            rawURL = result.url
            authorName = authorName ?? result.authorName
            sourceTitle = sourceTitle ?? result.sourceTitle
        }

        // 3. 用户自定义 API
        if rawURL == nil,
           instagramCarouselItemIndex(from: sourceURL) == nil,
           !endpoint.isEmpty,
           let result = try? await importViaConfiguredAPI(
               sourceURL: sourceURL,
               endpoint: endpoint,
               destinationDirectory: destinationDirectory,
               progressCallback: progressCallback
           ) {
            rawURL = result
            sourceTitle = sourceTitle ?? Self.sourceTitle(from: [], fileName: result.lastPathComponent)
        }

        // 4. cobalt.tools 兜底（对 Instagram / YouTube 有效，需要服务可用）
        if rawURL == nil,
           let result = try? await importViaCobalt(
               sourceURL: sourceURL,
               destinationDirectory: destinationDirectory,
               progressCallback: progressCallback
           ) {
            rawURL = result
            sourceTitle = sourceTitle ?? Self.sourceTitle(from: [], fileName: result.lastPathComponent)
        }

        guard let downloadedURL = rawURL else {
            if isYouTubeURL(sourceURL), let ytdlpFailure {
                throw ytdlpFailure
            }
            throw RemoteImportError.downloaderFailed("所有下载方式均失败，请确认链接是否可公开访问")
        }

        // 后处理：VP9 / AV1 在 MP4 容器中不被 macOS AVFoundation 支持，转码为 H.264
        finalizingCallback?(0)
        let finalURL = await transcodeToH264IfNeeded(downloadedURL, progressCallback: transcodingCallback) ?? downloadedURL
        finalizingCallback?(1)
        return DownloadedVideoResult(
            url: finalURL,
            authorName: authorName,
            sourceTitle: sourceTitle ?? Self.sourceTitle(from: [], fileName: finalURL.lastPathComponent)
        )
    }

    // MARK: - VP9/AV1 → H.264 转码（解决 macOS 播放兼容性）

    nonisolated private static func transcodeToH264IfNeeded(
        _ url: URL,
        progressCallback: (@Sendable (Double?) -> Void)? = nil
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
            let probeErrorPipe = Pipe()
            probeProcess.standardOutput = probePipe
            probeProcess.standardError = probeErrorPipe
            probeErrorPipe.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }

            guard (try? probeProcess.run()) != nil else {
                probeErrorPipe.fileHandleForReading.readabilityHandler = nil
                return nil
            }
            probeProcess.waitUntilExit()
            probeErrorPipe.fileHandleForReading.readabilityHandler = nil

            let codec = (String(
                data: probePipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            // macOS AVFoundation 在 MP4 容器中不支持 VP9 / AV1 / VP8
            let unsupported = ["vp9", "vp09", "av1", "av01", "vp8"]
            guard unsupported.contains(codec) else { return nil }

            // 通知 UI 进入转码阶段
            progressCallback?(nil)

            // 找 ffmpeg
            let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
            guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else { return nil }
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0

            // 先输出到临时文件，避免和原文件重名冲突
            let stem = url.deletingPathExtension().lastPathComponent
            let tmpURL = url.deletingLastPathComponent()
                .appendingPathComponent("\(stem).transcoding.tmp.mp4")

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
                "-progress", "pipe:1",
                "-nostats",
                "-y",
                tmpURL.path
            ]
            let progressPipe = Pipe()
            let ffmpegErrorPipe = Pipe()
            ffmpegProcess.standardOutput = progressPipe
            ffmpegProcess.standardError = ffmpegErrorPipe

            let progressCollector = PipeDataCollector()
            progressPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                progressCollector.append(chunk)
                guard duration.isFinite, duration > 0,
                      let text = String(data: chunk, encoding: .utf8) else { return }
                for line in text.components(separatedBy: .newlines) {
                    guard line.hasPrefix("out_time_ms="),
                          let rawValue = Double(line.dropFirst("out_time_ms=".count)) else { continue }
                    progressCallback?(min(0.995, max(0, rawValue / 1_000_000 / duration)))
                }
            }
            ffmpegErrorPipe.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }

            guard (try? ffmpegProcess.run()) != nil else {
                progressPipe.fileHandleForReading.readabilityHandler = nil
                ffmpegErrorPipe.fileHandleForReading.readabilityHandler = nil
                return nil
            }
            ffmpegProcess.waitUntilExit()
            progressPipe.fileHandleForReading.readabilityHandler = nil
            ffmpegErrorPipe.fileHandleForReading.readabilityHandler = nil
            progressCollector.append(progressPipe.fileHandleForReading.readDataToEndOfFile())

            guard
                ffmpegProcess.terminationStatus == 0,
                FileManager.default.fileExists(atPath: tmpURL.path)
            else {
                try? FileManager.default.removeItem(at: tmpURL)
                return nil
            }
            progressCallback?(1)

            let finalURL = url.deletingLastPathComponent()
                .appendingPathComponent("\(stem).mp4")
            if finalURL.path != url.path {
                try? FileManager.default.removeItem(at: finalURL)
            }
            try? FileManager.default.removeItem(at: url)
            if (try? FileManager.default.moveItem(at: tmpURL, to: finalURL)) != nil {
                return finalURL
            }
            try? FileManager.default.removeItem(at: tmpURL)
            return nil
        }.value
    }

    // MARK: - 小红书原生解析器

    nonisolated private static func downloadRemoteFile(
        request: URLRequest,
        to outputURL: URL,
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil
    ) async throws -> URL {
        progressCallback?(nil, nil)
        let downloader = RemoteFileDownloader(destinationURL: outputURL, progressCallback: progressCallback)
        return try await downloader.download(request: request)
    }

    nonisolated private static func downloadXiaoHongShuNative(
        from sourceURL: URL,
        destinationDirectory: URL,
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil
    ) async throws -> DownloadedVideoResult {
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

        let authorName = xiaoHongShuAuthorName(from: noteObj)
        let sourceTitle = screenedSourceTitle(
            rawTitle: noteObj["title"] as? String,
            description: noteObj["desc"] as? String,
            sourceURL: sourceURL
        )
        let outputURL = cleanedImportVideoURL(
            in: destinationDirectory,
            sourceURL: sourceURL,
            rawTitle: noteObj["title"] as? String,
            description: noteObj["desc"] as? String,
            uploader: authorName,
            preferredExtension: "mp4"
        )
        let fileURL = try await downloadRemoteFile(
            request: dlReq,
            to: outputURL,
            progressCallback: progressCallback
        )
        return DownloadedVideoResult(
            url: fileURL,
            authorName: normalizedImportTag(authorName ?? ""),
            sourceTitle: sourceTitle
        )
    }

    nonisolated private static func xiaoHongShuAuthorName(from noteObject: [String: Any]) -> String? {
        for containerKey in ["user", "userInfo", "author", "owner"] {
            guard let container = noteObject[containerKey] as? [String: Any] else { continue }
            for nameKey in ["nickname", "nickName", "name", "userName", "username", "userId", "user_id"] {
                if let value = container[nameKey] as? String,
                   let author = normalizedImportTag(value) {
                    return author
                }
            }
        }

        for nameKey in ["nickname", "nickName", "userName", "username"] {
            if let value = noteObject[nameKey] as? String,
               let author = normalizedImportTag(value) {
                return author
            }
        }
        return nil
    }

    nonisolated private static func localYTDLPURL() -> URL? {
        var paths = [String]()
        if let appManagedPath = appManagedYTDLPURL()?.path {
            paths.append(appManagedPath)
        }
        paths += [
            // Conda 版保留为回退，适合 Homebrew Python 兼容性异常的机器。
            "/opt/miniconda3/bin/yt-dlp",
            "/opt/anaconda3/bin/yt-dlp",
            // Homebrew 版常见，但如果 Python 环境异常会卡住；下面会做短超时健康检查。
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        return paths.first {
            FileManager.default.isExecutableFile(atPath: $0)
                && isResponsiveYTDLP(at: URL(fileURLWithPath: $0))
        }
            .map(URL.init(fileURLWithPath:))
    }

    nonisolated private static func isResponsiveYTDLP(at url: URL, timeout: TimeInterval = 5) -> Bool {
        let process = Process()
        process.executableURL = url
        process.arguments = ["--version"]
        process.environment = downloaderProcessEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            if process.isRunning {
                process.terminate()
            }
            return false
        }

        return process.terminationStatus == 0
    }

    nonisolated private static func loadDownloaderSelfCheckReport() -> DownloaderSelfCheckReport {
        guard
            let data = UserDefaults.standard.data(forKey: downloaderSelfCheckReportKey),
            let report = try? JSONDecoder().decode(DownloaderSelfCheckReport.self, from: data)
        else {
            return DownloaderSelfCheckReport()
        }
        return report.status == .running ? DownloaderSelfCheckReport() : report
    }

    nonisolated private static func saveDownloaderSelfCheckReport(_ report: DownloaderSelfCheckReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        UserDefaults.standard.set(data, forKey: downloaderSelfCheckReportKey)
    }

    nonisolated private static func isDownloaderSelfCheckFresh(_ report: DownloaderSelfCheckReport) -> Bool {
        guard report.status == .succeeded,
              let checkedAt = report.checkedAt
        else { return false }
        return Calendar.current.isDateInToday(checkedAt)
    }

    nonisolated private struct DownloaderSelfCheckProcessResult: Sendable {
        var terminationStatus: Int32?
        var didTimeOut: Bool = false
        var output: String = ""
        var errorOutput: String = ""

        var succeeded: Bool { terminationStatus == 0 && !didTimeOut }
    }

    nonisolated private struct DownloaderAutoRepairResult: Sendable {
        var didAttemptRepair = false
        var steps: [String] = []

        var summary: String {
            guard !steps.isEmpty else { return "未找到可自动更新渠道" }
            return steps.suffix(4).joined(separator: "；")
        }
    }

    nonisolated private static func runDownloaderSelfCheck(startedAt: Date) async -> DownloaderSelfCheckReport {
        await Task.detached(priority: .utility) {
            let initialReport = runDownloaderSelfCheckOnce(startedAt: startedAt)
            guard initialReport.status == .failed else {
                return await reportByAddingExternalServiceChecks(to: initialReport)
            }

            let repairResult = runDownloaderAutoRepair()
            guard repairResult.didAttemptRepair else {
                var report = initialReport
                report.message = "\(initialReport.message)\n自动修复：\(repairResult.summary)"
                return await reportByAddingExternalServiceChecks(to: report)
            }

            var repairedReport = runDownloaderSelfCheckOnce(startedAt: Date())
            if repairedReport.status == .succeeded {
                repairedReport.message = "\(repairedReport.message)\n自动修复：\(repairResult.summary)"
                return await reportByAddingExternalServiceChecks(to: repairedReport)
            }

            repairedReport.message = "自动修复后仍失败：\(repairedReport.message)\n修复记录：\(repairResult.summary)"
            return await reportByAddingExternalServiceChecks(to: repairedReport)
        }.value
    }

    nonisolated private static func runDownloaderSelfCheckOnce(startedAt: Date) -> DownloaderSelfCheckReport {
        guard let ytdlp = localYTDLPURL() else {
            return DownloaderSelfCheckReport(
                status: .failed,
                checkedAt: startedAt,
                message: "未找到 yt-dlp"
            )
        }

        let versionResult = runDownloaderSelfCheckProcess(
            executableURL: ytdlp,
            arguments: ["--version"],
            timeout: 10
        )
        let version = firstNonEmptyLine(in: versionResult.output)
        guard versionResult.succeeded, version != nil else {
            return DownloaderSelfCheckReport(
                status: .failed,
                checkedAt: startedAt,
                message: "yt-dlp 无法启动：\(selfCheckFailureMessage(from: versionResult, fallback: "请检查 yt-dlp 安装"))",
                ytdlpPath: ytdlp.path,
                ytdlpVersion: version
            )
        }

        guard let ffmpegURL = localFFmpegURL() else {
            return DownloaderSelfCheckReport(
                status: .failed,
                checkedAt: startedAt,
                message: "未找到 ffmpeg",
                ytdlpPath: ytdlp.path,
                ytdlpVersion: version
            )
        }

        var failures: [String] = []
        for attempt in ytdlpYouTubeArgumentAttempts() {
            let probeResult = runDownloaderSelfCheckProcess(
                executableURL: ytdlp,
                arguments: downloaderSelfCheckYouTubeProbeArguments(extraArguments: attempt.arguments),
                timeout: attempt.arguments.contains("--remote-components") ? 60 : 45
            )
            let outputLine = firstNonEmptyLine(in: probeResult.output)
            if probeResult.succeeded,
               let outputLine,
               let title = downloaderSelfCheckYouTubeProbeTitle(from: outputLine) {
                let label = attempt.label.isEmpty ? "默认线路" : attempt.label
                return DownloaderSelfCheckReport(
                    status: .succeeded,
                    checkedAt: startedAt,
                    message: "自检通过：YouTube 解析正常（\(label)）",
                    ytdlpPath: ytdlp.path,
                    ytdlpVersion: version,
                    ffmpegPath: ffmpegURL.path,
                    youtubeProbeTitle: title
                )
            }

            let label = attempt.label.isEmpty ? "默认线路" : attempt.label
            failures.append("\(label)：\(selfCheckFailureMessage(from: probeResult, fallback: "YouTube 解析失败"))")
        }

        return DownloaderSelfCheckReport(
            status: .failed,
            checkedAt: startedAt,
            message: failures.suffix(2).joined(separator: "\n"),
            ytdlpPath: ytdlp.path,
            ytdlpVersion: version,
            ffmpegPath: ffmpegURL.path
        )
    }

    nonisolated private static func reportByAddingExternalServiceChecks(
        to report: DownloaderSelfCheckReport
    ) async -> DownloaderSelfCheckReport {
        async let appleMusicCheck = httpServiceSelfCheck(
            key: "appleMusicSearch",
            title: "Apple Music 搜索",
            url: appleMusicSelfCheckURL(),
            timeout: 8,
            successStatusUpperBound: 300,
            failureIsWarning: false
        )
        async let cobaltCheck = httpServiceSelfCheck(
            key: "cobalt",
            title: "Cobalt 下载兜底",
            url: URL(string: "https://api.cobalt.tools/"),
            timeout: 8,
            successStatusUpperBound: 500,
            failureIsWarning: false
        )
        async let xiaohongshuCheck = httpServiceSelfCheck(
            key: "xiaohongshuWeb",
            title: "小红书网页抓取",
            url: URL(string: "https://www.xiaohongshu.com/explore"),
            timeout: 8,
            successStatusUpperBound: 500,
            failureIsWarning: false
        )
        async let customImportAPICheck = configuredImportAPIServiceSelfCheck()
        async let ollamaCheck = ollamaServiceSelfCheck()

        var checks: [ExternalServiceSelfCheckItem] = [
            ytdlpServiceSelfCheckItem(from: report),
            ffmpegServiceSelfCheckItem(from: report),
            youtubeServiceSelfCheckItem(from: report),
            chromeCookieImportSelfCheck()
        ]

        checks.append(await appleMusicCheck)
        checks.append(await cobaltCheck)
        checks.append(await xiaohongshuCheck)
        if let customImportAPICheck = await customImportAPICheck {
            checks.append(customImportAPICheck)
        }
        checks.append(await ollamaCheck)

        var enriched = report
        enriched.serviceChecks = checks

        let failures = checks.filter { $0.status == .failed }
        let warnings = checks.filter { $0.status == .warning }
        if !failures.isEmpty {
            enriched.status = .failed
            let summary = failures
                .prefix(3)
                .map { "\($0.title)：\($0.message)" }
                .joined(separator: "；")
            enriched.message = "外部服务自检发现 \(failures.count) 项异常：\(summary)"
        } else if warnings.isEmpty {
            enriched.status = .succeeded
            enriched.message = "外部服务自检通过"
        } else if enriched.status == .succeeded {
            enriched.message = "核心下载自检通过，\(warnings.count) 项可选服务未就绪"
        }

        return enriched
    }

    nonisolated private static func ytdlpServiceSelfCheckItem(from report: DownloaderSelfCheckReport) -> ExternalServiceSelfCheckItem {
        if let path = report.ytdlpPath {
            let version = report.ytdlpVersion.map { " · \($0)" } ?? ""
            return ExternalServiceSelfCheckItem(
                key: "ytdlp",
                title: "yt-dlp 下载器",
                status: .succeeded,
                message: "\(path)\(version)"
            )
        }
        return ExternalServiceSelfCheckItem(
            key: "ytdlp",
            title: "yt-dlp 下载器",
            status: .failed,
            message: "未找到或无法启动，已尝试自动安装/更新"
        )
    }

    nonisolated private static func ffmpegServiceSelfCheckItem(from report: DownloaderSelfCheckReport) -> ExternalServiceSelfCheckItem {
        if let path = report.ffmpegPath {
            return ExternalServiceSelfCheckItem(
                key: "ffmpeg",
                title: "ffmpeg 转码器",
                status: .succeeded,
                message: path
            )
        }
        return ExternalServiceSelfCheckItem(
            key: "ffmpeg",
            title: "ffmpeg 转码器",
            status: .failed,
            message: "未找到 ffmpeg，下载后转码/合并可能失败"
        )
    }

    nonisolated private static func youtubeServiceSelfCheckItem(from report: DownloaderSelfCheckReport) -> ExternalServiceSelfCheckItem {
        if let title = report.youtubeProbeTitle {
            return ExternalServiceSelfCheckItem(
                key: "youtube",
                title: "YouTube 抓取",
                status: .succeeded,
                message: title
            )
        }
        return ExternalServiceSelfCheckItem(
            key: "youtube",
            title: "YouTube 抓取",
            status: .failed,
            message: singleLineRepairMessage(report.message)
        )
    }

    nonisolated private static func appleMusicSelfCheckURL() -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "test"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "country", value: "CN")
        ]
        return components?.url
    }

    nonisolated private static func configuredImportAPIServiceSelfCheck() async -> ExternalServiceSelfCheckItem? {
        let endpoint = UserDefaults.standard.string(forKey: instagramImportEndpointDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !endpoint.isEmpty else { return nil }
        return await httpServiceSelfCheck(
            key: "customImportAPI",
            title: "自定义导入 API",
            url: URL(string: endpoint),
            timeout: 8,
            successStatusUpperBound: 500,
            failureIsWarning: false
        )
    }

    nonisolated private static func httpServiceSelfCheck(
        key: String,
        title: String,
        url: URL?,
        timeout: TimeInterval,
        successStatusUpperBound: Int,
        failureIsWarning: Bool
    ) async -> ExternalServiceSelfCheckItem {
        guard let url else {
            return ExternalServiceSelfCheckItem(
                key: key,
                title: title,
                status: failureIsWarning ? .warning : .failed,
                message: "地址无效"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ExternalServiceSelfCheckItem(
                    key: key,
                    title: title,
                    status: failureIsWarning ? .warning : .failed,
                    message: "没有收到 HTTP 响应"
                )
            }
            let statusCode = httpResponse.statusCode
            if (200..<successStatusUpperBound).contains(statusCode) {
                return ExternalServiceSelfCheckItem(
                    key: key,
                    title: title,
                    status: .succeeded,
                    message: "HTTP \(statusCode)"
                )
            }
            return ExternalServiceSelfCheckItem(
                key: key,
                title: title,
                status: failureIsWarning ? .warning : .failed,
                message: "HTTP \(statusCode)"
            )
        } catch {
            return ExternalServiceSelfCheckItem(
                key: key,
                title: title,
                status: failureIsWarning ? .warning : .failed,
                message: singleLineRepairMessage(error.localizedDescription)
            )
        }
    }

    nonisolated private static func chromeCookieImportSelfCheck() -> ExternalServiceSelfCheckItem {
        var missingTools: [String] = []
        if localYTDLPURL() == nil {
            missingTools.append("yt-dlp")
        }
        if localCurlURL() == nil {
            missingTools.append("curl")
        }

        return ExternalServiceSelfCheckItem(
            key: "chromeCookieImport",
            title: "Chrome 收藏后台读取",
            status: missingTools.isEmpty ? .succeeded : .failed,
            message: missingTools.isEmpty
                ? "使用已登录 Cookie 后台读取，不打开浏览器窗口"
                : "缺少 \(missingTools.joined(separator: "、"))，无法后台读取 Chrome Cookie"
        )
    }

    nonisolated private static func ollamaServiceSelfCheck() async -> ExternalServiceSelfCheckItem {
        await httpServiceSelfCheck(
            key: "ollama",
            title: "Ollama 本地分析",
            url: URL(string: "http://127.0.0.1:11434/api/tags"),
            timeout: 3,
            successStatusUpperBound: 300,
            failureIsWarning: true
        )
    }

    nonisolated private static func runDownloaderAutoRepair() -> DownloaderAutoRepairResult {
        var result = DownloaderAutoRepairResult()

        if let ytdlp = localYTDLPURL() {
            appendDownloaderRepairStep(
                name: "清理 yt-dlp 缓存",
                commandResult: runDownloaderSelfCheckProcess(
                    executableURL: ytdlp,
                    arguments: ["--rm-cache-dir"],
                    timeout: 20
                ),
                to: &result
            )

            appendDownloaderRepairStep(
                name: "更新 yt-dlp nightly 通道",
                commandResult: runDownloaderSelfCheckProcess(
                    executableURL: ytdlp,
                    arguments: ["--update-to", "nightly"],
                    timeout: 120
                ),
                to: &result
            )
        }

        if let brew = localBrewURL() {
            appendDownloaderRepairStep(
                name: "更新 Homebrew 索引",
                commandResult: runDownloaderSelfCheckProcess(
                    executableURL: brew,
                    arguments: ["update", "--quiet"],
                    timeout: 180
                ),
                to: &result
            )

            let upgradeResult = runDownloaderSelfCheckProcess(
                executableURL: brew,
                arguments: ["upgrade", "yt-dlp"],
                timeout: 240
            )
            appendDownloaderRepairStep(name: "升级 Homebrew yt-dlp", commandResult: upgradeResult, to: &result)

            if !upgradeResult.succeeded {
                appendDownloaderRepairStep(
                    name: "安装 Homebrew yt-dlp",
                    commandResult: runDownloaderSelfCheckProcess(
                        executableURL: brew,
                        arguments: ["install", "yt-dlp"],
                        timeout: 240
                    ),
                    to: &result
                )
            }
        }

        if let curl = localCurlURL() {
            appendDownloaderRepairStep(
                name: "安装应用内 nightly 下载器",
                commandResult: installAppManagedNightlyYTDLP(using: curl),
                to: &result
            )
        }

        if let python = ytdlpPythonURL() {
            appendDownloaderRepairStep(
                name: "升级 Python 下载组件",
                commandResult: runDownloaderSelfCheckProcess(
                    executableURL: python,
                    arguments: [
                        "-m", "pip", "install",
                        "--upgrade",
                        "--pre",
                        "yt-dlp[default]",
                        "yt-dlp-ejs"
                    ],
                    timeout: 240
                ),
                to: &result
            )
        }

        return result
    }

    nonisolated private static func appendDownloaderRepairStep(
        name: String,
        commandResult: DownloaderSelfCheckProcessResult,
        to result: inout DownloaderAutoRepairResult
    ) {
        result.didAttemptRepair = true
        if commandResult.succeeded {
            result.steps.append("\(name)完成")
        } else {
            let message = selfCheckFailureMessage(from: commandResult, fallback: "失败")
            result.steps.append("\(name)未完成：\(singleLineRepairMessage(message))")
        }
    }

    nonisolated private static func singleLineRepairMessage(_ message: String) -> String {
        let collapsed = message
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        return String(collapsed.prefix(160))
    }

    nonisolated private static func localBrewURL() -> URL? {
        [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map(URL.init(fileURLWithPath:))
    }

    nonisolated private static func localCurlURL() -> URL? {
        [
            "/usr/bin/curl",
            "/opt/homebrew/bin/curl",
            "/usr/local/bin/curl"
        ]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map(URL.init(fileURLWithPath:))
    }

    nonisolated private static func appSupportToolsDirectoryURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LapianBao", isDirectory: true)
            .appendingPathComponent("Tools", isDirectory: true)
    }

    nonisolated private static func appManagedYTDLPURL() -> URL? {
        appSupportToolsDirectoryURL()?.appendingPathComponent("yt-dlp")
    }

    nonisolated private static func installAppManagedNightlyYTDLP(using curl: URL) -> DownloaderSelfCheckProcessResult {
        guard let toolsDirectory = appSupportToolsDirectoryURL(),
              let targetURL = appManagedYTDLPURL()
        else {
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 1,
                didTimeOut: false,
                output: "",
                errorOutput: "无法创建应用工具目录"
            )
        }

        let temporaryURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent(".yt-dlp.download")
        do {
            try FileManager.default.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: temporaryURL)
        } catch {
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 1,
                didTimeOut: false,
                output: "",
                errorOutput: error.localizedDescription
            )
        }

        let downloadResult = runDownloaderSelfCheckProcess(
            executableURL: curl,
            arguments: [
                "-L",
                "--fail",
                "--silent",
                "--show-error",
                "--retry", "2",
                "--connect-timeout", "15",
                "-o", temporaryURL.path,
                downloaderNightlyMacOSURL
            ],
            timeout: 180
        )
        guard downloadResult.succeeded else { return downloadResult }

        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporaryURL.path)
            try? FileManager.default.removeItem(at: targetURL)
            try FileManager.default.moveItem(at: temporaryURL, to: targetURL)
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 0,
                didTimeOut: false,
                output: "已安装到 \(targetURL.path)",
                errorOutput: ""
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            return DownloaderSelfCheckProcessResult(
                terminationStatus: 1,
                didTimeOut: false,
                output: "",
                errorOutput: error.localizedDescription
            )
        }
    }

    nonisolated private static func ytdlpPythonURL() -> URL? {
        guard let ytdlp = localYTDLPURL(),
              let firstLine = try? String(contentsOf: ytdlp, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .first
        else { return nil }

        let shebang = String(firstLine)
        guard shebang.hasPrefix("#!") else { return nil }
        let path = shebang.dropFirst(2)
            .split(separator: " ")
            .first
            .map(String.init) ?? ""
        let loweredPath = path.lowercased()
        guard !loweredPath.contains("/cellar/yt-dlp/") else { return nil }
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    nonisolated private static func downloaderSelfCheckYouTubeProbeArguments(extraArguments: [String]) -> [String] {
        var arguments = [
            "--no-playlist",
            "--skip-download",
            "--no-warnings",
            "--print", "%(id)s|%(title)s"
        ]
        arguments += ytdlpProbeNetworkArguments(isYouTube: true)
        arguments += ytdlpFormatSelectionArguments()
        arguments += extraArguments
        arguments.append(downloaderSelfCheckProbeURL)
        return arguments
    }

    nonisolated private static func runDownloaderSelfCheckProcess(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> DownloaderSelfCheckProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = downloaderProcessEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputCollector = PipeDataCollector()
        let errorCollector = PipeDataCollector()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputCollector.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorCollector.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return DownloaderSelfCheckProcessResult(
                terminationStatus: nil,
                output: "",
                errorOutput: error.localizedDescription
            )
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        let didTimeOut = semaphore.wait(timeout: .now() + timeout) == .timedOut
        if didTimeOut, process.isRunning {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 2)
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        return DownloaderSelfCheckProcessResult(
            terminationStatus: didTimeOut ? nil : process.terminationStatus,
            didTimeOut: didTimeOut,
            output: String(data: outputCollector.data, encoding: .utf8) ?? "",
            errorOutput: String(data: errorCollector.data, encoding: .utf8) ?? ""
        )
    }

    nonisolated private static func downloaderSelfCheckYouTubeProbeTitle(from outputLine: String) -> String? {
        let parts = outputLine.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              isValidYouTubeVideoID(parts[0])
        else { return nil }
        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    nonisolated private static func selfCheckFailureMessage(
        from result: DownloaderSelfCheckProcessResult,
        fallback: String
    ) -> String {
        if result.didTimeOut { return "超时" }
        let message = [result.errorOutput, result.output]
            .map { conciseYTDLPError($0, fallback: "") }
            .first(where: { !$0.isEmpty })
        return message ?? fallback
    }

    nonisolated private static func firstNonEmptyLine(in text: String) -> String? {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    nonisolated private static func ytdlpFormatSelectionArguments() -> [String] {
        [
            "-f", "bv*[vcodec^=avc1]+ba/b[ext=mp4]/bestvideo+bestaudio/best",
            "-S", "res,codec:h264:m4a",
            "--merge-output-format", "mp4"
        ]
    }

    nonisolated private static func runYTDLPOnce(
        executableURL: URL,
        sourceURL: URL,
        destinationDirectory: URL,
        extraArguments: [String] = [],
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil,
        processCallback: (@Sendable (Process?) -> Void)? = nil
    ) async throws -> DownloadedVideoResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            defer { processCallback?(nil) }
            process.executableURL = executableURL

            // 确保 yt-dlp 能找到 ffmpeg（App 启动时 PATH 不完整）
            let env = downloaderProcessEnvironment()
            process.environment = env

            progressCallback?(nil, nil)
            let selectedPlaylistItemIndex = instagramCarouselItemIndex(from: sourceURL)
            let downloaderSourceURL = ytdlpSourceURL(for: sourceURL)

            let videoInfo = fetchYTDLPVideoInfo(
                executableURL: executableURL,
                sourceURL: sourceURL,
                environment: env,
                extraArguments: extraArguments
            )
            let authorName = normalizedImportTag(videoInfo?.bestUploader ?? "")
            let sourceTitle = screenedSourceTitle(
                rawTitle: videoInfo?.title,
                description: videoInfo?.description,
                sourceURL: sourceURL
            )
            let expectedPartCount = videoInfo?.expectedDownloadPartCount ?? 2
            let progressTracker = YTDLPProgressTracker(
                expectedPartCount: expectedPartCount,
                allowsEstimatedMultipartProgress: true,
                reportsPostProcessingProgress: false
            )
            let baseOutputURL = cleanedImportVideoURL(
                in: destinationDirectory,
                sourceURL: sourceURL,
                rawTitle: videoInfo?.title,
                description: videoInfo?.description,
                uploader: videoInfo?.bestUploader,
                preferredExtension: "mp4"
            )
            let outputURL = selectedPlaylistItemIndex.map {
                uniqueImportVideoURL(
                    in: destinationDirectory,
                    stem: "\(baseOutputURL.deletingPathExtension().lastPathComponent) 分段 \($0)",
                    preferredExtension: "mp4"
                )
            } ?? baseOutputURL
            let outputTemplate = "\(outputURL.deletingPathExtension().lastPathComponent).%(ext)s"

            var arguments = ytdlpPlaylistSelectionArguments(for: sourceURL) + [
                "--progress",   // 非 TTY 环境也强制输出进度
                "--newline",    // 每次进度更新输出新行，便于实时解析
                "--no-colors",  // 去掉 ANSI 转义码，方便文本解析
                "--user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            ]
            arguments += ytdlpDownloadNetworkArguments(isYouTube: isYouTubeURL(downloaderSourceURL))
            if let ffmpegDirectoryPath = localFFmpegDirectoryPath() {
                arguments += ["--ffmpeg-location", ffmpegDirectoryPath]
            }
            arguments += ytdlpFormatSelectionArguments()
            arguments += extraArguments
            if isBilibiliURL(sourceURL) {
                arguments += [
                    "--referer", "https://www.bilibili.com/",
                    "--extractor-args", "bilibili:prefer_multi_flv=False"
                ]
            }
            arguments += [
                "--paths", destinationDirectory.path,
                "-o", outputTemplate,
                "--print", "after_move:filepath",
                downloaderSourceURL.absoluteString
            ]
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let outputCollector = PipeLineCollector()
            let errorCollector = PipeLineCollector()
            let handleProgressLines: @Sendable ([String]) -> Void = { lines in
                for line in lines {
                    if let update = progressTracker.update(from: line) {
                        progressCallback?(update.progress, update.speed)
                    }
                }
            }

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                handleProgressLines(outputCollector.append(handle.availableData))
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                handleProgressLines(errorCollector.append(handle.availableData))
            }

            try process.run()
            processCallback?(process)
            process.waitUntilExit()

            // nil 掉 handler（内部会等当前 handler 执行完毕），再排空剩余数据
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            handleProgressLines(outputCollector.finish(with: outputPipe.fileHandleForReading.readDataToEndOfFile()))
            handleProgressLines(errorCollector.finish(with: errorPipe.fileHandleForReading.readDataToEndOfFile()))

            let output = String(
                data: outputCollector.data,
                encoding: .utf8
            ) ?? ""
            let errorOutput = String(data: errorCollector.data, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw YTDLPDownloaderFailure(message: errorOutput, authorName: authorName)
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
                throw YTDLPDownloaderFailure(message: errorOutput, authorName: authorName)
            }

            return DownloadedVideoResult(
                url: URL(fileURLWithPath: outputPath),
                authorName: authorName,
                sourceTitle: sourceTitle
            )
        }.value
    }

    nonisolated private static func downloaderProcessEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/opt/miniconda3/bin:/opt/anaconda3/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        return env
    }

    nonisolated private static func fetchYTDLPVideoInfo(
        executableURL: URL,
        sourceURL: URL,
        environment: [String: String],
        extraArguments: [String] = []
    ) -> YTDLPVideoInfo? {
        let process = Process()
        process.executableURL = executableURL
        process.environment = environment
        let downloaderSourceURL = ytdlpSourceURL(for: sourceURL)
        var arguments = ytdlpPlaylistSelectionArguments(for: sourceURL) + [
            "--skip-download",
            "--dump-single-json",
            "--no-warnings",
        ]
        arguments += ytdlpProbeNetworkArguments(isYouTube: isYouTubeURL(downloaderSourceURL))
        arguments += ytdlpFormatSelectionArguments()
        arguments += extraArguments
        arguments += [
            downloaderSourceURL.absoluteString
        ]
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputCollector = PipeDataCollector()
        let errorCollector = PipeDataCollector()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputCollector.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorCollector.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 35) == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
        guard process.terminationStatus == 0 else { return nil }
        return try? JSONDecoder().decode(YTDLPVideoInfo.self, from: outputCollector.data)
    }

    nonisolated private struct YTDLPArgumentAttempt: Sendable {
        var label: String = ""
        var arguments: [String]
    }

    nonisolated private static func ytdlpArgumentAttempts(for sourceURL: URL) -> [YTDLPArgumentAttempt] {
        if isYouTubeURL(sourceURL) {
            return ytdlpYouTubeArgumentAttempts()
        }
        if isInstagramURL(sourceURL) {
            return [
                YTDLPArgumentAttempt(label: "本地解析", arguments: []),
                YTDLPArgumentAttempt(label: "Chrome Cookie", arguments: ["--cookies-from-browser", "chrome"])
            ]
        }
        return [YTDLPArgumentAttempt(arguments: [])]
    }

    nonisolated private static func ytdlpYouTubeArgumentAttempts() -> [YTDLPArgumentAttempt] {
        return [
            YTDLPArgumentAttempt(label: "本地解析", arguments: []),
            YTDLPArgumentAttempt(label: "备用客户端", arguments: ytdlpYouTubeClientArguments()),
            YTDLPArgumentAttempt(label: "本地代理", arguments: ["--proxy", "http://127.0.0.1:1082"]),
            YTDLPArgumentAttempt(label: "代理备用客户端", arguments: ["--proxy", "http://127.0.0.1:1082"] + ytdlpYouTubeClientArguments()),
            YTDLPArgumentAttempt(label: "Safari Cookie", arguments: ["--cookies-from-browser", "safari"] + ytdlpYouTubeClientArguments()),
            YTDLPArgumentAttempt(label: "远程组件", arguments: ["--remote-components", "ejs:github"] + ytdlpYouTubeClientArguments())
        ]
    }

    nonisolated private static func ytdlpYouTubeClientArguments() -> [String] {
        ["--extractor-args", "youtube:player_client=web_safari,mweb,android_vr"]
    }

    nonisolated private static func ytdlpProbeNetworkArguments(isYouTube: Bool) -> [String] {
        var arguments = [
            "--socket-timeout", "15",
            "--retries", "1",
            "--extractor-retries", "1"
        ]
        if isYouTube {
            arguments += ["--sleep-requests", "0.35"]
        }
        return arguments
    }

    nonisolated private static func ytdlpDownloadNetworkArguments(isYouTube: Bool) -> [String] {
        var arguments = [
            "--socket-timeout", "25",
            "--retries", "5",
            "--fragment-retries", "8",
            "--extractor-retries", "2",
            "--retry-sleep", "http:linear=1::1",
            "--retry-sleep", "fragment:exp=1:8"
        ]
        if isYouTube {
            arguments += ["--sleep-requests", "0.75"]
        }
        return arguments
    }

    nonisolated private static func isHardYouTubeYTDLPFailure(_ error: Error) -> Bool {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lowercased = message.lowercased()
        return lowercased.contains("video unavailable")
            || lowercased.contains("private video")
            || lowercased.contains("this video is unavailable")
            || lowercased.contains("not available in your country")
    }

    nonisolated private static func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtube.com" || host == "www.youtube.com"
            || host == "m.youtube.com" || host == "youtu.be"
            || host == "music.youtube.com"
    }

    nonisolated private static func isInstagramURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
            || host == "instagr.am" || host.hasSuffix(".instagr.am")
    }

    nonisolated private static func isBilibiliURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("bilibili.com") || host == "b23.tv"
    }

    nonisolated private static func remoteThumbnailData(for sourceURL: URL) async -> Data? {
        guard let ytdlp = localYTDLPURL() else { return nil }

        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = ytdlp
            process.environment = downloaderProcessEnvironment()
            let downloaderSourceURL = ytdlpSourceURL(for: sourceURL)
            var arguments = ytdlpPlaylistSelectionArguments(for: sourceURL) + [
                "--skip-download",
                "--print", "thumbnail",
                "--no-warnings",
            ]
            arguments += ytdlpProbeNetworkArguments(isYouTube: isYouTubeURL(downloaderSourceURL))
            arguments += ytdlpArgumentAttempts(for: sourceURL).first?.arguments ?? []
            arguments += [
                downloaderSourceURL.absoluteString
            ]
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let outputCollector = PipeDataCollector()
            let errorCollector = PipeDataCollector()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                outputCollector.append(handle.availableData)
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                errorCollector.append(handle.availableData)
            }

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                return nil
            }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
            errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

            guard process.terminationStatus == 0 else { return nil }

            let output = String(data: outputCollector.data, encoding: .utf8) ?? ""
            guard
                let thumbnail = output
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") }),
                let thumbnailURL = URL(string: thumbnail)
            else { return nil }

            return await fetchRemoteImageData(from: thumbnailURL)
        }.value
    }

    nonisolated private static func fetchRemoteImageData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard data.count <= 12_000_000 else { return nil }
            if let httpResponse = response as? HTTPURLResponse {
                guard (200..<300).contains(httpResponse.statusCode) else { return nil }
            }
            return data
        } catch {
            return nil
        }
    }

    /// 解析 yt-dlp 进度行，如 "[download]  45.6% of 1.23MiB at 2.34MiB/s ETA 00:12"
    nonisolated private static func parseYTDLPProgressLine(_ line: String) -> Double? {
        parseYTDLPProgressUpdate(line)?.progress
    }

    nonisolated private static func parseYTDLPProgressUpdate(_ line: String) -> DownloadProgressUpdate? {
        guard line.contains("[download]"), line.contains("%") else { return nil }
        // 忽略 "Destination:" 等非进度行
        guard !line.contains("Destination:"),
              !line.contains("already been downloaded"),
              !line.contains("Merging") else { return nil }
        let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for token in tokens where token.hasSuffix("%") {
            if let value = Double(token.dropLast()), value >= 0 {
                return DownloadProgressUpdate(
                    progress: min(1.0, value / 100.0),
                    speed: parseYTDLPSpeed(from: line)
                )
            }
        }
        return nil
    }

    nonisolated private static func isYTDLPPostProcessingLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains("[merger]")
            || lowercased.contains("[extractaudio]")
            || lowercased.contains("[fixup")
            || lowercased.contains("[movefiles]")
            || lowercased.contains("[videoconvertor]")
            || lowercased.contains("[videoremuxer]")
            || lowercased.contains("merging formats")
    }

    nonisolated private static func parseYTDLPSpeed(from line: String) -> String? {
        let pattern = #"\bat\s+([^\s]+/s)\b"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let range = Range(match.range(at: 1), in: line)
        else { return nil }
        let speed = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return speed.isEmpty || speed == "Unknown/s" ? nil : speed
    }

    nonisolated private static func importViaConfiguredAPI(
        sourceURL: URL,
        endpoint: String,
        destinationDirectory: URL,
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil
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
        let sourceFilename = remoteFilename.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        let outputURL = cleanedImportVideoURL(
            in: destinationDirectory,
            sourceURL: sourceURL,
            rawTitle: fileStem(from: sourceFilename),
            description: nil,
            uploader: nil,
            preferredExtension: fileExtension(from: sourceFilename, fallback: "mp4")
        )

        var downloadRequest = URLRequest(url: resolved.downloadURL)
        downloadRequest.timeoutInterval = 180
        return try await downloadRemoteFile(
            request: downloadRequest,
            to: outputURL,
            progressCallback: progressCallback
        )
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
        destinationDirectory: URL,
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil
    ) async throws -> URL {
        guard let cobaltEndpoint = URL(string: "https://api.cobalt.tools/") else {
            throw RemoteImportError.downloaderMissing
        }
        let selectedPlaylistItemIndex = instagramCarouselItemIndex(from: sourceURL)
        let requestSourceURL = ytdlpSourceURL(for: sourceURL)

        var request = URLRequest(url: cobaltEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(
            CobaltRequest(url: requestSourceURL.absoluteString)
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
            let pickerItems = cobalt.picker ?? []
            let videoItems = pickerItems.filter { $0.type == "video" }
            let selectedItem: CobaltResponse.CobaltPickerItem?
            if let selectedPlaylistItemIndex {
                let pickerOffset = selectedPlaylistItemIndex - 1
                if pickerItems.indices.contains(pickerOffset), pickerItems[pickerOffset].type == "video" {
                    selectedItem = pickerItems[pickerOffset]
                } else if videoItems.indices.contains(pickerOffset) {
                    selectedItem = videoItems[pickerOffset]
                } else {
                    selectedItem = nil
                }
            } else {
                selectedItem = videoItems.first ?? pickerItems.first
            }
            guard let item = selectedItem
            else { throw RemoteImportError.invalidAPIResponse }
            downloadURL = item.url
        default:
            throw RemoteImportError.downloaderFailed("cobalt.tools 无法解析该链接，请安装 yt-dlp 后重试")
        }

        let fallbackName = downloadURL.lastPathComponent.isEmpty
            ? "instagram-\(UUID().uuidString).mp4"
            : downloadURL.lastPathComponent
        let sourceFilename = cobalt.filename ?? fallbackName
        let baseOutputURL = cleanedImportVideoURL(
            in: destinationDirectory,
            sourceURL: sourceURL,
            rawTitle: fileStem(from: sourceFilename),
            description: nil,
            uploader: nil,
            preferredExtension: fileExtension(from: sourceFilename, fallback: "mp4")
        )
        let outputURL = selectedPlaylistItemIndex.map {
            uniqueImportVideoURL(
                in: destinationDirectory,
                stem: "\(baseOutputURL.deletingPathExtension().lastPathComponent) 分段 \($0)",
                preferredExtension: fileExtension(from: sourceFilename, fallback: "mp4")
            )
        } ?? baseOutputURL

        var downloadRequest = URLRequest(url: downloadURL)
        downloadRequest.timeoutInterval = 180
        return try await downloadRemoteFile(
            request: downloadRequest,
            to: outputURL,
            progressCallback: progressCallback
        )
    }

    nonisolated private static func sanitizedFilename(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let components = name.components(separatedBy: forbidden)
        let sanitized = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "instagram-\(UUID().uuidString).mp4" : sanitized
    }

    nonisolated private static func cleanedImportVideoURL(
        in directory: URL,
        sourceURL: URL,
        rawTitle: String?,
        description: String?,
        uploader: String?,
        preferredExtension: String
    ) -> URL {
        let stem = cleanImportVideoStem(
            rawTitle: rawTitle,
            description: description,
            uploader: uploader,
            sourceURL: sourceURL
        )
        return uniqueImportVideoURL(in: directory, stem: stem, preferredExtension: preferredExtension)
    }

    nonisolated private static func cleanImportVideoStem(
        rawTitle: String?,
        description: String?,
        uploader: String?,
        sourceURL: URL
    ) -> String {
        let title = stripTrailingSourceID(normalizedSpaces(rawTitle ?? ""))
        var candidate = isGenericImportTitle(title) ? "" : title

        if candidate.isEmpty {
            candidate = cleanImportDescription(description ?? "")
        }
        if candidate.isEmpty {
            candidate = stripTrailingSourceID(normalizedSpaces(uploader ?? ""))
        }
        if candidate.isEmpty {
            candidate = sourceURL.host?.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression) ?? "Imported Video"
        }

        return compactImportFileStem(sanitizeImportFileStem(candidate), maxLength: 118)
    }

    nonisolated private static func cleanImportDescription(_ rawValue: String) -> String {
        let normalized = normalizedSpaces(rawValue)
        guard !normalized.isEmpty else { return "" }

        let markerPatterns = [
            #"\bcomment\s+[“"']?"#,
            #"\bkomen\s+[“"']?"#,
            #"\bdm\s+"#,
            #"\bif you don"#,
            #"\blink in (my )?bio"#,
            #"\bfollow for\b"#
        ]
        var cutIndex = normalized.endIndex
        for pattern in markerPatterns {
            if let range = normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                if range.lowerBound < cutIndex {
                    cutIndex = range.lowerBound
                }
            }
        }

        var cleaned = String(normalized[..<cutIndex])
            .replacingOccurrences(of: #"@[A-Za-z0-9_.]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"#[^\s#]+"#, with: " ", options: .regularExpression)
        cleaned = normalizedSpaces(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))

        if cleaned.count < 8 {
            cleaned = usefulHashtagImportTitle(from: rawValue)
        }
        if cleaned.count > 96,
           let sentenceRange = cleaned.range(of: #"^.{12,90}?[。.!?！？]"#, options: .regularExpression) {
            cleaned = String(cleaned[sentenceRange])
        }

        return stripTrailingSourceID(String(cleaned.prefix(96))).trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
    }

    nonisolated private static func usefulHashtagImportTitle(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"#([^\s#]+)"#) else { return "" }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        var values: [String] = []

        for match in regex.matches(in: text, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: text) else { continue }
            let rawTag = String(text[tagRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?，。；：！？、)]}）】》>\"'“”‘’"))
            let lowercased = rawTag.lowercased()
            guard !rawTag.isEmpty,
                  !genericImportHashtags.contains(lowercased),
                  seen.insert(lowercased).inserted
            else { continue }
            values.append(titleCasedImportTag(rawTag))
        }

        return values.prefix(3).joined(separator: " ")
    }

    nonisolated private static func titleCasedImportTag(_ tag: String) -> String {
        tag
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map { word in
                guard let first = word.first else { return "" }
                return String(first).uppercased() + String(word.dropFirst())
            }
            .joined(separator: " ")
    }

    nonisolated private static func isGenericImportTitle(_ title: String) -> Bool {
        let lowercased = title.lowercased()
        return title.isEmpty
            || lowercased == "video"
            || lowercased == "untitled"
            || lowercased.hasPrefix("video by ")
            || lowercased.hasPrefix("instagram reel")
    }

    nonisolated private static func sanitizeImportFileStem(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let sanitized = stripTrailingSourceID(name)
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .replacingOccurrences(of: "｜", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        return sanitized.isEmpty ? "Imported Video" : sanitized
    }

    nonisolated private static func stripTrailingSourceID(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+\[(?:BV[0-9A-Za-z]+|[A-Za-z0-9_-]{11})\]\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func normalizedSpaces(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func compactImportFileStem(_ stem: String, maxLength: Int) -> String {
        guard stem.count > maxLength else { return stem }
        let suffix = stem.suffix(12)
        let prefixCount = max(1, maxLength - suffix.count - 3)
        let prefix = String(stem.prefix(prefixCount)).trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        return "\(prefix) - \(suffix)"
    }

    nonisolated private static func uniqueImportVideoURL(in directory: URL, stem: String, preferredExtension: String) -> URL {
        let cleanExtension = preferredExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let fileExtension = cleanExtension.isEmpty ? "mp4" : cleanExtension
        var candidate = directory.appendingPathComponent("\(stem).\(fileExtension)")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem) - \(String(format: "%02d", suffix)).\(fileExtension)")
            suffix += 1
        }

        return candidate
    }

    nonisolated private static func fileStem(from filename: String) -> String {
        let lastComponent = filename.components(separatedBy: CharacterSet(charactersIn: "/\\")).last ?? filename
        return URL(fileURLWithPath: lastComponent).deletingPathExtension().lastPathComponent
    }

    nonisolated private static func fileExtension(from filename: String, fallback: String) -> String {
        let lastComponent = filename.components(separatedBy: CharacterSet(charactersIn: "/\\")).last ?? filename
        let ext = URL(fileURLWithPath: lastComponent).pathExtension
        return ext.isEmpty ? fallback : ext
    }

    func loadMetadataIfNeeded(for video: VideoItem) {
        let path = video.url.path
        guard videos.contains(where: { $0.url.path == path }) else { return }
        guard metadataByVideoPath[path] == nil || playbackSupportByVideoPath[path] == nil else { return }
        guard !thumbnailLoadingPaths.contains(path) else { return }

        let generation = thumbnailLoadGeneration
        thumbnailLoadingPaths.insert(path)
        let task = Task.detached(priority: .utility) { [weak self, video] in
            let path = video.url.path
            async let metadata = Self.makeVideoMetadata(for: video.url)
            async let playbackSupport = Self.playbackSupport(for: video.url)
            let videoMetadata = await metadata
            let support = await playbackSupport

            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.thumbnailLoadGeneration == generation,
                      self.thumbnailLoadingPaths.contains(path),
                      self.videos.contains(where: { $0.url.path == path })
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

    private func loadThumbnails(for videos: [VideoItem], workerCount: Int = 3) {
        thumbnailWorkerTasks.forEach { $0.cancel() }
        thumbnailWorkerTasks.removeAll()
        metadataRefreshTask?.cancel()
        metadataRefreshTask = nil
        thumbnailLoadingPaths.removeAll()
        thumbnailLoadGeneration += 1
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
        thumbnailDataByVideoPath.removeAll()
        thumbnailImageByVideoPath.removeAll()
        durationByVideoPath.removeAll()
        metadataByVideoPath.removeAll()
        playbackSupportByVideoPath.removeAll()
        waveformSamplesByVideoPath.removeAll()
        frameStripByVideoPath.removeAll()
        frameStripImagesByVideoPath.removeAll()
        sceneStripImagesByVideoPath.removeAll()
        sceneCutsByVideoPath.removeAll()
        sceneCutProgressesByVideoPath.removeAll()
        sceneThumbnailVersionsByVideoPath.removeAll()
        sceneDetectionProgress.removeAll()

        guard !videos.isEmpty, workerCount > 0 else { return }
        let generation = thumbnailLoadGeneration
        let queue = VideoMetadataQueue(videos: videos)
        thumbnailLoadingPaths = Set(videos.map { $0.url.path })

        for _ in 0..<min(max(1, workerCount), videos.count) {
            let task = Task.detached(priority: .utility) { [weak self, queue] in
                while !Task.isCancelled {
                    guard let video = await queue.next() else { break }
                    let path = video.url.path
                    async let metadata = Self.makeVideoMetadata(for: video.url)
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

    private func scheduleDeferredMetadataLoad(for videos: [VideoItem], after delay: TimeInterval, workerCount: Int) {
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
                    guard self.metadataByVideoPath[path] == nil || self.playbackSupportByVideoPath[path] == nil else { return false }
                    return !self.thumbnailLoadingPaths.contains(path)
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
                            async let metadata = Self.makeVideoMetadata(for: video.url)
                            async let playbackSupport = Self.playbackSupport(for: video.url)
                            let videoMetadata = await metadata
                            let support = await playbackSupport

                            guard !Task.isCancelled else { break }
                            await MainActor.run { [weak self] in
                                guard let self,
                                      self.thumbnailLoadGeneration == generation,
                                      self.thumbnailLoadingPaths.contains(path),
                                      self.videos.contains(where: { $0.url.path == path })
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

    private func applyVideoMetadata(
        _ videoMetadata: (thumbnailData: Data?, duration: Double?, metadata: VideoMetadata),
        playbackSupport: VideoPlaybackSupport,
        for path: String
    ) {
        objectWillChange.send()

        if let data = videoMetadata.thumbnailData {
            thumbnailDataByVideoPath[path] = data
            thumbnailImageByVideoPath[path] = NSImage(data: data)
            updateSceneStripImages(for: path)
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

        if sortOption.dependsOnMetadata {
            scheduleMetadataDependentRefresh()
        }
    }

    nonisolated private static func playbackSupport(for url: URL) async -> VideoPlaybackSupport {
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
            guard let image = await renderFrameImageSynchronously(for: url, at: seconds) else { return nil }
            return jpegData(from: image)
        }.value
    }

    nonisolated private static func renderFrameImage(for url: URL, at seconds: Double) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            await renderFrameImageSynchronously(for: url, at: seconds)
        }.value
    }

    nonisolated private static func renderFrameImageSynchronously(for url: URL, at seconds: Double) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 4096, height: 4096)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)
        return await sceneThumbnailImage(from: generator, at: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
    }

    nonisolated private static func jpegData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }

    nonisolated private static func frameDragItemProvider(
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

    nonisolated private static func renderFrameDragFile(
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

    nonisolated private static func fullResolutionJPEGData(for url: URL, at seconds: Double) async -> Data? {
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

    nonisolated private static func generatedCGImage(from generator: AVAssetImageGenerator, at time: CMTime) async -> CGImage? {
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

    nonisolated private static func frameDragFilename(videoName: String, time: Double, kind: SampledFrame.Kind?) -> String {
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

    nonisolated private static func cleanOldFrameDragExports(in folderURL: URL) {
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

    nonisolated private static func frameDragError() -> NSError {
        NSError(
            domain: "LapianBao.FrameDragExport",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "无法导出这张画面"]
        )
    }

    private func saveImageExport(data: Data, video: VideoItem, time: Double, preferredExtension: String) -> URL? {
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

    private func imageExportDestination(for video: VideoItem) -> URL {
        let folder = libraryURL.map {
            Self.mediaFolder(in: $0, named: Self.imageExportFolderName)
        } ?? video.url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    nonisolated private static func uniqueExportURL(in folder: URL, baseName: String, preferredExtension: String) -> URL {
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

    nonisolated private static func compactFileStem(_ name: String, maxLength: Int) -> String {
        let stem = safeFileStem(name)
        guard stem.count > maxLength else { return stem }
        let end = stem.suffix(12)
        let prefixCount = max(1, maxLength - end.count - 1)
        return "\(stem.prefix(prefixCount))-\(end)"
    }

    private func writeFrameIndex() {
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

    nonisolated private static func exportAudioClipFile(video: VideoItem, videoName: String, start: Double, end: Double, libraryURL: URL?) async -> URL? {
        await Task.detached(priority: .utility) {
            guard let libraryURL else { return nil }
            let folder = mediaFolder(in: libraryURL, named: soundEffectExportFolderName)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let outputURL = folder.appendingPathComponent("\(safeFileStem(videoName))_\(fileTimecode(start))-\(fileTimecode(end)).m4a")
            try? FileManager.default.removeItem(at: outputURL)

            let asset = AVURLAsset(url: video.url)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return nil }
            session.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )

            do {
                try await session.export(to: outputURL, as: .m4a)
                return outputURL
            } catch {
                return nil
            }
        }.value
    }

    nonisolated private static func runWhisperTranscription(
        video: VideoItem,
        videoName: String,
        libraryURL: URL?,
        progressCallback: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> [TranscriptSegment] {
        try await Task.detached(priority: .utility) {
            progressCallback?(0.01, "准备字幕分析")
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
            try process.run()
            process.waitUntilExit()
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
        }.value
    }

    nonisolated private struct WhisperProgressUpdate: Sendable {
        let progress: Double
        let message: String
    }

    nonisolated private static func parseWhisperProgressUpdate(_ line: String) -> WhisperProgressUpdate? {
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

    nonisolated private static func parsePercentValue(from line: String) -> Double? {
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

    nonisolated private static func trimmedProcessLog(_ message: String, fallback: String) -> String {
        let lines = message
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let tail = lines.suffix(12).joined(separator: "\n")
        return tail.isEmpty ? fallback : tail
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

    nonisolated private static func cleanTranscriptSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
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

    nonisolated private static func mergeShortGaps(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
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

    nonisolated private static func collapseRepeatedSentences(in text: String) -> String {
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

    nonisolated private static func transcriptRepeatKey(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[[:punct:][:symbol:]，。！？；：“”‘’、（）《》【】—…·]"#, with: "", options: .regularExpression)
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

    nonisolated private static func makeWaveformSamples(
        for url: URL,
        sampleCount: Int,
        start: Double? = nil,
        end: Double? = nil
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

            while !Task.isCancelled,
                  reader.status == .reading,
                  let sampleBuffer = output.copyNextSampleBuffer() {
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
            return downsample(peaks, to: sampleCount)
        }

        return await withTaskCancellationHandler(operation: {
            await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    nonisolated private static func forEachFloat32Sample(in data: Data, _ body: (Float32) -> Void) {
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
