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
        var thumbnail: String?
        var thumbnails: [YTDLPThumbnail]?
        var ext: String?
        var vcodec: String?
        var duration: Double?
        var requestedFormats: [YTDLPRequestedFormat]?
        var formats: [YTDLPRequestedFormat]?
        var entries: [YTDLPPlaylistEntry]?

        enum CodingKeys: String, CodingKey {
            case id, title, description, uploader, channel, creator, artist
            case ext, vcodec, duration, formats, thumbnail, thumbnails
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
                albumArtist
            ]
            .compactMap { normalizedSourceAuthorName($0 ?? "") }
            .first
        }

        var expectedDownloadPartCount: Int? {
            guard let count = requestedFormats?.count, count > 0 else { return nil }
            return min(max(count, 1), 3)
        }

        var expectedDownloadPartByteCounts: [Double] {
            guard let requestedFormats,
                  let expectedDownloadPartCount,
                  expectedDownloadPartCount > 1
            else { return [] }

            let byteCounts = requestedFormats
                .prefix(expectedDownloadPartCount)
                .compactMap(\.expectedByteCount)
            return byteCounts.count == expectedDownloadPartCount ? byteCounts : []
        }

        var bestThumbnailURL: URL? {
            var candidates: [String] = []
            if let thumbnail {
                candidates.append(thumbnail)
            }
            candidates += Array((thumbnails ?? []).compactMap(\.url).reversed())
            return candidates
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .compactMap(URL.init(string:))
                .first { url in
                    guard let scheme = url.scheme?.lowercased() else { return false }
                    return scheme == "http" || scheme == "https"
                }
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
        var filesize: Double?
        var filesizeApprox: Double?

        enum CodingKeys: String, CodingKey {
            case formatID = "format_id"
            case filesize
            case filesizeApprox = "filesize_approx"
        }

        var expectedByteCount: Double? {
            for value in [filesize, filesizeApprox] {
                if let value, value.isFinite, value > 0 {
                    return value
                }
            }
            return nil
        }
    }

    nonisolated struct YTDLPThumbnail: Decodable {
        var url: String?
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

    nonisolated struct RemoteImportCandidateMetadata: Sendable {
        var title: String?
        var authorName: String?
        var thumbnailData: Data?

        var hasAnyValue: Bool {
            title?.isEmpty == false
                || authorName?.isEmpty == false
                || thumbnailData != nil
        }
    }

    nonisolated final class YTDLPProgressTracker: @unchecked Sendable {
        let lock = NSLock()
        private(set) var expectedPartCount: Int
        let downloadCompletionProgress: Double
        let postProcessingProgress: Double
        let allowsEstimatedMultipartProgress: Bool
        let reportsPostProcessingProgress: Bool
        private(set) var expectedPartByteCounts: [Double]
        var observedPartByteCounts: [Int: Double] = [:]
        var observedPartDownloadedBytes: [Int: Double] = [:]
        var partIndex = 0
        var lastRawProgress = 0.0
        var lastDownloadedBytes = 0.0
        var lastOverallProgress = 0.0
        var hasSeenProgress = false

        init(
            expectedPartCount: Int,
            downloadCompletionProgress: Double = 1,
            postProcessingProgress: Double = 1,
            expectedPartByteCounts: [Double] = [],
            allowsEstimatedMultipartProgress: Bool = true,
            reportsPostProcessingProgress: Bool = true
        ) {
            let resolvedExpectedPartCount = max(1, expectedPartCount)
            self.expectedPartCount = resolvedExpectedPartCount
            self.downloadCompletionProgress = LibraryStore.normalizedProgress(downloadCompletionProgress)
            self.postProcessingProgress = LibraryStore.normalizedProgress(postProcessingProgress)
            self.expectedPartByteCounts = Array(expectedPartByteCounts.prefix(resolvedExpectedPartCount))
                .map { max(0, $0) }
            self.allowsEstimatedMultipartProgress = allowsEstimatedMultipartProgress
            self.reportsPostProcessingProgress = reportsPostProcessingProgress
        }

        /// 免探测快速启动路径:下载进程在正式下载前打印选中的分片信息,
        /// 在收到第一条进度前用它补齐部件数和字节权重。
        func noteExpectedParts(count: Int, byteCounts: [Double]) {
            lock.lock()
            defer { lock.unlock() }
            guard !hasSeenProgress else { return }
            let resolvedCount = max(1, count)
            expectedPartCount = resolvedCount
            expectedPartByteCounts = Array(byteCounts.prefix(resolvedCount)).map { max(0, $0) }
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
            guard update.progress != nil || update.downloadedBytes != nil else {
                return DownloadProgressUpdate(progress: nil, speed: update.speed)
            }

            let initialTotalBytes = resolvedTotalBytes(for: partIndex, updateTotalBytes: update.totalBytes)
            let initialDownloadedBytes = resolvedDownloadedBytes(
                updateDownloadedBytes: update.downloadedBytes,
                updateProgress: update.progress,
                totalBytes: initialTotalBytes
            )
            let rawProgress = resolvedRawProgress(
                updateProgress: update.progress,
                downloadedBytes: initialDownloadedBytes,
                totalBytes: initialTotalBytes
            )

            var advancedPart = false
            if hasSeenProgress,
               shouldAdvancePart(rawProgress: rawProgress, downloadedBytes: initialDownloadedBytes) {
                partIndex += 1
                advancedPart = true
            }

            let activeTotalBytes = resolvedTotalBytes(for: partIndex, updateTotalBytes: update.totalBytes)
            let activeDownloadedBytes = resolvedDownloadedBytes(
                updateDownloadedBytes: update.downloadedBytes,
                updateProgress: update.progress,
                totalBytes: activeTotalBytes
            )
            let activeRawProgress = resolvedRawProgress(
                updateProgress: update.progress,
                downloadedBytes: activeDownloadedBytes,
                totalBytes: activeTotalBytes
            )

            if let totalBytes = activeTotalBytes, totalBytes.isFinite, totalBytes > 0 {
                observedPartByteCounts[partIndex] = totalBytes
            }
            if let downloadedBytes = activeDownloadedBytes, downloadedBytes.isFinite, downloadedBytes >= 0 {
                observedPartDownloadedBytes[partIndex] = downloadedBytes
            }

            hasSeenProgress = true
            lastRawProgress = activeRawProgress ?? 0
            lastDownloadedBytes = activeDownloadedBytes ?? 0

            let byteWeightedProgress = byteWeightedOverallProgress(
                rawProgress: activeRawProgress,
                downloadedBytes: activeDownloadedBytes,
                totalBytes: activeTotalBytes
            )
            guard byteWeightedProgress != nil
                    || allowsEstimatedMultipartProgress
                    || (expectedPartCount == 1 && partIndex == 0 && activeRawProgress != nil) else {
                return DownloadProgressUpdate(progress: nil, speed: update.speed)
            }

            let partCount = max(expectedPartCount, partIndex + 1)
            let estimatedProgress = (
                byteWeightedProgress
                    ?? (Double(partIndex) + LibraryStore.normalizedProgress(activeRawProgress ?? 0)) / Double(partCount)
            ) * downloadCompletionProgress
            let clampedProgress = min(downloadCompletionProgress, estimatedProgress)
            // 进度严格单调:换部时字节权重未知的话,宁可停在高位等后续部分
            // 追上来,也不回退(音频部分通常几秒就补完)。
            lastOverallProgress = max(lastOverallProgress, max(0, min(downloadCompletionProgress, clampedProgress)))
            return DownloadProgressUpdate(progress: lastOverallProgress, speed: update.speed)
        }

        private func shouldAdvancePart(rawProgress: Double?, downloadedBytes: Double?) -> Bool {
            if let rawProgress,
               rawProgress + 0.12 < lastRawProgress,
               lastRawProgress > 0.65 {
                return true
            }
            if let downloadedBytes,
               downloadedBytes + max(1, lastDownloadedBytes * 0.12) < lastDownloadedBytes,
               lastRawProgress > 0.65 {
                return true
            }
            return false
        }

        private func resolvedTotalBytes(for index: Int, updateTotalBytes: Double?) -> Double? {
            if let updateTotalBytes, updateTotalBytes.isFinite, updateTotalBytes > 0 {
                return updateTotalBytes
            }
            if expectedPartByteCounts.indices.contains(index),
               expectedPartByteCounts[index].isFinite,
               expectedPartByteCounts[index] > 0 {
                return expectedPartByteCounts[index]
            }
            if let observed = observedPartByteCounts[index],
               observed.isFinite,
               observed > 0 {
                return observed
            }
            return nil
        }

        private func resolvedDownloadedBytes(
            updateDownloadedBytes: Double?,
            updateProgress: Double?,
            totalBytes: Double?
        ) -> Double? {
            if let updateDownloadedBytes, updateDownloadedBytes.isFinite, updateDownloadedBytes >= 0 {
                return updateDownloadedBytes
            }
            guard let updateProgress,
                  let totalBytes,
                  totalBytes.isFinite,
                  totalBytes > 0
            else { return nil }
            return LibraryStore.normalizedProgress(updateProgress) * totalBytes
        }

        private func resolvedRawProgress(
            updateProgress: Double?,
            downloadedBytes: Double?,
            totalBytes: Double?
        ) -> Double? {
            if let updateProgress {
                return LibraryStore.normalizedProgress(updateProgress)
            }
            guard let downloadedBytes,
                  let totalBytes,
                  totalBytes.isFinite,
                  totalBytes > 0
            else { return nil }
            return LibraryStore.normalizedProgress(downloadedBytes / totalBytes)
        }

        private func byteWeightedOverallProgress(
            rawProgress: Double?,
            downloadedBytes: Double?,
            totalBytes: Double?
        ) -> Double? {
            guard partIndex >= 0 else { return nil }

            let partCount = max(expectedPartCount, partIndex + 1)
            var byteCounts = Array(repeating: 0.0, count: partCount)
            for index in 0..<min(expectedPartByteCounts.count, partCount) {
                byteCounts[index] = expectedPartByteCounts[index]
            }
            for (index, byteCount) in observedPartByteCounts where index >= 0 && index < partCount {
                byteCounts[index] = byteCount
            }
            if let totalBytes, totalBytes.isFinite, totalBytes > 0, partIndex < partCount {
                byteCounts[partIndex] = totalBytes
            }

            guard byteCounts.allSatisfy({ $0.isFinite && $0 > 0 }) else {
                return nil
            }

            let overallTotalBytes = byteCounts.reduce(0, +)
            guard overallTotalBytes > 0 else { return nil }

            let completedBytes = partIndex == 0 ? 0 : byteCounts.prefix(partIndex).reduce(0, +)
            let currentBytes: Double
            if let downloadedBytes, downloadedBytes.isFinite, downloadedBytes >= 0 {
                currentBytes = min(byteCounts[partIndex], downloadedBytes)
            } else if let rawProgress {
                currentBytes = byteCounts[partIndex] * LibraryStore.normalizedProgress(rawProgress)
            } else if let observedDownloaded = observedPartDownloadedBytes[partIndex] {
                currentBytes = min(byteCounts[partIndex], observedDownloaded)
            } else {
                return nil
            }
            return LibraryStore.normalizedProgress((completedBytes + currentBytes) / overallTotalBytes)
        }
    }

    nonisolated static let genericImportHashtags: Set<String> = [
        "foryou", "fyp", "viral", "edit", "edits", "sfx", "cinematic", "cinematography",
        "filmmaking", "filmmaker", "photography", "videography", "video", "reels", "reel",
        "colorgrading", "colourgrading", "sounddesign"
    ]

}
