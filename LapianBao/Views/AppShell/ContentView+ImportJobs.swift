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
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            isImportSheetPresented = false
        }
    }

    func startRemoteImport() {
        let videos = manualImportVideos
        guard !videos.isEmpty else {
            importURLFeedbackMessage = unavailableImportURLFeedbackText
            return
        }

        importURLFeedbackMessage = nil
        libraryStore.saveInstagramImportEndpoint(importEndpointText)
        libraryStore.importRemoteVideos(from: videos.map(\.urlString).joined(separator: "\n"))

        let importedIDs = Set(videos.map(\.id))
        let remainingURLs = LibraryStore.remoteImportURLs(from: importURLText)
            .filter { !importedIDs.contains(importCandidateID(for: $0)) }
        importURLText = remainingURLs.joined(separator: "\n")
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

    var canSubmitImportURLs: Bool {
        !importURLTokens.isEmpty
    }

    var importInputStatusText: String? {
        if let importURLFeedbackMessage {
            return importURLFeedbackMessage
        }

        guard !importURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        if !manualImportVideos.isEmpty {
            let duplicateCount = duplicateManualImportVideos.count
            if duplicateCount > 0 {
                return "\(manualImportVideos.count) 个可下载 · \(duplicateCount) 个已存在"
            }
            return "\(manualImportVideos.count) 个输入链接"
        }

        if !duplicateManualImportVideos.isEmpty {
            return unavailableImportURLFeedbackText
        }

        if !importURLTokens.isEmpty {
            return "\(importURLTokens.count) 个链接待检查"
        }

        return "没有识别到有效链接"
    }

    var importInputStatusIconName: String {
        if importURLFeedbackMessage != nil {
            return "exclamationmark.circle.fill"
        }
        if !manualImportVideos.isEmpty {
            return VideoSourcePlatform.iconName(for: manualImportVideos[0].platform)
        }
        if !duplicateManualImportVideos.isEmpty {
            return "checkmark.circle.fill"
        }
        return "exclamationmark.triangle.fill"
    }

    var importInputStatusColor: Color {
        if importURLFeedbackMessage != nil {
            return Color.orange.opacity(0.9)
        }
        if !manualImportVideos.isEmpty {
            return VideoSourcePlatform.color(for: manualImportVideos[0].platform)
        }
        if !duplicateManualImportVideos.isEmpty {
            return Color(red: 0.42, green: 0.78, blue: 0.48)
        }
        return Color.orange.opacity(0.9)
    }

    var unavailableImportURLFeedbackText: String {
        if !duplicateManualImportVideos.isEmpty {
            return "\(duplicateManualImportVideos.count) 个链接已在素材库或下载队列中"
        }
        if !importURLTokens.isEmpty {
            return "链接已识别，但没有可加入的新任务"
        }
        return "没有识别到有效链接"
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

    var duplicateManualImportVideos: [PendingImportVideo] {
        let alreadyAddedIDs = queuedOrImportedImportCandidateIDs
        return importVideos(from: importURLTokens)
            .filter { alreadyAddedIDs.contains($0.id) }
    }

    func importVideos(from links: [String]) -> [PendingImportVideo] {
        var seenIDs = Set<String>()
        return links.compactMap { link in
            guard let video = importVideoCandidate(from: link) else { return nil }
            guard seenIDs.insert(video.id).inserted else { return nil }
            return video
        }
    }

    func importVideoCandidate(from rawURL: String) -> PendingImportVideo? {
        guard let url = URL(string: rawURL) else { return nil }
        let platform = LibraryStore.platformName(for: url)
        return PendingImportVideo(
            id: importCandidateID(for: rawURL),
            urlString: rawURL,
            platform: platform ?? "未知平台",
            title: pendingImportTitle(for: url, platform: platform),
            subtitle: pendingImportSubtitle(for: url),
            isSupported: platform != nil
        )
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

        return "\(activeImportJobs.count) 个任务"
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

    var downloadHistorySummary: String {
        let totalCount = finishedImportCount + failedImportCount
        guard totalCount > 0 else { return "" }
        if failedImportCount > 0 {
            return "\(finishedImportCount) 完成 · \(failedImportCount) 失败"
        }
        return "\(finishedImportCount) 条记录"
    }

    var activeImportOverallProgress: Double? {
        guard !activeImportJobs.isEmpty else { return nil }
        let progressValues = activeImportJobs.map { job in
            normalizedImportProgress(for: job)
        }
        return progressValues.reduce(0, +) / Double(progressValues.count)
    }

    func normalizedImportProgress(for job: RemoteImportJob) -> Double {
        if let progress = job.downloadProgress {
            return normalizedProgressFraction(progress)
        }

        switch job.status {
        case .idle, .paused, .importing:
            return 0
        case .transcoding:
            return 0.92
        case .finalizing:
            return 0.98
        case .succeeded:
            return 1
        case .failed:
            return 0
        }
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

    func importProgressJobStatus(_ job: RemoteImportJob) -> some View {
        HStack(alignment: .center, spacing: 10) {
            importJobCover(for: job, width: 54, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(importProgressTitleText(for: job))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(job.candidateTitle == nil ? Color.secondary : Color.white.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 6)

                    Text(importProgressBadgeText(for: job))
                        .font(Design.numericCaption(weight: .semibold))
                        .foregroundStyle(importStatusTint(for: job))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Text(job.sourceURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                importActiveProgressBar(for: job)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            importJobActions(for: job)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    func importProgressTitleText(for job: RemoteImportJob) -> String {
        job.candidateTitle ?? importStatusTitle(for: job)
    }

    func importProgressBadgeText(for job: RemoteImportJob) -> String {
        progressPercentText(normalizedImportProgress(for: job))
    }

    func importActiveJobStatus(_ job: RemoteImportJob) -> some View {
        HStack(alignment: .top, spacing: 12) {
            importJobCover(for: job, width: 100, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(importActiveTitleText(for: job))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(job.candidateTitle == nil ? Color.secondary : Color.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 18)

                Text(importActiveSubtitleText(for: job))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(height: 16)

                Spacer(minLength: 0)

                importActiveProgressBar(for: job)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 56)

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

    func importActiveProgressBar(for job: RemoteImportJob) -> some View {
        let progress = normalizedImportProgress(for: job)
        let tint = importStatusTint(for: job)

        return GeometryReader { proxy in
            let width = max(0, proxy.size.width)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.white.opacity(0.075))

                if progress > 0 {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(0.90))
                        .frame(width: max(4, width * CGFloat(progress)))
                }
            }
        }
        .frame(height: 4)
        .padding(.top, 5)
        .accessibilityLabel("下载进度")
        .accessibilityValue(progressPercentText(progress))
    }

    func importActiveTitleText(for job: RemoteImportJob) -> String {
        job.candidateTitle ?? importActiveStatusText(for: job)
    }

    func importActiveSubtitleText(for job: RemoteImportJob) -> String {
        guard job.candidateTitle != nil else {
            return job.sourceURL.absoluteString
        }

        let detailText = importJobMetadataDetailText(for: job, leadingText: importActiveStatusText(for: job))
        return detailText.isEmpty ? job.sourceURL.absoluteString : detailText
    }

    func importJobMetadataDetailText(for job: RemoteImportJob, leadingText: String?) -> String {
        var parts: [String] = []
        if let leadingText, !leadingText.isEmpty {
            parts.append(leadingText)
        }
        if let authorName = job.candidateAuthorName, !authorName.isEmpty {
            parts.append(authorName)
        }
        return parts.joined(separator: " · ")
    }

    func importHistorySourceText(for job: RemoteImportJob) -> String {
        var parts = [importHistorySourceName(for: job)]
        if let authorName = importHistoryAuthorName(for: job) {
            parts.append(authorName)
        }
        return parts.joined(separator: " · ")
    }

    func importHistorySourceName(for job: RemoteImportJob) -> String {
        if let outputPath = job.outputPath,
           let platform = libraryStore.sourceInfoByVideoPath[outputPath]?.platform.trimmingCharacters(in: .whitespacesAndNewlines),
           !platform.isEmpty {
            return platform
        }
        return job.platform
    }

    func importHistoryAuthorName(for job: RemoteImportJob) -> String? {
        if let outputPath = job.outputPath,
           let authorName = libraryStore.sourceInfoByVideoPath[outputPath]?.authorName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !authorName.isEmpty {
            return authorName
        }
        if let authorName = job.candidateAuthorName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !authorName.isEmpty {
            return authorName
        }
        return nil
    }

    func importHistoryFileDetailText(for job: RemoteImportJob) -> String? {
        guard let outputPath = job.outputPath else { return nil }

        let metadata = libraryStore.metadataByVideoPath[outputPath]
        var parts: [String] = []

        if let resolutionText = metadata?.resolutionText {
            parts.append(resolutionText)
        }

        if let fileSize = metadata?.fileSize ?? importHistoryFileSize(for: outputPath),
           let fileSizeText = importHistoryFileSizeText(fileSize) {
            parts.append(fileSizeText)
        }

        let duration = libraryStore.durationByVideoPath[outputPath] ?? metadata?.duration
        if let duration, duration.isFinite, duration > 0 {
            parts.append(formatDuration(duration))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func importHistoryFileSize(for outputPath: String) -> Int64? {
        let url = URL(fileURLWithPath: outputPath)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values?.fileSize, fileSize > 0 else { return nil }
        return Int64(fileSize)
    }

    func importHistoryFileSizeText(_ fileSize: Int64) -> String? {
        guard fileSize > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
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

            VStack(alignment: .leading, spacing: 5) {
                // 标题贴封面顶边、信息行贴封面底边,文字块与封面等高对齐
                VStack(alignment: .leading, spacing: 5) {
                    Text(importStatusTitle(for: job))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(importHistorySourceText(for: job))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer(minLength: 0)

                    if let detailText = importHistoryFileDetailText(for: job) {
                        Text(detailText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                    }
                }
                .frame(height: 56, alignment: .topLeading)

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

    func importJobAccessibilityKey(for job: RemoteImportJob) -> String {
        Self.accessibilityStableKey(job.sourceURL.absoluteString)
    }

    @ViewBuilder
    func importJobActions(for job: RemoteImportJob) -> some View {
        let jobAccessibilityKey = importJobAccessibilityKey(for: job)

        VStack(spacing: 4) {
            if case .paused = job.status {
                importJobActionButton(icon: "play.fill", help: "继续下载", identifier: "import_job_resume_\(job.id.uuidString)") {
                    libraryStore.resumeRemoteImportJob(id: job.id)
                }
            } else if isActiveImportJob(job) {
                importJobActionButton(icon: "pause.fill", help: "暂停下载", identifier: "import_job_pause_\(job.id.uuidString)") {
                    libraryStore.pauseRemoteImportJob(id: job.id)
                }
            } else if job.outputPath != nil {
                importJobActionButton(icon: "arrow.turn.up.right", help: "跳转到视频", identifier: "import_job_jump_\(jobAccessibilityKey)_\(job.id.uuidString)") {
                    libraryStore.jumpToRemoteImportJob(id: job.id)
                    closeImportPanel()
                }
            }

            importJobActionButton(icon: "trash", help: "删除条目", identifier: "import_job_delete_\(job.id.uuidString)") {
                libraryStore.deleteRemoteImportJob(id: job.id)
            }
        }
        .frame(width: 30)
    }

    nonisolated static func accessibilityStableKey(_ rawValue: String) -> String {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
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

    func importJobActionButton(
        icon: String,
        help: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
        .accessibilityIdentifier(identifier)
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
            return Design.neutralAccent
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
