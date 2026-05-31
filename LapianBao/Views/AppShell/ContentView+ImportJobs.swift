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
        let text = importURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !importURLTokens.isEmpty else { return }
        libraryStore.saveInstagramImportEndpoint(importEndpointText)
        libraryStore.importRemoteVideos(from: text)
        importURLText = ""
    }

    func syncLatestInstagramSaved() {
        guard !isInstagramSavedSyncing else { return }

        isInstagramSavedSyncing = true
        instagramSavedSyncIsError = false
        instagramSavedSyncMessage = "正在读取 Chrome 收藏页..."

        Task { @MainActor in
            defer { isInstagramSavedSyncing = false }

            do {
                let result = try await libraryStore.importLatestInstagramSavedFromChrome()
                instagramSavedSyncIsError = false
                instagramSavedSyncMessage = instagramSavedSyncStatusText(result)
            } catch {
                instagramSavedSyncIsError = true
                instagramSavedSyncMessage = error.localizedDescription
            }
        }
    }

    func syncLatestXiaohongshuSavedVideos() {
        guard !isXiaohongshuSavedSyncing else { return }

        isXiaohongshuSavedSyncing = true
        xiaohongshuSavedSyncIsError = false
        xiaohongshuSavedSyncMessage = "正在读取 Chrome 小红书收藏页..."

        Task { @MainActor in
            defer { isXiaohongshuSavedSyncing = false }

            do {
                let result = try await libraryStore.importLatestXiaohongshuSavedVideosFromChrome(limit: 10)
                xiaohongshuSavedSyncIsError = false
                xiaohongshuSavedSyncMessage = xiaohongshuSavedSyncStatusText(result)
            } catch {
                xiaohongshuSavedSyncIsError = true
                xiaohongshuSavedSyncMessage = error.localizedDescription
            }
        }
    }

    func instagramSavedSyncStatusText(_ result: InstagramSavedImportResult) -> String {
        if result.queuedCount > 0 {
            return "扫描 \(result.scannedPageCount) 页，发现 \(result.foundCount) 条，新加入 \(result.queuedCount) 条"
        }
        if result.skippedCount > 0 {
            return "扫描 \(result.scannedPageCount) 页，发现 \(result.foundCount) 条，均已在基准中"
        }
        return "没有新的收藏链接"
    }

    func xiaohongshuSavedSyncStatusText(_ result: InstagramSavedImportResult) -> String {
        if result.queuedCount > 0 {
            return "发现 \(result.foundCount) 条视频，新加入 \(result.queuedCount) 条"
        }
        if result.skippedCount > 0 {
            return "发现 \(result.foundCount) 条视频，均已在库中"
        }
        return "没有新的视频收藏链接"
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
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，"))
        return importURLText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }

    func sourcePlatformName(for video: VideoItem) -> String? {
        guard let platform = libraryStore.videoSourcePlatform(for: video) else { return nil }
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
            return libraryStore.remoteImportJobs.isEmpty ? "等待添加下载链接" : "下载任务已完成"
        }

        let progress = activeImportOverallProgress
        guard let progress else { return "\(activeImportJobs.count) 个任务进行中 · 等待准确进度" }
        return "\(activeImportJobs.count) 个任务进行中 · 可追踪 \(progressPercentText(progress))"
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
        case .importing, .transcoding, .finalizing, .paused:
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
                        .font(.caption.monospacedDigit().weight(.semibold))
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
            ? Color(red: 0.96, green: 0.58, blue: 0.24)
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

                importStatusDetail(for: job)
                    .frame(height: 8)
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
                        .foregroundStyle(Color(red: 0.96, green: 0.58, blue: 0.24))
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
        let tags = libraryStore.tagsByVideoPath[video.url.path, default: []]

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
            .help(tags.joined(separator: " / "))
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
        .help(help)
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
            return Color(red: 0.96, green: 0.58, blue: 0.24)
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

    @ViewBuilder
    func importStatusDetail(for job: RemoteImportJob) -> some View {
        switch job.status {
        case .idle:
            EmptyView()
        case .paused:
            if let progress = job.downloadProgress {
                importLinearProgress(progress, tint: .secondary)
            } else {
                EmptyView()
            }
        case .importing:
            if let progress = job.downloadProgress {
                importLinearProgress(progress, tint: Color(red: 0.36, green: 0.70, blue: 1.00))
            } else {
                importIndeterminateProgress(tint: Color(red: 0.36, green: 0.70, blue: 1.00))
            }
        case .transcoding:
            if let progress = job.downloadProgress {
                importLinearProgress(progress, tint: Design.captureFrameAccent)
            } else {
                importIndeterminateProgress(tint: Design.captureFrameAccent)
            }
        case .finalizing:
            if let progress = job.downloadProgress {
                importLinearProgress(progress, tint: Color(red: 0.42, green: 0.78, blue: 0.48))
            } else {
                importIndeterminateProgress(tint: Color(red: 0.42, green: 0.78, blue: 0.48))
            }
        case .succeeded:
            EmptyView()
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(Color(red: 0.96, green: 0.58, blue: 0.24))
                .lineLimit(4)
                .textSelection(.enabled)
        }
    }

    func importLinearProgress(_ progress: Double, tint: Color) -> some View {
        ProgressView(value: normalizedProgressFraction(progress))
            .progressViewStyle(.linear)
            .controlSize(.small)
            .tint(tint)
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    func importIndeterminateProgress(tint: Color) -> some View {
        ProgressView()
            .progressViewStyle(.linear)
            .controlSize(.small)
            .tint(tint)
    }

}
