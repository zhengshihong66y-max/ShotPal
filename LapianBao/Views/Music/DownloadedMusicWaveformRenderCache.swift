//
//  DownloadedMusicWaveformRenderCache.swift
//  LapianBao
//
//  Static bitmap cache for downloaded music waveform drawing.
//

import AppKit
import Foundation
import ImageIO

nonisolated enum DownloadedMusicWaveformRenderLayer: String {
    case inactiveBase
    case activeBase
    case activePlayed
}

nonisolated struct DownloadedMusicWaveformDiskPrewarmSummary: Sendable {
    var requested = 0
    var skippedExisting = 0
    var rendered = 0
    var failed = 0
}

nonisolated struct DownloadedMusicWaveformRenderPrewarmRequest: Sendable {
    let displaySamples: [Double]
    let signature: UInt64
    let renderSize: CGSize
    let scale: CGFloat
    let isCompact: Bool
    let includesActiveLayers: Bool
    let key: String

    init?(
        samples rawSamples: [Double],
        size: CGSize,
        scale: CGFloat,
        isCompact: Bool,
        includesActiveLayers: Bool = true
    ) {
        guard !rawSamples.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let renderSize = DownloadedMusicWaveformRenderCache.renderCacheSize(
            for: size,
            isCompact: isCompact
        )
        let displaySamples = DownloadedMusicWaveformRenderCache.preparedSamples(
            rawSamples,
            for: renderSize.width,
            isCompact: isCompact
        )
        guard !displaySamples.isEmpty else { return nil }

        let clampedScale = max(1, min(3, scale))
        let signature = DownloadedMusicWaveformRenderCache.sampleSignature(displaySamples)
        let pixelWidth = max(1, Int((renderSize.width * clampedScale).rounded(.up)))
        let pixelHeight = max(1, Int((renderSize.height * clampedScale).rounded(.up)))
        self.displaySamples = displaySamples
        self.signature = signature
        self.renderSize = renderSize
        self.scale = clampedScale
        self.isCompact = isCompact
        self.includesActiveLayers = includesActiveLayers
        key = [
            "\(signature)",
            "\(displaySamples.count)",
            "\(pixelWidth)x\(pixelHeight)",
            "\(Int((clampedScale * 100).rounded()))",
            isCompact ? "compact" : "regular",
            includesActiveLayers ? "all" : "base"
        ].joined(separator: "|")
    }
}

actor DownloadedMusicWaveformRenderPrewarmQueue {
    static let shared = DownloadedMusicWaveformRenderPrewarmQueue()

    private var queuedRequests: [DownloadedMusicWaveformRenderPrewarmRequest] = []
    private var activeKeys = Set<String>()
    private var waitersByKey: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var isProcessing = false

    func enqueue(_ requests: [DownloadedMusicWaveformRenderPrewarmRequest]) {
        _ = enqueueRequests(requests)
        startProcessingIfNeeded()
    }

    func prewarm(_ requests: [DownloadedMusicWaveformRenderPrewarmRequest]) async {
        let keys = enqueueRequests(requests)
        startProcessingIfNeeded()
        guard !keys.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for key in keys {
                group.addTask {
                    await self.waitUntilCompleted(key: key)
                }
            }
            await group.waitForAll()
        }
    }

    private func enqueueRequests(_ requests: [DownloadedMusicWaveformRenderPrewarmRequest]) -> [String] {
        var keysToWaitFor: [String] = []
        var seenKeys = Set<String>()

        for request in requests {
            guard seenKeys.insert(request.key).inserted else { continue }
            keysToWaitFor.append(request.key)

            guard !activeKeys.contains(request.key) else { continue }
            activeKeys.insert(request.key)
            queuedRequests.append(request)
        }

        return keysToWaitFor
    }

    private func startProcessingIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true
        Task(priority: .utility) {
            await processLoop()
        }
    }

    private func processLoop() async {
        while let request = dequeueRequest() {
            await Task.detached(priority: .utility) {
                DownloadedMusicWaveformRenderCache.shared.prewarm(request)
            }.value
            AppEventBus.postDownloadedMusicWaveformRenderCacheUpdated(key: request.key)
            finish(key: request.key)
            await Task.yield()
        }
        isProcessing = false
    }

    private func dequeueRequest() -> DownloadedMusicWaveformRenderPrewarmRequest? {
        guard !queuedRequests.isEmpty else { return nil }
        return queuedRequests.removeFirst()
    }

    private func waitUntilCompleted(key: String) async {
        await withCheckedContinuation { continuation in
            guard activeKeys.contains(key) else {
                continuation.resume()
                return
            }
            waitersByKey[key, default: []].append(continuation)
        }
    }

    private func finish(key: String) {
        activeKeys.remove(key)
        let waiters = waitersByKey.removeValue(forKey: key) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }
}

