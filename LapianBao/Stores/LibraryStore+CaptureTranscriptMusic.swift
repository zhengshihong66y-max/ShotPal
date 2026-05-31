//
//  LibraryStore+CaptureTranscriptMusic.swift
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

    func updateTranscriptProgress(path: String, progress: Double, message: String) {
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

    func updateTranscriptBatchProgress(completed: Int, currentProgress: Double) {
        let total = max(1, transcriptBatchJob.total)
        transcriptBatchJob.completed = completed
        transcriptBatchJob.progress = Self.normalizedProgress((Double(completed) + Self.normalizedProgress(currentProgress)) / Double(total))
    }

    nonisolated static func progressPercentTextForStatus(_ progress: Double) -> String {
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

    func updateMusicBatchProgress(completed: Int, currentProgress: Double) {
        let total = max(1, musicBatchJob.total)
        musicBatchJob.completed = completed
        musicBatchJob.progress = Self.normalizedProgress((Double(completed) + Self.normalizedProgress(currentProgress)) / Double(total))
    }

    func recognizeLocalMusicAssetsIfNeeded() {
        if deduplicateRecognizedLocalMusicAssets() {
            scanResourceLibrary(forceFullScan: true)
        }

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
                        if self.deduplicateRecognizedLocalMusicAssets() {
                            self.scanResourceLibrary(forceFullScan: true)
                        }
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

    func localMusicRecognitionQueue() -> [LocalMusicAsset] {
        localMusicAssets.filter { !shouldSkipLocalMusicRecognition(for: $0) }
    }

    func shouldSkipLocalMusicRecognition(for asset: LocalMusicAsset) -> Bool {
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

    @discardableResult
    func deduplicateRecognizedLocalMusicAssets() -> Bool {
        guard !localMusicAssets.isEmpty else { return false }

        let fm = FileManager.default
        let orderedAssets = localMusicAssets.sorted(by: Self.preferredLocalMusicAssetSort)
        var retainedAssetByKey: [String: LocalMusicAsset] = [:]
        var retainedPathByDeletedPath: [String: String] = [:]
        var deletedPaths = Set<String>()

        for asset in orderedAssets {
            let path = asset.filePath
            guard !deletedPaths.contains(path),
                  fm.fileExists(atPath: path),
                  let key = Self.recognizedLocalMusicDuplicateKey(
                    for: asset,
                    songs: musicsByVideoPath[path, default: []]
                  )
            else { continue }

            guard let retainedAsset = retainedAssetByKey[key] else {
                retainedAssetByKey[key] = asset
                continue
            }

            guard fm.fileExists(atPath: retainedAsset.filePath) else {
                retainedAssetByKey[key] = asset
                continue
            }

            do {
                try fm.removeItem(atPath: path)
            } catch {
                continue
            }

            mergeLocalMusicRecognition(from: path, into: retainedAsset.filePath)
            retainedPathByDeletedPath[path] = retainedAsset.filePath
            deletedPaths.insert(path)
        }

        guard !deletedPaths.isEmpty else { return false }

        for path in deletedPaths {
            musicsByVideoPath.removeValue(forKey: path)
            musicDetectionStatusByVideoPath.removeValue(forKey: path)
            localMusicWaveformSamplesByPath.removeValue(forKey: path)
            knownLocalResourcePaths.remove(path)

            let enrichmentKeys = musicTagEnrichmentTasks.keys.filter { $0.hasPrefix("\(path)|") }
            for key in enrichmentKeys {
                musicTagEnrichmentTasks[key]?.cancel()
                musicTagEnrichmentTasks[key] = nil
            }
        }

        localMusicAssets.removeAll { deletedPaths.contains($0.filePath) }
        for index in musicDownloadJobs.indices {
            guard let filePath = musicDownloadJobs[index].filePath,
                  let retainedPath = retainedPathByDeletedPath[filePath]
            else { continue }
            musicDownloadJobs[index].filePath = retainedPath
        }

        let musicPaths = Set(localMusicAssets.map(\.filePath))
        let audioPaths = Set(localAudioAssets.map(\.filePath))
        pruneLocalWaveformCaches(musicPaths: musicPaths, audioPaths: audioPaths)

        if let libraryURL {
            let snapshot = ResourceLibrarySnapshot(music: localMusicAssets, audio: localAudioAssets)
            Self.saveCachedResourceLibrarySnapshot(snapshot, in: libraryURL)
            Task.detached(priority: .background) {
                ResourceLibrarySQLite.write(libraryURL: libraryURL, music: snapshot.music, audio: snapshot.audio)
            }
        }

        saveProjectData()
        return true
    }

    func mergeLocalMusicRecognition(from duplicatePath: String, into retainedPath: String) {
        let duplicateSongs = musicsByVideoPath[duplicatePath, default: []]
        guard !duplicateSongs.isEmpty else { return }

        var retainedSongs = musicsByVideoPath[retainedPath, default: []]
        for duplicateSong in duplicateSongs {
            if let index = retainedSongs.firstIndex(where: { Self.sameRecognizedSong($0, duplicateSong) }) {
                var retainedSong = retainedSongs[index]
                retainedSong.tags = MusicRecognitionItem.cleanedTags(retainedSong.tags + duplicateSong.tags)
                if retainedSong.artworkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    retainedSong.artworkURL = duplicateSong.artworkURL
                }
                if retainedSong.appleMusicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    retainedSong.appleMusicURL = duplicateSong.appleMusicURL
                }
                retainedSongs[index] = retainedSong
            } else {
                retainedSongs.append(duplicateSong)
            }
        }
        musicsByVideoPath[retainedPath] = retainedSongs
    }

    nonisolated static func recognizedLocalMusicDuplicateKey(
        for asset: LocalMusicAsset,
        songs: [MusicRecognitionItem]
    ) -> String? {
        guard let song = songs.first(where: { song in
            !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !song.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return nil }

        let title = normalizedMusicDuplicateText(song.title)
        let artist = normalizedMusicDuplicateText(song.artist)
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return "\(asset.role.rawValue)|\(title)|\(artist)"
    }

    nonisolated static func normalizedMusicDuplicateText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    nonisolated static func preferredLocalMusicAssetSort(_ lhs: LocalMusicAsset, _ rhs: LocalMusicAsset) -> Bool {
        let lhsName = URL(fileURLWithPath: lhs.filePath).lastPathComponent
        let rhsName = URL(fileURLWithPath: rhs.filePath).lastPathComponent
        let lhsIsAudio = supportedAudioExtensions.contains(lhs.fileExtension)
        let rhsIsAudio = supportedAudioExtensions.contains(rhs.fileExtension)
        if lhsIsAudio != rhsIsAudio {
            return lhsIsAudio
        }
        if lhs.title != rhs.title {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        if lhsName.count != rhsName.count {
            return lhsName.count < rhsName.count
        }
        return lhs.filePath.localizedStandardCompare(rhs.filePath) == .orderedAscending
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

    func prepareMusicDownloadJob(song: MusicRecognitionItem, type: MusicDownloadJob.DownloadType) -> UUID? {
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

    func runMusicDownload(jobID: UUID, song: MusicRecognitionItem, type: MusicDownloadJob.DownloadType) async {
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

    func updateMusicDownloadJob(id: UUID, mutate: (inout MusicDownloadJob) -> Void) {
        guard let index = musicDownloadJobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&musicDownloadJobs[index])
        saveProjectData()
    }

    func updateMusicDownloadBatchProgress(completed: Int, currentProgress: Double) {
        let total = max(1, musicDownloadBatchJob.total)
        musicDownloadBatchJob.completed = completed
        musicDownloadBatchJob.progress = Self.normalizedProgress((Double(completed) + Self.normalizedProgress(currentProgress)) / Double(total))
    }

    func musicDownloadBatchQueue(types: [MusicDownloadJob.DownloadType]) -> [(song: MusicRecognitionItem, type: MusicDownloadJob.DownloadType)] {
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

    func isMusicDownloadSatisfied(song: MusicRecognitionItem, type: MusicDownloadJob.DownloadType) -> Bool {
        guard let job = latestMusicDownloadJob(songKey: musicSongKey(song), type: type) else { return false }
        return isSatisfiedMusicDownload(job)
    }

    func isSatisfiedMusicDownload(_ job: MusicDownloadJob) -> Bool {
        guard case .succeeded = job.status,
              let filePath = job.filePath,
              FileManager.default.fileExists(atPath: filePath)
        else { return false }
        return true
    }

    func latestMusicDownloadJob(songKey: String, type: MusicDownloadJob.DownloadType) -> MusicDownloadJob? {
        musicDownloadJobs.last { $0.songKey == songKey && $0.type == type }
    }

    func musicSongKey(_ song: MusicRecognitionItem) -> String {
        "\(song.title)|\(song.artist)"
    }

}
