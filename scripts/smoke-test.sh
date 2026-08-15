#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/边记.app"

"$ROOT_DIR/scripts/package-app.sh" >/dev/null

"$ROOT_DIR/.build/release/ScreenMarker" --logic-self-test

pkill -x ScreenMarker 2>/dev/null || true
open "$APP_PATH"
sleep 2

PID="$(pgrep -x ScreenMarker || true)"
if [[ -z "$PID" ]]; then
  echo "FAIL: ScreenMarker process did not start"
  exit 1
fi

echo "PASS: ScreenMarker process started: $PID"

swift - <<'SWIFT'
import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
let owned = windows.filter { ($0[kCGWindowOwnerName as String] as? String) == "ScreenMarker" }

print("ScreenMarker visible windows: \(owned.count)")
for window in owned {
    let name = window[kCGWindowName as String] as? String ?? "(unnamed)"
    let layer = window[kCGWindowLayer as String] as? Int ?? -1
    let bounds = window[kCGWindowBounds as String] ?? [:]
    print("- \(name), layer=\(layer), bounds=\(bounds)")
}

if owned.isEmpty {
    print("WARN: macOS did not expose ScreenMarker windows through CGWindowList in this environment")
}
SWIFT

pkill -x ScreenMarker
sleep 1

if pgrep -x ScreenMarker >/dev/null; then
  echo "FAIL: ScreenMarker process did not stop"
  exit 1
fi

echo "PASS: ScreenMarker process stopped"
