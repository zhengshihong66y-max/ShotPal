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

enum AudioFilterKind: String, CaseIterable, Hashable {
    case name = "名字"
    case tag = "标签"
}

struct AudioFilterOption: Identifiable, Hashable {
    var kind: AudioFilterKind
    var value: String

    var id: String { "\(kind.rawValue)|\(value)" }
}

enum MusicFilterKind: String, CaseIterable, Hashable {
    case title = "标题"
    case artist = "作者"
    case tag = "标签"

    var sortOrder: Int {
        switch self {
        case .title: return 0
        case .artist: return 1
        case .tag: return 2
        }
    }
}

struct MusicFilterOption: Identifiable, Hashable {
    var kind: MusicFilterKind
    var value: String

    var id: String { "\(kind.rawValue)|\(value)" }
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

func isActiveDownloadStatus(_ status: RemoteImportJob.Status) -> Bool {
    switch status {
    case .importing, .transcoding, .finalizing:
        return true
    default:
        return false
    }
}

func musicDownloadIcon(type: MusicDownloadJob.DownloadType, job: MusicDownloadJob?) -> String {
    guard let job else {
        return type == .original ? "arrow.down.circle" : "waveform"
    }
    switch job.status {
    case .succeeded:
        return type == .original ? "play.circle.fill" : "waveform.circle.fill"
    case .importing, .transcoding, .finalizing:
        return "arrow.down.circle.fill"
    case .failed:
        return "exclamationmark.circle.fill"
    case .paused:
        return "pause.circle.fill"
    case .idle:
        return type == .original ? "arrow.down.circle" : "waveform"
    }
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

enum MusicRecognitionLayout {
    static let actionButtonSize: CGFloat = 22
    static let actionIconSize: CGFloat = 16
    static let actionGlyphSize: CGFloat = 16
    static let primaryContentHeight: CGFloat = 48
}

struct MusicRecognitionActionColumn: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let song: MusicRecognitionItem

    private let actionTint = Color.white.opacity(0.72)

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

            Menu {
                Button {
                    libraryStore.downloadMusic(song: song, type: .original)
                } label: {
                    Label("下载原曲", systemImage: "arrow.down.circle")
                }

                Button {
                    libraryStore.downloadMusic(song: song, type: .instrumental)
                } label: {
                    Label("下载伴奏", systemImage: "waveform")
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
        }
        .frame(width: MusicRecognitionLayout.actionButtonSize)
        .frame(height: MusicRecognitionLayout.primaryContentHeight, alignment: .center)
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

struct ExportMusicRecognitionRow: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let song: MusicRecognitionItem
    let videoPath: String
    let onJump: () -> Void

    var body: some View {
        let downloadJobs = musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs)

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
                                .font(.caption2.monospacedDigit())
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

                MusicRecognitionActionColumn(song: song)
            }

            MusicDownloadExtensionStack(downloadJobs: downloadJobs)
        }
        .padding(7)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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

        VStack(alignment: .leading, spacing: 0) {
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
                                .font(.caption2.monospacedDigit())
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

                MusicRecognitionActionColumn(song: song)
            }
            .frame(minHeight: 56)

            MusicDownloadExtensionStack(downloadJobs: downloadJobs)
        }
        .padding(7)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 0.7)
        }
    }

}

enum MusicArtworkCache {
    static let shared: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
}

actor MusicArtworkLoadGate {
    static let shared = MusicArtworkLoadGate()

    private let limit = 6
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if activeCount < limit {
            activeCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard let nextWaiter = waiters.first else {
            activeCount = max(0, activeCount - 1)
            return
        }

        waiters.removeFirst()
        nextWaiter.resume()
    }
}

