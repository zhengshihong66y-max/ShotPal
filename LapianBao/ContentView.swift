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

                for cut in sceneCuts where size.width > 0 {
                    let x = size.width * CGFloat(cut)
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

private struct FrameScrubberView: View {
    let frames: [NSImage]?
    let progress: Double
    let timecodeText: String
    let sceneCuts: [Double]
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

                    // Scene cut markers
                    ForEach(Array(sceneCuts.enumerated()), id: \.offset) { _, cut in
                        ZStack(alignment: .top) {
                            Rectangle()
                                .fill(Color.white.opacity(0.52))
                                .frame(width: 1, height: height)
                            Path { p in
                                p.move(to: CGPoint(x: -3.5, y: 0))
                                p.addLine(to: CGPoint(x: 3.5, y: 0))
                                p.addLine(to: CGPoint(x: 0, y: 6))
                                p.closeSubpath()
                            }
                            .fill(Color.orange.opacity(0.92))
                        }
                        .frame(width: 1, height: height)
                        .offset(x: width * CGFloat(cut) - 0.5)
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
    let cut: SceneCut
    let timeLabel: String
    let onTap: () -> Void

    @State private var cachedImage: NSImage?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                Text(timeLabel)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(5)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background {
                if let image = cachedImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .task(id: cut.id) {
            guard cachedImage == nil else { return }
            let data = cut.thumbnailData
            let img = await Task.detached(priority: .utility) {
                NSImage(data: data)
            }.value
            cachedImage = img
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage("mediaGridSize") private var mediaGridSize = 1
    @State private var isHoveringWindowControls = false
    @State private var previewPlayer = AVPlayer()
    @State private var isPreviewPlaying = false
    @State private var previewElapsed = 0.0
    @State private var previewDuration = 0.0
    @State private var previewProgress = 0.0
    @State private var previewFrameRate = 30.0
    @State private var previewPlaybackRate = 0.0
    @State private var previewPlaybackMessage: String?
    @State private var renamingTag: String? = nil
    @State private var renameInput = ""
    @State private var activePreviewTab: PreviewTab = .frames
    @State private var hoveredVideoPath: String? = nil
    @State private var tagPopoverVideoPath: String? = nil
    @State private var isImportSheetPresented = false
    @State private var importURLText = ""
    @State private var importEndpointText = ""
    @State private var isShowingImportAdvanced = false

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
        .onAppear {
            playPreview(libraryStore.selectedVideo)
        }
        .onChange(of: libraryStore.selectedVideo) { _, newVideo in
            playPreview(newVideo)
        }
        .onChange(of: libraryStore.playbackSupportByVideoPath) { _, _ in
            applyPlaybackSupportIfNeeded()
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            updatePreviewProgress()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
        ) { _ in
            handlePreviewEnd()
        }
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
                .frame(width: isCompact ? 190 : 238)

            if isCompact {
                VStack(spacing: Design.panelSpacing) {
                    previewPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    videoGrid(isCompact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HStack(spacing: Design.panelSpacing) {
                    videoGrid(isCompact: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    previewPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            // 素材库 section
            sidebarSectionLabel("素材库")

            sidebarItem(
                icon: "rectangle.stack.fill",
                label: "全部",
                isSelected: libraryStore.selectedTags.isEmpty
            ) {
                libraryStore.selectedTags.removeAll()
            }

            // 标签 section（有标签才显示）
            if !libraryStore.allTags.isEmpty {
                sidebarSectionLabel("标签")

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

            if !libraryStore.selectedTags.isEmpty {
                Text("已选 \(libraryStore.selectedTags.count) 个标签（AND）")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }

            sceneIndexingStatusView
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            Text("\(libraryStore.videos.count) 个视频")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var sceneIndexingStatusView: some View {
        let status = libraryStore.sceneIndexingStatus
        if status.isRunning || status.total > 0 {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: status.isRunning ? "sparkles" : "checkmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(status.isRunning ? "后台识别切点" : "切点缓存完成")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(status.completed)/\(max(status.total, 1))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                ProgressView(value: status.progress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)

                if let name = status.currentVideoName, status.isRunning {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if status.isRunning {
                    Button {
                        libraryStore.stopSceneIndexing()
                    } label: {
                        Label("停止识别", systemImage: "stop.fill")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                    .help("停止后台切点识别")
                }
            }
            .padding(10)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous))
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
                Text(label)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
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
                TextField("粘贴 Instagram 链接…", text: $importURLText)
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

        if platform == "Instagram" {
            return "Instagram"
        }
        return "\(platform) 尚未接入"
    }

    private var platformIconName: String {
        detectedImportPlatform == "Instagram" ? "camera" : "link"
    }

    private var isImporting: Bool {
        if case .importing = libraryStore.remoteImportJob?.status {
            return true
        }
        return false
    }

    @ViewBuilder
    private func importJobStatus(_ job: RemoteImportJob) -> some View {
        switch job.status {
        case .idle:
            EmptyView()
        case .importing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在导入 \(job.platform)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case let .succeeded(filename):
            Label(filename, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
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

    private var previewPanel: some View {
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
                    player: previewPlayer,
                    statusMessage: previewPlaybackMessage
                )

                // Tab 切换栏（在时间线上方）
                previewTabSwitcher

                // 动态时间线（随 Tab 变化）
                previewTimeline(for: selectedVideo)

                // Tab 内容区
                previewTabContent(for: selectedVideo)

                // 视频信息（简化，只留名字）
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
    }

    private var previewTabSwitcher: some View {
        Picker("", selection: $activePreviewTab) {
            ForEach(PreviewTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private func previewTimeline(for video: VideoItem) -> some View {
        switch activePreviewTab {
        case .frames:
            FrameScrubberView(
                frames: frameStripImages(for: video),
                progress: previewProgress,
                timecodeText: previewTimecodeText,
                sceneCuts: normalizedSceneCuts(for: video),
                isPlaying: isPreviewPlaying,
                togglePlayback: togglePreviewPlayback,
                seek: { seekPreview(to: $0) }
            )
        case .audio:
            WaveformControlBar(
                samples: libraryStore.waveformSamplesByVideoPath[video.url.path],
                progress: previewProgress,
                timecodeText: previewTimecodeText,
                isPlaying: isPreviewPlaying,
                togglePlayback: togglePreviewPlayback,
                seek: { seekPreview(to: $0) },
                sceneCuts: normalizedSceneCuts(for: video)
            )
        case .content:
            SimpleProgressBar(
                progress: previewProgress,
                timecodeText: previewTimecodeText,
                isPlaying: isPreviewPlaying,
                togglePlayback: togglePreviewPlayback,
                seek: { seekPreview(to: $0) }
            )
        }
    }

    @ViewBuilder
    private func previewTabContent(for video: VideoItem) -> some View {
        switch activePreviewTab {
        case .frames:
            scenePanel(for: video)
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

    @ViewBuilder
    private func scenePanel(for video: VideoItem) -> some View {
        let path = video.url.path
        let cuts = libraryStore.sceneCutsByVideoPath[path] ?? []

        VStack(alignment: .leading, spacing: 8) {
            if cuts.isEmpty && libraryStore.sceneDetectionProgress[path] == nil {
                Text("点击「识别场景」按钮开始自动分析")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                let columns = [GridItem(.adaptive(minimum: 76), spacing: 6)]
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(cuts) { cut in
                            SceneCutTile(
                                cut: cut,
                                timeLabel: formatDuration(cut.time)
                            ) {
                                let progress = previewDuration > 0 ? cut.time / previewDuration : 0
                                seekPreview(to: progress)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private func frameStripImages(for video: VideoItem) -> [NSImage]? {
        guard let images = libraryStore.frameStripImagesByVideoPath[video.url.path],
              !images.isEmpty else { return nil }
        return images
    }

    private func videoTile(_ video: VideoItem) -> some View {
        let isSelected = libraryStore.selectedVideo == video

        return Button {
            selectAndPlay(video)
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
                        .font(.system(size: 10, weight: .bold))
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
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

    private func durationText(for video: VideoItem) -> String {
        durationTextIfReady(for: video) ?? "--:--"
    }

    private var previewTimecodeText: String {
        formatTimecode(previewElapsed, frameRate: previewFrameRate)
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

    private func selectAndPlay(_ video: VideoItem) {
        if libraryStore.selectedVideo != video {
            libraryStore.selectedVideo = video
        }
        playPreview(video)
    }

    private func playPreview(_ video: VideoItem?) {
        guard let video else {
            previewPlayer.pause()
            previewPlayer.replaceCurrentItem(with: nil)
            isPreviewPlaying = false
            previewElapsed = 0
            previewDuration = 0
            previewProgress = 0
            previewFrameRate = 30
            previewPlaybackRate = 0
            previewPlaybackMessage = nil
            return
        }

        loadPreviewFrameRate(for: video)

        if let unsupportedMessage = libraryStore.playbackSupportByVideoPath[video.url.path]?.message {
            previewPlayer.replaceCurrentItem(with: nil)
            isPreviewPlaying = false
            previewElapsed = 0
            previewDuration = libraryStore.durationByVideoPath[video.url.path] ?? 0
            previewProgress = 0
            previewPlaybackRate = 0
            previewPlaybackMessage = unsupportedMessage
            libraryStore.loadWaveform(for: video)
            libraryStore.loadFrameStrip(for: video)
            libraryStore.loadCachedSceneCuts(for: video)
            return
        }

        previewPlaybackMessage = nil
        previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: video.url))
        previewElapsed = 0
        previewDuration = libraryStore.durationByVideoPath[video.url.path] ?? 0
        previewProgress = 0
        playPreview(atRate: 1)
        isPreviewPlaying = true
        libraryStore.loadWaveform(for: video)
        libraryStore.loadFrameStrip(for: video)
        libraryStore.loadCachedSceneCuts(for: video)
    }

    private func loadPreviewFrameRate(for video: VideoItem) {
        let path = video.url.path
        previewFrameRate = 30

        Task {
            let frameRate = await Self.frameRate(for: video.url)
            guard libraryStore.selectedVideo?.url.path == path else { return }
            previewFrameRate = frameRate
        }
    }

    nonisolated private static func frameRate(for url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard
            let tracks = try? await asset.loadTracks(withMediaType: .video),
            let videoTrack = tracks.first,
            let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate),
            nominalFrameRate.isFinite,
            nominalFrameRate > 0
        else {
            return 30
        }

        return Double(nominalFrameRate)
    }

    private func applyPlaybackSupportIfNeeded() {
        guard
            let video = libraryStore.selectedVideo,
            let unsupportedMessage = libraryStore.playbackSupportByVideoPath[video.url.path]?.message
        else { return }

        previewPlayer.pause()
        previewPlayer.replaceCurrentItem(with: nil)
        isPreviewPlaying = false
        previewElapsed = 0
        previewDuration = libraryStore.durationByVideoPath[video.url.path] ?? previewDuration
        previewProgress = 0
        previewPlaybackRate = 0
        previewPlaybackMessage = unsupportedMessage
    }

    private func togglePreviewPlayback() {
        if isPreviewPlaying || abs(previewPlaybackRate) > 0.001 {
            pausePreview()
        } else {
            playPreview(atRate: 1)
        }
    }

    private func pausePreview() {
        previewPlayer.pause()
        previewPlaybackRate = 0
        isPreviewPlaying = false
    }

    private func playPreview(atRate rate: Double) {
        guard previewPlayer.currentItem != nil else { return }
        previewPlayer.rate = Float(rate)
        previewPlaybackRate = rate
        isPreviewPlaying = abs(rate) > 0.001
    }

    private func handlePreviewKeyboardCommand(_ command: PreviewKeyboardCommand) -> Bool {
        guard libraryStore.selectedVideo != nil, previewPlayer.currentItem != nil else {
            return false
        }

        switch command {
        case .togglePlayback:
            togglePreviewPlayback()
        case .pause:
            pausePreview()
        case .shuttleForward:
            let nextRate = previewPlaybackRate > 0 ? min(previewPlaybackRate * 2, 8) : 1
            playPreview(atRate: nextRate)
        case .shuttleBackward:
            let nextRate = previewPlaybackRate < 0 ? max(previewPlaybackRate * 2, -8) : -1
            playPreview(atRate: nextRate)
        case .stepForward:
            stepPreviewFrame(by: 1)
        case .stepBackward:
            stepPreviewFrame(by: -1)
        }

        return true
    }

    private func stepPreviewFrame(by direction: Int) {
        pausePreview()
        let fps = max(previewFrameRate, 1)
        seekPreview(toSeconds: previewElapsed + Double(direction) / fps)
    }

    private func seekPreview(to progress: Double) {
        let duration = previewDuration > 0 ? previewDuration : currentPlayerDuration()
        guard let duration, duration > 0 else { return }

        let nextProgress = min(1, max(0, progress))
        seekPreview(toSeconds: duration * nextProgress)
    }

    private func seekPreview(toSeconds seconds: Double) {
        let duration = previewDuration > 0 ? previewDuration : currentPlayerDuration()
        guard let duration, duration > 0 else { return }

        let targetSeconds = min(duration, max(0, seconds))
        previewElapsed = targetSeconds
        previewProgress = min(1, max(0, targetSeconds / duration))
        previewPlayer.seek(
            to: CMTime(seconds: targetSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func handlePreviewEnd() {
        isPreviewPlaying = false
        previewPlaybackRate = 0
        previewProgress = 0
        previewElapsed = 0
        previewPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func normalizedSceneCuts(for video: VideoItem) -> [Double] {
        guard
            let cuts = libraryStore.sceneCutsByVideoPath[video.url.path],
            previewDuration > 0
        else { return [] }
        return cuts.map { min(1, max(0, $0.time / previewDuration)) }
    }

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

    private func updatePreviewProgress() {
        guard previewPlayer.currentItem != nil else {
            if isPreviewPlaying { isPreviewPlaying = false }
            if previewElapsed != 0 { previewElapsed = 0 }
            if previewProgress != 0 { previewProgress = 0 }
            return
        }

        if let item = previewPlayer.currentItem, item.status == .failed {
            if isPreviewPlaying { isPreviewPlaying = false }
            let msg = item.error?.localizedDescription ?? "这个视频无法播放"
            if previewPlaybackMessage != msg { previewPlaybackMessage = msg }
            if previewElapsed != 0 { previewElapsed = 0 }
            if previewProgress != 0 { previewProgress = 0 }
            return
        }

        if previewPlayer.currentItem?.status == .readyToPlay, previewPlaybackMessage != nil {
            previewPlaybackMessage = nil
        }

        if let duration = currentPlayerDuration() {
            assignIfChanged(&previewDuration, duration, tolerance: 0.001)
        }

        let elapsed = previewPlayer.currentTime().seconds
        if elapsed.isFinite, previewDuration > 0 {
            let nextElapsed = min(max(0, elapsed), previewDuration)
            assignIfChanged(&previewElapsed, nextElapsed, tolerance: 0.001)
            assignIfChanged(&previewProgress, min(1, max(0, nextElapsed / previewDuration)), tolerance: 0.0001)
        }

        let nextRate = Double(previewPlayer.rate)
        assignIfChanged(&previewPlaybackRate, nextRate, tolerance: 0.0001)
        let nextPlaying = abs(nextRate) > 0.001
        if isPreviewPlaying != nextPlaying {
            isPreviewPlaying = nextPlaying
        }
    }

    private func assignIfChanged(_ value: inout Double, _ nextValue: Double, tolerance: Double) {
        guard abs(value - nextValue) > tolerance else { return }
        value = nextValue
    }

    private func currentPlayerDuration() -> Double? {
        guard
            let seconds = previewPlayer.currentItem?.duration.seconds,
            seconds.isFinite,
            seconds > 0
        else {
            return nil
        }

        return seconds
    }

    private func tagEditor(for video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("标签")
                .font(.headline)

            tagChips(for: video)

            HStack {
                TextField("添加标签", text: $libraryStore.tagInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        libraryStore.addTag(to: video)
                    }

                Button {
                    libraryStore.addTag(to: video)
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(libraryStore.tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
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
