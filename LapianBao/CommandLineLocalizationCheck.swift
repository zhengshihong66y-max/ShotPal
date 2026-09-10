import AppKit
import Darwin
import Foundation

@MainActor
enum CommandLineLocalizationCheck {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--lapianbao-localization-check") else { return }
        let english = Bundle.main.preferredLocalizations.first == "en"
        let home = AppWorkspace.home.title
        let expectedHome = english ? "Home" : "主页"
        var checks: [String: Bool] = [
            "app_language_resolves": home == expectedHome,
            "menu_label": L10n.text("打开文件夹") == (english ? "Open Folder" : "打开文件夹"),
            "brand": L10n.text("拉片宝") == (english ? "ShotPal Pro" : "拉片宝"),
            "localized_bundle_name": Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == (english ? "ShotPal Pro" : "拉片宝"),
            "interpolation": L10n.text("\(3) 个视频") == (english ? "3 videos" : "3 个视频"),
            "user_content_preserved": L10n.text("视频：\("我的电影 {1} 100%")") == (english ? "Video: 我的电影 {1} 100%" : "视频：我的电影 {1} 100%"),
            "reordered_arguments": L10n.render("{1} / {0}", arguments: ["{1}", "100% 视频"]) == "100% 视频 / {1}",
            "stored_enum_unchanged": ExportPanelFilter.images.rawValue == "图片",
            "stored_folder_unchanged": LibraryStore.videoFolderName == "拉片宝视频下载",
            "platform_routing_unchanged": VideoSourcePlatform.xiaohongshu.rawValue == "小红书",
            "worker_dynamic_error": L10n.workerMessage("音乐识别服务请求失败（ConnectionError），请检查网络后重试") == (english ? "Music recognition request failed (ConnectionError). Check the network and retry." : "音乐识别服务请求失败（ConnectionError），请检查网络后重试"),
            "worker_unknown_detail_preserved": L10n.workerMessage("fixture {0} 网络 100%") == "fixture {0} 网络 100%"
        ]
        let url = URL(string: "https://www.youtube.com/watch?v=fixture")!
        let login = LibraryStore.userFacingYTDLPFailureMessage("Sign in to confirm you’re not a bot", sourceURL: url, usedCookies: false)
        checks["localized_login_still_triggers_retry"] = LibraryStore.isYouTubeBotVerificationFailure(login)
        checks["localized_music_cache_stays_classified"] = LibraryScanProgress(message: L10n.text("正在生成音乐缓存"), completed: 0, total: 1).isMusicWaveformCacheProgress
        let export = LibraryStore.transcriptExportMarkdown(videoName: "User 中文", videoFileName: "fixture.mp4", segments: [], sceneCutTimes: [], duration: 4)
        checks["export_heading"] = export.contains(english ? "## Original transcript" : "## 原脚本")
        checks["export_preserves_user_title"] = export.contains("# User 中文")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("shotpal-language-cache-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            MusicWorkspaceDisplayCache.save(projection: .empty, signature: "fixture", in: temp)
            checks["same_language_cache_restores"] = MusicWorkspaceDisplayCache.loadLatest(in: temp) != nil
            let url = ProjectRepository.musicWorkspaceCacheURL(in: temp)
            var cache = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            cache["language"] = english ? "zh-Hans" : "en"
            try JSONSerialization.data(withJSONObject: cache).write(to: url)
            checks["previous_language_cache_is_rebuilt"] = MusicWorkspaceDisplayCache.loadLatest(in: temp) == nil
        } catch { checks["language_cache_io"] = false }
        let report: [String: Any] = ["status": checks.values.allSatisfy { $0 } ? "passed" : "failed", "language": Bundle.main.preferredLocalizations, "checks": checks]
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        Darwin.exit(checks.values.allSatisfy { $0 } ? 0 : 1)
    }
}
