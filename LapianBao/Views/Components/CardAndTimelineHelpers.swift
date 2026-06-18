//
//  CardAndTimelineHelpers.swift
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

struct CardInlineTagChip: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: VideoTagChipSize.mini.maxTextWidth, minHeight: 18, maxHeight: 18, alignment: .center)
            .foregroundStyle(Design.tagChipForeground)
            .padding(.horizontal, 7)
            .background(Design.tagChipFill)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Design.tagChipStroke, lineWidth: 0.8)
            }
    }
}

struct FadingVerticalScrollIndicators: NSViewRepresentable {
    final class Coordinator {
        weak var configuredScrollView: NSScrollView?
        var isLookupScheduled = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Self.configureSoon(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.configureSoon(from: nsView, coordinator: context.coordinator)
    }

    private static func configureSoon(from view: NSView, coordinator: Coordinator) {
        if configureIfAvailable(from: view, coordinator: coordinator) {
            return
        }

        guard !coordinator.isLookupScheduled else { return }
        coordinator.isLookupScheduled = true
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let view, let coordinator else { return }
            coordinator.isLookupScheduled = false
            _ = configureIfAvailable(from: view, coordinator: coordinator)
        }
    }

    private static func configureIfAvailable(from view: NSView, coordinator: Coordinator) -> Bool {
        if let scrollView = coordinator.configuredScrollView {
            configure(scrollView)
            return true
        }

        guard let scrollView = nearestScrollView(from: view) else {
            return false
        }
        coordinator.configuredScrollView = scrollView
        configure(scrollView)
        return true
    }

    private static func nearestScrollView(from view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
    }

    private static func configure(_ scrollView: NSScrollView) {
        if !scrollView.hasVerticalScroller {
            scrollView.hasVerticalScroller = true
        }
        if scrollView.hasHorizontalScroller {
            scrollView.hasHorizontalScroller = false
        }
        if !scrollView.autohidesScrollers {
            scrollView.autohidesScrollers = true
        }
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        if scrollView.drawsBackground {
            scrollView.drawsBackground = false
        }
        if scrollView.verticalScroller?.controlSize != .small {
            scrollView.verticalScroller?.controlSize = .small
        }
    }
}

extension View {
    func fadingVerticalScrollIndicators() -> some View {
        self
            .scrollIndicators(.automatic)
            .background(FadingVerticalScrollIndicators())
    }
}

private enum TimelineStripMetrics {
    static let segmentGap: CGFloat = 7
    static let segmentRadius: CGFloat = 5
}

private func sameNSImageIdentities(_ lhs: [NSImage], _ rhs: [NSImage]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy { pair in
        ObjectIdentifier(pair.0) == ObjectIdentifier(pair.1)
    }
}

private struct TimelineImageLayerStrip: NSViewRepresentable {
    let images: [NSImage]
    let sceneCuts: [Double]?
    let viewportStart: Double
    let viewportSpan: Double

    func makeNSView(context: Context) -> TimelineImageLayerStripView {
        TimelineImageLayerStripView()
    }

    func updateNSView(_ nsView: TimelineImageLayerStripView, context: Context) {
        nsView.configure(
            images: images,
            sceneCuts: sceneCuts,
            viewportStart: viewportStart,
            viewportSpan: viewportSpan
        )
    }
}

private final class TimelineImageLayerStripView: NSView {
    private struct Configuration {
        var images: [NSImage]
        var sceneCuts: [Double]?
        var viewportStart: Double
        var viewportSpan: Double
    }

    private struct VisibleImage {
        var image: NSImage
        var x: CGFloat
        var width: CGFloat
    }

