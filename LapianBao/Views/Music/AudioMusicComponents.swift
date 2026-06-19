//
//  AudioMusicComponents.swift
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

enum MusicFilterKind: String, CaseIterable, Hashable {
    case artist = "作者"
    case tag = "类型"
}

struct MusicFilterOption: Identifiable, Hashable {
    var kind: MusicFilterKind
    var value: String

    var id: String { "\(kind.rawValue)|\(value)" }
}

private struct MusicTagStrip: View {
    let tags: [String]

    private var visibleTags: [String] {
        Array(tags.prefix(4))
    }

    private var overflowCount: Int {
        max(0, tags.count - visibleTags.count)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleTags, id: \.self) { tag in
                CardInlineTagChip(tag: tag)
            }

            if overflowCount > 0 {
                VideoTagOverflowChip(count: overflowCount)
                    .frame(height: 18, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        .clipped()
    }
}

enum MusicSortOption: String, CaseIterable, Identifiable {
    case title
    case addedDate
    case artist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: return "按名称排序"
        case .addedDate: return "按添加日期排序"
        case .artist: return "按作者排序"
        }
    }
}

func completedMusicFileURL(for job: MusicDownloadJob?) -> URL? {
    guard
        let job,
        case .succeeded = job.status,
        let filePath = job.filePath,
        FileManager.default.fileExists(atPath: filePath)
    else { return nil }
    return URL(fileURLWithPath: filePath)
}

func musicPreviewTimeText(duration: Double, progress: Double, isActive: Bool) -> String? {
    guard duration.isFinite, duration > 0 else { return nil }
    let totalText = clockText(duration)
    guard isActive else { return totalText }
    let current = duration * min(1, max(0, progress))
    return "\(clockText(current)) / \(totalText)"
}

func hasCompletedMusicDownload(_ jobs: [MusicDownloadJob]) -> Bool {
    jobs.contains { completedMusicFileURL(for: $0) != nil }
}

func completedMusicFileURLs(from jobs: [MusicDownloadJob]) -> [URL] {
    var seenPaths = Set<String>()
    return MusicDownloadJob.DownloadType.allCases.compactMap { type in
        jobs.last { job in
            job.type == type && completedMusicFileURL(for: job) != nil
        }
    }
    .compactMap(completedMusicFileURL)
    .compactMap { url in
        guard seenPaths.insert(url.path).inserted else { return nil }
        return url
    }
}

func musicDownloadIcon(type _: MusicDownloadJob.DownloadType, job: MusicDownloadJob?) -> String {
    completedMusicFileURL(for: job) == nil ? "arrow.down.circle" : "play.circle.fill"
}

func musicDownloadTitle(type: MusicDownloadJob.DownloadType, job: MusicDownloadJob?) -> String {
    guard let job else { return type.label }
    switch job.status {
    case .succeeded:
        return type.label
    case .importing, .transcoding, .finalizing:
        if let progress = job.downloadProgress {
            return "\(Int((normalizedProgressFraction(progress) * 100).rounded()))%"
        }
        return "下载中"
    case .failed:
        return "失败"
    case .paused:
        return "暂停"
    case .idle:
        return type.label
    }
}

func musicDownloadHelp(type: MusicDownloadJob.DownloadType, job: MusicDownloadJob?) -> String {
    guard let job else { return "下载\(type.label)" }
    switch job.status {
    case .succeeded:
        return "播放已下载\(type.label)"
    case .importing, .transcoding, .finalizing:
        return "正在下载\(type.label)"
    case .failed(let message):
        return message.isEmpty ? "\(type.label)下载失败" : message
    case .paused:
        return "\(type.label)下载已暂停"
    case .idle:
        return "下载\(type.label)"
    }
}

func musicDownloadDisplayName(for job: MusicDownloadJob) -> String {
    let title = job.songKey
        .split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        .first
        .map(String.init)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let fallbackName: String
    if case let .succeeded(filename) = job.status {
        fallbackName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
    } else {
        fallbackName = job.type.label
    }

    let baseName = title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
    return job.type == .instrumental ? "\(baseName)（伴奏版）" : baseName
}

