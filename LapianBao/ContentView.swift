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

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.remove([.titled, .closable, .miniaturizable])
        window.styleMask.insert(.resizable)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
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

    private let placeholderSamples: [Double] = (0..<72).map { index in
        0.14 + 0.10 * abs(sin(Double(index) * 0.46))
    }

    var body: some View {
        Canvas { context, size in
            let values = samples ?? placeholderSamples

            guard !values.isEmpty else {
                let rect = CGRect(x: 0, y: size.height / 2, width: size.width, height: 1)
                context.fill(Path(rect), with: .color(.white.opacity(0.18)))
                return
            }

            let step = size.width / CGFloat(values.count)
            let barWidth = max(1.4, step * 0.58)
            let color = samples == nil ? Color.white.opacity(0.16) : Color.white.opacity(0.72)

            for (index, value) in values.enumerated() {
                let normalized = max(0.04, min(1, value))
                let barHeight = CGFloat(normalized) * size.height * 0.84
                let x = CGFloat(index) * step + (step - barWidth) / 2
                let y = (size.height - barHeight) / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)

                var path = Path()
                path.addRoundedRect(
                    in: rect,
                    cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                )
                context.fill(path, with: .color(color))
            }
        }
        .frame(height: 54)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
        .accessibilityLabel("音频波形")
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

private struct PreviewScrubber: View {
    let progress: Double
    let seek: (Double) -> Void

    @State private var draftProgress: Double?

    var body: some View {
        GeometryReader { proxy in
            let displayedProgress = draftProgress ?? progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))

                Capsule()
                    .fill(.white.opacity(0.72))
                    .frame(width: proxy.size.width * displayedProgress)

                Circle()
                    .fill(.white.opacity(0.92))
                    .frame(width: 8, height: 8)
                    .offset(x: max(0, proxy.size.width * displayedProgress - 4))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateProgress(at: value.location.x, width: proxy.size.width, commitsSeek: false)
                    }
                    .onEnded { value in
                        updateProgress(at: value.location.x, width: proxy.size.width, commitsSeek: true)
                    }
            )
        }
        .frame(height: 12)
    }

    private func updateProgress(at xPosition: CGFloat, width: CGFloat, commitsSeek: Bool) {
        guard width > 0 else { return }
        let nextProgress = min(1, max(0, Double(xPosition / width)))
        draftProgress = commitsSeek ? nil : nextProgress
        seek(nextProgress)
    }
}

private struct PreviewPlayerView: View {
    let player: AVPlayer
    let isPlaying: Bool
    let progress: Double
    let elapsedText: String
    let durationText: String
    let togglePlayback: () -> Void
    let seek: (Double) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            PlayerSurfaceView(player: player)
                .background(.black)

