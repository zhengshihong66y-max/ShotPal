#!/usr/bin/python3
from __future__ import annotations

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


def main() -> None:
    app_swift = read_tree("LapianBao")
    library_store = app_swift
    preview_controller = app_swift
    content_view = app_swift
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
        and "func startDailyExternalServiceSelfCheckIfNeeded()" in library_store,
        "External service self-check must expose manual and daily entry points.",
    )
    require(
        "func startExternalServiceRepair()" in library_store
        and "repairMode: .always" in library_store,
        "External service self-check must expose an independent update/repair entry point.",
    )
    require(
        "func prepareExternalServiceWork()" in library_store,
        "External service work must have a reusable preflight entry point.",
    )
    require(
        "runDownloaderSelfCheck(" in library_store
        and "repairMode: DownloaderSelfCheckRepairMode = .afterFailure" in library_store
        and "runDownloaderAutoRepair(" in library_store
        and "for report: DownloaderSelfCheckReport" in library_store
        and "removeUnresponsiveAppManagedYTDLP()" in library_store
        and "安装 Homebrew ffmpeg" in library_store,
        "Downloader self-check repair must be target-aware and cover stale app-managed yt-dlp plus missing ffmpeg.",
    )
    require(
        "--lapianbao-self-repair" in app_swift
        and "--lapianbao-self-check" in app_swift,
        "External service self-check must be runnable from a command-line self-check hook.",
    )
    require(
        app_swift.count("startDailyExternalServiceSelfCheckIfNeeded()") >= 2,
        "App activation and launch setup must trigger daily external service self-checks.",
    )

    for service_key in [
        "ytdlp",
        "ffmpeg",
        "youtube",
        "chromeCookieImport",
        "appleMusicSearch",
        "cobalt",
        "xiaohongshuWeb",
        "customImportAPI",
        "ollama",
    ]:
        require(
            f'key: "{service_key}"' in library_store,
            f"External self-check must cover service: {service_key}.",
        )

    for start, end, name in [
        (
            "func importLatestInstagramSavedFromChrome",
            "func importLatestXiaohongshuSavedVideosFromChrome",
            "Instagram saved import",
        ),
        (
            "func importLatestXiaohongshuSavedVideosFromChrome",
            "func queuedOrImportedInstagramSourceURLs",
            "Xiaohongshu saved import",
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
            "func generateContentNodeTimeline",
            "content node timeline analysis",
        ),
        (
            "private func analyzeFrame",
            "frame image analysis",
        ),
        (
            "private func runAppleMusicSearch",
            "Apple Music search",
        ),
        (
            "struct MusicWorkspaceView",
            "music workspace external artwork/search",
        ),
        (
            "struct MusicRecognitionActionColumn",
            "YouTube first-result open",
        ),
        (
            "private func generateTranscriptTimeline",
            "transcript timeline analysis",
        ),
    ]:
        require(
            "libraryStore.prepareExternalServiceWork()" in section_after(content_view, start),
            f"{name} must prepare external service work.",
        )

    print("Regression checks passed.")


if __name__ == "__main__":
    main()
