//
//  LibraryStore.swift
//  LapianBao
//
//  Created by 郑士泓 on 2026/5/24.
//

import AppKit
import AVFoundation
import Combine
import Foundation

struct VideoItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    var folder: String {
        url.deletingLastPathComponent().lastPathComponent
    }

    var fileExtension: String {
        url.pathExtension.uppercased()
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published var libraryURL: URL?
    @Published var videos: [VideoItem] = []
    @Published var selectedVideo: VideoItem?
    @Published var selectedTag = "全部"
    @Published var tagInput = ""
    @Published var tagsByVideoPath: [String: [String]] = [:]
    @Published var isSidebarVisible = true
    @Published var thumbnailDataByVideoPath: [String: Data] = [:]
    @Published var durationByVideoPath: [String: Double] = [:]
    @Published var waveformSamplesByVideoPath: [String: [Double]] = [:]

    private let lastLibraryPathKey = "lastLibraryPath"
    private let videoExtensions = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]
    private var waveformTasks: [String: Task<Void, Never>] = [:]

    var allTags: [String] {
        let tags = tagsByVideoPath.values.flatMap { $0 }
        return ["全部"] + Array(Set(tags)).sorted()
    }

    var filteredVideos: [VideoItem] {
        guard selectedTag != "全部" else { return videos }
        return videos.filter { tagsByVideoPath[$0.url.path, default: []].contains(selectedTag) }
    }

    func loadLastLibrary() {
        guard
            let path = UserDefaults.standard.string(forKey: lastLibraryPathKey),
            FileManager.default.fileExists(atPath: path)
        else {
            return
        }

        scanVideos(in: URL(fileURLWithPath: path))
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "打开文件夹"
        panel.prompt = "打开"

        if panel.runModal() == .OK, let url = panel.url {
            scanVideos(in: url)
        }
    }

    func scanVideos(in folder: URL) {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let urls = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

        libraryURL = folder
        UserDefaults.standard.set(folder.path, forKey: lastLibraryPathKey)

        videos = urls
            .filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            .map(VideoItem.init(url:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        selectedVideo = videos.first
        loadThumbnails(for: videos)
    }

    func addTag(to video: VideoItem) {
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }

        var tags = tagsByVideoPath[video.url.path, default: []]
        if !tags.contains(tag) {
            tags.append(tag)
            tagsByVideoPath[video.url.path] = tags.sorted()
        }

        selectedTag = "全部"
        tagInput = ""
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    func loadWaveform(for video: VideoItem) {
        let path = video.url.path
        guard waveformSamplesByVideoPath[path] == nil, waveformTasks[path] == nil else { return }

        waveformTasks[path] = Task { [weak self] in
            let samples = await Self.makeWaveformSamples(for: video.url, sampleCount: 180) ?? []
            guard !Task.isCancelled else { return }

            self?.waveformSamplesByVideoPath[path] = samples
            self?.waveformTasks[path] = nil
        }
    }

    private func loadThumbnails(for videos: [VideoItem]) {
        thumbnailTasks.values.forEach { $0.cancel() }
        thumbnailTasks.removeAll()
        waveformTasks.values.forEach { $0.cancel() }
        waveformTasks.removeAll()
        thumbnailDataByVideoPath.removeAll()
        durationByVideoPath.removeAll()
        waveformSamplesByVideoPath.removeAll()

        for video in videos {
            let path = video.url.path
            thumbnailTasks[path] = Task { [weak self] in
                let metadata = await Self.makeVideoMetadata(for: video.url)
                guard !Task.isCancelled else { return }

                if let data = metadata.thumbnailData {
                    self?.thumbnailDataByVideoPath[path] = data
                }

                if let duration = metadata.duration {
                    self?.durationByVideoPath[path] = duration
                }

                self?.thumbnailTasks[path] = nil
            }
        }
    }

    nonisolated private static func makeVideoMetadata(for url: URL) async -> (thumbnailData: Data?, duration: Double?) {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            async let duration = durationSeconds(for: asset)

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360)

            var bestCandidate: (data: Data, score: Double)?
            for seconds in [1.0, 2.0, 3.0, 5.0, 8.0, 13.0, 0.5, 0.1, 0.0] {
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                guard let candidate = await thumbnailCandidate(from: generator, at: time) else { continue }

                if candidate.score > (bestCandidate?.score ?? -1) {
                    bestCandidate = candidate
                }

                if candidate.score > 0.18 {
                    return (candidate.data, await duration)
                }
            }

            return (bestCandidate?.data, await duration)
        }.value
    }

    nonisolated private static func durationSeconds(for asset: AVURLAsset) async -> Double? {
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    nonisolated private static func thumbnailCandidate(
        from generator: AVAssetImageGenerator,
        at time: CMTime
    ) async -> (data: Data, score: Double)? {
        await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, _ in
                guard result == .succeeded, let image else {
                    continuation.resume(returning: nil)
                    return
                }

                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: (data, imageContentScore(image)))
            }
        }
    }

    nonisolated private static func imageContentScore(_ image: CGImage) -> Double {
        let width = 24
        let height = 24
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        return pixels.withUnsafeMutableBytes { rawBuffer in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return 0
            }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            var total = 0.0
            var totalSquared = 0.0
            var brightPixels = 0
            let count = width * height
            let byteCount = bytesPerRow * height

            for offset in stride(from: 0, to: byteCount, by: 4) {
                let r = Double(rawBuffer[offset]) / 255.0
                let g = Double(rawBuffer[offset + 1]) / 255.0
                let b = Double(rawBuffer[offset + 2]) / 255.0
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                total += luma
                totalSquared += luma * luma

                if luma > 0.12 {
                    brightPixels += 1
                }
            }

            let average = total / Double(count)
            let variance = max(0, totalSquared / Double(count) - average * average)
            let visibleRatio = Double(brightPixels) / Double(count)
            return average * 0.48 + sqrt(variance) * 0.32 + visibleRatio * 0.20
        }
    }

    nonisolated private static func makeWaveformSamples(for url: URL, sampleCount: Int) async -> [Double]? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            guard
                let tracks = try? await asset.loadTracks(withMediaType: .audio),
                let track = tracks.first,
                let reader = try? AVAssetReader(asset: asset)
            else {
                return nil
            }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsBigEndianKey: false
            ]

            let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            guard reader.startReading() else { return nil }

            var peaks: [Double] = []
            var currentPeak = 0.0
            var samplesInWindow = 0
            let windowSize = 2048

            while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
                let byteCount = CMBlockBufferGetDataLength(blockBuffer)
                guard byteCount > 0 else { continue }

                var data = Data(count: byteCount)
                let copyResult = data.withUnsafeMutableBytes { buffer -> OSStatus in
                    guard let destination = buffer.baseAddress else { return -1 }
                    return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: byteCount, destination: destination)
                }

                guard copyResult == noErr else { continue }

                data.withUnsafeBytes { rawBuffer in
                    let floatSamples = rawBuffer.bindMemory(to: Float32.self)
                    for sample in floatSamples {
                        currentPeak = max(currentPeak, min(1, Double(abs(sample))))
                        samplesInWindow += 1

                        if samplesInWindow >= windowSize {
                            peaks.append(currentPeak)
                            currentPeak = 0
                            samplesInWindow = 0
                        }
                    }
                }
            }

            if samplesInWindow > 0 {
                peaks.append(currentPeak)
            }

            guard !peaks.isEmpty else { return nil }
            return downsample(peaks, to: sampleCount)
        }.value
    }

    nonisolated private static func downsample(_ peaks: [Double], to sampleCount: Int) -> [Double] {
        guard sampleCount > 0 else { return [] }

        let maxPeak = max(peaks.max() ?? 0, 0.0001)
        return (0..<sampleCount).map { index in
            let start = Int(Double(index) * Double(peaks.count) / Double(sampleCount))
            let rawEnd = Int(Double(index + 1) * Double(peaks.count) / Double(sampleCount))
            let end = min(max(start + 1, rawEnd), peaks.count)
            let value = peaks[start..<end].max() ?? 0
            return sqrt(min(1, value / maxPeak))
        }
    }
}
