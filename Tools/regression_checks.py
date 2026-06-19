#!/usr/bin/python3
from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def read_tree(relative: str, pattern: str = "*.swift") -> str:
    root = ROOT / relative
    return "\n\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(root.rglob(pattern))
        if path.is_file()
    )


def read_sources(relative: str, pattern: str = "*.swift") -> dict[str, str]:
    root = ROOT / relative
    return {
        path.relative_to(ROOT).as_posix(): path.read_text(encoding="utf-8")
        for path in sorted(root.rglob(pattern))
        if path.is_file()
    }


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def section_between(text: str, start: str, end: str) -> str:
    start_index = text.find(start)
    require(start_index >= 0, f"Missing section start: {start}")
    end_index = text.find(end, start_index + len(start))
    require(end_index >= 0, f"Missing section end after {start}: {end}")
    return text[start_index:end_index]


def section_after(text: str, start: str, window: int = 3_000) -> str:
    start_index = text.find(start)
    require(start_index >= 0, f"Missing section start: {start}")
    return text[start_index : start_index + window]


def line_count(text: str) -> int:
    return len(text.splitlines())


def require_file_line_limits(sources: dict[str, str], limits: dict[str, int]) -> None:
    for relative, maximum in limits.items():
        require(relative in sources, f"Missing expected source file for architecture checks: {relative}.")
        actual = line_count(sources[relative])
        require(
            actual <= maximum,
            f"{relative} has {actual} lines; keep it under {maximum} or split responsibilities first.",
        )


def require_tree_line_limit(
    sources: dict[str, str],
    prefix: str,
    maximum: int,
    message: str,
) -> None:
    offenders = [
        f"{relative} ({line_count(text)} lines)"
        for relative, text in sources.items()
        if relative.startswith(prefix) and line_count(text) > maximum
    ]
    require(not offenders, f"{message}: {', '.join(offenders)}.")


def require_regex_allowlist(
    sources: dict[str, str],
    pattern: str,
    allowed_files: set[str],
    message: str,
) -> None:
    regex = re.compile(pattern)
    offenders = [
        relative
        for relative, text in sources.items()
        if regex.search(text) and relative not in allowed_files
    ]
    require(not offenders, f"{message}: {', '.join(offenders)}.")


def require_app_storage_keys_are_centralized(sources: dict[str, str]) -> None:
    regex = re.compile(r"@AppStorage\((?!AppSettings\.Key\.)")
    offenders = [
        relative
        for relative, text in sources.items()
        if regex.search(text)
    ]
    require(not offenders, f"@AppStorage keys must come from AppSettings.Key: {', '.join(offenders)}.")


def require_video_media_generation_guardrails(sources: dict[str, str], app_swift: str) -> None:
    video_tiles = sources.get("LapianBao/Views/AppShell/ContentView+VideoTiles.swift", "")
    require(
        "queueMetadataLoadIfNeeded(for: video, allowThumbnailGeneration: true)" in video_tiles,
        "Visible video tiles must queue thumbnail generation for uncached newly added videos.",
    )

    indexes = sources.get("LapianBao/Stores/LibraryStore+IndexesAndBasics.swift", "")
    select_video_section = section_between(
        indexes,
        "func selectVideo(_ video: VideoItem, autoplay: Bool)",
        "func selectVideo(path: String",
    )
    require(
        "loadMetadataIfNeeded(for: video, priority: .userInitiated, allowThumbnailGeneration: true)" in select_video_section,
        "Selecting a video must request full media metadata and thumbnail generation.",
    )
    require(
        "loadWaveform(for: video)" in select_video_section
        and "loadFrameStrip(for: video)" in select_video_section
        and "loadCachedSceneCuts(for: video)" in select_video_section,
        "Selecting a video must prepare waveform, frame strip, and cached scene cuts through the shared store path.",
    )

    remote_import_section = section_between(
        app_swift,
        "if let importedVideo = self?.integrateDownloadedVideo",
        "func updateRemoteImportJob",
    )
    require(
        "loadMetadataIfNeeded(for: importedVideo, allowThumbnailGeneration: true)" in remote_import_section,
        "Remote imports must warm full media render state even when the imported video is auto-selected.",
    )

    match = re.search(r"launchVideoReconcileDelay:\s*TimeInterval\s*=\s*([0-9.]+)", app_swift)
    require(match is not None, "LibraryStore must define launchVideoReconcileDelay.")
    require(
        float(match.group(1)) <= 30.0,
        "Launch video reconcile must not wait minutes before discovering newly added local files.",
    )


