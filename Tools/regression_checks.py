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
        'return "\\(percent)%"' in status_tiles,
        "Progress text must display integer percentages for consistent compact UI status text.",
    )


def require_music_library_projection_guardrails(sources: dict[str, str]) -> None:
    content_view = sources.get("LapianBao/ContentView.swift", "")
    require(
        "@StateObject var musicWorkspaceViewModel = MusicWorkspaceViewModel()" in content_view
        and "@State var hasMountedMusicWorkspace = false" in content_view
        and "MusicWorkspaceView(\n                    viewModel: musicWorkspaceViewModel" in content_view
        and ".opacity(presentedAppWorkspace == .music ? 1 : 0)" in content_view
        and ".allowsHitTesting(presentedAppWorkspace == .music)" in content_view,
        "Music workspace must stay mounted after first open so switching away does not discard its rendered state.",
    )

    projection_builder = sources.get("LapianBao/Views/Music/MusicWorkspaceProjectionBuilder.swift", "")
    projection_models = sources.get("LapianBao/Views/Music/MusicWorkspaceModels.swift", "")
    make_projection = section_between(
        projection_builder,
        "func makeProjection() -> MusicWorkspaceProjection",
        "func sortedMusicLibraryEntries",
    )
    require(
        "groupedLocalMusicAssets(from: folderLocalMusicAssets)" in make_projection
        and "displayedLocalMusicGroups" in make_projection
        and "localMusicLibraryIdentityKeys(from: displayedLocalMusicGroups)" in make_projection,
        "Music workspace projection must include scanned local music files, not only recognized songs.",
    )
    require(
        "localGroups: []" not in make_projection
        and "displayedLocalMusicGroups: []" not in make_projection,
        "Music workspace projection must not drop local music groups with empty-array placeholders.",
    )
    require(
        "musicArtistTagLookup(from: recognizedAssets, localGroups: displayedLocalMusicGroups)" in make_projection
        and "repeatedMusicArtistTagLookup" not in projection_builder
        and "static let singleSongArtistFilterCollapseThreshold = 24" in projection_builder
        and "guard songCount > 0 else { return nil }" in projection_builder
        and "singleSongArtistCount > Self.singleSongArtistFilterCollapseThreshold" in projection_builder
        and "entry.value.songCount > 1 || selectedArtistValues.contains(entry.value.displayName)" in projection_builder
        and "guard songCount > 1 else { return nil }" not in projection_builder,
        "Music artist filters must include single-song artists until the adaptive single-song artist threshold is exceeded.",
    )
    require(
        "Task.detached(priority: .userInitiated)" in projection_models
        and "markInitialProjectionReady()" in projection_models,
        "Music workspace projection building must run off the main actor and only mark readiness after projection data is applied.",
    )
    require(
        "isInitialProjectionReady" in projection_models
        and "isInitialHeavyMediaReady" in projection_models
        and "isInitialRenderPrewarmReady" not in projection_models
        and "&& isInitialRenderPrewarmReady" not in projection_models,
        "Music first-open readiness must wait for projection and heavy row media, but not for full-library waveform render prewarm.",
    )
    require(
        "MusicWorkspaceDisplayCacheFile" in projection_models
        and "MusicWorkspaceDisplayCache" in projection_models
        and "static func loadLatest(in libraryURL: URL)" in projection_models
        and "applyingAdaptiveArtistFilterLimit(to: cache.projection)" in projection_models
        and "MusicWorkspaceProjectionBuilder.singleSongArtistFilterCollapseThreshold" in projection_models
        and "MusicWorkspaceProjection: Codable" in projection_models
        and "ProjectRepository.musicWorkspaceCacheURL" in projection_models,
        "Music workspace display projection must be persisted as a cache and normalize adaptive artist filters when restored.",
    )

    music_workspace = sources.get("LapianBao/Views/Music/MusicWorkspaceView.swift", "")
    require(
        "@ObservedObject var viewModel: MusicWorkspaceViewModel" in music_workspace
        and "viewModel.cancelTasks()" not in music_workspace
        and "MusicWorkspaceDisplayCache.loadLatest(in: libraryURL)" in music_workspace
        and "makeMusicWorkspaceDisplayCacheSignature" not in music_workspace
        and "MusicWorkspaceDisplayCache.load(in: libraryURL, matching:" not in music_workspace
        and "MusicWaveformCacheProgressOverlay" not in music_workspace
        and "musicWaveformScanProgressCard" not in music_workspace
        and "正在准备音乐界面" not in music_workspace
        and "暂无两首以上作者" not in music_workspace
        and "暂无可显示作者" in music_workspace
        and "isWorkspaceWarmupVisible" not in music_workspace,
        "Music workspace view must reuse the retained view model and avoid legacy per-task progress surfaces.",
    )
    require(
        "musicCacheLoadingProgressBar" in music_workspace
        and ".overlay(alignment: .bottom)" in music_workspace
        and "viewModel.launchPreparationStatus.isLoading" in music_workspace,
        "Music workspace cache loading must be represented by one short total progress bar at the bottom of the page.",
    )
    music_cache_progress_bar = section_between(
        music_workspace,
        "private func musicCacheLoadingProgressBar",
        "private var musicTagFilterButton",
    )
    require(
        "ProgressView(value: status.progress)" in music_cache_progress_bar
        and "progressPercentText(status.progress)" in music_cache_progress_bar
        and "Text(status.message" not in music_cache_progress_bar
        and "status.message.isEmpty" not in music_cache_progress_bar,
        "Music cache progress bar must remove the left status/count text and keep only the bar plus right percentage.",
    )
    require(
        "prewarmMusicWorkspaceDisplayCachesForScroll" in music_workspace
        and "MusicWorkspaceDisplayCacheHydrator.waveformRenderPrewarmRequests" in music_workspace
        and "MusicArtworkCache.prewarmCachedArtwork" in music_workspace
        and "initialMusicRowLimit" not in music_workspace
        and "initialSearchRowLimit" not in music_workspace
        and ".prefix(Self.initial" not in music_workspace,
        "Music workspace scrolling must preload full cached row media instead of revealing only an initial row subset.",
    )
    content_view = sources.get("LapianBao/ContentView.swift", "")
    library_store = sources.get("LapianBao/LibraryStore.swift", "")
    music_launch_preparation = sources.get("LapianBao/Views/AppShell/ContentView+MusicLaunchPreparation.swift", "")
    app_shell_music_launch = content_view + "\n" + music_launch_preparation
    require(
        "musicWorkspaceLaunchPreparationID(containerWidth:" in app_shell_music_launch
        and "startMusicWorkspaceLaunchPreparation(containerWidth:" in app_shell_music_launch
        and "launchPreparationStatus.isLoading" in app_shell_music_launch
        and "musicWorkspaceLaunchSourceKey" in app_shell_music_launch
        and "checksFileSystem: false" in app_shell_music_launch,
        "Music workspace caches must start preparing in the background at launch and expose a gray music icon while loading.",
    )
    music_launch_source_key = section_after(
        music_launch_preparation,
        "var musicWorkspaceLaunchSourceKey",
        700,
    )
    require(
        "libraryStore.videos.count" not in music_launch_source_key
        and "recognizedSongCount" not in music_launch_source_key
        and "libraryStore.localMusicAssets.count" not in music_launch_source_key
        and "libraryStore.metadataByVideoPath.count" not in music_launch_source_key
        and "libraryStore.knownLocalResourcePaths.count" not in music_launch_source_key
        and "waveformSampleSetCount" not in music_launch_source_key,
        "Music launch preparation id must not restart from volatile library counters while caches load.",
    )
    require(
        "@Published var projectDataLoadState" in library_store
        and "@Published var knownLocalResourcePaths" in library_store
        and "libraryStore.projectDataLoadState" in music_launch_preparation
        and "libraryStore.projectDataLoadState == .loaded" in music_launch_preparation,
        "Music launch preparation must wait for loaded project data and must not build a launch projection from loading project data.",
    )
    require(
        "startLaunchPreparationIfNeeded(" in projection_models
        and "MusicWorkspaceLaunchPreparationStatus" in projection_models
        and "MusicWorkspaceDisplayCache.loadLatest(in: libraryURL)" in projection_models
        and "DownloadedMusicWaveformRenderPrewarmQueue.shared.prewarm(requests)" in projection_models
        and "MusicArtworkCache.prewarmCachedArtwork(urls: artworkURLs)" in projection_models,
        "Music launch preparation must load display cache and row media in the retained view model instead of mounting the music workspace.",
    )
    require(
        "sourceKey: String" in projection_models
        and "fallbackInput: MusicWorkspaceProjectionInput?" in projection_models
        and "guard let fallbackInput else" in projection_models
        and "launchPreparationLibraryPath" in projection_models
        and "launchPreparationStatus.phase == .ready" in projection_models
        and "等待音乐数据" not in projection_models
        and "生成音乐列表" in projection_models
        and "self.launchPreparationStatus = .ready\n                return" not in projection_models,
        "Music launch preparation must stay idle until project data can provide one complete launch projection input, then run once per library.",
    )
    music_launch_width_estimate = section_after(
        music_launch_preparation,
        "func estimatedMusicWorkspaceContentWidth(containerWidth: CGFloat) -> CGFloat",
        500,
    )
    require(
        "- Design.railWidth" in music_launch_width_estimate
        and "- Design.libraryContentInset * 2" in music_launch_width_estimate
        and "- 28" not in music_launch_width_estimate,
        "Music launch waveform prewarm width must match the actual music row content width and avoid extra fixed-width underestimation.",
    )
    require(
        "@Published var isMusicTagFilterBarPresented = true" in projection_models,
        "Music workspace tag filter panel must be expanded by default when the workspace view model is created.",
    )
    scroll_content = section_between(
        music_workspace,
        "ScrollView {",
        ".fadingVerticalScrollIndicators()",
    )
    first_visible_music_section = section_between(
        scroll_content,
        "LazyVStack(alignment: .leading, spacing: 16) {",
        "recognizedMusicSection(",
    )
    require(
        "GeometryReader" not in first_visible_music_section
        and "musicWaveformRenderPrewarmProbe" not in music_workspace
        and "prewarmMusicWaveformRenderCache" not in music_workspace
        and "musicWaveformRenderPrewarmRequests" not in music_workspace,
        "Music workspace must not run full-library waveform render prewarm on first open; visible rows should read prepared cache images themselves.",
    )

    require(
        music_workspace.count("HStack(alignment: .top, spacing: MusicRowMetrics.columnSpacing)") >= 3
        and music_workspace.count(".frame(width: proxy.size.width, height: MusicRowMetrics.rowHeight, alignment: .topLeading)") >= 3
        and ".frame(width: width, height: MusicRowMetrics.artworkSize, alignment: .topLeading)" in music_workspace,
        "Music row artwork, text, tags, actions, and waveform columns must keep a shared top edge.",
    )
    require(
        "struct EditableMusicTagChip" in music_workspace
        and "MusicEntryTagChip(tag: tag, size: size, maxChipWidth: maxChipWidth)" in music_workspace
        and 'Image(systemName: "xmark")' in music_workspace
        and ".onHover { isHovered = $0 }" in music_workspace
        and "onRemove: { onRemove(tag) }" in music_workspace,
        "Editable music tag chips must show a hover delete button that removes the tag directly.",
    )
    editable_music_tag_strip = section_between(
        music_workspace,
        "private struct EditableMusicTagStrip",
        "private struct MusicEntryTagStrip",
    )
    require(
        "let suggestedTags: [String]" in editable_music_tag_strip
        and "let onAdd: ((String) -> Void)?" in editable_music_tag_strip
        and "MusicEntryTagAddChip(" in editable_music_tag_strip
        and "TagStripAddButton" not in editable_music_tag_strip,
        "Music content tag rows must keep the inline add-tag button at the end of the editable tag flow.",
    )
    music_entry_tag_add_chip = section_between(
        music_workspace,
        "private struct MusicEntryTagAddChip: View",
        "private struct MusicEntryTagChip: View",
    )
    require(
        "CenteredPlusGlyph" in music_entry_tag_add_chip
        and ".frame(width: addChipWidth, height: size.height, alignment: .center)" in music_entry_tag_add_chip
        and ".background(isHovered ? Design.tagChipProminentFill : Design.tagChipFill)" in music_entry_tag_add_chip
        and "TagEditorSection(" in music_entry_tag_add_chip
        and "domain: .music" in music_entry_tag_add_chip,
        "Music entry add-tag chips must match the tag chip height and capsule styling while preserving the music tag editor popover.",
    )
    music_featured_button = section_between(
        music_workspace,
        "private func musicFeaturedButton",
        "private func musicRowActionIcon",
    )
    require(
        '"star.fill"' in music_featured_button
        and "tint: isFeatured ? .yellow : .white.opacity(0.70)" in music_featured_button
        and ".background(" not in music_featured_button
        and ".overlay" not in music_featured_button
        and "RoundedRectangle" not in music_featured_button,
        "Featured music stars must use icon color only and must not add a selected background or outline.",
    )

    audio_components = sources.get("LapianBao/Views/Music/AudioMusicComponents.swift", "")
    completed_music_file_url = section_between(
        audio_components,
        "nonisolated func completedMusicFileURL",
        "nonisolated func musicPreviewTimeText",
    )
    music_download_status_preview_url = section_between(
        audio_components,
        "struct MusicDownloadStatusView: View",
        "private var canPreviewAudio",
    )
    require(
        "FileManager.default.fileExists" not in completed_music_file_url
        and "FileManager.default.fileExists" not in music_download_status_preview_url,
        "Music row view state must trust prepared download status and must not synchronously check file existence while rendering.",
    )
    music_download_controls = section_between(
        audio_components,
        "struct MusicDownloadControlsAndWaveform: View",
        "private var waveformPanel: some View",
    )
    require(
        "HStack(alignment: .top, spacing: elementSpacing)" in music_download_controls
        and ".frame(width: buttonsWidth, height: waveformHeight, alignment: .top)" in music_download_controls
        and ".frame(height: waveformHeight, alignment: .top)" in music_download_controls,
        "Music download controls and waveform must align to the row top edge instead of vertically centering.",
    )
    require(
        "prewarmWaveformRenderCacheIfNeeded" not in music_download_controls
        and "DownloadedMusicWaveformRenderPrewarmQueue.shared.enqueue(requests)" not in music_download_controls,
        "Visible music rows must not submit waveform render work on appear, download changes, or width changes; workspace-level prewarm owns rendering.",
    )
    cached_waveform = section_between(
        audio_components,
        "private func cachedMusicWaveform(",
        "private func ensureWaveformImagesCached(",
    )
    require(
        "cachedMemoryImage" in cached_waveform
        and "cache.image(" not in cached_waveform,
        "DownloadedMusicWaveformView body must only read already-warm memory images and must not synchronously load or render cache images.",
    )
    require(
        "musicWaveformCachePlaceholder()" in cached_waveform
        and "musicWaveformCanvas(" not in audio_components,
        "DownloadedMusicWaveformView must show a stable placeholder on cache miss instead of drawing Canvas waveforms during scroll.",
    )

    render_cache = sources.get("LapianBao/Views/Music/DownloadedMusicWaveformRenderCache.swift", "")
    require(
        "actor DownloadedMusicWaveformRenderPrewarmQueue" in render_cache
        and "activeKeys" in render_cache
        and "waitUntilCompleted" in render_cache,
        "Downloaded music waveform render prewarming must be globally deduplicated while preserving full-cache requests for smooth scrolling.",
    )
    require(
        "maximumQueuedRequestCount" not in render_cache
        and "while queuedRequests.count >" not in render_cache,
        "Music waveform render prewarming must not drop full-cache requests before deeper rows are loaded.",
    )