    private var configuration: Configuration?
    private var imageLayers: [CALayer] = []
    private var imageCache: [ObjectIdentifier: CGImage] = [:]

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.masksToBounds = true
        rootLayer.backgroundColor = NSColor.clear.cgColor
        layer = rootLayer
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(
        images: [NSImage],
        sceneCuts: [Double]?,
        viewportStart: Double,
        viewportSpan: Double
    ) {
        configuration = Configuration(
            images: images,
            sceneCuts: sceneCuts,
            viewportStart: viewportStart,
            viewportSpan: viewportSpan
        )
        trimImageCache(to: images)
        render()
    }

    override func layout() {
        super.layout()
        render()
    }

    private func render() {
        guard
            let configuration,
            bounds.width > 0,
            bounds.height > 0,
            !configuration.images.isEmpty
        else {
            hideAllImageLayers()
            return
        }

        let visibleImages = visibleImages(for: configuration, width: bounds.width)
        ensureImageLayerCount(visibleImages.count)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for (index, item) in visibleImages.enumerated() {
            let imageLayer = imageLayers[index]
            imageLayer.isHidden = false
            imageLayer.contentsScale = scale
            imageLayer.contentsGravity = .resizeAspectFill
            imageLayer.masksToBounds = true
            imageLayer.cornerRadius = min(
                TimelineStripMetrics.segmentRadius,
                max(0, min(item.width, bounds.height) / 2)
            )
            imageLayer.frame = CGRect(x: item.x, y: 0, width: item.width, height: bounds.height)
            imageLayer.contents = cgImage(for: item.image)
        }

        if visibleImages.count < imageLayers.count {
            for index in visibleImages.count..<imageLayers.count {
                imageLayers[index].isHidden = true
                imageLayers[index].contents = nil
            }
        }

        CATransaction.commit()
    }

    private func visibleImages(for configuration: Configuration, width: CGFloat) -> [VisibleImage] {
        if let sceneCuts = configuration.sceneCuts {
            return visibleSceneImages(
                images: configuration.images,
                sceneCuts: sceneCuts,
                viewportStart: configuration.viewportStart,
                viewportSpan: configuration.viewportSpan,
                width: width
            )
        }

        return visibleUniformImages(
            images: configuration.images,
            viewportStart: configuration.viewportStart,
            viewportSpan: configuration.viewportSpan,
            width: width
        )
    }

    private func visibleUniformImages(
        images: [NSImage],
        viewportStart: Double,
        viewportSpan: Double,
        width: CGFloat
    ) -> [VisibleImage] {
        let count = images.count
        guard count > 0, viewportSpan > 0 else { return [] }

        let span = max(0.0001, min(1, viewportSpan))
        let start = min(1, max(0, viewportStart))
        let end = min(1, max(start, start + span))
        let frameWidth = width / (CGFloat(span) * CGFloat(count))
        let originX = -CGFloat(start / span) * width
        let first = max(0, Int(floor(start * Double(count))) - 1)
        let last = min(count - 1, Int(ceil(end * Double(count))) + 1)

        guard first <= last else { return [] }

        return (first...last).map { index in
            VisibleImage(
                image: images[index],
                x: CGFloat(index) * frameWidth + originX,
                width: max(1, frameWidth)
            )
        }
    }

    private func visibleSceneImages(
        images: [NSImage],
        sceneCuts: [Double],
        viewportStart: Double,
        viewportSpan: Double,
        width: CGFloat
    ) -> [VisibleImage] {
        let sceneCount = sceneCuts.count + 1
        guard images.count == sceneCount, sceneCount > 0, viewportSpan > 0 else { return [] }

        let start = min(1, max(0, viewportStart))
        let end = min(1, max(start, start + viewportSpan))
        guard end > start else { return [] }

        let first = min(sceneCount - 1, firstSceneIndexEnding(after: start, sceneCuts: sceneCuts))
        let last = min(sceneCount - 1, lastSceneIndexStarting(before: end, sceneCuts: sceneCuts))
        guard first <= last else { return [] }

        return (first...last).compactMap { index in
            guard let frame = visibleSceneFrame(
                for: index,
                sceneCuts: sceneCuts,
                viewportStart: start,
                viewportSpan: viewportSpan,
                imageCount: images.count,
                width: width
            ) else { return nil }

            return VisibleImage(image: images[index], x: frame.x, width: frame.width)
        }
    }