def require_scene_detection_progress_guardrails(sources: dict[str, str]) -> None:
    external_runner = sources.get("LapianBao/ExternalProcessRunner.swift", "")
    require(
        "errorLineHandler: (@Sendable (String) -> Void)? = nil" in external_runner
        and "PipeLineCollector()" in external_runner,
        "ExternalProcessRunner must support streaming stderr line handlers for precise tool progress.",
    )

    scene_detection = sources.get("LapianBao/Stores/LibraryStore+SceneDetection.swift", "")
    require(
        'sceneDetectionProgressLinePrefix = "LAPIANBAO_PROGRESS\\t"' in scene_detection
        and "sceneDetectionProgress(from: line)" in scene_detection
        and "errorLineHandler: { line in" in scene_detection,
        "Scene detection must parse structured TransNet progress lines while the process is running.",
    )
    require(
        "0.86 + Self.normalizedProgress(progress) * 0.13" in scene_detection
        and "progressCallback?(Double(index + 1) / Double(orderedCutTimes.count))" in scene_detection,
        "Scene detection progress must include scene thumbnail generation, not only the TransNet process.",
    )

    script = read("Tools/detect_scene_cuts_transnet.py")
    require(
        'PROGRESS_PREFIX = "LAPIANBAO_PROGRESS\\t"' in script
        and "run_async(pipe_stdout=True, pipe_stderr=True)" in script
        and "predict_frames_with_progress" in script
        and "emit_progress(0.45 + (processed_frames / max(1, len(frames))) * 0.37)" in script,
        "TransNet helper must stream extraction and model inference progress.",
    )

    status_tiles = sources.get("LapianBao/Views/Components/StatusAndSceneTiles.swift", "")
    require(
        'String(format: "%.1f%%", percent)' in status_tiles,
        "Progress text must display fractional percentages instead of integer-only scene progress.",
    )


def require_interaction_hit_testing_guardrails(sources: dict[str, str], guidance: str) -> None:
    require(
        "全窗口遮罩背景" in guidance
        and "`Button { Color... }`" in guidance
        and "只能监听 `.keyDown` 和 `.keyUp`" in guidance
        and "命中检查" in guidance,
        "AGENTS must document hit-testing guardrails for overlays and app-level event monitors.",
    )

    app_delegate = sources.get("LapianBao/LapianBaoApp.swift", "")
    require(
        ".leftMouseDown" not in app_delegate
        and ".rightMouseDown" not in app_delegate
        and ".otherMouseDown" not in app_delegate,
        "LapianBaoApp.swift must not install app-level mouse-down monitors; they can steal clicks before controls receive them.",
    )
    require(
        "makeFirstResponder(nil)" not in app_delegate,
        "LapianBaoApp.swift must not reset first responder from app-level mouse handling; this can break SwiftUI click delivery.",
    )

    overlays = sources.get("LapianBao/Views/AppShell/ContentView+Overlays.swift", "")
    require(
        "Button(action: closeImportPanel)" not in overlays,
        "Import overlay backdrop must not be a full-window Button; use Color + onTapGesture instead.",
    )
    require(
        re.search(
            r"Color\.black\.opacity\([^)]+\)[\s\S]{0,280}"
            r"\.onTapGesture\s*\{\s*closeImportPanel\(\)\s*\}[\s\S]{0,160}"
            r"\.accessibilityHidden\(true\)",
            overlays,
        )
        is not None,
        "Import overlay backdrop must stay as non-control Color + onTapGesture and be accessibilityHidden(true).",
    )