def require_local_music_apple_metadata_guardrails(sources: dict[str, str]) -> None:
    models = sources.get("LapianBao/Models/LibraryModels.swift", "")
    video_library = sources.get("LapianBao/Stores/LibraryStore+VideoLibraryAndTags.swift", "")
    projection_builder = sources.get("LapianBao/Views/Music/MusicWorkspaceProjectionBuilder.swift", "")
    projection_models = sources.get("LapianBao/Views/Music/MusicWorkspaceModels.swift", "")
    timeline_media = sources.get("LapianBao/Stores/LibraryStore+TimelineMedia.swift", "")
    capture_music = sources.get("LapianBao/Stores/LibraryStore+CaptureTranscriptMusic.swift", "")
    music_packaging = sources.get("LapianBao/Stores/LibraryStore+MusicPackaging.swift", "")

    require(
        "var recognizedSong: MusicRecognitionItem? = nil" in models,
        "Local music assets must persist Apple Music recognition metadata in the resource cache.",
    )

    scan_music_loop = section_between(
        video_library,
        "for entry in musicFiles {",
        "music.sort { (lhs: LocalMusicAsset, rhs: LocalMusicAsset) in",
    )
    require(
        "appleMusicRecognitionForLocalMusicFile(" in scan_music_loop
        and "recognizedSong: recognizedSong" in scan_music_loop,
        "Full local music scans must enrich files with Apple Music metadata before saving the snapshot.",
    )
    require(
        "func appleMusicRecognitionForLocalMusicFile" in video_library
        and "searchAppleMusic(query: seed.query)" in video_library
        and "bestAppleMusicResult(for: seed" in video_library
        and "localMusicAppleMusicSeed(from:" in video_library,
        "Local music Apple Music enrichment must clean filenames and score search results instead of using raw filenames blindly.",
    )

    require(
        "if let song = asset.recognizedSong, hasRecognizedTitleAndArtist(song)" in projection_builder
        and "if let song = asset.recognizedSong,\n           !song.title" in projection_builder,
        "Music workspace projections must prefer cached Apple Music metadata for scanned local music.",
    )
    require(
        "if let recognizedSong = asset.recognizedSong {\n                Self.combine(recognizedSong, into: &hasher)" in projection_models,
        "Music projection signatures must include local Apple Music metadata so rows refresh after enrichment.",
    )
    require(
        "if let song = asset.recognizedSong" in timeline_media,
        "Local music tag enrichment must use cached Apple Music metadata as its seed when available.",
    )
    require(
        "recognizedSong: song" in capture_music
        and "recognizedSong: song" in music_packaging,
        "Downloaded and restored music assets must populate the same Apple Music metadata field as scanned files.",
    )


