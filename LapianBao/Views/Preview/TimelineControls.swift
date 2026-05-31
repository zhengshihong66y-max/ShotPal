//
//  TimelineControls.swift
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

struct AudioWaveformView: View {
    let samples: [Double]?
    let progress: Double
    let seek: (Double) -> Void
    var sceneCuts: [Double] = []
    var inPoint: Double? = nil
    var outPoint: Double? = nil
    var viewportStart: Double = 0
    var viewportSpan: Double = 1
    var duration: Double = 0
    var panViewport: ((Double) -> Void)? = nil
    var zoomViewport: ((Double, Double) -> Void)? = nil

    @State private var isDragging = false
    @State private var draftProgress: Double?
    @State private var lastMagnification: CGFloat = 1
    @State private var lastLiveSeekAt = Date.distantPast

    private let placeholderSamples: [Double] = (0..<240).map { index in
        0.14 + 0.10 * abs(sin(Double(index) * 0.46))
    }

    var body: some View {
        let activeProgress = min(1, max(0, draftProgress ?? progress))
        let displayedProgress = localProgress(activeProgress)

        GeometryReader { proxy in
            ZStack {
                Canvas { context, size in
                    let values = samples ?? placeholderSamples

                    guard !values.isEmpty else {
                        let rect = CGRect(x: 0, y: size.height / 2, width: size.width, height: 1)
                        context.fill(Path(rect), with: .color(.white.opacity(0.18)))
                        return
                    }

                    // In/Out 区间高亮
                    if let inP = inPoint, let outP = outPoint, size.width > 0 {
                        let lo = CGFloat(localProgress(min(inP, outP)))
                        let hi = CGFloat(localProgress(max(inP, outP)))
                        var regionPath = Path()
                        regionPath.addRect(CGRect(x: size.width * lo, y: 0, width: size.width * (hi - lo), height: size.height))
                        context.fill(regionPath, with: .color(.white.opacity(0.18)))
                    }

                    let sampleCount = values.count
                    let span = max(0.0001, min(1, viewportSpan))
                    let visibleStart = min(1, max(0, viewportStart))
                    let visibleEnd = min(1, max(visibleStart, visibleStart + span))
                    let contentWidth = size.width / CGFloat(span)
                    let contentOffset = -CGFloat(visibleStart / span) * size.width
                    let step = contentWidth / CGFloat(sampleCount)
                    let barWidth = max(0.65, min(1.6, step * 0.82))
                    let firstIndex = max(0, Int(floor(visibleStart * Double(sampleCount))) - 1)
                    let lastIndex = min(sampleCount - 1, Int(ceil(visibleEnd * Double(sampleCount))) + 1)

                    if firstIndex <= lastIndex {
                        for index in firstIndex...lastIndex {
                            let value = values[index]
                            let normalized = max(0.04, min(1, value))
                            let barHeight = CGFloat(normalized) * size.height * 0.84
                            let x = CGFloat(index) * step + contentOffset + (step - barWidth) / 2
                            guard x <= size.width, x + barWidth >= 0 else { continue }
                            let y = (size.height - barHeight) / 2
                            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)

                            let barProgress = (Double(index) + 0.5) / Double(sampleCount)
                            let color: Color = samples == nil
                                ? .white.opacity(0.16)
                                : (barProgress <= activeProgress
                                    ? .white.opacity(0.88)
                                    : .white.opacity(0.28))

                            var path = Path()
                            path.addRoundedRect(
                                in: rect,
                                cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                            )
                            context.fill(path, with: .color(color))
                        }
                    }

                    // In/Out 竖线标记
                    for (pt, isIn) in [(inPoint, true), (outPoint, false)].compactMap({ p, flag -> (Double, Bool)? in
                        guard let p else { return nil }; return (p, flag)
                    }) where size.width > 0 && isVisible(pt) {
                        let x = size.width * CGFloat(localProgress(pt))
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: 0))
                        line.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(line, with: .color(Color.orange.opacity(0.85)),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        // 顶部小标签圆
                        let labelR: CGFloat = 5
                        var dot = Path()
                        dot.addEllipse(in: CGRect(x: x - labelR, y: 1, width: labelR * 2, height: labelR * 2))
                        context.fill(dot, with: .color(Color.orange.opacity(isIn ? 0.92 : 0.70)))
                    }

                    if samples != nil, size.width > 0 {
                        let headX = min(max(1, size.width * CGFloat(displayedProgress)), max(1, size.width - 1))
                        var headPath = Path()
                        headPath.addRoundedRect(
                            in: CGRect(x: headX - 1, y: 2, width: 2, height: size.height - 4),
                            cornerSize: CGSize(width: 1, height: 1)
                        )
                        context.fill(headPath, with: .color(.white.opacity(0.95)))
                    }

                    var drawnCutColumns = Set<Int>()
                    for cut in sceneCuts where size.width > 0 && isVisible(cut) {
                        let x = size.width * CGFloat(localProgress(cut))
                        let column = Int(x.rounded())
                        guard drawnCutColumns.insert(column).inserted else { continue }
                        var cutPath = Path()
                        cutPath.move(to: CGPoint(x: x, y: 5))
                        cutPath.addLine(to: CGPoint(x: x, y: size.height - 5))
                        context.stroke(
                            cutPath,
                            with: .color(Color.orange.opacity(0.80)),
                            style: StrokeStyle(lineWidth: 1.5)
                        )
                        var diamondPath = Path()
                        diamondPath.move(to: CGPoint(x: x, y: 2))
                        diamondPath.addLine(to: CGPoint(x: x + 3, y: 5))
                        diamondPath.addLine(to: CGPoint(x: x, y: 8))
                        diamondPath.addLine(to: CGPoint(x: x - 3, y: 5))
                        diamondPath.closeSubpath()
                        context.fill(diamondPath, with: .color(Color.orange.opacity(0.90)))
                    }
                }

                if panViewport != nil {
                    ScrollPanLayer(panViewport: panViewport, viewportSpan: viewportSpan)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let next = globalProgress(from: value.location, width: proxy.size.width)
                        draftProgress = next
                        sendLiveSeekIfNeeded(next)
                    }
                    .onEnded { value in
                        let final = globalProgress(from: value.location, width: proxy.size.width)
                        draftProgress = nil
                        lastLiveSeekAt = .distantPast
                        isDragging = false
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
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 64)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
        .accessibilityLabel("音频波形进度条")
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

    private func sendLiveSeekIfNeeded(_ progress: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastLiveSeekAt) >= 1.0 / 30.0 else { return }
        lastLiveSeekAt = now
        seek(progress)
    }

}

