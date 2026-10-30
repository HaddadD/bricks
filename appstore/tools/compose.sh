#!/bin/bash
# Drops each real simulator screenshot (appstore/raw/) into the green screen of its
# generated backdrop (appstore/art/) and writes the upload-ready App Store
# screenshots at Apple's exact sizes to appstore/screenshots/.
#
#   appstore/tools/compose.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
BIN=$(mktemp -d)/composite
swiftc -O appstore/tools/composite.swift -o "$BIN"

for i in 1 2 3 4 5; do
  "$BIN" appstore/art/iphone-$i.png appstore/raw/iphone-$i.png 1320 2868 /tmp/bricks-iphone-$i.png
  sips -s format jpeg -s formatOptions 92 /tmp/bricks-iphone-$i.png --out appstore/screenshots/iphone-6.9/0$i.jpg >/dev/null
  "$BIN" appstore/art/ipad-$i.png appstore/raw/ipad-$i.png 2064 2752 /tmp/bricks-ipad-$i.png
  sips -s format jpeg -s formatOptions 92 /tmp/bricks-ipad-$i.png --out appstore/screenshots/ipad-13/0$i.jpg >/dev/null
done
rm -f /tmp/bricks-iphone-*.png /tmp/bricks-ipad-*.png
echo "Wrote appstore/screenshots/"
