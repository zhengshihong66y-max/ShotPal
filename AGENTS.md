# Project Rules

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
