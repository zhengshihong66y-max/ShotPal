//
//  ContentView+ImportJobs.swift
//  LapianBao
//
//  Split from ContentView.swift.
//

import SwiftUI
import AVFoundation
import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension ContentView {
    func closeImportPanel() {
        savedImportRefreshTask?.cancel()
        savedImportRefreshTask = nil
        savedImportRefreshID = nil
        savedImportMetadataTask?.cancel()
        savedImportMetadataTask = nil
        savedImportMetadataID = nil
        isSavedImportRefreshing = false
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            isImportSheetPresented = false
        }
    }

    func startRemoteImport() {
        let videos = manualImportVideos
        guard !videos.isEmpty else { return }

        libraryStore.saveInstagramImportEndpoint(importEndpointText)
        libraryStore.importRemoteVideos(from: videos.map(\.urlString).joined(separator: "\n"))

        let importedIDs = Set(videos.map(\.id))
        let remainingURLs = LibraryStore.remoteImportURLs(from: importURLText)
            .filter { !importedIDs.contains(importCandidateID(for: $0)) }
        importURLText = remainingURLs.joined(separator: "\n")
    }

    func startAllSavedImportCandidates() {
        guard !isSavedImportSerialRunning else { return }
        let videos = pendingImportVideos
        guard !videos.isEmpty else { return }

        libraryStore.saveInstagramImportEndpoint(importEndpointText)
        let rawText = videos.map(\.urlString).joined(separator: "\n")
        removeSavedImportCandidates(videos)
        isSavedImportSerialRunning = true
        savedImportRefreshIsError = false
        savedImportRefreshMessage = "已将 \(videos.count) 个收藏视频加入下载队列，正在排队下载..."
        savedImportSerialTask?.cancel()
        savedImportSerialTask = Task { @MainActor in
            defer {
                isSavedImportSerialRunning = false
                savedImportSerialTask = nil
            }
            await libraryStore.importRemoteVideosSerially(from: rawText)
            guard !Task.isCancelled else { return }
            savedImportRefreshIsError = false
            savedImportRefreshMessage = "全部下载任务已处理完成"
        }
    }

    func startRemoteImport(_ pendingVideo: PendingImportVideo) {
        libraryStore.saveInstagramImportEndpoint(importEndpointText)
        libraryStore.importRemoteVideos(from: pendingVideo.urlString)
        removePendingImportVideo(pendingVideo)
    }

    func removePendingImportVideo(_ pendingVideo: PendingImportVideo) {
        removeSavedImportCandidates([pendingVideo])
    }

    func ignorePendingImportVideo(_ pendingVideo: PendingImportVideo) {
        if let sourceURL = URL(string: pendingVideo.urlString) {
            libraryStore.recordSavedImportStatus(sourceURL: sourceURL, status: "ignored")
        }
        removePendingImportVideo(pendingVideo)
    }

    func removeSavedImportCandidates(_ videos: [PendingImportVideo]) {
        let removedIDs = Set(videos.map(\.id))
        savedImportCandidates.removeAll { removedIDs.contains($0.id) }
    }

    func savedImportFetchOutcome(
        suppressMissingXiaohongshuVideos: Bool = false,
        _ body: () async throws -> InstagramSavedImportResult
    ) async -> (result: InstagramSavedImportResult?, errorMessage: String?) {
        do {
            return (try await body(), nil)
        } catch InstagramSavedImportError.noXiaohongshuVideoLinks where suppressMissingXiaohongshuVideos {
            return (nil, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    func refreshSavedImportCandidatesIfNeeded(force: Bool = false) {
        guard force || savedImportCandidates.isEmpty || savedImportRefreshMessage == nil else { return }
        refreshSavedImportCandidates()
    }

    func prewarmSavedImportCandidatesIfPossible() {
        guard libraryStore.libraryURL != nil else { return }
        guard !isSavedImportRefreshing else { return }
        guard savedImportCandidates.isEmpty else { return }
        guard savedImportRefreshMessage == nil else { return }
        refreshSavedImportCandidates()
    }

    func refreshSavedImportCandidates(restartExisting: Bool = false) {
        if isSavedImportRefreshing {
            guard restartExisting else { return }
            savedImportRefreshTask?.cancel()
        }

        guard libraryStore.libraryURL != nil else {
            savedImportRefreshTask = nil
            savedImportRefreshID = nil
            isSavedImportRefreshing = false
            savedImportRefreshIsError = true
            savedImportRefreshMessage = "请先打开一个素材库文件夹，再刷新收藏"
            return
        }

        savedImportRefreshTask?.cancel()
        savedImportMetadataTask?.cancel()
        savedImportMetadataTask = nil
        savedImportMetadataID = nil
        let refreshID = UUID()
        savedImportRefreshID = refreshID
        isSavedImportRefreshing = true
        savedImportRefreshIsError = false
        savedImportRefreshMessage = "正在拉取 IG 和小红书收藏..."

        savedImportRefreshTask = Task { @MainActor in
            defer {
                if savedImportRefreshID == refreshID {
                    isSavedImportRefreshing = false
                    savedImportRefreshTask = nil
                    savedImportRefreshID = nil
                }
            }

            var links: [String] = []
            var metadataByLink: [String: SavedImportCandidateMetadata] = [:]
            var summaries: [String] = []
            var errors: [String] = []

            async let instagramOutcome = savedImportFetchOutcome {
                try await libraryStore.latestInstagramSavedImportCandidatesFromChrome()
            }
            async let xiaohongshuOutcome = savedImportFetchOutcome(suppressMissingXiaohongshuVideos: true) {
                try await libraryStore.latestXiaohongshuSavedVideoImportCandidatesFromChrome(limit: 50)
            }

            let (instagramResult, xiaohongshuResult) = await (instagramOutcome, xiaohongshuOutcome)

            if let result = instagramResult.result {
                links.append(contentsOf: result.queuedLinks)
                metadataByLink.merge(result.queuedMetadataByLink) { current, fallback in
                    current.merging(fallback)
                }
                summaries.append("IG \(result.queuedCount)")
            } else if let errorMessage = instagramResult.errorMessage {
                errors.append("IG：\(errorMessage)")
            }

            guard !Task.isCancelled, savedImportRefreshID == refreshID else { return }

            if let result = xiaohongshuResult.result {
                links.append(contentsOf: result.queuedLinks)
                metadataByLink.merge(result.queuedMetadataByLink) { current, fallback in
                    current.merging(fallback)
                }
                summaries.append("小红书 \(result.queuedCount)")
            } else if let errorMessage = xiaohongshuResult.errorMessage {
                errors.append("小红书：\(errorMessage)")
            }

            guard !Task.isCancelled, savedImportRefreshID == refreshID else { return }

            let alreadyAddedIDs = queuedOrImportedImportCandidateIDs
            let candidates = importVideos(from: links, metadataByLink: metadataByLink)
                .filter { !alreadyAddedIDs.contains($0.id) }
                .filter { !libraryStore.savedImportCandidateIsIgnored(sourceURLString: $0.urlString) }
            savedImportCandidates = candidates
            startSavedImportCandidateMetadataEnrichment(for: candidates)
            savedImportRefreshIsError = candidates.isEmpty && !errors.isEmpty

            if candidates.isEmpty {
                savedImportRefreshMessage = errors.isEmpty
                    ? "IG 和小红书收藏里没有未添加的视频"
                    : errors.joined(separator: " · ")
            } else if errors.isEmpty {
                savedImportRefreshMessage = "\(summaries.joined(separator: " · "))，共 \(candidates.count) 个未添加"
            } else {
                savedImportRefreshMessage = "已拉取 \(candidates.count) 个未添加 · \(errors.joined(separator: " · "))"
            }
        }
    }

    func startSavedImportCandidateMetadataEnrichment(for candidates: [PendingImportVideo]) {
        savedImportMetadataTask?.cancel()
        let enrichmentCandidates = candidates.filter(savedImportCandidateNeedsEnrichment)
        guard !enrichmentCandidates.isEmpty else {
            savedImportMetadataTask = nil
            savedImportMetadataID = nil
            return
        }

        let metadataID = UUID()
        savedImportMetadataID = metadataID

        savedImportMetadataTask = Task { @MainActor in
            defer {
                if savedImportMetadataID == metadataID {
                    savedImportMetadataTask = nil
                    savedImportMetadataID = nil
                }
            }

            let batches = savedImportMetadataBatches(from: enrichmentCandidates, size: 6)
            for batch in batches {
                guard !Task.isCancelled, savedImportMetadataID == metadataID else { return }
                let updates = await enrichedSavedImportCandidates(batch)
                guard !Task.isCancelled, savedImportMetadataID == metadataID else { return }
                for update in updates {
                    applySavedImportCandidateMetadata(update)
                }
            }
        }
    }

    func savedImportMetadataBatches(
        from candidates: [PendingImportVideo],
        size: Int
    ) -> [[PendingImportVideo]] {
        guard size > 0 else { return [candidates] }
        var batches: [[PendingImportVideo]] = []
        var index = candidates.startIndex
        while index < candidates.endIndex {
            let end = candidates.index(index, offsetBy: size, limitedBy: candidates.endIndex) ?? candidates.endIndex
            batches.append(Array(candidates[index..<end]))
            index = end
        }
        return batches
    }

    func enrichedSavedImportCandidates(_ candidates: [PendingImportVideo]) async -> [PendingImportVideo] {
        await withTaskGroup(of: PendingImportVideo?.self, returning: [PendingImportVideo].self) { group in
            for candidate in candidates where candidate.isSupported {
                let thumbnailURLString = cleanedSavedImportMetadataText(candidate.thumbnailURLString)
                group.addTask {
                    var updated = candidate

                    if updated.thumbnailData == nil,
                       let thumbnailURLString,
                       let thumbnailURL = URL(string: thumbnailURLString) {
                        updated.thumbnailData = await LibraryStore.fetchRemoteImageData(from: thumbnailURL)
                    }

                    updated.isMetadataLoading = false
                    return updated
                }
            }

            var updates: [PendingImportVideo] = []
            for await candidate in group {
                if let candidate {
                    updates.append(candidate)
                }
            }
            return updates
        }
    }

    func applySavedImportCandidateMetadata(_ updatedCandidate: PendingImportVideo) {
        guard let index = savedImportCandidates.firstIndex(where: { $0.id == updatedCandidate.id }) else { return }
        savedImportCandidates[index] = updatedCandidate
    }

    func savedImportCandidateNeedsEnrichment(_ candidate: PendingImportVideo) -> Bool {
        guard candidate.isSupported else { return false }
        if candidate.thumbnailData == nil,
           cleanedSavedImportMetadataText(candidate.thumbnailURLString) != nil {
            return true
        }
        return false
    }

    var detectedImportPlatform: String {
        guard
            let firstLink = importURLTokens.first,
            let url = URL(string: firstLink),
            let platform = LibraryStore.platformName(for: url)
        else { return "等待识别平台" }
        return platform
    }

    var platformIconName: String {
        VideoSourcePlatform.iconName(for: detectedImportPlatform)
    }

    var detectedImportPlatformSummary: String {
        let platforms = importURLTokens
            .compactMap { URL(string: $0) }
            .compactMap { LibraryStore.platformName(for: $0) }
        let unique = Array(Set(platforms)).sorted()
        guard !unique.isEmpty else { return "等待识别平台" }
        if unique.count == 1 { return "\(unique[0]) · \(platforms.count) 个链接" }
        return "\(unique.joined(separator: " / ")) · \(platforms.count) 个链接"
    }

    var importURLTokens: [String] {
        LibraryStore.remoteImportURLs(from: importURLText)
    }

    var manualImportVideos: [PendingImportVideo] {
        let alreadyAddedIDs = queuedOrImportedImportCandidateIDs
        return importVideos(from: importURLTokens)
            .filter { !alreadyAddedIDs.contains($0.id) }
    }

    var pendingImportVideos: [PendingImportVideo] {
        let alreadyAddedIDs = queuedOrImportedImportCandidateIDs
        var seenIDs = Set<String>()

        return savedImportCandidates.filter { candidate in
            !alreadyAddedIDs.contains(candidate.id) && seenIDs.insert(candidate.id).inserted
        }
    }

    func importVideos(
        from links: [String],
        metadataByLink: [String: SavedImportCandidateMetadata] = [:]
    ) -> [PendingImportVideo] {
        let metadataByID = savedImportMetadataByCandidateID(from: metadataByLink)
        var seenIDs = Set<String>()
        return links.compactMap { link in
            let id = importCandidateID(for: link)
            guard let video = importVideoCandidate(from: link, metadata: metadataByID[id]) else { return nil }
            guard seenIDs.insert(video.id).inserted else { return nil }
            return video
        }
    }

    func savedImportMetadataByCandidateID(
        from metadataByLink: [String: SavedImportCandidateMetadata]
    ) -> [String: SavedImportCandidateMetadata] {
        var metadataByID: [String: SavedImportCandidateMetadata] = [:]
        for (link, metadata) in metadataByLink where metadata.hasAnyValue {
            let id = importCandidateID(for: link)
            if let current = metadataByID[id] {
                metadataByID[id] = current.merging(metadata)
            } else {
                metadataByID[id] = metadata
            }
        }
        return metadataByID
    }

    func importVideoCandidate(
        from rawURL: String,
        metadata: SavedImportCandidateMetadata? = nil
    ) -> PendingImportVideo? {
        guard let url = URL(string: rawURL) else { return nil }
        let platform = LibraryStore.platformName(for: url)
        let cleanedMetadata = SavedImportCandidateMetadata(
            title: cleanedSavedImportMetadataText(metadata?.title),
            authorName: cleanedSavedImportMetadataText(metadata?.authorName),
            thumbnailURLString: cleanedSavedImportMetadataText(metadata?.thumbnailURLString)
        )
        return PendingImportVideo(
            id: importCandidateID(for: rawURL),
            urlString: rawURL,
            platform: platform ?? "未知平台",
            title: cleanedMetadata.title ?? pendingImportTitle(for: url, platform: platform),
            subtitle: pendingImportSubtitle(for: url),
            authorName: cleanedMetadata.authorName,
            thumbnailURLString: cleanedMetadata.thumbnailURLString,
            hasSeededMetadata: cleanedMetadata.hasAnyValue,
            isSupported: platform != nil
        )
    }

    func cleanedSavedImportMetadataText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var queuedOrImportedImportCandidateIDs: Set<String> {
        var ids = Set<String>()

        for sourceInfo in libraryStore.sourceInfoByVideoPath.values {
            if let sourceURL = sourceInfo.sourceURL {
                ids.insert(importCandidateID(for: sourceURL))
            }
        }

        for job in libraryStore.remoteImportJobs where LibraryStore.remoteImportJobCountsAsQueuedOrImported(job.status) {
            ids.insert(importCandidateID(for: job.sourceURL.absoluteString))
        }

        return ids
    }

    func importCandidateID(for rawValue: String) -> String {
        if let normalized = LibraryStore.normalizedInstagramContentURL(rawValue) {
            return "instagram:\(normalized)"
        }
        if let normalized = LibraryStore.normalizedXiaohongshuNoteURL(rawValue) {
            return "xiaohongshu:\(normalized)"
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else {
            return trimmed.lowercased()
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        return components.url?.absoluteString ?? trimmed.lowercased()
    }

    func pendingImportTitle(for url: URL, platform: String?) -> String {
        if platform == "Instagram",
           let content = LibraryStore.instagramContentParts(from: url) {
            let type = content.type == "reel" ? "Reel" : "帖子"
            return "Instagram \(type) · \(content.shortcode)"
        }

        if platform == "小红书",
           let noteID = LibraryStore.xiaohongshuNoteID(from: url) {
            return "小红书视频 · \(noteID)"
        }

        if platform == "YouTube" {
            if url.host?.lowercased() == "youtu.be", !url.lastPathComponent.isEmpty {
                return "YouTube · \(url.lastPathComponent)"
            }
            if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               let videoID = queryItems.first(where: { $0.name == "v" })?.value,
               !videoID.isEmpty {
                return "YouTube · \(videoID)"
            }
        }

        let fallbackPlatform = platform ?? "链接"
        let pathTail = url.pathComponents.last { $0 != "/" && !$0.isEmpty }
        if let pathTail {
            return "\(fallbackPlatform) · \(pathTail)"
        }
        return fallbackPlatform
    }

    func pendingImportSubtitle(for url: URL) -> String {
        guard let host = url.host, !host.isEmpty else {
            return url.absoluteString
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return host }
        return "\(host)/\(path)"
    }

    func sourcePlatformName(for video: VideoItem) -> String? {
        guard let platform = libraryStore.videoSourcePlatform(for: video) else { return nil }
        guard !LibraryStore.isUnknownSourcePlatform(platform) else { return nil }
        return VideoSourcePlatform.matching(platform)?.rawValue ?? platform
    }

    func videoDisplayName(for video: VideoItem) -> String {
        libraryStore.videoSourceTitle(for: video) ?? video.name
    }

    var isImporting: Bool {
        !activeImportJobs.isEmpty
    }

    var activeImportJobs: [RemoteImportJob] {
        libraryStore.remoteImportJobs.filter(isActiveImportJob)
    }

    var importHistoryJobs: [RemoteImportJob] {
        libraryStore.remoteImportJobs.filter(isImportHistoryJob)
    }

    var downloadTimelineJobs: [RemoteImportJob] {
        libraryStore.remoteImportJobs.enumerated()
            .sorted { lhs, rhs in
                let leftPriority = downloadTimelinePriority(for: lhs.element)
                let rightPriority = downloadTimelinePriority(for: rhs.element)
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
                return leftPriority <= 2 ? lhs.offset < rhs.offset : lhs.offset > rhs.offset
            }
            .map(\.element)
    }

    func downloadTimelinePriority(for job: RemoteImportJob) -> Int {
        switch job.status {
        case .importing, .transcoding, .finalizing:
            return 0
        case .idle:
            return 1
        case .paused:
            return 2
        case .failed:
            return 3
        case .succeeded:
            return 4
        }
    }

    var importHistoryItems: [ImportHistoryItem] {
        var items: [ImportHistoryItem] = []
        var batchIndexByID: [UUID: Int] = [:]

        for job in importHistoryJobs {
            guard let batchID = job.batchID else {
                items.append(.single(job))
                continue
            }

            if let itemIndex = batchIndexByID[batchID],
               case var .batch(batch) = items[itemIndex] {
                batch.jobs.append(job)
                items[itemIndex] = .batch(batch)
            } else {
                let title = job.batchTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                batchIndexByID[batchID] = items.count
                items.append(.batch(ImportHistoryBatch(
                    id: batchID,
                    title: title.map { $0.isEmpty ? "批量导入" : $0 } ?? "批量导入",
                    jobs: [job]
                )))
            }
        }

        return items
    }

    var finishedImportCount: Int {
        libraryStore.remoteImportJobs.filter { job in
            if case .succeeded = job.status { return true }
            return false
        }.count
    }

    var failedImportCount: Int {
        libraryStore.remoteImportJobs.filter { job in
            if case .failed = job.status { return true }
            return false
        }.count
    }

    var importProgressSummary: String {
        guard !activeImportJobs.isEmpty else {
            return libraryStore.remoteImportJobs.isEmpty ? "" : "下载任务已完成"
        }

        let progress = activeImportOverallProgress
        guard let progress else { return "\(activeImportJobs.count) 个任务 · 等待准确进度" }
        return "\(activeImportJobs.count) 个任务 · \(progressPercentText(progress))"
    }

    var downloadTimelineSummary: String {
        guard !libraryStore.remoteImportJobs.isEmpty else { return "" }

        if !activeImportJobs.isEmpty {
            if let progress = activeImportOverallProgress {
                return "\(activeImportJobs.count) · \(progressPercentText(progress))"
            }
            return "\(activeImportJobs.count) 个任务"
        }

        if failedImportCount > 0 {
            return "\(finishedImportCount) 完成 · \(failedImportCount) 失败"
        }
        return "\(finishedImportCount) 已完成"
    }

    var activeImportOverallProgress: Double? {
        guard !activeImportJobs.isEmpty else { return nil }
        let progressValues = activeImportJobs.compactMap { job in
            job.downloadProgress.map(normalizedProgressFraction)
        }
        guard progressValues.count == activeImportJobs.count else { return nil }
        return progressValues.reduce(0, +) / Double(progressValues.count)
    }

    func isActiveImportJob(_ job: RemoteImportJob) -> Bool {
        switch job.status {
        case .idle, .importing, .transcoding, .finalizing, .paused:
            return true
        default:
            return false
        }
    }

    func isImportHistoryJob(_ job: RemoteImportJob) -> Bool {
        switch job.status {
        case .succeeded, .failed:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    func importHistoryListItem(_ item: ImportHistoryItem) -> some View {
        switch item {
        case .single(let job):
            importJobStatus(job)
        case .batch(let batch):
            importBatchHistoryStatus(batch)
        }
    }

    func importBatchHistoryStatus(_ batch: ImportHistoryBatch) -> some View {
        let isExpanded = expandedImportBatchIDs.contains(batch.id)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                    if isExpanded {
                        expandedImportBatchIDs.remove(batch.id)
                    } else {
                        expandedImportBatchIDs.insert(batch.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    Image(systemName: importBatchIconName(batch))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(importBatchTint(batch))
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(importBatchTitle(batch))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(importBatchSummaryText(batch))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(batch.completedCount)/\(max(batch.totalCount, batch.completedCount))")
                        .font(Design.numericCaption(weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVStack(spacing: 8) {
                    ForEach(batch.jobs) { job in
                        importJobStatus(job)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    func importBatchTitle(_ batch: ImportHistoryBatch) -> String {
        "\(batch.title) · \(batch.totalCount) 条"
    }

    func importBatchSummaryText(_ batch: ImportHistoryBatch) -> String {
        if batch.failedCount > 0 {
            return "\(batch.succeededCount) 成功 · \(batch.failedCount) 失败"
        }
        if batch.completedCount < batch.totalCount {
            return "已完成 \(batch.completedCount) 条，剩余任务仍在下载"
        }
        return "全部下载完成"
    }

    func importBatchIconName(_ batch: ImportHistoryBatch) -> String {
        batch.failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    func importBatchTint(_ batch: ImportHistoryBatch) -> Color {
        batch.failedCount > 0
            ? Color.red.opacity(0.86)
            : Color(red: 0.42, green: 0.78, blue: 0.48)
    }

    @ViewBuilder
    func importJobStatus(_ job: RemoteImportJob) -> some View {
        if isImportHistoryJob(job) {
            importHistoryJobStatus(job)
        } else {
            importActiveJobStatus(job)
        }
    }

    func importActiveJobStatus(_ job: RemoteImportJob) -> some View {
        HStack(alignment: .top, spacing: 12) {
            importJobCover(for: job, width: 100, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(importActiveStatusText(for: job))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 18)

                Text(job.sourceURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(height: 16)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)

            importJobActions(for: job)
                .frame(height: 56, alignment: .top)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .frame(minHeight: 76)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    func importActiveStatusText(for job: RemoteImportJob) -> String {
        switch job.status {
        case .idle:
            return "等待下载"
        case .importing:
            guard let progressText = importStatusProgressText(for: job) else {
                return "正在处理下载任务 · 等待准确进度"
            }
            return "正在下载 \(job.platform) · \(progressText)"
        case .transcoding:
            guard let progressText = importStatusProgressText(for: job) else {
                return "正在转码 · 等待 ffmpeg 返回进度"
            }
            return "正在转码 · \(progressText)"
        case .finalizing:
            guard let progressText = importStatusProgressText(for: job) else {
                return "正在整理导入结果"
            }
            return "正在整理导入结果 · \(progressText)"
        case .paused:
            if let progressText = importStatusProgressText(for: job) {
                return "\(job.platform) 已暂停 · \(progressText)"
            }
            return "\(job.platform) 已暂停"
        case let .succeeded(filename):
            return filename
        case .failed:
            return "\(job.platform) 下载失败"
        }
    }

    func importHistoryJobStatus(_ job: RemoteImportJob) -> some View {
        HStack(alignment: .top, spacing: 12) {
            importJobCover(for: job, width: 100, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(importStatusTitle(for: job))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(job.sourceURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if let video = importedVideo(for: job) {
                    importJobTagStrip(for: video)
                }

                if case let .failed(message) = job.status {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(Color.red.opacity(0.86))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)

            importJobActions(for: job)
                .frame(height: 56, alignment: .top)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .frame(minHeight: 76)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 0.8)
        }
    }

    func importJobCover(for job: RemoteImportJob, width: CGFloat = 76, height: CGFloat = 52) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.06))

            if let image = importJobThumbnail(for: job) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: importStatusIconName(for: job))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(importStatusTint(for: job))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    func importJobThumbnail(for job: RemoteImportJob) -> NSImage? {
        if let outputPath = job.outputPath,
           let image = libraryStore.thumbnailImageByVideoPath[outputPath] {
            return image
        }
        if let data = job.thumbnailData {
            return NSImage(data: data)
        }
        return nil
    }

    func importedVideo(for job: RemoteImportJob) -> VideoItem? {
        guard let outputPath = job.outputPath else { return nil }
        return libraryStore.selectedVideo(for: outputPath)
    }

    @ViewBuilder
    func importJobActions(for job: RemoteImportJob) -> some View {
        VStack(spacing: 4) {
            if case .paused = job.status {
                importJobActionButton(icon: "play.fill", help: "继续下载") {
                    libraryStore.resumeRemoteImportJob(id: job.id)
                }
            } else if isActiveImportJob(job) {
                importJobActionButton(icon: "pause.fill", help: "暂停下载") {
                    libraryStore.pauseRemoteImportJob(id: job.id)
                }
            } else if job.outputPath != nil {
                importJobActionButton(icon: "arrow.turn.up.right", help: "跳转到视频") {
                    libraryStore.jumpToRemoteImportJob(id: job.id)
                    closeImportPanel()
                }
            }

            importJobActionButton(icon: "trash", help: "删除条目") {
                libraryStore.deleteRemoteImportJob(id: job.id)
            }
        }
        .frame(width: 30)
    }

    @ViewBuilder
    func importJobTagStrip(for video: VideoItem) -> some View {
        let tags = libraryStore.videoTags(for: video)

        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        CardInlineTagChip(tag: tag)
                    }
                }
                .frame(minHeight: 18, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            .clipped()
        }
    }

    func importJobActionButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func importStatusTitle(for job: RemoteImportJob) -> String {
        switch job.status {
        case .idle:
            return "等待下载"
        case .importing:
            return "正在下载 \(job.platform)"
        case .transcoding:
            return "正在转码为 H.264"
        case .finalizing:
            return "正在整理导入结果"
        case .paused:
            return "\(job.platform) 已暂停"
        case let .succeeded(filename):
            return filename
        case .failed:
            return "\(job.platform) 下载失败"
        }
    }

    func importStatusIconName(for job: RemoteImportJob) -> String {
        switch job.status {
        case .idle:
            return "clock"
        case .importing:
            return "arrow.down.circle.fill"
        case .transcoding:
            return "film.circle.fill"
        case .finalizing:
            return "checkmark.seal.fill"
        case .paused:
            return "pause.circle.fill"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    func importStatusTint(for job: RemoteImportJob) -> Color {
        switch job.status {
        case .idle:
            return .secondary
        case .importing:
            return Color(red: 0.36, green: 0.70, blue: 1.00)
        case .transcoding:
            return Design.captureFrameAccent
        case .finalizing:
            return Color(red: 0.42, green: 0.78, blue: 0.48)
        case .paused:
            return .secondary
        case .succeeded:
            return Color(red: 0.42, green: 0.78, blue: 0.48)
        case .failed:
            return Color.red.opacity(0.86)
        }
    }

    func importStatusProgressText(for job: RemoteImportJob) -> String? {
        switch job.status {
        case .importing, .paused, .succeeded:
            guard let progress = job.downloadProgress else { return nil }
            if case .importing = job.status,
               let speed = job.downloadSpeed,
               !speed.isEmpty {
                return "\(progressPercentText(progress)) · \(speed)"
            }
            return progressPercentText(progress)
        case .transcoding, .finalizing:
            guard let progress = job.downloadProgress else { return nil }
            return progressPercentText(progress)
        default:
            return nil
        }
    }

}
