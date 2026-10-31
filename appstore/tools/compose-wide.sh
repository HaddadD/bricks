#!/bin/bash
# Turns the raw Mac, Apple TV and Vision Pro captures (capture-wide.sh) and the iPhone Duo
# ones (capture-duo.sh) into
# upload-ready App Store screenshots at Apple's sizes in appstore/screenshots/.
#
#   appstore/tools/compose-wide.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
TMP=$(mktemp -d)
swiftc -O appstore/tools/compose-wide.swift -o "$TMP/compose"

# shot: platform index sky headline subtitle
shot() {
  local p=$1 i=$2 dir size
  case $p in
    mac) dir=mac; size="2880 1800" ;;
    tv) dir=apple-tv; size="3840 2160" ;;
    vision) dir=vision-pro; size="3840 2160" ;;
    duo) dir=iphone-duo; size="2007 2853" ;;
  esac
  mkdir -p "appstore/screenshots/$dir"
  # shellcheck disable=SC2086
  "$TMP/compose" "appstore/raw/$p-$i.png" "$p" $size "$3" "$4" "$5" "$TMP/$p-$i.png"
  sips -s format jpeg -s formatOptions 92 "$TMP/$p-$i.png" --out "appstore/screenshots/$dir/0$i.jpg" >/dev/null
}

shot mac 1 FFA3C6 "Drop. Fill. Clear." "A calm block puzzle for your Mac"
shot mac 2 73DFE8 "Every 1,000 points, a new sky" "Seven pastel skies to unlock"
shot mac 3 CCACF5 "52 achievements to chase" "Leaderboards and challenges in Game Center"
shot mac 4 A6BDF7 "Easy on the eyes, day or night" "Full dark mode, same pastel bricks"

shot tv 1 FFA3C6 "Drop. Fill. Clear." "A calm block puzzle for the big screen"
shot tv 2 73DFE8 "Every 1,000 points, a new sky" "Seven pastel skies to unlock"
shot tv 3 CCACF5 "52 achievements to chase" "Leaderboards and achievements in Game Center"
shot tv 4 A6BDF7 "Play from the couch" "Just the Siri Remote, in light or dark"

shot vision 1 FFA3C6 "Drop. Fill. Clear." "A calm block puzzle in your space"
shot vision 2 73DFE8 "Every 1,000 points, a new sky" "Seven pastel skies to unlock"
shot vision 3 CCACF5 "52 achievements to chase" "Leaderboards and challenges in Game Center"
shot vision 4 A6BDF7 "Look, pinch, play" "Put the board anywhere, in light or dark"

shot duo 1 FFA3C6 "Drop. Fill. Clear." "A calm block puzzle that folds into your pocket"
shot duo 2 73DFE8 "Every 1,000 points, a new sky" "Seven pastel skies to unlock"
shot duo 3 CCACF5 "52 achievements to chase" "Leaderboards and challenges in Game Center"
shot duo 4 A6BDF7 "Easy on the eyes, day or night" "Full dark mode, same pastel bricks"

rm -rf "$TMP"
echo "Wrote appstore/screenshots/{mac,apple-tv,vision-pro,iphone-duo}/"
