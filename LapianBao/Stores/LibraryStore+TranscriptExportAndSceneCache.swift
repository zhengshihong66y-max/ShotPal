//
//  LibraryStore+TranscriptExportAndSceneCache.swift
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

    func updateTranscriptExportProgress(path: String, progress: Double) {
        guard var job = transcriptExportJobs[path] else { return }
        guard !job.isFailed else { return }
        job.progress = Self.normalizedProgress(progress)
        transcriptExportJobs[path] = job
    }

    func failTranscriptExport(path: String, message: String) {
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

    @discardableResult
    func deleteTranscriptExport(_ export: TranscriptExportItem) -> Bool {
        guard trashLibraryFileIfPresent(URL(fileURLWithPath: export.filePath), context: "transcript export") else {
            return false
        }

        transcriptExportJobs.removeValue(forKey: export.videoPath)
        let originalCount = transcriptExports.count
        transcriptExports.removeAll { $0.id == export.id || $0.filePath == export.filePath }
        guard transcriptExports.count != originalCount else { return true }
        saveProjectData()
        return true
    }

    nonisolated static func transcriptExportMarkdown(
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

    nonisolated static func transcriptSceneBlocks(
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

    nonisolated static func transcriptSegment(_ segment: TranscriptSegment, overlapsSceneStart start: Double, end: Double) -> Bool {
        let segmentStart = max(0, segment.start)
        let segmentEnd = max(segmentStart, segment.end)
        guard end > start else {
            return segmentStart >= start
        }
        return segmentStart < end && segmentEnd > start
    }

    nonisolated static func transcriptSceneMarkdown(_ block: TranscriptSceneBlock) -> String {
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

    nonisolated static func singleLineMarkdownText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func sceneIndex(for video: VideoItem, at time: Double) -> Int? {
        guard let cuts = sceneCutsByVideoPath[video.url.path], !cuts.isEmpty else { return nil }
        return cuts.lastIndex { $0.time <= time }
    }

    func sceneCutCacheURL() -> URL? {
        libraryURL.map(ProjectRepository.sceneCutsURL)
    }

    func loadSceneCutCache() {
        guard
            let url = sceneCutCacheURL(),
            let cache = ProjectRepository.readJSON(SceneCutCacheFile.self, from: url)
        else {
            sceneCutCache = [:]
            return
        }

        sceneCutCache = cache.entries
    }

    func saveSceneCutCache() {
        guard let url = sceneCutCacheURL() else { return }

        let cache = SceneCutCacheFile(
            detectorVersion: Self.sceneDetectorVersion,
            entries: sceneCutCache
        )

        do {
            try ProjectRepository.writeJSON(cache, to: url, encoder: ProjectRepository.prettySortedEncoder)
        } catch {
            return
        }
    }

    func validCachedSceneCutEntry(for video: VideoItem) -> SceneCutCacheEntry? {
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

    func hasSceneRecognitionResult(for video: VideoItem) -> Bool {
        sceneCutsByVideoPath[video.url.path] != nil || validCachedSceneCutEntry(for: video) != nil
    }

    func sceneRecognitionCutCount(for video: VideoItem) -> Int? {
        if let cuts = sceneCutsByVideoPath[video.url.path] {
            return cuts.count
        }
        return validCachedSceneCutEntry(for: video).map { Self.stableSceneCutTimes(from: $0.cutTimes).count }
    }

    func storeSceneCutCache(for video: VideoItem, cuts: [SceneCut]) {
        guard let signature = videoFileSignature(for: video.url) else { return }

        let relativePath = relativeVideoPath(for: video.url)
        let orderedCuts = cuts.sorted { $0.time < $1.time }
        let cutTimes = orderedCuts
            .map { round($0.time * 1000) / 1000 }
        let thumbnailData = sceneCutCacheThumbnailData(from: orderedCuts)

        sceneCutCache[relativePath] = SceneCutCacheEntry(
            detectorVersion: Self.sceneDetectorVersion,
            videoID: stableVideoID(for: relativePath),
            relativePath: relativePath,
            fileSize: signature.fileSize,
            modificationTime: signature.modificationTime,
            duration: durationByVideoPath[video.url.path],
            cutTimes: cutTimes,
            thumbnailData: thumbnailData,
            sceneIDs: cutTimes.indices.map { sceneID(for: relativePath, index: $0) },
            generatedAt: Date()
        )
        saveSceneCutCache()
    }

    func sceneCutCacheThumbnailData(from cuts: [SceneCut]) -> [Data]? {
        guard !cuts.isEmpty else { return [] }
        var thumbnails: [Data] = []
        thumbnails.reserveCapacity(cuts.count)

        for cut in cuts {
            guard !cut.isPlaceholder,
                  let data = Self.sceneCacheThumbnailData(from: cut.thumbnailImage)
            else { return nil }
            thumbnails.append(data)
        }

        return thumbnails
    }

    nonisolated static func sceneCacheThumbnailData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78])
    }

    func videoFileSignature(for url: URL) -> (fileSize: Int64, modificationTime: Double)? {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let fileSize = values.fileSize,
            let modificationDate = values.contentModificationDate
        else { return nil }

        return (Int64(fileSize), modificationDate.timeIntervalSince1970)
    }

    func relativeVideoPath(for url: URL) -> String {
        guard let libraryURL else { return url.lastPathComponent }

        let libraryPath = libraryURL.standardizedFileURL.path
        let videoPath = url.standardizedFileURL.path
        let prefix = libraryPath.hasSuffix("/") ? libraryPath : libraryPath + "/"
        guard videoPath.hasPrefix(prefix) else { return url.lastPathComponent }

        return String(videoPath.dropFirst(prefix.count))
    }

    func stableVideoID(for relativePath: String) -> String {
        "video-\(Self.fnv1a64(relativePath))"
    }

    func sceneID(for relativePath: String, index: Int) -> String {
        "\(stableVideoID(for: relativePath))-scene-\(String(format: "%04d", index + 1))"
    }

}
