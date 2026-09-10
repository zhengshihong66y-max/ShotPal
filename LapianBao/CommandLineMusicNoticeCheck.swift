import AppKit
import SwiftUI

@MainActor
enum CommandLineMusicNoticeCheck {
    static func run() -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let noMatch = MusicRecognitionPresentation(status: .completed, songCount: 0)
        checks["music_no_match_is_neutral"] = noMatch.menuTone == .idle && noMatch.noticeTitle == L10n.text("暂未匹配到歌曲")
        checks["music_no_match_is_not_service_failure"] = noMatch.menuStatus == L10n.text("未匹配") && noMatch.status == .completed
        for (kind, reason) in [("timeout", "音乐识别服务连接超时，请检查网络后重试"),
                               ("runtime", "内置音乐识别依赖缺失，请重新安装完整安装包。"),
                               ("file", "无法读取音频文件") ] {
            let failed = MusicRecognitionPresentation(status: .failed(reason), songCount: 0)
            checks["music_\(kind)_is_neutral_but_truthful"] = failed.menuTone == .idle
                && failed.menuStatus == L10n.text("未完成") && failed.noticeTitle == L10n.text("音乐识别未完成")
                && failed.noticeDetail == L10n.workerMessage(reason) && failed.status == .failed(reason)
        }
        let partial = MusicRecognitionPresentation(status: .failed("服务暂时不可用"), songCount: 2)
        checks["music_partial_result_notice_preserves_context"] = partial.songCount == 2
            && partial.noticeDetail == L10n.text("已保留识别出的歌曲。\("服务暂时不可用")") && partial.menuTone == .idle
        let initial = MusicRecognitionPresentation(status: nil, songCount: 0)
        checks["music_no_attempt_has_no_notice"] = initial.noticeTitle == nil && initial.menuStatus == L10n.text("空闲")
        let running = MusicRecognitionPresentation(status: .running("识别中"), songCount: 0)
        checks["music_running_has_no_failure_notice"] = running.noticeTitle == nil && running.menuTone == .running
        let matched = MusicRecognitionPresentation(status: .completed, songCount: 1)
        checks["music_matched_has_no_notice"] = matched.noticeTitle == nil && matched.menuTone == .completed
        let emptyError = MusicRecognitionPresentation(status: .failed("  "), songCount: 0)
        checks["music_empty_error_has_retry_hint"] = emptyError.noticeDetail == L10n.text("可以稍后重试。")

        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--music-notice-preview-directory"), arguments.count > index + 1 {
            do {
                let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let timeout = MusicRecognitionPresentation(status: .failed("音乐识别服务连接超时，请检查网络后重试"), songCount: 0)
                let longError = MusicRecognitionPresentation(status: .failed(Array(repeating: "服务暂时不可用，请稍后重试。", count: 12).joined(separator: "\n")), songCount: 0)
                for (name, presentation) in [("no-match", noMatch), ("timeout", timeout), ("partial", partial), ("long-error", longError)] {
                    let view = MusicRecognitionNotice(presentation: presentation, retry: {})
                        .frame(width: 640, height: 140)
                        .background(Color(white: 0.13))
                        .environment(\.colorScheme, .dark)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    guard let image = renderer.cgImage else {
                        checks["music_notice_render_\(name)_has_no_red"] = false
                        continue
                    }
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else {
                        checks["music_notice_render_\(name)_has_no_red"] = false
                        continue
                    }
                    try png.write(to: directory.appendingPathComponent("music-\(name).png"))
                    var containsRed = false
                    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                        for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                            if color.redComponent > 0.35 && color.redComponent > color.greenComponent + 0.15
                                && color.redComponent > color.blueComponent + 0.15 { containsRed = true }
                        }
                    }
                    checks["music_notice_render_\(name)_has_no_red"] = !containsRed
                }
            } catch { checks["music_notice_render_io"] = false }
        }
        return checks
    }
}