            HStack(spacing: 10) {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.16))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "暂停" : "播放")

                Text(elapsedText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.74))
                    .frame(width: 42, alignment: .trailing)

                PreviewScrubber(progress: progress, seek: seek)

                Text(durationText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.74))
                    .frame(width: 42, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.74))
            .clipShape(Capsule())
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
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
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            updatePreviewProgress()
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
            windowControls
                .padding(.leading, 9)
                .padding(.top, 7)

            sidebarContent
                .padding(.horizontal, 18)
                .padding(.top, 88)
                .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity)
        .glassPanel()
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("分类")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(libraryStore.allTags, id: \.self) { tag in
                    Button {
                        libraryStore.selectedTag = tag
                    } label: {
                        HStack {
                            Text(tag)
                                .lineLimit(1)
                            Spacer()
                            if tag == libraryStore.selectedTag {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background {
                        if tag == libraryStore.selectedTag {
                            RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous)
                                .fill(.thinMaterial)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous))
                }
            }

            Spacer()

            Text("\(libraryStore.videos.count) 个视频")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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

            if libraryStore.filteredVideos.isEmpty {
                ContentUnavailableView(
                    "没有视频",
                    systemImage: "film.stack",
                    description: Text("从菜单栏 File 里打开文件夹后，这里会显示里面的视频。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(libraryStore.filteredVideos) { video in
                            videoTile(video)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .contentPanel()
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("预览")
                    .font(.title2.bold())
                Spacer()
                if let selectedVideo = libraryStore.selectedVideo {
                    Text(durationText(for: selectedVideo))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
            }

            if let selectedVideo = libraryStore.selectedVideo {
                PreviewPlayerView(
                    player: previewPlayer,
                    isPlaying: isPreviewPlaying,
                    progress: previewProgress,
                    elapsedText: formatDuration(previewElapsed),
                    durationText: previewDuration > 0 ? formatDuration(previewDuration) : durationText(for: selectedVideo),
                    togglePlayback: togglePreviewPlayback,
                    seek: seekPreview
                )

                AudioWaveformView(samples: libraryStore.waveformSamplesByVideoPath[selectedVideo.url.path])

                VStack(alignment: .leading, spacing: 10) {
                    Text(selectedVideo.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    Text(selectedVideo.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    tagEditor(for: selectedVideo)
                }
                .padding(14)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))

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
    }

    private func videoTile(_ video: VideoItem) -> some View {
        Button {
            libraryStore.selectedVideo = video
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous)
                        .fill(.black.opacity(0.32))

                    if let image = thumbnailImage(for: video) {
                        GeometryReader { proxy in
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                        }
                    } else {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.88))
                    }

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.42)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    if let duration = durationTextIfReady(for: video) {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(duration)
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(.thinMaterial)
                                    .clipShape(Capsule())
                            }
                            .padding(7)
                        }
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(video.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                }

                tagChips(for: video)
            }
            .padding(10)
            .background(libraryStore.selectedVideo == video ? .regularMaterial : .thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous)
                    .stroke(libraryStore.selectedVideo == video ? .white.opacity(0.28) : .white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func thumbnailImage(for video: VideoItem) -> NSImage? {
        guard let data = libraryStore.thumbnailDataByVideoPath[video.url.path] else { return nil }
        return NSImage(data: data)
    }

    private func durationTextIfReady(for video: VideoItem) -> String? {
        guard let duration = libraryStore.durationByVideoPath[video.url.path] else { return nil }
        return formatDuration(duration)
    }

    private func durationText(for video: VideoItem) -> String {
        durationTextIfReady(for: video) ?? "--:--"
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

    private func playPreview(_ video: VideoItem?) {
        guard let video else {
            previewPlayer.pause()
            previewPlayer.replaceCurrentItem(with: nil)
            isPreviewPlaying = false
            previewElapsed = 0
            previewDuration = 0
            previewProgress = 0
            return
        }

        previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: video.url))
        previewElapsed = 0
        previewDuration = libraryStore.durationByVideoPath[video.url.path] ?? 0
        previewProgress = 0
        previewPlayer.play()
        isPreviewPlaying = true
        libraryStore.loadWaveform(for: video)
    }

    private func togglePreviewPlayback() {
        if previewPlayer.timeControlStatus == .playing {
            previewPlayer.pause()
            isPreviewPlaying = false
        } else {
            previewPlayer.play()
            isPreviewPlaying = true
        }
    }

    private func seekPreview(to progress: Double) {
        let duration = previewDuration > 0 ? previewDuration : currentPlayerDuration()
        guard let duration, duration > 0 else { return }

        let nextProgress = min(1, max(0, progress))
        let targetSeconds = duration * nextProgress
        previewElapsed = targetSeconds
        previewProgress = nextProgress
        previewPlayer.seek(
            to: CMTime(seconds: targetSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func updatePreviewProgress() {
        guard previewPlayer.currentItem != nil else {
            isPreviewPlaying = false
            previewElapsed = 0
            previewDuration = 0
            previewProgress = 0
            return
        }

        if let duration = currentPlayerDuration() {
            previewDuration = duration
        }

        let elapsed = previewPlayer.currentTime().seconds
        if elapsed.isFinite, previewDuration > 0 {
            previewElapsed = min(max(0, elapsed), previewDuration)
            previewProgress = min(1, max(0, previewElapsed / previewDuration))
        }

        isPreviewPlaying = previewPlayer.timeControlStatus == .playing
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
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
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

#Preview {
    ContentView()
        .environmentObject(LibraryStore())
}