struct CenteredWaveformTimeline: View {
    let samples: [Double]?
    let progress: Double
    let seek: (Double) -> Void
    var sceneCuts: [Double] = []
    var inPoint: Double? = nil
    var outPoint: Double? = nil
    var annotationItems: [TimelineAnnotationMarker] = []
    var onAnnotationSelect: ((UUID) -> Void)? = nil
    var onClearSelection: (() -> Void)? = nil
    var viewportSpan: Double = 1
    var playheadTint: Color = .white.opacity(0.96)
    var panViewport: ((Double) -> Void)? = nil
    var zoomViewport: ((Double, Double) -> Void)? = nil

    @State private var dragStartProgress: Double?
    @State private var draftProgress: Double?
    @State private var isHoveringSelection = false
    @State private var lastMagnification: CGFloat = 1
    @State private var lastLiveSeekAt = Date.distantPast

    private let placeholderSamples: [Double] = (0..<360).map { index in
        0.12 + 0.18 * abs(sin(Double(index) * 0.34))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Canvas { context, size in
                    let values = samples ?? placeholderSamples
                    guard !values.isEmpty, size.width > 0, size.height > 0 else { return }

                    let span = max(0.02, min(1, viewportSpan))
                    let focus = min(1, max(0, draftProgress ?? progress))
                    let centerX = size.width / 2

                    if let inPoint, let outPoint {
                        let x1 = xPosition(for: min(inPoint, outPoint), focus: focus, span: span, width: size.width)
                        let x2 = xPosition(for: max(inPoint, outPoint), focus: focus, span: span, width: size.width)
                        let rect = CGRect(
                            x: max(0, min(x1, x2)),
                            y: 0,
                            width: min(size.width, max(x1, x2)) - max(0, min(x1, x2)),
                            height: size.height
                        )
                        if rect.width > 0 {
                            context.fill(Path(rect), with: .color(Color.orange.opacity(0.14)))
                        }
                    }

                    let sampleStep = 1 / Double(values.count)
                    let visibleWidth = size.width / CGFloat(span)
                    let barWidth = max(0.65, min(1.5, visibleWidth / CGFloat(values.count) * 0.82))
                    let visibleStart = max(0, focus - span / 2)
                    let visibleEnd = min(1, focus + span / 2)
                    let firstIndex = max(0, Int(floor(visibleStart / sampleStep)) - 1)
                    let lastIndex = min(values.count - 1, Int(ceil(visibleEnd / sampleStep)) + 1)

                    if firstIndex <= lastIndex {
                        for index in firstIndex...lastIndex {
                            let value = values[index]
                            let sampleProgress = (Double(index) + 0.5) * sampleStep
                            let x = xPosition(for: sampleProgress, focus: focus, span: span, width: size.width)
                            guard x > -barWidth, x < size.width + barWidth else { continue }

                            let normalized = max(0.04, min(1, value))
                            let barHeight = CGFloat(normalized) * size.height * 0.78
                            let rect = CGRect(x: x - barWidth / 2, y: (size.height - barHeight) / 2, width: barWidth, height: barHeight)
                            var path = Path()
                            path.addRoundedRect(in: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
                            let color: Color = samples == nil
                                ? .white.opacity(0.18)
                                : (sampleProgress <= focus ? .white.opacity(0.72) : .white.opacity(0.30))
                            context.fill(path, with: .color(color))
                        }
                    }

                    for cut in sceneCuts {
                        let x = xPosition(for: cut, focus: focus, span: span, width: size.width)
                        guard x >= 0, x <= size.width else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 5))
                        path.addLine(to: CGPoint(x: x, y: size.height - 5))
                        context.stroke(path, with: .color(Color.orange.opacity(0.64)), style: StrokeStyle(lineWidth: 1.2))
                    }

                    var centerLine = Path()
                    centerLine.addRoundedRect(
                        in: CGRect(x: centerX - 1, y: 1, width: 2, height: size.height - 2),
                        cornerSize: CGSize(width: 1, height: 1)
                    )
                    context.fill(centerLine, with: .color(playheadTint))
                }

