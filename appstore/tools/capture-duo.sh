#!/bin/bash
# Captures the raw iPhone Duo App Store screenshots into appstore/raw/ (duo-1 … duo-4).
# `simctl io` can't capture the Duo's displays, so a UI test (testStoreScreenshots)
# stages each state and keeps its screenshot, and this pulls them out of the results.
#
#   appstore/tools/capture-duo.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

DUO=$(xcrun simctl list devices available | grep -F "    iPhone Duo (" | head -1 | grep -oE '[0-9A-F-]{36}')
TMP=$(mktemp -d)
xcrun simctl boot "$DUO" 2>/dev/null || true
xcrun simctl status_bar "$DUO" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3
TEST_RUNNER_STORE_SHOTS=1 xcodebuild test -project BRICKS.xcodeproj -scheme BRICKS \
  -destination "id=$DUO" -derivedDataPath "$TMP/dd" -resultBundlePath "$TMP/shots.xcresult" \
  -only-testing:BRICKSUITests/BRICKSUITests/testStoreScreenshots CODE_SIGNING_ALLOWED=NO -quiet
xcrun xcresulttool export attachments --path "$TMP/shots.xcresult" --output-path "$TMP/att" >/dev/null
mkdir -p appstore/raw
python3 - "$TMP/att" <<'PY'
import json, shutil, sys
att = sys.argv[1]
for test in json.load(open(f"{att}/manifest.json")):
    for a in test["attachments"]:
        name = a.get("suggestedHumanReadableName", "")
        if name.startswith("store-"):
            n = name.split("_")[0].removeprefix("store-")
            shutil.copy(f"{att}/{a['exportedFileName']}", f"appstore/raw/duo-{n}.png")
PY
rm -rf "$TMP"
echo "Captured appstore/raw/duo-{1..4}.png"
