import AVFoundation
import Combine
import CryptoKit
import Foundation

// MARK: - PreviewController
/// 持有 AVPlayer 和播放状态。作为 @StateObject 存在，
/// 播放中定期同步 AVPlayer 状态。视频画面由 AVPlayerLayer 自己刷新，
/// 这里避免用显示器刷新率驱动整块 SwiftUI 预览面板重算。
@MainActor
final class PreviewController: ObservableObject {
    private static let sharedPlayer = AVPlayer()
    private static let playbackStateInterval = 1.0 / 12.0

    // ── Published（播放中高频变化）────────────────
    @Published var isPlaying     = false
    @Published var elapsed       = 0.0
    @Published var duration      = 0.0
    var progress      = 0.0
    @Published var frameRate     = 30.0
    @Published var playbackRate  = 0.0
    @Published var playbackMessage: String?


    let player: AVPlayer

    // 由 PreviewPanelView.onAppear 注入，weak 避免循环引用
    weak var libraryStore: LibraryStore?

    private(set) var currentVideoPath: String?
    private var currentSourceURL: URL?
    private var activePlaybackURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var frameRateTask: Task<Void, Never>?
    private var reverseProxyTask: Task<Void, Never>?
    private var pendingReverseProxyRate: Double?
    private let unsupportedReversePlaybackMessage = "这个视频编码不支持流畅倒放"
    private let reverseProxyPreparationMessage = "正在准备流畅倒放代理"
    /// AVPlayer 原生周期观察者：只同步控制 UI；视频帧刷新不走 SwiftUI。
    private var timeObserverToken: Any?

    init() {
        player = Self.sharedPlayer
        player.automaticallyWaitsToMinimizeStalling = true

        let interval = CMTime(seconds: Self.playbackStateInterval, preferredTimescale: 600)
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

    func loadVideo(_ video: VideoItem?, autoplay: Bool) {
        frameRateTask?.cancel()
        frameRateTask = nil
        reverseProxyTask?.cancel()
        reverseProxyTask = nil
        pendingReverseProxyRate = nil

        guard let video else {
            stopPlayback()
            elapsed = 0; duration = 0; progress = 0
            frameRate = 30; playbackRate = 0; playbackMessage = nil
            currentVideoPath = nil
            currentSourceURL = nil
            activePlaybackURL = nil
            return
        }

        player.pause()
        player.rate = 0
        playbackRate = 0
        isPlaying = false

        currentVideoPath = video.url.path
        currentSourceURL = video.url
        loadFrameRate(for: video)

        let store = libraryStore
        if let msg = store?.playbackSupportByVideoPath[video.url.path]?.message {
            stopPlayback()
            elapsed = 0
            duration = store?.durationByVideoPath[video.url.path] ?? 0
            progress = 0; playbackRate = 0; playbackMessage = msg
            store?.loadWaveform(for: video)
            store?.loadFrameStrip(for: video)
            store?.loadCachedSceneCuts(for: video)
            return
        }

        playbackMessage = nil
        activePlaybackURL = video.url
        replacePlayerItem(with: video.url)
        elapsed = 0
        duration = store?.durationByVideoPath[video.url.path] ?? 0
        progress = 0
        if autoplay {
            setRate(1)
            isPlaying = true
        } else {
            player.pause()
            playbackRate = 0
            isPlaying = false
        }
        store?.loadWaveform(for: video)
        store?.loadFrameStrip(for: video)
        store?.loadCachedSceneCuts(for: video)
    }

    func stopPlayback() {
        reverseProxyTask?.cancel()
        reverseProxyTask = nil
        pendingReverseProxyRate = nil
        player.pause()
        player.rate = 0
        player.isMuted = false
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        playbackRate = 0
        activePlaybackURL = nil
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
        if isPlaying || abs(playbackRate) > 0.001 {
            pause()
        } else {
            if isAtPlaybackEnd {
                seekToSeconds(0, snapToFrame: false)
            }
            setRate(1)
        }
    }

    func pause(snapToFrame: Bool = false) {
        player.pause()
        player.isMuted = false
        playbackRate = 0
        isPlaying = false
        updateProgress()
        if snapToFrame {
            snapToNearestFrame()
        }
    }

    func setRate(_ rate: Double) {
        guard player.currentItem != nil else { return }
        if abs(rate) <= 0.001 {
            pause()
            return
        }

        if rate < 0 {
            if switchToCachedReverseProxyForReversePlayback(rate: rate) {
                return
            }
            prepareReverseProxyIfNeeded()
        } else if shouldSwitchBackToSourceForForwardPlayback {
            switchToSourceForForwardPlayback(rate: rate)
            return
        }

        guard let item = player.currentItem else { return }
        guard let supportedRate = supportedPlaybackRate(rate, for: item) else {
            if rate < 0, reverseProxyTask != nil {
                player.pause()
                playbackRate = 0
                isPlaying = false
                pendingReverseProxyRate = rate
                playbackMessage = reverseProxyPreparationMessage
                return
            }

            pause()
            playbackMessage = unsupportedReversePlaybackMessage
            return
        }

        if supportedRate < 0, elapsed <= frameDuration, let d = effectiveDuration, d > frameDuration {
            beginReversePlaybackFromEnd(rate: supportedRate, duration: d)
            return
        }

        beginPlayback(at: supportedRate)
    }

    func stepFrame(by direction: Int) {
        pause(snapToFrame: false)
        seekToSeconds(elapsed + Double(direction) / max(frameRate, 1))
    }

    // MARK: – Seek

    func seekToProgress(_ p: Double) {
        let d = effectiveDuration; guard let d, d > 0 else { return }
        seekToSeconds(d * min(1, max(0, p)))
    }

    /// 直接按秒跳转（供 ScenePanelView 调用，不需要传入 duration）
    func seekToSeconds(_ seconds: Double, snapToFrame: Bool? = nil) {
        let d = effectiveDuration; guard let d, d > 0 else { return }
        let shouldSnap = snapToFrame ?? !isPlaying
        let raw = min(d, max(0, seconds))
        let t = shouldSnap ? nearestFrameTime(raw, duration: d) : raw
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

        if player.currentItem?.status == .readyToPlay,
           let playbackMessage,
           playbackMessage != unsupportedReversePlaybackMessage,
           playbackMessage != reverseProxyPreparationMessage {
            self.playbackMessage = nil
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
        isPlaying = false
        playbackRate = 0
        if let d = effectiveDuration, d > 0 {
            elapsed = d
            progress = 1
        } else {
            elapsed = 0
            progress = 0
        }
    }

    private func snapToNearestFrame() {
        let d = effectiveDuration; guard let d, d > 0 else { return }
        let snapped = nearestFrameTime(elapsed, duration: d)
        guard abs(snapped - elapsed) > 0.0001 else { return }
        elapsed = snapped
        progress = min(1, max(0, snapped / d))
        player.seek(
            to: CMTime(seconds: snapped, preferredTimescale: frameTimeScale),
            toleranceBefore: .zero, toleranceAfter: .zero
        )
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

    private func beginPlayback(at rate: Double) {
        playbackMessage = nil
        player.isMuted = rate < 0
        if abs(rate - 1) <= 0.001 {
            player.play()
        } else {
            player.playImmediately(atRate: Float(rate))
        }
        playbackRate = rate
        isPlaying = true
    }

    private func beginReversePlaybackFromEnd(rate: Double, duration: Double) {
        let target = nearestFrameTime(duration, duration: duration)
        elapsed = target
        progress = 1
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: frameTimeScale),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor [weak self] in
                self?.beginPlayback(at: rate)
            }
        }
    }