                ForEach(annotationItems) { item in
                    Button {
                        onAnnotationSelect?(item.id)
                    } label: {
                        Circle()
                            .fill(Color.orange.opacity(0.92))
                            .frame(width: 8, height: 8)
                            .overlay {
                                Circle().stroke(.black.opacity(0.36), lineWidth: 0.6)
                            }
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .offset(
                        x: xPosition(
                            for: item.progress,
                            focus: min(1, max(0, draftProgress ?? progress)),
                            span: max(0.02, min(1, viewportSpan)),
                            width: proxy.size.width
                        ) - 9,
                        y: 4
                    )
                    .opacity(isMarkerVisible(item.progress, focus: min(1, max(0, draftProgress ?? progress)), span: max(0.02, min(1, viewportSpan))) ? 1 : 0)
                    .zIndex(5)
                }

                if isHoveringSelection,
                   let onClearSelection,
                   let frame = selectionFrame(
                       focus: min(1, max(0, draftProgress ?? progress)),
                       span: max(0.02, min(1, viewportSpan)),
                       width: proxy.size.width,
                       height: proxy.size.height
                   ) {
                    Button(action: onClearSelection) {
                        Image(systemName: "trash")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 22, height: 22)
                            .background(Color.orange.opacity(0.82))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(x: frame.midX, y: frame.midY)
                    .help("清除声音选区")
                    .zIndex(3)
                }

                if panViewport != nil {
                    ScrollPanLayer(panViewport: panViewport, viewportSpan: viewportSpan)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    isHoveringSelection = selectionFrame(
                        focus: min(1, max(0, draftProgress ?? progress)),
                        span: max(0.02, min(1, viewportSpan)),
                        width: proxy.size.width,
                        height: proxy.size.height
                    )?.contains(location) == true
                case .ended:
                    isHoveringSelection = false
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let next = scrubProgress(for: value, width: proxy.size.width)
                        draftProgress = next
                        sendLiveSeekIfNeeded(next)
                    }
                    .onEnded { value in
                        let final = scrubProgress(for: value, width: proxy.size.width)
                        draftProgress = nil
                        dragStartProgress = nil
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
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.7)
        }
        .accessibilityLabel("居中播放头音频波形")
    }

    private func xPosition(for sampleProgress: Double, focus: Double, span: Double, width: CGFloat) -> CGFloat {
        width / 2 + CGFloat((sampleProgress - focus) / span) * width
    }

    private func isMarkerVisible(_ sampleProgress: Double, focus: Double, span: Double) -> Bool {
        abs(sampleProgress - focus) <= span / 2
    }

    private func selectionFrame(focus: Double, span: Double, width: CGFloat, height: CGFloat) -> CGRect? {
        guard let inPoint, let outPoint, width > 0, height > 0 else { return nil }
        let x1 = xPosition(for: min(inPoint, outPoint), focus: focus, span: span, width: width)
        let x2 = xPosition(for: max(inPoint, outPoint), focus: focus, span: span, width: width)
        let minX = max(0, min(x1, x2))
        let maxX = min(width, max(x1, x2))
        guard maxX - minX >= 10 else { return nil }
        return CGRect(x: minX, y: 0, width: maxX - minX, height: height)
    }

    private func scrubProgress(for value: DragGesture.Value, width: CGFloat) -> Double {
        if dragStartProgress == nil {
            dragStartProgress = progress
        }

        let base = dragStartProgress ?? progress
        let span = max(0.02, min(1, viewportSpan))
        let next = base - Double(value.translation.width / max(width, 1)) * span
        return min(1, max(0, next))
    }

    private func sendLiveSeekIfNeeded(_ progress: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastLiveSeekAt) >= 1.0 / 30.0 else { return }
        lastLiveSeekAt = now
        seek(progress)
    }
}

