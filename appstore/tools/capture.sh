#!/bin/bash
# Builds BRICKS for the simulator and captures the raw App Store screenshots into
# appstore/raw/. Uses the DEBUG launch arguments (-demo, -celebrate n) and the
# UserDefaults argument domain (-bricks.darkMode, -bricks.bestScore) to stage each state.
#
#   appstore/tools/capture.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

BUNDLE=ca.wilsonlam.bricks
IPHONE="iPhone 17 Pro Max"       # 6.9" display: 1320x2868
IPAD="iPad Pro 13-inch (M5)"     # 13" display: 2064x2752
DD=$(mktemp -d)
mkdir -p appstore/raw

xcodebuild -project BRICKS.xcodeproj -scheme BRICKS -configuration Debug -sdk iphonesimulator \
  -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build -quiet
APP="$DD/Build/Products/Debug-iphonesimulator/BRICKS.app"

udid() { xcrun simctl list devices available | grep -F "    $1 (" | head -1 | grep -oE '[0-9A-F-]{36}'; }

shot() { # udid name args...
  local d=$1 name=$2; shift 2
  xcrun simctl terminate "$d" $BUNDLE 2>/dev/null || true
  xcrun simctl launch "$d" $BUNDLE "$@" -bricks.bestScore 4820 >/dev/null
  sleep 3
  xcrun simctl io "$d" screenshot "appstore/raw/$name.png" >/dev/null
}

for dev in iphone ipad; do
  if [ $dev = iphone ]; then d=$(udid "$IPHONE"); else d=$(udid "$IPAD"); fi
  xcrun simctl boot "$d" 2>/dev/null || true
  xcrun simctl bootstatus "$d" -b >/dev/null
  xcrun simctl status_bar "$d" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
  xcrun simctl install "$d" "$APP"
  shot "$d" $dev-1 -demo -bricks.darkMode NO          # Drop. Fill. Clear.
  shot "$d" $dev-2 -celebrate 3 -bricks.darkMode NO   # aqua sky
  shot "$d" $dev-3 -celebrate 0 -bricks.darkMode NO   # blush sky, gifts
  shot "$d" $dev-4 -celebrate 4 -bricks.darkMode NO   # mint sky, power-ups
  shot "$d" $dev-5 -demo -bricks.darkMode YES         # dark mode
done
echo "Captured into appstore/raw/"
