# Project Rules

## Launch Responsiveness

- Do not create the main window synchronously inside `applicationDidFinishLaunching(_:)`. That delegate callback must return quickly and schedule `completeLaunchSetupIfNeeded()` with `DispatchQueue.main.async`.
- Do not run `libraryStore.loadLastLibrary()`, folder scans, media metadata loading, waveform generation, thumbnail generation, or any other potentially expensive startup work before the first main window is ordered front and has had time to paint.
- `completeLaunchSetupIfNeeded()` must keep this order: install menu, create/show the main window, install launch visibility checks and keyboard monitor, activate the app, then defer `libraryStore.loadLastLibraryForLaunch()` with `DispatchQueue.main.asyncAfter`.
- `loadLastLibraryForLaunch()` must keep directory enumeration off the main actor. Startup may update `LibraryStore` on the main actor only after background enumeration has finished.
- Do not restore SwiftUI `WindowGroup` as the primary app window. The app intentionally owns a retained `NSWindow` from `AppDelegate` so Debug/Xcode/Preview/JIT paths cannot leave a process with no usable window.
- After changing `LapianBaoApp.swift`, `AppChrome.swift`, app lifecycle code, window setup, project build settings, or launch scripts, run `Tools/check_launch_window.sh`. Treat a failure as blocking.
- If Dock shows `LapianBao` as "Application Not Responding" after a build, inspect for a stale Xcode `debugserver` holding an old app process before assuming the new build is broken. The real fix is still to keep launch work off the synchronous launch callback.

## Preview Keyboard Shortcuts

- Preview keyboard shortcuts must be silent. Any handled keyDown/keyUp event must be consumed in every keyboard handling path so macOS never plays the system beep.
- Keep shortcut semantics strict:
  - `Space`: toggle playback.
  - `J`: shuttle/drag backward while pressed.
  - `L`: shuttle/drag forward while pressed. It must not start normal forward playback or call `setRate`.
  - Releasing `J` or `L`: stop shuttle/drag.
  - `K`: toggle playback normally; while shuttling with `J` or `L`, increase shuttle speed.
  - Left/Right arrows: step one frame backward/forward.
  - `I`/`O`: set audio in/out.
  - `U`: clear audio selection.
  - `P`: export audio selection.
- Keyboard command execution has one owner: the app-level `NSEvent` local monitor parses shortcut events and dispatches through `PreviewKeyboardCommandDispatcher`.
- `PreviewKeyboardWindow` and capture views may consume handled events to prevent beeps, but must not independently dispatch shortcut commands.
- When changing keyboard behavior, update `PreviewKeyboardEventRouter` and the app-level monitor first. Only touch window/capture handling to preserve silent consumption.