final class PlayerSurfaceNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.backgroundColor = NSColor.black.cgColor
        layer = rootLayer

        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        rootLayer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

struct PlayerSurfaceView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerSurfaceNSView {
        let view = PlayerSurfaceNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerSurfaceNSView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
    }

    static func dismantleNSView(_ nsView: PlayerSurfaceNSView, coordinator: ()) {
        nsView.playerLayer.player = nil
    }
}

struct PreviewPlayerView: View {
    let player: AVPlayer
    let statusMessage: String?
    var dragItemProvider: (() -> NSItemProvider)? = nil
    var onSurfaceHold: (() -> Void)? = nil
    var onSurfaceTap: (() -> Void)? = nil

    @State private var isHoldingSurface = false

    var body: some View {
        ZStack {
            PlayerSurfaceView(player: player)
                .background(.black)

            Color.clear
                .contentShape(Rectangle())

            if let statusMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24, weight: .semibold))
                    Text(statusMessage)
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .foregroundStyle(.white.opacity(0.82))
                .padding(18)
                .frame(maxWidth: 360)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isHoldingSurface else { return }
                    isHoldingSurface = true
                    onSurfaceHold?()
                }
                .onEnded { value in
                    let isTap = abs(value.translation.width) < 4 && abs(value.translation.height) < 4
                    if isTap {
                        onSurfaceTap?()
                    }
                    isHoldingSurface = false
                }
        )
        .fullResolutionImageDrag(dragItemProvider)
        .help(dragItemProvider == nil ? "点击播放/暂停" : "点击播放/暂停，按住拖出当前帧")
    }
}

struct WaveformControlBar: View {
    let samples: [Double]?
    let progress: Double
    let timecodeText: String
    let isPlaying: Bool
    let togglePlayback: () -> Void
    let seek: (Double) -> Void
    var sceneCuts: [Double] = []
    var inPoint: Double? = nil
    var outPoint: Double? = nil
    var prevScene: (() -> Void)? = nil
    var nextScene: (() -> Void)? = nil
    var stepBack: (() -> Void)? = nil
    var stepForward: (() -> Void)? = nil
    var onScreenshot: (() -> Void)? = nil
    var onAnnotate: (() -> Void)? = nil
    var viewportStart: Double = 0
    var viewportSpan: Double = 1
    var duration: Double = 0
    var zoomLevel: Double = 1
    var panViewport: ((Double) -> Void)? = nil
    var zoomViewport: ((Double, Double) -> Void)? = nil
    var resetViewport: (() -> Void)? = nil

    var body: some View {
        AudioWaveformView(
            samples: samples,
            progress: progress,
            seek: seek,
            sceneCuts: sceneCuts,
            inPoint: inPoint,
            outPoint: outPoint,
            viewportStart: viewportStart,
            viewportSpan: viewportSpan,
            duration: duration,
            panViewport: panViewport,
            zoomViewport: zoomViewport
        )
        .frame(maxWidth: .infinity)
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            navButton(icon: "backward.end.fill", help: "上一个场景", action: prevScene)
            navButton(icon: "gobackward.1", help: "后退一帧", action: stepBack)

            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "暂停" : "播放")