    private func replacePlayerItem(with url: URL) {
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 1.5
        item.forwardPlaybackEndTime = .invalid
        item.reversePlaybackEndTime = .zero
        player.replaceCurrentItem(with: item)
    }

    private var shouldSwitchBackToSourceForForwardPlayback: Bool {
        guard let currentSourceURL else { return false }
        return activePlaybackURL?.path != currentSourceURL.path
    }

    private func switchToSourceForForwardPlayback(rate: Double) {
        guard let sourceURL = currentSourceURL else { return }
        let resumeTime = elapsed

        player.pause()
        player.isMuted = false
        activePlaybackURL = sourceURL
        replacePlayerItem(with: sourceURL)
        player.seek(
            to: CMTime(seconds: resumeTime, preferredTimescale: frameTimeScale),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor [weak self] in
                self?.beginPlayback(at: rate)
            }
        }
    }

    private func switchToCachedReverseProxyForReversePlayback(rate: Double) -> Bool {
        guard let sourceURL = currentSourceURL,
              let proxyURL = PreviewController.cachedReverseProxyURL(for: sourceURL),
              activePlaybackURL?.path != proxyURL.path else {
            return false
        }

        pendingReverseProxyRate = rate
        switchToReverseProxy(proxyURL, sourceURL: sourceURL)
        return true
    }

    private func prepareReverseProxyIfNeeded() {
        guard let sourceURL = currentSourceURL else { return }

        if let proxyURL = PreviewController.cachedReverseProxyURL(for: sourceURL) {
            switchToReverseProxy(proxyURL, sourceURL: sourceURL)
            return
        }

        guard reverseProxyTask == nil else { return }
        let sourcePath = sourceURL.path
        reverseProxyTask = Task { [weak self, sourceURL] in
            let proxyURL = await PreviewController.makeReversePlaybackProxy(for: sourceURL)
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.reverseProxyTask = nil
                guard self.currentVideoPath == sourcePath else { return }
                guard let proxyURL else {
                    if self.pendingReverseProxyRate != nil {
                        self.pendingReverseProxyRate = nil
                        self.playbackMessage = self.unsupportedReversePlaybackMessage
                    }
                    return
                }
                self.switchToReverseProxy(proxyURL, sourceURL: sourceURL)
            }
        }
    }

    private func switchToReverseProxy(_ proxyURL: URL, sourceURL: URL) {
        guard currentSourceURL?.path == sourceURL.path,
              activePlaybackURL?.path != proxyURL.path else { return }

        let resumeTime = elapsed
        let resumeRate = pendingReverseProxyRate ?? playbackRate
        let shouldResume = pendingReverseProxyRate != nil || abs(resumeRate) > 0.001
        pendingReverseProxyRate = nil

        player.pause()
        player.isMuted = shouldResume && resumeRate < 0
        activePlaybackURL = proxyURL
        replacePlayerItem(with: proxyURL)
        player.seek(
            to: CMTime(seconds: resumeTime, preferredTimescale: frameTimeScale),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard finished, shouldResume else { return }
            Task { @MainActor [weak self] in
                self?.beginPlayback(at: resumeRate)
            }
        }
    }

    private func supportedPlaybackRate(_ requestedRate: Double, for item: AVPlayerItem) -> Double? {
        if requestedRate > 1, !item.canPlayFastForward {
            return 1
        }

        guard requestedRate < 0 else { return requestedRate }
        let speed = abs(requestedRate)

        if speed > 1, item.canPlayFastReverse {
            return requestedRate
        }

        if speed < 1, item.canPlaySlowReverse {
            return requestedRate
        }

        if item.canPlayReverse {
            return -1
        }

        return nil
    }

    private func nearestFrameTime(_ seconds: Double, duration: Double) -> Double {
        let fps = max(1, frameRate)
        let frame = (seconds * fps).rounded()
        return min(duration, max(0, frame / fps))
    }

    private var frameDuration: Double {
        1 / max(frameRate, 1)
    }

    private var isAtPlaybackEnd: Bool {
        guard let d = effectiveDuration, d > 0 else { return false }
        return progress >= 0.999 || elapsed >= d - max(frameDuration, 0.05)
    }

    private var frameTimeScale: CMTimeScale {
        CMTimeScale(max(600, Int32((max(1, frameRate) * 100).rounded())))
    }

    nonisolated private static func cachedReverseProxyURL(for sourceURL: URL) -> URL? {
        let proxyURL = reverseProxyURL(for: sourceURL)
        guard FileManager.default.fileExists(atPath: proxyURL.path) else { return nil }
        guard let sourceDate = modificationDate(for: sourceURL),
              let proxyDate = modificationDate(for: proxyURL),
              proxyDate >= sourceDate else { return nil }
        return proxyURL
    }

    nonisolated private static func makeReversePlaybackProxy(for sourceURL: URL) async -> URL? {
        await Task.detached(priority: .utility) {
            if let cached = cachedReverseProxyURL(for: sourceURL) {
                return cached
            }

            guard let ffmpegURL = ffmpegExecutableURL() else { return nil }
            let outputURL = reverseProxyURL(for: sourceURL)
            let folderURL = outputURL.deletingLastPathComponent()
            let tmpURL = folderURL.appendingPathComponent(outputURL.deletingPathExtension().lastPathComponent + ".tmp.mp4")

            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: tmpURL.path) {
                    try FileManager.default.removeItem(at: tmpURL)
                }

                let process = Process()
                process.executableURL = ffmpegURL
                process.arguments = [
                    "-y",
                    "-hide_banner",
                    "-loglevel", "error",
                    "-i", sourceURL.path,
                    "-map", "0:v:0",
                    "-an",
                    "-c:v", "libx264",
                    "-preset", "veryfast",
                    "-crf", "20",
                    "-g", "1",
                    "-keyint_min", "1",
                    "-sc_threshold", "0",
                    "-pix_fmt", "yuv420p",
                    "-movflags", "+faststart",
                    tmpURL.path
                ]
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                process.environment = env
                process.standardOutput = Pipe()
                process.standardError = Pipe()

                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: tmpURL.path) else {
                    try? FileManager.default.removeItem(at: tmpURL)
                    return nil
                }

                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.moveItem(at: tmpURL, to: outputURL)
                return outputURL
            } catch {
                try? FileManager.default.removeItem(at: tmpURL)
                return nil
            }
        }.value
    }

    nonisolated private static func reverseProxyURL(for sourceURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(sourceURL.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("LapianBao", isDirectory: true)
            .appendingPathComponent("ReversePlaybackProxies", isDirectory: true)
            .appendingPathComponent("\(digest)-intra-silent.mp4")
    }

    nonisolated private static func ffmpegExecutableURL() -> URL? {
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        return paths
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    nonisolated private static func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