def require_initial_music_cache_prewarm_guardrails(sources: dict[str, str]) -> None:
    video_library = sources.get("LapianBao/Stores/LibraryStore+VideoLibraryAndTags.swift", "")
    timeline_media = sources.get("LapianBao/Stores/LibraryStore+TimelineMedia.swift", "")
    library_grid = sources.get("LapianBao/Views/AppShell/ContentView+LibraryGrid.swift", "")
    music_workspace = sources.get("LapianBao/Views/Music/MusicWorkspaceView.swift", "")
    status_tiles = sources.get("LapianBao/Views/Components/StatusAndSceneTiles.swift", "")
    scan_videos = section_between(
        video_library,
        "func scanVideos(in folder: URL)",
        "func restoreRecognizedLibraryIfAvailable",
    )
    restore_section = section_between(
        video_library,
        "func restoreRecognizedLibraryIfAvailable",
        "func scheduleRecognizedLibraryReconcile",
    )
    prewarm_section = section_between(
        timeline_media,
        "func prewarmInitialMusicCachesForLibraryScan",
        "func startLocalMusicWaveformTask",
    )
    require(
        "await self.prewarmInitialMusicCachesForLibraryScan" in scan_videos,
        "Initial full library scans must finish local music cache prewarming before clearing scan progress.",
    )
    require(
        "await self.prewarmInitialMusicCachesForLibraryScan" in restore_section
        and "正在检查音乐缓存" in restore_section,
        "Cached recognized-library restores must also surface and finish music cache checks in scan progress.",
    )
    require(
        "generateMissingSamples: false" in restore_section
        and "prewarmRenderedImages: false" in restore_section,
        "Cached recognized-library restores must not regenerate all music samples or pre-render every waveform image on open.",
    )
    require(
        "DownloadedMusicWaveformRenderCache.shared" in prewarm_section
        and ".ensureDiskImages(" in prewarm_section
        and "saveLocalWaveformCache(cacheByKey, in: libraryURL)" in prewarm_section,
        "Initial music cache prewarm must materialize both local waveform samples and the shared disk PNG waveform cache.",
    )
    require(
        "var isMusicWaveformCacheProgress: Bool" in status_tiles
        and 'message.contains("音乐波形")' in status_tiles,
        "Music waveform cache scan progress must have a shared classifier for workspace-specific placement.",
    )
    require(
        'message.contains("音乐缓存")' in status_tiles
        and 'message.contains("识别音乐素材")' in status_tiles,
        "Music workspace progress must also include cache-check and music-resource scan messages.",
    )
    require(
        "!progress.isMusicWaveformCacheProgress" in library_grid,
        "Video library scan cards must not show music waveform cache progress.",
    )
    require(
        "private var musicWaveformScanProgress: LibraryScanProgress?" not in music_workspace
        and "progress.isMusicWaveformCacheProgress" not in music_workspace
        and "musicWaveformScanProgressCard(" not in music_workspace
        and "showsBottomProgress" not in music_workspace,
        "Music waveform cache scan progress must not create a separate progress surface in the music workspace.",
    )


