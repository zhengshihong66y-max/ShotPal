import SwiftUI

/// Presentation only: unsuccessful recognition stays truthful without a red alert.
struct MusicRecognitionPresentation {
    let status: TranscriptJobStatus?
    let songCount: Int

    var noticeTitle: String? {
        if case .failed = status { return L10n.text("音乐识别未完成") }
        if status == .completed && songCount == 0 { return L10n.text("暂未匹配到歌曲") }
        return nil
    }

    var noticeDetail: String? {
        if case .failed(let message) = status {
            let reason = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = reason.isEmpty ? L10n.text("可以稍后重试。") : L10n.workerMessage(reason)
            return songCount > 0 ? L10n.text("已保留识别出的歌曲。\(detail)") : detail
        }
        if status == .completed && songCount == 0 {
            return L10n.text("可能没有可匹配的背景音乐，也可以稍后重试。")
        }
        return nil
    }

    var menuStatus: String {
        switch status {
        case .running(let message): return message
        case .failed: return L10n.text("未完成")
        case .completed: return songCount == 0 ? L10n.text("未匹配") : L10n.text("已完成")
        default: return L10n.text("空闲")
        }
    }

    var menuTone: VideoAnalysisTone {
        switch status {
        case .running: return .running
        case .completed where songCount > 0: return .completed
        default: return .idle
        }
    }
}

struct MusicRecognitionNotice: View {
    let presentation: MusicRecognitionPresentation
    let retry: () -> Void

    var body: some View {
        if let title = presentation.noticeTitle {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "music.note")
                    .font(.caption)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption)
                    if let detail = presentation.noticeDetail {
                        Text(detail)
                            .font(.caption2)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: retry) {
                    Text(L10n.text("重试识别"))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("music_recognition_notice_retry")
            }
            .foregroundStyle(.secondary)
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: presentation.songCount > 0 ? 48 : 82, alignment: .leading)
            .accessibilityIdentifier("music_recognition_neutral_notice")
        }
    }
}