def require_architecture_guardrails(sources: dict[str, str]) -> None:
    agents = read("AGENTS.md")
    require(
        "## 架构护栏和收尾边界" in agents
        and "Tools/regression_checks.py" in agents
        and "LibraryStore.swift` 只能保留状态壳" in agents,
        "AGENTS must document the current architecture guardrails before checks can enforce them.",
    )
    require(
        "LapianBao/AppSettings.swift" in sources
        and "enum AppSettings" in sources["LapianBao/AppSettings.swift"],
        "AppSettings.swift must own app preference keys and UserDefaults access.",
    )
    require(
        "LapianBao/AppEventBus.swift" in sources
        and "enum AppEventBus" in sources["LapianBao/AppEventBus.swift"],
        "AppEventBus.swift must own app-wide custom notifications.",
    )
    require(
        "LapianBao/ExternalProcessRunner.swift" in sources
        and "enum ExternalProcessRunner" in sources["LapianBao/ExternalProcessRunner.swift"],
        "ExternalProcessRunner.swift must own short-lived external command execution.",
    )
    require(
        "LapianBao/ProjectRepository.swift" in sources
        and "enum ProjectRepository" in sources["LapianBao/ProjectRepository.swift"],
        "ProjectRepository.swift must own project hidden-file paths and JSON persistence helpers.",
    )
    require_interaction_hit_testing_guardrails(sources, agents)

    require_file_line_limits(
        sources,
        {
            "LapianBao/LibraryStore.swift": 450,
            "LapianBao/ContentView.swift": 650,
            "LapianBao/LapianBaoApp.swift": 260,
            "LapianBao/AppChrome.swift": 950,
            "LapianBao/PreviewController.swift": 850,
            "LapianBao/AppSettings.swift": 220,
            "LapianBao/AppEventBus.swift": 180,
            "LapianBao/ExternalProcessRunner.swift": 220,
            "LapianBao/ProjectRepository.swift": 240,
            "LapianBao/Models/LibraryModels.swift": 1_300,
        },
    )
    require_tree_line_limit(
        sources,
        "LapianBao/Stores/",
        2_200,
        "Store extension files should stay small enough for AI review",
    )
    require_tree_line_limit(
        sources,
        "LapianBao/Views/",
        2_200,
        "View files should stay small enough for AI review",
    )

    require_regex_allowlist(
        sources,
        r"\bProcess\(",
        {
            "LapianBao/ExternalProcessRunner.swift",
            "LapianBao/Models/LibraryInfrastructureModels.swift",
            "LapianBao/PreviewController.swift",
            "LapianBao/Stores/LibraryStore+LaunchAndRemoteImports.swift",
            "LapianBao/Stores/LibraryStore+MetadataAndExportHelpers.swift",
            "LapianBao/Stores/LibraryStore+MusicDetection.swift",
            "LapianBao/Stores/LibraryStore+RemoteTranscoding.swift",
            "LapianBao/Stores/LibraryStore+YTDLPDownload.swift",
        },
        "Short-lived Process launching must go through ExternalProcessRunner; remaining direct launches must stay in known streaming or proxy boundaries",
    )
    require_regex_allowlist(
        sources,
        r"UserDefaults\.standard",
        {
            "LapianBao/AppSettings.swift",
        },
        "UserDefaults access must stay inside AppSettings",
    )
    require_app_storage_keys_are_centralized(sources)
    require_video_media_generation_guardrails(sources, "\n\n".join(sources.values()))
    require_scene_detection_progress_guardrails(sources)
    require_regex_allowlist(
        sources,
        r"NotificationCenter\.default",
        {
            "LapianBao/AppChrome.swift",
            "LapianBao/AppEventBus.swift",
            "LapianBao/PreviewController.swift",
            "LapianBao/Views/Music/AudioMusicComponents.swift",
            "LapianBao/Views/Preview/PreviewPanelView+ExportPanel.swift",
        },
        "NotificationCenter access must stay inside AppEventBus, AppKit window observers, or local AVPlayer observers",
    )
    require_regex_allowlist(
        sources,
        r"lapianBao[A-Za-z]+",
        {
            "LapianBao/AppEventBus.swift",
        },
        "Custom lapianBao notifications must stay inside AppEventBus",
    )
    require_regex_allowlist(
        sources,
        r"\.lapianbao[A-Za-z0-9_]*\.json|\.lapianbaotags\.json",
        {
            "LapianBao/ProjectRepository.swift",
        },
        "Project-owned hidden JSON file names must stay inside ProjectRepository",
    )


