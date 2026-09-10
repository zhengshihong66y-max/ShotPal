import SwiftUI

/// Empty recognition is a completed attempt, not missing audio or an idle task.
struct TranscriptTimelineState {
    let segments: [TranscriptSegment]?
    let status: TranscriptJobStatus?

    var hasWords: Bool { !(segments ?? []).isEmpty }
    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }
    var hasFinishedAttempt: Bool {
        if segments != nil { return true } // Includes a persisted empty result.
        switch status {
        case .completed, .failed: return true
        default: return false
        }
    }
    var shouldStartAutomatically: Bool {
        !isRunning && !hasFinishedAttempt
    }
    var canExpand: Bool { hasWords || (!isRunning && hasFinishedAttempt) }
    var showsWaveformFallback: Bool { !hasWords }
    var message: String {
        switch status {
        case .running: return L10n.text("正在识别字幕，仍可播放和拖动下方波形。")
        case .failed(let message): return L10n.text("字幕识别失败：\(message)；音频仍可正常播放。")
        default:
            return hasFinishedAttempt
                ? L10n.text("未识别出可用文字，可能是音乐或难以辨认的人声。仍可播放、拖动波形或重试。")
                : L10n.text("尚未识别字幕，音频仍可正常播放。")
        }
    }
}

struct TranscriptTimelineFallback<Waveform: View>: View {
    let state: TranscriptTimelineState
    let retry: () -> Void
    @ViewBuilder let waveform: () -> Waveform

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(state.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: retry) {
                    Text(state.hasFinishedAttempt ? L10n.text("重试转写") : L10n.text("识别字幕"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(state.isRunning ? 0.35 : 0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                    .buttonStyle(.plain)
                    .disabled(state.isRunning)
                    .accessibilityIdentifier("transcript_fallback_retry")
            }
            waveform()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 40)
                .accessibilityIdentifier("transcript_fallback_waveform")
        }
        .padding(8)
        .accessibilityIdentifier("transcript_timeline_fallback")
    }
}
