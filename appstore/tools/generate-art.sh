#!/bin/bash
# Generates the App Store screenshot backdrops (headline, pastel background, floating
# bricks, a device with a chroma-key green screen) with GPT Image 2 through the
# gpt-image-2 skill, which drives the local Codex CLI on a ChatGPT subscription.
# The screen is green so composite.swift can drop the real screenshot in afterwards:
# the UI in the final images is never drawn by the model.
#
#   GEN=~/.claude/skills/gpt-image-2/scripts/gen.sh appstore/tools/generate-art.sh
#
# Existing files in appstore/art/ are skipped; delete one to regenerate it.
# If Codex rejects its configured model, pass a supported one with `-m` (see
# docs/PUBLISHING.md).
set -uo pipefail
cd "$(dirname "$0")/../.."
GEN=${GEN:-$HOME/.claude/skills/gpt-image-2/scripts/gen.sh}
REF=appstore/raw/iphone-1.png   # brick style and palette reference
mkdir -p appstore/art

SCREEN='The phone screen must be a perfectly flat, solid, pure chroma-key green (#00FF00) filling the whole display area edge to edge, with absolutely no content, text, reflection, glare, gradient or shadow on it — it will be replaced later. Keep the black camera cutout / Dynamic Island visible on top of the green if the device has one.'
STYLE='Add a few glossy, chunky rounded pastel bricks (same soft 3D style and palette as the bricks in the attached reference image) floating softly around the device, never overlapping the screen. The headline is a large, bold, rounded sans-serif in dark plum (#4A3F48), the subline smaller and lighter plum. Clean, minimal, premium App Store screenshot. No logos, no watermark, no extra text beyond the headline and subline.'

gen() { # name device background headline subline
  local name=$1 device=$2 bg=$3 head=$4 sub=$5 shape dev
  if [ "$device" = iphone ]; then
    shape='Tall portrait canvas with aspect ratio exactly 1320:2868 (about 1:2.17).'
    dev='a modern iPhone with thin black bezels and a Dynamic Island, straight-on, upright and centred, filling most of the lower two-thirds of the canvas'
  else
    shape='Portrait canvas with aspect ratio exactly 2064:2752 (3:4).'
    dev='a modern iPad Pro in portrait with thin black bezels, straight-on, upright and centred, filling most of the lower area of the canvas'
  fi
  [ -s "appstore/art/$name.png" ] && { echo "skip $name"; return; }
  bash "$GEN" --timeout-sec 500 --ref "$REF" --out "$PWD/appstore/art/$name.png" \
    --prompt "$shape Background: $bg. At the top, the headline \"$head\" and beneath it the subline \"$sub\". Below the text, $dev. $SCREEN $STYLE" \
    && echo "done $name" || echo "FAILED $name"
}

for d in iphone ipad; do
  gen $d-1 $d 'a soft cream-to-lilac pastel gradient' 'Drop. Fill. Clear.' 'A calm, colourful block puzzle'
  gen $d-2 $d 'a soft aqua-to-white pastel gradient' 'Every 1,000 points, a new sky' 'Seven pastel skies to unlock'
  gen $d-3 $d 'a soft blush-pink-to-white pastel gradient' 'Unwrap gifts' 'Clear its line before the countdown ends'
  gen $d-4 $d 'a soft mint-to-cream pastel gradient' 'Five power-ups' 'Hammer, bomb, shuffle, rotate and undo'
  gen $d-5 $d 'a deep dusky plum-to-charcoal gradient with soft glow, headline and subline in warm off-white instead of plum' 'Lovely in the dark' 'Full dark mode, same pastel bricks'
done