actor MusicArtworkFallbackResolver {
    static let shared = MusicArtworkFallbackResolver()

    private var cachedURLs: [String: URL?] = [:]

    func artworkURL(title rawTitle: String, artist rawArtist: String) async -> URL? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = [normalizedSearch(artist), normalizedSearch(title)].joined(separator: "|")
        guard key != "|" else { return nil }

        if cachedURLs.keys.contains(key) {
            return cachedURLs[key] ?? nil
        }

        let query = [artist, title]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else {
            cachedURLs[key] = nil
            return nil
        }

        do {
            let results = try await LibraryStore.searchAppleMusic(query: query)
            let url = bestArtworkURL(in: results, title: title, artist: artist)
            cachedURLs[key] = url
            return url
        } catch {
            cachedURLs[key] = nil
            return nil
        }
    }

    private func bestArtworkURL(
        in results: [AppleMusicSearchResult],
        title: String,
        artist: String
    ) -> URL? {
        results
            .compactMap { result -> (score: Int, url: URL)? in
                guard let url = normalizedMusicArtworkURL(result.artworkURL) else { return nil }
                return (musicArtworkMatchScore(result: result, title: title, artist: artist), url)
            }
            .sorted { lhs, rhs in lhs.score > rhs.score }
            .first?
            .url
    }

    private func musicArtworkMatchScore(
        result: AppleMusicSearchResult,
        title: String,
        artist: String
    ) -> Int {
        let targetTitle = normalizedSearch(title)
        let targetArtist = normalizedSearch(artist)
        let resultTitle = normalizedSearch(result.title)
        let resultArtist = normalizedSearch(result.artist)
        var score = 0

        if !targetTitle.isEmpty {
            if resultTitle == targetTitle {
                score += 8
            } else if !resultTitle.isEmpty,
                      resultTitle.contains(targetTitle) || targetTitle.contains(resultTitle) {
                score += 4
            }
        }

        if !targetArtist.isEmpty {
            if resultArtist == targetArtist {
                score += 6
            } else if !resultArtist.isEmpty,
                      resultArtist.contains(targetArtist) || targetArtist.contains(resultArtist) {
                score += 3
            }
        }

        return score
    }
}

struct MusicArtworkView: View {
    let urlString: String
    var title: String = ""
    var artist: String = ""
    var cornerRadius: CGFloat = 5
    var shouldLoad = true

    @State private var image: NSImage?
    @State private var didFail = false

    private var artworkURL: URL? {
        normalizedMusicArtworkURL(urlString)
    }

    private var loadKey: String {
        [urlString, title, artist, shouldLoad ? "load" : "pause"].joined(separator: "|")
    }

    private var hasPotentialArtwork: Bool {
        artworkURL != nil
            || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
                    .redacted(reason: hasPotentialArtwork && !didFail ? .placeholder : [])
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: loadKey) {
            guard shouldLoad else {
                image = nil
                didFail = false
                return
            }
            await loadArtwork()
        }
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.pink.opacity(0.86))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.pink.opacity(0.12))
    }

    private func loadArtwork() async {
        image = nil
        didFail = false

        if let artworkURL, await loadImage(from: artworkURL) {
            return
        }

        if let fallbackURL = await MusicArtworkFallbackResolver.shared.artworkURL(title: title, artist: artist),
           fallbackURL != artworkURL,
           await loadImage(from: fallbackURL) {
            return
        }

        guard !Task.isCancelled else { return }
        image = nil
        didFail = true
    }

    private func loadImage(from artworkURL: URL) async -> Bool {
        if let cached = MusicArtworkCache.shared.object(forKey: artworkURL as NSURL) {
            image = cached
            didFail = false
            return true
        }

        do {
            var request = URLRequest(url: artworkURL)
            request.timeoutInterval = 12
            request.cachePolicy = .returnCacheDataElseLoad
            request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            await MusicArtworkLoadGate.shared.acquire()
            defer {
                Task {
                    await MusicArtworkLoadGate.shared.release()
                }
            }
            guard !Task.isCancelled else { return false }

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let loadedImage = NSImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            MusicArtworkCache.shared.setObject(loadedImage, forKey: artworkURL as NSURL, cost: data.count)
            guard !Task.isCancelled else { return false }
            image = loadedImage
            didFail = false
            return true
        } catch {
            return false
        }
    }
}

