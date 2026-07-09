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
    @discardableResult
    func loadLastLibraryForLaunch() -> Bool {
        guard libraryURL == nil else { return true }
        guard let url = lastLibraryURLForLoading() else { return false }

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
                    selectFirstVideo: false,
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
        return true
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
        guard !defaultLibraryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let url = URL(fileURLWithPath: defaultLibraryPath)
        return isExistingDirectory(url) ? url : nil
    }

    func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    @discardableResult
    func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "打开文件夹"
        panel.prompt = "打开"

        if panel.runModal() == .OK, let url = panel.url {
            persistLibraryAccess(for: url)
            scanVideos(in: url)
            return true
        }

        return false
    }

    func promptForInitialLibraryIfNeeded() {
        guard libraryURL == nil, !isPresentingInitialLibraryPicker else { return }
        isPresentingInitialLibraryPicker = true
        _ = chooseFolder()
        isPresentingInitialLibraryPicker = false
    }

    func saveInstagramImportEndpoint(_ endpoint: String) {
        instagramImportEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.instagramImportEndpoint = instagramImportEndpoint
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
        remoteImportTasks.cancel(id)
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
        remoteImportTasks.cancel(id)
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
            await remoteImportTasks.wait(for: jobID)
        }
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
        let jobID = job.id

        loadRemoteImportCandidateMetadata(for: jobID, sourceURL: importSourceURL)

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

        remoteImportTasks.start(jobID) { [weak self] in
            var didAcquireDownloadSlot = false
            defer {
                if didAcquireDownloadSlot {
                    Task {
                        await remoteImportDownloadGate.release(jobID)
                    }
                }
                Task { @MainActor [weak self] in
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
                    self?.downloaderSelfCheck.startExternalServiceSelfCheckPreflightIfNeeded()
                }
                let downloadedVideo: DownloadedVideoResult
                do {
                    downloadedVideo = try await Self.downloadVideo(
                        from: importSourceURL,
                        into: libraryURL,
                        platform: platform,
                        endpoint: endpoint,
                        progressCallback: progressCallback,
                        transcodingCallback: transcodingCallback,
                        finalizingCallback: finalizingCallback,
                        processCallback: processCallback
                    )
                } catch {
                    // YouTube 登录验证失败时自动更新一次 cookie 再重试,避免用户手动刷新
                    guard !Task.isCancelled,
                          Self.isYouTubeURL(importSourceURL),
                          Self.isYouTubeBotVerificationFailure(error.localizedDescription),
                          let store = self,
                          await store.youtubeCookie.refreshAfterBotCheckIfNeeded()
                    else { throw error }
                    downloadedVideo = try await Self.downloadVideo(
                        from: importSourceURL,
                        into: libraryURL,
                        platform: platform,
                        endpoint: endpoint,
                        progressCallback: progressCallback,
                        transcodingCallback: transcodingCallback,
                        finalizingCallback: finalizingCallback,
                        processCallback: processCallback
                    )
                }
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
                    if selectOnCompletion {
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
            }
        }
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

    func loadRemoteImportCandidateMetadata(for jobID: UUID, sourceURL: URL) {
        Task { [weak self] in
            let metadata = await Self.remoteImportCandidateMetadata(for: sourceURL)
            guard metadata.hasAnyValue, !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                self?.updateRemoteImportJob(id: jobID) { job in
                    if let title = metadata.title, !title.isEmpty {
                        job.candidateTitle = title
                    }
                    if let authorName = metadata.authorName, !authorName.isEmpty {
                        job.candidateAuthorName = authorName
                    }
                    if job.thumbnailData == nil, let thumbnailData = metadata.thumbnailData {
                        job.thumbnailData = thumbnailData
                    }
                }
            }
        }
    }

    func loadRemoteImportThumbnail(for jobID: UUID, sourceURL: URL) {
        loadRemoteImportCandidateMetadata(for: jobID, sourceURL: sourceURL)
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

    nonisolated enum RemoteWebFetchError: LocalizedError {
        case toolUnavailable(String)
        case timedOut
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .toolUnavailable(let message), .failed(let message):
                return message
            case .timedOut:
                return "网页读取超时"
            }
        }
    }

    nonisolated static func runCurlFetch(
        urlString: String,
        cookieFileURL: URL? = nil,
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
        throw lastError ?? RemoteWebFetchError.timedOut
    }

    nonisolated static func shouldRetryCurlFetch(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 425 || statusCode == 429 || (500..<600).contains(statusCode)
    }

    nonisolated static func shouldRetryCurlFetch(error: Error) -> Bool {
        if case RemoteWebFetchError.timedOut = error {
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
        cookieFileURL: URL? = nil,
        headers: [(String, String)] = [],
        timeout: TimeInterval
    ) throws -> CurlFetchResult {
        guard let curl = localCurlURL() else {
            throw RemoteWebFetchError.toolUnavailable("未找到 curl，无法读取网页")
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
            "--output", bodyURL.path,
            "--write-out", "%{http_code}"
        ]
        if let cookieFileURL {
            arguments += ["--cookie", cookieFileURL.path]
        }
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
            throw RemoteWebFetchError.toolUnavailable("无法启动 curl：\(error.localizedDescription)")
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
            throw RemoteWebFetchError.timedOut
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        guard process.terminationStatus == 0 else {
            let errorText = String(data: errorCollector.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw RemoteWebFetchError.failed(errorText.isEmpty ? "curl 请求失败" : errorText)
        }

        let statusText = String(data: outputCollector.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let data = (try? Data(contentsOf: bodyURL)) ?? Data()
        return CurlFetchResult(statusCode: Int(statusText) ?? 0, data: data)
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
