#!/bin/bash
# Captures the raw Mac, Apple TV and Vision Pro screenshots into appstore/raw/
# (mac-N, tv-N, vision-N), staged with the same DEBUG launch arguments as capture.sh.
# The Mac app is captured as its own window; Apple TV and Vision Pro from the simulator.
#
#   appstore/tools/capture-wide.sh [mac] [tv] [vision]     # default: all three
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

BUNDLE=ca.wilsonlam.bricks
TV="Apple TV 4K (4th generation)"
VISION="Apple Vision Pro"
DD=$(mktemp -d)
mkdir -p appstore/raw
PLATFORMS=${*:-mac tv vision}

# Every flag carries a value: on the Mac a bare flag pairs with the next word and the
# leftover is opened as a file, which launches the app without a window.
STATES=(
  "-demo YES -bricks.darkMode NO"                              # Drop. Fill. Clear.
  "-celebrate 3 -bricks.darkMode NO"                           # aqua sky
  "-gameOver YES -gameCenterPreview YES -bricks.darkMode NO"   # achievements
  "-demo YES -bricks.darkMode YES"                             # dark mode
)

udid() { xcrun simctl list devices available | grep -F "    $1 (" | head -1 | grep -oE '[0-9A-F-]{36}'; }

sim() { # name sdk device wait
  local name=$1 sdk=$2 d; d=$(udid "$3")
  xcodebuild -project BRICKS.xcodeproj -scheme BRICKS -configuration Debug -sdk "$sdk" \
    -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build -quiet
  xcrun simctl boot "$d" 2>/dev/null || true
  xcrun simctl bootstatus "$d" -b >/dev/null
  xcrun simctl install "$d" "$DD/Build/Products/Debug-$sdk/BRICKS.app"
  local i=1
  for args in "${STATES[@]}"; do
    xcrun simctl terminate "$d" $BUNDLE 2>/dev/null || true
    sleep 2
    # shellcheck disable=SC2086
    xcrun simctl launch "$d" $BUNDLE $args -bricks.bestScore 4820 >/dev/null
    sleep "$4"   # Vision Pro takes a long time to open the window
    xcrun simctl io "$d" screenshot "appstore/raw/$name-$i.png" >/dev/null
    i=$((i + 1))
  done
}

mac() {
  xcodebuild -project BRICKS.xcodeproj -scheme BRICKS -configuration Debug -destination platform=macOS \
    -derivedDataPath "$DD" build -quiet
  local app="$DD/Build/Products/Debug/BRICKS.app" winid="$DD/winid" i=1
  cat > "$DD/winid.swift" <<'EOF'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "BRICKS" && (w[kCGWindowLayer as String] as? Int) == 0 {
    print(w[kCGWindowNumber as String]!); break
}
EOF
  swiftc -O "$DD/winid.swift" -o "$winid"
  for args in "${STATES[@]}"; do
    pkill -x BRICKS || true
    sleep 2
    # shellcheck disable=SC2086
    open -n "$app" --args $args -bricks.bestScore 4820
    local w=""
    for _ in $(seq 1 20); do w=$("$winid"); [ -n "$w" ] && break; sleep 1; done
    sleep 3
    screencapture -o -x -l"$w" "appstore/raw/mac-$i.png"   # the window alone, no shadow
    i=$((i + 1))
  done
  pkill -x BRICKS || true
}

for p in $PLATFORMS; do
  case $p in
    mac) mac ;;
    tv) sim tv appletvsimulator "$TV" 10 ;;
    vision) sim vision xrsimulator "$VISION" 30 ;;
  esac
done
echo "Captured into appstore/raw/"