nonisolated func normalizedMusicArtworkURL(_ rawURLString: String) -> URL? {
    var text = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    if text.hasPrefix("//") {
        text = "https:" + text
    } else if text.hasPrefix("http://") {
        text = "https://" + String(text.dropFirst("http://".count))
    }

    text = text.replacingOccurrences(
        of: #"(\d+)x(\d+)bb(\.[A-Za-z0-9]+)$"#,
        with: "512x512bb$3",
        options: .regularExpression
    )

    if let url = URL(string: text) {
        return url
    }

    return URL(string: text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
}

func youTubeMusicQuery(for song: MusicRecognitionItem) -> String {
    [song.artist, song.title]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

func youTubeSearchURL(for query: String) -> URL? {
    guard
        !query.isEmpty,
        var components = URLComponents(string: "https://www.youtube.com/results")
    else { return nil }
    components.queryItems = [URLQueryItem(name: "search_query", value: query)]
    return components.url
}

func openFirstYouTubeVideo(for song: MusicRecognitionItem) {
    let query = youTubeMusicQuery(for: song)
    guard !query.isEmpty else { return }

    Task {
        let firstResultURL = await LibraryStore.firstYouTubeSearchResultURL(for: query)
        guard let url = firstResultURL ?? youTubeSearchURL(for: query) else { return }
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
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

struct MusicDownloadInlineStatusStack: View {
    let downloadJobs: [MusicDownloadJob]

    var body: some View {
        if downloadJobs.isEmpty {
            Color.clear
                .frame(height: 42)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(downloadJobs) { job in
                    MusicDownloadStatusView(job: job, isCompact: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AudioWaveformScrollPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.black.opacity(0.14))
            .overlay {
                Capsule()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 0.8)
            }
            .allowsHitTesting(false)
    }
}

struct AudioClipWaveformStrip: View, Equatable {
    let samples: [Double]?
    let isActive: Bool
    var progress: Double = 0

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
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let values = displayedSamples
            let step = size.width / CGFloat(values.count)
            let barWidth = max(1, min(2.2, step * 0.72))
            let midY = size.height / 2
            let baseOpacity = isPlaceholder ? 0.18 : (isActive ? 0.86 : 0.48)
            let tint = isActive ? Color.orange : Color.white
            let clampedProgress = min(1, max(0, progress))
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
        .background(Color.black.opacity(isActive ? 0.22 : 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isActive ? Color.orange.opacity(0.22) : .white.opacity(0.08), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
    }
}

struct MusicDownloadStatusView: View {
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
            let provider = NSItemProvider()
            provider.suggestedName = suggestedName
            let typeIdentifier = UTType(filenameExtension: previewFileURL.pathExtension)?.identifier ?? UTType.audio.identifier

            provider.registerFileRepresentation(
                forTypeIdentifier: typeIdentifier,
                fileOptions: .openInPlace,
                visibility: .all
            ) { completion in
                let progress = Progress(totalUnitCount: 1)
                guard FileManager.default.fileExists(atPath: previewFileURL.path) else {
                    completion(nil, true, NSError(
                        domain: "LapianBao.MusicDragExport",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "音频文件不存在"]
                    ))
                    return progress
                }

                progress.completedUnitCount = 1
                completion(previewFileURL, true, nil)
                return progress
            }

            provider.registerObject(previewFileURL as NSURL, visibility: .all)
            return provider
        }
    }

    private var isPreviewing: Bool {
        previewPlayer != nil
    }

    private var effectiveAudioDuration: Double {
        [loadedAudioDuration, previewDuration]
            .filter { $0.isFinite && $0 > 0 }
            .max() ?? 0
    }

    private var audioTimeText: String? {
        let duration = effectiveAudioDuration
        guard duration > 0 else { return nil }

        if isPreviewing || previewScrubProgress != nil {
            let progress = min(1, max(0, previewScrubProgress ?? previewProgress))
            return clockText(duration * progress)
        }

        return clockText(duration)
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
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(isPreviewing || previewScrubProgress != nil ? .secondary : .tertiary)
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
                        isActive: isPreviewing || previewScrubProgress != nil,
                        progress: previewScrubProgress ?? previewProgress,
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
        .background(.white.opacity(isCompact ? 0 : (isPreviewing ? 0.075 : 0.055)))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(isCompact ? 0 : (isPreviewing ? 0.20 : 0.06)), lineWidth: 0.8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if canPreviewAudio {
                toggleAudioPreview()
            }
        }
        .itemProviderDrag(audioFileDragProvider)
        .help(canPreviewAudio ? (isPreviewing ? "暂停\(job.type.label)预览，可拖出音频文件" : "播放\(job.type.label)预览，可拖出音频文件") : (job.filePath ?? ""))
        .onDisappear {
            stopAudioPreview()
        }
        .onChange(of: job.filePath) { _, _ in
            stopAudioPreview()
            loadedAudioDuration = 0
        }
        .onChange(of: job.status) { _, _ in
            if !canPreviewAudio {
                stopAudioPreview()
            }
        }
        .task(id: previewFileURL?.path) {
            await loadAudioDuration()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lapianBaoMusicPreviewStarted)) { notification in
            guard
                let activeID = notification.userInfo?["id"] as? UUID,
                activeID != job.id
            else { return }
            stopAudioPreview()
        }
        .animation(.easeInOut(duration: 0.18), value: job.downloadProgress)
        .animation(.easeInOut(duration: 0.22), value: job.waveformSamples)
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
                    .font(.caption2.monospacedDigit())
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
            stopAudioPreview()
        } else {
            startAudioPreview()
        }
    }

    private func startAudioPreview(at initialProgress: Double = 0) {
        guard let previewFileURL else { return }
        let clampedProgress = min(1, max(0, initialProgress))
        stopAudioPreview()
        NotificationCenter.default.post(name: .lapianBaoPausePreviewRequest, object: nil)
        NotificationCenter.default.post(
            name: .lapianBaoMusicPreviewStarted,
            object: nil,
            userInfo: ["id": job.id, "type": job.type.rawValue]
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
            let duration = item.duration.seconds
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

    private func stopAudioPreview() {
        if let previewTimeObserver, let previewPlayer {
            previewPlayer.removeTimeObserver(previewTimeObserver)
        }
        previewTimeObserver = nil

        previewPlayer?.pause()
        previewPlayer = nil
        previewProgress = 0
        previewDuration = 0
        previewScrubProgress = nil

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
    var onScrubChanged: ((Double) -> Void)?
    var onScrubEnded: ((Double) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard !samples.isEmpty, size.width > 0, size.height > 0 else { return }

                let step = size.width / CGFloat(samples.count)
                let barWidth = max(1, min(isCompact ? 1.8 : 2.4, step * 0.72))
                let midY = size.height / 2
                let clampedProgress = min(1, max(0, progress))

                for (index, sample) in samples.enumerated() {
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
                    let sampleProgress = Double(index + 1) / Double(samples.count)
                    let played = isActive && sampleProgress <= clampedProgress
                    let opacity = played ? 0.94 : (isActive ? 0.74 : 0.56)
                    context.fill(path, with: .color(Color.white.opacity(opacity)))
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
        .frame(height: isCompact ? 32 : 38)
        .background(Color.black.opacity(isActive ? 0.24 : 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(isActive ? 0.20 : 0.09), lineWidth: 1)
        }
    }

    private func scrubProgress(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, Double(x / width)))
    }
}
