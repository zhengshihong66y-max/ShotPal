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

struct ViewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

struct CardInlineTagChip: View {
    let tag: String

    var body: some View {
        let tint = VideoTagPalette.color(for: tag)

        Text(tag)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: VideoTagChipSize.mini.maxTextWidth, minHeight: 18, maxHeight: 18, alignment: .center)
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .background(tint.opacity(0.18))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.34), lineWidth: 0.8)
            }
    }
}

struct ScaledCardTagCloud: View {
    let tags: [String]

    private var visibleTags: [String] {
        Array(tags.prefix(2))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

struct HiddenScrollIndicators: NSViewRepresentable {
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
        if scrollView.hasVerticalScroller {
            scrollView.hasVerticalScroller = false
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
        if scrollView.verticalScroller?.isHidden == false {
            scrollView.verticalScroller?.isHidden = true
        }
        if scrollView.horizontalScroller?.isHidden == false {
            scrollView.horizontalScroller?.isHidden = true
        }
    }
}

struct SceneStoryboardStrip: View {
    let images: [NSImage]
    let sceneCuts: [Double]
    let viewportStart: Double
    let viewportSpan: Double
    let activeProgress: Double
    let previewProgress: Double?

    private let segmentGap: CGFloat = 7
    private let segmentRadius: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let visibleRange = visibleSceneRange()

            ZStack(alignment: .leading) {
                if images.count == sceneCuts.count + 1,
                   viewportSpan > 0,
                   let visibleRange {
                    ForEach(Array(visibleRange), id: \.self) { index in
                        if let frame = visibleFrame(for: index, width: width) {
                            Image(nsImage: images[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: frame.width, height: height)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: segmentRadius, style: .continuous))
                                .overlay(alignment: .leading) {
                                    Rectangle()
                                        .fill(.white.opacity(0.16))
                                        .frame(width: playbackWidth(for: index, visibleFrameWidth: frame.width))
                                        .clipShape(RoundedRectangle(cornerRadius: segmentRadius, style: .continuous))
                                }
                                .overlay {
                                    if isActive(index) {
                                        CurrentFrameFocusOverlay(cornerRadius: segmentRadius)
                                    }
                                }
                                .offset(x: frame.x)
                        }
                    }
                }
            }
            .frame(width: width, height: height, alignment: .leading)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    private func visibleSceneRange() -> ClosedRange<Int>? {
        let sceneCount = sceneCuts.count + 1
        guard images.count == sceneCount, sceneCount > 0, viewportSpan > 0 else { return nil }

        let start = min(1, max(0, viewportStart))
        let end = min(1, max(start, viewportStart + viewportSpan))
        guard end > start else { return nil }

        let first = min(sceneCount - 1, firstSceneIndexEnding(after: start))
        let last = min(sceneCount - 1, lastSceneIndexStarting(before: end))
        guard first <= last else { return nil }
        return first...last
    }

    private func firstSceneIndexEnding(after progress: Double) -> Int {
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
        return lower
    }

    private func lastSceneIndexStarting(before progress: Double) -> Int {
        var lower = 0
        var upper = sceneCuts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cutProgress(at: middle) < progress {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func visibleFrame(for index: Int, width: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        guard viewportSpan > 0, index >= 0, index < images.count else { return nil }

        let viewportStart = min(1, max(0, self.viewportStart))
        let viewportEnd = min(1, max(viewportStart, self.viewportStart + viewportSpan))
        let start = sceneStart(for: index)
        let end = sceneEnd(for: index)
        let visibleStart = max(start, viewportStart)
        let visibleEnd = min(end, viewportEnd)
        guard visibleEnd > visibleStart else { return nil }

        var x0 = CGFloat((visibleStart - viewportStart) / viewportSpan) * width
        var x1 = CGFloat((visibleEnd - viewportStart) / viewportSpan) * width
        let rawWidth = max(0, x1 - x0)

        var leadingInset: CGFloat = index > 0 && start >= viewportStart ? segmentGap / 2 : 0
        var trailingInset: CGFloat = index < images.count - 1 && end <= viewportEnd ? segmentGap / 2 : 0
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

    private func isActive(_ index: Int) -> Bool {
        guard index >= 0, index < images.count else { return false }
        let progress = min(1, max(0, activeProgress))
        if index == images.count - 1 {
            return progress >= sceneStart(for: index) && progress <= sceneEnd(for: index)
        }
        return progress >= sceneStart(for: index) && progress < sceneEnd(for: index)
    }

    private func playbackWidth(for index: Int, visibleFrameWidth: CGFloat) -> CGFloat {
        guard index >= 0, index < images.count else { return 0 }
        let start = sceneStart(for: index)
        let end = sceneEnd(for: index)
        let isActive = index == images.count - 1
            ? activeProgress >= start && activeProgress <= end
            : activeProgress >= start && activeProgress < end
        guard isActive else { return 0 }

        let viewportStart = min(1, max(0, self.viewportStart))
        let viewportEnd = min(1, max(viewportStart, self.viewportStart + viewportSpan))
        let visibleStart = max(start, viewportStart)
        let visibleEnd = min(end, viewportEnd)
        guard visibleEnd > visibleStart, activeProgress > visibleStart else { return 0 }
        let played = min(visibleEnd, activeProgress)
        return visibleFrameWidth * CGFloat((played - visibleStart) / (visibleEnd - visibleStart))
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

struct FrameScrubberView: View {
    let frames: [NSImage]?
    let progress: Double
    let timecodeText: String
    let sceneCuts: [Double]
    let isPlaying: Bool
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
    var playheadTint: Color = .white.opacity(0.92)
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
                        SceneStoryboardStrip(
                            images: sceneImages,
                            sceneCuts: sceneCuts,
                            viewportStart: viewportStart,
                            viewportSpan: viewportSpan,
                            activeProgress: draftProgress ?? progress,
                            previewProgress: hoverProgress
                        )
                    } else if let frames, !frames.isEmpty {
                        // 暂无场景识别结果时：均匀采样帧带，随 viewport 缩放/平移
                        let count   = frames.count
                        let frameW  = width / (CGFloat(viewportSpan) * CGFloat(count))
                        let originX = -CGFloat(viewportStart / viewportSpan) * width
                        let first   = max(0, Int(viewportStart * Double(count)))
                        let last    = min(count - 1, Int((viewportStart + viewportSpan) * Double(count)) + 1)
                        if first <= last {
                            ZStack(alignment: .leading) {
                                ForEach(first...last, id: \.self) { i in
                                    Image(nsImage: frames[i])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: max(1, frameW), height: height)
                                        .clipped()
                                        .offset(x: CGFloat(i) * frameW + originX)
                                }

                                Rectangle()
                                    .fill(.white.opacity(0.16))
                                    .frame(width: width * CGFloat(dp))
                            }
                            .frame(width: width, height: height, alignment: .leading)
                            .clipped()
                        }
                    } else {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.06), location: 0),
                                .init(color: .white.opacity(0.10), location: 0.5),
                                .init(color: .white.opacity(0.06), location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
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
                    .font(.caption.monospacedDigit().weight(.semibold))
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

    private func localizedMarkers(_ markers: [Double]) -> [Double] {
        markers.filter(isVisible).map(localProgress)
    }

    private func isVisible(_ global: Double) -> Bool {
        global >= viewportStart && global <= viewportStart + viewportSpan
    }

    private func annotationTint(for kind: AnnotationItem.Kind) -> Color {
        switch kind {
        case .frame: return Design.captureFrameAccent
        case .audio: return .orange
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
    var chapters: [TranscriptTimelineChapter] = []
    var duration: Double = 0
    var annotationItems: [TimelineAnnotationMarker] = []
    var onAnnotationSelect: ((UUID) -> Void)? = nil
    var playheadTint: Color = .white.opacity(0.92)
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
            let chapterSegments = normalizedChapterSegments(duration: duration)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)

                if chapterSegments.isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: max(0, width * CGFloat(dp)))
                } else {
                    let segmentGap: CGFloat = 4

                    ForEach(Array(chapterSegments.enumerated()), id: \.element.id) { index, segment in
                        let isFirst = index == chapterSegments.startIndex
                        let isLast = index == chapterSegments.index(before: chapterSegments.endIndex)
                        let leadingInset: CGFloat = isFirst ? 0 : segmentGap / 2
                        let trailingInset: CGFloat = isLast ? 0 : segmentGap / 2
                        let x = width * CGFloat(segment.start) + leadingInset
                        let segmentWidth = max(0, width * CGFloat(segment.end - segment.start) - leadingInset - trailingInset)

                        RoundedRectangle(cornerRadius: min(Design.innerRadius, height / 2), style: .continuous)
                            .fill(chapterFill(for: segment, progress: dp))
                            .overlay(alignment: .leading) {
                                if segmentWidth > 42 {
                                    Text(segment.title)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white.opacity(segmentTextOpacity(for: segment, progress: dp)))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                        .padding(.horizontal, 7)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: min(Design.innerRadius, height / 2), style: .continuous)
                                    .stroke(.white.opacity(segmentStrokeOpacity(for: segment, progress: dp)), lineWidth: 0.7)
                            }
                            .frame(width: segmentWidth, height: height)
                            .offset(x: x)
                    }
                }

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
        }
        .frame(maxWidth: .infinity)
    }