func sanitizedMusicFilenameStem(_ name: String) -> String {
    let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    let sanitized = name
        .components(separatedBy: forbidden)
        .joined(separator: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized.isEmpty ? "音乐" : sanitized
}

func musicDownloadSuggestedFilename(for job: MusicDownloadJob, fileURL: URL) -> String {
    let stem = sanitizedMusicFilenameStem(musicDownloadDisplayName(for: job))
    let fileExtension = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
    return fileExtension.isEmpty ? stem : "\(stem).\(fileExtension)"
}

func musicDownloadFileDragProvider(for job: MusicDownloadJob?) -> (() -> NSItemProvider)? {
    guard let job, let fileURL = completedMusicFileURL(for: job) else { return nil }
    return {
        let suggestedName = musicDownloadSuggestedFilename(for: job, fileURL: fileURL)
        let dragURL = externalAudioDragFileURL(for: fileURL, suggestedName: suggestedName)
        return existingFileItemProvider(
            for: dragURL,
            suggestedName: suggestedName,
            fallbackTypeIdentifier: UTType.audio.identifier,
            errorDomain: "LapianBao.MusicDragExport",
            missingFileMessage: "音频文件不存在"
        )
    }
}

func musicDownloadRowDragProvider(from jobs: [MusicDownloadJob]) -> (() -> NSItemProvider)? {
    let preferredJob = MusicDownloadJob.DownloadType.allCases.compactMap { type in
        jobs.first { job in
            job.type == type && completedMusicFileURL(for: job) != nil
        }
    }
    .first
    return musicDownloadFileDragProvider(for: preferredJob)
}

enum MusicRecognitionLayout {
    static let actionButtonSize: CGFloat = 22
    static let actionIconSize: CGFloat = 16
    static let actionGlyphSize: CGFloat = 16
    static let primaryContentHeight: CGFloat = 48
    static let inlineRowHeight: CGFloat = 76
    static let inlineDownloadButtonsWidth: CGFloat = 78
    static let inlineWaveformHeight: CGFloat = 48
}

struct MusicRecognitionActionColumn: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let song: MusicRecognitionItem

    private let actionTint = Color.white.opacity(0.72)
    private var downloadJobs: [MusicDownloadJob] {
        musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs)
    }

    private var completedDownloadJobs: [MusicDownloadJob] {
        downloadJobs.filter { completedMusicFileURL(for: $0) != nil }
    }

    private var completedFileURLs: [URL] {
        completedDownloadJobs.compactMap(completedMusicFileURL)
    }

    var body: some View {
        VStack(spacing: 4) {
            Button {
                libraryStore.prepareExternalServiceWork()
                openFirstYouTubeVideo(for: song)
            } label: {
                actionIcon("play.rectangle.fill", glyphWidth: 18, glyphHeight: 14)
            }
            .buttonStyle(.plain)
            .help("在浏览器中打开 YouTube 第一个视频")

            downloadAction
        }
        .frame(width: MusicRecognitionLayout.actionButtonSize)
        .frame(height: MusicRecognitionLayout.primaryContentHeight, alignment: .center)
    }

    @ViewBuilder
    private var downloadAction: some View {
        if completedFileURLs.isEmpty {
            Menu {
                Button {
                    libraryStore.downloadMusic(song: song, type: .original)
                } label: {
                    Label("下载原曲", systemImage: "arrow.down.circle")
                }

                Button {
                    libraryStore.downloadMusic(song: song, type: .instrumental)
                } label: {
                    Label("下载伴奏", systemImage: "arrow.down.circle")
                }
            } label: {
                actionIcon("arrow.down", glyphWidth: 14, glyphHeight: 16)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(
                width: MusicRecognitionLayout.actionButtonSize,
                height: MusicRecognitionLayout.actionButtonSize
            )
            .help("下载原曲或伴奏")
        } else {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting(completedFileURLs)
            } label: {
                actionIcon("folder", glyphWidth: 16, glyphHeight: 14)
            }
            .buttonStyle(.plain)
            .help("在访达显示已下载音乐")
            .contextMenu {
                ForEach(completedDownloadJobs) { job in
                    if let url = completedMusicFileURL(for: job) {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("显示\(job.type.label)文件", systemImage: "folder")
                        }
                    }
                }

                Divider()

                Button {
                    libraryStore.downloadMusic(song: song, type: .original)
                } label: {
                    Label("重新下载原曲", systemImage: "arrow.clockwise")
                }

                Button {
                    libraryStore.downloadMusic(song: song, type: .instrumental)
                } label: {
                    Label("重新下载伴奏", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func actionIcon(
        _ systemImage: String,
        glyphWidth: CGFloat = MusicRecognitionLayout.actionGlyphSize,
        glyphHeight: CGFloat = MusicRecognitionLayout.actionGlyphSize
    ) -> some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .font(.system(size: MusicRecognitionLayout.actionIconSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(actionTint)
            .frame(width: glyphWidth, height: glyphHeight)
            .frame(
                width: MusicRecognitionLayout.actionButtonSize,
                height: MusicRecognitionLayout.actionButtonSize
            )
            .contentShape(Rectangle())
    }
}

struct ExportMusicRecognitionActionColumn: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let song: MusicRecognitionItem
    let downloadJobs: [MusicDownloadJob]

    private var completedJobs: [MusicDownloadJob] {
        MusicDownloadJob.DownloadType.allCases.compactMap { type in
            guard let job = job(for: type), completedFileURL(for: job) != nil else { return nil }
            return job
        }
    }

    private var allDownloadsCompleted: Bool {
        MusicDownloadJob.DownloadType.allCases.allSatisfy { type in
            guard let job = job(for: type) else { return false }
            return completedFileURL(for: job) != nil
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            finderMenu
            downloadMenu
        }
        .frame(width: MusicRecognitionLayout.actionButtonSize)
        .frame(height: MusicRecognitionLayout.primaryContentHeight, alignment: .center)
    }

    private var finderMenu: some View {
        let hasCompletedDownloads = !completedJobs.isEmpty

        return Menu {
            ForEach(completedJobs) { job in
                if let url = completedFileURL(for: job) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("显示\(job.type.label)", systemImage: "folder")
                    }
                }
            }
        } label: {
            actionIcon(
                "folder",
                tint: .white.opacity(hasCompletedDownloads ? 0.72 : 0.28),
                glyphWidth: 16,
                glyphHeight: 14
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(
            width: MusicRecognitionLayout.actionButtonSize,
            height: MusicRecognitionLayout.actionButtonSize
        )
        .disabled(!hasCompletedDownloads)
        .help(hasCompletedDownloads ? "在访达显示原曲或伴奏" : "暂无已下载音乐文件")
    }

    private var downloadMenu: some View {
        Menu {
            ForEach(MusicDownloadJob.DownloadType.allCases, id: \.self) { type in
                let job = job(for: type)
                let isDownloaded = completedFileURL(for: job) != nil

                Button {
                    libraryStore.downloadMusic(song: song, type: type)
                } label: {
                    Label(isDownloaded ? "已下载\(type.label)" : "下载\(type.label)", systemImage: "arrow.down.circle")
                }
                .disabled(isDownloaded)
            }
        } label: {
            actionIcon(
                "arrow.down",
                tint: .white.opacity(allDownloadsCompleted ? 0.28 : 0.72),
                glyphWidth: 14,
                glyphHeight: 16
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(
            width: MusicRecognitionLayout.actionButtonSize,
            height: MusicRecognitionLayout.actionButtonSize
        )
        .disabled(allDownloadsCompleted)
        .help(allDownloadsCompleted ? "原曲和伴奏已下载" : "下载原曲或伴奏")
    }

    private func job(for type: MusicDownloadJob.DownloadType) -> MusicDownloadJob? {
        downloadJobs.first { $0.type == type }
    }

    private func completedFileURL(for job: MusicDownloadJob?) -> URL? {
        guard let job else { return nil }
        return libraryStore.completedMusicDownloadFileURL(for: job)
    }

    private func actionIcon(
        _ systemImage: String,
        tint: Color,
        glyphWidth: CGFloat = MusicRecognitionLayout.actionGlyphSize,
        glyphHeight: CGFloat = MusicRecognitionLayout.actionGlyphSize
    ) -> some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .font(.system(size: MusicRecognitionLayout.actionIconSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(width: glyphWidth, height: glyphHeight)
            .frame(
                width: MusicRecognitionLayout.actionButtonSize,
                height: MusicRecognitionLayout.actionButtonSize
            )
            .contentShape(Rectangle())
    }
}

struct ExportMusicRecognitionRow: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let song: MusicRecognitionItem
    let videoPath: String
    let onJump: () -> Void

    var body: some View {
        let downloadJobs = musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs)
        let rowDragProvider = musicDownloadRowDragProvider(from: downloadJobs)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 9) {
                Button(action: onJump) {
                    HStack(spacing: 9) {
                        artwork

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title.isEmpty ? "未知音乐" : song.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if !song.artist.isEmpty {
                                Text(song.artist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text("出现于 \(clockText(song.detectedAt))")
                                .font(Design.numericCaption2())
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: MusicRecognitionLayout.primaryContentHeight, alignment: .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("跳到视频中此段落")
                .frame(maxWidth: .infinity, alignment: .leading)

                ExportMusicRecognitionActionColumn(song: song, downloadJobs: downloadJobs)
            }
            .frame(height: MusicRecognitionLayout.primaryContentHeight, alignment: .center)

            MusicDownloadExtensionStack(downloadJobs: downloadJobs)
        }
        .padding(7)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .itemProviderDrag(rowDragProvider)
    }

    private var artwork: some View {
        MusicArtworkView(urlString: song.artworkURL, title: song.title, artist: song.artist)
        .frame(width: 42, height: 42)
    }
}

struct MusicRecognitionRow: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let song: MusicRecognitionItem
    let videoPath: String
    let onJump: () -> Void

    var body: some View {
        let downloadJobs = musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs)

        GeometryReader { proxy in
            let waveformWidth = proxy.size.width >= 640
                ? min(max(260, proxy.size.width * 0.44), 640)
                : 0

            HStack(alignment: .center, spacing: 9) {
                Button(action: onJump) {
                    HStack(spacing: 9) {
                        MusicArtworkView(urlString: song.artworkURL, title: song.title, artist: song.artist)
                        .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title.isEmpty ? "未知音乐" : song.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if !song.artist.isEmpty {
                                Text(song.artist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text("出现于 \(clockText(song.detectedAt))")
                                .font(Design.numericCaption2())
                                .foregroundStyle(.tertiary)
                            let musicTags = song.displayTags
                            if !musicTags.isEmpty {
                                MusicTagStrip(tags: musicTags)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("跳到视频中此段落")
                .frame(maxWidth: .infinity, alignment: .leading)

                MusicDownloadControlsAndWaveform(
                    song: song,
                    downloadJobs: downloadJobs,
                    buttonsWidth: MusicRecognitionLayout.inlineDownloadButtonsWidth,
                    buttonLayout: .vertical,
                    waveformWidth: waveformWidth,
                    waveformHeight: MusicRecognitionLayout.inlineWaveformHeight
                )

                MusicRecognitionActionColumn(song: song)
            }
            .padding(7)
            .frame(width: proxy.size.width, height: MusicRecognitionLayout.inlineRowHeight, alignment: .leading)
        }
        .frame(height: MusicRecognitionLayout.inlineRowHeight)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 0.7)
        }
    }

}

func latestMusicDownloadJobs(_ jobs: [MusicDownloadJob]) -> [MusicDownloadJob] {
    MusicDownloadJob.DownloadType.allCases.compactMap { type in
        jobs.last { $0.type == type }
    }
}

func musicDownloadJobs(for song: MusicRecognitionItem, in jobs: [MusicDownloadJob]) -> [MusicDownloadJob] {
    let songKey = "\(song.title)|\(song.artist)"
    return latestMusicDownloadJobs(jobs.filter { $0.songKey == songKey })
}

struct MusicDownloadExtensionStack: View {
    let downloadJobs: [MusicDownloadJob]

    var body: some View {
        if !downloadJobs.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(downloadJobs) { job in
                    MusicDownloadStatusView(job: job, isCompact: true)
                }
            }
            .padding(.top, 7)
        }
    }
}

enum MusicDownloadSelectorLayout {
    case horizontal
    case vertical
}

struct MusicDownloadControlsAndWaveform: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let song: MusicRecognitionItem
    let downloadJobs: [MusicDownloadJob]
    var buttonsWidth: CGFloat = 160
    var buttonLayout: MusicDownloadSelectorLayout = .horizontal
    var elementSpacing: CGFloat = 8
    var timeWidth: CGFloat = 56
    var waveformWidth: CGFloat = 360
    var waveformHeight: CGFloat = 48
    var fallbackDuration: Double = 0

    @State private var selectedType: MusicDownloadJob.DownloadType = .original
    @State private var selectedAudioTimeText: String?

    private var selectedJob: MusicDownloadJob? {
        job(for: selectedType)
    }

    private var selectedJobIsDownloaded: Bool {
        completedMusicFileURL(for: selectedJob) != nil
    }

    private var selectedLocalAssetDuration: Double {
        guard let filePath = selectedJob?.filePath else { return 0 }
        let normalizedPath = LibraryStore.normalizedLocalFilePath(filePath)
        return libraryStore.localMusicAssets.first {
            LibraryStore.normalizedLocalFilePath($0.filePath) == normalizedPath
        }?.duration ?? 0
    }

    private var selectedScannedFileDuration: Double {
        guard let filePath = selectedJob?.filePath else { return 0 }
        let normalizedPath = LibraryStore.normalizedLocalFilePath(filePath)
        return libraryStore.musicFileDurationsByPath[normalizedPath] ?? 0
    }

    private var resolvedFallbackDuration: Double {
        if selectedLocalAssetDuration.isFinite, selectedLocalAssetDuration > 0 {
            return selectedLocalAssetDuration
        }
        if selectedScannedFileDuration.isFinite, selectedScannedFileDuration > 0 {
            return selectedScannedFileDuration
        }
        if song.duration.isFinite, song.duration > 0 {
            return song.duration
        }
        return fallbackDuration.isFinite && fallbackDuration > 0 ? fallbackDuration : 0
    }

    private var controlTimeText: String {
        if let selectedAudioTimeText {
            return selectedAudioTimeText
        }
        return resolvedFallbackDuration > 0 ? clockText(resolvedFallbackDuration) : "--:--"
    }

    private var preferredType: MusicDownloadJob.DownloadType {
        if completedMusicFileURL(for: job(for: .original)) != nil { return .original }
        if completedMusicFileURL(for: job(for: .instrumental)) != nil { return .instrumental }
        if job(for: .original) != nil { return .original }
        if job(for: .instrumental) != nil { return .instrumental }
        return .original
    }

    private var selectorButtonSpacing: CGFloat {
        buttonLayout == .vertical ? MusicRowMetrics.actionButtonSpacing : 6
    }

    private var selectorButtonWidth: CGFloat {
        switch buttonLayout {
        case .horizontal:
            return max(58, (buttonsWidth - selectorButtonSpacing) / 2)
        case .vertical:
            return buttonsWidth
        }
    }

    private var selectorButtonHeight: CGFloat {
        switch buttonLayout {
        case .horizontal:
            return 30
        case .vertical:
            return max(20, (waveformHeight - selectorButtonSpacing) / 2)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: elementSpacing) {
            selectorButtons
                .frame(width: buttonsWidth, height: waveformHeight, alignment: .center)

            if waveformWidth > 0 {
                if selectedJobIsDownloaded {
                    waveformPanel
                        .frame(width: waveformWidth, height: waveformHeight)
                } else {
                    Color.clear
                        .frame(width: waveformWidth, height: waveformHeight)
                }
            } else if selectedJobIsDownloaded {
                Color.clear
                .frame(width: 0, height: 0)
            }
        }
        .frame(height: waveformHeight, alignment: .center)
        .onAppear {
            requestDownloadedMediaInfoIfNeeded()
            syncSelectionIfNeeded(force: true)
        }
        .onChange(of: downloadJobs) { _, _ in
            selectedAudioTimeText = nil
            requestDownloadedMediaInfoIfNeeded()
            syncSelectionIfNeeded(force: false)
        }
    }

    private var waveformPanel: some View {
        MusicDownloadWaveformPanel(
            job: selectedJob,
            selectedType: selectedType,
            height: waveformHeight,
            onTimeTextChange: { selectedAudioTimeText = $0 }
        )
        .overlay(alignment: .bottomTrailing) {
            Text(controlTimeText)
                .font(Design.numericCaption2(weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.trailing, 6)
                .padding(.bottom, 5)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var selectorButtons: some View {
        switch buttonLayout {
        case .horizontal:
            HStack(spacing: selectorButtonSpacing) {
                selectorButton(type: .original, job: job(for: .original))
                selectorButton(type: .instrumental, job: job(for: .instrumental))
            }
        case .vertical:
            VStack(spacing: selectorButtonSpacing) {
                selectorButton(type: .original, job: job(for: .original))
                selectorButton(type: .instrumental, job: job(for: .instrumental))
            }
        }
    }

    private func job(for type: MusicDownloadJob.DownloadType) -> MusicDownloadJob? {
        downloadJobs.first { $0.type == type }
    }

    private func syncSelectionIfNeeded(force: Bool) {
        if force || selectedJob == nil {
            let nextType = preferredType
            if selectedType != nextType {
                selectedAudioTimeText = nil
            }
            selectedType = nextType
            return
        }

        let preferredJob = job(for: preferredType)
        let selectedJobIsActive = selectedJob.map { LibraryStore.isActiveDownloadStatus($0.status) } ?? false
        if completedMusicFileURL(for: preferredJob) != nil, !selectedJobIsDownloaded, !selectedJobIsActive {
            selectedAudioTimeText = nil
            selectedType = preferredType
        }
    }

    private func requestDownloadedMediaInfoIfNeeded() {
        for job in downloadJobs where completedMusicFileURL(for: job) != nil {
            if let filePath = job.filePath {
                libraryStore.ensureMusicFileDurationIfNeeded(filePath: filePath)
            }
        }
    }

    private func selectorButton(
        type: MusicDownloadJob.DownloadType,
        job: MusicDownloadJob?
    ) -> some View {
        let isDownloaded = completedMusicFileURL(for: job) != nil
        let isActive = job.map { LibraryStore.isActiveDownloadStatus($0.status) } ?? false
        let isPreviewing = job.map { libraryStore.activeMusicPreviewJobID == $0.id } ?? false
        let textOpacity: Double = isPreviewing ? 0.94 : (isActive ? 0.82 : (isDownloaded ? 0.74 : 0.56))
        let fillOpacity: Double = isPreviewing ? 0.16 : (isActive ? 0.09 : (isDownloaded ? 0.075 : 0.045))
        let strokeOpacity: Double = isPreviewing ? 0.26 : (isActive ? 0.13 : (isDownloaded ? 0.12 : 0.07))

        return Button {
            if selectedType != type {
                selectedAudioTimeText = nil
            }
            selectedType = type

            if isDownloaded, let job {
                libraryStore.activeMusicPreviewJobID = job.id
                DispatchQueue.main.async {
                    AppEventBus.postMusicPreviewToggleRequest(id: job.id)
                }
            } else if !isActive {
                libraryStore.downloadMusic(song: song, type: type)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: musicDownloadIcon(type: type, job: job))
                    .font(.system(size: 11, weight: .semibold))
                Text(musicDownloadTitle(type: type, job: job))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundStyle(.white.opacity(textOpacity))
            .frame(width: selectorButtonWidth, height: selectorButtonHeight)
            .background(.white.opacity(fillOpacity))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(strokeOpacity), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .help(isDownloaded ? "播放/停止\(type.label)" : musicDownloadHelp(type: type, job: job))
        .contextMenu {
            if let url = completedMusicFileURL(for: job) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("显示\(type.label)文件", systemImage: "folder")
                }
            }

            Button {
                selectedType = type
                libraryStore.downloadMusic(song: song, type: type)
            } label: {
                Label("重新下载\(type.label)", systemImage: "arrow.clockwise")
            }
        }
    }
}

struct MusicDownloadWaveformPanel: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let job: MusicDownloadJob?
    let selectedType: MusicDownloadJob.DownloadType
    var height: CGFloat = 48
    var onTimeTextChange: ((String?) -> Void)? = nil

    @State private var previewPlayer: AVPlayer?
    @State private var previewTimeObserver: Any?
    @State private var previewEndObserver: NSObjectProtocol?
    @State private var previewProgress: Double = 0
    @State private var previewDuration: Double = 0
    @State private var previewScrubProgress: Double?
    @State private var loadedAudioDuration: Double = 0

    private static let placeholderSamples: [Double] = (0..<120).map { index -> Double in
        let position = Double(index)
        let primary = abs(sin(position * 0.31))
        let secondary = abs(sin(position * 1.17))
        return 0.11 + 0.24 * primary + 0.10 * secondary
    }

    private var previewFileURL: URL? {
        completedMusicFileURL(for: job)
    }

    private var canPreviewAudio: Bool {
        previewFileURL != nil
    }

    private var isPreviewing: Bool {
        previewPlayer != nil
    }

    private var hasPreviewPosition: Bool {
        previewProgress > 0 && previewProgress < 1
    }

    private var isPreviewActive: Bool {
        isPreviewing || previewScrubProgress != nil || hasPreviewPosition
    }

    private func requestWaveformIfNeeded() {
        guard let job else { return }
        if let samples = waveformSamples(for: job), !samples.isEmpty {
            return
        }
        if libraryStore.musicDownloadJobs.contains(where: { $0.id == job.id }) {
            libraryStore.ensureMusicDownloadWaveformIfNeeded(job)
        } else if let localAsset = localMusicAsset(for: job) {
            libraryStore.ensureLocalMusicWaveformIfNeeded(localAsset)
        }
    }

    private func localMusicAsset(for job: MusicDownloadJob) -> LocalMusicAsset? {
        guard let filePath = job.filePath else { return nil }
        let normalizedPath = LibraryStore.normalizedLocalFilePath(filePath)
        return libraryStore.localMusicAssets.first {
            LibraryStore.normalizedLocalFilePath($0.filePath) == normalizedPath
        }
    }

    private func waveformSamples(for job: MusicDownloadJob) -> [Double]? {
        if let samples = job.waveformSamples, !samples.isEmpty {
            return samples
        }
        guard let localAsset = localMusicAsset(for: job) else { return nil }
        return libraryStore.localMusicWaveformSamplesByPath[localAsset.filePath]
    }

    private var effectiveAudioDuration: Double {
        [loadedAudioDuration, previewDuration]
            .filter { $0.isFinite && $0 > 0 }
            .max() ?? 0
    }

    private var audioTimeText: String? {
        let duration = effectiveAudioDuration
        let progress = previewScrubProgress ?? previewProgress
        return musicPreviewTimeText(duration: duration, progress: progress, isActive: isPreviewActive)
    }

    var body: some View {
        Group {
            if let job {
                panel(for: job)
            } else {
                placeholderPanel(opacity: 0.26)
                    .help("下载\(selectedType.label)")
            }
        }
        .frame(height: height)
        .itemProviderDrag(musicDownloadFileDragProvider(for: job))
        .onAppear {
            requestWaveformIfNeeded()
            onTimeTextChange?(audioTimeText)
        }
        .onDisappear {
            stopAudioPreview()
            onTimeTextChange?(nil)
            if libraryStore.activeMusicPreviewJobID == job?.id {
                libraryStore.activeMusicPreviewJobID = nil
            }
        }
        .onChange(of: job?.id) { _, _ in
            onTimeTextChange?(nil)
            requestWaveformIfNeeded()
            stopAudioPreview()
            loadedAudioDuration = 0
        }
        .onChange(of: job?.filePath) { _, _ in
            onTimeTextChange?(nil)
            requestWaveformIfNeeded()
            stopAudioPreview()
            loadedAudioDuration = 0
        }
        .onChange(of: job?.status) { _, _ in
            if canPreviewAudio {
                requestWaveformIfNeeded()
            } else {
                onTimeTextChange?(nil)
                stopAudioPreview()
            }
        }
        .task(id: previewFileURL?.path) {
            await loadAudioDuration()
        }
        .onChange(of: audioTimeText) { _, timeText in
            onTimeTextChange?(timeText)
        }
        .onReceive(AppEventBus.musicPreviewStartedPublisher) { notification in
            let event = AppEventBus.musicPreviewStartedEvent(from: notification)
            guard
                let activeID = event.id,
                activeID != job?.id
            else { return }
            stopAudioPreview()
        }
        .onReceive(AppEventBus.musicPreviewToggleRequestPublisher) { notification in
            guard
                let targetID = AppEventBus.musicPreviewToggleRequestID(from: notification),
                targetID == job?.id,
                canPreviewAudio
            else { return }
            toggleAudioPreview()
        }
        .animation(.easeInOut(duration: 0.18), value: job?.downloadProgress)
        .animation(.easeInOut(duration: 0.22), value: job?.waveformSamples?.count ?? 0)
        .animation(.easeInOut(duration: 0.18), value: isPreviewing)
    }

    @ViewBuilder
    private func panel(for job: MusicDownloadJob) -> some View {
        switch job.status {
        case .succeeded:
            succeededPanel(for: job)
        case .importing:
            progressPanel(
                title: "正在下载\(job.type.label)",
                systemImage: "arrow.down.circle.fill",
                progress: job.downloadProgress
            )
        case .transcoding:
            progressPanel(title: "正在处理\(job.type.label)", systemImage: "waveform", progress: nil)
        case .finalizing:
            progressPanel(title: "正在整理\(job.type.label)", systemImage: "checkmark.seal.fill", progress: job.downloadProgress)
        case .paused:
            statusPanel(title: "\(job.type.label)已暂停", systemImage: "pause.circle.fill")
        case let .failed(message):
            statusPanel(
                title: message.isEmpty ? "\(job.type.label)下载失败" : message,
                systemImage: "xmark.circle.fill"
            )
        case .idle:
            placeholderPanel(opacity: 0.26)
        }
    }

    private func succeededPanel(for job: MusicDownloadJob) -> some View {
        ZStack(alignment: .leading) {
            if let samples = waveformSamples(for: job), !samples.isEmpty, !job.isPreparingWaveform {
                DownloadedMusicWaveformView(
                    samples: samples,
                    isCompact: false,
                    isActive: isPreviewActive,
                    progress: previewScrubProgress ?? previewProgress,
                    playbackDuration: effectiveAudioDuration,
                    smoothsPlaybackProgress: isPreviewing && previewScrubProgress == nil,
                    height: height,
                    onScrubChanged: { progress in
                        guard canPreviewAudio else { return }
                        previewScrubProgress = progress
                        previewProgress = progress
                    },
                    onScrubEnded: { progress in
                        guard canPreviewAudio else { return }
                        previewScrubProgress = progress
                        previewProgress = progress
                        seekAudioPreview(to: progress)
                    }
                )
            } else {
                placeholderPanel(opacity: 0.36)
            }

            if job.isPreparingWaveform {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .help(canPreviewAudio ? "预览\(job.type.label)，可拖出音频文件" : (job.filePath ?? ""))
    }

    private func placeholderPanel(opacity: Double) -> some View {
        DownloadedMusicWaveformView(
            samples: Self.placeholderSamples,
            isCompact: false,
            isActive: false,
            height: height
        )
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    private func progressPanel(title: String, systemImage: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let progress {
                    Text(progressPercentText(progress))
                        .font(Design.numericCaption2())
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)

            if let progress {
                ProgressView(value: normalizedProgressFraction(progress))
                    .controlSize(.mini)
                    .tint(.white)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 0.9)
        }
    }

    private func statusPanel(title: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 0.9)
        }
    }

    private func loadAudioDuration() async {
        guard let previewFileURL else {
            loadedAudioDuration = 0
            return
        }

        do {
            let asset = AVURLAsset(url: previewFileURL)
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            loadedAudioDuration = seconds.isFinite && seconds > 0 ? seconds : 0
        } catch {
            loadedAudioDuration = 0
        }
    }

    private func toggleAudioPreview() {
        if isPreviewing {
            stopAudioPreview(resetProgress: false)
        } else {
            startAudioPreview(at: previewProgress >= 1 ? 0 : previewProgress)
        }
    }

    private func startAudioPreview(at initialProgress: Double = 0) {
        guard let previewFileURL, let job else { return }
        let clampedProgress = min(1, max(0, initialProgress))
        stopAudioPreview()
        libraryStore.activeMusicPreviewJobID = job.id
        AppEventBus.postPausePreviewRequest()
        AppEventBus.postMusicPreviewStarted(
            id: job.id,
            type: job.type.rawValue
        )

        let item = AVPlayerItem(url: previewFileURL)
        let player = AVPlayer(playerItem: item)
        previewPlayer = player
        previewProgress = clampedProgress
        previewDuration = 0

        previewTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { time in
            let elapsed = time.seconds
            guard elapsed.isFinite else { return }
            let itemDuration = item.duration.seconds
            let duration = itemDuration.isFinite && itemDuration > 0
                ? itemDuration
                : loadedAudioDuration
            if duration.isFinite, duration > 0 {
                previewDuration = duration
                previewProgress = min(1, max(0, elapsed / duration))
            }
        }

        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            stopAudioPreview()
        }

        if clampedProgress > 0 {
            seekAudioPreview(to: clampedProgress)
        } else {
            player.play()
        }
    }

    private func stopAudioPreview(resetProgress: Bool = true) {
        if let previewTimeObserver, let previewPlayer {
            previewPlayer.removeTimeObserver(previewTimeObserver)
        }
        previewTimeObserver = nil

        previewPlayer?.pause()
        previewPlayer = nil
        if resetProgress {
            previewProgress = 0
            previewDuration = 0
        }
        previewScrubProgress = nil

        if libraryStore.activeMusicPreviewJobID == job?.id {
            libraryStore.activeMusicPreviewJobID = nil
        }

        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
            self.previewEndObserver = nil
        }
    }

    private func seekAudioPreview(to progress: Double) {
        let clampedProgress = min(1, max(0, progress))

        if previewPlayer == nil {
            startAudioPreview(at: clampedProgress)
            return
        }

        guard let player = previewPlayer, let item = player.currentItem else { return }
        previewProgress = clampedProgress

        Task { @MainActor in
            do {
                let duration = try await item.asset.load(.duration)
                let durationSeconds = duration.seconds
                guard durationSeconds.isFinite, durationSeconds > 0 else {
                    previewScrubProgress = nil
                    return
                }

                let target = CMTime(seconds: durationSeconds * clampedProgress, preferredTimescale: 600)
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    DispatchQueue.main.async {
                        previewProgress = clampedProgress
                        previewScrubProgress = nil
                        player.play()
                    }
                }
            } catch {
                previewScrubProgress = nil
            }
        }
    }
}

struct AudioClipWaveformStrip: View, Equatable {
    let samples: [Double]?
    let isActive: Bool
    var progress: Double = 0
    var playbackDuration: Double = 0
    var smoothsPlaybackProgress = false

    private static let placeholderSamples: [Double] = (0..<72).map { index in
        0.13 + 0.17 * abs(sin(Double(index) * 0.58))
    }

    private var displayedSamples: [Double] {
        guard let samples, !samples.isEmpty else { return Self.placeholderSamples }
        return samples
    }

    private var isPlaceholder: Bool {
        samples?.isEmpty != false
    }

    var body: some View {
        SmoothTimelineProgressReader(
            progress: progress,
            duration: playbackDuration,
            isPlaying: isActive && smoothsPlaybackProgress
        ) { displayedProgress in
            waveformCanvas(progress: displayedProgress)
        }
        .background(Color.black.opacity(isActive ? 0.22 : 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isActive ? .white.opacity(0.16) : .white.opacity(0.08), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
    }

    private func waveformCanvas(progress displayedProgress: Double) -> some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let values = displayedSamples
            let step = size.width / CGFloat(values.count)
            let barWidth = max(1, min(2.2, step * 0.72))
            let midY = size.height / 2
            let baseOpacity = isPlaceholder ? 0.18 : (isActive ? 0.86 : 0.48)
            let tint = Color.white
            let clampedProgress = min(1, max(0, displayedProgress))
            var basePath = Path()
            var playedPath = Path()

            for (index, sample) in values.enumerated() {
                let value = min(1, max(0.04, sample))
                let barHeight = max(2, CGFloat(value) * size.height * 0.82)
                let rect = CGRect(
                    x: CGFloat(index) * step + (step - barWidth) / 2,
                    y: midY - barHeight / 2,
                    width: barWidth,
                    height: barHeight
                )
                var path = Path()
                path.addRoundedRect(
                    in: rect,
                    cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                )
                let sampleProgress = Double(index + 1) / Double(values.count)
                let played = isActive && sampleProgress <= clampedProgress
                if played {
                    playedPath.addPath(path)
                } else {
                    basePath.addPath(path)
                }
            }

            context.fill(basePath, with: .color(tint.opacity(baseOpacity)))
            if isActive {
                context.fill(playedPath, with: .color(Color.white.opacity(0.92)))
            }

            if isActive {
                let headX = size.width * CGFloat(clampedProgress)
                var head = Path()
                head.addRoundedRect(
                    in: CGRect(x: headX - 1, y: 2, width: 2, height: size.height - 4),
                    cornerSize: CGSize(width: 1, height: 1)
                )
                context.fill(head, with: .color(Color.white.opacity(0.96)))
            }
        }
    }
}

struct MusicDownloadStatusView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let job: MusicDownloadJob
    var isCompact = false

    @State private var previewPlayer: AVPlayer?
    @State private var previewTimeObserver: Any?
    @State private var previewEndObserver: NSObjectProtocol?
    @State private var previewProgress: Double = 0
    @State private var previewDuration: Double = 0
    @State private var previewScrubProgress: Double?
    @State private var loadedAudioDuration: Double = 0

    private var previewFileURL: URL? {
        guard
            let filePath = job.filePath,
            FileManager.default.fileExists(atPath: filePath)
        else { return nil }
        return URL(fileURLWithPath: filePath)
    }

    private var canPreviewAudio: Bool {
        guard previewFileURL != nil else { return false }
        if case .succeeded = job.status { return true }
        return false
    }

    private var cleanedDisplayName: String {
        let title = job.songKey
            .split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fallbackName: String
        if case let .succeeded(filename) = job.status {
            fallbackName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        } else {
            fallbackName = job.type.label
        }

        let baseName = title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        return job.type == .instrumental ? "\(baseName)（伴奏版）" : baseName
    }

    private var cleanedSuggestedFilename: String? {
        guard let previewFileURL else { return nil }
        let stem = sanitizedMusicFilenameStem(cleanedDisplayName)
        let fileExtension = previewFileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return fileExtension.isEmpty ? stem : "\(stem).\(fileExtension)"
    }

    private var audioFileDragProvider: (() -> NSItemProvider)? {
        guard canPreviewAudio, let previewFileURL else { return nil }
        let suggestedName = cleanedSuggestedFilename ?? previewFileURL.lastPathComponent
        return {
            let dragURL = externalAudioDragFileURL(for: previewFileURL, suggestedName: suggestedName)
            return existingFileItemProvider(
                for: dragURL,
                suggestedName: suggestedName,
                fallbackTypeIdentifier: UTType.audio.identifier,
                errorDomain: "LapianBao.MusicDragExport",
                missingFileMessage: "音频文件不存在"
            )
        }
    }

    private var isPreviewing: Bool {
        previewPlayer != nil
    }

    private var hasPreviewPosition: Bool {
        previewProgress > 0 && previewProgress < 1
    }

    private var isPreviewActive: Bool {
        isPreviewing || previewScrubProgress != nil || hasPreviewPosition
    }

    private var effectiveAudioDuration: Double {
        [loadedAudioDuration, previewDuration]
            .filter { $0.isFinite && $0 > 0 }
            .max() ?? 0
    }

    private var audioTimeText: String? {
        let duration = effectiveAudioDuration
        let progress = previewScrubProgress ?? previewProgress
        return musicPreviewTimeText(duration: duration, progress: progress, isActive: isPreviewActive)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 5 : 7) {
            switch job.status {
            case .importing:
                progressHeader(text: "正在下载\(job.type.label)…", systemImage: "arrow.down.circle.fill")
                if let progress = job.downloadProgress {
                    ProgressView(value: normalizedProgressFraction(progress))
                        .controlSize(.mini)
                        .tint(.white)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }
            case .transcoding:
                progressHeader(text: "正在处理\(job.type.label)…", systemImage: "waveform")
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
            case .finalizing:
                progressHeader(text: "正在整理\(job.type.label)…", systemImage: "checkmark.seal.fill")
                if let progress = job.downloadProgress {
                    ProgressView(value: normalizedProgressFraction(progress))
                        .controlSize(.mini)
                        .tint(.white)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }
            case .paused:
                progressHeader(text: "\(job.type.label)已暂停", systemImage: "pause.circle.fill")
            case .succeeded:
                HStack(spacing: 6) {
                    Button {
                        toggleAudioPreview()
                    } label: {
                        Image(systemName: canPreviewAudio ? (isPreviewing ? "pause.circle.fill" : "play.circle.fill") : "checkmark.circle.fill")
                            .font(.system(size: isCompact ? 18 : 20, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white.opacity(canPreviewAudio ? 0.86 : 0.72))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPreviewAudio)
                    Text(cleanedDisplayName)
                        .font(isCompact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if let audioTimeText {
                        Text(audioTimeText)
                            .font(Design.numericCaption2())
                            .foregroundStyle(isPreviewActive ? .secondary : .tertiary)
                            .lineLimit(1)
                    }
                }

                if job.isPreparingWaveform {
                    GenerationProgressRow(
                        message: "正在生成波形",
                        progress: nil,
                        tint: .white,
                        systemImage: "waveform",
                        compact: true,
                        showPercent: false
                    )
                } else if let samples = job.waveformSamples, !samples.isEmpty {
                    DownloadedMusicWaveformView(
                        samples: samples,
                        isCompact: isCompact,
                        isActive: isPreviewActive,
                        progress: previewScrubProgress ?? previewProgress,
                        playbackDuration: effectiveAudioDuration,
                        smoothsPlaybackProgress: isPreviewing && previewScrubProgress == nil,
                        onScrubChanged: { progress in
                            guard canPreviewAudio else { return }
                            previewScrubProgress = progress
                            previewProgress = progress
                        },
                        onScrubEnded: { progress in
                            guard canPreviewAudio else { return }
                            previewScrubProgress = progress
                            previewProgress = progress
                            seekAudioPreview(to: progress)
                        }
                    )
                }
            case let .failed(message):
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                    Text("\(job.type.label)下载失败")
                        .font(isCompact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer(minLength: 6)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, isCompact ? 0 : 9)
        .padding(.vertical, isCompact ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(isCompact ? 0 : (isPreviewActive ? 0.075 : 0.055)))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(isCompact ? 0 : (isPreviewActive ? 0.20 : 0.06)), lineWidth: 0.8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if canPreviewAudio {
                toggleAudioPreview()
            }
        }
        .itemProviderDrag(audioFileDragProvider)
        .help(canPreviewAudio ? (isPreviewing ? "暂停\(job.type.label)预览，可拖出音频文件" : "播放\(job.type.label)预览，可拖出音频文件") : (job.filePath ?? ""))
        .onAppear {
            requestDownloadedMediaInfoIfNeeded()
        }
        .onDisappear {
            stopAudioPreview()
            if libraryStore.activeMusicPreviewJobID == job.id {
                libraryStore.activeMusicPreviewJobID = nil
            }
        }
        .onChange(of: job.filePath) { _, _ in
            stopAudioPreview()
            loadedAudioDuration = 0
            requestDownloadedMediaInfoIfNeeded()
        }
        .onChange(of: job.status) { _, _ in
            requestDownloadedMediaInfoIfNeeded()
            if !canPreviewAudio {
                stopAudioPreview()
            }
        }
        .task(id: previewFileURL?.path) {
            await loadAudioDuration()
        }
        .onReceive(AppEventBus.musicPreviewStartedPublisher) { notification in
            let event = AppEventBus.musicPreviewStartedEvent(from: notification)
            guard
                let activeID = event.id,
                activeID != job.id
            else { return }
            stopAudioPreview()
        }
        .onReceive(AppEventBus.musicPreviewToggleRequestPublisher) { notification in
            guard
                AppEventBus.musicPreviewToggleRequestID(from: notification) == job.id,
                canPreviewAudio
            else { return }
            toggleAudioPreview()
        }
        .animation(.easeInOut(duration: 0.18), value: job.downloadProgress)
        .animation(.easeInOut(duration: 0.22), value: job.waveformSamples?.count ?? 0)
        .animation(.easeInOut(duration: 0.18), value: isPreviewing)
    }

    private func progressHeader(text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
            Text(text)
                .font(isCompact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            if let progress = job.downloadProgress {
                Text(progressPercentText(progress))
                    .font(Design.numericCaption2())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func loadAudioDuration() async {
        guard let previewFileURL else {
            loadedAudioDuration = 0
            return
        }

        do {
            let asset = AVURLAsset(url: previewFileURL)
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            loadedAudioDuration = seconds.isFinite && seconds > 0 ? seconds : 0
        } catch {
            loadedAudioDuration = 0
        }
    }

    private func requestDownloadedMediaInfoIfNeeded() {
        guard completedMusicFileURL(for: job) != nil else { return }
        libraryStore.ensureMusicDownloadWaveformIfNeeded(job)
        if let filePath = job.filePath {
            libraryStore.ensureMusicFileDurationIfNeeded(filePath: filePath)
        }
    }

    private func sanitizedMusicFilenameStem(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let sanitized = name
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? job.type.label : sanitized
    }

    private func toggleAudioPreview() {
        if isPreviewing {
            stopAudioPreview(resetProgress: false)
        } else {
            startAudioPreview(at: previewProgress >= 1 ? 0 : previewProgress)
        }
    }

    private func startAudioPreview(at initialProgress: Double = 0) {
        guard let previewFileURL else { return }
        let clampedProgress = min(1, max(0, initialProgress))
        stopAudioPreview()
        libraryStore.activeMusicPreviewJobID = job.id
        AppEventBus.postPausePreviewRequest()
        AppEventBus.postMusicPreviewStarted(
            id: job.id,
            type: job.type.rawValue
        )

        let item = AVPlayerItem(url: previewFileURL)
        let player = AVPlayer(playerItem: item)
        previewPlayer = player
        previewProgress = clampedProgress
        previewDuration = 0

        previewTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { time in
            let elapsed = time.seconds
            guard elapsed.isFinite else { return }
            let itemDuration = item.duration.seconds
            let duration = itemDuration.isFinite && itemDuration > 0
                ? itemDuration
                : loadedAudioDuration
            if duration.isFinite, duration > 0 {
                previewDuration = duration
                previewProgress = min(1, max(0, elapsed / duration))
            }
        }

        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            stopAudioPreview()
        }

        if clampedProgress > 0 {
            seekAudioPreview(to: clampedProgress)
        } else {
            player.play()
        }
    }

    private func stopAudioPreview(resetProgress: Bool = true) {
        if let previewTimeObserver, let previewPlayer {
            previewPlayer.removeTimeObserver(previewTimeObserver)
        }
        previewTimeObserver = nil

        previewPlayer?.pause()
        previewPlayer = nil
        if resetProgress {
            previewProgress = 0
            previewDuration = 0
        }
        previewScrubProgress = nil

        if libraryStore.activeMusicPreviewJobID == job.id {
            libraryStore.activeMusicPreviewJobID = nil
        }

        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
            self.previewEndObserver = nil
        }
    }

    private func seekAudioPreview(to progress: Double) {
        let clampedProgress = min(1, max(0, progress))

        if previewPlayer == nil {
            startAudioPreview(at: clampedProgress)
            return
        }

        guard let player = previewPlayer, let item = player.currentItem else { return }
        previewProgress = clampedProgress

        Task { @MainActor in
            do {
                let duration = try await item.asset.load(.duration)
                let durationSeconds = duration.seconds
                guard durationSeconds.isFinite, durationSeconds > 0 else {
                    previewScrubProgress = nil
                    return
                }

                let target = CMTime(seconds: durationSeconds * clampedProgress, preferredTimescale: 600)
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    DispatchQueue.main.async {
                        previewProgress = clampedProgress
                        previewScrubProgress = nil
                        player.play()
                    }
                }
            } catch {
                previewScrubProgress = nil
            }
        }
    }
}

struct DownloadedMusicWaveformView: View {
    let samples: [Double]
    var isCompact = false
    var isActive = false
    var progress: Double = 0
    var playbackDuration: Double = 0
    var smoothsPlaybackProgress = false
    var height: CGFloat?
    var onScrubChanged: ((Double) -> Void)?
    var onScrubEnded: ((Double) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let displaySamples = preparedSamples(for: proxy.size.width)

            SmoothTimelineProgressReader(
                progress: progress,
                duration: playbackDuration,
                isPlaying: isActive && smoothsPlaybackProgress
            ) { displayedProgress in
                musicWaveformCanvas(samples: displaySamples, progress: displayedProgress)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                onScrubChanged?(scrubProgress(at: value.location.x, width: proxy.size.width))
                            }
                            .onEnded { value in
                                onScrubEnded?(scrubProgress(at: value.location.x, width: proxy.size.width))
                            }
                    )
            }
        }
        .frame(height: height ?? (isCompact ? 32 : 38))
        .background(Color.black.opacity(isActive ? 0.24 : 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(isActive ? 0.20 : 0.09), lineWidth: 1)
        }
    }

    private func musicWaveformCanvas(samples displaySamples: [Double], progress displayedProgress: Double) -> some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
            guard !displaySamples.isEmpty, size.width > 0, size.height > 0 else { return }

            let midY = size.height / 2
            let clampedProgress = min(1, max(0, displayedProgress))
            let maxHalfHeight = size.height * 0.43
            let pointCount = displaySamples.count
            let xStep = pointCount > 1 ? size.width / CGFloat(pointCount - 1) : size.width
            var upperPath = Path()
            var lowerPath = Path()
            var shapePath = Path()
            var upperPoints: [CGPoint] = []
            var lowerPoints: [CGPoint] = []

            for (index, sample) in displaySamples.enumerated() {
                let value = min(1, max(0.03, sample))
                let x = pointCount > 1 ? CGFloat(index) * xStep : size.width / 2
                let halfHeight = max(1.2, CGFloat(value) * maxHalfHeight)
                upperPoints.append(CGPoint(x: x, y: midY - halfHeight))
                lowerPoints.append(CGPoint(x: x, y: midY + halfHeight))
            }

            for (index, point) in upperPoints.enumerated() {
                if index == 0 {
                    upperPath.move(to: point)
                    shapePath.move(to: point)
                } else {
                    upperPath.addLine(to: point)
                    shapePath.addLine(to: point)
                }
            }

            for (index, point) in lowerPoints.enumerated() {
                let reversedPoint = lowerPoints[lowerPoints.count - 1 - index]
                if index == 0 {
                    lowerPath.move(to: point)
                } else {
                    lowerPath.addLine(to: point)
                }
                shapePath.addLine(to: reversedPoint)
            }
            shapePath.closeSubpath()

            var centerPath = Path()
            centerPath.move(to: CGPoint(x: 0, y: midY))
            centerPath.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(centerPath, with: .color(Color.white.opacity(0.08)), lineWidth: 1)

            let baseFillOpacity = isActive ? 0.30 : 0.22
            let baseStrokeOpacity = isActive ? 0.66 : 0.42
            context.fill(shapePath, with: .color(Color.white.opacity(baseFillOpacity)))
            context.stroke(upperPath, with: .color(Color.white.opacity(baseStrokeOpacity)), lineWidth: isCompact ? 0.9 : 1.05)
            context.stroke(lowerPath, with: .color(Color.white.opacity(baseStrokeOpacity * 0.7)), lineWidth: isCompact ? 0.8 : 0.95)

            if isActive {
                let playedWidth = size.width * CGFloat(clampedProgress)
                var playedContext = context
                playedContext.clip(to: Path(CGRect(x: 0, y: 0, width: playedWidth, height: size.height)))
                playedContext.fill(shapePath, with: .color(Color.white.opacity(0.58)))
                playedContext.stroke(upperPath, with: .color(Color.white.opacity(0.92)), lineWidth: isCompact ? 1.0 : 1.2)
                playedContext.stroke(lowerPath, with: .color(Color.white.opacity(0.72)), lineWidth: isCompact ? 0.9 : 1.05)
            }

            if isActive {
                let headX = size.width * CGFloat(clampedProgress)
                var head = Path()
                head.addRoundedRect(
                    in: CGRect(x: headX - 1, y: 2, width: 2, height: size.height - 4),
                    cornerSize: CGSize(width: 1, height: 1)
                )
                context.fill(head, with: .color(Color.white.opacity(0.96)))
            }
        }
    }

    private func preparedSamples(for width: CGFloat) -> [Double] {
        guard !samples.isEmpty else { return [] }
        let targetCount = max(24, min(samples.count, Int(max(24, width / (isCompact ? 3.2 : 2.6)))))
        let reduced: [Double]

        if samples.count <= targetCount {
            reduced = samples
        } else {
            reduced = (0..<targetCount).map { index in
                let start = Int(Double(index) * Double(samples.count) / Double(targetCount))
                let rawEnd = Int(Double(index + 1) * Double(samples.count) / Double(targetCount))
                let end = min(max(start + 1, rawEnd), samples.count)
                let slice = samples[start..<end]
                let peak = slice.max() ?? 0
                let average = slice.reduce(0, +) / Double(slice.count)
                return min(1, peak * 0.72 + average * 0.28)
            }
        }

        return contrastExpanded(reduced)
    }

    private func contrastExpanded(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }
        let high = values.max() ?? 0

        guard high > 0.015 else {
            return values.map { min(1, max(0.08, $0)) }
        }

        return values.map { value in
            let normalized = min(1, max(0, value / high))
            return 0.07 + pow(normalized, 0.78) * 0.93
        }
    }

    private func scrubProgress(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, Double(x / width)))
    }
}
