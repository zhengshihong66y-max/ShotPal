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

nonisolated enum MusicFilterKind: String, CaseIterable, Codable, Hashable, Sendable {
    case local = "本地"
    case artist = "作者"
    case tag = "类型"
}

nonisolated struct MusicFilterOption: Identifiable, Codable, Hashable, Sendable {
    static let local = MusicFilterOption(kind: .local, value: "本地")

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

nonisolated enum MusicSortOption: String, CaseIterable, Codable, Identifiable, Sendable {
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

nonisolated func completedMusicFileURL(for job: MusicDownloadJob?) -> URL? {
    guard
        let job,
        case .succeeded = job.status,
        let filePath = job.filePath
    else { return nil }
    return URL(fileURLWithPath: filePath)
}

nonisolated func musicPreviewTimeText(duration: Double, progress: Double, isActive: Bool) -> String? {
    guard duration.isFinite, duration > 0 else { return nil }
    let totalText = clockText(duration)
    guard isActive else { return totalText }
    let current = duration * min(1, max(0, progress))
    return "\(clockText(current)) / \(totalText)"
}

nonisolated func hasCompletedMusicDownload(_ jobs: [MusicDownloadJob]) -> Bool {
    jobs.contains { completedMusicFileURL(for: $0) != nil }
}

nonisolated func completedMusicFileURLs(from jobs: [MusicDownloadJob]) -> [URL] {
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

nonisolated func musicDownloadIcon(type _: MusicDownloadJob.DownloadType, job: MusicDownloadJob?) -> String {
    completedMusicFileURL(for: job) == nil ? "arrow.down.circle" : "play.circle.fill"
}

struct MusicPreviewToggleRequest: Equatable {
    let jobID: UUID
    let token = UUID()
}

nonisolated func musicDownloadTitle(type: MusicDownloadJob.DownloadType, job: MusicDownloadJob?) -> String {
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

nonisolated func musicDownloadTypeAccessibilityKey(_ type: MusicDownloadJob.DownloadType) -> String {
    switch type {
    case .original:
        return "original"
    case .instrumental:
        return "instrumental"
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
    static let circledDownloadIconOpticalOffsetX: CGFloat = -2.5
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
        musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs, recognitionID: song.id)
    }

    private var completedDownloadJobs: [MusicDownloadJob] {
        downloadJobs.filter { completedFileURL(for: $0) != nil }
    }

    private var completedFileURLs: [URL] {
        completedDownloadJobs.compactMap(completedFileURL)
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
                    libraryStore.downloadMusic(song: song, type: .original, recognitionID: song.id)
                } label: {
                    Label("下载原曲", systemImage: "arrow.down.circle")
                }

                Button {
                    libraryStore.downloadMusic(song: song, type: .instrumental, recognitionID: song.id)
                } label: {
                    Label("下载伴奏", systemImage: "arrow.down.circle")
                }
            } label: {
                actionIcon(
                    "arrow.down.circle",
                    glyphWidth: 16,
                    glyphHeight: 16
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(
                width: MusicRecognitionLayout.actionButtonSize,
                height: MusicRecognitionLayout.actionButtonSize
            )
            .offset(x: MusicRecognitionLayout.circledDownloadIconOpticalOffsetX)
        } else {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting(completedFileURLs)
            } label: {
                actionIcon("folder", glyphWidth: 16, glyphHeight: 14)
            }
            .buttonStyle(.plain)
            .contextMenu {
                ForEach(completedDownloadJobs) { job in
                    if let url = completedFileURL(for: job) {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("显示\(job.type.label)文件", systemImage: "folder")
                        }
                    }
                }

                Divider()

                Button {
                    libraryStore.downloadMusic(song: song, type: .original, recognitionID: song.id)
                } label: {
                    Label("重新下载原曲", systemImage: "arrow.clockwise")
                }

                Button {
                    libraryStore.downloadMusic(song: song, type: .instrumental, recognitionID: song.id)
                } label: {
                    Label("重新下载伴奏", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func completedFileURL(for job: MusicDownloadJob) -> URL? {
        libraryStore.completedMusicDownloadFileURL(for: job)
    }

    private func actionIcon(
        _ systemImage: String,
        glyphWidth: CGFloat = MusicRecognitionLayout.actionGlyphSize,
        glyphHeight: CGFloat = MusicRecognitionLayout.actionGlyphSize,
        opticalOffsetX: CGFloat = 0
    ) -> some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .font(.system(size: MusicRecognitionLayout.actionIconSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(actionTint)
            .frame(width: glyphWidth, height: glyphHeight)
            .offset(x: opticalOffsetX)
            .frame(
                width: MusicRecognitionLayout.actionButtonSize,
                height: MusicRecognitionLayout.actionButtonSize
            )
            .contentShape(Rectangle())
    }
}

struct ExportMusicRecognitionActionColumn: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var isDownloadOptionsPresented = false

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
    }

    private var downloadMenu: some View {
        Button {
            guard !allDownloadsCompleted else { return }
            isDownloadOptionsPresented.toggle()
        } label: {
            actionIcon(
                "arrow.down.circle",
                tint: .white.opacity(allDownloadsCompleted ? 0.28 : 0.72),
                glyphWidth: 16,
                glyphHeight: 16
            )
        }
        .buttonStyle(.plain)
        .frame(
            width: MusicRecognitionLayout.actionButtonSize,
            height: MusicRecognitionLayout.actionButtonSize
        )
        .offset(x: MusicRecognitionLayout.circledDownloadIconOpticalOffsetX)
        .accessibilityLabel(allDownloadsCompleted ? "音乐下载已完成" : "选择下载音乐")
        .accessibilityIdentifier("export_music_download_menu_button")
        .disabled(allDownloadsCompleted)
        .popover(isPresented: $isDownloadOptionsPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(MusicDownloadJob.DownloadType.allCases, id: \.self) { type in
                    downloadOptionButton(for: type)
                }
            }
            .padding(8)
            .frame(width: 154, alignment: .leading)
        }
    }

    private func downloadOptionButton(for type: MusicDownloadJob.DownloadType) -> some View {
        let job = job(for: type)
        let isDownloaded = completedFileURL(for: job) != nil
        let title = isDownloaded ? "已下载\(type.label)" : "下载\(type.label)"

        return Button {
            libraryStore.downloadMusic(song: song, type: type, recognitionID: song.id)
            isDownloadOptionsPresented = false
        } label: {
            Label(title, systemImage: "arrow.down.circle")
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isDownloaded ? Color.clear : Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel(title)
        .accessibilityIdentifier("export_music_download_\(musicDownloadTypeAccessibilityKey(type))_menu_item")
        .disabled(isDownloaded)
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
        glyphHeight: CGFloat = MusicRecognitionLayout.actionGlyphSize,
        opticalOffsetX: CGFloat = 0
    ) -> some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .font(.system(size: MusicRecognitionLayout.actionIconSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(width: glyphWidth, height: glyphHeight)
            .offset(x: opticalOffsetX)
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
        let downloadJobs = musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs, recognitionID: song.id)
        let preferredDragJob = MusicDownloadJob.DownloadType.allCases.compactMap { type in
            downloadJobs.first { job in
                job.type == type && libraryStore.completedMusicDownloadFileURL(for: job) != nil
            }
        }
        .first
        let rowDragProvider = musicDownloadFileDragProvider(for: preferredDragJob)
        let rowAccessibilityIdentifier = rowDragProvider == nil ? "export_music_row_\(song.id.uuidString)" : "export_music_drag_row_\(song.id.uuidString)"

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
                .itemProviderDrag(rowDragProvider)
                .accessibilityIdentifier(rowAccessibilityIdentifier)
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
        .accessibilityIdentifier(rowAccessibilityIdentifier)
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
        let downloadJobs = musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs, recognitionID: song.id)

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
                .frame(maxWidth: .infinity, alignment: .leading)

                MusicDownloadControlsAndWaveform(
                    song: song,
                    downloadJobs: downloadJobs,
                    recognitionID: song.id,
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

nonisolated func latestMusicDownloadJobs(_ jobs: [MusicDownloadJob]) -> [MusicDownloadJob] {
    MusicDownloadJob.DownloadType.allCases.compactMap { type in
        jobs.last { $0.type == type }
    }
}

nonisolated func musicDownloadJobs(for song: MusicRecognitionItem, in jobs: [MusicDownloadJob]) -> [MusicDownloadJob] {
    let songKey = "\(song.title)|\(song.artist)"
    return latestMusicDownloadJobs(jobs.filter { $0.songKey == songKey && $0.recognitionID == nil })
}

nonisolated func musicDownloadJobs(
    for song: MusicRecognitionItem,
    in jobs: [MusicDownloadJob],
    recognitionID: UUID
) -> [MusicDownloadJob] {
    latestMusicDownloadJobs(jobs.filter { $0.recognitionID == recognitionID })
}

struct MusicDownloadExtensionStack: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let downloadJobs: [MusicDownloadJob]

    private var visibleDownloadJobs: [MusicDownloadJob] {
        downloadJobs.filter { job in
            if case .succeeded = job.status {
                return libraryStore.completedMusicDownloadFileURL(for: job) != nil
            }
            return true
        }
    }

    var body: some View {
        if !visibleDownloadJobs.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(visibleDownloadJobs) { job in
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
    var recognitionID: UUID? = nil
    var buttonsWidth: CGFloat = 160
    var buttonLayout: MusicDownloadSelectorLayout = .horizontal
    var elementSpacing: CGFloat = 8
    var timeWidth: CGFloat = 56
    var waveformWidth: CGFloat = 360
    var waveformHeight: CGFloat = 48
    var fallbackDuration: Double = 0

    @State private var selectedType: MusicDownloadJob.DownloadType = .original
    @State private var selectedAudioTimeText: String?
    @State private var previewToggleRequest: MusicPreviewToggleRequest?

    private var selectedJob: MusicDownloadJob? {
        job(for: selectedType)
    }

    private var selectedJobIsDownloaded: Bool {
        completedFileURL(for: selectedJob) != nil
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
        if completedFileURL(for: job(for: .original)) != nil { return .original }
        if completedFileURL(for: job(for: .instrumental)) != nil { return .instrumental }
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
        HStack(alignment: .top, spacing: elementSpacing) {
            selectorButtons
                .frame(width: buttonsWidth, height: waveformHeight, alignment: .top)

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
        .frame(height: waveformHeight, alignment: .top)
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
            previewToggleRequest: previewToggleRequest,
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

    private func completedFileURL(for job: MusicDownloadJob?) -> URL? {
        guard let job else { return nil }
        return libraryStore.completedMusicDownloadFileURL(for: job)
    }

    private func displayJob(for job: MusicDownloadJob?, isDownloaded: Bool) -> MusicDownloadJob? {
        guard let job else { return nil }
        if isDownloaded { return job }
        if case .succeeded = job.status {
            return nil
        }
        return job
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
        if completedFileURL(for: preferredJob) != nil, !selectedJobIsDownloaded, !selectedJobIsActive {
            selectedAudioTimeText = nil
            selectedType = preferredType
        }
    }

    private func requestDownloadedMediaInfoIfNeeded() {
        for job in downloadJobs where completedFileURL(for: job) != nil {
            if let filePath = job.filePath {
                libraryStore.ensureMusicFileDurationIfNeeded(filePath: filePath)
            }
        }
    }

    private func selectorButton(
        type: MusicDownloadJob.DownloadType,
        job: MusicDownloadJob?
    ) -> some View {
        let isDownloaded = completedFileURL(for: job) != nil
        let isActive = job.map { LibraryStore.isActiveDownloadStatus($0.status) } ?? false
        let isPreviewing = job.map { libraryStore.activeMusicPreviewJobID == $0.id } ?? false
        let displayJob = displayJob(for: job, isDownloaded: isDownloaded)
        let textOpacity: Double = isPreviewing ? 0.94 : (isActive ? 0.82 : (isDownloaded ? 0.74 : 0.56))
        let fillOpacity: Double = isPreviewing ? 0.16 : (isActive ? 0.09 : (isDownloaded ? 0.075 : 0.045))
        let strokeOpacity: Double = isPreviewing ? 0.26 : (isActive ? 0.13 : (isDownloaded ? 0.12 : 0.07))

        return Button {
            if selectedType != type {
                selectedAudioTimeText = nil
            }
            selectedType = type

            if isDownloaded, let job {
                previewToggleRequest = MusicPreviewToggleRequest(jobID: job.id)
            } else if !isActive {
                libraryStore.downloadMusic(song: song, type: type, recognitionID: recognitionID)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isPreviewing ? "pause.circle.fill" : musicDownloadIcon(type: type, job: displayJob))
                    .font(.system(size: 11, weight: .semibold))
                Text(musicDownloadTitle(type: type, job: displayJob))
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
        .accessibilityLabel(isPreviewing ? "暂停已下载\(type.label)" : musicDownloadHelp(type: type, job: displayJob))
        .accessibilityIdentifier("music_download_\(musicDownloadTypeAccessibilityKey(type))_button")
        .contextMenu {
            if let url = completedFileURL(for: job) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("显示\(type.label)文件", systemImage: "folder")
                }
            }

            Button {
                selectedType = type
                libraryStore.downloadMusic(song: song, type: type, recognitionID: recognitionID)
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
    var previewToggleRequest: MusicPreviewToggleRequest?
    var onTimeTextChange: ((String?) -> Void)? = nil

    @State private var previewPlayer: AVPlayer?
    @State private var previewTimeObserver: Any?
    @State private var previewEndObserver: NSObjectProtocol?
    @State private var previewProgress: Double = 0
    @State private var previewDuration: Double = 0
    @State private var previewScrubProgress: Double?
    @State private var loadedAudioDuration: Double = 0
    @State private var handledPreviewToggleRequestToken: UUID?

    private static let placeholderSamples: [Double] = (0..<120).map { index -> Double in
        let position = Double(index)
        let primary = abs(sin(position * 0.31))
        let secondary = abs(sin(position * 1.17))
        return 0.11 + 0.24 * primary + 0.10 * secondary
    }

    private var previewFileURL: URL? {
        guard let job else { return nil }
        return libraryStore.completedMusicDownloadFileURL(for: job)
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
            libraryStore.clearMusicPreviewJob(job?.id)
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
        .onChange(of: libraryStore.isHydratingLocalWaveformCache) { _, isHydrating in
            if !isHydrating {
                requestWaveformIfNeeded()
            }
        }
        // 资源扫描晚于行首次出现时,资产列表就绪后补一次波形请求,
        // 否则该行会一直停在占位条(时好时坏的波形缺失)。
        .onChange(of: libraryStore.localMusicAssets.count) { _, _ in
            requestWaveformIfNeeded()
        }
        .task(id: previewToggleRequest) {
            handlePreviewToggleRequest(previewToggleRequest)
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
        }
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

    private func handlePreviewToggleRequest(_ request: MusicPreviewToggleRequest?) {
        guard
            let request,
            handledPreviewToggleRequestToken != request.token,
            request.jobID == job?.id,
            canPreviewAudio
        else { return }
        handledPreviewToggleRequestToken = request.token
        toggleAudioPreview()
    }

    private func startAudioPreview(at initialProgress: Double = 0) {
        guard let previewFileURL, let job else { return }
        let clampedProgress = min(1, max(0, initialProgress))
        stopAudioPreview()
        libraryStore.activateMusicPreviewJob(job.id)
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

        if resetProgress {
            libraryStore.clearMusicPreviewJob(job?.id)
        } else {
            libraryStore.pauseMusicPreviewJob(job?.id)
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
        libraryStore.completedMusicDownloadFileURL(for: job)
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
                    .accessibilityLabel(isPreviewing ? "暂停已下载\(job.type.label)" : "播放已下载\(job.type.label)")
                    .accessibilityIdentifier("export_music_download_status_\(musicDownloadTypeAccessibilityKey(job.type))_play_button")
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

                if let samples = waveformSamples(for: job), !samples.isEmpty {
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
                } else if job.isPreparingWaveform {
                    GenerationProgressRow(
                        message: "正在生成波形",
                        progress: nil,
                        tint: .white,
                        systemImage: "waveform",
                        compact: true,
                        showPercent: false
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
        .onAppear {
            requestDownloadedMediaInfoIfNeeded()
        }
        .onDisappear {
            stopAudioPreview()
            libraryStore.clearMusicPreviewJob(job.id)
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
        // 波形缓存水合完成或资源扫描就绪后补请求,避免行停在占位条
        .onChange(of: libraryStore.isHydratingLocalWaveformCache) { _, isHydrating in
            if !isHydrating {
                requestDownloadedMediaInfoIfNeeded()
            }
        }
        .onChange(of: libraryStore.localMusicAssets.count) { _, _ in
            requestDownloadedMediaInfoIfNeeded()
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
        guard libraryStore.completedMusicDownloadFileURL(for: job) != nil else { return }
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
        libraryStore.activateMusicPreviewJob(job.id)
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

        if resetProgress {
            libraryStore.clearMusicPreviewJob(job.id)
        } else {
            libraryStore.pauseMusicPreviewJob(job.id)
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

    @State private var cacheRenderRevision = 0

    var body: some View {
        GeometryReader { proxy in
            let renderSize = DownloadedMusicWaveformRenderCache.renderCacheSize(
                for: proxy.size,
                isCompact: isCompact
            )
            let displaySamples = DownloadedMusicWaveformRenderCache.preparedSamples(
                samples,
                for: renderSize.width,
                isCompact: isCompact
            )
            let sampleSignature = DownloadedMusicWaveformRenderCache.sampleSignature(displaySamples)
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let cacheLoadID = [
                "\(sampleSignature)",
                "\(displaySamples.count)",
                "\(Int(renderSize.width.rounded(.up)))x\(Int(renderSize.height.rounded(.up)))",
                "\(Int((scale * 100).rounded()))",
                isCompact ? "compact" : "regular",
                isActive ? "active" : "inactive"
            ].joined(separator: "|")
            let renderPrewarmKey = downloadedMusicWaveformRenderPrewarmKey(
                sampleSignature: sampleSignature,
                sampleCount: displaySamples.count,
                renderSize: renderSize,
                scale: scale,
                isCompact: isCompact
            )

            SmoothTimelineProgressReader(
                progress: progress,
                duration: playbackDuration,
                isPlaying: isActive && smoothsPlaybackProgress
            ) { displayedProgress in
                cachedMusicWaveform(
                    samples: displaySamples,
                    sampleSignature: sampleSignature,
                    displaySize: proxy.size,
                    renderSize: renderSize,
                    progress: displayedProgress
                )
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
            .task(id: cacheLoadID) {
                let didLoad = await ensureWaveformImagesCached(
                    displaySamples: displaySamples,
                    sampleSignature: sampleSignature,
                    renderSize: renderSize,
                    scale: scale,
                    isActive: isActive
                )
                guard didLoad, !Task.isCancelled else { return }
                cacheRenderRevision &+= 1
            }
            .onReceive(AppEventBus.downloadedMusicWaveformRenderCacheUpdatedPublisher) { notification in
                guard
                    AppEventBus.downloadedMusicWaveformRenderCacheKey(from: notification) == renderPrewarmKey
                else { return }
                cacheRenderRevision &+= 1
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

    @ViewBuilder
    private func cachedMusicWaveform(
        samples displaySamples: [Double],
        sampleSignature: UInt64,
        displaySize: CGSize,
        renderSize: CGSize,
        progress displayedProgress: Double
    ) -> some View {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let clampedProgress = min(1, max(0, displayedProgress))
        let cache = DownloadedMusicWaveformRenderCache.shared
        let _ = cacheRenderRevision

        let preferredBaseLayer: DownloadedMusicWaveformRenderLayer = isActive ? .activeBase : .inactiveBase
        let baseImage = cache.cachedMemoryImage(
            for: displaySamples,
            signature: sampleSignature,
            size: renderSize,
            scale: scale,
            isCompact: isCompact,
            layer: preferredBaseLayer
        ) ?? (isActive ? cache.cachedMemoryImage(
            for: displaySamples,
            signature: sampleSignature,
            size: renderSize,
            scale: scale,
            isCompact: isCompact,
            layer: .inactiveBase
        ) : nil)

        if displaySize.width > 0,
           displaySize.height > 0,
           let baseImage {
            ZStack(alignment: .leading) {
                Image(decorative: baseImage.cgImage, scale: baseImage.scale, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displaySize.width, height: displaySize.height)

                if isActive {
                    if let playedImage = cache.cachedMemoryImage(
                        for: displaySamples,
                        signature: sampleSignature,
                        size: renderSize,
                        scale: scale,
                        isCompact: isCompact,
                        layer: .activePlayed
                    ) {
                        Image(decorative: playedImage.cgImage, scale: playedImage.scale, orientation: .up)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: displaySize.width, height: displaySize.height)
                            .frame(width: displaySize.width * CGFloat(clampedProgress), alignment: .leading)
                            .clipped()
                    }

                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.white.opacity(0.96))
                        .frame(width: 2, height: max(0, displaySize.height - 4))
                        .position(
                            x: min(max(1, displaySize.width * CGFloat(clampedProgress)), max(1, displaySize.width - 1)),
                            y: displaySize.height / 2
                        )
                }
            }
        } else {
            musicWaveformCachePlaceholder()
        }
    }

    private func ensureWaveformImagesCached(
        displaySamples: [Double],
        sampleSignature: UInt64,
        renderSize: CGSize,
        scale: CGFloat,
        isActive: Bool
    ) async -> Bool {
        guard !displaySamples.isEmpty, renderSize.width > 0, renderSize.height > 0 else { return false }
        let compact = isCompact

        await Task.detached(priority: .utility) {
            let cache = DownloadedMusicWaveformRenderCache.shared
            _ = cache.image(
                for: displaySamples,
                signature: sampleSignature,
                size: renderSize,
                scale: scale,
                isCompact: compact,
                layer: isActive ? .activeBase : .inactiveBase
            )

            if isActive {
                _ = cache.image(
                    for: displaySamples,
                    signature: sampleSignature,
                    size: renderSize,
                    scale: scale,
                    isCompact: compact,
                    layer: .activePlayed
                )
            }
        }.value

        return true
    }

    private func downloadedMusicWaveformRenderPrewarmKey(
        sampleSignature: UInt64,
        sampleCount: Int,
        renderSize: CGSize,
        scale: CGFloat,
        isCompact: Bool
    ) -> String {
        let clampedScale = max(1, min(3, scale))
        let pixelWidth = max(1, Int((renderSize.width * clampedScale).rounded(.up)))
        let pixelHeight = max(1, Int((renderSize.height * clampedScale).rounded(.up)))
        return [
            "\(sampleSignature)",
            "\(sampleCount)",
            "\(pixelWidth)x\(pixelHeight)",
            "\(Int((clampedScale * 100).rounded()))",
            isCompact ? "compact" : "regular",
            "all"
        ].joined(separator: "|")
    }

    private func musicWaveformCachePlaceholder() -> some View {
        ZStack {
            Color.white.opacity(0.045)
            LinearGradient(
                colors: [
                    .white.opacity(0.02),
                    .white.opacity(0.08),
                    .white.opacity(0.02)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private func scrubProgress(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, Double(x / width)))
    }
}
