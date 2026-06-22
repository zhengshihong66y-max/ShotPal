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

nonisolated final class SceneDetectionFrameReader: @unchecked Sendable {
    private let lock = NSLock()
    private var generators: [AVAssetImageGenerator] = []
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        let result = cancelled
        lock.unlock()
        return result
    }

    func register(_ generator: AVAssetImageGenerator) -> Bool {
        lock.lock()
        if cancelled {
            lock.unlock()
            generator.cancelAllCGImageGeneration()
            return false
        }
        generators.append(generator)
        lock.unlock()
        return true
    }

    func unregister(_ generator: AVAssetImageGenerator) {
        lock.lock()
        generators.removeAll { $0 === generator }
        lock.unlock()
    }

    func cancelReading() {
        lock.lock()
        cancelled = true
        let activeGenerators = generators
        generators.removeAll()
        lock.unlock()

        activeGenerators.forEach { $0.cancelAllCGImageGeneration() }
    }
}

nonisolated enum SceneDetectionError: LocalizedError, Sendable {
    case pluginPythonMissing
    case pluginScriptMissing
    case videoMissing(String)
    case videoUnreadable(String)
    case runtimeSetupFailed(String)
    case processFailed(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .pluginPythonMissing:
            return "未检测到场景识别 Python 环境，且自动安装没有完成"
        case .pluginScriptMissing:
            return "未找到场景识别脚本：Tools/detect_scene_cuts_transnet.py"
        case .videoMissing:
            return "视频文件不存在，无法识别场景"
        case .videoUnreadable:
            return "视频文件不可读取，无法识别场景"
        case .runtimeSetupFailed(let message):
            return message.isEmpty ? "场景识别运行环境准备失败" : "场景识别运行环境准备失败：\(message)"
        case .processFailed(let message):
            return message.isEmpty ? "场景识别模型运行失败" : "场景识别模型运行失败：\(message)"
        case .invalidOutput(let message):
            return message.isEmpty ? "场景识别模型输出无效" : "场景识别模型输出无效：\(message)"
        }
    }
}

nonisolated struct SceneDetectionPlugin: Sendable {
    let pythonURL: URL
    let scriptURL: URL

    var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let binURL = pythonURL.deletingLastPathComponent()
        let envURL = binURL.deletingLastPathComponent()
        let bundledToolBinURL = scriptURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
        let toolPath = [
            bundledToolBinURL.path,
            binURL.path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ].joined(separator: ":")

        environment["VIRTUAL_ENV"] = envURL.path
        environment["PATH"] = [toolPath, environment["PATH"]]
            .compactMap { $0 }
            .joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONIOENCODING"] = "utf-8"
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment.removeValue(forKey: "PYTHONPATH")
        environment["OMP_NUM_THREADS"] = "1"
        environment["OPENBLAS_NUM_THREADS"] = "1"
        environment["MKL_NUM_THREADS"] = "1"
        environment["VECLIB_MAXIMUM_THREADS"] = "1"
        environment["NUMEXPR_NUM_THREADS"] = "1"
        return environment
    }

