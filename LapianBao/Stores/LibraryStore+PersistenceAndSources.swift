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
        return libraryURL.appendingPathComponent(".lapianbaotags.json")
    }

    func sourceInfoJSONURL() -> URL? {
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

    func saveSourceInfoJSON() {
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

    func projectDataURL() -> URL? {
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

    func saveProjectData() {
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
        return dataFile
    }

    nonisolated static func writeProjectData(_ dataFile: ProjectDataFile, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dataFile)
        try Task.checkCancellation()
        try data.write(to: url, options: .atomic)
    }

    func loadProjectData() {
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

    func loadProjectDataDeferred(after delay: TimeInterval = 0) {
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

    nonisolated static func readProjectData(from url: URL) -> ProjectDataFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProjectDataFile.self, from: data)
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
        sampledFrames = decoded.sampledFrames
        annotations = decoded.annotations
        audioClips = decoded.audioClips
        transcriptSegmentsByVideoPath = decoded.transcripts
        transcriptExports = decoded.transcriptExports ?? []
        musicsByVideoPath = decoded.musicsByVideoPath ?? [:]
        musicDownloadJobs = reconciledMusicDownloadJobs(decoded.musicDownloadJobs ?? [])
        enrichMusicTagsIfNeeded()
        hydratePersistedMusicDownloadWaveformsIfNeeded()
        prepareAudioClipWaveformsIfNeeded()
        runStartupAutomationIfNeeded()
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

    func hydratePersistedMusicDownloadWaveformsIfNeeded() {
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

    func runStartupAutomationIfNeeded() {
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

    func loadSourceInfoJSON() {
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

    func applyPendingVideoPathMigrationToLoadedMetadata() {
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

    func ensureVideoSourceInfoAndTags() {
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

    func scheduleDeferredSourceInfoAndTags(for libraryPath: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.libraryURL?.path == libraryPath else { return }
            self.ensureVideoSourceInfoAndTags()
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

    func sourceTag(forImportedVideo video: VideoItem) -> String? {
        let components = video.url.pathComponents
        guard
            let importsIndex = components.lastIndex(of: "Imports"),
            components.indices.contains(importsIndex + 1)
        else { return nil }

        let folder = components[importsIndex + 1]
        return Self.canonicalSourcePlatform(folder)
    }

    func inferredVideoSource(for video: VideoItem, sourceInfo: VideoSourceInfo?, tags: [String]) -> VideoSourceInference {
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

    nonisolated static func sourcePlatform(fromTags tags: [String]) -> String? {
        tags.compactMap(canonicalSourcePlatform).first
    }

    nonisolated static func sourcePlatform(fromPathComponents components: [String]) -> String? {
        components.compactMap(canonicalSourcePlatform).first
    }

    nonisolated static func sourcePlatform(fromText text: String) -> String? {
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
            ?? pathHints.lazy.compactMap(normalizedImportTag).first
            ?? instagramAuthorID(from: urls)
    }

    nonisolated static func firstMentionHandle(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.])@([A-Za-z0-9_.]{2,30})"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return normalizedImportTag(String(text[captureRange]))
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

    nonisolated static func instagramAuthorID(from urls: [URL]) -> String? {
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
