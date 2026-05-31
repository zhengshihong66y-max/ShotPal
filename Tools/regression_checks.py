#!/usr/bin/python3
from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def section_between(text: str, start: str, end: str) -> str:
    start_index = text.find(start)
    require(start_index >= 0, f"Missing section start: {start}")
    end_index = text.find(end, start_index + len(start))
    require(end_index >= 0, f"Missing section end after {start}: {end}")
    return text[start_index:end_index]


def main() -> None:
    library_store = read("LapianBao/LibraryStore.swift")
    preview_controller = read("LapianBao/PreviewController.swift")
    content_view = read("LapianBao/ContentView.swift")
    lapianbao_app = read("LapianBao/LapianBaoApp.swift")
    debug_scheme = read("LapianBao.xcodeproj/xcshareddata/xcschemes/LapianBao-Debug.xcscheme")

    require(
        "private var projectDataLoadState: ProjectDataLoadState = .idle" in library_store,
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
        "@Published var progress = 0.0" in preview_controller,
        "PlaybackClock.progress must be published for timeline updates.",
    )
    require(
        "private static let playbackStateInterval = 1.0 / 12.0" in preview_controller,
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
    ]:
        require(
            helper in library_store,
            f"Chrome/curl saved-collection fallback helper is missing: {helper}.",
        )
    require(
        "struct ExternalServiceSelfCheckItem" in library_store
        and "var serviceChecks: [ExternalServiceSelfCheckItem]" in library_store,
        "External service self-check results must be stored with the downloader report.",
    )
    require(
        "func startExternalServiceSelfCheck(force: Bool = true)" in library_store
        and "func startDailyExternalServiceSelfCheckIfNeeded()" in library_store,
        "External service self-check must expose manual and daily entry points.",
    )
    require(
        "func prepareExternalServiceWork()" in library_store,
        "External service work must have a reusable preflight entry point.",
    )
    require(
        lapianbao_app.count("startDailyExternalServiceSelfCheckIfNeeded()") >= 2,
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
            "private func queuedOrImportedInstagramSourceURLs",
            "Xiaohongshu saved import",
        ),
        (
            "private func enqueueRemoteImport",
            "private func updateRemoteImportJob",
            "remote URL import",
        ),
        (
            "func downloadMusic(song:",
            "func startMusicDownloadBatch",
            "single music download",
        ),
        (
            "func startMusicDownloadBatch",
            "private func runMusicDownload",
            "music batch download",
        ),
        (
            "private func runMusicDownload",
            "private func updateMusicDownloadJob",
            "music download worker",
        ),
    ]:
        require(
            "startExternalServiceSelfCheckPreflightIfNeeded()" in section_between(library_store, start, end),
            f"{name} must start the external service self-check preflight.",
        )

    for start, end, name in [
        (
            "private func generateContentNodeTimeline",
            "private func frameTimeline",
            "content node timeline analysis",
        ),
        (
            "private func analyzeFrame",
            "private enum FrameAnalysisState",
            "frame image analysis",
        ),
        (
            "private func runAppleMusicSearch",
            "nonisolated private func normalizedSearch",
            "Apple Music search",
        ),
        (
            "private struct MusicWorkspaceView",
            "private func musicHeader",
            "music workspace external artwork/search",
        ),
        (
            "private struct MusicRecognitionActionColumn",
            "private struct ExportMusicRecognitionRow",
            "YouTube first-result open",
        ),
        (
            "private func generateTranscriptTimeline",
            "private struct SettingsWorkspaceView",
            "transcript timeline analysis",
        ),
    ]:
        require(
            "libraryStore.prepareExternalServiceWork()" in section_between(content_view, start, end),
            f"{name} must prepare external service work.",
        )

    print("Regression checks passed.")


if __name__ == "__main__":
    main()
