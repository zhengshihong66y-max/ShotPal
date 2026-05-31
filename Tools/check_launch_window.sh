#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_BASE="${LPB_LAUNCH_CHECK_TMP:-/private/tmp}"
TMP_BASE="${TMP_BASE%/}"
DERIVED_DATA_DIR="$TMP_BASE/LapianBaoLaunchCheckDerivedData"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug/LapianBao.app"
BUNDLE_ID="com.newtybei.LapianBao"
APP_NAME="LapianBao"
APP_SOURCE="$ROOT_DIR/LapianBao/LapianBaoApp.swift"
STARTUP_SOURCE="$ROOT_DIR/LapianBao/AppStartup/AppStartupCoordinator.swift"

visible_cg_window_count() {
  local pid="$1"
  swift - "$pid" <<'SWIFT' 2>/dev/null || printf '0\n'
import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1,
      let pid = Int(CommandLine.arguments[1]),
      let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
    print("0")
    exit(0)
}

let count = windows.filter { window in
    let ownerPID = window[kCGWindowOwnerPID as String] as? Int
    let layer = window[kCGWindowLayer as String] as? Int
    let isOnscreen = window[kCGWindowIsOnscreen as String] as? Int
    let alpha = window[kCGWindowAlpha as String] as? Double
    let bounds = window[kCGWindowBounds as String] as? [String: Any]
    let width = bounds?["Width"] as? Double
    let height = bounds?["Height"] as? Double

    return ownerPID == pid
        && layer == 0
        && isOnscreen == 1
        && (alpha ?? 0) > 0
        && (width ?? 0) >= 40
        && (height ?? 0) >= 40
}.count

print(count)
SWIFT
}

resume_launched_app_processes() {
  local pids
  pids="$(pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" || true)"
  [[ -n "$pids" ]] || return 0
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -CONT "$pid" 2>/dev/null || true
  done <<< "$pids"
}

is_launched_suspended() {
  local pid="$1"
  local vmmap_file="$TMP_BASE/lapianbao-launch-check-vmmap-$pid.txt"
  vmmap -summary "$pid" > "$vmmap_file" 2>/dev/null || return 1
  grep -q 'Process exists but has not started -- it is launched-suspended' "$vmmap_file"
}

cd "$ROOT_DIR"

enabled_breakpoint_files=()
while IFS= read -r -d '' breakpoint_file; do
  if grep -q 'shouldBeEnabled = "Yes"' "$breakpoint_file"; then
    enabled_breakpoint_files+=("$breakpoint_file")
  fi
done < <(find LapianBao.xcodeproj -path '*/xcdebugger/Breakpoints_v2.xcbkptlist' -type f -print0)

if [[ "${#enabled_breakpoint_files[@]}" -gt 0 ]]; then
  echo "Launch check failed: enabled Xcode user breakpoints can pause the app before it opens a window." >&2
  printf '  %s\n' "${enabled_breakpoint_files[@]}" >&2
  exit 1
fi

if ! awk '
  /func applicationDidFinishLaunching/ { in_launch = 1; saw_async = 0; saw_complete = 0 }
  in_launch && /DispatchQueue\.main\.async/ { saw_async = 1 }
  in_launch && /completeLaunchSetupIfNeeded\(\)/ { saw_complete = 1 }
  in_launch && /^    }$/ {
    if (saw_async && saw_complete) ok = 1
    in_launch = 0
  }
  END { exit ok ? 0 : 1 }
' "$APP_SOURCE"; then
  echo "Launch check failed: applicationDidFinishLaunching must defer completeLaunchSetupIfNeeded() with DispatchQueue.main.async." >&2
  exit 1
fi

if ! awk '
  /func completeLaunchSetupIfNeeded/ { in_setup = 1; saw_async_after = 0; bad = 0; ok = 0 }
  in_setup && /DispatchQueue\.main\.asyncAfter/ { saw_async_after = 1 }
  in_setup && /libraryStore\.loadLastLibraryForLaunch\(\)/ && saw_async_after { ok = 1 }
  in_setup && /libraryStore\.loadLastLibrary/ && !saw_async_after { bad = 1 }
  in_setup && /libraryStore\.loadLastLibrary\(\)/ { bad = 1 }
  in_setup && /^    }$/ { in_setup = 0 }
  END { exit (!bad && ok) ? 0 : 1 }
' "$STARTUP_SOURCE"; then
  echo "Launch check failed: startup must defer loadLastLibraryForLaunch() with DispatchQueue.main.asyncAfter; do not call loadLastLibrary() on the launch path." >&2
  exit 1
fi

xcodebuild \
  -project LapianBao.xcodeproj \
  -scheme LapianBao \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

if find "$APP_PATH" -maxdepth 3 -type f \( -name '*debug*' -o -name '*preview*' \) | grep -q .; then
  echo "Launch check failed: Preview/JIT debug files were produced in $APP_PATH" >&2
  exit 1
fi

osascript \
  -e 'with timeout of 2 seconds' \
  -e "tell application id \"$BUNDLE_ID\" to quit" \
  -e 'end timeout' >/dev/null 2>&1 || true
sleep 1

opened="0"
for _ in {1..5}; do
  if open -n "$APP_PATH"; then
    opened="1"
    resume_launched_app_processes
    break
  fi
  sleep 1
done

if [[ "$opened" != "1" ]]; then
  echo "Launch check failed: could not open $APP_PATH" >&2
  exit 1
fi

window_count="0"
app_pid=""
for _ in {1..30}; do
  resume_launched_app_processes
  app_pid="$(pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" | tail -n 1 || true)"
  [[ -n "$app_pid" ]] && window_count="$(visible_cg_window_count "$app_pid" | tail -n 1)"
  if [[ "$window_count" =~ ^[0-9]+$ && "$window_count" -ge 1 ]]; then
    echo "Launch check passed: $APP_NAME opened $window_count visible CoreGraphics window(s)."
    exit 0
  fi
  sleep 0.5
done

if [[ -n "$app_pid" ]]; then
  if is_launched_suspended "$app_pid"; then
    echo "Launch check failed: $APP_NAME is launched-suspended before main() entered." >&2
    echo "This is usually caused by enabled Xcode breakpoints, stale debugserver/lldb state, or LaunchServices/Xcode launch-state pollution; app startup code has not run yet." >&2
    pgrep -fl "$APP_NAME.app/Contents/MacOS/$APP_NAME" >&2 || true
    exit 1
  fi

  sample_file="$TMP_BASE/lapianbao-launch-check-sample-$app_pid.txt"
  sample "$app_pid" 2 -file "$sample_file" >/dev/null 2>&1 || true
  if grep -q 'NSApplication(NSEventRouting).*nextEventMatchingMask' "$sample_file"; then
    if grep -q 'LibraryStore.scanVideos(in:).*LibraryStore.swift' "$sample_file"; then
      echo "Launch check failed: main thread is scanning the library during launch." >&2
      exit 1
    fi
    if grep -q 'PreviewPanelView.init' "$sample_file"; then
      echo "Launch check failed: main thread is stuck constructing PreviewPanelView during launch." >&2
      exit 1
    fi
    echo "Launch check passed: $APP_NAME is running and its main thread is responsive; window count was unavailable in this macOS session."
    exit 0
  fi
fi

echo "Launch check failed: $APP_NAME started without a visible window." >&2
pgrep -fl "$APP_NAME.app/Contents/MacOS/$APP_NAME" >&2 || true
exit 1