def require_video_tag_popover_spacing_guardrails(sources: dict[str, str]) -> None:
    video_tile = sources.get("LapianBao/Views/Library/LibraryVideoTile.swift", "")
    more_popover = section_between(
        video_tile,
        "private var morePopover: some View",
        "private var sourcePlatformChoices",
    )
    require(
        "let tagVerticalInset: CGFloat = 16" in more_popover
        and "let tagContentGap: CGFloat = tagVerticalInset" in more_popover
        and "inputSpacing: tagContentGap" in more_popover
        and ".padding(.top, tagVerticalInset)" in more_popover
        and ".padding(.bottom, tagVerticalInset)" in more_popover,
        "Video tag popover must keep the input-to-tags and tags-to-divider vertical spacing equal.",
    )


def require_quick_filter_chip_stable_selection_guardrails(sources: dict[str, str]) -> None:
    tags_and_badges = sources.get("LapianBao/Views/Components/TagsAndBadges.swift", "")
    quick_filter_chip = section_between(
        tags_and_badges,
        "struct QuickFilterChoiceChip: View",
        "struct WrappingFilterChipGroup",
    )
    require(
        'Image(systemName: "checkmark")' not in quick_filter_chip
        and ".padding(.horizontal, 9)" in quick_filter_chip
        and ".background(isSelected ? Design.tagChipSelectedFill" in quick_filter_chip,
        "Quick filter chips must not reserve a hidden trailing checkmark slot that makes chip padding look uneven.",
    )

