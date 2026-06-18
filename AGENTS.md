# Project Rules

## Library Toolbar Pixel Lock

- Do not change the home/library toolbar geometry unless the user explicitly asks to redesign it.
- Treat the home toolbar as the pixel reference for every other workspace toolbar.
- Locked values:
  - Top inset: `14pt`
  - Horizontal content inset: `14pt`
  - Toolbar height: `26pt`
  - Search field: `140pt x 26pt` (`280px x 52px` on 2x captures)
  - Search field inner horizontal padding: `9pt`
  - Search icon-to-text spacing: `6pt`
  - Search field corner radius: `7pt`
  - Toolbar button slot: `18pt x 22pt`
  - Search-to-button and button-to-button spacing: `14pt`
- Other workspace top bars must use the same `LibraryToolbar` visual system and `searchExpands: false` so their search boxes match the home toolbar pixel-for-pixel.
- If toolbar spacing, button sizes, search width, search height, padding, or corner radius need to change, first ask the user and compare against fresh screenshots.

## Interaction Hit-Testing Safety

- Never implement a full-window dimming backdrop as `Button { Color... }` or `Button(action: close...) { Color... }`. On macOS SwiftUI this can become a giant accessibility/hit-test button and swallow clicks meant for the sheet or the app underneath.
- Modal/import backdrops must stay as a non-control view: `Color.black.opacity(...).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { ... }.accessibilityHidden(true)`, with the actual sheet content above it via `zIndex`.
- The app-level preview keyboard monitor in `LapianBaoApp.swift` must listen only for keyboard events (`.keyDown`, `.keyUp`). Do not add `.leftMouseDown`, `.rightMouseDown`, or app-wide mouse monitors there.
- Do not call `window.makeFirstResponder(nil)` from an app-level mouse-down monitor. Mouse focus restoration may only live in narrow local bridge views such as `PreviewKeyboardHandler`, and must return the original mouse event.
- If the app suddenly "cannot click", first check for multiple running `LapianBao` instances and stale debug launches with `pgrep -fl LapianBao`; overlapping old windows can make a fixed build look broken.
- After changing overlays, AppKit bridges, keyboard/mouse event routing, `LapianBaoApp.swift`, or `AppChrome.swift`, run `python3 Tools/regression_checks.py`, `xcodebuild -project LapianBao.xcodeproj -scheme LapianBao -destination 'platform=macOS' build`, and `Tools/check_launch_window.sh`.

## Launch Responsiveness

- Do not create the main window synchronously inside `applicationDidFinishLaunching(_:)`. That delegate callback must return quickly and schedule `completeLaunchSetupIfNeeded()` with `DispatchQueue.main.async`.
- Do not run `libraryStore.loadLastLibrary()`, folder scans, media metadata loading, waveform generation, thumbnail generation, or any other potentially expensive startup work before the first main window is ordered front and has had time to paint.
- Startup ownership is split on purpose: `LapianBaoApp.swift` is only the AppDelegate/lifecycle bridge, `AppStartup/AppStartupCoordinator.swift` owns launch order, `AppStartup/AppWindowManager.swift` owns the retained `NSWindow`, and `AppStartup/StartupDiagnostics.swift` owns startup-stage markers. Keep this split; do not move window creation or launch sequencing back into a giant AppDelegate.
- `completeLaunchSetupIfNeeded()` in `AppStartupCoordinator` must keep this order: install menu, create/show the main window, install launch visibility checks and keyboard monitor, activate the app, then defer `libraryStore.loadLastLibraryForLaunch()` with `DispatchQueue.main.asyncAfter`.
- `loadLastLibraryForLaunch()` must keep directory enumeration off the main actor. Startup may update `LibraryStore` on the main actor only after background enumeration has finished.
- Do not restore SwiftUI `WindowGroup` as the primary app window. The app intentionally owns a retained `NSWindow` from `AppDelegate` so Debug/Xcode/Preview/JIT paths cannot leave a process with no usable window.
- After changing `LapianBaoApp.swift`, anything in `AppStartup/`, `AppChrome.swift`, app lifecycle code, window setup, project build settings, or launch scripts, run `Tools/check_launch_window.sh`. Treat a failure as blocking.
- If Dock shows `LapianBao` as "Application Not Responding" or the process has no window, first separate pre-main launch failure from app startup failure. `sample` showing only `_dyld_start`, `vmmap -summary` saying `Process exists but has not started -- it is launched-suspended`, or a roughly 96K footprint means App code has not run yet. In that case inspect enabled Xcode breakpoints, stale `debugserver`/`lldb`, LaunchServices/Xcode state, or signing/quarantine before changing Swift startup code.
- Xcode user breakpoints can pause the app before the first window. `Tools/check_launch_window.sh` fails if any `Breakpoints_v2.xcbkptlist` contains `shouldBeEnabled = "Yes"`; disable those breakpoints before launch verification.