            navButton(icon: "goforward.1", help: "前进一帧", action: stepForward)
            navButton(icon: "forward.end.fill", help: "下一个场景", action: nextScene)

            Text(timecodeText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
                .frame(minWidth: 72, alignment: .center)

            Spacer()

            if let fn = onScreenshot {
                Button(action: fn) { Label("截图", systemImage: "camera.fill") }
                    .help("截取当前帧")
            }
            if let fn = onAnnotate {
                Button(action: fn) { Label("批注", systemImage: "text.bubble.fill") }
                    .help("添加批注")
            }
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

    private func shouldPan(translation: CGFloat) -> Bool {
        panViewport != nil && viewportSpan < 0.999 && abs(translation) > 6
    }
}

struct SceneCutMarkersCanvas: View {
    let sceneCuts: [Double]

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0, !sceneCuts.isEmpty else { return }

            var drawnColumns = Set<Int>()
            for cut in sceneCuts {
                let clamped = min(1, max(0, cut))
                let x = size.width * CGFloat(clamped)
                let column = Int(x.rounded())
                guard drawnColumns.insert(column).inserted else { continue }

                var line = Path()
                line.addRect(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height))
                context.fill(line, with: .color(.white.opacity(0.52)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct TimelineCaptureMarker: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "camera.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Design.captureFrameAccent)
                .frame(width: 14, height: 11)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.62))
                )
                .overlay {
                    Capsule()
                        .stroke(Design.captureFrameAccent.opacity(0.72), lineWidth: 0.8)
                }

            Rectangle()
                .fill(Design.captureFrameAccent.opacity(0.92))
                .frame(width: 1.5, height: 6)
        }
        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        .allowsHitTesting(false)
    }
}

struct TimelineTicksCanvas: View {
    let duration: Double
    let viewportStart: Double
    let viewportSpan: Double

    var body: some View {
        Canvas { context, size in
            guard duration > 0, size.width > 0, viewportSpan > 0 else { return }

            let start = viewportStart * duration
            let visibleDuration = max(0.01, viewportSpan * duration)
            let end = min(duration, start + visibleDuration)
            let interval = tickInterval(for: visibleDuration, width: size.width)
            var tick = ceil(start / interval) * interval

            while tick <= end + 0.001 {
                let x = CGFloat((tick - start) / visibleDuration) * size.width
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: 6))
                context.stroke(line, with: .color(.white.opacity(0.42)), lineWidth: 1)

                let label = Text(clockText(tick))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.56))
                context.draw(label, at: CGPoint(x: min(max(x + 18, 18), size.width - 18), y: 13))
                tick += interval
            }
        }
        .allowsHitTesting(false)
    }

    private func tickInterval(for visibleDuration: Double, width: CGFloat) -> Double {
        let targetCount = max(2, Double(width / 92))
        let raw = visibleDuration / targetCount
        let options: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800]
        return options.first(where: { $0 >= raw }) ?? 3600
    }
}

/// 将双指水平滑动转换为时间线左右平移，同时穿透鼠标拖拽和捏合手势。
struct ScrollPanLayer: NSViewRepresentable {
    var panViewport:  ((Double) -> Void)?
    var viewportSpan: Double

    func makeNSView(context: Context) -> PanCapture {
        let view = PanCapture()
        view.installMonitor()
        return view
    }

    func updateNSView(_ v: PanCapture, context: Context) {
        v.panViewport  = panViewport
        v.viewportSpan = viewportSpan
    }

    static func dismantleNSView(_ nsView: PanCapture, coordinator: ()) {
        nsView.removeMonitor()
    }

    final class PanCapture: NSView {
        var panViewport:  ((Double) -> Void)?
        var viewportSpan: Double = 1.0
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.processScrollWheel(event) ?? event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            removeMonitor()
        }

        private func processScrollWheel(_ event: NSEvent) -> NSEvent? {
            guard event.window === window else { return event }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return event }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard panViewport != nil, abs(dx) > abs(dy) * 0.5, abs(dx) > 0.5 else { return event }

            let fraction = -Double(dx) / Double(max(bounds.width, 1)) * viewportSpan
            panViewport?(fraction)
            return nil
        }
    }
}
