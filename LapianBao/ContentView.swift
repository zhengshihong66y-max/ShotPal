//
//  ContentView.swift
//  LapianBao
//
//  Created by 郑士泓 on 2026/5/24.
//

import SwiftUI
import AVFoundation
import AppKit
import Combine

private enum Design {
    static let windowInset: CGFloat = 8
    static let windowRadius: CGFloat = 30
    static let panelSpacing: CGFloat = windowInset
    static let panelRadius: CGFloat = windowRadius - windowInset
    static let innerRadius: CGFloat = 18
    static let itemRadius: CGFloat = 12
}

private enum PreviewTab: String, CaseIterable {
    case frames = "提取画面"
    case audio  = "提取声音"
    case content = "提取内容"
}

private enum AppWorkspace: String, CaseIterable, Identifiable {
    case home
    case frames
    case audio
    case content

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "主页"
        case .frames: return "画面"
        case .audio: return "声音"
        case .content: return "内容"
        }
    }

    var icon: String {
        switch self {
        case .home: return "play.rectangle.fill"
        case .frames: return "photo.on.rectangle.angled"
        case .audio: return "waveform"
        case .content: return "text.quote"
        }
    }
}

private enum PreviewKeyboardCommand {
    case togglePlayback
    case pause
    case shuttleForward
    case shuttleBackward
    case stepForward
    case stepBackward
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.configureIfNeeded(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.configureIfNeeded(nsView.window)
        }
    }

    final class Coordinator {
        private weak var configuredWindow: NSWindow?

        func configureIfNeeded(_ window: NSWindow?) {
            guard let window, configuredWindow !== window else { return }
            configuredWindow = window
            window.styleMask.remove([.titled, .closable, .miniaturizable])
            window.styleMask.insert(.resizable)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.isMovableByWindowBackground = false
        }
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct PreviewKeyboardHandler: NSViewRepresentable {
    let handle: (PreviewKeyboardCommand) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(handle: handle)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitor()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handle = handle
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var handle: (PreviewKeyboardCommand) -> Bool
        private var monitor: Any?
        private var pressedKeyCodes = Set<UInt16>()

        init(handle: @escaping (PreviewKeyboardCommand) -> Bool) {
            self.handle = handle
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                self?.process(event) ?? event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func process(_ event: NSEvent) -> NSEvent? {
            if isEditingText {
                return event
            }

            if event.type == .keyUp {
                pressedKeyCodes.remove(event.keyCode)
                return event
            }

            pressedKeyCodes.insert(event.keyCode)

            guard let command = command(for: event) else {
                return event
            }

            return handle(command) ? nil : event
        }

        private var isEditingText: Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else { return false }
            return responder is NSTextView || responder is NSTextField
        }

        private func command(for event: NSEvent) -> PreviewKeyboardCommand? {
            switch event.keyCode {
            case 49:
                return .togglePlayback
            case 40:
                return .pause
            case 37:
                return pressedKeyCodes.contains(40) ? .stepForward : .shuttleForward
            case 38:
                return pressedKeyCodes.contains(40) ? .stepBackward : .shuttleBackward
            case 124:
                return .stepForward
            case 123:
                return .stepBackward
            default:
                return nil
            }
        }
    }
}

private enum WindowControlAction {
    case close
    case minimize
    case fullscreen
}

private struct WindowControlButton: View {
    let color: Color
    let systemImage: String
    let action: WindowControlAction
    let showsSymbol: Bool

    var body: some View {
        Button {
            perform(action)
        } label: {
            Circle()
                .fill(color)
                .frame(width: 13, height: 13)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(.black.opacity(showsSymbol ? 0.48 : 0))
                }
        }
        .buttonStyle(.plain)
    }

    private func perform(_ action: WindowControlAction) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }

        switch action {
        case .close:
            window.close()
        case .minimize:
            window.miniaturize(nil)
        case .fullscreen:
            window.toggleFullScreen(nil)
        }
    }
}

private struct AudioWaveformView: View {
    let samples: [Double]?
    let progress: Double
    let seek: (Double) -> Void
    var sceneCuts: [Double] = []

    @State private var isDragging = false
    @State private var draftProgress: Double?

    private let placeholderSamples: [Double] = (0..<72).map { index in
        0.14 + 0.10 * abs(sin(Double(index) * 0.46))
    }

    var body: some View {
        let displayedProgress = draftProgress ?? progress

        GeometryReader { proxy in
            Canvas { context, size in
                let values = samples ?? placeholderSamples

                guard !values.isEmpty else {
                    let rect = CGRect(x: 0, y: size.height / 2, width: size.width, height: 1)
                    context.fill(Path(rect), with: .color(.white.opacity(0.18)))
                    return
                }

                let step = size.width / CGFloat(values.count)
                let barWidth = max(1.4, step * 0.58)

                for (index, value) in values.enumerated() {
                    let normalized = max(0.04, min(1, value))
                    let barHeight = CGFloat(normalized) * size.height * 0.84
                    let x = CGFloat(index) * step + (step - barWidth) / 2
                    let y = (size.height - barHeight) / 2
                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)

                    let barProgress = CGFloat(index) / CGFloat(values.count)
                    let color: Color = samples == nil
                        ? .white.opacity(0.16)
                        : (barProgress <= CGFloat(displayedProgress)
                            ? .white.opacity(0.88)
                            : .white.opacity(0.28))

                    var path = Path()
                    path.addRoundedRect(
                        in: rect,
                        cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                    )
                    context.fill(path, with: .color(color))
                }

                if samples != nil, size.width > 0 {
                    let headX = size.width * CGFloat(displayedProgress)
                    var headPath = Path()
                    headPath.addRoundedRect(
                        in: CGRect(x: headX - 1, y: 2, width: 2, height: size.height - 4),
                        cornerSize: CGSize(width: 1, height: 1)
                    )
                    context.fill(headPath, with: .color(.white.opacity(0.95)))
                }

                var drawnCutColumns = Set<Int>()
                for cut in sceneCuts where size.width > 0 {
                    let x = size.width * CGFloat(cut)
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
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        draftProgress = progressFrom(location: value.location, width: proxy.size.width)
                    }
                    .onEnded { value in
                        let final = progressFrom(location: value.location, width: proxy.size.width)
                        draftProgress = nil
                        isDragging = false
                        seek(final)
                    }
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

    private func progressFrom(location: CGPoint, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, Double(location.x / width)))
    }
}

private final class PlayerSurfaceNSView: NSView {
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

private struct PlayerSurfaceView: NSViewRepresentable {
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
}

private struct PreviewPlayerView: View {
    let player: AVPlayer
    let statusMessage: String?

