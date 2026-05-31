//
//  LibraryStore+RemoteDownloadTypes.swift
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
    // MARK: - 统一下载入口

    nonisolated struct YTDLPVideoInfo: Decodable {
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

        enum CodingKeys: String, CodingKey {
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

    nonisolated struct YTDLPRequestedFormat: Decodable {
        var formatID: String?

        enum CodingKeys: String, CodingKey {
            case formatID = "format_id"
        }
    }

    nonisolated struct YTDLPPlaylistEntry: Decodable {
        var playlistIndex: Int?
        var ext: String?
        var vcodec: String?
        var duration: Double?
        var requestedFormats: [YTDLPRequestedFormat]?
        var formats: [YTDLPRequestedFormat]?

        enum CodingKeys: String, CodingKey {
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

    nonisolated struct YTDLPDownloaderFailure: LocalizedError {
        var message: String
        var authorName: String?

        var errorDescription: String? {
            message
        }
    }

    nonisolated struct DownloadedVideoResult: Sendable {
        var url: URL
        var authorName: String?
        var sourceTitle: String? = nil
    }

    nonisolated final class YTDLPProgressTracker: @unchecked Sendable {
        let lock = NSLock()
        let expectedPartCount: Int
        let downloadCompletionProgress: Double
        let postProcessingProgress: Double
        let allowsEstimatedMultipartProgress: Bool
        let reportsPostProcessingProgress: Bool
        var partIndex = 0
        var lastRawProgress = 0.0
        var lastOverallProgress = 0.0
        var hasSeenProgress = false

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

    nonisolated static let genericImportHashtags: Set<String> = [
        "foryou", "fyp", "viral", "edit", "edits", "sfx", "cinematic", "cinematography",
        "filmmaking", "filmmaker", "photography", "videography", "video", "reels", "reel",
        "colorgrading", "colourgrading", "sounddesign"
    ]

}