#if DEBUG
    private static var defaultSourceFilePath: String { #filePath }
#else
    private static var defaultSourceFilePath: String { "" }
#endif

    static func resolve(sourceFilePath: String = defaultSourceFilePath) throws -> SceneDetectionPlugin {
        let fileManager = FileManager.default
        let roots = candidateProjectRoots(sourceFilePath: sourceFilePath)
        let pythonRelativePaths = [
            "Tools/transnet-env/bin/python",
            "Tools/transnet-env/bin/python3"
        ]

        guard let scriptURL = firstToolURL(
            relativePaths: ["Tools/detect_scene_cuts_transnet.py"],
            roots: roots,
            mustBeExecutable: false,
            fileManager: fileManager
        ) else {
            throw SceneDetectionError.pluginScriptMissing
        }
        let pythonURL: URL
        if let existingPythonURL = firstToolURL(
            relativePaths: pythonRelativePaths,
            roots: roots,
            mustBeExecutable: true,
            fileManager: fileManager
        ) {
            pythonURL = existingPythonURL
        } else {
            do {
                pythonURL = try LibraryStore.ensurePythonRuntime(
                    named: "transnet-env",
                    requirementsRelativePath: "Tools/requirements-transnet.txt",
                    probeModules: ["numpy", "torch", "transnetv2_pytorch", "ffmpeg"]
                )
            } catch {
                throw SceneDetectionError.runtimeSetupFailed(error.localizedDescription)
            }
        }

        return SceneDetectionPlugin(pythonURL: pythonURL, scriptURL: scriptURL)
    }

    private static func firstToolURL(
        relativePaths: [String],
        roots: [URL],
        mustBeExecutable: Bool,
        fileManager: FileManager
    ) -> URL? {
        var checkedPaths = Set<String>()
        for root in roots {
            for relativePath in relativePaths {
                let url = root.appendingPathComponent(relativePath)
                guard checkedPaths.insert(url.path).inserted else { continue }
                if mustBeExecutable {
                    if fileManager.isExecutableFile(atPath: url.path) { return url }
                } else if fileManager.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    private static func candidateProjectRoots(sourceFilePath: String) -> [URL] {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        var candidates = [URL]()

        if let bundleResourceURL = Bundle.main.resourceURL {
            candidates.append(bundledRuntimeToolsResourceRoot(from: bundleResourceURL))
            candidates.append(contentsOf: ancestors(from: bundleResourceURL, limit: 8))
        }
        if !sourceFilePath.isEmpty {
            let sourceDirectory = URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent()
            candidates.append(contentsOf: ancestors(from: sourceDirectory, limit: 6))
        }
        candidates.append(contentsOf: ancestors(from: currentDirectory, limit: 8))

        return deduplicatedURLs(candidates)
    }

    private static func bundledRuntimeToolsResourceRoot(from bundleResourceURL: URL) -> URL {
        bundleResourceURL
            .appendingPathComponent("RuntimeTools.bundle", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
    }

    private static func ancestors(from url: URL, limit: Int) -> [URL] {
        var result = [URL]()
        var current = url
        for _ in 0..<limit {
            result.append(current)
            current.deleteLastPathComponent()
        }
        return result
    }

    private static func deduplicatedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

extension LibraryStore {
    nonisolated static let sceneDetectionProgressLinePrefix = "LAPIANBAO_PROGRESS\t"
    nonisolated static let sceneDetectionTimingLinePrefix = "LAPIANBAO_TIMING\t"

    nonisolated static func performSceneDetection(
        for url: URL,
        progressCallback: @escaping (Double) -> Void
    ) async throws -> [SceneCut] {
        await SceneDetectionGate.shared.acquire()
        defer {
            Task {
                await SceneDetectionGate.shared.release()
            }
        }

        try Task.checkCancellation()
        let processRegistry = SceneDetectionProcessRegistry()
        let reader = SceneDetectionFrameReader()

        let detectionTask = Task.detached(priority: .utility) { () throws -> [SceneCut] in
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: url.path) else {
                throw SceneDetectionError.videoMissing(url.path)
            }
            guard fileManager.isReadableFile(atPath: url.path) else {
                throw SceneDetectionError.videoUnreadable(url.path)
            }

            let asset = AVURLAsset(url: url)

            guard let duration = try? await asset.load(.duration) else {
                throw SceneDetectionError.videoUnreadable(url.path)
            }
            let totalSeconds = CMTimeGetSeconds(duration)
            guard totalSeconds.isFinite, totalSeconds > 0 else {
                throw SceneDetectionError.videoUnreadable(url.path)
            }

            let totalStartedAt = Date()
            PerformanceDiagnostics.mark("scene detection start", path: url.path)
            progressCallback(0.02)
            let transNetStartedAt = Date()
            let transNetCutTimes = try runTransNetSceneDetection(
                for: url,
                processRegistry: processRegistry,
                progressCallback: { progress in
                    progressCallback(min(0.86, max(0.02, progress)))
                }
            )
            PerformanceDiagnostics.mark(
                "scene detection transnet \(Self.elapsedSecondsText(since: transNetStartedAt)) cuts=\(transNetCutTimes.count)",
                path: url.path
            )
            try Task.checkCancellation()
            progressCallback(0.86)
            let thumbnailsStartedAt = Date()
            let cuts = await makeSceneCuts(
                for: asset,
                cutTimes: transNetCutTimes,
                reader: reader,
                progressCallback: { progress in
                    progressCallback(0.86 + Self.normalizedProgress(progress) * 0.13)
                }
            )
            PerformanceDiagnostics.mark(
                "scene detection thumbnails \(Self.elapsedSecondsText(since: thumbnailsStartedAt)) cuts=\(cuts.count)",
                path: url.path
            )
            progressCallback(1.0)
            PerformanceDiagnostics.mark(
                "scene detection total \(Self.elapsedSecondsText(since: totalStartedAt))",
                path: url.path
            )
            return cuts
        }

        return try await withTaskCancellationHandler {
            try await detectionTask.value
        } onCancel: {
            detectionTask.cancel()
            processRegistry.cancelRunningProcess()
            reader.cancelReading()
        }
    }

    nonisolated struct TransNetDetectionResult: Decodable {
        let cutTimes: [Double]

        enum CodingKeys: String, CodingKey {
            case cutTimes = "cut_times"
        }
    }

    nonisolated static func runTransNetSceneDetection(
        for url: URL,
        processRegistry: SceneDetectionProcessRegistry,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) throws -> [Double] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw SceneDetectionError.videoMissing(url.path)
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw SceneDetectionError.videoUnreadable(url.path)
        }

        progressCallback?(0.01)
        let plugin = try SceneDetectionPlugin.resolve()
        progressCallback?(0.02)
        let arguments = [
            plugin.scriptURL.path,
            url.path,
            "--threshold",
            "0.35",
            "--device",
            sceneDetectionDeviceArgument()
        ]

        let result = ExternalProcessRunner.run(
            executableURL: plugin.pythonURL,
            arguments: arguments,
            environment: plugin.environment,
            qualityOfService: .utility,
            errorLineHandler: { line in
                if let progress = sceneDetectionProgress(from: line) {
                    progressCallback?(progress)
                    return
                }
                if let timing = sceneDetectionTiming(from: line) {
                    PerformanceDiagnostics.mark(
                        "scene detection \(timing.stage) \(timing.secondsText)\(timing.detailText)",
                        path: url.path
                    )
                }
            },
            processRegistry: processRegistry
        )

        guard result.succeeded else {
            throw SceneDetectionError.processFailed(nonProgressProcessErrorText(result.errorText))
        }

        let detectionResult: TransNetDetectionResult
        do {
            detectionResult = try JSONDecoder().decode(TransNetDetectionResult.self, from: result.outputData)
        } catch {
            let output = result.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SceneDetectionError.invalidOutput(output.isEmpty ? error.localizedDescription : output)
        }

        return detectionResult.cutTimes
            .map { max(0, $0) }
            .sorted()
    }

    nonisolated static func sceneDetectionDeviceArgument() -> String {
        let environment = ProcessInfo.processInfo.environment
        let rawValue = environment["LAPIANBAO_SCENE_DEVICE"]
            ?? environment["LAPIANBAO_SCENE_DETECTION_DEVICE"]
            ?? "auto"
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["auto", "cpu", "mps", "cuda"].contains(normalized) ? normalized : "auto"
    }

    nonisolated static func sceneDetectionProgress(from line: String) -> Double? {
        guard line.hasPrefix(sceneDetectionProgressLinePrefix) else { return nil }
        let valueText = line.dropFirst(sceneDetectionProgressLinePrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(valueText), value.isFinite else { return nil }
        return normalizedProgress(value)
    }

    nonisolated struct SceneDetectionTimingLine {
        let stage: String
        let seconds: Double
        let detail: String

        var secondsText: String {
            String(format: "%.3fs", seconds)
        }

        var detailText: String {
            detail.isEmpty ? "" : " \(detail)"
        }
    }

    nonisolated static func sceneDetectionTiming(from line: String) -> SceneDetectionTimingLine? {
        guard line.hasPrefix(sceneDetectionTimingLinePrefix) else { return nil }
        let valueText = line.dropFirst(sceneDetectionTimingLinePrefix.count)
        let parts = valueText.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let seconds = Double(parts[1]),
              seconds.isFinite else { return nil }
        let detail = parts.count >= 3 ? String(parts[2]) : ""
        return SceneDetectionTimingLine(stage: String(parts[0]), seconds: seconds, detail: detail)
    }

    nonisolated static func nonProgressProcessErrorText(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter {
                sceneDetectionProgress(from: $0) == nil
                    && sceneDetectionTiming(from: $0) == nil
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func elapsedSecondsText(since startDate: Date) -> String {
        String(format: "%.3fs", max(0, Date().timeIntervalSince(startDate)))
    }

    nonisolated static func makeSceneCuts(
        for asset: AVAsset,
        cutTimes: [Double],
        reader: SceneDetectionFrameReader? = nil,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async -> [SceneCut] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 113)
        // 从切点之后取帧，保证拿到新场景的首帧而非旧场景末帧
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.06, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)
        guard reader?.register(generator) ?? true else { return [] }
        defer { reader?.unregister(generator) }

        let orderedCutTimes = stableSceneCutTimes(from: cutTimes)
        if orderedCutTimes.isEmpty {
            progressCallback?(1.0)
            return []
        }

        var cuts: [SceneCut] = []
        cuts.reserveCapacity(orderedCutTimes.count)
        var placeholderImage: NSImage?
        let targetTimes = orderedCutTimes.map {
            CMTime(seconds: max(0, $0 + 0.08), preferredTimescale: 600)
        }
        let thumbnailImages = await sceneThumbnailImages(
            from: generator,
            at: targetTimes
        )

        for (index, time) in orderedCutTimes.enumerated() {
            guard reader?.isCancelled != true else { break }
            let image = thumbnailImages[index]
            let isPlaceholder = image == nil
            if isPlaceholder, placeholderImage == nil {
                placeholderImage = scenePlaceholderImage()
            }

            cuts.append(SceneCut(
                id: sceneCutID(index: index, time: time),
                time: time,
                thumbnailImage: image ?? placeholderImage ?? scenePlaceholderImage(),
                isPlaceholder: isPlaceholder
            ))
            progressCallback?(Double(index + 1) / Double(orderedCutTimes.count))
        }

        return removeDuplicateThumbnailCuts(cuts)
    }

    nonisolated static func sceneThumbnailImages(
        from generator: AVAssetImageGenerator,
        at times: [CMTime],
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async -> [Int: NSImage] {
        guard !times.isEmpty else {
            progressCallback?(1.0)
            return [:]
        }

        let batchSize = 96
        var results: [Int: NSImage] = [:]
        results.reserveCapacity(times.count)

        var startIndex = 0
        while startIndex < times.count {
            let endIndex = min(times.count, startIndex + batchSize)
            let batchTimes = Array(times[startIndex..<endIndex])
            let batchResults = await sceneThumbnailImageBatch(from: generator, at: batchTimes)
            for (batchIndex, image) in batchResults {
                results[startIndex + batchIndex] = image
            }
            startIndex = endIndex
            progressCallback?(Double(startIndex) / Double(times.count))
        }

        return results
    }

    nonisolated static func sceneThumbnailImageBatch(
        from generator: AVAssetImageGenerator,
        at times: [CMTime]
    ) async -> [Int: NSImage] {
        guard !times.isEmpty else { return [:] }
        let requestedValues = times.map(NSValue.init(time:))
        let indexByMillisecond = Dictionary(
            uniqueKeysWithValues: times.enumerated().map { index, time in
                (Int((CMTimeGetSeconds(time) * 1000).rounded()), index)
            }
        )

        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var images: [Int: NSImage] = [:]
            var completed = 0
            var didResume = false

            func finishIfNeeded() {
                guard completed >= requestedValues.count, !didResume else { return }
                didResume = true
                continuation.resume(returning: images)
            }

            generator.generateCGImagesAsynchronously(forTimes: requestedValues) { requestedTime, image, _, result, _ in
                lock.lock()
                defer { lock.unlock() }

                if result == .succeeded, let image {
                    let key = Int((CMTimeGetSeconds(requestedTime) * 1000).rounded())
                    if let index = indexByMillisecond[key] {
                        images[index] = NSImage(
                            cgImage: image,
                            size: NSSize(width: image.width, height: image.height)
                        )
                    }
                }

                completed += 1
                finishIfNeeded()
            }
        }
    }

    nonisolated static func removeDuplicateThumbnailCuts(_ cuts: [SceneCut]) -> [SceneCut] {
        guard cuts.count > 1 else { return cuts }
        var result: [SceneCut] = [cuts[0]]
        for cut in cuts.dropFirst() {
            guard let previousCut = result.last else {
                result.append(cut)
                continue
            }
            if previousCut.isPlaceholder || cut.isPlaceholder {
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