    var body: some View {
        ZStack {
            PlayerSurfaceView(player: player)
                .background(.black)

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
        .aspectRatio(16 / 9, contentMode: .fit)
    }
}

private struct WaveformControlBar: View {
    let samples: [Double]?
    let progress: Double
    let timecodeText: String
    let isPlaying: Bool
    let togglePlayback: () -> Void
    let seek: (Double) -> Void
    var sceneCuts: [Double] = []

    var body: some View {
        HStack(spacing: 10) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "暂停" : "播放")

            Text(timecodeText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)

            AudioWaveformView(
                samples: samples,
                progress: progress,
                seek: seek,
                sceneCuts: sceneCuts
            )
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SceneCutMarkersCanvas: View {
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

                var triangle = Path()
                triangle.move(to: CGPoint(x: x - 3.5, y: 0))
                triangle.addLine(to: CGPoint(x: x + 3.5, y: 0))
                triangle.addLine(to: CGPoint(x: x, y: 6))
                triangle.closeSubpath()
                context.fill(triangle, with: .color(Color.orange.opacity(0.92)))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FrameScrubberView: View {
    let frames: [NSImage]?
    let progress: Double
    let timecodeText: String
    let sceneCuts: [Double]
    let isPlaying: Bool
    let togglePlayback: () -> Void
    let seek: (Double) -> Void
    var screenshotMarkers: [Double] = []
    var annotationMarkers: [Double] = []

    @State private var draftProgress: Double?

    var body: some View {
        let dp = draftProgress ?? progress

        HStack(spacing: 10) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "暂停" : "播放")

            Text(timecodeText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let headX = min(max(width * CGFloat(dp), 0), width - 2.5)

                ZStack(alignment: .leading) {
                    // Bottom layer: frame strip or shimmer placeholder
                    if let frames, !frames.isEmpty {
                        HStack(spacing: 0) {
                            ForEach(0..<frames.count, id: \.self) { i in
                                Image(nsImage: frames[i])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: width / CGFloat(frames.count), height: height)
                                    .clipped()
                            }
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

                    // Darkening overlay for played region (right side)
                    let playedWidth = width * CGFloat(dp)
                    Rectangle()
                        .fill(Color.black.opacity(0.28))
                        .frame(width: max(0, width - playedWidth))
                        .offset(x: playedWidth)

                    SceneCutMarkersCanvas(sceneCuts: sceneCuts)

                    ForEach(Array(screenshotMarkers.enumerated()), id: \.offset) { _, marker in
                        Image(systemName: "camera.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                            .offset(x: width * CGFloat(marker) - 4, y: height - 15)
                    }

                    ForEach(Array(annotationMarkers.enumerated()), id: \.offset) { _, marker in
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 7, height: 7)
                            .offset(x: width * CGFloat(marker) - 3.5, y: 5)
                    }

                    // Playhead
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2.5, height: height)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .offset(x: headX - 1.25)
                }
                .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            draftProgress = min(1, max(0, Double(value.location.x / width)))
                        }
                        .onEnded { value in
                            let final = min(1, max(0, Double(value.location.x / width)))
                            draftProgress = nil
                            seek(final)
                        }
                )
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 56)
    }
}

private struct SimpleProgressBar: View {
    let progress: Double
    let timecodeText: String
    let isPlaying: Bool
    let togglePlayback: () -> Void
    let seek: (Double) -> Void

    @State private var draftProgress: Double?

    var body: some View {
        let dp = draftProgress ?? progress

        HStack(spacing: 10) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "暂停" : "播放")

            Text(timecodeText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                let width = geo.size.width
                let thumbOffset = min(max(width * CGFloat(dp) - 7, 0), width - 14)

                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 4)

                    // Played
                    Capsule()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: max(0, width * CGFloat(dp)), height: 4)

                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .offset(x: thumbOffset)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            draftProgress = min(1, max(0, Double(value.location.x / width)))
                        }
                        .onEnded { value in
                            let final = min(1, max(0, Double(value.location.x / width)))
                            draftProgress = nil
                            seek(final)
                        }
                )
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 56)
    }
}

