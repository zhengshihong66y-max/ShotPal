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

private actor RemoteImportDownloadGate {
    private var activeID: UUID?
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []

    func acquire(_ id: UUID) async {
        if activeID == nil {
            activeID = id
            return
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task {
                await remoteImportDownloadGate.cancel(id)
            }
        }
    }

    func release(_ id: UUID) {
        guard activeID == id else {
            cancel(id)
            return
        }

        if waiters.isEmpty {
            activeID = nil
            return
        }

        let next = waiters.removeFirst()
        activeID = next.id
        next.continuation.resume()
    }

    func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume()
    }
}

nonisolated private let remoteImportDownloadGate = RemoteImportDownloadGate()

extension LibraryStore {
    nonisolated private static let chromeCookieFileCache = ChromeCookieFileCache(timeToLive: 10 * 60)

    func loadLastLibraryForLaunch() {
        guard libraryURL == nil else { return }
        guard let url = lastLibraryURLForLoading() else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            if let cached = Self.loadCachedVideoOrganization(in: url, includeThumbnailData: false) {
                await MainActor.run { [weak self] in
                    guard let store = self, store.libraryURL == nil else { return }
                    store.applyScannedVideos(
                        in: url,
                        urls: cached.urls,
                        deferProjectDataLoad: true,
                        projectDataLoadDelay: 0,
                        selectFirstVideo: false,
                        metadataPrefetchLimit: Self.launchMetadataPrefetchLimit,
                        metadataWorkerCount: Self.launchMetadataWorkerCount,
                        metadataBackgroundPrefetchDelay: nil,
                        videoPathRemap: cached.pathRemap,
                        videoFolderTagsByPath: cached.folderTagsByPath,
                        cachedMetadataByPath: cached.metadataByPath,
                        cachedThumbnailDataByPath: cached.thumbnailDataByPath,
                        cachedPlaybackSupportByPath: cached.playbackSupportByPath,
                        decodeCachedThumbnailsImmediately: false
                    )
                    store.scheduleInitialVideoSelectionAfterLaunch(
                        in: url,
                        after: Self.launchInitialVideoSelectionDelay
                    )
                }
                return
            }

            let quickSnapshot = Self.quickVideoOrganizationSnapshot(in: url)
            await MainActor.run { [weak self] in
                guard let store = self, store.libraryURL == nil else { return }
                store.applyScannedVideos(
                    in: url,
                    urls: quickSnapshot.urls,
                    deferProjectDataLoad: true,
                    projectDataLoadDelay: 0,
                    selectFirstVideo: false,
                    metadataPrefetchLimit: Self.launchMetadataPrefetchLimit,
                    metadataWorkerCount: Self.launchMetadataWorkerCount,
                    metadataBackgroundPrefetchDelay: nil,
                    videoPathRemap: quickSnapshot.pathRemap,
                    videoFolderTagsByPath: quickSnapshot.folderTagsByPath,
                    cachedMetadataByPath: quickSnapshot.metadataByPath,
                    cachedThumbnailDataByPath: quickSnapshot.thumbnailDataByPath,
                    cachedPlaybackSupportByPath: quickSnapshot.playbackSupportByPath
                )
                store.scheduleInitialVideoSelectionAfterLaunch(
                    in: url,
                    after: Self.launchInitialVideoSelectionDelay
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
                    metadataBackgroundPrefetchDelay: nil,
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

    func scheduleInitialVideoSelectionAfterLaunch(in url: URL, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) { [weak self] in
            guard let self,
                  self.libraryURL?.path == url.path,
                  self.selectedVideo == nil,
                  let firstVideo = self.videos.first
            else { return }
            self.selectVideo(firstVideo, autoplay: false)
        }
    }

    func lastLibraryURLForLoading() -> URL? {
        if let bookmarkedURL = restoreLastLibraryBookmark() {
            return bookmarkedURL
        }

        if let path = AppSettings.lastLibraryPath {
            let url = URL(fileURLWithPath: path)
            if isExistingDirectory(url) {
                return url
            }
            AppSettings.lastLibraryPath = nil
            AppSettings.lastLibraryBookmark = nil
        }

        if let defaultURL = defaultLibraryURL() {
            AppSettings.lastLibraryPath = defaultURL.path
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
        AppSettings.instagramImportEndpoint = instagramImportEndpoint
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

    func importRemoteVideosSerially(from rawText: String) async {
        let inputs = Self.remoteImportURLs(from: rawText)
        guard !inputs.isEmpty else {
            remoteImportJobs.append(RemoteImportJob(
                sourceURL: Self.placeholderRemoteImportURL,
                platform: "未知平台",
                status: .failed("请输入至少一个有效链接")
            ))
            return
        }

        let batchID = inputs.count > 1 ? UUID() : nil
        let batchTitle = batchID.map { _ in "逐个导入" }
        var jobIDs: [UUID] = []
        for (index, rawURL) in inputs.enumerated() {
            guard !Task.isCancelled else { return }
            guard let jobID = enqueueRemoteImport(
                from: rawURL,
                selectOnCompletion: false,
                batchID: batchID,
                batchTitle: batchTitle,
                batchTotalCount: inputs.count,
                batchIndex: index + 1
            ) else { continue }
            jobIDs.append(jobID)
        }

        for jobID in jobIDs {
            guard !Task.isCancelled else { return }
            await remoteImportTasks[jobID]?.value
        }
    }

    func latestInstagramSavedImportCandidatesFromChrome(limit: Int = 50) async throws -> InstagramSavedImportResult {
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
        let metadataByDiscoveredLink = scan.metadataByLink
        let linksToImport = discoveredLinks.filter { link in
            guard !alreadyQueuedOrImported.contains(link) else { return false }
            guard let key = Self.instagramContentKey(link) else { return true }
            return !knownKeys.contains(key)
        }
        let skippedLinks = discoveredLinks.filter { !linksToImport.contains($0) }
        let linksToImportSet = Set(linksToImport)
        recordInstagramSavedSyncSnapshot(
            discoveredLinks: discoveredLinks,
            skippedLinks: skippedLinks,
            queuedLinks: linksToImport,
            scannedPageCount: scan.pageCount,
            stoppedAtKnownBaseline: scan.stoppedAtKnownBaseline
        )

        return InstagramSavedImportResult(
            foundCount: discoveredLinks.count,
            skippedCount: discoveredLinks.count - linksToImport.count,
            queuedCount: linksToImport.count,
            queuedLinks: linksToImport,
            queuedMetadataByLink: metadataByDiscoveredLink.filter { element in
                linksToImportSet.contains(element.key)
            },
            scannedPageCount: scan.pageCount,
            stoppedAtKnownBaseline: scan.stoppedAtKnownBaseline
        )
    }

    func latestXiaohongshuSavedVideoImportCandidatesFromChrome(limit: Int = 10) async throws -> InstagramSavedImportResult {
        guard libraryURL != nil else {
            throw InstagramSavedImportError.noLibrary
        }
        startExternalServiceSelfCheckPreflightIfNeeded()

        let alreadyQueuedOrImported = queuedOrImportedXiaohongshuSourceURLs()
        let knownNoteIDs = queuedOrImportedXiaohongshuNoteIDs()
            .union(xiaohongshuSavedBaselineKnownNoteIDs())
        let scan = try await Self.fetchLatestXiaohongshuSavedVideoScanFromChrome(
            limit: limit,
            excludingMetadataNoteIDs: knownNoteIDs
        )
        let discoveredLinks = scan.links
        let metadataByDiscoveredLink = scan.metadataByLink
        let linksToImport = discoveredLinks.filter { link in
            guard !alreadyQueuedOrImported.contains(link) else { return false }
            guard
                let url = URL(string: link),
                let noteID = Self.xiaohongshuNoteID(from: url)
            else { return true }
            return !knownNoteIDs.contains(noteID)
        }
        let skippedLinks = discoveredLinks.filter { !linksToImport.contains($0) }
        recordXiaohongshuSavedSyncSnapshot(
            discoveredLinks: discoveredLinks,
            skippedLinks: skippedLinks,
            queuedLinks: linksToImport
        )
        let linksToImportSet = Set(linksToImport)

        return InstagramSavedImportResult(
            foundCount: discoveredLinks.count,
            skippedCount: discoveredLinks.count - linksToImport.count,
            queuedCount: linksToImport.count,
            queuedLinks: linksToImport,
            queuedMetadataByLink: metadataByDiscoveredLink.filter { element in
                linksToImportSet.contains(element.key)
            }
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
        libraryURL.map(ProjectRepository.instagramSavedBaselineURL)
    }

    func xiaohongshuSavedBaselineURL() -> URL? {
        libraryURL.map(ProjectRepository.xiaohongshuSavedBaselineURL)
    }

    func instagramSavedBaselineKnownSourceKeys() -> Set<String> {
        guard let url = instagramSavedBaselineURL() else { return [] }
        let root = ProjectRepository.readJSONObject(at: url)
        guard let results = root["results"] as? [String: Any] else { return [] }

        let knownStatuses = Set(["already_recorded", "downloaded", "duplicate", "ignored"])
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

    func xiaohongshuSavedBaselineKnownNoteIDs() -> Set<String> {
        guard let url = xiaohongshuSavedBaselineURL() else { return [] }
        let root = ProjectRepository.readJSONObject(at: url)
        guard let results = root["results"] as? [String: Any] else { return [] }

        let knownStatuses = Set(["already_recorded", "downloaded", "duplicate", "ignored"])
        var noteIDs = Set<String>()
        for (rawKey, rawValue) in results {
            guard let entry = rawValue as? [String: Any] else { continue }
            let status = entry["status"] as? String
            guard status.map(knownStatuses.contains) == true else { continue }
            if let noteID = Self.xiaohongshuNoteID(fromRawURLString: rawKey) {
                noteIDs.insert(noteID)
            }
            if let sourceURL = entry["sourceURL"] as? String,
               let noteID = Self.xiaohongshuNoteID(fromRawURLString: sourceURL) {
                noteIDs.insert(noteID)
            }
        }
        return noteIDs
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
                entry["status"] = "pending"
            } else if skippedSet.contains(link) {
                let status = entry["status"] as? String
                if status != "downloaded" && status != "duplicate" && status != "ignored" {
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

    func recordXiaohongshuSavedSyncSnapshot(
        discoveredLinks: [String],
        skippedLinks: [String],
        queuedLinks: [String]
    ) {
        guard let url = xiaohongshuSavedBaselineURL() else { return }

        var root = Self.readJSONObject(at: url)
        var results = root["results"] as? [String: Any] ?? [:]
        let now = Self.iso8601String(Date())
        let queuedSet = Set(queuedLinks)
        let skippedSet = Set(skippedLinks)

        for link in discoveredLinks {
            let key = Self.normalizedXiaohongshuNoteURL(link) ?? link
            var entry = results[key] as? [String: Any] ?? [:]
            entry["sourceURL"] = key
            entry["updatedAt"] = now
            if let noteID = Self.xiaohongshuNoteID(fromRawURLString: key) {
                entry["noteID"] = noteID
            }
            if queuedSet.contains(link) {
                entry["status"] = "pending"
            } else if skippedSet.contains(link) {
                let status = entry["status"] as? String
                if status != "downloaded" && status != "duplicate" && status != "ignored" {
                    entry["status"] = "already_recorded"
                }
            }
            results[key] = entry
        }

        root["version"] = 1
        root["updatedAt"] = now
        root["lastSeenLinks"] = discoveredLinks
        root["lastSeenCount"] = discoveredLinks.count
        root["results"] = results
        Self.writeJSONObject(root, to: url)
    }

    func recordSavedImportStatus(
        sourceURL: URL,
        status: String,
        outputURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        if Self.isInstagramURL(sourceURL) {
            recordInstagramSavedImportStatus(
                sourceURL: sourceURL,
                status: status,
                outputURL: outputURL,
                errorMessage: errorMessage
            )
        } else if Self.platformName(for: sourceURL) == "小红书" {
            recordXiaohongshuSavedImportStatus(
                sourceURL: sourceURL,
                status: status,
                outputURL: outputURL,
                errorMessage: errorMessage
            )
        }
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

    func recordXiaohongshuSavedImportStatus(
        sourceURL: URL,
        status: String,
        outputURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        guard let url = xiaohongshuSavedBaselineURL() else { return }

        var root = Self.readJSONObject(at: url)
        var results = root["results"] as? [String: Any] ?? [:]
        let key = Self.normalizedXiaohongshuNoteURL(sourceURL.absoluteString) ?? sourceURL.absoluteString
        let now = Self.iso8601String(Date())
        var entry = results[key] as? [String: Any] ?? [:]
        entry["sourceURL"] = key
        entry["status"] = status
        entry["updatedAt"] = now
        if let noteID = Self.xiaohongshuNoteID(fromRawURLString: key) {
            entry["noteID"] = noteID
        }
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

    func queuedOrImportedXiaohongshuNoteIDs() -> Set<String> {
        var noteIDs = Set<String>()

        for info in sourceInfoByVideoPath.values {
            if let sourceURL = info.sourceURL,
               let noteID = Self.xiaohongshuNoteID(fromRawURLString: sourceURL) {
                noteIDs.insert(noteID)
            }
        }

        for job in remoteImportJobs where Self.remoteImportJobCountsAsQueuedOrImported(job.status) {
            if let noteID = Self.xiaohongshuNoteID(fromRawURLString: job.sourceURL.absoluteString) {
                noteIDs.insert(noteID)
            }
        }

        return noteIDs
    }

    @discardableResult
    func enqueueRemoteImport(
        from rawURL: String,
        initialThumbnailData: Data? = nil,
        selectOnCompletion: Bool = true,
        batchID: UUID? = nil,
        batchTitle: String? = nil,
        batchTotalCount: Int? = nil,
        batchIndex: Int? = nil
    ) -> UUID? {
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
            return nil
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
            return nil
        }
        let importSourceURL = Self.instagramBundledImportURL(for: sourceURL) ?? sourceURL

        guard let libraryURL else {
            remoteImportJobs.append(RemoteImportJob(
                sourceURL: importSourceURL,
                platform: platform,
                batchID: batchID,
                batchTitle: batchTitle,
                batchTotalCount: batchTotalCount,
                batchIndex: batchIndex,
                status: .failed("请先打开一个素材库文件夹")
            ))
            return nil
        }

        let endpoint = instagramImportEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let job = RemoteImportJob(
            sourceURL: importSourceURL,
            platform: platform,
            batchID: batchID,
            batchTitle: batchTitle,
            batchTotalCount: batchTotalCount,
            batchIndex: batchIndex,
            status: .idle,
            thumbnailData: initialThumbnailData
        )
        remoteImportJobs.append(job)
        recordSavedImportStatus(sourceURL: importSourceURL, status: "queued")
        let jobID = job.id

        if initialThumbnailData == nil {
            loadRemoteImportThumbnail(for: jobID, sourceURL: importSourceURL)
        }

        // 进度回调：yt-dlp 每行输出一次，跳回主线程更新 UI
        let progressCallback: @Sendable (Double?, String?) -> Void = { [weak self] progress, speed in
            Task { @MainActor [weak self] in
                self?.updateRemoteImportJob(id: jobID) { job in
                    guard case .importing = job.status else { return }
                    if let progress {
                        job.downloadProgress = Self.normalizedProgress(progress)
                    }
                    if let speed, !speed.isEmpty {
                        job.downloadSpeed = speed
                    } else if progress == nil {
                        job.downloadSpeed = nil
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
        let finalizingCallback: @Sendable (Double) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.updateRemoteImportJob(id: jobID) { job in
                    guard Self.remoteImportJobCanReceiveWorkerProgress(job.status) else { return }
                    job.status = .finalizing
                    job.downloadProgress = Self.normalizedProgress(progress)
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
            var didAcquireDownloadSlot = false
            defer {
                if didAcquireDownloadSlot {
                    Task {
                        await remoteImportDownloadGate.release(jobID)
                    }
                }
                Task { @MainActor [weak self] in
                    self?.remoteImportTasks[jobID] = nil
                    self?.remoteImportProcesses[jobID] = nil
                }
            }
            do {
                await remoteImportDownloadGate.acquire(jobID)
                didAcquireDownloadSlot = true
                guard !Task.isCancelled else { return }
                self?.updateRemoteImportJob(id: jobID) { job in
                    guard case .idle = job.status else { return }
                    job.status = .importing
                }
                await MainActor.run { [weak self] in
                    self?.startExternalServiceSelfCheckPreflightIfNeeded()
                }
                let downloadedVideo = try await Self.downloadVideo(
                    from: importSourceURL,
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
                    self?.loadMetadataIfNeeded(for: importedVideo, allowThumbnailGeneration: true)
                    self?.recordImportedVideoSource(
                        videoURL: outputURL,
                        sourceURL: importSourceURL,
                        platform: platform,
                        authorName: downloadedVideo.authorName,
                        sourceTitle: downloadedVideo.sourceTitle
                    )
                    self?.recordSavedImportStatus(
                        sourceURL: importSourceURL,
                        status: "downloaded",
                        outputURL: outputURL
                    )
                    if selectOnCompletion || self?.selectedVideo == nil {
                        self?.selectVideo(importedVideo, autoplay: false)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.updateRemoteImportJob(id: jobID) { job in
                    job.status = .failed(error.localizedDescription)
                    job.downloadProgress = nil
                    job.downloadSpeed = nil
                }
                self?.recordSavedImportStatus(
                    sourceURL: importSourceURL,
                    status: "failed",
                    errorMessage: error.localizedDescription
                )
            }
        }
        remoteImportTasks[jobID] = task
        return jobID
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

        if containsVideoPath(outputPath) {
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

    func recordImportedVideoSource(
        videoURL: URL,
        sourceURL: URL,
        platform: String,
        authorName: String?,
        sourceTitle: String?
    ) {
        let normalizedPlatform = Self.canonicalSourcePlatform(platform) ?? platform
        let normalizedAuthor = authorName.flatMap(Self.normalizedSourceAuthorName)
        let normalizedTitle = sourceTitle.flatMap(Self.normalizedSourceTitle)
        sourceInfoByVideoPath[videoURL.path] = VideoSourceInfo(
            platform: normalizedPlatform,
            sourceURL: sourceURL.absoluteString,
            authorName: normalizedAuthor,
            title: normalizedTitle
        )
        saveSourceInfoJSON()
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

        return "https://www.instagram.com/\(content.type)/\(content.shortcode)/"
    }

    nonisolated static func instagramContentKey(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let content = instagramContentParts(from: url)
        else { return nil }

        return "\(content.type):\(content.shortcode)"
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

    nonisolated static func instagramBundledImportURL(for url: URL) -> URL? {
        guard let content = instagramContentParts(from: url),
              content.type == "p"
        else { return nil }
        return instagramBaseContentURL(from: url)
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

    nonisolated static func normalizedXiaohongshuNoteURL(
        _ rawValue: String,
        preservingXsecToken: Bool = false
    ) -> String? {
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
        if preservingXsecToken {
            components.queryItems = components.queryItems?.filter { item in
                item.name == "xsec_token" || item.name == "xsec_source"
            }
            if components.queryItems?.isEmpty == true {
                components.queryItems = nil
            }
        } else {
            components.queryItems = nil
        }
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

    nonisolated static func xiaohongshuNoteID(fromRawURLString rawValue: String) -> String? {
        guard let normalized = normalizedXiaohongshuNoteURL(rawValue),
              let url = URL(string: normalized)
        else { return nil }
        return xiaohongshuNoteID(from: url)
    }

    nonisolated static func remoteImportJobCountsAsQueuedOrImported(_ status: RemoteImportJob.Status) -> Bool {
        switch status {
        case .idle, .importing, .transcoding, .finalizing, .paused, .succeeded:
            return true
        case .failed:
            return false
        }
    }

    nonisolated struct CurlFetchResult: Sendable {
        var statusCode: Int
        var data: Data
    }

    nonisolated static func readJSONObject(at url: URL) -> [String: Any] {
        ProjectRepository.readJSONObject(at: url)
    }

    nonisolated static func writeJSONObject(_ object: [String: Any], to url: URL) {
        ProjectRepository.writeJSONObject(object, to: url)
    }

    nonisolated static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    nonisolated struct InstagramSavedScanResult: Sendable {
        var links: [String]
        var metadataByLink: [String: SavedImportCandidateMetadata] = [:]
        var itemCount: Int
        var pageCount: Int
        var stoppedAtKnownBaseline: Bool
    }

    nonisolated struct XiaohongshuSavedScanResult: Sendable {
        var links: [String]
        var metadataByLink: [String: SavedImportCandidateMetadata] = [:]
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

        var savedVideoLinks: [String] {
            var links: [String] = []

            if let media {
                links.append(contentsOf: LibraryStore.instagramVideoLinks(fromSavedMedia: media))
            }
            if let item {
                links.append(contentsOf: LibraryStore.instagramVideoLinks(fromSavedMedia: item))
            }
            if let carouselMedia,
               carouselMedia.contains(where: \.isLikelyVideo),
               let parentCode = media?.code ?? item?.code ?? carouselMedia.first(where: \.isLikelyVideo)?.code {
                links.append("https://www.instagram.com/p/\(parentCode)/")
            }

            var seen = Set<String>()
            return links.filter { link in
                let normalized = LibraryStore.normalizedInstagramContentURL(link) ?? link
                return seen.insert(normalized).inserted
            }
        }

        var displayMedia: InstagramSavedMedia? {
            bestMedia ?? carouselMedia?.first(where: \.isLikelyVideo) ?? carouselMedia?.first
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
        var caption: InstagramSavedCaption?
        var user: InstagramSavedUser?
        var imageVersions2: InstagramSavedImageVersions?

        var bestImageURLString: String? {
            imageVersions2?.bestURLString
        }

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
            case caption, user
            case imageVersions2 = "image_versions2"
        }
    }

    nonisolated struct InstagramSavedVideoVersion: Decodable {
        var url: String?
    }

    nonisolated struct InstagramSavedCaption: Decodable {
        var text: String?
    }

    nonisolated struct InstagramSavedUser: Decodable {
        var username: String?
        var fullName: String?

        enum CodingKeys: String, CodingKey {
            case username
            case fullName = "full_name"
        }
    }

    nonisolated struct InstagramSavedImageVersions: Decodable {
        var candidates: [InstagramSavedImageCandidate]?

        var bestURLString: String? {
            candidates?
                .compactMap(\.url)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { rawValue in
                    guard let url = URL(string: rawValue),
                          let scheme = url.scheme?.lowercased()
                    else { return false }
                    return scheme == "http" || scheme == "https"
                }
        }
    }

    nonisolated struct InstagramSavedImageCandidate: Decodable {
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
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let result = try runCurlFetchOnce(
                    urlString: urlString,
                    cookieFileURL: cookieFileURL,
                    headers: headers,
                    timeout: timeout
                )
                guard attempt < 3, shouldRetryCurlFetch(statusCode: result.statusCode) else {
                    return result
                }
            } catch {
                lastError = error
                guard attempt < 3, shouldRetryCurlFetch(error: error) else {
                    throw error
                }
            }
            Thread.sleep(forTimeInterval: min(2.5, Double(attempt)))
        }
        throw lastError ?? InstagramSavedImportError.timedOut
    }

    nonisolated static func shouldRetryCurlFetch(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 425 || statusCode == 429 || (500..<600).contains(statusCode)
    }

    nonisolated static func shouldRetryCurlFetch(error: Error) -> Bool {
        if case InstagramSavedImportError.timedOut = error {
            return true
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("timed out")
            || message.contains("timeout")
            || message.contains("connection")
            || message.contains("could not resolve")
            || message.contains("failed to connect")
    }

    nonisolated static func runCurlFetchOnce(
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
            if carouselMedia.contains(where: \.isLikelyVideo),
               let parentCode = media.code ?? carouselMedia.first(where: \.isLikelyVideo)?.code {
                links.append("https://www.instagram.com/p/\(parentCode)/")
            }
        }

        if media.isLikelyVideo, let code = media.code {
            let type = media.productType?.lowercased().contains("clips") == true ? "reel" : "p"
            links.append("https://www.instagram.com/\(type)/\(code)/")
        }

        var seen = Set<String>()
        return links.filter { seen.insert($0).inserted }
    }

    nonisolated static func instagramSavedCandidateMetadataByLink(
        from item: InstagramSavedFeedItem
    ) -> [String: SavedImportCandidateMetadata] {
        let metadata = instagramSavedCandidateMetadata(from: item)
        guard metadata.hasAnyValue else { return [:] }

        var metadataByLink: [String: SavedImportCandidateMetadata] = [:]
        for link in item.savedVideoLinks {
            let normalized = normalizedInstagramContentURL(link) ?? link
            metadataByLink[normalized] = metadata
        }
        return metadataByLink
    }

    nonisolated static func instagramSavedCandidateMetadata(
        from item: InstagramSavedFeedItem
    ) -> SavedImportCandidateMetadata {
        let sourceURL = item.savedVideoLinks
            .first
            .flatMap(URL.init(string:))
            ?? URL(string: "https://www.instagram.com/")!
        return SavedImportCandidateMetadata(
            title: screenedSourceTitle(
                rawTitle: instagramSavedCaptionText(from: item),
                description: nil,
                sourceURL: sourceURL
            ),
            authorName: instagramSavedAuthorName(from: item),
            thumbnailURLString: instagramSavedThumbnailURLString(from: item)
        )
    }

    nonisolated static func instagramSavedCaptionText(from item: InstagramSavedFeedItem) -> String? {
        [
            item.media?.caption?.text,
            item.item?.caption?.text,
            item.displayMedia?.caption?.text
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    nonisolated static func instagramSavedAuthorName(from item: InstagramSavedFeedItem) -> String? {
        let users = [
            item.media?.user,
            item.item?.user,
            item.displayMedia?.user
        ]
        for user in users {
            if let author = normalizedSourceAuthorName(user?.fullName ?? "") {
                return author
            }
            if let author = normalizedSourceAuthorName(user?.username ?? "") {
                return author
            }
        }
        return nil
    }

    nonisolated static func instagramSavedThumbnailURLString(from item: InstagramSavedFeedItem) -> String? {
        let mediaCandidates = [
            item.displayMedia,
            item.media,
            item.item,
            item.carouselMedia?.first(where: \.isLikelyVideo),
            item.carouselMedia?.first
        ]
        return mediaCandidates
            .compactMap { $0?.bestImageURLString }
            .first
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
            var metadataByLink: [String: SavedImportCandidateMetadata] = [:]
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
                    let mediaLinks = item.savedVideoLinks
                    let itemMetadataByLink = Self.instagramSavedCandidateMetadataByLink(from: item)
                    for link in mediaLinks {
                        let normalized = normalizedInstagramContentURL(link) ?? link
                        if let key = instagramContentKey(normalized),
                           knownContentKeys.contains(key) {
                            pageContainsKnownContent = true
                        }
                        if seen.insert(normalized).inserted {
                            links.append(normalized)
                        }
                        if let metadata = itemMetadataByLink[normalized] ?? itemMetadataByLink[link] {
                            if let current = metadataByLink[normalized] {
                                metadataByLink[normalized] = current.merging(metadata)
                            } else {
                                metadataByLink[normalized] = metadata
                            }
                        }
                    }
                }

                if pageContainsKnownContent && !knownContentKeys.isEmpty {
                    stoppedAtKnownBaseline = true
                    break
                }

                if links.count >= limit {
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
                links: Array(links.prefix(limit)),
                metadataByLink: metadataByLink,
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
                replacementLinks = videoLinks.isEmpty ? [] : [instagramBaseContentURL(from: url)?.absoluteString ?? normalizedLink]
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
        return instagramPostVideoItemLinks(from: info, baseURL: baseURL)
    }

    nonisolated static func instagramPostVideoItemLinks(from info: YTDLPVideoInfo, baseURL: URL) -> [String] {
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
        try await fetchLatestXiaohongshuSavedVideoScanFromChrome(limit: limit).links
    }

    nonisolated static func fetchLatestXiaohongshuSavedVideoCandidatesFromChrome(limit: Int) async throws -> [SavedImportCandidate] {
        let scan = try await fetchLatestXiaohongshuSavedVideoScanFromChrome(limit: limit)
        return scan.links.map { link in
            SavedImportCandidate(urlString: link, metadata: scan.metadataByLink[link])
        }
    }

    nonisolated static func fetchLatestXiaohongshuSavedVideoLinksFromChromeCookies(limit: Int) throws -> [String] {
        try fetchLatestXiaohongshuSavedVideoScanFromChromeCookies(limit: limit).links
    }

    nonisolated static func fetchLatestXiaohongshuSavedVideoCandidatesFromChromeCookies(limit: Int) throws -> [SavedImportCandidate] {
        let scan = try fetchLatestXiaohongshuSavedVideoScanFromChromeCookies(limit: limit)
        return scan.links.map { link in
            SavedImportCandidate(urlString: link, metadata: scan.metadataByLink[link])
        }
    }

    nonisolated static func fetchLatestXiaohongshuSavedVideoScanFromChrome(
        limit: Int,
        excludingMetadataNoteIDs: Set<String> = []
    ) async throws -> XiaohongshuSavedScanResult {
        let clampedLimit = min(max(limit, 1), 50)
        return try await Task.detached(priority: .userInitiated) {
            try fetchLatestXiaohongshuSavedVideoScanFromChromeCookies(
                limit: clampedLimit,
                excludingMetadataNoteIDs: excludingMetadataNoteIDs
            )
        }.value
    }

    nonisolated static func fetchLatestXiaohongshuSavedVideoScanFromChromeCookies(
        limit: Int,
        excludingMetadataNoteIDs: Set<String> = []
    ) throws -> XiaohongshuSavedScanResult {
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

            let links = Self.xiaohongshuVideoLinks(fromSavedHTML: html, limit: limit)
            guard !links.isEmpty else {
                throw InstagramSavedImportError.noXiaohongshuVideoLinks
            }

            let metadataNoteIDs = Set(links.compactMap(Self.xiaohongshuNoteID(fromRawURLString:)))
                .subtracting(excludingMetadataNoteIDs)
            let metadataByNoteID = Self.xiaohongshuSavedCandidateMetadataByNoteID(
                fromSavedHTML: html,
                limitedTo: metadataNoteIDs
            )
            var metadataByLink: [String: SavedImportCandidateMetadata] = [:]
            for link in links {
                guard
                    let noteID = Self.xiaohongshuNoteID(fromRawURLString: link),
                    let metadata = metadataByNoteID[noteID]
                else { continue }
                metadataByLink[link] = metadata
            }

            return XiaohongshuSavedScanResult(
                links: links,
                metadataByLink: metadataByLink
            )
        }
    }

    nonisolated static func platformName(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if host.contains("instagram.com") || host.contains("instagr.am")
            || host.contains("sssinstagram.com") || host.contains("cdninstagram.com")
            || host.contains("cdninstagram")
            || (host.contains("instagram") && host.contains("fbcdn.net")) {
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
        AppSettings.lastLibraryPath = folder.path

        do {
            let bookmarkData = try folder.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            AppSettings.lastLibraryBookmark = bookmarkData

            if folder.startAccessingSecurityScopedResource() {
                scopedLibraryURL = folder
            }
        } catch {
            AppSettings.lastLibraryBookmark = nil
        }
    }

    func restoreLastLibraryBookmark() -> URL? {
        guard let bookmarkData = AppSettings.lastLibraryBookmark else {
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

            stopAccessingScopedLibrary()
            if url.startAccessingSecurityScopedResource() {
                scopedLibraryURL = url
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                stopAccessingScopedLibrary()
                return nil
            }

            if isStale {
                persistLibraryAccess(for: url)
            } else {
                AppSettings.lastLibraryPath = url.path
            }

            return url
        } catch {
            AppSettings.lastLibraryBookmark = nil
            return nil
        }
    }

    func stopAccessingScopedLibrary() {
        scopedLibraryURL?.stopAccessingSecurityScopedResource()
        scopedLibraryURL = nil
    }

}