    private func visibleSceneFrame(
        for index: Int,
        sceneCuts: [Double],
        viewportStart: Double,
        viewportSpan: Double,
        imageCount: Int,
        width: CGFloat
    ) -> (x: CGFloat, width: CGFloat)? {
        guard viewportSpan > 0, index >= 0, index < imageCount else { return nil }

        let span = max(0.0001, min(1, viewportSpan))
        let viewportEnd = min(1, max(viewportStart, viewportStart + span))
        let start = sceneStart(for: index, sceneCuts: sceneCuts)
        let end = sceneEnd(for: index, sceneCuts: sceneCuts)
        let visibleStart = max(start, viewportStart)
        let visibleEnd = min(end, viewportEnd)
        guard visibleEnd > visibleStart else { return nil }

        var x0 = CGFloat((start - viewportStart) / span) * width
        var x1 = CGFloat((end - viewportStart) / span) * width
        let rawWidth = max(0, x1 - x0)

        var leadingInset: CGFloat = index > 0 ? TimelineStripMetrics.segmentGap / 2 : 0
        var trailingInset: CGFloat = index < imageCount - 1 ? TimelineStripMetrics.segmentGap / 2 : 0
        let totalInset = leadingInset + trailingInset
        if totalInset > 0 {
            let scale = min(1, max(0, (rawWidth - 2) / totalInset))
            leadingInset *= scale
            trailingInset *= scale
        }

        x0 += leadingInset
        x1 -= trailingInset
        guard x1 > x0 else { return nil }
        return (x: x0, width: x1 - x0)
    }

