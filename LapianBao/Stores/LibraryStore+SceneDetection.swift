//
//  LibraryStore+SceneDetection.swift
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

extension LibraryStore {
    nonisolated static func performSceneDetection(
        for url: URL,
        progressCallback: @escaping (Double) -> Void
    ) async -> [SceneCut] {
        await SceneDetectionGate.shared.acquire()
        defer {
            Task {
                await SceneDetectionGate.shared.release()
            }
        }

        guard !Task.isCancelled else { return [] }

        let detectionTask = Task.detached(priority: .utility) { () -> [SceneCut] in
            let asset = AVURLAsset(url: url)

            guard let duration = try? await asset.load(.duration) else { return [] }
            let totalSeconds = CMTimeGetSeconds(duration)
            guard totalSeconds.isFinite, totalSeconds > 0 else { return [] }

            progressCallback(0.03)
            if let transNetCutTimes = runTransNetSceneDetection(for: url), !transNetCutTimes.isEmpty {
                progressCallback(0.82)
                let cuts = await makeSceneCuts(for: asset, cutTimes: transNetCutTimes)
                progressCallback(1.0)
                return cuts
            }

            guard
                let tracks = try? await asset.loadTracks(withMediaType: .video),
                let videoTrack = tracks.first,
                let reader = try? AVAssetReader(asset: asset)
            else { return [] }

            let frameRate = Double((try? await videoTrack.load(.nominalFrameRate)) ?? 24)
            let minimumSceneLength = max(0.12, 4.0 / max(1.0, frameRate))
            let fingerprintWidth = 48
            let fingerprintHeight = 27

            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: fingerprintWidth,
                kCVPixelBufferHeightKey as String: fingerprintHeight
            ]

            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else { return [] }
            reader.add(output)
            guard reader.startReading() else { return [] }

            var previousFingerprint: SceneFingerprint?
            var changes: [SceneChange] = []
            var lastReportedProgress = 0.03

            while reader.status == .reading {
                guard let sampleBuffer = output.copyNextSampleBuffer() else { break }

                let timestamp = CMTimeGetSeconds(sampleBuffer.presentationTimeStamp)

                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

                let fingerprint = extractSceneFingerprint(
                    from: pixelBuffer,
                    width: fingerprintWidth,
                    height: fingerprintHeight
                )

                if let previousFingerprint {
                    let score = sceneChangeScore(from: previousFingerprint, to: fingerprint)
                    changes.append(SceneChange(time: timestamp, score: score))
                }

                previousFingerprint = fingerprint

                let progress = min(1.0, timestamp / totalSeconds)
                if progress - lastReportedProgress >= 0.01 || progress >= 0.995 {
                    progressCallback(progress)
                    lastReportedProgress = progress
                }
            }

            let cutTimes = selectSceneCutTimes(from: changes, minimumSceneLength: minimumSceneLength)
            guard !cutTimes.isEmpty else { return [] }

            return await makeSceneCuts(for: asset, cutTimes: cutTimes)
        }
        return await detectionTask.value
    }

    nonisolated struct TransNetDetectionResult: Decodable {
        let cutTimes: [Double]

        enum CodingKeys: String, CodingKey {
            case cutTimes = "cut_times"
        }
    }

    nonisolated static func runTransNetSceneDetection(for url: URL) -> [Double]? {
        let fileManager = FileManager.default
        guard
            fileManager.isExecutableFile(atPath: transNetPythonPath),
            fileManager.fileExists(atPath: transNetScriptPath)
        else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: transNetPythonPath)
        process.qualityOfService = .utility
        process.arguments = [
            transNetScriptPath,
            url.path,
            "--threshold",
            "0.35",
            "--device",
            "cpu"
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["OMP_NUM_THREADS"] = "1"
        environment["OPENBLAS_NUM_THREADS"] = "1"
        environment["MKL_NUM_THREADS"] = "1"
        environment["VECLIB_MAXIMUM_THREADS"] = "1"
        environment["NUMEXPR_NUM_THREADS"] = "1"
        process.environment = environment

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
            SceneDetectionProcessRegistry.shared.set(process)
            process.waitUntilExit()
            SceneDetectionProcessRegistry.shared.set(nil)
        } catch {
            SceneDetectionProcessRegistry.shared.set(nil)
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        guard process.terminationStatus == 0 else { return nil }

        guard
            let result = try? JSONDecoder().decode(TransNetDetectionResult.self, from: outputCollector.data),
            !result.cutTimes.isEmpty
        else { return nil }

        return result.cutTimes
            .map { max(0, $0) }
            .sorted()
    }

    nonisolated static func makeSceneCuts(for asset: AVAsset, cutTimes: [Double]) async -> [SceneCut] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 113)
        // 从切点之后取帧，保证拿到新场景的首帧而非旧场景末帧
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.06, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)

        let orderedCutTimes = stableSceneCutTimes(from: cutTimes)
        var cuts: [SceneCut] = []
        cuts.reserveCapacity(orderedCutTimes.count)

        for (index, time) in orderedCutTimes.enumerated() {
            // 切点时刻 + 80ms，确保落在新场景内
            let targetTime = CMTime(seconds: max(0, time + 0.08), preferredTimescale: 600)
            guard let image = await sceneThumbnailImage(from: generator, at: targetTime) else {
                continue
            }

            cuts.append(SceneCut(
                id: sceneCutID(index: index, time: time),
                time: time,
                thumbnailImage: image
            ))
        }

        return removeDuplicateThumbnailCuts(cuts)
    }

    nonisolated static func removeDuplicateThumbnailCuts(_ cuts: [SceneCut]) -> [SceneCut] {
        guard cuts.count > 1 else { return cuts }
        var result: [SceneCut] = [cuts[0]]
        for cut in cuts.dropFirst() {
            guard let previousCut = result.last else {
                result.append(cut)
                continue
            }
            if !thumbnailsAreSimilar(previousCut.thumbnailImage, cut.thumbnailImage) {
                result.append(cut)
            }
        }
        return result
    }

    nonisolated static func thumbnailsAreSimilar(_ a: NSImage, _ b: NSImage) -> Bool {
        let compareSize = CGSize(width: 16, height: 9)
        guard let lumaA = imageLuma(a, size: compareSize),
              let lumaB = imageLuma(b, size: compareSize) else { return false }
        let diff = zip(lumaA, lumaB).reduce(0.0) { $0 + abs($1.0 - $1.1) } / Double(lumaA.count)
        return diff < 0.03
    }

    nonisolated static func imageLuma(_ image: NSImage, size: CGSize) -> [Double]? {
        let w = Int(size.width), h = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        guard let data = context.data else { return nil }
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        return (0..<w * h).map { i in
            let r = Double(ptr[i * 4]) / 255.0
            let g = Double(ptr[i * 4 + 1]) / 255.0
            let b = Double(ptr[i * 4 + 2]) / 255.0
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
    }

    nonisolated static func sceneCuts(from cutTimes: [Double], for url: URL) async -> [SceneCut] {
        let asset = AVURLAsset(url: url)
        return await makeSceneCuts(for: asset, cutTimes: cutTimes)
    }

    nonisolated static func fnv1a64(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    nonisolated static func normalizedSceneCutProgresses(from cutTimes: [Double], duration: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        return cutTimes.map { min(1, max(0, $0 / duration)) }
    }

    struct SceneFingerprint {
        let luma: [Double]
        let histogram: [Double]
        let edges: [Double]
        let contrast: Double
    }

    struct SceneChange {
        let time: Double
        let score: Double
    }

    nonisolated static func extractSceneFingerprint(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> SceneFingerprint {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return SceneFingerprint(
                luma: [Double](repeating: 0, count: width * height),
                histogram: [Double](repeating: 0, count: 64),
                edges: [Double](repeating: 0, count: width * height),
                contrast: 0
            )
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)

        let pixelCount = width * height
        var luma = [Double](repeating: 0, count: width * height)
        var histogram = [Double](repeating: 0, count: 64)
        var lumaSum = 0.0

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let b = Double(pointer[offset]) / 255.0
                let g = Double(pointer[offset + 1]) / 255.0
                let r = Double(pointer[offset + 2]) / 255.0
                let value = 0.2126 * r + 0.7152 * g + 0.0722 * b
                luma[y * width + x] = value
                lumaSum += value

                let rBin = min(3, Int(r * 4))
                let gBin = min(3, Int(g * 4))
                let bBin = min(3, Int(b * 4))
                histogram[rBin * 16 + gBin * 4 + bBin] += 1
            }
        }

        let normalizer = max(1.0, Double(pixelCount))
        for index in histogram.indices {
            histogram[index] /= normalizer
        }

        let meanLuma = lumaSum / normalizer
        let contrast = luma.reduce(0.0) { $0 + abs($1 - meanLuma) } / normalizer

        let edges = extractEdges(from: luma, width: width, height: height)

        return SceneFingerprint(luma: luma, histogram: histogram, edges: edges, contrast: contrast)
    }

    nonisolated static func sceneChangeScore(from previous: SceneFingerprint, to current: SceneFingerprint) -> Double {
        let frameSize = min(previous.luma.count, current.luma.count)
        guard frameSize > 0 else { return 0 }

        var lumaDifference = 0.0
        for index in 0..<frameSize {
            lumaDifference += abs(current.luma[index] - previous.luma[index])
        }
        lumaDifference /= Double(frameSize)

        var histogramDifference = 0.0
        for index in previous.histogram.indices {
            histogramDifference += abs(current.histogram[index] - previous.histogram[index])
        }
        histogramDifference *= 0.5

        let edgeSize = min(previous.edges.count, current.edges.count)
        var edgeDifference = 0.0
        if edgeSize > 0 {
            for index in 0..<edgeSize {
                edgeDifference += abs(current.edges[index] - previous.edges[index])
            }
            edgeDifference /= Double(edgeSize)
        }

        let contrastDifference = abs(current.contrast - previous.contrast)
        return lumaDifference * 0.38 + histogramDifference * 0.32 + edgeDifference * 0.22 + contrastDifference * 0.08
    }

    nonisolated static func extractEdges(from luma: [Double], width: Int, height: Int) -> [Double] {
        guard width > 2, height > 2, luma.count == width * height else {
            return [Double](repeating: 0, count: width * height)
        }

        var edges = [Double](repeating: 0, count: width * height)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let left = luma[y * width + x - 1]
                let right = luma[y * width + x + 1]
                let top = luma[(y - 1) * width + x]
                let bottom = luma[(y + 1) * width + x]
                edges[y * width + x] = min(1.0, abs(right - left) + abs(bottom - top))
            }
        }
        return edges
    }

    nonisolated static func selectSceneCutTimes(from changes: [SceneChange], minimumSceneLength: Double) -> [Double] {
        guard !changes.isEmpty else { return [0.0] }

        let scores = changes.map(\.score).sorted()
        let medianScore = median(ofSortedValues: scores)
        let deviations = scores.map { abs($0 - medianScore) }.sorted()
        let medianDeviation = median(ofSortedValues: deviations)
        let upperQuartile = percentile(ofSortedValues: scores, percentile: 0.75)
        let threshold = max(0.08, max(medianScore + max(0.018, medianDeviation * 4.0), upperQuartile * 1.35))
        let peakWindow = 2

        var selected: [SceneChange] = []
        for index in changes.indices {
            let change = changes[index]
            guard change.score >= threshold else { continue }

            let lowerBound = max(changes.startIndex, index - peakWindow)
            let upperBound = min(changes.index(before: changes.endIndex), index + peakWindow)
            var isLocalPeak = true
            for neighborIndex in lowerBound...upperBound where neighborIndex != index {
                if changes[neighborIndex].score > change.score {
                    isLocalPeak = false
                    break
                }
            }
            guard isLocalPeak else { continue }

            if let last = selected.last, change.time - last.time < minimumSceneLength {
                if change.score > last.score {
                    selected[selected.count - 1] = change
                }
            } else {
                selected.append(change)
            }
        }

        return ([0.0] + selected.map(\.time)).sorted()
    }

    nonisolated static func median(ofSortedValues values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    nonisolated static func percentile(ofSortedValues values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let clampedPercentile = min(1, max(0, percentile))
        let position = clampedPercentile * Double(values.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        guard lowerIndex != upperIndex else { return values[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        return values[lowerIndex] * (1 - fraction) + values[upperIndex] * fraction
    }

    nonisolated static func stableSceneCutTimes(from cutTimes: [Double]) -> [Double] {
        var result: [Double] = []
        var previous: Double?

        for time in cutTimes.map({ max(0, ($0 * 1000).rounded() / 1000) }).sorted() {
            guard previous.map({ time - $0 >= 0.3 }) ?? true else { continue }
            result.append(time)
            previous = time
        }

        return result
    }

    nonisolated static func sceneCutID(index: Int, time: Double) -> String {
        let milliseconds = Int((time * 1000).rounded())
        return "scene-\(String(format: "%04d", index + 1))-\(milliseconds)"
    }

    nonisolated static func sceneThumbnailImage(from generator: AVAssetImageGenerator, at time: CMTime) async -> NSImage? {
        guard let image = await generatedCGImage(from: generator, at: time) else { return nil }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    nonisolated enum RemoteImportError: LocalizedError {
        case downloaderMissing
        case downloaderFailed(String)
        case invalidAPIEndpoint
        case invalidAPIResponse
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .downloaderMissing:
                return "下载失败：请检查网络连接，或在高级设置中配置自定义 API。"
            case let .downloaderFailed(message):
                return message.isEmpty ? "Instagram 下载失败" : message
            case .invalidAPIEndpoint:
                return "Instagram 下载 API 地址无效"
            case .invalidAPIResponse:
                return "Instagram 下载 API 返回格式不正确"
            case .downloadFailed:
                return "下载远程视频文件失败"
            }
        }
    }

    nonisolated final class RemoteFileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let destinationURL: URL
        let progressCallback: (@Sendable (Double?, String?) -> Void)?
        let lock = NSLock()
        var continuation: CheckedContinuation<URL, Error>?
        var session: URLSession?
        var lastSpeedSampleDate = Date()
        var lastSpeedSampleBytes: Int64 = 0

        init(destinationURL: URL, progressCallback: (@Sendable (Double?, String?) -> Void)?) {
            self.destinationURL = destinationURL
            self.progressCallback = progressCallback
        }

        func download(request: URLRequest) async throws -> URL {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                    lock.lock()
                    self.continuation = continuation
                    let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                    self.session = session
                    let task = session.downloadTask(with: request)
                    lock.unlock()
                    task.resume()
                }
            } onCancel: {
                cancel()
            }
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastSpeedSampleDate)
            let speed: String?
            if elapsed >= 0.45, totalBytesWritten >= lastSpeedSampleBytes {
                let bytesPerSecond = Double(totalBytesWritten - lastSpeedSampleBytes) / elapsed
                speed = Self.formatSpeed(bytesPerSecond)
                lastSpeedSampleDate = now
                lastSpeedSampleBytes = totalBytesWritten
            } else {
                speed = nil
            }
            guard totalBytesExpectedToWrite > 0 else {
                progressCallback?(nil, speed)
                return
            }
            let progress = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
            progressCallback?(progress, speed)
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            guard
                let response = downloadTask.response as? HTTPURLResponse,
                (200 ..< 300).contains(response.statusCode)
            else {
                resume(with: .failure(RemoteImportError.downloadFailed))
                return
            }

            let fileSize = ((try? FileManager.default.attributesOfItem(atPath: location.path)[.size]) as? NSNumber)?.int64Value ?? 0
            guard fileSize > 0 else {
                resume(with: .failure(RemoteImportError.downloadFailed))
                return
            }

            do {
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.moveItem(at: location, to: destinationURL)
                progressCallback?(1, nil)
                resume(with: .success(destinationURL))
            } catch {
                resume(with: .failure(error))
            }
        }

        static func formatSpeed(_ bytesPerSecond: Double) -> String? {
            guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return nil }
            return ByteCountFormatter.string(
                fromByteCount: Int64(bytesPerSecond.rounded()),
                countStyle: .file
            ) + "/s"
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            if let error {
                resume(with: .failure(error))
            }
        }

        func cancel() {
            lock.lock()
            let session = self.session
            lock.unlock()
            session?.invalidateAndCancel()
        }

        func resume(with result: Result<URL, Error>) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            let session = self.session
            self.session = nil
            lock.unlock()

            session?.finishTasksAndInvalidate()
            continuation?.resume(with: result)
        }
    }

    nonisolated struct InstagramImportAPIRequest: Encodable {
        let url: String
    }

    nonisolated struct InstagramImportAPIResponse: Decodable {
        let downloadURL: URL
        let filename: String?

        enum CodingKeys: String, CodingKey {
            case downloadURL = "download_url"
            case filename
        }
    }

}
