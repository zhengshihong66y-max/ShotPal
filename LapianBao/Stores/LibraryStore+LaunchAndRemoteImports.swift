//
//  LibraryStore+LaunchAndRemoteImports.swift
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

nonisolated private final class ChromeCookieFileCache: @unchecked Sendable {
    private let condition = NSCondition()
    private let timeToLive: TimeInterval
    private var cachedURL: URL?
    private var cachedAt: Date?
    private var isRefreshing = false

    init(timeToLive: TimeInterval) {
        self.timeToLive = timeToLive
    }

    func validCookieURL() -> URL? {
        condition.lock()
        let url = validCookieURLLocked(now: Date())
        condition.unlock()
        return url
    }

    func tryStartRefresh() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard !isRefreshing else { return false }
        isRefreshing = true
        return true
    }

    func waitForRefresh() -> URL? {
        condition.lock()
        while isRefreshing {
            condition.wait()
        }
        let url = validCookieURLLocked(now: Date())
        condition.unlock()
        return url
    }

    func finishRefresh(with url: URL?) {
        var oldURL: URL?
        condition.lock()
        if let url {
            oldURL = cachedURL
            cachedURL = url
            cachedAt = Date()
        }
        isRefreshing = false
        condition.broadcast()
        condition.unlock()

        if let oldURL, oldURL != url {
            try? FileManager.default.removeItem(at: oldURL)
        }
    }

    func invalidate(_ url: URL? = nil) {
        var removedURL: URL?
        condition.lock()
        if url == nil || url == cachedURL {
            removedURL = cachedURL
            cachedURL = nil
            cachedAt = nil
        }
        condition.unlock()

        if let removedURL {
            try? FileManager.default.removeItem(at: removedURL)
        }
    }

    private func validCookieURLLocked(now: Date) -> URL? {
        guard let cachedURL,
              let cachedAt,
              now.timeIntervalSince(cachedAt) < timeToLive,
              FileManager.default.fileExists(atPath: cachedURL.path),
              (((try? cachedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0)
        else { return nil }
        return cachedURL
    }
}

extension LibraryStore {
    nonisolated private static let chromeCookieFileCache = ChromeCookieFileCache(timeToLive: 10 * 60)

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
                videoFolderTagsByPath: cached.folderTagsByPath,
                cachedMetadataByPath: cached.metadataByPath,
                cachedThumbnailDataByPath: cached.thumbnailDataByPath,
                cachedPlaybackSupportByPath: cached.playbackSupportByPath
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
                    videoFolderTagsByPath: quickSnapshot.folderTagsByPath,
                    cachedMetadataByPath: quickSnapshot.metadataByPath,
                    cachedThumbnailDataByPath: quickSnapshot.thumbnailDataByPath,
                    cachedPlaybackSupportByPath: quickSnapshot.playbackSupportByPath
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
                    cachedMetadataByPath: organized.metadataByPath,
                    cachedThumbnailDataByPath: organized.thumbnailDataByPath,
                    cachedPlaybackSupportByPath: organized.playbackSupportByPath,
                    preservedSelectionPath: selectedPath,
                    preservedSelectedTags: selectedTags
                )
            }
        }
    }

    func reconcileVideoLibraryAfterLaunch(in url: URL, after delay: TimeInterval) {
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
                    cachedMetadataByPath: organized.metadataByPath,
                    cachedThumbnailDataByPath: organized.thumbnailDataByPath,
                    cachedPlaybackSupportByPath: organized.playbackSupportByPath,
                    preservedSelectionPath: selectedPath,
                    preservedSelectedTags: selectedTags
                )
            }
        }
    }

    func lastLibraryURLForLoading() -> URL? {
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

    func defaultLibraryURL() -> URL? {
        let url = URL(fileURLWithPath: defaultLibraryPath)
        return isExistingDirectory(url) ? url : nil
    }

    func isExistingDirectory(_ url: URL) -> Bool {
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

    func prewarmSavedCollectionCookieCache() {
        Self.prewarmChromeCookieCache()
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
        enqueueRemoteImport(
            from: job.sourceURL.absoluteString,
            initialThumbnailData: job.thumbnailData,
            selectOnCompletion: true,
            batchID: job.batchID,
            batchTitle: job.batchTitle,
            batchTotalCount: job.batchTotalCount,
            batchIndex: job.batchIndex
        )
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

        let shouldSelectOnCompletion = inputs.count == 1
        let batchID = inputs.count > 1 ? UUID() : nil
        let batchTitle = batchID.map { _ in "批量导入" }
        for (index, rawURL) in inputs.enumerated() {
            enqueueRemoteImport(
                from: rawURL,
                selectOnCompletion: shouldSelectOnCompletion,
                batchID: batchID,
                batchTitle: batchTitle,
                batchTotalCount: inputs.count,
                batchIndex: index + 1
            )
        }
    }

    func importLatestInstagramSavedFromChrome(limit: Int = 50) async throws -> InstagramSavedImportResult {
        guard libraryURL != nil else {
            throw InstagramSavedImportError.noLibrary
        }
        startExternalServiceSelfCheckPreflightIfNeeded()

        let alreadyQueuedOrImported = queuedOrImportedInstagramSourceURLs()
        let knownKeys = queuedOrImportedInstagramSourceKeys()
            .union(instagramSavedBaselineKnownSourceKeys())
        let scan = try await Self.fetchLatestInstagramSavedLinksFromChrome(
            limit: limit,
            knownContentKeys: knownKeys
        )
        let discoveredLinks = scan.links
        let linksToImport = discoveredLinks.filter { link in
            guard !alreadyQueuedOrImported.contains(link) else { return false }
            guard let key = Self.instagramContentKey(link) else { return true }
            return !knownKeys.contains(key)
        }
        let skippedLinks = discoveredLinks.filter { !linksToImport.contains($0) }
        recordInstagramSavedSyncSnapshot(
            discoveredLinks: discoveredLinks,
            skippedLinks: skippedLinks,
            queuedLinks: linksToImport,
            scannedPageCount: scan.pageCount,
            stoppedAtKnownBaseline: scan.stoppedAtKnownBaseline
        )

        let batchID = linksToImport.count > 1 ? UUID() : nil
        for (index, link) in linksToImport.enumerated() {
            enqueueRemoteImport(
                from: link,
                selectOnCompletion: false,
                batchID: batchID,
                batchTitle: "IG 收藏同步",
                batchTotalCount: linksToImport.count,
                batchIndex: index + 1
            )
        }

        return InstagramSavedImportResult(
            foundCount: discoveredLinks.count,
            skippedCount: discoveredLinks.count - linksToImport.count,
            queuedCount: linksToImport.count,
            queuedLinks: linksToImport,
            scannedPageCount: scan.pageCount,
            stoppedAtKnownBaseline: scan.stoppedAtKnownBaseline
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

        let batchID = linksToImport.count > 1 ? UUID() : nil
        for (index, link) in linksToImport.enumerated() {
            enqueueRemoteImport(
                from: link,
                selectOnCompletion: false,
                batchID: batchID,
                batchTitle: "小红书视频同步",
                batchTotalCount: linksToImport.count,
                batchIndex: index + 1
            )
        }

        return InstagramSavedImportResult(
            foundCount: discoveredLinks.count,
            skippedCount: discoveredLinks.count - linksToImport.count,
            queuedCount: linksToImport.count,
            queuedLinks: linksToImport
        )
    }

    func queuedOrImportedInstagramSourceURLs() -> Set<String> {
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

    func queuedOrImportedInstagramSourceKeys() -> Set<String> {
        var keys = Set<String>()

        for info in sourceInfoByVideoPath.values {
            if let sourceURL = info.sourceURL,
               let key = Self.instagramContentKey(sourceURL) {
                keys.insert(key)
            }
        }

        for job in remoteImportJobs where Self.remoteImportJobCountsAsQueuedOrImported(job.status) {
            if let key = Self.instagramContentKey(job.sourceURL.absoluteString) {
                keys.insert(key)
            }
        }

        return keys
    }

    func instagramSavedBaselineURL() -> URL? {
        libraryURL?.appendingPathComponent(".lapianbao_ig_saved_baseline.json")
    }

    func instagramSavedBaselineKnownSourceKeys() -> Set<String> {
        guard
            let url = instagramSavedBaselineURL(),
            let data = try? Data(contentsOf: url),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let results = root["results"] as? [String: Any]
        else { return [] }

        let knownStatuses = Set(["already_recorded", "downloaded", "duplicate"])
        var keys = Set<String>()
        for (rawKey, rawValue) in results {
            guard let entry = rawValue as? [String: Any] else { continue }
            let status = entry["status"] as? String
            guard status.map(knownStatuses.contains) == true else { continue }
            if let key = Self.instagramContentKey(rawKey) {
                keys.insert(key)
            }
            if let sourceURL = entry["sourceURL"] as? String,
               let key = Self.instagramContentKey(sourceURL) {
                keys.insert(key)
            }
        }
        return keys
    }

    func recordInstagramSavedSyncSnapshot(
        discoveredLinks: [String],
        skippedLinks: [String],
        queuedLinks: [String],
        scannedPageCount: Int,
        stoppedAtKnownBaseline: Bool
    ) {
        guard let url = instagramSavedBaselineURL() else { return }

        var root = Self.readJSONObject(at: url)
        var results = root["results"] as? [String: Any] ?? [:]
        let now = Self.iso8601String(Date())
        let queuedSet = Set(queuedLinks)
        let skippedSet = Set(skippedLinks)

        for link in discoveredLinks {
            var entry = results[link] as? [String: Any] ?? [:]
            entry["sourceURL"] = link
            entry["updatedAt"] = now
            if queuedSet.contains(link) {
                entry["status"] = "queued"
            } else if skippedSet.contains(link) {
                let status = entry["status"] as? String
                if status != "downloaded" && status != "duplicate" {
                    entry["status"] = "already_recorded"
                }
            }
            results[link] = entry
        }

        root["version"] = 1
        root["updatedAt"] = now
        root["lastSeenLinks"] = discoveredLinks
        root["lastSeenCount"] = discoveredLinks.count
        root["scannedPageCount"] = scannedPageCount
        root["stoppedAtKnownBaseline"] = stoppedAtKnownBaseline
        root["results"] = results
        Self.writeJSONObject(root, to: url)
    }

    func recordInstagramSavedImportStatus(
        sourceURL: URL,
        status: String,
        outputURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        guard Self.isInstagramURL(sourceURL),
              let url = instagramSavedBaselineURL()
        else { return }

        var root = Self.readJSONObject(at: url)
        var results = root["results"] as? [String: Any] ?? [:]
        let key = Self.normalizedInstagramContentURL(sourceURL.absoluteString) ?? sourceURL.absoluteString
        let now = Self.iso8601String(Date())
        var entry = results[key] as? [String: Any] ?? [:]
        entry["sourceURL"] = key
        entry["status"] = status
        entry["updatedAt"] = now
        if let outputURL, let libraryURL {
            entry["file"] = Self.libraryRelativePath(for: outputURL, base: libraryURL)
        }
        if let errorMessage {
            entry["error"] = errorMessage
        } else {
            entry.removeValue(forKey: "error")
        }
        results[key] = entry
        root["version"] = 1
        root["updatedAt"] = now
        root["results"] = results
        Self.writeJSONObject(root, to: url)
    }

    func queuedOrImportedXiaohongshuSourceURLs() -> Set<String> {
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

    func enqueueRemoteImport(
        from rawURL: String,
        initialThumbnailData: Data? = nil,
        selectOnCompletion: Bool = true,
        batchID: UUID? = nil,
        batchTitle: String? = nil,
        batchTotalCount: Int? = nil,
        batchIndex: Int? = nil
    ) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sourceURL = URL(string: trimmed) else {
            remoteImportJobs.append(RemoteImportJob(
                sourceURL: Self.placeholderRemoteImportURL,
                platform: "未知平台",
                batchID: batchID,
                batchTitle: batchTitle,
                batchTotalCount: batchTotalCount,
                batchIndex: batchIndex,
                status: .failed("请输入有效链接")
            ))
            return
        }

        guard let platform = Self.platformName(for: sourceURL) else {
            remoteImportJobs.append(RemoteImportJob(
                sourceURL: sourceURL,
                platform: "未知平台",
                batchID: batchID,
                batchTitle: batchTitle,
                batchTotalCount: batchTotalCount,
                batchIndex: batchIndex,
                status: .failed("暂不支持该平台，目前支持 Instagram、YouTube、小红书、Bilibili 和抖音")
            ))
            return
        }

        guard let libraryURL else {
            remoteImportJobs.append(RemoteImportJob(
                sourceURL: sourceURL,
                platform: platform,
                batchID: batchID,
                batchTitle: batchTitle,
                batchTotalCount: batchTotalCount,
                batchIndex: batchIndex,
                status: .failed("请先打开一个素材库文件夹")
            ))
            return
        }

        let endpoint = instagramImportEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let job = RemoteImportJob(
            sourceURL: sourceURL,
            platform: platform,
            batchID: batchID,
            batchTitle: batchTitle,
            batchTotalCount: batchTotalCount,
            batchIndex: batchIndex,
            status: .importing,
            thumbnailData: initialThumbnailData
        )
        remoteImportJobs.append(job)
        recordInstagramSavedImportStatus(sourceURL: sourceURL, status: "queued")
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
                    guard Self.remoteImportJobCanReceiveWorkerProgress(job.status) else { return }
                    job.status = .transcoding
                    job.downloadProgress = progress.map(Self.normalizedProgress)
                    job.downloadSpeed = nil
                }
            }
        }
        let finalizingCallback: @Sendable (Double) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateRemoteImportJob(id: jobID) { job in
                    guard Self.remoteImportJobCanReceiveWorkerProgress(job.status) else { return }
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
                if let importedVideo = self?.integrateDownloadedVideo(outputURL, into: libraryURL) {
                    self?.recordImportedVideoSource(
                        videoURL: outputURL,
                        sourceURL: sourceURL,
                        platform: platform,
                        authorName: downloadedVideo.authorName,
                        sourceTitle: downloadedVideo.sourceTitle
                    )
                    self?.recordInstagramSavedImportStatus(
                        sourceURL: sourceURL,
                        status: "downloaded",
                        outputURL: outputURL
                    )
                    self?.addImportTags(to: importedVideo, platform: platform, authorName: downloadedVideo.authorName)
                    if selectOnCompletion || self?.selectedVideo == nil {
                        self?.selectVideo(importedVideo, autoplay: false)
                    } else {
                        self?.loadMetadataIfNeeded(for: importedVideo)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.updateRemoteImportJob(id: jobID) { job in
                    job.status = .failed(error.localizedDescription)
                    job.downloadProgress = nil
                    job.downloadSpeed = nil
                }
                self?.recordInstagramSavedImportStatus(
                    sourceURL: sourceURL,
                    status: "failed",
                    errorMessage: error.localizedDescription
                )
            }
        }
        remoteImportTasks[jobID] = task
    }

    func updateRemoteImportJob(id: UUID, mutate: (inout RemoteImportJob) -> Void) {
        guard let index = remoteImportJobs.firstIndex(where: { $0.id == id }) else { return }
        var updatedJobs = remoteImportJobs
        let previousJob = updatedJobs[index]
        mutate(&updatedJobs[index])
        if Self.isTerminalRemoteImportStatus(previousJob.status),
           Self.remoteImportJobCanReceiveWorkerProgress(updatedJobs[index].status) {
            updatedJobs[index] = previousJob
        }
        remoteImportJobs = updatedJobs
    }

    nonisolated static func isTerminalRemoteImportStatus(_ status: RemoteImportJob.Status) -> Bool {
        switch status {
        case .succeeded, .failed:
            return true
        case .idle, .importing, .transcoding, .finalizing, .paused:
            return false
        }
    }

    nonisolated static func remoteImportJobCanReceiveWorkerProgress(_ status: RemoteImportJob.Status) -> Bool {
        switch status {
        case .importing, .transcoding, .finalizing:
            return true
        case .idle, .paused, .succeeded, .failed:
            return false
        }
    }

    func integrateDownloadedVideo(_ outputURL: URL, into libraryURL: URL) -> VideoItem? {
        let fileURL = outputURL.standardizedFileURL
        let outputPath = fileURL.path
        let libraryPath = libraryURL.standardizedFileURL.path
        guard self.libraryURL?.standardizedFileURL.path == libraryPath else { return nil }
        guard FileManager.default.fileExists(atPath: outputPath) else { return nil }
        guard videoExtensions.contains(fileURL.pathExtension.lowercased()) else { return nil }
        guard outputPath == libraryPath || outputPath.hasPrefix(libraryPath + "/") else { return nil }

        let importedVideo = VideoItem(url: fileURL)
        metadataByVideoPath[outputPath] = Self.fileResourceMetadata(
            for: fileURL,
            preserving: metadataByVideoPath[outputPath]
        )

        if videos.contains(where: { $0.url.path == outputPath }) {
            refreshFilteredVideos()
            return importedVideo
        }

        var nextVideos = videos.filter { $0.url.path != outputPath }
        nextVideos.append(importedVideo)
        videos = nextVideos.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return importedVideo
    }

    func addImportTags(to video: VideoItem, platform: String, authorName: String?) {
        addImportTags(toPath: video.url.path, platform: platform, authorName: authorName)
    }

    func addImportTags(toPath path: String, platform: String?, authorName: String?) {
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

    func recordImportedVideoSource(
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

    nonisolated static func normalizedImportTag(_ rawValue: String) -> String? {
        let tag = stripTrailingSourceID(normalizedSpaces(rawValue))
            .trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        guard !tag.isEmpty, tag.count <= 64 else { return nil }
        guard URL(string: tag)?.scheme == nil else { return nil }
        return tag
    }

    func loadRemoteImportThumbnail(for jobID: UUID, sourceURL: URL) {
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

    nonisolated static func remoteImportURLs(from text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，"))
        var seen = Set<String>()
        return text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
            .filter { seen.insert($0).inserted }
    }

    nonisolated static func normalizedInstagramContentURL(_ rawValue: String) -> String? {
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

    nonisolated static func instagramContentKey(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let content = instagramContentParts(from: url)
        else { return nil }

        let itemIndex = instagramCarouselItemIndex(from: url) ?? 1
        return "\(content.shortcode)#\(max(1, itemIndex))"
    }

    nonisolated static func instagramContentParts(from url: URL) -> (type: String, shortcode: String)? {
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

    nonisolated static func instagramBaseContentURL(from url: URL) -> URL? {
        guard let content = instagramContentParts(from: url) else { return nil }
        return URL(string: "https://www.instagram.com/\(content.type)/\(content.shortcode)/")
    }

    nonisolated static func instagramCarouselItemURLString(baseURL: URL, itemIndex: Int) -> String {
        guard itemIndex > 1 else {
            return instagramBaseContentURL(from: baseURL)?.absoluteString ?? baseURL.absoluteString
        }
        let baseURLString = instagramBaseContentURL(from: baseURL)?.absoluteString ?? baseURL.absoluteString
        return "\(baseURLString)?img_index=\(itemIndex)"
    }

    nonisolated static func instagramCarouselItemIndex(from url: URL) -> Int? {
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

    nonisolated static func ytdlpSourceURL(for sourceURL: URL) -> URL {
        instagramCarouselItemIndex(from: sourceURL) == nil
            ? sourceURL
            : (instagramBaseContentURL(from: sourceURL) ?? sourceURL)
    }

    nonisolated static func ytdlpPlaylistSelectionArguments(for sourceURL: URL) -> [String] {
        guard let itemIndex = instagramCarouselItemIndex(from: sourceURL) else {
            return ["--no-playlist"]
        }
        return ["--yes-playlist", "--playlist-items", "\(itemIndex)"]
    }

    nonisolated static func normalizedXiaohongshuNoteURL(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let absoluteString: String
        if trimmed.hasPrefix("/") {
            absoluteString = "https://www.xiaohongshu.com\(trimmed)"
        } else {
            absoluteString = trimmed
        }
        guard var components = URLComponents(string: absoluteString),
              let url = components.url,
              let host = url.host?.lowercased()
        else { return nil }

        if host.contains("xhslink.com") {
            return absoluteString
        }

        guard host == "xiaohongshu.com" || host.hasSuffix(".xiaohongshu.com") else { return nil }
        guard let noteID = xiaohongshuNoteID(from: url) else { return nil }

        components.scheme = "https"
        components.host = "www.xiaohongshu.com"
        components.path = "/explore/\(noteID)"
        let allowedQueryNames = Set(["xsec_token", "xsec_source"])
        components.queryItems = components.queryItems?
            .filter { allowedQueryNames.contains($0.name) }
        return components.url?.absoluteString ?? "https://www.xiaohongshu.com/explore/\(noteID)"
    }

    nonisolated static func xiaohongshuNoteID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        let noteID: String?
        if parts.count >= 2, parts[0] == "explore" || parts[0] == "search_result" {
            noteID = parts[1]
        } else if parts.count >= 3, parts[0] == "discovery", parts[1] == "item" {
            noteID = parts[2]
        } else if parts.count >= 4, parts[0] == "user", parts[1] == "profile" {
            noteID = parts[3]
        } else {
            noteID = nil
        }

        guard let noteID,
              !noteID.isEmpty,
              noteID != "undefined",
              noteID != "null"
        else { return nil }
        return noteID
    }

    nonisolated static func remoteImportJobCountsAsQueuedOrImported(_ status: RemoteImportJob.Status) -> Bool {
        switch status {
        case .importing, .transcoding, .finalizing, .paused, .succeeded:
            return true
        case .idle, .failed:
            return false
        }
    }

    nonisolated struct CurlFetchResult: Sendable {
        var statusCode: Int
        var data: Data
    }

    nonisolated static func readJSONObject(at url: URL) -> [String: Any] {
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else { return [:] }
        return dictionary
    }

    nonisolated static func writeJSONObject(_ object: [String: Any], to url: URL) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    nonisolated static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    nonisolated struct InstagramSavedScanResult: Sendable {
        var links: [String]
        var itemCount: Int
        var pageCount: Int
        var stoppedAtKnownBaseline: Bool
    }

    nonisolated struct InstagramSavedFeedResponse: Decodable {
        var items: [InstagramSavedFeedItem]
        var moreAvailable: Bool?
        var nextMaxID: String?

        enum CodingKeys: String, CodingKey {
            case items
            case moreAvailable = "more_available"
            case nextMaxID = "next_max_id"
        }
    }

    nonisolated struct InstagramSavedFeedItem: Decodable {
        var media: InstagramSavedMedia?
        var item: InstagramSavedMedia?
        var carouselMedia: [InstagramSavedMedia]?

        var bestMedia: InstagramSavedMedia? {
            media ?? item ?? carouselMedia?.first
        }

        enum CodingKeys: String, CodingKey {
            case media, item
            case carouselMedia = "carousel_media"
        }
    }

    nonisolated struct InstagramSavedMedia: Decodable {
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

        enum CodingKeys: String, CodingKey {
            case code
            case mediaType = "media_type"
            case productType = "product_type"
            case carouselMedia = "carousel_media"
            case videoVersions = "video_versions"
        }
    }

    nonisolated struct InstagramSavedVideoVersion: Decodable {
        var url: String?
    }

    nonisolated static func withExportedChromeCookies<T>(
        seedURLString _: String,
        _ body: (URL) throws -> T
    ) throws -> T {
        let cookieURL = try cachedOrExportedChromeCookieURL()
        do {
            return try body(cookieURL)
        } catch {
            guard shouldRefreshChromeCookies(after: error) else { throw error }
            chromeCookieFileCache.invalidate(cookieURL)
            let freshCookieURL = try cachedOrExportedChromeCookieURL(forceRefresh: true)
            return try body(freshCookieURL)
        }
    }

    nonisolated static func prewarmChromeCookieCache() {
        Task.detached(priority: .utility) {
            _ = try? cachedOrExportedChromeCookieURL()
        }
    }

    nonisolated static func cachedOrExportedChromeCookieURL(forceRefresh: Bool = false) throws -> URL {
        if forceRefresh {
            chromeCookieFileCache.invalidate()
        } else if let cachedURL = chromeCookieFileCache.validCookieURL() {
            return cachedURL
        }

        while !chromeCookieFileCache.tryStartRefresh() {
            if let cachedURL = chromeCookieFileCache.waitForRefresh() {
                return cachedURL
            }
        }

        do {
            let cookieURL = try exportChromeCookiesToTemporaryFile()
            chromeCookieFileCache.finishRefresh(with: cookieURL)
            return cookieURL
        } catch {
            chromeCookieFileCache.finishRefresh(with: nil)
            throw error
        }
    }

    nonisolated static func exportChromeCookiesToTemporaryFile() throws -> URL {
        guard let ytdlp = localYTDLPURL() else {
            throw InstagramSavedImportError.chromeCookieUnavailable("未找到 yt-dlp，无法读取 Chrome Cookie")
        }

        let cookieURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lapianbao-chrome-cookies-\(UUID().uuidString).txt")

        let exportResult = runDownloaderSelfCheckProcess(
            executableURL: ytdlp,
            arguments: [
                "--cookies-from-browser", "chrome",
                "--cookies", cookieURL.path,
                "--skip-download",
                "--simulate",
                "--no-warnings"
            ],
            timeout: 28
        )
        let cookieSize = ((try? cookieURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard FileManager.default.fileExists(atPath: cookieURL.path), cookieSize > 0 else {
            throw InstagramSavedImportError.chromeCookieUnavailable(
                selfCheckFailureMessage(from: exportResult, fallback: "无法导出 Chrome Cookie")
            )
        }

        return cookieURL
    }

    nonisolated static func shouldRefreshChromeCookies(after error: Error) -> Bool {
        let message = error.localizedDescription
        return message.contains("HTTP 401") || message.contains("HTTP 403")
    }

    nonisolated static func runCurlFetch(
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

    nonisolated static func instagramVideoLinks(fromSavedMedia media: InstagramSavedMedia) -> [String] {
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

    nonisolated static func xiaohongshuVideoLinks(fromSavedHTML html: String, limit: Int) -> [String] {
        let normalizedHTML = html
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
        let sectionPattern = #"<section\b(?:(?!</section>).)*</section>"#
        let hrefPattern = #"href=["']([^"']+)["']"#
        guard let sectionRegex = try? NSRegularExpression(
            pattern: sectionPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ),
              let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: [.caseInsensitive])
        else { return [] }

        let nsString = normalizedHTML as NSString
        var videoLinks: [String] = []
        let sections = sectionRegex.matches(
            in: normalizedHTML,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        )
        for section in sections {
            let sectionHTML = nsString.substring(with: section.range)
            let lowercasedSection = sectionHTML.lowercased()
            guard lowercasedSection.contains("play-icon")
                    || lowercasedSection.contains("#play-s")
                    || lowercasedSection.contains("xgplayer")
                    || lowercasedSection.contains("player-container")
            else { continue }

            let sectionNSString = sectionHTML as NSString
            let hrefMatches = hrefRegex.matches(
                in: sectionHTML,
                options: [],
                range: NSRange(location: 0, length: sectionNSString.length)
            )
            var sectionLinks: [(url: String, hasToken: Bool)] = []
            for hrefMatch in hrefMatches where hrefMatch.numberOfRanges > 1 {
                let href = sectionNSString.substring(with: hrefMatch.range(at: 1))
                    .replacingOccurrences(of: "&amp;", with: "&")
                guard let normalized = normalizedXiaohongshuNoteURL(href) else { continue }
                sectionLinks.append((url: normalized, hasToken: href.contains("xsec_token=")))
            }
            if let selectedLink = sectionLinks.first(where: { $0.hasToken })?.url ?? sectionLinks.first?.url {
                videoLinks.append(selectedLink)
            }
        }

        var seen = Set<String>()
        return videoLinks
            .filter { seen.insert($0).inserted }
            .prefix(max(1, limit))
            .map { $0 }
    }

    nonisolated static func xiaohongshuSnippetLooksLikeVideo(in html: NSString, near location: Int) -> Bool {
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

    nonisolated static func fetchLatestInstagramSavedLinksFromChrome(limit: Int) async throws -> [String] {
        try await fetchLatestInstagramSavedLinksFromChrome(
            limit: limit,
            knownContentKeys: []
        ).links
    }

    nonisolated static func fetchLatestInstagramSavedLinksFromChrome(
        limit: Int,
        knownContentKeys: Set<String>
    ) async throws -> InstagramSavedScanResult {
        let clampedLimit = min(max(limit, 1), 50)
        return try await Task.detached(priority: .userInitiated) {
            try fetchLatestInstagramSavedLinksFromChromeCookies(
                limit: clampedLimit,
                knownContentKeys: knownContentKeys
            )
        }.value
    }

    nonisolated static func fetchLatestInstagramSavedLinksFromChromeCookies(
        limit: Int,
        knownContentKeys: Set<String>
    ) throws -> InstagramSavedScanResult {
        try withExportedChromeCookies(seedURLString: "https://www.instagram.com/") { cookieURL in
            var seen = Set<String>()
            var links: [String] = []
            var itemCount = 0
            var pageCount = 0
            var stoppedAtKnownBaseline = false
            var nextMaxID: String?
            var seenPageCursors = Set<String>()

            while true {
                if let nextMaxID, !seenPageCursors.insert(nextMaxID).inserted {
                    break
                }

                var components = URLComponents(string: "https://www.instagram.com/api/v1/feed/saved/")!
                components.queryItems = [URLQueryItem(name: "count", value: "\(limit)")]
                if let nextMaxID, !nextMaxID.isEmpty {
                    components.queryItems?.append(URLQueryItem(name: "max_id", value: nextMaxID))
                }

                let result = try runCurlFetch(
                    urlString: components.url?.absoluteString ?? "https://www.instagram.com/api/v1/feed/saved/?count=\(limit)",
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
                pageCount += 1
                itemCount += response.items.count
                var pageContainsKnownContent = false

                for item in response.items {
                    guard let media = item.bestMedia else { continue }
                    let mediaLinks = instagramVideoLinks(fromSavedMedia: media)
                    for link in mediaLinks {
                        let normalized = normalizedInstagramContentURL(link) ?? link
                        if let key = instagramContentKey(normalized),
                           knownContentKeys.contains(key) {
                            pageContainsKnownContent = true
                        }
                        if seen.insert(normalized).inserted {
                            links.append(normalized)
                        }
                    }
                }

                if pageContainsKnownContent && !knownContentKeys.isEmpty {
                    stoppedAtKnownBaseline = true
                    break
                }

                guard response.moreAvailable == true,
                      let next = response.nextMaxID,
                      !next.isEmpty,
                      next != nextMaxID
                else { break }
                nextMaxID = next
            }

            guard !links.isEmpty else {
                throw InstagramSavedImportError.noLinks
            }
            return InstagramSavedScanResult(
                links: links,
                itemCount: itemCount,
                pageCount: pageCount,
                stoppedAtKnownBaseline: stoppedAtKnownBaseline
            )
        }
    }

    nonisolated static func expandedInstagramCarouselVideoLinks(_ links: [String]) -> [String] {
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

    nonisolated static func instagramPostVideoItemLinks(executableURL: URL, sourceURL: URL) -> [String]? {
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

    nonisolated static func fetchYTDLPInstagramPlaylistInfo(
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

    nonisolated static func fetchLatestXiaohongshuSavedVideoLinksFromChrome(limit: Int) async throws -> [String] {
        let clampedLimit = min(max(limit, 1), 50)
        return try await Task.detached(priority: .userInitiated) {
            try fetchLatestXiaohongshuSavedVideoLinksFromChromeCookies(limit: clampedLimit)
        }.value
    }

    nonisolated static func fetchLatestXiaohongshuSavedVideoLinksFromChromeCookies(limit: Int) throws -> [String] {
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

    func persistLibraryAccess(for folder: URL) {
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

    func restoreLastLibraryBookmark() -> URL? {
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

    func stopAccessingScopedLibrary() {
        scopedLibraryURL?.stopAccessingSecurityScopedResource()
        scopedLibraryURL = nil
    }

}