def main() -> None:
    swift_sources = read_sources("LapianBao")
    require_architecture_guardrails(swift_sources)

    app_swift = "\n\n".join(swift_sources.values())
    library_store = app_swift
    preview_controller = app_swift
    content_view = app_swift
    launch_imports = swift_sources.get("LapianBao/Stores/LibraryStore+LaunchAndRemoteImports.swift", "")
    debug_scheme = read("LapianBao.xcodeproj/xcshareddata/xcschemes/LapianBao-Debug.xcscheme")

    require(
        "final class AppStartupCoordinator" in app_swift
        and "final class AppWindowManager" in app_swift
        and "enum StartupDiagnostics" in app_swift,
        "Startup must stay split into coordinator, window manager, and diagnostics.",
    )
    require(
        "StartupDiagnostics.mark(.mainEntered)" in app_swift
        and "StartupDiagnostics.mark(.didFinishLaunching)" in app_swift
        and "StartupDiagnostics.mark(.mainWindowOrderedFront)" in app_swift,
        "Startup diagnostics must mark pre-main, AppDelegate, and window-ordering stages.",
    )
    launch_restore_section = section_between(
        launch_imports,
        "func loadLastLibraryForLaunch()",
        "func scheduleInitialVideoSelectionAfterLaunch",
    )
    require(
        "includeThumbnailData: false" in launch_restore_section
        and "CachedVideoLibrarySummary" in library_store,
        "Launch library restore must use a lightweight video cache and avoid decoding cached thumbnail data before the list appears.",
    )
    bookmark_restore_section = section_between(
        launch_imports,
        "func restoreLastLibraryBookmark()",
        "func stopAccessingScopedLibrary()",
    )
    require(
        bookmark_restore_section.find("startAccessingSecurityScopedResource()") >= 0
        and bookmark_restore_section.find("FileManager.default.fileExists") > bookmark_restore_section.find("startAccessingSecurityScopedResource()"),
        "Restored security-scoped bookmarks must start access before probing protected library folders.",
    )
    project_file = read("LapianBao.xcodeproj/project.pbxproj")
    require(
        "INFOPLIST_KEY_NSDownloadsFolderUsageDescription" in project_file
        and "INFOPLIST_KEY_NSDocumentsFolderUsageDescription" in project_file
        and "INFOPLIST_KEY_NSDesktopFolderUsageDescription" in project_file,
        "Generated Info.plist settings must explain access to user-selected protected library folders.",
    )

    require(
        "projectDataLoadState: ProjectDataLoadState = .idle" in library_store,
        "LibraryStore must track project data load state.",
    )
    require(
        "guard projectDataLoadState == .loaded else { return }" in library_store,
        "Project data saves must not write before project data is loaded.",
    )
    require(
        "guard projectDataDirty || projectSaveTask != nil else { return }" in library_store,
        "Project data flush must only write dirty or pending snapshots.",
    )
    require(
        "projectDataLoadState = .loading" in library_store and "projectDataLoadState = .loaded" in library_store,
        "Project data load state must move through loading and loaded states.",
    )
    require(
        "@Published private(set) var value = PlaybackClockValue()" in preview_controller
        and "var progress: Double { value.progress }" in preview_controller,
        "PlaybackClock.progress must be published for timeline updates.",
    )
    require(
        "private static let playbackStateInterval = 1.0 / 30.0" in preview_controller,
        "Playback clock must stay responsive enough for timeline work.",
    )
    require(
        "musicDetectionStatusByVideoPath[path] = .failed(error.localizedDescription)" in library_store,
        "Music detection failures must surface as failed states.",
    )
    require(
        "musicsByVideoPath[path] = []\n" not in library_store,
        "Music detection must not clear existing results before success.",
    )
    scene_detection_section = section_between(
        library_store,
        "nonisolated static func performSceneDetection",
        "nonisolated struct TransNetDetectionResult",
    )
    require(
        "withTaskCancellationHandler" in scene_detection_section
        and "processRegistry.cancelRunningProcess()" in scene_detection_section
        and "reader.cancelReading()" in scene_detection_section,
        "Scene detection cancellation must stop the active TransNet process and local frame reader.",
    )
    make_scene_cuts_section = section_between(
        library_store,
        "nonisolated static func makeSceneCuts",
        "nonisolated static func removeDuplicateThumbnailCuts",
    )
    require(
        "isPlaceholder" in make_scene_cuts_section
        and "SceneCut(" in make_scene_cuts_section
        and "continue" not in make_scene_cuts_section,
        "Scene detection must preserve detected cut times even when thumbnail generation fails.",
    )
    finish_scene_detection_section = section_between(
        library_store,
        "func finishSceneDetection",
        "func deleteSceneRecognition",
    )
    require(
        "setSceneCuts(cuts, for: path)" in finish_scene_detection_section
        and "guard !cuts.isEmpty" not in finish_scene_detection_section,
        "Scene detection must record completed empty results instead of restarting forever.",
    )
    cached_scene_entry_section = section_between(
        library_store,
        "func validCachedSceneCutEntry",
        "func hasSceneRecognitionResult",
    )
    require(
        "!entry.cutTimes.isEmpty" not in cached_scene_entry_section,
        "Scene cut cache validation must allow completed empty scene results.",
    )
    store_scene_cache_section = section_between(
        library_store,
        "func storeSceneCutCache",
        "func sceneCutCacheThumbnailData",
    )
    require(
        "guard !cuts.isEmpty" not in store_scene_cache_section,
        "Scene cut cache must persist completed empty scene results.",
    )
    require(
        "job.errorMessage" in content_view and "字幕导出失败" in content_view,
        "Transcript export failures must be visible in the export panel.",
    )
    require(
        "selectedDebuggerIdentifier = \"Xcode.DebuggerFoundation.Debugger.LLDB\"" in debug_scheme,
        "LapianBao-Debug scheme must keep LLDB enabled.",
    )
    require(
        "copyCGImage(" not in library_store,
        "Frame export must use async CGImage generation instead of deprecated copyCGImage(at:actualTime:).",
    )
    for helper in [
        "withExportedChromeCookies",
        "runCurlFetch",
        "InstagramSavedFeedResponse",
        "instagramVideoLinks",
        "xiaohongshuVideoLinks",
        "isTerminalRemoteImportStatus",
        "remoteImportJobCanReceiveWorkerProgress",
        "ChromeCookieFileCache",
        "prewarmChromeCookieCache",
        "cachedOrExportedChromeCookieURL",
        "instagramBundledImportURL",
        "downloadInstagramCarouselBundleIfNeeded",
        "concatenateVideosWithFFmpeg",
    ]:
        require(
            helper in library_store,
            f"Chrome/curl saved-collection fallback helper is missing: {helper}.",
        )
    require(
        "chromeCookieFileCache.validCookieURL()" in library_store
        and "chromeCookieFileCache.finishRefresh(with: cookieURL)" in library_store,
        "Chrome cookies must be cached so saved-collection sync does not export cookies on every click.",
    )
    require(
        "libraryStore.prewarmSavedCollectionCookieCache()" in content_view,
        "Opening the import panel must prewarm Chrome cookies for saved-collection sync.",
    )
    require(
        "libraryStore.prewarmSavedCollectionCookieCache()" in app_swift,
        "App launch must prewarm Chrome cookies before the user clicks saved-collection sync.",
    )
    require(
        'links.append("https://www.instagram.com/p/\\(parentCode)/")' in library_store
        and 'return "\\(content.type):\\(content.shortcode)"' in library_store,
        "Instagram carousel imports must queue and de-dupe by base post so carousel videos can be bundled.",
    )
    require(
        "Self.isTerminalRemoteImportStatus(previousJob.status)" in library_store
        and "updatedJobs[index] = previousJob" in library_store,
        "Remote import jobs must not regress from terminal states back to active progress states.",
    )
    require(
        "if let progress {\n                        job.downloadProgress = Self.normalizedProgress(progress)" in library_store
        and "else if progress == nil {\n                        job.downloadSpeed = nil" in library_store,
        "Remote import progress callbacks must preserve the last percent on yt-dlp speed-only or post-processing lines.",
    )
    require(
        "finalizingCallback?(1)\n        let finalURL" in library_store
        and "job.downloadProgress = Self.normalizedProgress(progress)" in library_store,
        "Remote import finalizing must keep determinate progress instead of clearing the bar.",
    )
    require(
        "struct ExternalServiceSelfCheckItem" in library_store
        and "var serviceChecks: [ExternalServiceSelfCheckItem]" in library_store,
        "External service self-check results must be stored with the downloader report.",
    )
    require(
        "var problemLocation: String?" in library_store
        and "var repairSummary: String?" in library_store,
        "External service self-check must persist problem location and repair summary.",
    )
    require(
        "func startExternalServiceSelfCheck(force: Bool = true)" in library_store
        and "func startExternalServiceSelfCheckPreflightIfNeeded()" in library_store,
        "External service self-check must expose manual and preflight entry points.",
    )
    require(
        "repairMode = .always" in app_swift
        and "--lapianbao-self-repair" in app_swift,
        "External service self-check must expose a command-line update/repair entry point.",
    )
    require(
        "func prepareExternalServiceWork()" in library_store,
        "External service work must have a reusable preflight entry point.",
    )
    require(
        "runDownloaderSelfCheck(" in library_store
        and "repairMode: DownloaderSelfCheckRepairMode = .afterFailure" in library_store
        and "检查 yt-dlp 最新版本" in library_store
        and "fetchLatestNightlyYTDLPRelease" in library_store
        and "下载最新 yt-dlp" in library_store
        and "verifySHA256Digest" in library_store
        and "replaceAppManagedYTDLP" in library_store
        and "removeUnresponsiveAppManagedYTDLP()" in library_store
        and "installAppManagedNightlyYTDLP" in library_store,
        "yt-dlp self-check must follow the latest-version, verified-download, safe-replacement flow.",
    )
    require(
        "--lapianbao-self-repair" in app_swift
        and "--lapianbao-self-check" in app_swift,
        "External service self-check must be runnable from a command-line self-check hook.",
    )
    require(
        library_store.count("startExternalServiceSelfCheckPreflightIfNeeded()") >= 4,
        "Import and media work must trigger downloader self-check preflight checks.",
    )

    for service_key in [
        "ytdlp",
    ]:
        require(
            f'key: "{service_key}"' in library_store,
            f"Downloader self-check must cover service: {service_key}.",
        )

    for start, end, name in [
        (
            "func latestInstagramSavedImportCandidatesFromChrome",
            "func latestXiaohongshuSavedVideoImportCandidatesFromChrome",
            "Instagram saved candidate scan",
        ),
        (
            "func latestXiaohongshuSavedVideoImportCandidatesFromChrome",
            "func recordInstagramSavedSyncSnapshot",
            "Xiaohongshu saved candidate scan",
        ),
        (
            "func enqueueRemoteImport",
            "func updateRemoteImportJob",
            "remote URL import",
        ),
        (
            "func downloadMusic(song:",
            "func startMusicDownloadBatch",
            "single music download",
        ),
        (
            "func startMusicDownloadBatch",
            "func runMusicDownload",
            "music batch download",
        ),
        (
            "func runMusicDownload",
            "func updateMusicDownloadJob",
            "music download worker",
        ),
    ]:
        require(
            "startExternalServiceSelfCheckPreflightIfNeeded()" in section_between(library_store, start, end),
            f"{name} must start the external service self-check preflight.",
        )

    for start, name in [
        (
            "struct MusicWorkspaceView",
            "music workspace external artwork/search",
        ),
        (
            "struct MusicRecognitionActionColumn",
            "YouTube first-result open",
        ),
        (
            "func startContentRecognitionIfNeeded",
            "content transcript recognition",
        ),
    ]:
        require(
            "libraryStore.prepareExternalServiceWork()" in section_after(content_view, start),
            f"{name} must prepare external service work.",
        )

    print("Regression checks passed.")


if __name__ == "__main__":
    main()