## Timeline Movement Responsiveness

- Playback-driven timeline movement, frame-strip panning, scroll-wheel panning, magnification zooming, and playhead updates are high-frequency paths. Do not let them inherit SwiftUI implicit animations.
- Live timeline viewport changes must be coalesced to display cadence, skip tiny offset deltas, and update state inside an explicit no-animation transaction.
- Keep heavy/static timeline content separate from lightweight moving overlays. Prefer `CALayer`, `Canvas`, or narrowly scoped `NSViewRepresentable` rendering for thumbnail strips, waveforms, and other dense timeline visuals.
- When fixing right-edge stutter in the video timeline or frame timeline, inspect `keepTimelineProgressVisible`, `panTimelineViewport`, `ScrollPanLayer`, `FrameScrubberView`, and `SimpleProgressBar` first.
- After changing timeline movement behavior, test playback near the right edge of a zoomed timeline, manual scroll/pan, pinch zoom, and drag-to-seek before treating the issue as fixed.

## Library Scrolling Responsiveness

- Material-library scrolling is a high-frequency path. `onAppear`, grid row construction, search/filter recomputation, and hover state changes must not synchronously decode images, read file extended attributes, scan folders, generate waveforms/thumbnails, or spawn unbounded work.
- Viewport-triggered thumbnail and metadata work must be coalesced into bounded background queues; the main actor may only receive small batches and throttled display refreshes.
- If the material library becomes unresponsive while scrolling, inspect `videoTile(_:).onAppear`, `queueMetadataLoadIfNeeded`, cached thumbnail hydration, source inference, and `objectWillChange` fan-out before changing visual layout.
- Do not fix scroll freezes by hiding work behind animation or larger grids. Remove the synchronous work from the scroll path.

## Media Tag Domain Separation

- The app has exactly four independent tag domains: video, image/frame, sound effect, and music.
- Video tags live in `tagsByVideoPath` and `.lapianbaotags.json`; video tag buttons and video tag suggestions must use only the video tag domain.
- Image/frame tags live on `SampledFrame.tags`; image tag buttons and image tag suggestions must use only `allFrameTags` / frame-tag mutations.
- Sound effect tags live on `AudioClipItem.tags` and `LocalAudioAsset.tags`; sound effect tag buttons and suggestions must not include source video tags.
- Music tags live on `MusicRecognitionItem.tags` and `LocalMusicAsset.tags`; music tag buttons and suggestions must not include video, image, or sound effect tags.
- Do not use one media type's tags as another media type's defaults, suggestions, filters, or visible tags unless the user explicitly asks for a cross-domain copy/migration command.

## Preview Keyboard Shortcuts

- Preview keyboard shortcuts must be silent. Any handled keyDown/keyUp event must be consumed in every keyboard handling path so macOS never plays the system beep.
- Keep shortcut semantics strict:
  - `Space`: toggle playback.
  - `J`: tap once to step one frame backward; hold to shuttle/drag backward.
  - `L`: tap once to step one frame forward; hold to shuttle/drag forward. It must not start normal forward playback or call `setRate`.
  - Releasing `J` or `L`: stop shuttle/drag.
  - `K`: toggle playback normally; while shuttling with `J` or `L`, increase shuttle speed.
  - Left/Right arrows: step one frame backward/forward.
  - `I`/`O`: set audio in/out.
  - `E`: export current frame image.
  - `U`: clear audio selection.
  - `P`: export audio selection.
- Keyboard command execution has one owner: the app-level `NSEvent` local monitor parses shortcut events and dispatches through `PreviewKeyboardCommandDispatcher`.
- `PreviewKeyboardWindow` and capture views may consume handled events to prevent beeps, but must not independently dispatch shortcut commands.
- When changing keyboard behavior, update `PreviewKeyboardEventRouter` and the app-level monitor first. Only touch window/capture handling to preserve silent consumption.