    private func firstSceneIndexEnding(after progress: Double, sceneCuts: [Double]) -> Int {
        var lower = 0
        var upper = sceneCuts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cutProgress(at: middle, sceneCuts: sceneCuts) <= progress {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func lastSceneIndexStarting(before progress: Double, sceneCuts: [Double]) -> Int {
        var lower = 0
        var upper = sceneCuts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cutProgress(at: middle, sceneCuts: sceneCuts) < progress {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func sceneStart(for index: Int, sceneCuts: [Double]) -> Double {
        index <= 0 ? 0 : cutProgress(at: index - 1, sceneCuts: sceneCuts)
    }

    private func sceneEnd(for index: Int, sceneCuts: [Double]) -> Double {
        index < sceneCuts.count ? cutProgress(at: index, sceneCuts: sceneCuts) : 1
    }

    private func cutProgress(at index: Int, sceneCuts: [Double]) -> Double {
        guard sceneCuts.indices.contains(index) else { return index < 0 ? 0 : 1 }
        return min(1, max(0, sceneCuts[index]))
    }

    private func ensureImageLayerCount(_ count: Int) {
        guard count > imageLayers.count else { return }
        for _ in imageLayers.count..<count {
            let imageLayer = CALayer()
            imageLayer.magnificationFilter = .linear
            imageLayer.minificationFilter = .linear
            layer?.addSublayer(imageLayer)
            imageLayers.append(imageLayer)
        }
    }

    private func hideAllImageLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for imageLayer in imageLayers {
            imageLayer.isHidden = true
            imageLayer.contents = nil
        }
        CATransaction.commit()
    }

    private func cgImage(for image: NSImage) -> CGImage? {
        let identifier = ObjectIdentifier(image)
        if let cached = imageCache[identifier] {
            return cached
        }

        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        imageCache[identifier] = cgImage
        return cgImage
    }

    private func trimImageCache(to images: [NSImage]) {
        let visibleImageIDs = Set(images.map { ObjectIdentifier($0) })
        imageCache = imageCache.filter { visibleImageIDs.contains($0.key) }
    }
}

struct SceneStoryboardStrip: View, Equatable {
    let images: [NSImage]
    let sceneCuts: [Double]
    let viewportStart: Double
    let viewportSpan: Double

    static func == (lhs: SceneStoryboardStrip, rhs: SceneStoryboardStrip) -> Bool {
        sameNSImageIdentities(lhs.images, rhs.images)
            && lhs.sceneCuts == rhs.sceneCuts
            && lhs.viewportStart == rhs.viewportStart
            && lhs.viewportSpan == rhs.viewportSpan
    }

    var body: some View {
        TimelineImageLayerStrip(
            images: images,
            sceneCuts: sceneCuts,
            viewportStart: viewportStart,
            viewportSpan: viewportSpan
        )
        .allowsHitTesting(false)
    }
}

struct SceneStoryboardProgressOverlay: View {
    let sceneCuts: [Double]
    let viewportStart: Double
    let viewportSpan: Double
    let activeProgress: Double
    let isPlaying: Bool
    let duration: Double
    var playbackRate: Double = 1

    var body: some View {
        SmoothTimelineProgressReader(
            progress: activeProgress,
            duration: duration,
            playbackRate: playbackRate,
            isPlaying: isPlaying
        ) { displayedProgress in
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height

                ZStack(alignment: .leading) {
                    if let activeFrame = activeVisibleFrame(width: width, progress: displayedProgress) {
                        Rectangle()
                            .fill(.white.opacity(0.16))
                            .frame(width: activeFrame.playedWidth, height: height)
                            .clipShape(RoundedRectangle(cornerRadius: TimelineStripMetrics.segmentRadius, style: .continuous))
                            .offset(x: activeFrame.x)

                        CurrentFrameFocusOverlay(cornerRadius: TimelineStripMetrics.segmentRadius)
                            .frame(width: activeFrame.width, height: height)
                            .offset(x: activeFrame.x)
                    }
                }
                .frame(width: width, height: height, alignment: .leading)
                .clipped()
            }
        }
        .allowsHitTesting(false)
    }

    private func activeVisibleFrame(width: CGFloat, progress: Double) -> (x: CGFloat, width: CGFloat, playedWidth: CGFloat)? {
        guard viewportSpan > 0 else { return nil }
        let index = activeSceneIndex(progress: progress)
        guard let frame = visibleFrame(for: index, width: width) else { return nil }
        return (
            x: frame.x,
            width: frame.width,
            playedWidth: playbackWidth(for: index, visibleFrameWidth: frame.width, progress: progress)
        )
    }

    private func activeSceneIndex(progress: Double) -> Int {
        let sceneCount = sceneCuts.count + 1
        guard sceneCount > 1 else { return 0 }

        let progress = min(1, max(0, progress))
        var lower = 0
        var upper = sceneCuts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cutProgress(at: middle) <= progress {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return min(sceneCount - 1, lower)
    }

    private func visibleFrame(for index: Int, width: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        guard viewportSpan > 0, index >= 0, index <= sceneCuts.count else { return nil }

        let span = max(0.0001, min(1, viewportSpan))
        let viewportStart = min(1, max(0, self.viewportStart))
        let viewportEnd = min(1, max(viewportStart, viewportStart + span))
        let start = sceneStart(for: index)
        let end = sceneEnd(for: index)
        let visibleStart = max(start, viewportStart)
        let visibleEnd = min(end, viewportEnd)
        guard visibleEnd > visibleStart else { return nil }

        var x0 = CGFloat((start - viewportStart) / span) * width
        var x1 = CGFloat((end - viewportStart) / span) * width
        let rawWidth = max(0, x1 - x0)

        var leadingInset: CGFloat = index > 0 ? TimelineStripMetrics.segmentGap / 2 : 0
        var trailingInset: CGFloat = index < sceneCuts.count ? TimelineStripMetrics.segmentGap / 2 : 0
        let totalInset = leadingInset + trailingInset
        if totalInset > 0 {
            let scale = min(1, max(0, (rawWidth - 2) / totalInset))
            leadingInset *= scale
            trailingInset *= scale
        }

        x0 += leadingInset
        x1 -= trailingInset
        guard x1 > x0 else { return nil }
        return (x: x0, width: x1 - x0)
    }

    private func playbackWidth(for index: Int, visibleFrameWidth: CGFloat, progress: Double) -> CGFloat {
        guard index >= 0, index <= sceneCuts.count else { return 0 }
        let start = sceneStart(for: index)
        let end = sceneEnd(for: index)

        guard end > start, progress > start else { return 0 }
        let played = min(end, max(start, progress))
        return visibleFrameWidth * CGFloat((played - start) / (end - start))
    }

    private func sceneStart(for index: Int) -> Double {
        index <= 0 ? 0 : cutProgress(at: index - 1)
    }

    private func sceneEnd(for index: Int) -> Double {
        index < sceneCuts.count ? cutProgress(at: index) : 1
    }

    private func cutProgress(at index: Int) -> Double {
        guard sceneCuts.indices.contains(index) else { return index < 0 ? 0 : 1 }
        return min(1, max(0, sceneCuts[index]))
    }
}

struct FrameStripTimelineStrip: View, Equatable {
    let frames: [NSImage]
    let viewportStart: Double
    let viewportSpan: Double

    static func == (lhs: FrameStripTimelineStrip, rhs: FrameStripTimelineStrip) -> Bool {
        sameNSImageIdentities(lhs.frames, rhs.frames)
            && lhs.viewportStart == rhs.viewportStart
            && lhs.viewportSpan == rhs.viewportSpan
    }

    var body: some View {
        TimelineImageLayerStrip(
            images: frames,
            sceneCuts: nil,
            viewportStart: viewportStart,
            viewportSpan: viewportSpan
        )
        .allowsHitTesting(false)
    }
}

struct FrameScrubberPlaceholderStrip: View {
    let progress: Double
    let viewportStart: Double
    let viewportSpan: Double

    private let frameCount = 16

    var body: some View {
        Canvas { context, size in
            guard frameCount > 0, size.width > 0, size.height > 0 else { return }

            let span = max(0.0001, min(1, viewportSpan))
            let start = min(1, max(0, viewportStart))
            let end = min(1, max(start, start + span))
            let frameWidth = size.width / (CGFloat(span) * CGFloat(frameCount))
            let originX = -CGFloat(start / span) * size.width
            let first = max(0, Int(floor(start * Double(frameCount))) - 1)
            let last = min(frameCount - 1, Int(ceil(end * Double(frameCount))) + 1)

            if first <= last {
                for index in first...last {
                    let x = CGFloat(index) * frameWidth + originX
                    let rect = CGRect(
                        x: x + 2,
                        y: 0,
                        width: max(1, frameWidth - 4),
                        height: size.height
                    )
                    guard rect.maxX >= 0, rect.minX <= size.width else { continue }

                    var tile = Path()
                    tile.addRoundedRect(
                        in: rect,
                        cornerSize: CGSize(width: TimelineStripMetrics.segmentRadius, height: TimelineStripMetrics.segmentRadius)
                    )
                    let opacity = index.isMultiple(of: 2) ? 0.10 : 0.075
                    context.fill(tile, with: .color(.white.opacity(opacity)))
                    context.stroke(tile, with: .color(.white.opacity(0.07)), lineWidth: 0.7)
                }
            }

            let playedWidth = size.width * CGFloat(min(1, max(0, progress)))
            guard playedWidth > 0 else { return }
            let playedRect = CGRect(x: 0, y: 0, width: playedWidth, height: size.height)
            context.fill(Path(playedRect), with: .color(.white.opacity(0.10)))
        }
        .allowsHitTesting(false)
    }
}

struct FrameScrubberView: View {
    let frames: [NSImage]?
    let progress: Double
    let timecodeText: String
    let sceneCuts: [Double]
    let isPlaying: Bool
    var playbackRate: Double = 1
    let togglePlayback: () -> Void
    let seek: (Double) -> Void
    var screenshotMarkers: [Double] = []
    var annotationItems: [TimelineAnnotationMarker] = []
    var prevScene: (() -> Void)? = nil
    var nextScene: (() -> Void)? = nil
    var stepBack: (() -> Void)? = nil
    var stepForward: (() -> Void)? = nil
    var onScreenshot: (() -> Void)? = nil
    var onAnnotate: (() -> Void)? = nil
    var onAnnotationSelect: ((UUID) -> Void)? = nil
    var viewportStart: Double = 0
    var viewportSpan: Double = 1
    var duration: Double = 0
    var zoomLevel: Double = 1
    var playheadTint: Color = Design.timelinePlayheadAccent
    var showsPlayhead: Bool = false
    var panViewport: ((Double) -> Void)? = nil
    var zoomViewport: ((Double, Double) -> Void)? = nil
    var resetViewport: (() -> Void)? = nil
    var timelineHeight: CGFloat = 48
    /// 场景识别完成后传入：每个场景一张缩略图（index 0 = 片头帧，1…N = 各切点首帧）
    var sceneImages: [NSImage]? = nil

    @State private var draftProgress: Double?
    @State private var tappedAnnotationText: String? = nil
    @State private var showAnnotationDetail = false
    @State private var hoverProgress: Double?
    @State private var lastMagnification: CGFloat = 1
    @State private var lastLiveSeekAt = Date.distantPast

    var body: some View {
        let dp = localProgress(draftProgress ?? progress)

        VStack(spacing: 4) {
            // 行一：帧缩略图时间线
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                ZStack(alignment: .leading) {
                    // 优先使用场景识别缩略图（每场景宽度 ∝ 时长）
                    if let sceneImages, !sceneImages.isEmpty,
                       sceneCuts.count == sceneImages.count - 1 {
                        ZStack(alignment: .leading) {
                            SceneStoryboardStrip(
                                images: sceneImages,
                                sceneCuts: sceneCuts,
                                viewportStart: viewportStart,
                                viewportSpan: viewportSpan
                            )
                            .equatable()

                            SceneStoryboardProgressOverlay(
                                sceneCuts: sceneCuts,
                                viewportStart: viewportStart,
                                viewportSpan: viewportSpan,
                                activeProgress: draftProgress ?? progress,
                                isPlaying: isPlaying && draftProgress == nil,
                                duration: duration,
                                playbackRate: playbackRate
                            )
                        }
                    } else if let frames, !frames.isEmpty {
                        // 暂无场景识别结果时：均匀采样帧带，随 viewport 缩放/平移
                        ZStack(alignment: .leading) {
                            FrameStripTimelineStrip(
                                frames: frames,
                                viewportStart: viewportStart,
                                viewportSpan: viewportSpan
                            )
                            .equatable()

                            Rectangle()
                                .fill(.white.opacity(0.16))
                                .frame(width: width * CGFloat(dp))
                        }
                    } else {
                        FrameScrubberPlaceholderStrip(
                            progress: dp,
                            viewportStart: viewportStart,
                            viewportSpan: viewportSpan
                        )
                    }

                    if let hoverProgress, isVisible(hoverProgress) {
                        Rectangle()
                            .fill(.white.opacity(0.92))
                            .frame(width: 1, height: height)
                            .shadow(color: .black.opacity(0.35), radius: 1)
                            .offset(x: width * CGFloat(localProgress(hoverProgress)) - 0.5)
                            .allowsHitTesting(false)
                    }

                    // 批注点：可点击，显示批注文本
                    ForEach(Array(annotationItems.enumerated()), id: \.offset) { _, item in
                        Button {
                            if let onAnnotationSelect {
                                onAnnotationSelect(item.id)
                            } else {
                                tappedAnnotationText = item.text
                                showAnnotationDetail = true
                            }
                        } label: {
                            Circle()
                                .fill(annotationTint(for: item.kind).opacity(0.92))
                                .frame(width: 7, height: 7)
                                .overlay {
                                    Circle()
                                        .stroke(.black.opacity(0.35), lineWidth: 0.6)
                                }
                                .frame(width: 18, height: 18)
                        }
                    .buttonStyle(.plain)
                    .opacity(isVisible(item.progress) ? 1 : 0)
                    .offset(x: width * CGFloat(localProgress(item.progress)) - 9, y: 3)
                    .zIndex(5)
                }

                if showsPlayhead, isVisible(draftProgress ?? progress) {
                    Rectangle()
                        .fill(playheadTint)
                            .frame(width: 2, height: height)
                        .shadow(color: .black.opacity(0.35), radius: 1)
                        .offset(x: width * CGFloat(localProgress(draftProgress ?? progress)) - 1)
                        .allowsHitTesting(false)
                        .zIndex(3)
                }

                    // 双指水平滑动平移时间线（透明覆盖层，仅拦截 scroll 事件）
                    if panViewport != nil {
                        ScrollPanLayer(panViewport: panViewport, viewportSpan: viewportSpan)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        hoverProgress = globalProgress(from: location, width: width)
                    case .ended:
                        hoverProgress = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let next = globalProgress(from: value.location, width: width)
                            draftProgress = next
                            sendLiveSeekIfNeeded(next)
                        }
                        .onEnded { value in
                            let final = globalProgress(from: value.location, width: width)
                            draftProgress = nil
                            lastLiveSeekAt = .distantPast
                            seek(final)
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let factor = value / max(lastMagnification, 0.001)
                            lastMagnification = value
                            zoomViewport?(Double(factor), 0.5)
                        }
                        .onEnded { _ in lastMagnification = 1 }
                )
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: timelineHeight)
        }
        .popover(isPresented: $showAnnotationDetail, arrowEdge: .top) {
            if let text = tappedAnnotationText {
                VStack(alignment: .leading, spacing: 6) {
                    Label("批注", systemImage: "text.bubble.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Design.annotationAccent)
                    Text(text)
                        .font(.callout)
                        .frame(maxWidth: 220)
                }
                .padding(12)
            }
        }
    }

    // 播放键居中，快退/快进紧贴两侧，工具区图标靠右，去掉缩放按钮
    private var controlRow: some View {
        ZStack {
            // 播放控制组：ZStack 默认居中 → 播放键始终在正中心
            HStack(spacing: 4) {
                navButton(icon: "backward.end.fill", help: "上一个场景", action: prevScene)
                navButton(icon: "gobackward.1",      help: "后退一帧",   action: stepBack)

                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "暂停" : "播放")

                navButton(icon: "goforward.1",      help: "前进一帧",   action: stepForward)
                navButton(icon: "forward.end.fill", help: "下一个场景", action: nextScene)
            }

            // 右侧辅助区：timecode + 图标按钮（无文字标签）
            HStack(spacing: 4) {
                Spacer()

                Text(timecodeText)
                    .font(Design.numericCaption(weight: .semibold))
                    .foregroundStyle(.white.opacity(0.74))
                    .frame(minWidth: 60, alignment: .center)

                if let fn = onScreenshot {
                    Button(action: fn) {
                        Image(systemName: "camera.fill")
                            .frame(width: 22, height: 22)
                    }
                    .help("截取当前帧")
                }
                if let fn = onAnnotate {
                    Button(action: fn) {
                        Image(systemName: "text.bubble.fill")
                            .frame(width: 22, height: 22)
                    }
                    .help("添加批注")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private func navButton(icon: String, help: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(action == nil ? .quaternary : .secondary)
        .disabled(action == nil)
        .help(help)
    }

    private func globalProgress(from location: CGPoint, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        let local = min(1, max(0, Double(location.x / width)))
        return min(1, max(0, viewportStart + local * viewportSpan))
    }

    private func localProgress(_ global: Double) -> Double {
        guard viewportSpan > 0 else { return global }
        return min(1, max(0, (global - viewportStart) / viewportSpan))
    }

    private func isVisible(_ global: Double) -> Bool {
        global >= viewportStart && global <= viewportStart + viewportSpan
    }

    private func annotationTint(for kind: AnnotationItem.Kind) -> Color {
        switch kind {
        case .frame: return Design.captureFrameAccent
        case .audio: return Design.annotationAccent
        case .content: return Design.annotationAccent
        }
    }

    private func sendLiveSeekIfNeeded(_ progress: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastLiveSeekAt) >= 1.0 / 30.0 else { return }
        lastLiveSeekAt = now
        seek(progress)
    }

}

struct SimpleProgressBar: View {
    let progress: Double
    let timecodeText: String
    let isPlaying: Bool
    let togglePlayback: () -> Void
    let seek: (Double) -> Void
    var annotationItems: [TimelineAnnotationMarker] = []
    var onAnnotationSelect: ((UUID) -> Void)? = nil
    var playheadTint: Color = Design.timelinePlayheadAccent
    var stepBack: (() -> Void)? = nil
    var stepForward: (() -> Void)? = nil
    var onScreenshot: (() -> Void)? = nil
    var onAnnotate: (() -> Void)? = nil

    @State private var draftProgress: Double?
    @State private var lastLiveSeekAt = Date.distantPast

    var body: some View {
        let dp = draftProgress ?? progress

        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let cornerRadius = min(Design.innerRadius, height / 2)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)

                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: max(0, width * CGFloat(dp)))

                Rectangle()
                    .fill(playheadTint)
                    .frame(width: 2, height: height)
                    .shadow(color: .black.opacity(0.28), radius: 1)
                    .offset(x: min(max(0, width * CGFloat(dp) - 1), max(0, width - 2)))
                    .allowsHitTesting(false)
                    .zIndex(3)

                ForEach(annotationItems) { item in
                    Button {
                        onAnnotationSelect?(item.id)
                    } label: {
                        Circle()
                            .fill(annotationTint(for: item.kind).opacity(0.92))
                            .frame(width: 7, height: 7)
                            .overlay {
                                Circle().stroke(.black.opacity(0.58), lineWidth: 0.8)
                            }
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .zIndex(5)
                    .offset(
                        x: min(max(0, width * CGFloat(item.progress) - 9), max(0, width - 18)),
                        y: annotationYOffset(for: item.kind, height: height)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.7)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let next = min(1, max(0, Double(value.location.x / width)))
                        draftProgress = next
                        sendLiveSeekIfNeeded(next)
                    }
                    .onEnded { value in
                        let final = min(1, max(0, Double(value.location.x / width)))
                        draftProgress = nil
                        lastLiveSeekAt = .distantPast
                        seek(final)
                    }
            )
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func annotationYOffset(for kind: AnnotationItem.Kind, height: CGFloat) -> CGFloat {
        let margin: CGFloat = min(max(12, height * 0.16), max(12, height / 2))
        let topCenter = margin
        let middleCenter = height / 2
        let bottomCenter = max(margin, height - margin)
        let targetCenter: CGFloat
        switch kind {
        case .frame:
            targetCenter = topCenter
        case .audio:
            targetCenter = middleCenter
        case .content:
            targetCenter = bottomCenter
        }
        return targetCenter - height / 2
    }

    private func annotationTint(for kind: AnnotationItem.Kind) -> Color {
        .white
    }

    private func sendLiveSeekIfNeeded(_ progress: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastLiveSeekAt) >= 1.0 / 30.0 else { return }
        lastLiveSeekAt = now
        seek(progress)
    }
}