def require_home_tag_inline_edit_guardrails(sources: dict[str, str]) -> None:
    tags_and_badges = sources.get("LapianBao/Views/Components/TagsAndBadges.swift", "")
    tag_editor_choice = section_between(
        tags_and_badges,
        "private struct TagEditorChoiceChip: View",
        "private struct TagChoiceGridLayout",
    )
    require(
        'Image(systemName: "xmark")' not in tag_editor_choice
        and "toggleTag(tag, isSelected: isSelected)" in tags_and_badges,
        "Tag popover chips must use repeat-click toggling instead of showing a top-right remove button.",
    )

    content_view = sources.get("LapianBao/ContentView.swift", "")
    library_grid = sources.get("LapianBao/Views/AppShell/ContentView+LibraryGrid.swift", "")
    require(
        "@FocusState var focusedLibraryTagRenameTarget" in content_view
        and '.alert("重命名标签"' not in content_view
        and "func libraryTagFilterSection(" in library_grid
        and "func libraryEditableTagChip(" in library_grid
        and "var libraryTagEditButton" in library_grid
        and "libraryStore.renameGlobalTag(oldTag, to: nextTag)" in library_grid
        and "libraryStore.removeGlobalTag(tag)" in library_grid
        and "exitLibraryTagEditing()" in library_grid,
        "Home content tag chips must support inline global edit/delete mode without the old rename alert.",
    )


def require_frame_tag_popover_spacing_guardrails(sources: dict[str, str]) -> None:
    frames = sources.get("LapianBao/Views/Frames/FramesWorkspaceView.swift", "")
    more_popover = section_between(
        frames,
        "private var morePopover: some View",
        "private var actionSection: some View",
    )
    detail_popover = section_between(
        frames,
        "private var detailPopover: some View",
        "private var detailActionSection: some View",
    )
    for section_name, section in {
        "frame card tag popover": more_popover,
        "frame detail tag popover": detail_popover,
    }.items():
        require(
            "let tagVerticalInset: CGFloat = 16" in section
            and "let tagContentGap: CGFloat = tagVerticalInset" in section
            and "inputSpacing: tagContentGap" in section
            and "gridVerticalPadding: 0" in section
            and ".padding(.top, tagVerticalInset)" in section
            and ".padding(.bottom, tagVerticalInset)" in section,
            f"{section_name} must keep the tag search field visually centered between the popover top and divider.",
        )
        require(
            ".padding(.bottom, 6)" not in section,
            f"{section_name} must not use asymmetric bottom padding below the tag search field.",
        )

    status_tiles = sources.get("LapianBao/Views/Components/StatusAndSceneTiles.swift", "")
    scene_tile_popover = section_between(
        status_tiles,
        "private var morePopover: some View",
        "private var actionSection: some View",
    )
    require(
        "let tagVerticalInset: CGFloat = 16" in scene_tile_popover
        and "let tagContentGap: CGFloat = tagVerticalInset" in scene_tile_popover
        and "inputSpacing: tagContentGap" in scene_tile_popover
        and "gridVerticalPadding: 0" in scene_tile_popover
        and ".padding(.top, tagVerticalInset)" in scene_tile_popover
        and ".padding(.bottom, tagVerticalInset)" in scene_tile_popover
        and ".padding(14)" not in scene_tile_popover,
        "Scene/image tile tag popover must match the video tag popover vertical rhythm.",
    )
    scene_cut_tile = section_between(
        status_tiles,
        "struct SceneCutTile: View",
        "struct CaptureFrameBadge: View",
    )
    require(
        "sceneTagBadges(maxSize: proxy.size)" in scene_cut_tile
        and ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)" in scene_cut_tile
        and "ViewThatFits(in: .horizontal)" in scene_cut_tile
        and "sceneTagRow(Array(tags.prefix(4)), showsOverflow: tags.count > 4)" in scene_cut_tile
        and "SceneCardTagOverflowChip()" in status_tiles
        and "SceneCardTagChip(tag: tag)" in scene_cut_tile
        and ".background(Color.black.opacity(0.62))" in status_tiles
        and ".background(Color.black.opacity(0.46))" not in scene_cut_tile
        and "VideoTagOverflowChip(count: overflowCount)" not in scene_cut_tile,
        "Storyboard grid cells with frame tags must stay on one line and fall back to an ellipsis indicator without a large outer badge background.",
    )


