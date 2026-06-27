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
    library_grid = sources.get("LapianBao/Views/AppShell/ContentView+LibraryGrid.swift", "")
    frames_workspace = sources.get("LapianBao/Views/Frames/FramesWorkspaceView.swift", "")
    design = sources.get("LapianBao/Views/Design/Design.swift", "")
    agents = read("AGENTS.md")
    toolbar_search_field = section_between(
        design,
        "struct LibraryToolbarSearchField: View",
        "struct LibraryToolbar<Actions: View>",
    )
    toolbar = section_between(
        design,
        "struct LibraryToolbar<Actions: View>",
        "struct TopChromeBoundedContent<Content: View>",
    )
    music_header = section_between(
        music_workspace,
        "private func musicHeader() -> some View",
        "private func musicCacheLoadingProgressBar",
    )
    frame_board_toolbar = section_between(
        frames_workspace,
        "private var frameBoardToolbar",
        "private var frameTagFilterButton",
    )
    require(
        'LibraryToolbar(placeholder: "", text: $librarySearchText)' in library_grid
        and 'LibraryToolbar(placeholder: "", text: $viewModel.searchText)' in music_workspace
        and 'LibraryToolbar(placeholder: "", text: $frameSearchText)' in frames_workspace
        and "searchExpands" not in design
        and "static let libraryToolbarSearchMinWidth: CGFloat = 110" in design
        and "static let libraryToolbarSearchWidth: CGFloat = 280" in design
        and "var expands" not in toolbar_search_field
        and "maxWidth: .infinity" not in toolbar_search_field
        and "idealWidth: Design.libraryToolbarSearchWidth" in toolbar_search_field
        and "maxWidth: Design.libraryToolbarSearchWidth" in toolbar_search_field
        and "LibraryToolbarActionRow" in toolbar
        and "HStack(spacing: Design.libraryToolbarButtonGap)" in toolbar
        and "let mediaWorkspaceToolbarWidth = homeMediaContentWidth(containerWidth: containerWidth)" in content_view
        and "func homeMediaContentWidth(containerWidth: CGFloat) -> CGFloat" in content_view
        and "CGFloat(mediaPanelWidth)" in content_view
        and "workspaceView(toolbarWidth: mediaWorkspaceToolbarWidth)" in content_view
        and "func workspaceView(toolbarWidth: CGFloat? = nil) -> some View" in content_view
        and "toolbarWidth: toolbarWidth" in content_view
        and "let toolbarWidth: CGFloat?" in music_workspace
        and "let toolbarWidth: CGFloat?" in frames_workspace
        and ".frame(width: toolbarWidth, alignment: .leading)" in music_header
        and ".frame(width: toolbarWidth, alignment: .leading)" in frame_board_toolbar
        and "static let libraryToolbarActionSlotCount: CGFloat = 3" in design
        and "static let libraryToolbarActionRowWidth: CGFloat =" in design
        and "width: Design.libraryToolbarActionRowWidth" in toolbar
        and "struct LibraryToolbarActionPlaceholder: View" in toolbar
        and "LibraryToolbarActionPlaceholder()" not in music_header
        and "musicTagFilterButton" in music_header
        and "musicSortMenu" in music_header
        and "frameModeMenu" in frame_board_toolbar
        and "frameGridSizeMenu" in frame_board_toolbar
        and "frameModeButton(" not in frame_board_toolbar
        and "frameGridSizeControl" not in frame_board_toolbar
        and "LibraryToolbarActionPlaceholder()" in frame_board_toolbar
        and "顶部搜索框必须由 `LibraryToolbarSearchField` 使用旧版主页基线" in agents
        and "homeMediaContentWidth(containerWidth:)" in agents
        and "不能让全宽工作区或分镜自己的宽面板直接决定顶部搜索框长度" in agents
        and "不要改回 140" in agents
        and "顶部按钮必须由 `LibraryToolbarActionRow` 统一排列成 3 个固定槽位" in agents
        and "音乐页两个可见按钮直接从第一个槽位开始排列" in agents
        and "LibraryToolbarActionPlaceholder" in agents
        and "宽滑杆" in agents,
        "Home, music, and frame workspaces must use the previous home toolbar search width baseline and a fixed three-slot action row.",
    )
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
        and music_workspace.count(".frame(width: proxy.size.width, height: rowHeight, alignment: .topLeading)") >= 3
        and music_workspace.count(".frame(height: estimatedRowHeight)") >= 3
        and "let showsTags = !tags.isEmpty && containerWidth >= (includesSafari ? 560 : 500)" in music_workspace
        and "let visibleColumnCount = 3\n            + (showsTags ? 1 : 0)" in music_workspace
        and "let fixedWidth = MusicRowMetrics.totalHorizontalPadding" in music_workspace
        and "private func musicRowContentHeight(" in music_workspace
        and "private func musicTagFlowHeight(" in music_workspace
        and ".frame(width: width, height: MusicRowMetrics.artworkSize, alignment: .topLeading)" in music_workspace,
        "Music row artwork, text, tags, actions, and waveform columns must use shared fixed-column math while tag-heavy rows grow vertically instead of clipping chips.",
    )
    require(
        "EditableMusicTag" not in music_workspace
        and "MusicEntryTagAddChip" not in music_workspace
        and "domain: .music" not in music_workspace
        and "TagEditorSection(" not in music_workspace
        and "isEditableMusicContentTag" not in music_workspace
        and "cleanedMusicContentTags" not in music_workspace
        and "includesAddTagChip" not in music_workspace
        and "hasTagEditor" not in music_workspace
        and "hasTagEditor" not in projection_models,
        "Music rows must remove the self-added tag editor and only display system-recognized genre tags.",
    )
    music_tag_column = section_between(
        music_workspace,
        "private func musicTagColumn(",
        "private func sectionHeader",
    )
    require(
        "MusicEntryTagStrip(tags: tags)" in music_tag_column
        and "contentHeight: CGFloat = MusicRowMetrics.contentHeight" in music_tag_column
        and ".frame(width: layout.tagWidth, height: contentHeight, alignment: .topLeading)" in music_tag_column
        and "suggestedTags" not in music_tag_column
        and "onAdd" not in music_tag_column
        and "onRemove" not in music_tag_column
        and "EditableMusicTagStrip" not in music_tag_column
        and '"音乐标签"' not in music_tag_column,
        "Music rows must keep recognized genre tags visible without a manual add/remove tag editor.",
    )
    music_tagging = sources.get("LapianBao/Models/MusicTagging.swift", "")
    is_fallback_music_tag = section_between(
        music_tagging,
        "nonisolated static func isFallbackMusicTag",
        "nonisolated static func hasOnlyFallbackMusicTag",
    )
    require(
        "nonisolated var displayTags: [String]" in music_tagging
        and "Self.cleanedGenreTags(tags, title: title, artist: artist)" in music_tagging
        and "let requiredGenreTags = inferredGenreTags.isEmpty ? [defaultMusicGenreTag] : inferredGenreTags" in music_tagging
        and "return genreTags.isEmpty ? [Self.defaultMusicGenreTag] : genreTags" in music_tagging
        and "canonicalMusicGenreKey(defaultMusicGenreTag)" not in is_fallback_music_tag
        and "isEditableMusicContentTag" not in music_tagging
        and "cleanedMusicContentTags" not in music_tagging
        and "isRecognizedMusicGenreTag" not in music_tagging,
        "Music display tags must always include at least one genre fallback while remaining limited to recognized genre semantics.",
    )
    require(
        "func requiredVisibleMusicTags(_ tags: [String], metadataValues: [String]) -> [String]" in projection_builder
        and "return visibleTags.isEmpty ? [MusicRecognitionItem.defaultMusicGenreTag] : visibleTags" in projection_builder
        and "requiredVisibleMusicTags(" in projection_builder
        and "displayedMusicTags(" in projection_builder,
        "Music workspace projections must never expose empty visible genre tags after metadata filtering.",
    )
    require(
        "音乐界面不提供自添加标签系统" in agents
        and "只显示系统自动识别出的流派标签" in agents
        and "历史保存的非流派音乐标签不能进入行内显示或类型筛选" in agents
        and "所有音乐必须始终有至少一个流派标签" in agents
        and "整行高度必须随流派标签流自动增高" in agents,
        "AGENTS must record that music rows only display system-recognized genre tags.",
    )
    require(
        "固定列计算" in agents
        and "不能因为某一行缺流派或缺波形而横向错位" in agents,
        "AGENTS must record the music row fixed-column alignment rule.",
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
    content_view = sources.get("LapianBao/ContentView.swift", "")
    library_grid = sources.get("LapianBao/Views/AppShell/ContentView+LibraryGrid.swift", "")
    video_tiles = sources.get("LapianBao/Views/AppShell/ContentView+VideoTiles.swift", "")
    frame_filter = sources.get("LapianBao/Views/AppShell/ContentView+FrameFilter.swift", "")
    card_helpers = sources.get("LapianBao/Views/Components/CardAndTimelineHelpers.swift", "")
    agents = read("AGENTS.md")
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
    require(
        "var onScroll: (() -> Void)?" in card_helpers
        and "NSView.boundsDidChangeNotification" in card_helpers
        and "coordinator?.onScroll?()" in card_helpers
        and "@State var activeLibraryCardMenuID: String?" in content_view
        and "@State var libraryCardMenuDismissToken = 0" in content_view
        and "func dismissLibraryCardMenusForScroll()" in video_tiles
        and "guard activeLibraryCardMenuID != nil else { return }" in video_tiles
        and "libraryCardMenuDismissToken += 1" in video_tiles
        and "menuIdentity: video.url.path" in video_tiles
        and "menuDismissToken: libraryCardMenuDismissToken" in video_tiles
        and "onMenuPresentationChanged" in video_tile
        and ".onChange(of: menuDismissToken)" in video_tile
        and "dismissTransientMenus()" in video_tile
        and ".fadingVerticalScrollIndicators(onScroll: {" in library_grid
        and ".fadingVerticalScrollIndicators(onScroll: {" in frame_filter
        and "视频卡片标签小菜单和平台小菜单不能跟随视频网格上下滚动" in agents,
        "Library video card tag/source popovers must dismiss on grid scroll instead of following the scrolling card anchor.",
    )

    timeline = sources.get("LapianBao/Views/Preview/PreviewPanelView+TimelineLayout.swift", "")
    timeline_tag_popover = section_between(
        timeline,
        "func videoTagPopover(for video: VideoItem) -> some View",
        "func timelineStackContainer(",
    )
    require(
        "let tagHorizontalInset: CGFloat = 14" in timeline_tag_popover
        and "let tagVerticalInset: CGFloat = 16" in timeline_tag_popover
        and "let tagContentGap: CGFloat = tagVerticalInset" in timeline_tag_popover
        and "inputSpacing: tagContentGap" in timeline_tag_popover
        and "gridVerticalPadding: 0" in timeline_tag_popover
        and ".padding(.horizontal, tagHorizontalInset)" in timeline_tag_popover
        and ".padding(.vertical, tagVerticalInset)" in timeline_tag_popover,
        "Preview timeline video tag popover must match the library video tag popover spacing.",
    )


def require_quick_filter_chip_stable_selection_guardrails(sources: dict[str, str]) -> None:
    tags_and_badges = sources.get("LapianBao/Views/Components/TagsAndBadges.swift", "")
    library_grid = sources.get("LapianBao/Views/AppShell/ContentView+LibraryGrid.swift", "")
    agents = read("AGENTS.md")
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
    require(
        'Text("\\(count)")' in quick_filter_chip
        and ".fixedSize(horizontal: true, vertical: false)" in quick_filter_chip
        and ".layoutPriority(2)" in quick_filter_chip,
        "Quick filter chip counts must keep enough layout priority to avoid being ellipsized.",
    )
    library_compact_chip = section_between(
        library_grid,
        "func libraryCompactFilterChip(",
        "func libraryEditableTagChip(",
    )
    library_count_width = section_between(
        library_grid,
        "func libraryFilterChipCountWidth(for count: Int)",
        "func libraryFilterChipForeground",
    )
    require(
        'Text("\\(count)")' in library_compact_chip
        and ".fixedSize(horizontal: true, vertical: false)" in library_compact_chip
        and ".layoutPriority(2)" in library_compact_chip
        and "return max(14, ceil(width) + 6)" in library_count_width,
        "Library sidebar filter chip counts must reserve a non-compressing count slot so numbers never become ellipses.",
    )
    require(
        "标签筛选区使用紧凑胶囊 chip" in agents
        and "后缀数字不能省略成 `...`" in agents
        and "把原数字槽位替换为 `xmark` 删除按钮" in agents
        and "外层横向留白 14，纵向留白 16" in agents,
        "AGENTS must record the tag chip visual rules so future UI work keeps the established design.",
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
    require(
        "@State private var newTagClickProtectionKeys = Set<String>()" in tags_and_badges
        and "addTag(trimmedDraftTag, protectsNextSelectedTap: true)" in tags_and_badges
        and "if newTagClickProtectionKeys.remove(key) != nil" in tags_and_badges
        and "return\n            }\n            pendingAddedTags.removeAll" in tags_and_badges,
        "New tags created from the input field must ignore the first repeat click so they are not immediately deleted.",
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


def require_global_tag_edit_key_matching_guardrails(sources: dict[str, str]) -> None:
    library_store = sources.get("LapianBao/LibraryStore.swift", "")
    persistence = sources.get("LapianBao/Stores/LibraryStore+PersistenceAndSources.swift", "")
    tags_store = sources.get("LapianBao/Stores/LibraryStore+VideoLibraryAndTags.swift", "")
    save_tags_json = section_between(
        persistence,
        "func saveTagsJSON()",
        "func saveSourceInfoJSON()",
    )
    load_tags_json = section_between(
        persistence,
        "func loadTagsJSON()",
        "func loadSourceInfoJSON()",
    )
    pending_folder_tags = section_between(
        persistence,
        "func applyPendingVideoPathMigrationToLoadedMetadata()",
        "func remapVideoPath(",
    )
    rename_global_tag = section_between(
        tags_store,
        "func renameGlobalTag(_ old: String, to new: String)",
        "func removeGlobalTag(_ tag: String)",
    )
    remove_global_tag = section_between(
        tags_store,
        "func removeGlobalTag(_ tag: String)",
        "    // MARK: - JSON 持久化",
    )
    remove_single_tag = section_between(
        tags_store,
        "func removeTag(_ tag: String, from video: VideoItem)",
        "func setSourcePlatform",
    )
    require(
        "let oldKey = Self.normalizedSubjectiveTagKey(old)" in rename_global_tag
        and "Self.cleanedVideoTagSuggestions([new]).first" in rename_global_tag
        and "tagKey == oldKey" in rename_global_tag
        and "tagKey == newKey" in rename_global_tag
        and "tags.contains(old)" not in rename_global_tag,
        "Global tag rename must replace by normalized tag key so inline edits do not create a second tag.",
    )
    require(
        "let tagKey = Self.normalizedSubjectiveTagKey(tag)" in remove_global_tag
        and "removeVideoTags(matchingKey: tagKey" in remove_global_tag
        and "rebuildAllTagsCache()" in remove_global_tag
        and "markLibrarySidebarMetricsDirty()" in remove_global_tag
        and "refreshFilteredVideos()" in remove_global_tag,
        "Global tag deletion must remove by normalized tag key so display-normalized tags do not remain.",
    )
    require(
        "let tagKey = Self.normalizedSubjectiveTagKey(tag)" in remove_single_tag
        and "removeVideoTags(matchingKey: tagKey" in remove_single_tag
        and "selectedTags = Set(selectedTags.filter" in remove_single_tag
        and "tags.removeAll { $0 == tag }" not in remove_single_tag,
        "Single-video tag deletion must also remove by normalized key rather than exact display text.",
    )
    require(
        "var persistedVideoTagPaths = Set<String>()" in library_store
        and "relative[ProjectRepository.relativePath(for: absPath, base: libraryURL)] = cleanedTags" in save_tags_json
        and "guard !cleanedTags.isEmpty else" not in save_tags_json
        and "persistedVideoTagPaths = pathsToPersist" in save_tags_json
        and "persistedVideoTagPaths = loadedTagPaths" in load_tags_json
        and "loadedTagsByVideoPath.removeValue(forKey: absPath)" in load_tags_json
        and "guard !persistedVideoTagPaths.contains(path) else { continue }" in pending_folder_tags,
        "Video tag persistence must write empty tag arrays as tombstones so deleted folder-derived tags do not reappear after restart.",
    )


def require_frame_tag_popover_spacing_guardrails(sources: dict[str, str]) -> None:
    frames = sources.get("LapianBao/Views/Frames/FramesWorkspaceView.swift", "")
    frame_detail_tag_strip = sources.get("LapianBao/Views/Frames/FrameDetailTagStrip.swift", "")
    tags_and_badges = sources.get("LapianBao/Views/Components/TagsAndBadges.swift", "")
    export_panel = sources.get("LapianBao/Views/Preview/PreviewPanelView+ExportPanel.swift", "")
    agents = read("AGENTS.md")
    more_popover = section_between(
        frames,
        "private var morePopover: some View",
        "private var actionSection: some View",
    )
    require(
        "let tagVerticalInset: CGFloat = 16" in more_popover
        and "let tagContentGap: CGFloat = tagVerticalInset" in more_popover
        and "inputSpacing: tagContentGap" in more_popover
        and "gridVerticalPadding: 0" in more_popover
        and ".padding(.top, tagVerticalInset)" in more_popover
        and ".padding(.bottom, tagVerticalInset)" in more_popover,
        "Frame card tag popover must keep the tag search field visually centered between the popover top and divider.",
    )
    require(
        ".padding(.bottom, 6)" not in more_popover,
        "Frame card tag popover must not use asymmetric bottom padding below the tag search field.",
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
    inline_tag_add_button = section_between(
        tags_and_badges,
        "struct InlineTagAddButton: View",
        "struct PreviewTitleTagChip: View",
    )
    export_frame_tag_preview = section_between(
        export_panel,
        "func exportFrameTagPreview(for frame: SampledFrame) -> some View",
        "func exportAudioTagPreview(for clip: AudioClipItem) -> some View",
    )
    require(
        "let title: String?" in inline_tag_add_button
        and "let tagHorizontalInset: CGFloat = 14" in inline_tag_add_button
        and "let tagVerticalInset: CGFloat = 16" in inline_tag_add_button
        and "let tagContentGap: CGFloat = tagVerticalInset" in inline_tag_add_button
        and "inputSpacing: tagContentGap" in inline_tag_add_button
        and "gridVerticalPadding: 0" in inline_tag_add_button
        and ".padding(.horizontal, tagHorizontalInset)" in inline_tag_add_button
        and ".padding(.vertical, tagVerticalInset)" in inline_tag_add_button
        and ".padding(12)" not in inline_tag_add_button,
        "Inline tag add popovers must use the same spacing as the other tag menus.",
    )
    require(
        "title: nil" in export_frame_tag_preview
        and 'title: "图片标签"' not in export_frame_tag_preview,
        "Export-panel image tag popovers must match content tag menus and not show an extra 图片标签 title.",
    )
    require(
        "GeometryReader" in export_frame_tag_preview
        and "let rows = exportFrameTagTwoLineLayout(tags: frame.tags, maxWidth: proxy.size.width)" in export_frame_tag_preview
        and "ForEach(Array(rows.enumerated()), id: \\.offset)" in export_frame_tag_preview
        and "exportFrameTagPreviewItem(item, frame: frame)" in export_frame_tag_preview
        and "VideoTagOverflowChip(count: hiddenCount)" in export_frame_tag_preview
        and "InlineTagAddButton(" in export_frame_tag_preview
        and ".frame(width: proxy.size.width, height: 38, alignment: .topLeading)" in export_frame_tag_preview
        and "WrappingFilterChipGroup" not in export_frame_tag_preview,
        "Export-panel image tag rows must use two lines and keep the add button immediately after visible tags and overflow.",
    )
    require(
        "private func exportFrameTagTwoLineLayout(tags: [String], maxWidth: CGFloat) -> [[ExportFrameTagPreviewItem]]" in export_panel
        and "for visibleCount in stride(from: tags.count, through: 1, by: -1)" in export_panel
        and "fallbackItems: [ExportFrameTagPreviewItem] = [.tag(tags[0])]" in export_panel
        and "guard rows.count < 2 else { return nil }" in export_panel
        and "func exportFrameMiniTagChipWidth(for tag: String)" in export_panel
        and "func exportFrameTagOverflowChipWidth(for hiddenCount: Int)" in export_panel,
        "Export-panel image tag rows must compute two-line visible tags from available width and show a real tag before overflow fallback.",
    )
    frame_detail_overlay = section_between(
        frames,
        "private func frameDetailOverlay(_ frame: SampledFrame) -> some View",
        "private func storyboardDetailOverlay",
    )
    storyboard_detail_overlay = section_between(
        frames,
        "private func storyboardDetailOverlay(_ item: FrameStoryboardItem) -> some View",
        "private func frameDetailTopBar",
    )
    frame_detail_top_bar = section_between(
        frames,
        "private func frameDetailTopBar(",
        "private func frameDetailBottomBar",
    )
    frame_detail_bottom_bar = section_between(
        frames,
        "private func frameDetailBottomBar(",
        "private func frameDetailIconButton",
    )
    frame_detail_icon_button = section_between(
        frames,
        "private func frameDetailIconButton(",
        "private func selectedFrameDetailPreview",
    )
    detail_overlay_container = section_between(
        frames,
        "private func detailOverlayContainer<Content: View>",
        "private func frameDetailOverlay",
    )
    detail_overlay_presentation = section_between(
        frames,
        "private func presentFrameDetail(_ frame: SampledFrame)",
        "private func storyboardCardTitle",
    )
    detail_overlay_dismissal = section_between(
        frames,
        "private func dismissFrameDetailOverlay()",
        "private func stopDetailPlayback",
    )
    require(
        "struct FrameDetailTagStrip: View" in frame_detail_tag_strip,
        "Frame detail tag strip must live in its own focused view file.",
    )
    require(
        "FrameDetailMoreButton" not in frames
        and "detailPopover" not in frames,
        "Frame detail overlay must remove the old ellipsis popover menu.",
    )
    require(
        "FrameDetailTagStrip(" in frame_detail_top_bar
        and "HStack(alignment: .center, spacing: 14)" in frame_detail_top_bar
        and "ColorSwatches(imageData: colorData, orientation: .horizontal)" in frame_detail_top_bar
        and frame_detail_top_bar.count(".frame(maxWidth: .infinity") >= 2,
        "Frame detail top bar must split tags and color swatches into left/right halves above the image.",
    )
    require(
        "private let frameDetailRowSpacing: CGFloat = 8" in frames
        and "private let frameDetailTopBarHeight: CGFloat = FrameDetailTagStrip.rowHeight" in frames
        and "private let frameDetailBottomBarHeight: CGFloat = 34" in frames
        and "VStack(alignment: .center, spacing: frameDetailRowSpacing)" in frame_detail_overlay
        and "VStack(alignment: .center, spacing: frameDetailRowSpacing)" in storyboard_detail_overlay
        and ".padding(frameDetailRowSpacing)" in frame_detail_overlay
        and ".padding(frameDetailRowSpacing)" in storyboard_detail_overlay
        and ".padding(16)" not in frame_detail_overlay
        and ".padding(16)" not in storyboard_detail_overlay
        and ".frame(height: frameDetailTopBarHeight, alignment: .center)" in frame_detail_top_bar
        and ".frame(maxWidth: .infinity, alignment: .center)" in frame_detail_top_bar
        and ".frame(height: frameDetailBottomBarHeight, alignment: .center)" in frame_detail_bottom_bar
        and ".frame(maxWidth: .infinity, alignment: .center)" in frame_detail_bottom_bar,
        "Frame detail overlay must use the same compact vertical spacing for outer padding and row gaps.",
    )
    require(
        "private func detailOverlayWidth(for previewWidth: CGFloat) -> CGFloat" in frames
        and "previewWidth + frameDetailRowSpacing * 2" in frames
        and ".frame(width: 720)" not in frame_detail_overlay
        and ".frame(width: 720)" not in storyboard_detail_overlay,
        "Frame detail overlay outer frame must follow the preview width plus the same compact padding.",
    )
    require(
        ".transition(" not in detail_overlay_container
        and ".contentShape(Rectangle())" in detail_overlay_container
        and ".onTapGesture(perform: dismiss)" in detail_overlay_container
        and ".allowsHitTesting(false)" not in detail_overlay_container
        and "FrameDetailOutsideClickMonitor" not in frames
        and "private func dismissDetailOverlayWithoutAnimation(_ update: () -> Void)" in detail_overlay_dismissal
        and "transaction.disablesAnimations = true" in detail_overlay_dismissal
        and "withTransaction(transaction)" in detail_overlay_dismissal
        and "selectedFrameID = nil" in detail_overlay_dismissal,
        "Frame detail overlay backdrop must consume blank-area clicks while removing immediately for the next click.",
    )
    require(
        "private func presentFrameDetail(_ frame: SampledFrame)" in detail_overlay_presentation
        and "detailStoryboardItem = nil" in detail_overlay_presentation
        and "selectedFrameID = frame.id" in detail_overlay_presentation
        and "private func presentStoryboardDetail(_ item: FrameStoryboardItem)" in detail_overlay_presentation
        and "detailFrame = nil" in detail_overlay_presentation
        and "detailStoryboardItem = item" in detail_overlay_presentation,
        "Frame detail overlay presentation must keep saved-frame and storyboard detail states mutually exclusive.",
    )
    require(
        "case .tag(let tag):" in frame_detail_tag_strip
        and "Button {" in frame_detail_tag_strip
        and "onRemove?(tag)" in frame_detail_tag_strip
        and "InlineTagAddButton(" in frame_detail_tag_strip
        and "VideoTagOverflowChip(count: hiddenCount)" in frame_detail_tag_strip
        and "buttonSize: addButtonWidth" in frame_detail_tag_strip,
        "Frame detail tag strip must remove a tag on chip repeat-click and keep the add button at the end of the tag row.",
    )
    require(
        "static let rowHeight: CGFloat = 24" in frame_detail_tag_strip
        and "private func singleLineLayout(tags: [String], maxWidth: CGFloat) -> [RowItem]" in frame_detail_tag_strip
        and "for visibleCount in stride(from: tags.count, through: 1, by: -1)" in frame_detail_tag_strip
        and "rowWidth(items) <= availableWidth" in frame_detail_tag_strip
        and "fallbackItems: [RowItem] = [.tag(tags[0])]" in frame_detail_tag_strip
        and "twoLineLayout" not in frame_detail_tag_strip,
        "Frame detail tag strip must use a single-row layout with overflow so the top bar does not add hidden vertical padding.",
    )
    require(
        ".frame(width: proxy.size.width, height: rowHeight, alignment: .leading)" in frame_detail_tag_strip
        and "stripHeight" not in frame_detail_tag_strip,
        "Frame detail tag strip must use the visible single-row height instead of reserving two rows.",
    )
    require(
        "frameDetailTopBar(" in frame_detail_overlay
        and "let previewWidth = detailPreviewSize(for: previewImage).width" in frame_detail_overlay
        and "let overlayWidth = detailOverlayWidth(for: previewWidth)" in frame_detail_overlay
        and "VStack(alignment: .center" in frame_detail_overlay
        and frame_detail_overlay.count(".frame(width: previewWidth, alignment: .center)") >= 2
        and ".frame(width: overlayWidth)" in frame_detail_overlay
        and "selectedFrameDetailPreview(currentFrame, fallbackImage: previewImage)" in frame_detail_overlay
        and "frameDetailBottomBar(" in frame_detail_overlay
        and "FrameDetailMoreButton(" not in frame_detail_overlay
        and "ColorSwatches(" not in frame_detail_overlay,
        "Saved frame detail overlay must align its top bar, preview, and bottom bar to the preview width.",
    )
    require(
        "libraryStore.removeFrameTag($0, from: currentFrame)" in frame_detail_overlay
        and "removeFrameTagOrDeleteIfEmpty" not in frame_detail_overlay,
        "Saved frame detail tag repeat-click must only cancel that tag; image deletion belongs to the bottom delete button.",
    )
    require(
        "frameDetailTopBar(" in storyboard_detail_overlay
        and "let previewWidth = detailPreviewSize(for: previewImage).width" in storyboard_detail_overlay
        and "let overlayWidth = detailOverlayWidth(for: previewWidth)" in storyboard_detail_overlay
        and "VStack(alignment: .center" in storyboard_detail_overlay
        and storyboard_detail_overlay.count(".frame(width: previewWidth, alignment: .center)") >= 2
        and ".frame(width: overlayWidth)" in storyboard_detail_overlay
        and "storyboardItemDetailPreview(item, fallbackImage: previewImage)" in storyboard_detail_overlay
        and "frameDetailBottomBar(" in storyboard_detail_overlay
        and "FrameDetailMoreButton(" not in storyboard_detail_overlay
        and "ColorSwatches(" not in storyboard_detail_overlay,
        "Storyboard detail overlay must align its top bar, preview, and bottom bar to the preview width.",
    )
    require(
        "libraryStore.removeFrameTag($0, from: sample)" in storyboard_detail_overlay
        and "removeFrameTagOrDeleteIfEmpty" not in storyboard_detail_overlay,
        "Storyboard detail tag repeat-click must only cancel that tag; image deletion belongs to the bottom delete button.",
    )
    require(
        '"arrowshape.turn.up.left.fill"' in frame_detail_bottom_bar
        and '"folder"' in frame_detail_bottom_bar
        and '"play.fill"' in frame_detail_bottom_bar
        and '"pause.fill"' in frame_detail_bottom_bar
        and '"trash"' in frame_detail_bottom_bar
        and "toggleDetailPlayback(video: video, startTime: startTime, key: playbackKey)" in frame_detail_bottom_bar,
        "Frame detail bottom bar must expose jump, Finder, centered playback, and delete controls without an ellipsis menu.",
    )
    require(
        ".background(" not in frame_detail_bottom_bar
        and "Circle()" not in frame_detail_bottom_bar
        and ".background(" not in frame_detail_icon_button
        and "Circle()" not in frame_detail_icon_button
        and ".frame(width: 30" not in frame_detail_icon_button
        and ".contentShape(Rectangle())" in frame_detail_bottom_bar
        and ".contentShape(Rectangle())" in frame_detail_icon_button,
        "Frame detail bottom buttons must stay as plain icon buttons without circular backgrounds or invisible side insets.",
    )
    require(
        "画面详情浮层不使用省略号菜单" in agents
        and "顶部栏左半显示可点击取消的单行标签并在末尾放加号" in agents
        and "显示不下时用溢出 chip" in agents
        and "右半显示色卡" in agents
        and "按预览框实际宽度居中对齐" in agents
        and "外框宽度跟随预览框宽度加统一 padding" in agents
        and "关闭时立即移除遮罩" in agents
        and "空白处点击只关闭并消费当前点击" in agents
        and "外层上下 padding 与行间距使用同一个较小值" in agents
        and "底部栏左侧为回到原视频和访达" in agents
        and "底部按钮不加圆形背景" in agents,
        "AGENTS must record the frame detail overlay layout so future UI work keeps this design.",
    )


def require_frame_tag_filter_edit_guardrails(sources: dict[str, str]) -> None:
    frames = sources.get("LapianBao/Views/Frames/FramesWorkspaceView.swift", "")
    store = sources.get("LapianBao/Stores/LibraryStore+TimelineMedia.swift", "")
    inline_field = sources.get("LapianBao/Views/Components/InlineTagRenameTextField.swift", "")
    quick_bar = section_between(
        frames,
        "private var frameTagQuickFilterBar",
        "@ViewBuilder\n    private func frameModeButton",
    )
    edit_chip = section_between(
        frames,
        "private func editableFrameTagFilterChip",
        "private var frameTagEditButton",
    )
    edit_flow = section_between(
        frames,
        "private func beginFrameTagRename",
        "private func frameTagCountsByName",
    )
    require(
        "frameTagEditButton" in quick_bar
        and "editableFrameTagFilterChip(" in quick_bar
        and "frameTagFilterChip(" in quick_bar
        and "isFrameTagEditing" in frames
        and "@FocusState private var focusedFrameTagRenameTarget" in frames,
        "Frame tag filter row must include inline edit mode after the frame tag chips.",
    )
    require(
        "InlineTagRenameTextField(" in edit_chip
        and 'Image(systemName: "xmark")' in edit_chip
        and "frameTagFilterCountWidth(for: count)" in edit_chip,
        "Editable frame tag chips must reuse the inline rename field and replace the count slot with delete.",
    )
    require(
        "libraryStore.renameGlobalFrameTag" in edit_flow
        and "libraryStore.removeGlobalFrameTag" in edit_flow
        and "exitFrameTagEditing()" in frames,
        "Frame tag edit mode must rename/delete global frame tags and cleanly exit edit mode.",
    )
    require(
        "func renameGlobalFrameTag" in store
        and "func removeGlobalFrameTag" in store
        and "normalizedFrameTagKey" in store,
        "LibraryStore must support global frame tag rename/delete by normalized key.",
    )
    require(
        "struct InlineTagRenameTextField" in inline_field
        and "placeCaretAtEnd()" in inline_field,
        "Inline tag rename field must stay shared across tag edit surfaces.",
    )


def require_frame_detail_playback_guardrails(sources: dict[str, str]) -> None:
    frames = sources.get("LapianBao/Views/Frames/FramesWorkspaceView.swift", "")
    detail_playback_toggle = section_between(
        frames,
        "private func toggleDetailPlayback",
        "private func playDetailSegment",
    )
    require(
        "detailPlaybackResumeTime(video: video, startTime: startTime, key: key)" in detail_playback_toggle
        and "previewController.elapsed" in detail_playback_toggle
        and "detailPlaybackEndTime(for: video, after: startTime)" in detail_playback_toggle
        and "return currentTime >= endTime - endTolerance ? startTime : currentTime" in detail_playback_toggle
        and "playDetailSegment(video: video, startTime: resumeTime, key: key)" in detail_playback_toggle,
        "Frame detail playback must restart from the image anchor after a segment finishes instead of treating the end time as the next segment start.",
    )


def require_account_login_and_saved_import_removed_guardrails(sources: dict[str, str]) -> None:
    combined = "\n".join(
        text
        for relative, text in sources.items()
        if relative.startswith("LapianBao/") or relative.startswith("README")
    )
    removed_files = [
        "LapianBao/Stores/LibraryStore+AccountCookies.swift",
        "LapianBao/Stores/LibraryStore+BrowserCookies.swift",
        "LapianBao/Stores/LibraryStore+SavedImportBaselines.swift",
    ]
    require(
        all(path not in sources for path in removed_files),
        "Account cookie and saved-import baseline source files must stay removed.",
    )
    forbidden_tokens = [
        "withExportedAccountCookies",
        "withExportedChromeCookies",
        "AccountCookieSummary",
        "AccountLoginTarget",
        "prewarmSavedCollectionCookieCache",
        "latestInstagramSavedImportCandidatesFromChrome",
        "latestXiaohongshuSavedVideoImportCandidatesFromChrome",
        "fetchLatestInstagramSaved",
        "fetchLatestXiaohongshuSaved",
        "SavedImportCandidate",
        "InstagramSavedImport",
        "ChromeCookieFileCache",
        "cachedOrExportedChromeCookieURL",
        "browserCookieCandidates",
        "--cookies-from-browser",
    ]
    offenders = [token for token in forbidden_tokens if token in combined]
    require(
        not offenders,
        "Account login, browser-cookie, and saved-collection import code must stay removed: "
        + ", ".join(offenders),
    )


def require_annotation_editor_guardrails(sources: dict[str, str]) -> None:
    preview_panel = sources.get("LapianBao/Views/Preview/PreviewPanelView.swift", "")
    timeline_details = sources.get("LapianBao/Views/Preview/PreviewPanelView+TimelineDetails.swift", "")
    agents = read("AGENTS.md")
    annotation_editor = section_between(
        timeline_details,
        "func annotationEditorView(for video: VideoItem) -> some View",
        "func beginAnnotation",
    )
    annotation_text_view = section_between(
        timeline_details,
        "private struct AnnotationEditorTextView: NSViewRepresentable",
        "    final class Coordinator",
    )
    save_button = section_between(
        annotation_editor,
        'Button("保存")',
        ".disabled(annotationText.trimmingCharacters",
    )
    require(
        "static let annotationEditorWidth: CGFloat = 336" in preview_panel
        and "static let annotationEditorHeight: CGFloat = 226" in preview_panel
        and ".padding(.horizontal, 18)" in annotation_editor
        and ".padding(.vertical, 16)" in annotation_editor
        and ".frame(height: 122)" in annotation_editor,
        "Annotation editor must keep enough page width and balanced content spacing.",
    )
    require(
        ".font(.system(size: 15, weight: .semibold))" in annotation_editor
        and "textView.font = .systemFont(ofSize: 15, weight: .regular)" in annotation_text_view
        and "textView.textContainerInset = NSSize(width: 12, height: 10)" in annotation_text_view,
        "Annotation editor text must use moderate sizing and explicit horizontal text inset.",
    )
    require(
        ".keyboardShortcut(.defaultAction)" not in save_button,
        "Annotation editor save must not bind Return; Return should stay available for multiline text input.",
    )
    require(
        "批注编辑弹层要保留舒适的输入区左右内边距" in agents
        and "回车用于输入换行" in agents
        and "不能作为保存批注的默认动作" in agents,
        "AGENTS must record annotation editor spacing and Return-key behavior.",
    )


def require_preview_timeline_playback_viewport_guardrails(sources: dict[str, str]) -> None:
    preview_panel = sources.get("LapianBao/Views/Preview/PreviewPanelView.swift", "")
    timeline_layout = sources.get("LapianBao/Views/Preview/PreviewPanelView+TimelineLayout.swift", "")
    timeline_details = sources.get("LapianBao/Views/Preview/PreviewPanelView+TimelineDetails.swift", "")
    helpers = sources.get("LapianBao/Views/Preview/PreviewPanelView+HelpersAndKeyboard.swift", "")
    timeline_components = sources.get("LapianBao/Views/Components/CardAndTimelineHelpers.swift", "")
    status_tiles = sources.get("LapianBao/Views/Components/StatusAndSceneTiles.swift", "")
    scene_panel = sources.get("LapianBao/Views/Preview/ScenePanelView.swift", "")
    home_content = sources.get("LapianBao/Views/Preview/PreviewPanelView+HomeContent.swift", "")
    timeline_controls = sources.get("LapianBao/Views/Preview/TimelineControls.swift", "")
    agents = read("AGENTS.md")

    timeline_stack = section_between(
        timeline_layout,
        "func timelineStackContainer(",
        "@ViewBuilder\n    func compositeTimelineStack",
    )
    require(
        "PlaybackClockDrivenView(" in timeline_stack
        and "duration: controller.duration" in timeline_stack
        and "playbackRate: controller.playbackRate" in timeline_stack
        and "isPlaying: controller.isPlaying" in timeline_stack,
        "Preview timeline stack must keep using the interpolated playback clock for smooth playback display.",
    )

    focus_scene_timeline = section_between(
        helpers,
        "func focusSceneTimelineOnOpeningIfNeeded()",
        "func sceneTimelineOpeningFocusKey",
    )
    require(
        "activePreviewTab == .frames" not in focus_scene_timeline
        and "timelineViewportSpan >= 0.999" in focus_scene_timeline
        and "timelineOffset <= 0.0005" in focus_scene_timeline
        and "updateTimelineViewportWithoutAnimation(" in focus_scene_timeline,
        "Scene timeline default zoom must apply whenever the frame timeline viewport is reset, not only when the frames tab is active.",
    )

    scene_progress_overlay = section_between(
        timeline_components,
        "struct SceneStoryboardProgressOverlay: View",
        "struct FrameStripTimelineStrip: View",
    )
    require(
        "SmoothTimelineProgressReader(" not in scene_progress_overlay
        and "PlaybackTimelineAnimation.normalizedProgress(activeProgress)" in scene_progress_overlay
        and "transaction.disablesAnimations = true" in scene_progress_overlay,
        "Scene storyboard progress must consume the outer smooth clock directly and must not add a second progress interpolator.",
    )
    frame_timeline = section_between(
        timeline_details,
        "func frameTimeline(for video: VideoItem, clock: PlaybackClockSnapshot) -> some View",
        "func audioTimeline(for video: VideoItem, clock: PlaybackClockSnapshot) -> some View",
    )
    timeline_image_layer = section_between(
        timeline_components,
        "private final class TimelineImageLayerStripView: NSView",
        "struct SceneStoryboardStrip: View",
    )
    require(
        "func displayedTimelineOffset(for progress: Double) -> Double" in helpers
        and "controller.isPlaying || keyboardShuttleDirection != 0" in helpers
        and "let viewportStart = displayedTimelineOffset(for: clock.progress)" in frame_timeline
        and "viewportStart: viewportStart" in frame_timeline
        and "private var imageLayerIDs: [ObjectIdentifier?]" in timeline_image_layer
        and "private var cachedImageIDs: [ObjectIdentifier]" in timeline_image_layer
        and "if imageLayerIDs[index] != imageID" in timeline_image_layer
        and "imageLayer.contents = cgImage(for: item.image)" in timeline_image_layer,
        "Frame timeline playback follow must use the smooth clock for display offset and avoid resetting image layer contents on every frame.",
    )
    require(
        "activeProgressTick" not in timeline_layout
        and "activeProgressTick" not in timeline_details
        and "activeProgressTick" not in scene_panel
        and "activeProgressTick" not in home_content
        and "sceneGridProgressTick" not in timeline_layout
        and "struct SceneCutTileActivePlayback" in status_tiles
        and "private struct SceneCutTileActiveProgressOverlay" in status_tiles
        and "PlaybackClockDrivenView(" in status_tiles
        and "SceneCutTileProgressOverlay(progress: progress(for: clock.elapsed))" in status_tiles
        and "activePlayback: activePlayback(for: item)" in scene_panel
        and "playbackDuration: controller.duration" in timeline_details
        and "playbackRate: controller.playbackRate" in timeline_details
        and "isPlaybackPlaying: controller.isPlaying" in timeline_details,
        "Expanded frame timeline progress must update only the active tile overlay at 60fps instead of rebuilding the scene grid.",
    )
    require(
        "controller.seekToSeconds(sceneGridSeekTime(for: item), snapToFrame: false)" in scene_panel
        and "private func sceneGridSeekTime(for item: SceneGridItem) -> Double" in scene_panel
        and "let frameStep = 1 / max(controller.frameRate, 1)" in scene_panel
        and "let nudge = min(max(frameStep, 0.02), 0.05)" in scene_panel
        and "sceneCutActivationBoundaryTolerance" in helpers
        and "let target = controller.elapsed + sceneCutActivationBoundaryTolerance" in helpers
        and "分镜网格点击场景卡片时不能直接 seek 到剪辑点边界" in agents
        and "`activeSceneItemID` 也要保留剪辑点边界容差" in agents,
        "Scene grid tile clicks must seek just inside the selected segment and keep active-tile boundary tolerance.",
    )
    require(
        "主页画面时间线的默认缩放由场景数量决定" in agents
        and "不要依赖当前激活的是不是画面 tab" in agents
        and "不要再套第二层进度插值" in agents,
        "AGENTS must record the preview timeline default zoom and single-interpolator rules.",
    )
    require(
        "横向跟随必须用平滑播放 clock 计算显示用 viewport offset" in agents
        and "不能只靠 30fps 发布状态跳动" in agents
        and "只有当前活动卡片的进度层可以用 60fps clock 更新" in agents,
        "AGENTS must record the smooth frame timeline follow and active-tile-only progress rules.",
    )

    audio_timeline = section_between(
        timeline_details,
        "func audioTimeline(for video: VideoItem, clock: PlaybackClockSnapshot) -> some View",
        "func contentTimeline(for video: VideoItem, clock: PlaybackClockSnapshot) -> some View",
    )
    annotation_marker_point = section_between(
        timeline_layout,
        "func annotationMarkerPoint(in size: CGSize) -> CGPoint",
        "func visibleAnnotationSourceTab()",
    )
    require(
        "@State var audioTimelineZoom: Double = 1" in preview_panel
        and "resetAudioTimelineViewport()" in preview_panel
        and "var audioTimelineViewportSpan: Double" in helpers
        and "Design.centeredWaveformViewportSpan" in helpers
        and "func zoomAudioTimelineViewport(_ factor: Double, anchor _: Double)" in helpers
        and "audioTimelineZoom = nextZoom" in helpers
        and "viewportSpan: audioTimelineViewportSpan" in audio_timeline
        and "zoomViewport: zoomAudioTimelineViewport" in audio_timeline
        and "let span = audioTimelineViewportSpan" in annotation_marker_point
        and "MagnificationGesture()" in timeline_controls
        and "zoomViewport?(Double(factor), 0.5)" in timeline_controls
        and "主页声音时间线保持播放头居中" in agents
        and "必须支持双指捏合缩放" in agents
        and "不复用画面时间线的 `timelineZoom/timelineOffset` 状态" in agents,
        "Home audio timeline must support pinch zoom through its own centered-waveform zoom state.",
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
        and settings.count("VStack(alignment: .leading, spacing: Self.rowTextSpacing)") >= 1,
        "Settings rows with title, note, and status must use fixed spacing and a shared gray description color.",
    )
    require(
        'description: "使用开源下载工具，请保证网络环境。"' in downloader_card
        and "Text(description)" in compact_info_column
        and ".foregroundStyle(Self.rowDescriptionColor)" in compact_info_column
        and "detailColor: downloaderSelfCheckDetailColor(for: report)" in downloader_card
        and "private func downloaderSelfCheckDetailColor(for report: DownloaderSelfCheckReport) -> Color" in settings
        and "report.status == .succeeded ? .green : Color.yellow.opacity(0.92)" in settings
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
    active_progress_bar = section_between(
        import_jobs,
        "func importActiveProgressBar",
        "func importActiveStatusText",
    )
    require(
        "importActiveProgressBar(for: job)" in active_status
        and "func importActiveProgressBar(for job: RemoteImportJob) -> some View" in import_jobs
        and ".frame(height: 4)" in active_progress_bar
        and "RoundedRectangle(cornerRadius: 2" in active_progress_bar
        and "accessibilityLabel(\"下载进度\")" in active_progress_bar,
        "Active import job cards must render a visible compact progress bar below the source URL.",
    )
    require(
        "func importStatusDetail" not in import_jobs
        and "func importLinearProgress" not in import_jobs
        and "func importIndeterminateProgress" not in import_jobs
        and "ProgressView(value: normalizedProgressFraction(progress))" not in import_jobs,
        "Import job progress must use the custom compact active progress bar instead of a system ProgressView.",
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
    require_global_tag_edit_key_matching_guardrails(sources)
    require_video_tag_popover_spacing_guardrails(sources)
    require_frame_tag_popover_spacing_guardrails(sources)
    require_frame_tag_filter_edit_guardrails(sources)
    require_frame_detail_playback_guardrails(sources)
    require_account_login_and_saved_import_removed_guardrails(sources)
    require_annotation_editor_guardrails(sources)
    require_preview_timeline_playback_viewport_guardrails(sources)
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
            "LapianBao/Views/Components/CardAndTimelineHelpers.swift",
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
    remote_download = swift_sources.get("LapianBao/Stores/LibraryStore+RemoteDownload.swift", "")
    remote_download_types = swift_sources.get("LapianBao/Stores/LibraryStore+RemoteDownloadTypes.swift", "")
    ytdlp_download = swift_sources.get("LapianBao/Stores/LibraryStore+YTDLPDownload.swift", "")
    music_detection = swift_sources.get("LapianBao/Stores/LibraryStore+MusicDetection.swift", "")
    xiaohongshu_download = swift_sources.get("LapianBao/Stores/LibraryStore+XiaohongshuDownload.swift", "")
    requirements_music = read("Tools/requirements-music.txt")
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
        'audioop-lts==0.2.2; python_version >= "3.13"' in requirements_music,
        "Music recognition requirements must only install audioop-lts on Python 3.13+, because bundled Python 3.11 still has audioop.",
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
        "runCurlFetch",
        "isTerminalRemoteImportStatus",
        "remoteImportJobCanReceiveWorkerProgress",
        "instagramBundledImportURL",
        "downloadInstagramCarouselBundleIfNeeded",
        "concatenateVideosWithFFmpeg",
    ]:
        require(
            helper in library_store,
            f"Remote import helper is missing: {helper}.",
        )
    require(
        "cookieFileURL: URL? = nil" in launch_imports
        and '--cookie", cookieFileURL.path' in launch_imports
        and "cookieFileURL:" not in xiaohongshu_download,
        "Plain Xiaohongshu page fetch must not pass account cookies.",
    )
    require(
        "func ytdlpBilibiliArgumentAttempts()" in ytdlp_download
        and "bilibili:prefer_multi_flv=False" in ytdlp_download
        and "bilibili:prefer_multi_flv=True" in ytdlp_download
        and "ytdlpBilibiliHTTPHeaderArguments()" in ytdlp_download
        and '"--add-header", "Origin:https://www.bilibili.com"' in ytdlp_download
        and ytdlp_download.count("arguments += ytdlpBilibiliHTTPHeaderArguments()") >= 3
        and "ytdlpPrintedRemoteImportCandidateMetadata(for:" in ytdlp_download
        and '"--print", "title"' in ytdlp_download
        and '"--print", "uploader"' in ytdlp_download
        and '"--print", "thumbnail"' in ytdlp_download
        and "candidateTitle" in launch_imports
        and "candidateAuthorName" in launch_imports
        and "candidateSummary" not in library_store
        and "importActiveTitleText(for:" in content_view
        and "importActiveSubtitleText(for:" in content_view
        and '["-f", "b"]' in ytdlp_download
        and "isIgnorableYTDLPDiagnosticLine" in music_detection
        and 'hasPrefix("warning:")' in music_detection
        and 'let isBilibiliSource = platform == "Bilibili" || isBilibiliURL(sourceURL)' in remote_download
        and "if isBilibiliSource {" in remote_download
        and "if let ytdlpFailure" in remote_download,
        "Bilibili import must send the current Origin header, try multiple yt-dlp modes, and surface the real yt-dlp failure instead of a generic all-methods error or yt-dlp warning.",
    )
    require(
        "instagramBundledImportURL(for: sourceURL)" in library_store
        and "instagramBaseContentURL(from: url)?.absoluteString" in library_store
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