private struct SceneCutTile: View {
    let thumbnailImage: NSImage?
    let timeLabel: String
    var isExported = false
    var isScreenshot = false
    var isSelected = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                if let thumbnailImage {
                    Image(nsImage: thumbnailImage)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.08)
                }

                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .frame(height: 22)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                Text(timeLabel)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .padding(5)

                if isScreenshot {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : (isExported ? 1.7 : 1))
            }
        }
        .buttonStyle(.plain)
    }

    private var borderColor: Color {
        if isSelected { return .white.opacity(0.72) }
        if isExported || isScreenshot { return .orange.opacity(0.92) }
        return .white.opacity(0.10)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage("mediaGridSize") private var mediaGridSize = 1
    @AppStorage("appWorkspace") private var appWorkspaceRawValue = AppWorkspace.home.rawValue
    @AppStorage("isSidebarCollapsed") private var isSidebarCollapsed = false
    @AppStorage("mediaPanelWidth") private var mediaPanelWidth = 340.0
    @State private var isHoveringWindowControls = false
    @State private var renamingTag: String? = nil
    @State private var renameInput = ""
    @State private var hoveredVideoPath: String? = nil
    @State private var tagPopoverVideoPath: String? = nil
    @State private var isImportSheetPresented = false
    @State private var importURLText = ""
    @State private var importEndpointText = ""
    @State private var isShowingImportAdvanced = false
    @State private var mediaPanelDragStartWidth: Double?

    private var appWorkspace: AppWorkspace {
        get { AppWorkspace(rawValue: appWorkspaceRawValue) ?? .home }
        nonmutating set { appWorkspaceRawValue = newValue.rawValue }
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 900

            ZStack {
                backgroundGradient

                mainLayout(isCompact: isCompact)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Design.windowInset)
            }
            .ignoresSafeArea(.container, edges: .top)
            .clipShape(RoundedRectangle(cornerRadius: Design.windowRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.windowRadius, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
        }
        .background(WindowConfigurator())
        .frame(minWidth: 720, minHeight: 500)
        .alert("重命名标签", isPresented: Binding(
            get: { renamingTag != nil },
            set: { if !$0 { renamingTag = nil } }
        )) {
            TextField("新标签名", text: $renameInput)
            Button("确认") {
                if let old = renamingTag {
                    libraryStore.renameGlobalTag(old, to: renameInput)
                }
                renamingTag = nil
            }
            Button("取消", role: .cancel) { renamingTag = nil }
        } message: {
            Text("重命名后，所有含此标签的视频都会同步更新")
        }
        .sheet(isPresented: $isImportSheetPresented) {
            importSheet
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.09, blue: 0.11),
                Color(red: 0.14, green: 0.16, blue: 0.18),
                Color(red: 0.05, green: 0.06, blue: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func mainLayout(isCompact: Bool) -> some View {
        HStack(spacing: Design.panelSpacing) {
            sidebar
                .frame(width: isSidebarCollapsed ? 56 : (isCompact ? 190 : 272))

            if isCompact {
                VStack(spacing: Design.panelSpacing) {
                    workspaceView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    videoGrid(isCompact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HStack(spacing: Design.panelSpacing) {
                    videoGrid(isCompact: false)
                        .frame(width: mediaPanelWidth)
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(.white.opacity(0.001))
                                .frame(width: 8)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            let startWidth = mediaPanelDragStartWidth ?? mediaPanelWidth
                                            mediaPanelDragStartWidth = startWidth
                                            mediaPanelWidth = min(520, max(260, startWidth + value.translation.width))
                                        }
                                        .onEnded { _ in
                                            mediaPanelDragStartWidth = nil
                                        }
                                )
                        }

                    workspaceView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var workspaceView: some View {
        switch appWorkspace {
        case .home:
            PreviewPanelView()
        case .frames:
            FramesWorkspaceView(goHome: jumpToVideo)
        case .audio:
            AudioWorkspaceView(goHome: jumpToVideo)
        case .content:
            ContentWorkspaceView(goHome: jumpToVideo)
        }
    }

    private func jumpToVideo(path: String, time: Double) {
        libraryStore.selectVideo(path: path)
        appWorkspace = .home
        NotificationCenter.default.post(
            name: .lapianBaoSeekRequest,
            object: nil,
            userInfo: ["path": path, "time": time]
        )
    }

    private var windowControls: some View {
        HStack(spacing: 8) {
            WindowControlButton(color: Color(red: 1.0, green: 0.36, blue: 0.33), systemImage: "xmark", action: .close, showsSymbol: isHoveringWindowControls)
            WindowControlButton(color: Color(red: 1.0, green: 0.78, blue: 0.13), systemImage: "minus", action: .minimize, showsSymbol: isHoveringWindowControls)
            WindowControlButton(color: Color(red: 0.20, green: 0.80, blue: 0.33), systemImage: "plus", action: .fullscreen, showsSymbol: isHoveringWindowControls)
        }
        .padding(6)
        .contentShape(Rectangle())
        .onHover { isHoveringWindowControls = $0 }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            WindowDragRegion()
                .frame(height: 44)
                .padding(.leading, 88)
                .padding(.trailing, 12)

            windowControls
                .padding(.leading, 9)
                .padding(.top, 7)

            sidebarContent
                .padding(.top, 88)
                .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity)
        .glassPanel()
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !isSidebarCollapsed {
                    Text("拉片宝")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isSidebarCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isSidebarCollapsed ? "sidebar.left" : "sidebar.leading")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(isSidebarCollapsed ? "展开侧边栏" : "收起侧边栏")
            }
            .padding(.horizontal, isSidebarCollapsed ? 14 : 14)
            .padding(.bottom, 10)

            if !isSidebarCollapsed {
                sidebarSectionLabel("工作区")
            }

            ForEach(AppWorkspace.allCases) { workspace in
                sidebarItem(
                    icon: workspace.icon,
                    label: workspace.title,
                    isSelected: appWorkspace == workspace
                ) {
                    appWorkspace = workspace
                }
            }

            if !isSidebarCollapsed {
                sidebarSectionLabel("标签")

                sidebarItem(
                    icon: "rectangle.stack.fill",
                    label: "全部素材",
                    isSelected: libraryStore.selectedTags.isEmpty
                ) {
                    libraryStore.selectedTags.removeAll()
                }

                ForEach(libraryStore.allTags, id: \.self) { tag in
                    let isSelected = libraryStore.selectedTags.contains(tag)
                    sidebarItem(
                        icon: isSelected ? "tag.fill" : "tag",
                        label: tag,
                        isSelected: isSelected
                    ) {
                        libraryStore.toggleTagSelection(tag)
                    }
                    .contextMenu {
                        Button {
                            renamingTag = tag
                            renameInput = tag
                        } label: { Label("重命名", systemImage: "pencil") }
                        Divider()
                        Button(role: .destructive) {
                            libraryStore.removeGlobalTag(tag)
                        } label: { Label("从所有视频中删除", systemImage: "trash") }
                    }
                }
            }

            Spacer()

            if !libraryStore.selectedTags.isEmpty, !isSidebarCollapsed {
                Text("已选 \(libraryStore.selectedTags.count) 个标签（AND）")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }

            if !isSidebarCollapsed {
                Text("\(libraryStore.videos.count) 个视频")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func sidebarSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }

    private func sidebarItem(
        icon: String,
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                if !isSidebarCollapsed {
                    Text(label)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous)
                        .fill(.white.opacity(0.10))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private func videoGrid(isCompact: Bool) -> some View {
        let tileWidth = tileWidth(isCompact: isCompact)
        let columns = [
            GridItem(.adaptive(minimum: tileWidth, maximum: tileWidth + 34), spacing: 10)
        ]

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("素材库")
                    .font(.title2.bold())

                Spacer()

                sortMenu
                gridSizeControl
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    importTile
                    ForEach(libraryStore.filteredVideos) { video in
                        videoTile(video)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .contentPanel()
    }

    private var sortMenu: some View {
        Menu {
            Section("排序方式") {
                ForEach(VideoSortOption.allCases) { option in
                    Button {
                        libraryStore.setSort(option: option)
                    } label: {
                        Label(option.title, systemImage: libraryStore.sortOption == option ? "checkmark" : "")
                    }
                }
            }

            Section("方向") {
                ForEach(VideoSortDirection.allCases) { direction in
                    Button {
                        libraryStore.setSort(direction: direction)
                    } label: {
                        Label(direction.title, systemImage: libraryStore.sortDirection == direction ? "checkmark" : direction.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 28)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .help("排序")
    }

    private var importTile: some View {
        Button {
            importEndpointText = libraryStore.instagramImportEndpoint
            autoFillClipboardURL()
            isImportSheetPresented = true
        } label: {
            ZStack {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(.white.opacity(0.03))
            .contentShape(RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous)
                    .stroke(.white.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(.plain)
    }

    private func autoFillClipboardURL() {
        guard
            let clip = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !clip.isEmpty,
            let url = URL(string: clip),
            LibraryStore.platformName(for: url) != nil
        else { return }
        importURLText = clip
    }

    private var importSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("下载视频")
                    .font(.title2.bold())
                Spacer()
                Button {
                    isImportSheetPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("粘贴 Instagram、YouTube、小红书、Bilibili 或抖音链接…", text: $importURLText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onSubmit {
                        guard !importURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isImporting else { return }
                        libraryStore.saveInstagramImportEndpoint(importEndpointText)
                        libraryStore.importRemoteVideo(from: importURLText)
                    }

                if !importURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: platformIconName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(detectedImportPlatform)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 2)
                }
            }

            if let job = libraryStore.remoteImportJob {
                importJobStatus(job)
            }

            HStack(alignment: .bottom) {
                Button {
                    isShowingImportAdvanced.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isShowingImportAdvanced ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                        Text("高级设置")
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button("取消") {
                    isImportSheetPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    libraryStore.saveInstagramImportEndpoint(importEndpointText)
                    libraryStore.importRemoteVideo(from: importURLText)
                } label: {
                    HStack(spacing: 6) {
                        if isImporting {
                            ProgressView().controlSize(.small)
                        }
                        Text(isImporting ? "下载中…" : "下载")
                            .fontWeight(.semibold)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(importURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
            }

            if isShowingImportAdvanced {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("自定义下载 API（可选）")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("http://localhost:8080/download", text: $importEndpointText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Text("若不填，将自动使用本机 yt-dlp。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private var detectedImportPlatform: String {
        guard
            let url = URL(string: importURLText.trimmingCharacters(in: .whitespacesAndNewlines)),
            let platform = LibraryStore.platformName(for: url)
        else { return "等待识别平台" }
        return platform
    }

    private var platformIconName: String {
        switch detectedImportPlatform {
        case "Instagram": return "camera"
        case "YouTube":   return "play.rectangle.fill"
        case "小红书":    return "book.pages.fill"
        case "Bilibili":  return "tv.fill"
        case "抖音":      return "music.note.tv.fill"
        default:          return "link"
        }
    }

    private var isImporting: Bool {
        switch libraryStore.remoteImportJob?.status {
        case .importing, .transcoding: return true
        default: return false
        }
    }

    @ViewBuilder
    private func importJobStatus(_ job: RemoteImportJob) -> some View {
        switch job.status {
        case .idle:
            EmptyView()

        case .importing:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if job.downloadProgress == nil {
                        ProgressView().controlSize(.small)
                    }
                    Text("正在下载 \(job.platform)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let p = job.downloadProgress {
                        Text("\(Int(p * 100))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if let p = job.downloadProgress {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .tint(.white.opacity(0.75))
                        .animation(.linear(duration: 0.2), value: p)
                }
            }

        case .transcoding:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("正在转码为 H.264…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("原始视频使用了 VP9 / AV1 编码，macOS 不支持直接播放，正在自动转换。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

        case let .succeeded(filename):
            Label(filename, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

        case let .failed(message):
            ScrollView {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 80)
            .overlay(alignment: .topLeading) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding(.leading, 18)
        }
    }

    private var gridSizeControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { Double(mediaGridSize) },
                    set: { mediaGridSize = Int($0.rounded()) }
                ),
                in: 0...2
            )
            .frame(width: 86)
            .controlSize(.small)
            .help("网格大小")

            Image(systemName: "square.grid.2x2")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tileWidth(isCompact: Bool) -> Double {
        let widths = isCompact ? [106.0, 136.0, 166.0] : [112.0, 152.0, 192.0]
        let index = min(max(mediaGridSize, 0), widths.count - 1)
        return widths[index]
    }

    private func videoTile(_ video: VideoItem) -> some View {
        let isSelected = libraryStore.selectedVideo == video

        return Button {
            libraryStore.selectedVideo = video
        } label: {
            ZStack(alignment: .bottomLeading) {
                // thumbnail に依存しないコンテンツだけ ZStack に置く
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: .black.opacity(0.48), location: 0.65),
                        .init(color: .black.opacity(0.82), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .bottom) {
                        Text(video.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)

                        Spacer()

                        if let duration = durationTextIfReady(for: video) {
                            Text(duration)
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }

                    let tags = libraryStore.tagsByVideoPath[video.url.path, default: []]
                    if !tags.isEmpty {
                        Text(tags.prefix(2).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }
                .padding(9)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background {
                // 封面作为 background，不参与 ZStack 尺寸计算
                if let image = thumbnailImage(for: video) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black.opacity(0.32)
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous)
                    .stroke(isSelected ? .white.opacity(0.42) : .white.opacity(0.10), lineWidth: isSelected ? 1.5 : 1)
            }
            .shadow(color: .black.opacity(0.32), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredVideoPath = hovering ? video.url.path : nil
            }
        }
        .overlay(alignment: .topTrailing) {
            if hoveredVideoPath == video.url.path {
                Button {
                    tagPopoverVideoPath = (tagPopoverVideoPath == video.url.path) ? nil : video.url.path
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("更多")
                .popover(isPresented: Binding(
                    get: { tagPopoverVideoPath == video.url.path },
                    set: { if !$0 { tagPopoverVideoPath = nil } }
                ), arrowEdge: .trailing) {
                    tagEditorPopover(for: video)
                }
                .padding(6)
                .transition(.opacity)
            }
        }
    }

    private func tagEditorPopover(for video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("标签")
                .font(.headline)

            tagChips(for: video)

            HStack {
                TextField("添加标签", text: $libraryStore.tagInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { libraryStore.addTag(to: video) }

                Button {
                    libraryStore.addTag(to: video)
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(libraryStore.tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(minWidth: 200)
    }

    private func thumbnailImage(for video: VideoItem) -> NSImage? {
        libraryStore.thumbnailImageByVideoPath[video.url.path]
    }

    private func durationTextIfReady(for video: VideoItem) -> String? {
        guard let duration = libraryStore.durationByVideoPath[video.url.path] else { return nil }
        return formatDuration(duration)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    private func tagChips(for video: VideoItem) -> some View {
        let tags = libraryStore.tagsByVideoPath[video.url.path, default: []]

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if tags.isEmpty {
                    Text("未分类")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.caption.weight(.medium))
                            Button {
                                libraryStore.removeTag(tag, from: video)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("删除标签")
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 6)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - PreviewPanelView

// MARK: - PreviewController
/// 持有 AVPlayer、Timer 和所有播放状态。作为 @StateObject 存在，
/// Timer 触发时只有 PreviewPanelView 重渲染，ScenePanelView 完全不受影响。
@MainActor
private final class PreviewController: ObservableObject {
    // ── Published（Timer 驱动，每 250ms 可能变化）────────────────
    @Published var isPlaying     = false
    @Published var elapsed       = 0.0
    @Published var duration      = 0.0
    @Published var progress      = 0.0
    @Published var frameRate     = 30.0
    @Published var playbackRate  = 0.0
    @Published var playbackMessage: String?

    let player = AVPlayer()

    // 由 PreviewPanelView.onAppear 注入，weak 避免循环引用
    weak var libraryStore: LibraryStore?

    private(set) var currentVideoPath: String?
    private var cancellables = Set<AnyCancellable>()
    private var frameRateTask: Task<Void, Never>?
    /// AVPlayer 原生周期观察者：只在播放期间触发，暂停/停止后完全静默，
    /// 消除了 Combine Timer 在暂停时的无效调用开销。
    private var timeObserverToken: Any?

    init() {
        // 周期观察者每 250ms 触发一次（仅播放中），取代 Combine Timer
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] _ in
            // addPeriodicTimeObserver 的 block 是 nonisolated，
            // 用 Task @MainActor 切回 actor，实际已在 main queue 上故无线程切换开销
            Task { @MainActor [weak self] in self?.updateProgress() }
        }

        NotificationCenter.default
            .publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleEnd() }
            .store(in: &cancellables)
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
    }

    // MARK: – 加载视频

    func loadVideo(_ video: VideoItem?) {
        frameRateTask?.cancel()
        frameRateTask = nil

        guard let video else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            isPlaying = false; elapsed = 0; duration = 0; progress = 0
            frameRate = 30; playbackRate = 0; playbackMessage = nil
            currentVideoPath = nil
            return
        }

        currentVideoPath = video.url.path
        loadFrameRate(for: video)

        let store = libraryStore
        if let msg = store?.playbackSupportByVideoPath[video.url.path]?.message {
            player.replaceCurrentItem(with: nil)
            isPlaying = false; elapsed = 0
            duration = store?.durationByVideoPath[video.url.path] ?? 0
            progress = 0; playbackRate = 0; playbackMessage = msg
            store?.loadWaveform(for: video)
            store?.loadFrameStrip(for: video)
            store?.loadCachedSceneCuts(for: video)
            return
        }

        playbackMessage = nil
        player.replaceCurrentItem(with: AVPlayerItem(url: video.url))
        elapsed = 0
        duration = store?.durationByVideoPath[video.url.path] ?? 0
        progress = 0
        setRate(1)
        isPlaying = true
        store?.loadWaveform(for: video)
        store?.loadFrameStrip(for: video)
        store?.loadCachedSceneCuts(for: video)
    }

    func applyPlaybackSupportIfNeeded() {
        guard
            let path = currentVideoPath,
            let msg = libraryStore?.playbackSupportByVideoPath[path]?.message
        else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false; elapsed = 0
        duration = libraryStore?.durationByVideoPath[path] ?? duration
        progress = 0; playbackRate = 0; playbackMessage = msg
    }

    // MARK: – 播放控制

    func togglePlayback() {
        if isPlaying || abs(playbackRate) > 0.001 { pause() } else { setRate(1) }
    }

    func pause() {
        player.pause(); playbackRate = 0; isPlaying = false
    }

    func setRate(_ rate: Double) {
        guard player.currentItem != nil else { return }
        player.rate = Float(rate); playbackRate = rate
        isPlaying = abs(rate) > 0.001
    }

    func stepFrame(by direction: Int) {
        pause()
        seekToSeconds(elapsed + Double(direction) / max(frameRate, 1))
    }

    // MARK: – Seek

    func seekToProgress(_ p: Double) {
        let d = effectiveDuration; guard let d, d > 0 else { return }
        seekToSeconds(d * min(1, max(0, p)))
    }

    /// 直接按秒跳转（供 ScenePanelView 调用，不需要传入 duration）
    func seekToSeconds(_ seconds: Double) {
        let d = effectiveDuration; guard let d, d > 0 else { return }
        let t = min(d, max(0, seconds))
        elapsed = t
        progress = min(1, max(0, t / d))
        player.seek(
            to: CMTime(seconds: t, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        )
    }

    // MARK: – Timer & 通知

    private func updateProgress() {
        guard player.currentItem != nil else {
            if isPlaying { isPlaying = false }
            if elapsed != 0 { elapsed = 0 }
            if progress != 0 { progress = 0 }
            return
        }

        if let item = player.currentItem, item.status == .failed {
            if isPlaying { isPlaying = false }
            let msg = item.error?.localizedDescription ?? "这个视频无法播放"
            if playbackMessage != msg { playbackMessage = msg }
            if elapsed != 0 { elapsed = 0 }
            if progress != 0 { progress = 0 }
            return
        }

        if player.currentItem?.status == .readyToPlay, playbackMessage != nil {
            playbackMessage = nil
        }

        if let d = playerDuration() { assign(&duration, d, tol: 0.001) }

        let t = player.currentTime().seconds
        if t.isFinite, duration > 0 {
            let next = min(max(0, t), duration)
            assign(&elapsed, next, tol: 0.001)
            assign(&progress, min(1, max(0, next / duration)), tol: 0.0001)
        }

        let nextRate = Double(player.rate)
        assign(&playbackRate, nextRate, tol: 0.0001)
        let nextPlaying = abs(nextRate) > 0.001
        if isPlaying != nextPlaying { isPlaying = nextPlaying }
    }

    private func handleEnd() {
        isPlaying = false; playbackRate = 0; progress = 0; elapsed = 0
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func loadFrameRate(for video: VideoItem) {
        let path = video.url.path; frameRate = 30
        frameRateTask = Task { [weak self] in
            let fps = await Self.fetchFrameRate(for: video.url)
            guard !Task.isCancelled, self?.currentVideoPath == path else { return }
            self?.frameRate = fps
        }
    }

    nonisolated private static func fetchFrameRate(for url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard
            let tracks = try? await asset.loadTracks(withMediaType: .video),
            let track = tracks.first,
            let fps = try? await track.load(.nominalFrameRate),
            fps.isFinite, fps > 0
        else { return 30 }
        return Double(fps)
    }

    // MARK: – 工具

    var effectiveDuration: Double? {
        duration > 0 ? duration : playerDuration()
    }

    private func playerDuration() -> Double? {
        guard let s = player.currentItem?.duration.seconds, s.isFinite, s > 0 else { return nil }
        return s
    }

    private func assign(_ v: inout Double, _ next: Double, tol: Double) {
        guard abs(v - next) > tol else { return }
        v = next
    }
}

// MARK: - ScenePanelView
private struct SceneGridItem: Identifiable {
    let id: String
    let time: Double
    let cut: SceneCut?
    let sample: SampledFrame?
    let thumbnailImage: NSImage?
    let sceneIndex: Int?
}

/// Equatable 视图：只有 video 或 controller 引用变化时才重新渲染 body。
/// Timer 每 250ms 触发 PreviewController.objectWillChange，
/// PreviewPanelView 重渲后将相同的 (video, controller) 传给本视图，
/// .equatable() 比较相等 → body 完全跳过，场景网格不参与渲染循环。
private struct ScenePanelView: View, Equatable {
    let video: VideoItem
    let controller: PreviewController
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage("sceneGridSize") private var sceneGridSize = 1
    @State private var selectedItemID: String?

    static func == (lhs: ScenePanelView, rhs: ScenePanelView) -> Bool {
        lhs.video == rhs.video && lhs.controller === rhs.controller
    }

    var body: some View {
        let path = video.url.path
        let cuts = libraryStore.sceneCutsByVideoPath[path] ?? []
        let items = sceneGridItems(cuts: cuts)

        VStack(alignment: .leading, spacing: 8) {
            if cuts.isEmpty && libraryStore.sceneDetectionProgress[path] == nil {
                Button {
                    libraryStore.detectSceneCuts(for: video)
                } label: {
                    Label("识别场景", systemImage: "sparkles")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.10))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let progress = libraryStore.sceneDetectionProgress[path] {
                VStack(spacing: 8) {
                    Text("正在识别场景...")
                        .font(.caption.weight(.semibold))
                    ProgressView(value: progress)
                        .frame(maxWidth: 260)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                HStack {
                    Text(videoInfoLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    gridSizeControl
                    Button {
                        if let selectedItemID,
                           let item = items.first(where: { $0.id == selectedItemID }),
                           let cut = item.cut {
                            libraryStore.markSceneFrameExported(video: video, cut: cut, sceneIndex: item.sceneIndex)
                        }
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedItemID == nil)
                }

                let tileWidth = [86.0, 116.0, 150.0][min(max(sceneGridSize, 0), 2)]
                let columns = [GridItem(.adaptive(minimum: tileWidth), spacing: 8)]
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(items) { item in
                            SceneCutTile(
                                thumbnailImage: item.thumbnailImage,
                                timeLabel: item.sample?.kind == .screenshot ? formatDuration(item.time) : sceneDurationLabel(for: item, cuts: cuts),
                                isExported: item.sample?.isExported == true,
                                isScreenshot: item.sample?.kind == .screenshot,
                                isSelected: selectedItemID == item.id
                            ) {
                                selectedItemID = item.id
                                controller.seekToSeconds(item.time)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private var gridSizeControl: some View {
        Slider(
            value: Binding(
                get: { Double(sceneGridSize) },
                set: { sceneGridSize = Int($0.rounded()) }
            ),
            in: 0...2
        )
        .frame(width: 72)
        .controlSize(.small)
        .help("场景网格大小")
    }

    private var videoInfoLine: String {
        let metadata = libraryStore.metadataByVideoPath[video.url.path]
        let specs = [metadata?.frameRateText, metadata?.resolutionText].compactMap { $0 }.joined(separator: " · ")
        return specs.isEmpty ? video.name : "\(video.name)    \(specs)"
    }

    private func sceneGridItems(cuts: [SceneCut]) -> [SceneGridItem] {
        let cutItems = cuts.enumerated().map { index, cut in
            SceneGridItem(
                id: "cut-\(cut.id)",
                time: cut.time,
                cut: cut,
                sample: matchingSample(at: cut.time, kind: .sceneRepresentative),
                thumbnailImage: cut.thumbnailImage,
                sceneIndex: index
            )
        }
        let screenshotItems = libraryStore.sampledFrames(for: video)
            .filter { $0.kind == .screenshot }
            .map {
                SceneGridItem(
                    id: "sample-\($0.id)",
                    time: $0.time,
                    cut: nil,
                    sample: $0,
                    thumbnailImage: NSImage(data: $0.thumbnailData),
                    sceneIndex: $0.sceneIndex
                )
            }
        return (cutItems + screenshotItems).sorted { $0.time < $1.time }
    }

    private func matchingSample(at time: Double, kind: SampledFrame.Kind) -> SampledFrame? {
        libraryStore.sampledFrames(for: video).first {
            $0.kind == kind && abs($0.time - time) < 0.02
        }
    }

    private func sceneDurationLabel(for item: SceneGridItem, cuts: [SceneCut]) -> String {
        guard let index = item.sceneIndex else { return formatDuration(item.time) }
        let end = index + 1 < cuts.count ? cuts[index + 1].time : controller.duration
        return formatFrames(max(0, end - item.time), fps: controller.frameRate)
    }

    private func formatFrames(_ seconds: Double, fps: Double) -> String {
        let frameRate = max(1, Int(fps.rounded()))
        let totalFrames = max(0, Int((seconds * Double(frameRate)).rounded()))
        let wholeSeconds = totalFrames / frameRate
        let frames = totalFrames % frameRate
        if wholeSeconds == 0 { return "\(frames) 帧" }
        return "\(wholeSeconds) 秒 \(String(format: "%02d", frames)) 帧"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - PreviewPanelView
/// 预览面板：使用 @StateObject controller 驱动播放，
/// 场景网格由 ScenePanelView（Equatable）单独渲染，与 Timer 完全解耦。
private struct PreviewPanelView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var controller = PreviewController()
    @Namespace private var tabNamespace
    @State private var activePreviewTab: PreviewTab = .frames
    @State private var annotationText = ""
    @State private var isAnnotationPopoverPresented = false
    @State private var audioInPoint: Double?
    @State private var audioOutPoint: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("预览")
                    .font(.title2.bold())
                Spacer()
                if let selectedVideo = libraryStore.selectedVideo {
                    sceneDetectionControls(for: selectedVideo)
                }
            }

            if let selectedVideo = libraryStore.selectedVideo {
                // 视频画面
                PreviewPlayerView(
                    player: controller.player,
                    statusMessage: controller.playbackMessage
                )

                // Tab 切换栏（液态玻璃胶囊，在时间线上方）
                previewTabSwitcher

                // 动态时间线（随 Tab 变化）
                previewTimeline(for: selectedVideo)

                samplingControls(for: selectedVideo)

                // Tab 内容区
                previewTabContent(for: selectedVideo)

                // 视频信息
                Text(selectedVideo.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 2)

                Spacer(minLength: 0)
            } else {
                ContentUnavailableView(
                    "选择一个视频",
                    systemImage: "play.rectangle",
                    description: Text("点击左侧视频后，会在这里直接播放。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .contentPanel()
        .background {
            PreviewKeyboardHandler(handle: handlePreviewKeyboardCommand)
        }
        // ── Lifecycle & state reactions ──────────────────────────────
        .onAppear {
            controller.libraryStore = libraryStore
            controller.loadVideo(libraryStore.selectedVideo)
        }
        .onChange(of: libraryStore.selectedVideo) { _, newVideo in
            controller.libraryStore = libraryStore
            controller.loadVideo(newVideo)
        }
        .onChange(of: libraryStore.playbackSupportByVideoPath) { _, _ in
            controller.applyPlaybackSupportIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lapianBaoSeekRequest)) { notification in
            guard
                let path = notification.userInfo?["path"] as? String,
                let time = notification.userInfo?["time"] as? Double,
                path == libraryStore.selectedVideo?.url.path
            else { return }
            controller.pause()
            controller.seekToSeconds(time)
        }
    }

    // MARK: – Custom liquid-glass tab switcher

    private var previewTabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(PreviewTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        activePreviewTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(activePreviewTab == tab ? .white : .white.opacity(0.45))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background {
                            if activePreviewTab == tab {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.22),
                                                .white.opacity(0.12)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay {
                                        Capsule()
                                            .stroke(.white.opacity(0.28), lineWidth: 0.5)
                                    }
                                    .shadow(color: .black.opacity(0.30), radius: 6, y: 2)
                                    .matchedGeometryEffect(id: "tabHighlight", in: tabNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(.black.opacity(0.32))
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                }
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: – Timeline & content areas

    @ViewBuilder
    private func previewTimeline(for video: VideoItem) -> some View {
        switch activePreviewTab {
        case .frames:
            FrameScrubberView(
                frames: frameStripImages(for: video),
                progress: controller.progress,
                timecodeText: previewTimecodeText,
                sceneCuts: normalizedSceneCuts(for: video),
                isPlaying: controller.isPlaying,
                togglePlayback: { controller.togglePlayback() },
                seek: { controller.seekToProgress($0) },
                screenshotMarkers: normalizedSampledFrames(for: video),
                annotationMarkers: normalizedAnnotations(for: video)
            )
        case .audio:
            WaveformControlBar(
                samples: libraryStore.waveformSamplesByVideoPath[video.url.path],
                progress: controller.progress,
                timecodeText: previewTimecodeText,
                isPlaying: controller.isPlaying,
                togglePlayback: { controller.togglePlayback() },
                seek: { controller.seekToProgress($0) },
                sceneCuts: normalizedSceneCuts(for: video)
            )
        case .content:
            SimpleProgressBar(
                progress: controller.progress,
                timecodeText: previewTimecodeText,
                isPlaying: controller.isPlaying,
                togglePlayback: { controller.togglePlayback() },
                seek: { controller.seekToProgress($0) }
            )
        }
    }

    @ViewBuilder
    private func samplingControls(for video: VideoItem) -> some View {
        HStack(spacing: 8) {
            Button {
                libraryStore.captureCurrentFrame(video: video, time: controller.elapsed)
            } label: {
                Label("截图", systemImage: "camera.fill")
            }
            .help("截取当前播放帧")

            Button {
                annotationText = ""
                isAnnotationPopoverPresented = true
            } label: {
                Label("批注", systemImage: "text.bubble.fill")
            }
            .popover(isPresented: $isAnnotationPopoverPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("添加批注 \(previewTimecodeText)")
                        .font(.headline)
                    TextEditor(text: $annotationText)
                        .frame(width: 260, height: 96)
                    HStack {
                        Spacer()
                        Button("取消") { isAnnotationPopoverPresented = false }
                        Button("保存") {
                            libraryStore.addAnnotation(video: video, time: controller.elapsed, text: annotationText)
                            isAnnotationPopoverPresented = false
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(14)
            }

            Divider()
                .frame(height: 18)

            Button("In") {
                audioInPoint = controller.elapsed
            }
            .help("设置声音 In 点")

            Button("Out") {
                audioOutPoint = controller.elapsed
            }
            .help("设置声音 Out 点")

            Button {
                if let audioInPoint, let audioOutPoint {
                    libraryStore.exportAudioClip(video: video, inTime: audioInPoint, outTime: audioOutPoint)
                }
            } label: {
                Label("导出声音", systemImage: "waveform.badge.plus")
            }
            .disabled(audioInPoint == nil || audioOutPoint == nil)

            Spacer()

            if let audioInPoint {
                Text("In \(formatDuration(audioInPoint))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let audioOutPoint {
                Text("Out \(formatDuration(audioOutPoint))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private func previewTabContent(for video: VideoItem) -> some View {
        switch activePreviewTab {
        case .frames:
            ScenePanelView(video: video, controller: controller).equatable()
        case .audio:
            EmptyView()
        case .content:
            Text("AI 内容提取功能正在开发中")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
    }

    // MARK: – Scene detection controls

    @ViewBuilder
    private func sceneDetectionControls(for video: VideoItem) -> some View {
        let path = video.url.path
        let hasCuts = libraryStore.sceneCutsByVideoPath[path] != nil

        if let progress = libraryStore.sceneDetectionProgress[path] {
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("\(Int(progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                libraryStore.detectSceneCuts(for: video)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: hasCuts ? "sparkles" : "sparkle")
                        .font(.system(size: 12, weight: .semibold))
                    if hasCuts, let cuts = libraryStore.sceneCutsByVideoPath[path] {
                        Text("\(cuts.count) 个场景")
                            .font(.caption2)
                    } else {
                        Text("识别场景")
                            .font(.caption2)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.thinMaterial)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(hasCuts ? "重新识别场景切点" : "自动识别场景切点")
        }
    }

    // MARK: – Helper views / computed properties

    private func frameStripImages(for video: VideoItem) -> [NSImage]? {
        guard let images = libraryStore.frameStripImagesByVideoPath[video.url.path],
              !images.isEmpty else { return nil }
        return images
    }

    private var previewTimecodeText: String {
        formatTimecode(controller.elapsed, frameRate: controller.frameRate)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatTimecode(_ seconds: Double, frameRate: Double) -> String {
        let fps = max(1, Int(frameRate.rounded()))
        let clampedSeconds = max(0, seconds)
        let totalFrames = Int((clampedSeconds * Double(fps)).rounded(.down))
        let frames = totalFrames % fps
        let totalWholeSeconds = totalFrames / fps
        let hours = totalWholeSeconds / 3600
        let minutes = (totalWholeSeconds % 3600) / 60
        let wholeSeconds = totalWholeSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d:%02d", hours, minutes, wholeSeconds, frames)
        }
        return String(format: "%02d:%02d:%02d", minutes, wholeSeconds, frames)
    }

    private func normalizedSceneCuts(for video: VideoItem) -> [Double] {
        let path = video.url.path
        if let cached = libraryStore.sceneCutProgressesByVideoPath[path] {
            return cached
        }

        guard
            let cuts = libraryStore.sceneCutsByVideoPath[path],
            controller.duration > 0
        else { return [] }
        return cuts.map { min(1, max(0, $0.time / controller.duration)) }
    }

    private func normalizedSampledFrames(for video: VideoItem) -> [Double] {
        guard controller.duration > 0 else { return [] }
        return libraryStore.sampledFrames(for: video)
            .map { min(1, max(0, $0.time / controller.duration)) }
    }

    private func normalizedAnnotations(for video: VideoItem) -> [Double] {
        guard controller.duration > 0 else { return [] }
        return libraryStore.annotations(for: video)
            .map { min(1, max(0, $0.time / controller.duration)) }
    }

    // MARK: – Keyboard control

    private func handlePreviewKeyboardCommand(_ command: PreviewKeyboardCommand) -> Bool {
        guard libraryStore.selectedVideo != nil else { return false }

        switch command {
        case .togglePlayback:
            controller.togglePlayback()
        case .pause:
            controller.pause()
        case .shuttleForward:
            let nextRate = controller.playbackRate > 0 ? min(controller.playbackRate * 2, 8) : 1
            controller.setRate(nextRate)
        case .shuttleBackward:
            let nextRate = controller.playbackRate < 0 ? max(controller.playbackRate * 2, -8) : -1
            controller.setRate(nextRate)
        case .stepForward:
            controller.stepFrame(by: 1)
        case .stepBackward:
            controller.stepFrame(by: -1)
        }

        return true
    }
}

// MARK: - Workspace Pages

private struct FramesWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let goHome: (String, Double) -> Void
    @State private var selectedFrameID: UUID?

    private var selectedFrame: SampledFrame? {
        let frames = libraryStore.collectedFrames
        return frames.first { $0.id == selectedFrameID } ?? frames.first
    }

    var body: some View {
        HStack(spacing: 12) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
                    ForEach(libraryStore.collectedFrames) { frame in
                        Button {
                            selectedFrameID = frame.id
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                if let image = NSImage(data: frame.thumbnailData) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Color.black.opacity(0.24)
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: frame.kind == .screenshot ? "camera.fill" : "photo")
                                    Text(clockText(frame.time))
                                }
                                .font(.caption2.weight(.semibold))
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(6)
                            }
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selectedFrameID == frame.id ? .white.opacity(0.72) : .orange.opacity(0.75), lineWidth: selectedFrameID == frame.id ? 2 : 1.5)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
            }
            .frame(minWidth: 260)

            Divider().opacity(0.2)

            VStack(alignment: .leading, spacing: 12) {
                Text("画面")
                    .font(.title2.bold())

                if let frame = selectedFrame {
                    if let image = NSImage(data: frame.thumbnailData) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Text(frame.videoName)
                        .font(.headline)
                    Text("\(clockText(frame.time)) · \(frame.kind == .screenshot ? "手动截图帧" : "场景代表帧")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ColorSwatches(imageData: frame.thumbnailData)

                    Button {
                        goHome(frame.videoPath, frame.time)
                    } label: {
                        Label("回到原视频", systemImage: "arrowshape.turn.up.left.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ContentUnavailableView("还没有收集画面", systemImage: "photo.on.rectangle", description: Text("在主页点击截图，或导出场景网格帧。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .contentPanel()
    }
}

private struct AudioWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let goHome: (String, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("声音")
                .font(.title2.bold())

            if libraryStore.audioClips.isEmpty {
                ContentUnavailableView("还没有声音片段", systemImage: "waveform", description: Text("在主页设置 In / Out 后导出声音。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(libraryStore.audioClips.sorted { $0.createdAt > $1.createdAt }) { clip in
                            HStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(clip.videoName)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text("\(clockText(clip.inTime)) - \(clockText(clip.outTime)) · \(formatDuration(clip.outTime - clip.inTime))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let filePath = clip.filePath {
                                    Button {
                                        NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
                                    } label: {
                                        Image(systemName: "play.fill")
                                    }
                                    .help("播放片段")
                                }
                                Button {
                                    goHome(clip.videoPath, clip.inTime)
                                } label: {
                                    Label("回到原视频", systemImage: "arrowshape.turn.up.left")
                                }
                            }
                            .buttonStyle(.borderless)
                            .padding(12)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(16)
        .contentPanel()
    }
}

private struct ContentWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let goHome: (String, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("内容")
                    .font(.title2.bold())
                Spacer()
                if let video = libraryStore.selectedVideo {
                    Button {
                        libraryStore.transcribe(video: video)
                    } label: {
                        Label("开始分析", systemImage: "text.badge.plus")
                    }
                    Button {
                        libraryStore.exportTranscriptMarkdown(video: video)
                    } label: {
                        Label("导出 Markdown", systemImage: "doc.text")
                    }
                }
            }

            if let video = libraryStore.selectedVideo {
                let segments = libraryStore.transcriptSegmentsByVideoPath[video.url.path, default: []]
                if case let .running(message) = libraryStore.transcriptStatusByVideoPath[video.url.path] {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if case let .failed(message) = libraryStore.transcriptStatusByVideoPath[video.url.path] {
                    ContentUnavailableView("转写失败", systemImage: "exclamationmark.triangle", description: Text(message))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if segments.isEmpty {
                    ContentUnavailableView("还没有原脚本", systemImage: "text.quote", description: Text("点击开始分析，使用本地 Whisper 生成逐句时间戳。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(segments) { segment in
                                Button {
                                    goHome(segment.videoPath, segment.start)
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(clockText(segment.start))
                                            .font(.caption.monospacedDigit().weight(.semibold))
                                            .foregroundStyle(.orange)
                                            .frame(width: 58, alignment: .leading)
                                        Text(segment.text)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("选择一个视频", systemImage: "play.rectangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .contentPanel()
    }
}

private struct ColorSwatches: View {
    let imageData: Data

    var body: some View {
        let colors = dominantColors()
        VStack(alignment: .leading, spacing: 8) {
            Text("主色")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(color)
                        .frame(width: 42, height: 28)
                }
            }
        }
    }

    private func dominantColors() -> [Color] {
        guard let image = NSImage(data: imageData), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return [.gray.opacity(0.4)]
        }
        let width = 4
        let height = 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [.gray.opacity(0.4)] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: pixels.count, by: 4).prefix(8).map { offset in
            Color(
                red: Double(pixels[offset]) / 255.0,
                green: Double(pixels[offset + 1]) / 255.0,
                blue: Double(pixels[offset + 2]) / 255.0
            )
        }
    }
}

private func clockText(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}

private func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    let m = total / 60
    let s = total % 60
    return m > 0 ? "\(m) 分 \(s) 秒" : "\(s) 秒"
}

private extension Notification.Name {
    static let lapianBaoSeekRequest = Notification.Name("lapianBaoSeekRequest")
}

// MARK: - View extensions

private extension View {
    func contentPanel() -> some View {
        self
            .background(.ultraThinMaterial.opacity(0.52))
            .clipShape(RoundedRectangle(cornerRadius: Design.panelRadius, style: .continuous))
    }

    func glassPanel() -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Design.panelRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.panelRadius, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, x: 0, y: 18)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(LibraryStore())
    }
}