    private struct ChapterSegment: Identifiable {
        let id: UUID
        let title: String
        let start: Double
        let end: Double
    }

    private func normalizedChapterSegments(duration: Double) -> [ChapterSegment] {
        let sorted = chapters.sorted { $0.start < $1.start }
        let fallbackDuration = max(duration, sorted.last?.end ?? sorted.last?.start ?? 0)
        guard fallbackDuration > 0 else { return [] }

        return sorted.enumerated().compactMap { index, chapter in
            let startTime = index == sorted.startIndex ? 0 : chapter.start
            let rawStart = min(max(0, startTime / fallbackDuration), 1)
            let nextStart = sorted.indices.contains(index + 1) ? sorted[index + 1].start : fallbackDuration
            let rawEndTime = nextStart
            let rawEnd = min(max(rawStart, rawEndTime / fallbackDuration), 1)
            guard rawEnd > rawStart else { return nil }

            return ChapterSegment(
                id: chapter.id,
                title: chapter.title,
                start: rawStart,
                end: rawEnd
            )
        }
    }

    private func chapterFill(for segment: ChapterSegment, progress: Double) -> Color {
        if progress >= segment.start, progress <= segment.end {
            return Design.annotationAccent.opacity(0.32)
        }
        return progress > segment.end ? .white.opacity(0.20) : .white.opacity(0.10)
    }

    private func segmentTextOpacity(for segment: ChapterSegment, progress: Double) -> Double {
        if progress >= segment.start, progress <= segment.end { return 0.92 }
        return progress > segment.end ? 0.72 : 0.54
    }

    private func segmentStrokeOpacity(for segment: ChapterSegment, progress: Double) -> Double {
        if progress >= segment.start, progress <= segment.end { return 0.24 }
        return 0.08
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
