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
    var playheadTint: Color = Design.timelinePlayheadAccent
    var panViewport: ((Double) -> Void)? = nil
    var zoomViewport: ((Double, Double) -> Void)? = nil

    @State private var dragStartProgress: Double?
    @State private var draftProgress: Double?
    @State private var isHoveringSelection = false
    @State private var lastMagnification: CGFloat = 1
    @State private var lastLiveSeekAt = Date.distantPast

    private let clearSelectionButtonSize: CGFloat = 22
    private let clearSelectionButtonHitSize: CGFloat = 34

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
                            context.fill(Path(rect), with: .color(Design.timelineIOAccent.opacity(0.14)))
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
                        context.stroke(path, with: .color(.white.opacity(0.42)), style: StrokeStyle(lineWidth: 1.2))
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
                            .fill(Design.annotationAccent.opacity(0.88))
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
                            .frame(width: clearSelectionButtonSize, height: clearSelectionButtonSize)
                            .background(.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(x: frame.midX, y: frame.midY)
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
                        if isClearSelectionHit(
                            value.startLocation,
                            focus: min(1, max(0, draftProgress ?? progress)),
                            span: max(0.02, min(1, viewportSpan)),
                            width: proxy.size.width,
                            height: proxy.size.height
                        ) {
                            return
                        }
                        let next = scrubProgress(for: value, width: proxy.size.width)
                        draftProgress = next
                        sendLiveSeekIfNeeded(next)
                    }
                    .onEnded { value in
                        if isClearSelectionHit(
                            value.startLocation,
                            focus: min(1, max(0, progress)),
                            span: max(0.02, min(1, viewportSpan)),
                            width: proxy.size.width,
                            height: proxy.size.height
                        ) {
                            draftProgress = nil
                            dragStartProgress = nil
                            lastLiveSeekAt = .distantPast
                            onClearSelection?()
                            return
                        }
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
        .accessibilityLabel(L10n.text("居中播放头音频波形"))
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

    private func clearSelectionHitFrame(focus: Double, span: Double, width: CGFloat, height: CGFloat) -> CGRect? {
        guard let frame = selectionFrame(focus: focus, span: span, width: width, height: height) else { return nil }
        let size = max(clearSelectionButtonSize, clearSelectionButtonHitSize)
        return CGRect(
            x: frame.midX - size / 2,
            y: frame.midY - size / 2,
            width: size,
            height: size
        )
    }

    private func isClearSelectionHit(
        _ location: CGPoint,
        focus: Double,
        span: Double,
        width: CGFloat,
        height: CGFloat
    ) -> Bool {
        guard onClearSelection != nil else { return false }
        return clearSelectionHitFrame(
            focus: focus,
            span: span,
            width: width,
            height: height
        )?.contains(location) == true
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
        .accessibilityLabel(L10n.text("播放器画面"))
        .accessibilityIdentifier("preview_player_surface")
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
        private var pendingPanDelta = 0.0
        private var isPanFlushScheduled = false
        private var lastPanFlushTime = Date.distantPast
        private let panFrameInterval = 1.0 / 60.0

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
            enqueuePan(fraction)
            return nil
        }

        private func enqueuePan(_ delta: Double) {
            pendingPanDelta += delta

            guard !isPanFlushScheduled else { return }
            let now = Date()
            let elapsed = now.timeIntervalSince(lastPanFlushTime)
            if elapsed >= panFrameInterval {
                flushPendingPan(at: now)
                return
            }

            isPanFlushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (panFrameInterval - elapsed)) { [weak self] in
                self?.flushPendingPan(at: Date())
            }
        }

        private func flushPendingPan(at date: Date) {
            isPanFlushScheduled = false
            let delta = pendingPanDelta
            pendingPanDelta = 0
            lastPanFlushTime = date
            guard abs(delta) > 0.000001 else { return }
            panViewport?(delta)
        }
    }
}