def require_bilibili_official_display_name_guardrails(sources: dict[str, str]) -> None:
    display_sources = {
        "LapianBao/LibraryStore.swift": sources.get("LapianBao/LibraryStore.swift", ""),
        "LapianBao/Views/Settings/SettingsWorkspaceView.swift": sources.get(
            "LapianBao/Views/Settings/SettingsWorkspaceView.swift",
            "",
        ),
    }
    offenders = [
        relative
        for relative, text in display_sources.items()
        if "B站已登录" in text or "B站未登录" in text
    ]
    require(
        not offenders
        and all("Bilibili 已登录" in text and "Bilibili 未登录" in text for text in display_sources.values()),
        f"Account login UI must use the official Bilibili display name: {', '.join(offenders)}.",
    )
    require(
        all("Instagram 已登录" in text and "Instagram 未登录" in text for text in display_sources.values())
        and all("IG 已登录" not in text and "IG 未登录" not in text for text in display_sources.values()),
        "Account login UI must use the full Instagram display name instead of IG.",
    )


def require_account_cookie_detection_guardrails(sources: dict[str, str]) -> None:
    account_cookies = sources.get("LapianBao/Stores/LibraryStore+AccountCookies.swift", "")
    instagram_auth_names = section_between(
        account_cookies,
        "nonisolated private static let instagramAuthenticatedCookieNames",
        "nonisolated private static let xiaohongshuAuthenticatedCookieNames",
    )
    xiaohongshu_auth_names = section_between(
        account_cookies,
        "nonisolated private static let xiaohongshuAuthenticatedCookieNames",
        "nonisolated private static let youtubeAuthenticatedCookieNames",
    )
    youtube_auth_names = section_between(
        account_cookies,
        "nonisolated private static let youtubeAuthenticatedCookieNames",
        "nonisolated private static let bilibiliAuthenticatedCookieNames",
    )
    bilibili_auth_names = section_between(
        account_cookies,
        "nonisolated private static let bilibiliAuthenticatedCookieNames",
        "nonisolated private static let douyinAuthenticatedCookieNames",
    )
    douyin_auth_names = section_between(
        account_cookies,
        "nonisolated private static let douyinAuthenticatedCookieNames",
        "nonisolated private static func hasNonEmptyCookieValue",
    )
    require(
        '"sessionid"' in instagram_auth_names
        and '"ds_user_id"' not in instagram_auth_names,
        "Instagram login detection must require a real session cookie, not a user-id hint cookie.",
    )
    require(
        '"web_session"' in xiaohongshu_auth_names
        and '"webId"' not in xiaohongshu_auth_names,
        "Xiaohongshu login detection must require web_session and must not treat webId as authenticated.",
    )
    require(
        '"SID"' in youtube_auth_names
        and '"__Secure-1PSID"' in youtube_auth_names
        and '"LOGIN_INFO"' not in youtube_auth_names,
        "YouTube login detection must require strong Google session cookies and must not treat LOGIN_INFO as authenticated.",
    )
    require(
        '"SESSDATA"' in bilibili_auth_names
        and '"DedeUserID"' not in bilibili_auth_names
        and '"bili_jct"' not in bilibili_auth_names,
        "Bilibili login detection must require SESSDATA and must not treat user-id or CSRF cookies as authenticated.",
    )
    require(
        '"sessionid"' in douyin_auth_names
        and '"sid_guard"' in douyin_auth_names
        and '"s_v_web_id"' not in douyin_auth_names
        and '"passport_csrf_token"' not in douyin_auth_names
        and '"LOGIN_STATUS"' not in douyin_auth_names,
        "Douyin login detection must not treat visitor or CSRF cookies as authenticated sessions.",
    )
    require(
        "nonisolated private static func isAuthenticatedCookie(" in account_cookies
        and "hasNonEmptyCookieValue(value)" in account_cookies
        and "isAuthenticatedInstagramCookie(name: $0.name, value: $0.value)" in account_cookies
        and "isAuthenticatedXiaohongshuCookie(name: $0.name, value: $0.value)" in account_cookies
        and "isAuthenticatedYouTubeCookie(name: $0.name, value: $0.value)" in account_cookies
        and "isAuthenticatedBilibiliCookie(name: $0.name, value: $0.value)" in account_cookies
        and "isAuthenticatedDouyinCookie(name: $0.name, value: $0.value)" in account_cookies
        and "let value = columns[6]" in account_cookies
        and "isAuthenticatedInstagramCookie(name: name, value: value)" in account_cookies
        and "isAuthenticatedXiaohongshuCookie(name: name, value: value)" in account_cookies
        and "isAuthenticatedYouTubeCookie(name: name, value: value)" in account_cookies
        and "isAuthenticatedBilibiliCookie(name: name, value: value)" in account_cookies
        and "isAuthenticatedDouyinCookie(name: name, value: value)" in account_cookies,
        "Account status must require strong non-empty session cookies for both WebKit and Netscape cookie sources.",
    )


