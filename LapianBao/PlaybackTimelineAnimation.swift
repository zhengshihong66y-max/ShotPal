//
//  PlaybackTimelineAnimation.swift
//  LapianBao
//

import Foundation
import SwiftUI

enum PlaybackTimelineAnimation {
    static let visualFrameInterval = 1.0 / 60.0
    static let maximumPredictionLead = 0.24

    static func canAnimate(
        duration: Double,
        isPlaying: Bool,
        playbackRate: Double
    ) -> Bool {
        duration.isFinite
            && duration > 0
            && isPlaying
            && abs(playbackRate) > 0.001
    }

    static func interpolatedElapsed(
        from sample: PlaybackClockValue,
        duration: Double,
        playbackRate: Double,
        isPlaying: Bool,
        at date: Date
    ) -> Double {
        let base = sample.elapsed
        guard canAnimate(duration: duration, isPlaying: isPlaying, playbackRate: playbackRate) else {
            return min(max(0, base), max(duration, 0))
        }

        let lead = predictionLead(from: sample.sampledAt, to: date)
        return min(max(0, base + lead * playbackRate), duration)
    }

    static func interpolatedProgress(
        anchorProgress: Double,
        sampledAt: Date,
        duration: Double,
        playbackRate: Double,
        isPlaying: Bool,
        at date: Date
    ) -> Double {
        let base = normalizedProgress(anchorProgress)
        guard canAnimate(duration: duration, isPlaying: isPlaying, playbackRate: playbackRate) else {
            return base
        }

        let lead = predictionLead(from: sampledAt, to: date)
        return normalizedProgress(base + lead * playbackRate / duration)
    }

    static func normalizedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }

    private static func predictionLead(from sampledAt: Date, to date: Date) -> Double {
        min(max(0, date.timeIntervalSince(sampledAt)), maximumPredictionLead)
    }
}

struct PlaybackClockSnapshot {
    let elapsed: Double
    let progress: Double

    var timecodeText: String {
        previewPlaybackTimecode(elapsed)
    }
}

struct PlaybackClockDrivenView<Content: View>: View {
    @ObservedObject var clock: PlaybackClock
    let duration: Double
    let playbackRate: Double
    let isPlaying: Bool
    private let content: (PlaybackClockSnapshot) -> Content

    init(
        clock: PlaybackClock,
        duration: Double = 0,
        playbackRate: Double = 0,
        isPlaying: Bool = false,
        @ViewBuilder content: @escaping (PlaybackClockSnapshot) -> Content
    ) {
        self.clock = clock
        self.duration = duration
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
        self.content = content
    }

    var body: some View {
        let shouldAnimate = PlaybackTimelineAnimation.canAnimate(
            duration: duration,
            isPlaying: isPlaying,
            playbackRate: playbackRate
        )

        TimelineView(.animation(minimumInterval: PlaybackTimelineAnimation.visualFrameInterval, paused: !shouldAnimate)) { context in
            let value = clock.value
            let elapsed = PlaybackTimelineAnimation.interpolatedElapsed(
                from: value,
                duration: duration,
                playbackRate: playbackRate,
                isPlaying: shouldAnimate,
                at: context.date
            )
            let progress = duration > 0
                ? PlaybackTimelineAnimation.normalizedProgress(elapsed / duration)
                : value.progress

            content(PlaybackClockSnapshot(elapsed: elapsed, progress: progress))
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
        }
    }
}

private struct SmoothTimelineProgressAnchor {
    var progress = 0.0
    var sampledAt: Date?
}

struct SmoothTimelineProgressReader<Content: View>: View {
    let progress: Double
    let duration: Double
    let playbackRate: Double
    let isPlaying: Bool
    private let content: (Double) -> Content

    @State private var anchor = SmoothTimelineProgressAnchor()

    init(
        progress: Double,
        duration: Double,
        playbackRate: Double = 1,
        isPlaying: Bool,
        @ViewBuilder content: @escaping (Double) -> Content
    ) {
        self.progress = progress
        self.duration = duration
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
        self.content = content
    }

    var body: some View {
        let shouldAnimate = PlaybackTimelineAnimation.canAnimate(
            duration: duration,
            isPlaying: isPlaying,
            playbackRate: playbackRate
        )
        let normalizedProgress = PlaybackTimelineAnimation.normalizedProgress(progress)

        TimelineView(.animation(minimumInterval: PlaybackTimelineAnimation.visualFrameInterval, paused: !shouldAnimate)) { context in
            let sampledAt = anchor.sampledAt ?? context.date
            let anchorProgress = anchor.sampledAt == nil ? normalizedProgress : anchor.progress
            let displayedProgress = PlaybackTimelineAnimation.interpolatedProgress(
                anchorProgress: anchorProgress,
                sampledAt: sampledAt,
                duration: duration,
                playbackRate: playbackRate,
                isPlaying: shouldAnimate,
                at: context.date
            )

            content(displayedProgress)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
        }
        .onAppear {
            rebase(to: normalizedProgress)
        }
        .onChange(of: progress) { _, next in
            rebase(to: next)
        }
        .onChange(of: duration) { _, _ in
            rebase(to: progress)
        }
        .onChange(of: playbackRate) { _, _ in
            rebase(to: progress)
        }
        .onChange(of: isPlaying) { _, _ in
            rebase(to: progress)
        }
    }

    private func rebase(to progress: Double) {
        anchor = SmoothTimelineProgressAnchor(
            progress: PlaybackTimelineAnimation.normalizedProgress(progress),
            sampledAt: Date()
        )
    }
}