nonisolated private struct DownloadedMusicWaveformRenderPaths {
    let shape: CGPath
    let upper: CGPath
    let lower: CGPath
    let ticks: CGPath
    let center: CGPath
}

nonisolated final class DownloadedMusicWaveformRenderedImage {
    let cgImage: CGImage
    let scale: CGFloat
    let size: CGSize

    init(cgImage: CGImage, scale: CGFloat, size: CGSize) {
        self.cgImage = cgImage
        self.scale = scale
        self.size = size
    }
}

nonisolated final class DownloadedMusicWaveformRenderCache {
    static let shared = DownloadedMusicWaveformRenderCache()
    private static let diskCacheVersion = 3
    private static let renderWidthBuckets: [CGFloat] = [
        168, 236, 260, 320, 360, 420, 480, 560, 640, 720, 840, 960, 1120
    ]
    private static let renderHeightBuckets: [CGFloat] = [32, 38, 48, 52]

    static var defaultPrewarmDisplaySizes: [CGSize] {
        renderHeightBuckets
            .filter { $0 >= 48 }
            .flatMap { height in
                renderWidthBuckets.map { CGSize(width: $0, height: height) }
            }
    }

    static let defaultPrewarmScales: [CGFloat] = [1, 2]

    private let cache: NSCache<NSString, DownloadedMusicWaveformRenderedImage> = {
        let cache = NSCache<NSString, DownloadedMusicWaveformRenderedImage>()
        cache.countLimit = 12_288
        cache.totalCostLimit = 768 * 1024 * 1024
        return cache
    }()

    private let diskCacheDirectory: URL? = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LapianBao", isDirectory: true)
            .appendingPathComponent("WaveformRenderCache", isDirectory: true)
            .appendingPathComponent("v\(DownloadedMusicWaveformRenderCache.diskCacheVersion)", isDirectory: true)
    }()

    static func sampleSignature(_ samples: [Double]) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603

        for sample in samples {
            let quantized = UInt64(min(65_535, max(0, Int((sample * 65_535).rounded()))))
            hash ^= quantized
            hash &*= 1_099_511_628_211
        }

        return hash
    }

    static func preparedSamples(_ samples: [Double], for width: CGFloat, isCompact: Bool) -> [Double] {
        guard !samples.isEmpty else { return [] }
        let targetCount = max(32, min(samples.count, Int(max(32, width / (isCompact ? 2.6 : 2.0)))))
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
                return min(1, peak * 0.52 + average * 0.48)
            }
        }

        return contrastExpanded(reduced)
    }

    static func renderCacheSize(for displaySize: CGSize, isCompact _: Bool) -> CGSize {
        let requestedWidth = max(1, displaySize.width.rounded(.up))
        let requestedHeight = max(1, displaySize.height.rounded(.up))
        let width = renderWidthBuckets.first { $0 >= requestedWidth }
            ?? (ceil(requestedWidth / 160) * 160)
        let height = renderHeightBuckets.first { $0 >= requestedHeight }
            ?? (ceil(requestedHeight / 4) * 4)
        return CGSize(width: width, height: height)
    }

    func prewarm(
        samples: [[Double]],
        size: CGSize,
        scale: CGFloat,
        isCompact: Bool,
        includesActiveLayers: Bool = true
    ) {
        guard size.width > 0, size.height > 0 else { return }
        for rawSamples in samples where !rawSamples.isEmpty {
            guard let request = DownloadedMusicWaveformRenderPrewarmRequest(
                samples: rawSamples,
                size: size,
                scale: scale,
                isCompact: isCompact,
                includesActiveLayers: includesActiveLayers
            ) else { continue }
            prewarm(request)
        }
    }

    func prewarm(_ request: DownloadedMusicWaveformRenderPrewarmRequest) {
        _ = image(
            for: request.displaySamples,
            signature: request.signature,
            size: request.renderSize,
            scale: request.scale,
            isCompact: request.isCompact,
            layer: .inactiveBase
        )

        guard request.includesActiveLayers else { return }
        _ = image(
            for: request.displaySamples,
            signature: request.signature,
            size: request.renderSize,
            scale: request.scale,
            isCompact: request.isCompact,
            layer: .activeBase
        )
        _ = image(
            for: request.displaySamples,
            signature: request.signature,
            size: request.renderSize,
            scale: request.scale,
            isCompact: request.isCompact,
            layer: .activePlayed
        )
    }

    func ensureDiskImages(
        samples rawSamples: [Double],
        displaySize: CGSize,
        scale: CGFloat,
        isCompact: Bool,
        includesActiveLayers: Bool = true
    ) -> DownloadedMusicWaveformDiskPrewarmSummary {
        var summary = DownloadedMusicWaveformDiskPrewarmSummary()
        guard !rawSamples.isEmpty, displaySize.width > 0, displaySize.height > 0 else { return summary }

        let renderSize = Self.renderCacheSize(for: displaySize, isCompact: isCompact)
        let displaySamples = Self.preparedSamples(rawSamples, for: renderSize.width, isCompact: isCompact)
        guard !displaySamples.isEmpty else { return summary }

        let signature = Self.sampleSignature(displaySamples)
        let layers: [DownloadedMusicWaveformRenderLayer] = includesActiveLayers
            ? [.inactiveBase, .activeBase, .activePlayed]
            : [.inactiveBase]

        for layer in layers {
            summary.requested += 1
            let clampedScale = max(1, min(3, scale))
            let pixelWidth = max(1, Int((renderSize.width * clampedScale).rounded(.up)))
            let pixelHeight = max(1, Int((renderSize.height * clampedScale).rounded(.up)))
            let key = cacheKey(
                signature: signature,
                sampleCount: displaySamples.count,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                scale: clampedScale,
                isCompact: isCompact,
                layer: layer
            )

            if diskFileExists(for: key) {
                summary.skippedExisting += 1
                continue
            }

            guard let image = Self.renderImage(
                samples: displaySamples,
                size: renderSize,
                scale: clampedScale,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                isCompact: isCompact,
                layer: layer
            ) else {
                summary.failed += 1
                continue
            }

            storeDiskImage(image, for: key)
            cache.setObject(image, forKey: key, cost: pixelWidth * pixelHeight * 4)
            if diskFileExists(for: key) {
                summary.rendered += 1
            } else {
                summary.failed += 1
            }
        }

        return summary
    }

    var diskCacheURL: URL? {
        diskCacheDirectory
    }

    func removeAllImages() {
        cache.removeAllObjects()
        guard let diskCacheDirectory else { return }
        try? FileManager.default.removeItem(at: diskCacheDirectory)
    }

    func diskImageFileCount() -> Int {
        guard let diskCacheDirectory,
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: diskCacheDirectory,
                  includingPropertiesForKeys: nil
              )
        else { return 0 }
        return urls.filter { $0.pathExtension.lowercased() == "png" }.count
    }

    func image(
        for samples: [Double],
        signature: UInt64,
        size: CGSize,
        scale: CGFloat,
        isCompact: Bool,
        layer: DownloadedMusicWaveformRenderLayer
    ) -> DownloadedMusicWaveformRenderedImage? {
        guard !samples.isEmpty, size.width > 0, size.height > 0 else { return nil }

        let descriptor = imageDescriptor(
            signature: signature,
            sampleCount: samples.count,
            size: size,
            scale: scale,
            isCompact: isCompact,
            layer: layer
        )

        if let cached = cache.object(forKey: descriptor.key) {
            return cached
        }

        if let diskImage = diskImage(for: descriptor.key, scale: descriptor.scale, size: size) {
            cache.setObject(diskImage, forKey: descriptor.key, cost: descriptor.pixelWidth * descriptor.pixelHeight * 4)
            return diskImage
        }

        guard let image = Self.renderImage(
            samples: samples,
            size: size,
            scale: descriptor.scale,
            pixelWidth: descriptor.pixelWidth,
            pixelHeight: descriptor.pixelHeight,
            isCompact: isCompact,
            layer: layer
        ) else {
            return nil
        }

        cache.setObject(image, forKey: descriptor.key, cost: descriptor.pixelWidth * descriptor.pixelHeight * 4)
        storeDiskImage(image, for: descriptor.key)
        return image
    }

    func cachedMemoryImage(
        for samples: [Double],
        signature: UInt64,
        size: CGSize,
        scale: CGFloat,
        isCompact: Bool,
        layer: DownloadedMusicWaveformRenderLayer
    ) -> DownloadedMusicWaveformRenderedImage? {
        guard !samples.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let descriptor = imageDescriptor(
            signature: signature,
            sampleCount: samples.count,
            size: size,
            scale: scale,
            isCompact: isCompact,
            layer: layer
        )
        return cache.object(forKey: descriptor.key)
    }

    private func imageDescriptor(
        signature: UInt64,
        sampleCount: Int,
        size: CGSize,
        scale: CGFloat,
        isCompact: Bool,
        layer: DownloadedMusicWaveformRenderLayer
    ) -> (key: NSString, scale: CGFloat, pixelWidth: Int, pixelHeight: Int) {
        let clampedScale = max(1, min(3, scale))
        let pixelWidth = max(1, Int((size.width * clampedScale).rounded(.up)))
        let pixelHeight = max(1, Int((size.height * clampedScale).rounded(.up)))
        let key = cacheKey(
            signature: signature,
            sampleCount: sampleCount,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            scale: clampedScale,
            isCompact: isCompact,
            layer: layer
        )
        return (key, clampedScale, pixelWidth, pixelHeight)
    }

    private func cacheKey(
        signature: UInt64,
        sampleCount: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        scale: CGFloat,
        isCompact: Bool,
        layer: DownloadedMusicWaveformRenderLayer
    ) -> NSString {
        let scaleKey = Int((scale * 100).rounded())
        return "v\(Self.diskCacheVersion)|\(layer.rawValue)|\(isCompact ? 1 : 0)|\(pixelWidth)x\(pixelHeight)|\(scaleKey)|\(sampleCount)|\(signature)" as NSString
    }

    private func diskImage(
        for key: NSString,
        scale: CGFloat,
        size: CGSize
    ) -> DownloadedMusicWaveformRenderedImage? {
        guard let url = diskFileURL(for: key) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return DownloadedMusicWaveformRenderedImage(cgImage: cgImage, scale: scale, size: size)
    }

    private func storeDiskImage(_ image: DownloadedMusicWaveformRenderedImage, for key: NSString) {
        guard let url = diskFileURL(for: key) else { return }
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        guard let directory = diskCacheDirectory else { return }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return
        }

        CGImageDestinationAddImage(destination, image.cgImage, nil)
        _ = CGImageDestinationFinalize(destination)
    }

    private func diskFileURL(for key: NSString) -> URL? {
        guard let diskCacheDirectory else { return nil }
        let filename = (key as String)
            .replacingOccurrences(of: "|", with: "_")
        return diskCacheDirectory.appendingPathComponent("\(filename).png", isDirectory: false)
    }

    private func diskFileExists(for key: NSString) -> Bool {
        guard let url = diskFileURL(for: key) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func renderImage(
        samples: [Double],
        size: CGSize,
        scale: CGFloat,
        pixelWidth: Int,
        pixelHeight: Int,
        isCompact: Bool,
        layer: DownloadedMusicWaveformRenderLayer
    ) -> DownloadedMusicWaveformRenderedImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        let paths = renderPaths(samples: samples, size: size)
        draw(layer: layer, paths: paths, context: context, isCompact: isCompact)

        guard let cgImage = context.makeImage() else { return nil }
        return DownloadedMusicWaveformRenderedImage(cgImage: cgImage, scale: scale, size: size)
    }

    private static func renderPaths(samples: [Double], size: CGSize) -> DownloadedMusicWaveformRenderPaths {
        let midY = size.height / 2
        let maxHalfHeight = size.height * 0.40
        let pointCount = samples.count
        let xStep = pointCount > 1 ? size.width / CGFloat(pointCount - 1) : size.width
        var upperPoints: [CGPoint] = []
        var lowerPoints: [CGPoint] = []
        upperPoints.reserveCapacity(pointCount)
        lowerPoints.reserveCapacity(pointCount)

        for (index, sample) in samples.enumerated() {
            let value = min(1, max(0.02, sample))
            let x = pointCount > 1 ? CGFloat(index) * xStep : size.width / 2
            let halfHeight = max(1.2, CGFloat(value) * maxHalfHeight)
            upperPoints.append(CGPoint(x: x, y: midY - halfHeight))
            lowerPoints.append(CGPoint(x: x, y: midY + halfHeight))
        }

        let upperPath = CGMutablePath()
        let lowerPath = CGMutablePath()
        let shapePath = CGMutablePath()
        let tickPath = CGMutablePath()
        let centerPath = CGMutablePath()

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
            if index == 0 {
                lowerPath.move(to: point)
            } else {
                lowerPath.addLine(to: point)
            }
        }

        for point in lowerPoints.reversed() {
            shapePath.addLine(to: point)
        }

        shapePath.closeSubpath()

        let tickStride = max(1, Int(ceil(CGFloat(4) / max(xStep, 0.5))))
        for index in stride(from: 0, to: pointCount, by: tickStride) {
            tickPath.move(to: upperPoints[index])
            tickPath.addLine(to: lowerPoints[index])
        }

        centerPath.move(to: CGPoint(x: 0, y: midY))
        centerPath.addLine(to: CGPoint(x: size.width, y: midY))

        return DownloadedMusicWaveformRenderPaths(
            shape: shapePath,
            upper: upperPath,
            lower: lowerPath,
            ticks: tickPath,
            center: centerPath
        )
    }

    private static func draw(
        layer: DownloadedMusicWaveformRenderLayer,
        paths: DownloadedMusicWaveformRenderPaths,
        context: CGContext,
        isCompact: Bool
    ) {
        switch layer {
        case .inactiveBase:
            fill(paths.shape, context: context, opacity: 0.16)
            stroke(paths.center, context: context, opacity: 0.12, lineWidth: 1)
            stroke(paths.ticks, context: context, opacity: 0.30, lineWidth: isCompact ? 0.45 : 0.55)
            stroke(paths.upper, context: context, opacity: 0.86, lineWidth: isCompact ? 1.05 : 1.25)
            stroke(paths.lower, context: context, opacity: 0.72, lineWidth: isCompact ? 0.95 : 1.15)

        case .activeBase:
            fill(paths.shape, context: context, opacity: 0.18)
            stroke(paths.center, context: context, opacity: 0.12, lineWidth: 1)
            stroke(paths.ticks, context: context, opacity: 0.28, lineWidth: isCompact ? 0.45 : 0.55)
            stroke(paths.upper, context: context, opacity: 0.86, lineWidth: isCompact ? 1.05 : 1.25)
            stroke(paths.lower, context: context, opacity: 0.86 * 0.82, lineWidth: isCompact ? 0.95 : 1.15)

        case .activePlayed:
            fill(paths.shape, context: context, opacity: 0.34)
            stroke(paths.ticks, context: context, opacity: 0.46, lineWidth: isCompact ? 0.5 : 0.65)
            stroke(paths.upper, context: context, opacity: 0.96, lineWidth: isCompact ? 1.15 : 1.35)
            stroke(paths.lower, context: context, opacity: 0.84, lineWidth: isCompact ? 1.0 : 1.2)
        }
    }

    private static func fill(_ path: CGPath, context: CGContext, opacity: CGFloat) {
        context.addPath(path)
        context.setFillColor(NSColor.white.withAlphaComponent(opacity).cgColor)
        context.fillPath()
    }

    private static func stroke(_ path: CGPath, context: CGContext, opacity: CGFloat, lineWidth: CGFloat) {
        context.addPath(path)
        context.setStrokeColor(NSColor.white.withAlphaComponent(opacity).cgColor)
        context.setLineWidth(lineWidth)
        context.strokePath()
    }

    private static func contrastExpanded(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }
        let clamped = values.map { min(1, max(0, $0)) }
        let high = clamped.max() ?? 0

        guard high > 0.015 else {
            return clamped.map { min(1, max(0.08, $0)) }
        }

        let low = percentile(clamped, percentile: 0.12)
        let robustHigh = max(percentile(clamped, percentile: 0.92), low + 0.0001)
        let range = robustHigh - low

        guard range > 0.0001 else {
            return clamped.map { value in
                let normalized = min(1, max(0, value / high))
                return min(1, max(0.08, pow(normalized, 0.78)))
            }
        }

        return clamped.map { value in
            let dynamic = min(1, max(0, (value - low) / range))
            let level = min(1, max(0, value / high))
            let shapedDynamic = pow(dynamic, 0.78)
            let shapedLevel = pow(level, 0.58)
            return min(1, max(0.08, shapedDynamic * 0.64 + shapedLevel * 0.31 + 0.05))
        }
    }

    private static func percentile(_ values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }

        let sorted = values.sorted()
        let clampedPercentile = min(1, max(0, percentile))
        let index = Int((Double(sorted.count - 1) * clampedPercentile).rounded())
        return sorted[min(sorted.count - 1, max(0, index))]
    }
}