def require_no_app_tooltips_guardrails(sources: dict[str, str]) -> None:
    offenders = [
        relative
        for relative, text in sources.items()
        if ".help(" in text
        or ".toolTip" in text
        or ".setToolTip(" in text
        or "NSHelpManager" in text
    ]
    require(
        not offenders,
        f"App UI must not attach hover/click tooltips anywhere: {', '.join(offenders)}.",
    )


def require_settings_row_description_guardrails(sources: dict[str, str]) -> None:
    settings = sources.get("LapianBao/Views/Settings/SettingsWorkspaceView.swift", "")
    account_column = section_between(
        settings,
        "private func accountLoginInfoColumn() -> some View",
        "private func accountLoginStatusLink",
    )
    downloader_card = section_between(
        settings,
        "private func downloaderSelfCheckCard() -> some View",
        "private func shortcutSettingsCard() -> some View",
    )
    compact_info_column = section_between(
        settings,
        "private func settingsInfoColumn(",
        "private func settingsRowIcon",
    )
    require(
        "private static let rowTextSpacing: CGFloat = 4" in settings
        and "private static let rowDescriptionColor = Color.white.opacity(0.58)" in settings
        and settings.count("VStack(alignment: .leading, spacing: Self.rowTextSpacing)") >= 2,
        "Settings rows with title, note, and status must use fixed spacing and a shared gray description color.",
    )
    require(
        "仅用于下载授权，不读取账号密码。" in account_column
        and ".foregroundStyle(Self.rowDescriptionColor)" in account_column
        and "let isLoggedIn = target.isLoggedIn(summary)" in settings
        and "let color: Color = isLoggedIn ? .green : Color.yellow.opacity(0.92)" in settings
        and "Spacer(minLength: 0)" not in account_column,
        "Account login settings row must show the concise authorization note in gray, logged-in statuses in green, and logged-out statuses in yellow.",
    )
    require(
        'description: "使用开源下载工具，请保证网络环境。"' in downloader_card
        and "Text(description)" in compact_info_column
        and ".foregroundStyle(Self.rowDescriptionColor)" in compact_info_column
        and "detailColor: downloaderSelfCheckDetailColor(for: report)" in downloader_card
        and "private func downloaderSelfCheckDetailColor(for report: DownloaderSelfCheckReport) -> Color" in settings
        and "report.status == .succeeded ? .green : Color.yellow.opacity(0.92)" in settings
        and "Text(target.statusText(in: summary))" in settings
        and "Spacer(minLength: 0)" not in compact_info_column,
        "Downloader self-check settings row must show the concise network note in gray and version row as green on success or yellow otherwise.",
    )


def require_music_preview_playback_guardrails(sources: dict[str, str]) -> None:
    store = sources.get("LapianBao/LibraryStore.swift", "")
    require(
        "@Published var activeMusicPreviewJobID: UUID?" in store
        and "@Published var focusedMusicPreviewJobID: UUID?" in store
        and "var musicPreviewKeyboardTargetJobID: UUID?" in store
        and "func activateMusicPreviewJob(_ id: UUID)" in store
        and "func pauseMusicPreviewJob(_ id: UUID?)" in store
        and "func clearMusicPreviewJob(_ id: UUID?)" in store,
        "Music preview state must distinguish active playback from the keyboard resume target.",
    )

    app = sources.get("LapianBao/LapianBaoApp.swift", "")
    require(
        "libraryStore.musicPreviewKeyboardTargetJobID" in app
        and "AppEventBus.postMusicPreviewToggleRequest(id: id)" in app,
        "Spacebar handling must target the active or paused music preview job.",
    )

    audio_components = sources.get("LapianBao/Views/Music/AudioMusicComponents.swift", "")
    selector_button = section_between(
        audio_components,
        "private func selectorButton(",
        "struct MusicDownloadWaveformPanel",
    )
    require(
        'Image(systemName: isPreviewing ? "pause.circle.fill" : musicDownloadIcon(type: type, job: job))' in selector_button,
        "Original and instrumental music row buttons must show a pause icon while their preview is playing.",
    )
    require(
        audio_components.count("libraryStore.activateMusicPreviewJob(job.id)") >= 2
        and audio_components.count("libraryStore.pauseMusicPreviewJob(") >= 2
        and audio_components.count("libraryStore.clearMusicPreviewJob(") >= 4
        and "libraryStore.activeMusicPreviewJobID = job.id" not in audio_components
        and "libraryStore.activeMusicPreviewJobID = nil" not in audio_components,
        "Music preview views must use LibraryStore preview-state helpers so paused previews can resume from the keyboard.",
    )
    require(
        audio_components.count('"arrow.down.circle"') >= 5
        and 'actionIcon("arrow.down",' not in audio_components
        and 'actionIcon(\n                "arrow.down",' not in audio_components,
        "Music download action icons must use the circled download glyph and stay visually aligned with adjacent action icons.",
    )
    require(
        "opticalOffsetX: CGFloat = 0" in audio_components
        and "static let circledDownloadIconOpticalOffsetX: CGFloat = -2.5" in audio_components
        and audio_components.count(".offset(x: MusicRecognitionLayout.circledDownloadIconOpticalOffsetX)") >= 2,
        "Music vertical action columns must offset the circled download menu controls so they align with folder buttons.",
    )
    export_music_row = section_between(
        audio_components,
        "struct ExportMusicRecognitionRow: View",
        "struct MusicRecognitionRow: View",
    )
    preview_export_panel = sources.get("LapianBao/Views/Preview/PreviewPanelView+ExportPanel.swift", "")
    require(
        "MusicDownloadExtensionStack(downloadJobs: downloadJobs)" in export_music_row
        and "MusicDownloadControlsAndWaveform(" not in export_music_row
        and "exportMusicWaveformRenderPrewarmProbe(songs: songs)" in preview_export_panel
        and "DownloadedMusicWaveformRenderPrewarmQueue.shared.prewarm(requests)" in preview_export_panel,
        "Export-panel music rows must keep the original download-status layout while prewarming rendered waveform images before scrolling.",
    )


