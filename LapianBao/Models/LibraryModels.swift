//
//  LibraryModels.swift
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

nonisolated struct VideoItem: Identifiable, Hashable, Sendable {
    let url: URL
    var id: String { url.standardizedFileURL.path }

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

nonisolated enum VideoSortDirection: String, CaseIterable, Identifiable, Codable, Sendable {
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

struct VideoMetadata: Codable, Equatable, Sendable {
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
    var filePath: String? = nil
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
    var problemLocation: String?
    var repairSummary: String?
    var progress: Double?
    var serviceChecks: [ExternalServiceSelfCheckItem] = []

    var isRunning: Bool { status == .running }

    private enum CodingKeys: String, CodingKey {
        case status, checkedAt, message, ytdlpPath, ytdlpVersion, ffmpegPath, youtubeProbeTitle
        case problemLocation, repairSummary, progress, serviceChecks
    }

    nonisolated init(
        status: Status = .idle,
        checkedAt: Date? = nil,
        message: String = "未自检",
        ytdlpPath: String? = nil,
        ytdlpVersion: String? = nil,
        ffmpegPath: String? = nil,
        youtubeProbeTitle: String? = nil,
        problemLocation: String? = nil,
        repairSummary: String? = nil,
        progress: Double? = nil,
        serviceChecks: [ExternalServiceSelfCheckItem] = []
    ) {
        self.status = status
        self.checkedAt = checkedAt
        self.message = message
        self.ytdlpPath = ytdlpPath
        self.ytdlpVersion = ytdlpVersion
        self.ffmpegPath = ffmpegPath
        self.youtubeProbeTitle = youtubeProbeTitle
        self.problemLocation = problemLocation
        self.repairSummary = repairSummary
        self.progress = progress
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
        problemLocation = try container.decodeIfPresent(String.self, forKey: .problemLocation)
        repairSummary = try container.decodeIfPresent(String.self, forKey: .repairSummary)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
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
        try container.encodeIfPresent(problemLocation, forKey: .problemLocation)
        try container.encodeIfPresent(repairSummary, forKey: .repairSummary)
        try container.encodeIfPresent(progress, forKey: .progress)
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
    var duration: Double
    var tags: [String] = []

    nonisolated init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        artworkURL: String,
        appleMusicURL: String,
        detectedAt: Double,
        duration: Double = 0,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.appleMusicURL = appleMusicURL
        self.detectedAt = detectedAt
        self.duration = duration.isFinite && duration > 0 ? duration : 0
        self.tags = Self.cleanedMusicTags(tags, title: title, artist: artist)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist
        case artworkURL = "artwork_url"
        case appleMusicURL = "apple_music_url"
        case detectedAt = "detected_at"
        case duration
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
        let decodedDuration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        duration = decodedDuration.isFinite && decodedDuration > 0 ? decodedDuration : 0
        let decodedTags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        tags = Self.cleanedMusicTags(decodedTags, title: title, artist: artist)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encode(artworkURL, forKey: .artworkURL)
        try container.encode(appleMusicURL, forKey: .appleMusicURL)
        try container.encode(detectedAt, forKey: .detectedAt)
        if duration.isFinite && duration > 0 {
            try container.encode(duration, forKey: .duration)
        }
        try container.encode(tags, forKey: .tags)
    }

}

nonisolated struct AppleMusicSearchResult: Identifiable, Codable, Equatable, Sendable {
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

    nonisolated func asMusicRecognitionItem() -> MusicRecognitionItem {
        MusicRecognitionItem(
            title: title,
            artist: artist,
            artworkURL: artworkURL,
            appleMusicURL: appleMusicURL,
            detectedAt: 0,
            duration: duration,
            tags: MusicRecognitionItem.cleanedGenreTags([genre], title: title, artist: artist)
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
    var createdAt: Date? = nil
    var modifiedAt: Date?
    var recognizedSong: MusicRecognitionItem? = nil

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

struct LocalImageAsset: Identifiable, Codable, Equatable, Sendable {
    var filePath: String
    var title: String
    var fileExtension: String
    var tags: [String]
    var fileSize: Int64
    var modifiedAt: Date?
    var width: Int?
    var height: Int?

    var id: String { filePath }
}

struct MusicDownloadJob: Identifiable, Codable, Equatable, Sendable {
    enum DownloadType: String, CaseIterable, Codable, Equatable, Sendable {
        case original
        case instrumental

        nonisolated var label: String { self == .original ? "原曲" : "伴奏" }
        nonisolated var searchSuffix: String { self == .original ? "" : " instrumental" }
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

    nonisolated init(
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

enum VideoPlaybackSupport: Codable, Equatable, Sendable {
    case playable
    case unsupported(String)

    var message: String? {
        if case let .unsupported(message) = self {
            return message
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case message
    }

    private enum Status: String, Codable {
        case playable
        case unsupported
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(Status.self, forKey: .status)
        switch status {
        case .playable:
            self = .playable
        case .unsupported:
            self = .unsupported(try container.decodeIfPresent(String.self, forKey: .message) ?? "")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .playable:
            try container.encode(Status.playable, forKey: .status)
        case let .unsupported(message):
            try container.encode(Status.unsupported, forKey: .status)
            try container.encode(message, forKey: .message)
        }
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
    var batchID: UUID? = nil
    var batchTitle: String? = nil
    var batchTotalCount: Int? = nil
    var batchIndex: Int? = nil
    var status: Status
    var downloadProgress: Double? // nil = 不确定；0.0–1.0 = 已知进度
    var downloadSpeed: String? = nil
    var outputPath: String? = nil
    var thumbnailData: Data? = nil
    var candidateTitle: String? = nil
    var candidateAuthorName: String? = nil
}
