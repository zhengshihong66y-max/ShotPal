//
//  AudioWorkspacePreview.swift
//  LapianBao
//
//  Preview playback support for the sound-effect workspace.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

enum AudioPreviewID: Equatable {
    case local(String)
    case clip(UUID)
}

struct AudioPreviewMetrics: Equatable {
    var progress: Double = 0
    var elapsed: Double = 0
    var duration: Double = 0

    static let idle = AudioPreviewMetrics()
}

@MainActor
final class AudioPreviewProgressStore: ObservableObject {
    @Published private(set) var metrics = AudioPreviewMetrics.idle

    func reset(duration: Double = 0) {
        metrics = AudioPreviewMetrics(duration: Self.validDuration(duration) ?? 0)
    }

    func update(elapsed rawElapsed: Double, itemDuration: Double) {
        let elapsed = max(0, rawElapsed)
        let duration = Self.validDuration(itemDuration) ?? metrics.duration
        let progress = Self.validDuration(duration).map { min(1, max(0, elapsed / $0)) } ?? 0
        let nextMetrics = AudioPreviewMetrics(progress: progress, elapsed: elapsed, duration: duration)
        guard shouldPublish(nextMetrics) else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            metrics = nextMetrics
        }
    }

    func progressText(fallbackDuration: Double) -> String {
        let duration = Self.validDuration(metrics.duration) ?? Self.validDuration(fallbackDuration)
        let elapsed = max(0, metrics.elapsed)
        guard let duration else { return clockText(elapsed) }
        return clockText(min(elapsed, duration))
    }

    private func shouldPublish(_ nextMetrics: AudioPreviewMetrics) -> Bool {
        abs(nextMetrics.elapsed - metrics.elapsed) >= 0.1
            || abs(nextMetrics.progress - metrics.progress) >= 0.006
            || abs(nextMetrics.duration - metrics.duration) >= 0.05
            || nextMetrics.progress >= 1
    }

    private static func validDuration(_ duration: Double) -> Double? {
        duration.isFinite && duration > 0 ? duration : nil
    }
}

@MainActor
final class AudioPreviewController: ObservableObject {
    @Published private(set) var activeID: AudioPreviewID?

    let progressStore = AudioPreviewProgressStore()

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func toggle(fileURL: URL, id: AudioPreviewID, notificationID: UUID, totalDuration: Double) {
        if activeID == id {
            stop()
            return
        }

        start(fileURL: fileURL, id: id, notificationID: notificationID, totalDuration: totalDuration)
    }

    func start(fileURL: URL, id: AudioPreviewID, notificationID: UUID, totalDuration: Double) {
        stop()
        AppEventBus.postPausePreviewRequest()
        AppEventBus.postMusicPreviewStarted(
            id: notificationID,
            source: AppEventBus.MusicPreviewSource.audioWorkspace
        )

        let item = AVPlayerItem(url: fileURL)
        let player = AVPlayer(playerItem: item)
        self.player = player
        activeID = id
        progressStore.reset(duration: totalDuration)

        let progressStore = progressStore
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.12, preferredTimescale: 600),
            queue: .main
        ) { time in
            let elapsed = time.seconds
            guard elapsed.isFinite else { return }
            let duration = item.duration.seconds
            Task { @MainActor in
                progressStore.update(elapsed: elapsed, itemDuration: duration)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }

        player.play()
    }

    func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        player?.pause()
        player = nil
        activeID = nil
        progressStore.reset()

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