def require_recognized_library_restore_guardrails(sources: dict[str, str]) -> None:
    video_library = sources.get("LapianBao/Stores/LibraryStore+VideoLibraryAndTags.swift", "")
    scan_videos = section_between(
        video_library,
        "func scanVideos(in folder: URL)",
        "func restoreRecognizedLibraryIfAvailable",
    )
    restore_call_index = scan_videos.find("restoreRecognizedLibraryIfAvailable(in: folder")
    progress_index = scan_videos.find("libraryScanProgress = LibraryScanProgress")
    require(
        restore_call_index >= 0 and progress_index > restore_call_index,
        "Opening a library folder must try cached recognized-library restore before showing full scan progress.",
    )

    restore_section = section_between(
        video_library,
        "func restoreRecognizedLibraryIfAvailable",
        "func scheduleRecognizedLibraryReconcile",
    )
    require(
        "loadCachedVideoOrganization(in: folder, includeThumbnailData: false)" in restore_section
        and "loadCachedResourceLibrarySnapshot(in: folder)" in restore_section
        and "applyResourceLibrarySnapshot(cachedResources" in restore_section,
        "Recognized-library restore must use cached video and resource snapshots for immediate display.",
    )
    require(
        "quickVideoOrganizationSnapshot(in: folder)" not in restore_section
        and "organizeVideoFiles(in: folder)" not in restore_section,
        "Recognized-library restore must not enumerate or organize the folder before the cached UI appears.",
    )


def require_import_job_progress_text_guardrails(sources: dict[str, str]) -> None:
    import_jobs = sources.get("LapianBao/Views/AppShell/ContentView+ImportJobs.swift", "")
    active_status = section_between(
        import_jobs,
        "func importActiveJobStatus",
        "func importActiveStatusText",
    )
    require(
        "importStatusDetail" not in active_status
        and ".frame(height: 8)" not in active_status,
        "Active import job cards must not render a separate progress bar below the status text.",
    )
    require(
        "func importStatusDetail" not in import_jobs
        and "func importLinearProgress" not in import_jobs
        and "func importIndeterminateProgress" not in import_jobs
        and "ProgressView(value: normalizedProgressFraction(progress))" not in import_jobs,
        "Import job progress must be represented by status percentage text, not a linear progress bar.",
    )
    require(
        "importStatusProgressText(for: job)" in import_jobs
        and "progressPercentText(progress)" in import_jobs,
        "Import job status text must keep showing the numeric percentage when progress is known.",
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

    timeline_controls = sources.get("LapianBao/Views/Preview/TimelineControls.swift", "")
    waveform_timeline = section_between(
        timeline_controls,
        "struct CenteredWaveformTimeline: View",
        "struct PlayerSurfaceView",
    )
    drag_gesture = section_between(
        waveform_timeline,
        "DragGesture(minimumDistance: 0)",
        ".simultaneousGesture(",
    )
    require(
        "clearSelectionHitFrame" in waveform_timeline
        and "isClearSelectionHit" in waveform_timeline
        and "onClearSelection?()" in drag_gesture
        and "return" in section_between(drag_gesture, "if isClearSelectionHit(", "let final = scrubProgress"),
        "Centered waveform delete-selection button must bypass the high-priority seek gesture and clear the selection.",
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
    require_music_library_projection_guardrails(sources)
    require_local_music_apple_metadata_guardrails(sources)
    require_initial_music_cache_prewarm_guardrails(sources)
    require_quick_filter_chip_stable_selection_guardrails(sources)
    require_home_tag_inline_edit_guardrails(sources)
    require_video_tag_popover_spacing_guardrails(sources)
    require_frame_tag_popover_spacing_guardrails(sources)
    require_bilibili_official_display_name_guardrails(sources)
    require_account_cookie_detection_guardrails(sources)
    require_no_app_tooltips_guardrails(sources)
    require_settings_row_description_guardrails(sources)
    require_music_preview_playback_guardrails(sources)
    require_recognized_library_restore_guardrails(sources)
    require_import_job_progress_text_guardrails(sources)
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
