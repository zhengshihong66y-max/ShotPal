//
//  LibraryStore+PersistenceAndSources.swift
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
    func tagsJSONURL() -> URL? {
        guard let libraryURL else { return nil }
        return ProjectRepository.videoTagsURL(in: libraryURL)
    }

    func sourceInfoJSONURL() -> URL? {
        guard let libraryURL else { return nil }
        return ProjectRepository.sourceInfoURL(in: libraryURL)
    }

    func saveTagsJSON() {
        guard let url = tagsJSONURL(), let libraryURL else { return }
        var relative: [String: [String]] = [:]
        let videoPaths = Set(videos.map(\.url.path))
        let pathsToPersist = videoPaths
            .union(tagsByVideoPath.keys)
            .union(persistedVideoTagPaths)
        for absPath in pathsToPersist {
            let tags = tagsByVideoPath[absPath, default: []]
            let cleanedTags = subjectiveVideoTags(
                forPath: absPath,
                tags: tags,
                sourceInfo: sourceInfoByVideoPath[absPath]
            )
            relative[ProjectRepository.relativePath(for: absPath, base: libraryURL)] = cleanedTags
        }
        persistedVideoTagPaths = pathsToPersist
        try? ProjectRepository.writeJSON(relative, to: url)
    }

    func saveSourceInfoJSON() {
        guard let url = sourceInfoJSONURL(), let libraryURL else { return }
        var relative: [String: VideoSourceInfo] = [:]
        for (absPath, info) in sourceInfoByVideoPath {
            guard let cleanedInfo = Self.cleanedVideoSourceInfo(info) else { continue }
            relative[ProjectRepository.relativePath(for: absPath, base: libraryURL)] = cleanedInfo
        }

        try? ProjectRepository.writeJSON(relative, to: url, encoder: ProjectRepository.prettySortedEncoder)
    }

    func projectDataURL() -> URL? {
        libraryURL.map(ProjectRepository.projectDataURL)
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

    func saveProjectData() {
        guard projectDataLoadState == .loaded else {
            if projectDataLoadState == .loading {
                projectDataDirty = true
            }
            return
        }
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

    func makeProjectDataFile() -> ProjectDataFile {
        let dataFile = ProjectDataFile(
            sampledFrames: sampledFrames,
            annotations: annotations,
            audioClips: audioClips,
            transcripts: transcriptSegmentsByVideoPath,
            transcriptExports: transcriptExports.isEmpty ? nil : transcriptExports,
            musicsByVideoPath: musicsByVideoPath.isEmpty ? nil : musicsByVideoPath,
            musicDownloadJobs: musicDownloadJobs.isEmpty ? nil : persistedMusicDownloadJobs()
        )
        guard let libraryURL else { return dataFile }
        return Self.projectDataFile(dataFile, storingRelativeTo: libraryURL)
    }

    func pendingProjectDataEditsSnapshot(resolvingRelativeTo libraryURL: URL) -> ProjectDataFile {
        let dataFile = ProjectDataFile(
            sampledFrames: sampledFrames,
            annotations: annotations,
            audioClips: audioClips,
            transcripts: transcriptSegmentsByVideoPath,
            transcriptExports: transcriptExports.isEmpty ? nil : transcriptExports,
            musicsByVideoPath: musicsByVideoPath.isEmpty ? nil : musicsByVideoPath,
            musicDownloadJobs: musicDownloadJobs.isEmpty ? nil : persistedMusicDownloadJobs()
        )
        return Self.projectDataFile(dataFile, resolvingRelativeTo: libraryURL).dataFile
    }

    nonisolated static func writeProjectData(_ dataFile: ProjectDataFile, to url: URL) throws {
        try ProjectRepository.writeProjectData(dataFile, to: url)
    }

    func loadProjectData() {
        projectLoadTask?.cancel()
        projectLoadTask = nil
        projectLoadGeneration += 1
        projectDataLoadState = .loading
        projectDataDirty = false
        guard
            let url = projectDataURL(),
            let libraryURL,
            let decoded = Self.readProjectData(from: url)
        else {
            clearProjectData()
            projectDataLoadState = .loaded
            runStartupAutomationIfNeeded()
            return
        }
        let restored = Self.projectDataFile(decoded, resolvingRelativeTo: libraryURL)
        let shouldPersistMigration = restored.didChange || !pendingVideoPathRemap.isEmpty
        let migrated = migrateProjectDataVideoPaths(restored.dataFile)
        projectDataLoadState = .loaded
        applyProjectData(migrated)
        projectDataDirty = false
        if shouldPersistMigration {
            saveProjectData()
        }
    }

    func loadProjectDataDeferred(after delay: TimeInterval = 0) {
        projectLoadTask?.cancel()
        projectLoadGeneration += 1
        let generation = projectLoadGeneration
        let delayNanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        projectDataLoadState = .loading
        projectDataDirty = false
        clearProjectData()
        guard let url = projectDataURL(), let libraryURL else {
            projectDataLoadState = .loaded
            return
        }

        let priority: TaskPriority = delayNanoseconds > 0 ? .utility : .userInitiated
        projectLoadTask = Task.detached(priority: priority) { [weak self, url, libraryURL] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled else { return }
            }
            let decoded = Self.readProjectData(from: url)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.projectLoadGeneration == generation else { return }
                let pendingEdits = self.projectDataDirty
                    ? self.pendingProjectDataEditsSnapshot(resolvingRelativeTo: libraryURL)
                    : nil
                if let decoded {
                    let restored = Self.projectDataFile(decoded, resolvingRelativeTo: libraryURL)
                    let shouldPersistMigration = restored.didChange || !self.pendingVideoPathRemap.isEmpty
                    var migrated = self.migrateProjectDataVideoPaths(restored.dataFile)
                    if let pendingEdits {
                        migrated = Self.projectDataFile(migrated, mergingPendingEdits: pendingEdits)
                    }
                    self.projectDataLoadState = .loaded
                    self.applyProjectData(migrated)
                    self.projectDataDirty = false
                    if shouldPersistMigration || pendingEdits != nil {
                        self.saveProjectData()
                    }
                } else {
                    if let pendingEdits {
                        self.applyProjectData(pendingEdits)
                    } else {
                        self.clearProjectData()
                    }
                    self.projectDataLoadState = .loaded
                    self.runStartupAutomationIfNeeded()
                    self.projectDataDirty = false
                    if pendingEdits != nil {
                        self.saveProjectData()
                    }
                }
                self.projectLoadTask = nil
            }
        }
    }

    nonisolated static func readProjectData(from url: URL) -> ProjectDataFile? {
        ProjectRepository.readProjectData(from: url)
    }

    nonisolated static func projectDataFile(
        _ dataFile: ProjectDataFile,
        storingRelativeTo libraryURL: URL
    ) -> ProjectDataFile {
        var stored = dataFile

        stored.sampledFrames = dataFile.sampledFrames.map { frame in
            var item = frame
            item.videoPath = projectRelativePath(item.videoPath, libraryURL: libraryURL)
            return item
        }
        stored.annotations = dataFile.annotations.map { annotation in
            var item = annotation
            item.videoPath = projectRelativePath(item.videoPath, libraryURL: libraryURL)
            return item
        }
        stored.audioClips = dataFile.audioClips.map { clip in
            var item = clip
            item.videoPath = projectRelativePath(item.videoPath, libraryURL: libraryURL)
            item.filePath = item.filePath.map { projectRelativePath($0, libraryURL: libraryURL) }
            return item
        }
        stored.transcripts = projectDataDictionary(dataFile.transcripts, libraryURL: libraryURL, makeKey: projectRelativePath).mapValues { segments in
            segments.map { segment in
                var item = segment
                item.videoPath = projectRelativePath(item.videoPath, libraryURL: libraryURL)
                return item
            }
        }
        stored.transcriptExports = dataFile.transcriptExports?.map { export in
            var item = export
            item.videoPath = projectRelativePath(item.videoPath, libraryURL: libraryURL)
            item.filePath = projectRelativePath(item.filePath, libraryURL: libraryURL)
            return item
        }
        if let musicsByVideoPath = dataFile.musicsByVideoPath {
            stored.musicsByVideoPath = projectDataDictionary(musicsByVideoPath, libraryURL: libraryURL, makeKey: projectRelativePath)
        }
        stored.musicDownloadJobs = dataFile.musicDownloadJobs?.map { job in
            var item = job
            item.filePath = item.filePath.map { projectRelativePath($0, libraryURL: libraryURL) }
            return item
        }

        return stored
    }

    nonisolated static func projectDataFile(
        _ dataFile: ProjectDataFile,
        resolvingRelativeTo libraryURL: URL
    ) -> (dataFile: ProjectDataFile, didChange: Bool) {
        var restored = dataFile
        var didChange = false

        func resolve(_ path: String) -> String {
            let result = projectAbsolutePath(path, libraryURL: libraryURL)
            didChange = didChange || result != path
            return result
        }

        restored.sampledFrames = dataFile.sampledFrames.map { frame in
            var item = frame
            item.videoPath = resolve(item.videoPath)
            return item
        }
        restored.annotations = dataFile.annotations.map { annotation in
            var item = annotation
            item.videoPath = resolve(item.videoPath)
            return item
        }
        restored.audioClips = dataFile.audioClips.map { clip in
            var item = clip
            item.videoPath = resolve(item.videoPath)
            item.filePath = item.filePath.map(resolve)
            return item
        }
        restored.transcripts = projectDataDictionary(dataFile.transcripts, makeKey: resolve).mapValues { segments in
            segments.map { segment in
                var item = segment
                item.videoPath = resolve(item.videoPath)
                return item
            }
        }
        restored.transcriptExports = dataFile.transcriptExports?.map { export in
            var item = export
            item.videoPath = resolve(item.videoPath)
            item.filePath = resolve(item.filePath)
            return item
        }
        if let musicsByVideoPath = dataFile.musicsByVideoPath {
            restored.musicsByVideoPath = projectDataDictionary(musicsByVideoPath, makeKey: resolve)
        }
        restored.musicDownloadJobs = dataFile.musicDownloadJobs?.map { job in
            var item = job
            item.filePath = item.filePath.map(resolve)
            return item
        }

        return (restored, didChange)
    }

    static func projectDataFile(
        _ dataFile: ProjectDataFile,
        mergingPendingEdits pending: ProjectDataFile
    ) -> ProjectDataFile {
        var merged = dataFile
        merged.sampledFrames = mergeProjectDataItems(merged.sampledFrames, pending.sampledFrames)
        merged.annotations = mergeProjectDataItems(merged.annotations, pending.annotations)
        merged.audioClips = mergeProjectDataItems(merged.audioClips, pending.audioClips)

        if !pending.transcripts.isEmpty {
            merged.transcripts.merge(pending.transcripts) { _, pending in pending }
        }
        if let pendingExports = pending.transcriptExports, !pendingExports.isEmpty {
            merged.transcriptExports = mergeProjectDataItems(merged.transcriptExports ?? [], pendingExports)
        }
        if let pendingMusics = pending.musicsByVideoPath, !pendingMusics.isEmpty {
            var musics = merged.musicsByVideoPath ?? [:]
            musics.merge(pendingMusics) { _, pending in pending }
            merged.musicsByVideoPath = musics
        }
        if let pendingJobs = pending.musicDownloadJobs, !pendingJobs.isEmpty {
            merged.musicDownloadJobs = mergeProjectDataItems(merged.musicDownloadJobs ?? [], pendingJobs)
        }
        return merged
    }

    static func mergeProjectDataItems<Item: Identifiable>(
        _ base: [Item],
        _ pending: [Item]
    ) -> [Item] where Item.ID: Hashable {
        guard !pending.isEmpty else { return base }
        var merged = base
        var indexByID = Dictionary(uniqueKeysWithValues: merged.enumerated().map { ($0.element.id, $0.offset) })
        for item in pending {
            if let index = indexByID[item.id] {
                merged[index] = item
            } else {
                indexByID[item.id] = merged.count
                merged.append(item)
            }
        }
        return merged
    }

    nonisolated static func projectRelativePath(_ path: String, libraryURL: URL) -> String {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return path }
        return ProjectRepository.relativePath(for: path, base: libraryURL)
    }

    nonisolated static func projectAbsolutePath(_ path: String, libraryURL: URL) -> String {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return path }
        if path.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
            if let relocated = relocatedProjectPath(forAbsolutePath: path, libraryURL: libraryURL) {
                return relocated
            }
            return path
        }
        return libraryURL.appendingPathComponent(path).standardizedFileURL.path
    }

    nonisolated static func relocatedProjectPath(forAbsolutePath path: String, libraryURL: URL) -> String? {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let anchors = Set([
            videoFolderName,
            legacyVideoFolderName,
            imageExportFolderName,
            legacyImageExportFolderName,
            soundEffectExportFolderName,
            legacyAudioExportFolderName,
            legacySoundEffectExportFolderName,
            transcriptExportFolderName,
            legacyTranscriptExportFolderName,
            musicExportFolderName,
            legacyMusicExportFolderName,
            exportRootFolderName,
            "Imports"
        ])

        for index in components.indices.reversed() where anchors.contains(components[index]) {
            let relativeComponents = components[index...]
            let candidate = relativeComponents.reduce(libraryURL) { partial, component in
                partial.appendingPathComponent(component)
            }
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.standardizedFileURL.path
            }
        }

        let filename = URL(fileURLWithPath: path).lastPathComponent
        guard !filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let fallbackRoots = [
            libraryURL,
            mediaFolder(in: libraryURL, named: videoFolderName),
            mediaFolder(in: libraryURL, named: legacyVideoFolderName),
            mediaFolder(in: libraryURL, named: imageExportFolderName),
            mediaFolder(in: libraryURL, named: legacyImageExportFolderName),
            mediaFolder(in: libraryURL, named: soundEffectExportFolderName),
            mediaFolder(in: libraryURL, named: legacyAudioExportFolderName),
            mediaFolder(in: libraryURL, named: legacySoundEffectExportFolderName),
            mediaFolder(in: libraryURL, named: musicExportFolderName),
            mediaFolder(in: libraryURL, named: legacyMusicExportFolderName),
            exportFolder(in: libraryURL, named: transcriptExportFolderName),
            legacyExportFolder(in: libraryURL, named: legacyImageExportFolderName),
            legacyExportFolder(in: libraryURL, named: legacySoundEffectExportFolderName),
            legacyExportFolder(in: libraryURL, named: legacyTranscriptExportFolderName),
            legacyExportFolder(in: libraryURL, named: legacyMusicExportFolderName)
        ]
        let matches = fallbackRoots
            .map { $0.appendingPathComponent(filename).standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return matches.count == 1 ? matches[0].path : nil
    }

    nonisolated static func projectDataDictionary<Value>(
        _ dictionary: [String: Value],
        libraryURL: URL,
        makeKey: (String, URL) -> String
    ) -> [String: Value] {
        projectDataDictionary(dictionary) { makeKey($0, libraryURL) }
    }

    nonisolated static func projectDataDictionary<Value>(
        _ dictionary: [String: Value],
        makeKey: (String) -> String
    ) -> [String: Value] {
        var mapped: [String: Value] = [:]
        for (key, value) in dictionary {
            mapped[makeKey(key)] = value
        }
        return mapped
    }

    func clearProjectData() {
        sampledFrames = []
        annotations = []
        audioClips = []
        transcriptSegmentsByVideoPath = [:]
        transcriptExports = []
        musicsByVideoPath = [:]
        musicDownloadJobs = []
    }

    func applyProjectData(_ decoded: ProjectDataFile) {
        let pruned = projectDataRemovingMissingVideoImageExports(decoded)
        sampledFrames = pruned.sampledFrames
        annotations = pruned.annotations
        audioClips = pruned.audioClips
        transcriptSegmentsByVideoPath = pruned.transcripts
        transcriptExports = pruned.transcriptExports ?? []
        musicsByVideoPath = pruned.musicsByVideoPath ?? [:]
        musicDownloadJobs = reconciledMusicDownloadJobs(pruned.musicDownloadJobs ?? [])
        reconcileMusicDownloadJobsWithLocalAssets(localMusicAssets)
        enrichMusicTagsIfNeeded(includeLocalAssets: false)
        runStartupAutomationIfNeeded()
    }

    func projectDataRemovingMissingVideoImageExports(_ decoded: ProjectDataFile) -> ProjectDataFile {
        let liveVideoPaths = Set(videos.map(\.url.path))
        let framesToRemove = decoded.sampledFrames.filter { !liveVideoPaths.contains($0.videoPath) }
        guard !framesToRemove.isEmpty else { return decoded }

        let frameIDsToRemove = Set(framesToRemove.map(\.id))
        for frame in framesToRemove {
            for url in imageExportURLsToDelete(
                for: frame,
                excludingFrameIDs: frameIDsToRemove,
                in: decoded.sampledFrames
            ) {
                _ = trashLibraryFileIfPresent(url, context: "missing-video image export")
            }
        }

        var pruned = decoded
        pruned.sampledFrames.removeAll { !liveVideoPaths.contains($0.videoPath) }
        return pruned
    }

    func migrateProjectDataVideoPaths(_ decoded: ProjectDataFile) -> ProjectDataFile {
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

    func persistedMusicDownloadJobs() -> [MusicDownloadJob] {
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

    func reconciledMusicDownloadJobs(_ jobs: [MusicDownloadJob]) -> [MusicDownloadJob] {
        jobs.map { job in
            var reconciled = job
            if reconciled.recognitionID == nil {
                reconciled.recognitionID = uniqueMusicRecognitionID(forSongKey: reconciled.songKey)
            }
            reconciled.isPreparingWaveform = false
            if Self.isActiveDownloadStatus(reconciled.status) {
                reconciled.status = .paused
                reconciled.downloadProgress = nil
            }
            if let filePath = reconciled.filePath,
               FileManager.default.fileExists(atPath: filePath) {
                reconciled.status = .succeeded(URL(fileURLWithPath: filePath).lastPathComponent)
                reconciled.downloadProgress = 1
            } else if case .succeeded = reconciled.status {
                reconciled.downloadProgress = nil
                reconciled.waveformSamples = nil
            }
            return reconciled
        }
    }

    func uniqueMusicRecognitionID(forSongKey songKey: String) -> UUID? {
        var matchedID: UUID?
        for song in musicsByVideoPath.values.flatMap({ $0 }) where musicSongKey(song) == songKey {
            guard let currentID = matchedID else {
                matchedID = song.id
                continue
            }
            guard currentID == song.id else { return nil }
        }
        return matchedID
    }

    func runStartupAutomationIfNeeded() {
        guard projectDataLoadState == .loaded,
              let libraryPath = libraryURL?.path,
              startupAutomationLibraryPath != libraryPath
        else { return }

        startupAutomationLibraryPath = libraryPath
        DispatchQueue.main.async { [weak self] in
            guard let self, self.libraryURL?.path == libraryPath else { return }
            if AppSettings.autoSceneBatchEnabled {
                self.startSceneBatch(onlyMissing: true)
            }
            if AppSettings.autoTranscriptBatchEnabled {
                self.startTranscriptBatch(onlyMissing: true)
            }
            if AppSettings.autoMusicDownloadBatchEnabled {
                self.startMusicDownloadBatch(types: MusicDownloadJob.DownloadType.allCases)
            }
        }
    }

    func loadTagsJSON() {
        guard let url = tagsJSONURL(), let libraryURL else { return }
        guard let decoded = ProjectRepository.readJSON([String: [String]].self, from: url) else {
            persistedVideoTagPaths.removeAll()
            return
        }

        let base = libraryURL.path.hasSuffix("/") ? libraryURL.path : libraryURL.path + "/"
        var loadedTagsByVideoPath = tagsByVideoPath
        var loadedTagPaths = Set<String>()
        for (key, tags) in decoded {
            let absPath = key.hasPrefix("/") ? key : base + key
            loadedTagPaths.insert(absPath)
            if tags.isEmpty {
                loadedTagsByVideoPath.removeValue(forKey: absPath)
            } else {
                loadedTagsByVideoPath[absPath] = tags
            }
        }
        persistedVideoTagPaths = loadedTagPaths
        tagsByVideoPath = loadedTagsByVideoPath
    }

    func loadSourceInfoJSON() {
        guard let url = sourceInfoJSONURL(), let libraryURL else { return }
        guard let decoded = ProjectRepository.readJSON([String: VideoSourceInfo].self, from: url) else { return }

        let base = libraryURL.path.hasSuffix("/") ? libraryURL.path : libraryURL.path + "/"
        var loadedSourceInfoByVideoPath = sourceInfoByVideoPath
        for (key, info) in decoded {
            guard let cleanedInfo = Self.cleanedVideoSourceInfo(info) else { continue }
            let absPath = key.hasPrefix("/") ? key : base + key
            loadedSourceInfoByVideoPath[absPath] = cleanedInfo
        }
        sourceInfoByVideoPath = loadedSourceInfoByVideoPath
    }

    func applyPendingVideoPathMigrationToLoadedMetadata() {
        var shouldSaveTags = false
        var shouldSaveSources = false

        if !pendingVideoPathRemap.isEmpty {
            tagsByVideoPath = remapVideoPathDictionary(tagsByVideoPath)
            sourceInfoByVideoPath = remapVideoPathDictionary(sourceInfoByVideoPath)
            persistedVideoTagPaths = Set(persistedVideoTagPaths.map(remapVideoPath))
            shouldSaveTags = true
            shouldSaveSources = true
        }

        if !pendingVideoFolderTagsByPath.isEmpty {
            var updated = tagsByVideoPath
            for (path, folderTags) in pendingVideoFolderTagsByPath {
                guard !persistedVideoTagPaths.contains(path) else { continue }
                let cleanedTags = Self.cleanedResourceTags(folderTags)
                guard !cleanedTags.isEmpty else { continue }
                var merged = updated[path] ?? []
                var seen = Set(merged)
                for tag in cleanedTags where seen.insert(tag).inserted {
                    merged.append(tag)
                }
                updated[path] = merged
                persistedVideoTagPaths.insert(path)
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

    func remapVideoPath(_ path: String) -> String {
        pendingVideoPathRemap[path] ?? path
    }

    func remapVideoPathDictionary<Value>(_ dictionary: [String: Value]) -> [String: Value] {
        guard !pendingVideoPathRemap.isEmpty else { return dictionary }
        var remapped: [String: Value] = [:]
        for (path, value) in dictionary {
            remapped[remapVideoPath(path)] = value
        }
        return remapped
    }

    struct VideoSourceInference {
        var platform: String?
        var sourceURL: URL?
        var authorName: String?
        var title: String?
    }

    nonisolated static func cleanedVideoSourceInfo(_ info: VideoSourceInfo) -> VideoSourceInfo? {
        return VideoSourceInfo(
            platform: normalizedSourcePlatform(info.platform),
            sourceURL: usefulSourceURLString(info.sourceURL),
            authorName: info.authorName.flatMap(normalizedSourceAuthorName),
            title: info.title.flatMap(normalizedSourceTitle)
        )
    }

    nonisolated static func instagramSourceTitleFamilyKeys(
        from sourceInfoByVideoPath: [String: VideoSourceInfo]
    ) -> Set<String> {
        var keys = Set<String>()
        for (path, info) in sourceInfoByVideoPath {
            guard canonicalSourcePlatform(info.platform) == "Instagram" else { continue }
            if let key = sourceTitleFamilyKey(info.title) {
                keys.insert(key)
            }
            let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if let key = sourceTitleFamilyKey(fileName) {
                keys.insert(key)
            }
        }
        return keys
    }

    static func sourcePlatformFromKnownInstagramTitleFamily(
        video: VideoItem,
        sourceInfo: VideoSourceInfo?,
        instagramTitleFamilyKeys: Set<String>
    ) -> String? {
        guard !instagramTitleFamilyKeys.isEmpty else { return nil }
        let storedPlatform = sourceInfo.flatMap { canonicalSourcePlatform($0.platform) }
        guard storedPlatform == nil || storedPlatform == unknownSourcePlatformName else {
            return nil
        }

        let candidates = [
            sourceInfo?.title,
            video.name,
            video.url.deletingPathExtension().lastPathComponent
        ]
        for candidate in candidates {
            if let key = sourceTitleFamilyKey(candidate),
               instagramTitleFamilyKeys.contains(key) {
                return "Instagram"
            }
        }
        return nil
    }

    func ensureVideoSourceInfoAndTags() {
        var updatedTagsByVideoPath = tagsByVideoPath
        var updatedSourceInfoByVideoPath = sourceInfoByVideoPath
        let instagramTitleFamilyKeys = Self.instagramSourceTitleFamilyKeys(
            from: updatedSourceInfoByVideoPath
        )
        var didChangeTags = false
        var didChangeSourceInfo = false

        for video in videos {
            let path = video.url.path
            let tags = updatedTagsByVideoPath[path, default: []]
            let sourceInfo = updatedSourceInfoByVideoPath[path]
            let inference = inferredVideoSource(for: video, sourceInfo: sourceInfo)
            let titleFamilyPlatform = Self.sourcePlatformFromKnownInstagramTitleFamily(
                video: video,
                sourceInfo: sourceInfo,
                instagramTitleFamilyKeys: instagramTitleFamilyKeys
            )
            let normalizedPlatform = Self.normalizedSourcePlatform(
                titleFamilyPlatform ?? inference.platform
            )
            let normalizedAuthor = [
                sourceInfo?.authorName,
                inference.authorName
            ]
                .compactMap { $0.flatMap(Self.normalizedSourceAuthorName) }
                .first
            let normalizedTitle = (sourceInfo?.title ?? inference.title).flatMap(Self.normalizedSourceTitle)

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

            let sortedTags = subjectiveVideoTags(
                forPath: path,
                tags: tags,
                sourceInfo: updatedSourceInfoByVideoPath[path]
            ).sorted()
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
            let availableTags = Set(updatedTagsByVideoPath.values.flatMap { $0 })
            if !selectedTags.isSubset(of: availableTags) {
                selectedTags.formIntersection(availableTags)
            }
            tagsByVideoPath = updatedTagsByVideoPath
            saveTagsJSON()
        }
    }

    func scheduleDeferredSourceInfoAndTags(for libraryPath: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.libraryURL?.path == libraryPath else { return }
            self.ensureVideoSourceInfoAndTags()
        }
    }

    func videoSourceAuthorName(for video: VideoItem) -> String? {
        let path = video.url.path
        if let cached = videoSourceAuthorCache[path] {
            return cached
        }

        let sourceInfo = sourceInfoByVideoPath[path]
        let storedAuthor = sourceInfo?.authorName.flatMap(Self.normalizedSourceAuthorName)
        let inferredAuthor = inferredVideoSource(
            for: video,
            sourceInfo: sourceInfo
        ).authorName.flatMap(Self.normalizedSourceAuthorName)
        let author = [storedAuthor, inferredAuthor].compactMap { $0 }.first
        videoSourceAuthorCache[path] = Optional.some(author)
        return author
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
        let platform = inferredVideoSource(
            for: video,
            sourceInfo: sourceInfoByVideoPath[path]
        ).platform
        videoSourcePlatformCache[path] = platform
        return platform
    }

    func subjectiveVideoTags(forPath path: String, tags: [String]) -> [String] {
        subjectiveVideoTags(forPath: path, tags: tags, sourceInfo: sourceInfoByVideoPath[path])
    }

    func subjectiveVideoTags(forPath _: String, tags: [String], sourceInfo: VideoSourceInfo?) -> [String] {
        var sourceValues: [String] = []
        if let rawPlatform = sourceInfo?.platform,
           let platform = Self.canonicalSourcePlatform(rawPlatform) {
            sourceValues.append(platform)
        }
        if let rawAuthor = sourceInfo?.authorName,
           let author = Self.normalizedSourceAuthorName(rawAuthor) {
            sourceValues.append(author)
        }
        if let rawTitle = sourceInfo?.title,
           let title = Self.normalizedSourceTitle(rawTitle) {
            sourceValues.append(title)
        }
        let sourceValueKeys = Set(sourceValues.compactMap(Self.normalizedSubjectiveTagKey))

        var seenKeys = Set<String>()
        return tags.compactMap { rawTag in
            guard let tag = Self.normalizedImportTag(rawTag),
                  let key = Self.normalizedSubjectiveTagKey(tag),
                  !Self.looksLikeSourceMetadataFragment(tag),
                  Self.canonicalSourcePlatform(tag) == nil,
                  !Self.isRemovedDefaultVideoTagSuggestion(tag),
                  !sourceValueKeys.contains(key),
                  seenKeys.insert(key).inserted
            else { return nil }

            return tag
        }
    }

    func sourceTag(forImportedVideo video: VideoItem) -> String? {
        let components = video.url.pathComponents
        guard
            let importsIndex = components.lastIndex(of: "Imports"),
            components.indices.contains(importsIndex + 1)
        else { return nil }

        let folder = components[importsIndex + 1]
        return Self.canonicalSourcePlatform(folder)
    }

    func inferredVideoSource(
        for video: VideoItem,
        sourceInfo: VideoSourceInfo?,
        readExtendedAttributes: Bool = false
    ) -> VideoSourceInference {
        let importedPlatform = sourceInfo.flatMap { Self.canonicalSourcePlatform($0.platform) }
        let explicitImportedPlatform = importedPlatform.flatMap {
            Self.isUnknownSourcePlatform($0) ? nil : $0
        }
        let storedSourceURLs = Self.sourceURLs(from: sourceInfo)
        let shouldReadWhereFromURLs = readExtendedAttributes && explicitImportedPlatform == nil && storedSourceURLs.isEmpty
        let whereFromURLs = shouldReadWhereFromURLs ? Self.whereFromURLs(for: video.url) : []
        let sourceURLs = Self.uniqueURLs(storedSourceURLs + whereFromURLs)
        let importedAuthorName = sourceInfo?.authorName
        let videoTags = tagsByVideoPath[video.url.path, default: []]
        let inferredPlatforms = [
            Self.sourcePlatform(from: sourceURLs),
            sourceTag(forImportedVideo: video),
            Self.sourcePlatform(fromPathComponents: video.url.pathComponents),
            Self.sourcePlatform(fromText: video.name),
            Self.sourcePlatform(fromVideoTags: videoTags)
        ].compactMap { $0 }
        let concreteInferredPlatform = inferredPlatforms.first { !Self.isUnknownSourcePlatform($0) }
        let platform = [
            explicitImportedPlatform,
            concreteInferredPlatform,
            importedPlatform,
            inferredPlatforms.first
        ].compactMap { $0 }.first ?? Self.unknownSourcePlatformName

        let sourceURL = sourceURLs.first(where: Self.isUsefulSourceURL)
        let authorName = importedAuthorName.flatMap(Self.normalizedSourceAuthorName)
            ?? Self.sourceAuthorName(from: sourceURLs, fileName: video.url.lastPathComponent)
        let title = sourceInfo?.title.flatMap(Self.normalizedSourceTitle)
            ?? Self.sourceTitle(from: sourceURLs, fileName: video.url.lastPathComponent)

        return VideoSourceInference(platform: platform, sourceURL: sourceURL, authorName: authorName, title: title)
    }

    nonisolated static func sourceURLs(from sourceInfo: VideoSourceInfo?) -> [URL] {
        guard
            let sourceURL = sourceInfo?.sourceURL,
            let url = URL(string: sourceURL)
        else { return [] }
        return [url]
    }

    nonisolated static func sourcePlatform(from urls: [URL]) -> String? {
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

    nonisolated static func normalizedSubjectiveTagKey(_ rawValue: String) -> String? {
        normalizedImportTag(rawValue)?.lowercased()
    }

    nonisolated static func normalizedSourcePlatform(_ rawValue: String?) -> String {
        guard let rawValue,
              normalizedImportTag(rawValue) != nil
        else { return unknownSourcePlatformName }
        return canonicalSourcePlatform(rawValue) ?? unknownSourcePlatformName
    }

    nonisolated static func looksLikeSourceIdentityTag(_ rawValue: String) -> Bool {
        let normalized = normalizedSpaces(rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        let compact = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "@# "))

        if normalized.range(
            of: #"(?i)^instagram\s+id\s+\d{6,}$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if compact.range(
            of: #"^\d{6,}$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if compact.range(
            of: #"(?i)^[0-9a-f]{8,}$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if compact.range(
            of: #"(?i)^UC[A-Za-z0-9_-]{20,}$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if compact.range(
            of: #"^[A-Za-z0-9_-]{18,}$"#,
            options: .regularExpression
        ) != nil {
            let digitCount = compact.filter(\.isNumber).count
            let letterCount = compact.filter(\.isLetter).count
            return digitCount >= 4 || letterCount == 0
        }

        return false
    }

    nonisolated static func looksLikeSourceMetadataFragment(_ rawValue: String) -> Bool {
        let normalized = normalizedSpaces(rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let lowercased = normalized.lowercased()
        if looksLikeSourceIdentityTag(normalized) { return true }
        if lowercased.contains("http://")
            || lowercased.contains("https://")
            || lowercased.contains("www.")
            || lowercased.contains(".com") {
            return true
        }
        if normalized.contains("/") || normalized.contains("\\") {
            return true
        }
        if normalized.contains("...") || normalized.contains("…") {
            return true
        }
        return normalized.range(
            of: #"(?i)\.(mp4|mov|m4v|webm|mkv|avi|m2ts|mts)$"#,
            options: .regularExpression
        ) != nil
    }

    nonisolated static func normalizedSourceAuthorName(_ rawValue: String) -> String? {
        guard let author = normalizedImportTag(rawValue) else { return nil }
        guard !looksLikeSourceMetadataFragment(author),
              canonicalSourcePlatform(author) == nil,
              sourcePlatform(fromText: author) == nil,
              !isGenericImportTitle(author),
              !looksLikeTechnicalSourceTitle(author)
        else { return nil }
        return author
    }

    nonisolated static func sourceAuthorName(fromVideoTags tags: [String]) -> String? {
        for tag in tags {
            if let author = sourceAuthorName(fromVideoTag: tag) {
                return author
            }
        }

        let candidates = tags.compactMap(normalizedSourceAuthorName)
        guard !candidates.isEmpty else { return nil }

        let hasPlatformTag = tags.contains { tag in
            if canonicalSourcePlatform(tag) != nil {
                return true
            }
            return looksLikeSourceMetadataFragment(tag) && sourcePlatform(fromText: tag) != nil
        }
        if hasPlatformTag {
            return candidates.first
        }

        return nil
    }

    nonisolated static func sourcePlatform(fromVideoTags tags: [String]) -> String? {
        for tag in tags {
            if let platform = canonicalSourcePlatform(tag) ?? sourcePlatform(fromText: tag) {
                return platform
            }
        }
        return nil
    }

    nonisolated static func sourceAuthorName(fromVideoTag rawValue: String) -> String? {
        let tag = normalizedSpaces(rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return nil }

        if let handle = firstMentionHandle(in: tag) {
            return handle
        }

        if let author = authorNameAfterLeadingBy(in: tag) {
            return author
        }

        let labels = [
            "作者", "博主", "UP主", "up主",
            "creator", "author", "uploader", "channel",
            "user", "username", "nickname"
        ]
        var separators = CharacterSet.whitespacesAndNewlines
        separators.insert(charactersIn: ":：-=–—")

        for label in labels {
            guard let labelRange = tag.range(of: label, options: [.caseInsensitive, .anchored]) else {
                continue
            }

            let rawRemainder = String(tag[labelRange.upperBound...])
            guard let firstScalar = rawRemainder.unicodeScalars.first,
                  separators.contains(firstScalar)
            else { continue }

            let remainder = rawRemainder.trimmingCharacters(in: separators)
            if let author = normalizedSourceAuthorName(remainder) {
                return author
            }
        }

        return nil
    }

    nonisolated static func authorNameAfterLeadingBy(in rawValue: String) -> String? {
        guard let byRange = rawValue.range(of: "by", options: [.caseInsensitive, .anchored]) else {
            return nil
        }

        let rawRemainder = String(rawValue[byRange.upperBound...])
        guard let firstScalar = rawRemainder.unicodeScalars.first,
              CharacterSet.whitespacesAndNewlines.contains(firstScalar)
        else { return nil }

        return normalizedSourceAuthorName(rawRemainder)
    }

    nonisolated static func sourcePlatform(fromPathComponents components: [String]) -> String? {
        components.compactMap(canonicalSourcePlatform).first
    }

    nonisolated static func sourcePlatform(fromText text: String) -> String? {
        let lowercased = text.lowercased()
        if lowercased.contains("instagram.com")
            || lowercased.contains("instagr.am")
            || lowercased.contains("sssinstagram")
            || lowercased.contains("cdninstagram")
            || lowercased.contains("instagram")
            || lowercased.range(
                of: #"(?i)(^|[^a-z0-9])insta([^a-z0-9]|$)"#,
                options: .regularExpression
            ) != nil
            || lowercased.range(
                of: #"(?i)(^|[\s._-])ig([\s._-]|$)"#,
                options: .regularExpression
            ) != nil {
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

    nonisolated static func isUnknownSourcePlatform(_ platform: String?) -> Bool {
        guard let platform else { return true }
        return canonicalSourcePlatform(platform) == unknownSourcePlatformName
    }

    nonisolated static func canonicalSourcePlatform(_ rawValue: String) -> String? {
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
        case "其他", "other", "others", "unknown":
            return unknownSourcePlatformName
        default:
            return nil
        }
    }

    nonisolated static func whereFromURLs(for fileURL: URL) -> [URL] {
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

    nonisolated static func sourceURLs(in text: String) -> [URL] {
        var urls: [URL] = []
        if let url = URL(string: text), url.scheme != nil {
            urls.append(url)
            urls.append(contentsOf: embeddedSourceURLs(in: url))
        }
        return urls
    }

    nonisolated static func embeddedSourceURLs(in url: URL) -> [URL] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        let sourceQueryNames = Set(["url", "u", "uri", "referer", "referrer", "source", "source_url"])
        return components.queryItems?
            .filter { sourceQueryNames.contains($0.name.lowercased()) }
            .compactMap { $0.value }
            .flatMap(sourceURLs(in:)) ?? []
    }

    nonisolated static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    nonisolated static func isUsefulSourceURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return platformName(for: url) != nil
            && !host.contains("fbcdn.net")
            && !host.contains("cdninstagram.com")
            && !host.contains("sssinstagram.com")
            && !host.contains("googlevideo.com")
            && url.path != "/"
            && !url.path.isEmpty
    }

    nonisolated static func usefulSourceURLString(_ rawValue: String?) -> String? {
        guard
            let rawValue,
            let url = URL(string: rawValue),
            isUsefulSourceURL(url)
        else { return nil }
        return rawValue
    }

    nonisolated static func sourceAuthorName(from urls: [URL], fileName: String) -> String? {
        let queryHints = urls.flatMap { url -> [String] in
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
            return components.queryItems?.compactMap(\.value) ?? []
        }
        let pathHints = urls.flatMap(sourceAuthorHints(from:))
        let hints = [fileName] + queryHints + urls.map(\.absoluteString)
        return hints.lazy.compactMap(firstMentionHandle).first
            ?? pathHints.lazy.compactMap(normalizedSourceAuthorName).first
    }

    nonisolated static func firstMentionHandle(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.])@([A-Za-z0-9_.]{2,30})"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return normalizedSourceAuthorName(String(text[captureRange]))
    }

    nonisolated static func sourceAuthorHints(from url: URL) -> [String] {
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

    nonisolated static func sourceTitle(from urls: [URL], fileName: String) -> String? {
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

    nonisolated static func sourceTitleFamilyKey(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        var title = decodedSourceText(rawValue)
        title = fileStem(from: title)
        title = normalizedSpaces(title)
        title = title.replacingOccurrences(
            of: #"(?i)\.(mp4|mov|m4v|webm|mkv|avi|m2ts|mts)$"#,
            with: "",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: #"\s+[-–—_]\s*0?\d{1,3}$"#,
            with: "",
            options: .regularExpression
        )
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isGenericImportTitle(title), !looksLikeTechnicalSourceTitle(title) else {
            return nil
        }
        let key = normalizedSearch(title)
        return key.count >= 8 ? key : nil
    }

    nonisolated static func normalizedSourceTitle(_ rawValue: String) -> String? {
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

    nonisolated static func screenedSourceTitle(
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

    nonisolated static func isDirectMediaURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "webm", "mkv", "avi", "m2ts", "mts"].contains(ext)
    }

    nonisolated static func looksLikeTechnicalSourceTitle(_ title: String) -> Bool {
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

    nonisolated static func decodedSourceText(_ text: String) -> String {
        var current = text
        for _ in 0..<2 {
            guard let decoded = current.removingPercentEncoding, decoded != current else { break }
            current = decoded
        }
        return current
    }

    nonisolated static func importFolderName(for platform: String) -> String {
        let safeFolder = platform.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return safeFolder.isEmpty ? "Other" : safeFolder
    }

}
