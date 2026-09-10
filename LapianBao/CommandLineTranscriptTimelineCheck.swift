import AppKit
import AVFoundation
import Foundation
import SwiftUI

@MainActor
enum CommandLineTranscriptTimelineCheck {
    static func run() -> [String: Bool] {
        var checks: [String: Bool] = [:]
        checks.merge(CommandLineSubtitleScrollCheck.run(), uniquingKeysWith: { _, new in new })
        let path = "/synthetic-fixture/audio.mp4"
        let words = [TranscriptSegment(videoPath: path, start: 2, end: 4, text: "A clear spoken phrase.")]
        let store = LibraryStore() // No library is opened; all mutations are in memory.
        let waveform = [0.2, 0.8, 0.4, 0.7]
        store.waveformSamplesByVideoPath[path] = waveform
        store.transcriptStatusByVideoPath[path] = .running("识别中 50%")
        store.completeTranscription(path: path, segments: [])
        let empty = TranscriptTimelineState(segments: store.transcriptSegmentsByVideoPath[path],
                                            status: store.transcriptStatusByVideoPath[path])
        checks["transcript_empty_result_is_completed"] = store.transcriptStatusByVideoPath[path] == .completed
        checks["transcript_empty_result_keeps_waveform"] = store.waveformSamplesByVideoPath[path] == waveform
        checks["transcript_empty_result_has_visible_fallback"] = empty.showsWaveformFallback && !empty.message.isEmpty && empty.canExpand
        checks["transcript_empty_result_does_not_auto_retry"] = !empty.shouldStartAutomatically
        store.videos = [VideoItem(url: URL(fileURLWithPath: path))]
        store.startTranscriptBatch(onlyMissing: true)
        checks["transcript_startup_batch_skips_completed_empty_result"] = store.transcriptBatchJob.total == 0 && store.transcriptBatchTask == nil
        store.transcriptBatchTask?.cancel()
        store.updateTranscriptProgress(path: path, progress: 0.99, message: "late callback")
        checks["transcript_late_progress_cannot_revive_completion"] = store.transcriptStatusByVideoPath[path] == .completed
        store.transcriptStatusByVideoPath[path] = .failed("fixture failure")
        store.updateTranscriptProgress(path: path, progress: 1, message: "late callback")
        checks["transcript_late_progress_cannot_revive_failure"] = store.transcriptStatusByVideoPath[path] == .failed("fixture failure")
        store.transcriptStatusByVideoPath[path] = .idle
        store.updateTranscriptProgress(path: path, progress: 1, message: "late callback")
        checks["transcript_late_progress_cannot_revive_cancellation"] = store.transcriptStatusByVideoPath[path] == .idle
        store.completeTranscription(path: path, segments: words)
        store.completeTranscription(path: path, segments: [])
        checks["transcript_empty_retry_preserves_previous_words"] = store.transcriptSegmentsByVideoPath[path] == words

        let partial = TranscriptTimelineState(segments: words, status: .completed)
        checks["transcript_partial_result_keeps_recognized_words"] = !partial.showsWaveformFallback && partial.canExpand
        let failed = TranscriptTimelineState(segments: nil, status: .failed("fixture failure"))
        checks["transcript_failure_offers_waveform_without_auto_retry"] = failed.showsWaveformFallback && failed.canExpand && !failed.shouldStartAutomatically
        let failedWithWords = TranscriptTimelineState(segments: words, status: .failed("fixture failure"))
        checks["transcript_failed_retry_keeps_previous_timeline"] = failedWithWords.hasWords && !failedWithWords.showsWaveformFallback
        let running = TranscriptTimelineState(segments: nil, status: .running("识别中"))
        checks["transcript_running_keeps_collapsed_waveform"] = !running.canExpand && !running.shouldStartAutomatically
        let initial = TranscriptTimelineState(segments: nil, status: nil)
        checks["transcript_new_clip_still_starts_recognition"] = initial.shouldStartAutomatically && !initial.canExpand
        do {
            let cache = try JSONEncoder().encode([path: [TranscriptSegment]()])
            let restored = try JSONDecoder().decode([String: [TranscriptSegment]].self, from: cache)
            let state = TranscriptTimelineState(segments: restored[path], status: nil)
            checks["transcript_cached_empty_result_does_not_restart"] = !state.shouldStartAutomatically && state.canExpand
            let parsed = try LibraryStore.parseWhisperSegments(data: Data("{\"transcription\":[]}".utf8), videoPath: path)
            checks["transcript_no_words_are_not_fabricated"] = LibraryStore.cleanTranscriptSegments(parsed).isEmpty
            let mixed = try LibraryStore.parseWhisperSegments(data: Data("{\"transcription\":[{\"start\":0,\"end\":2,\"text\":\"  \"},{\"start\":2,\"end\":4,\"text\":\"clear speech\"}]}".utf8), videoPath: path)
            checks["transcript_unclear_section_does_not_erase_clear_section"] = LibraryStore.cleanTranscriptSegments(mixed).count == 1
        } catch { checks["transcript_fixture_parsing"] = false }

        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--subtitle-playback-fixture"), arguments.count > index + 1 {
            checks.merge(checkContinuousPlayback(url: URL(fileURLWithPath: arguments[index + 1])),
                         uniquingKeysWith: { _, new in new })
        }
        if let index = arguments.firstIndex(of: "--transcript-json"), arguments.count > index + 1 {
            do {
                let parsed = try LibraryStore.parseWhisperSegments(data: Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])), videoPath: path)
                let clean = LibraryStore.cleanTranscriptSegments(parsed)
                let state = TranscriptTimelineState(segments: clean, status: .completed)
                checks["real_whisper_result_has_words_or_waveform_fallback"] = state.canExpand && !state.shouldStartAutomatically && (state.hasWords || state.showsWaveformFallback)
            } catch { checks["real_whisper_result_has_words_or_waveform_fallback"] = false }
        }
        if let index = arguments.firstIndex(of: "--transcript-preview-directory"), arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let longFailure = TranscriptTimelineState(segments: nil, status: .failed(Array(repeating: "A long diagnostic line from the transcription process.", count: 12).joined(separator: "\n")))
                for (name, state) in [("empty", empty), ("failed", failed), ("running", running), ("long-error", longFailure)] {
                    let view = TranscriptTimelineFallback(state: state, retry: {}) {
                        CenteredWaveformTimeline(samples: (0..<160).map { 0.1 + 0.7 * abs(sin(Double($0) * 0.13)) },
                                                 progress: 0.4, seek: { _ in })
                    }
                    .frame(width: 640, height: 180)
                    .background(Color(white: 0.13))
                    .environment(\.colorScheme, .dark)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    guard let image = renderer.cgImage,
                          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                    else { checks["transcript_render_\(name)"] = false; continue }
                    try png.write(to: directory.appendingPathComponent("transcript-\(name).png"))
                    checks["transcript_render_\(name)"] = true
                }
            } catch { checks["transcript_render_io"] = false }
        }
        return checks
    }

    private static func checkContinuousPlayback(url: URL) -> [String: Bool] {
        let controller = PreviewController()
        let originalVolume = controller.player.volume
        controller.player.volume = 0 // Exercise real playback without audible test output.
        defer {
            controller.stopPlayback()
            controller.player.volume = originalVolume
        }
        controller.loadVideo(VideoItem(url: url), autoplay: false)
        var checks: [String: Bool] = [:]
        let ready = waitUntil { controller.player.currentItem?.status == .readyToPlay }
        checks["subtitle_playback_fixture_ready"] = ready && (controller.effectiveDuration ?? 0) >= 4
        guard checks["subtitle_playback_fixture_ready"] == true else { return checks }

        controller.pause()
        controller.playContinuously(from: 1.03)
        checks["subtitle_click_starts_paused_player"] = controller.isPlaying && controller.playbackRate == 1
        checks["subtitle_click_keeps_exact_start_timestamp"] = abs(controller.elapsed - 1.03) < 0.001
        checks["subtitle_playback_continues_beyond_entry_end"] = waitUntil {
            controller.player.currentTime().seconds > 1.5 && controller.player.rate > 0
        }

        controller.pause()
        let rangeStarted = controller.playSegment(from: 0, to: 0.4)
            && waitUntil { controller.player.rate > 0 }
        controller.playContinuously(from: 1)
        checks["subtitle_click_clears_previous_segment_limit"] = rangeStarted
            && controller.player.currentItem?.forwardPlaybackEndTime.isValid == false
        checks["subtitle_playback_outlives_previous_segment_limit"] = waitUntil {
            controller.player.currentTime().seconds > 1.5 && controller.player.rate > 0
        }

        controller.playContinuously(from: 2)
        controller.playContinuously(from: 3)
        checks["subtitle_rapid_selection_plays_latest_entry"] = waitUntil {
            let seconds = controller.player.currentTime().seconds
            return seconds >= 3.1 && seconds < 3.8 && controller.player.rate > 0
        }
        controller.playContinuously(from: 1)
        controller.pause()
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        checks["subtitle_click_respects_subsequent_pause"] = controller.player.rate == 0 && !controller.isPlaying
        return checks
    }

    private static func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }
}
