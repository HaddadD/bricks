#!/bin/bash
# Ships the committed code to TestFlight: bumps the build number, archives and uploads
# each platform, then adds the "What to Test" notes, adds the build to both groups and
# submits it for beta review. It never touches an App Store version.
# The whole routine is in docs/RELEASE-PLAYBOOK.md.
#
#   appstore/tools/testflight.sh --notes notes.txt ios            # the usual run
#   appstore/tools/testflight.sh --notes notes.txt all            # iOS, Mac, Apple TV, Vision Pro
#   appstore/tools/testflight.sh --version 1.7 --notes notes.txt all
#   appstore/tools/testflight.sh --dry-run all                    # check and plan, change nothing
#
# Platforms: ios (also carries the Watch app and the widget), mac, tvos, vision, or all.
#
# Options:
#   --notes FILE      What to Test notes (required unless --upload-only or --archive-only)
#   --version X.Y     set MARKETING_VERSION first (needed once a version is approved)
#   --no-bump         keep the current build number (e.g. to add a platform to a build)
#   --upload-only     upload, but leave notes, groups and beta review alone
#   --archive-only    archive and check the archives; no upload (implies --no-bump)
#   --allow-dirty     build even though tracked files have uncommitted changes
#   --dry-run         run every check and print the plan; change nothing
#
# Needs: Xcode 27.1 (the newest Xcode App Store Connect accepts; override with
# BRICKS_XCODE=/Applications/Xcode-X.app), asc signed in with an API key whose .p8 is in
# ~/.keys/, and the distribution certificate and profiles from docs/PUBLISHING.md#signing.
# Archives and logs go to build/testflight/<version>-<build>/.
set -euo pipefail

APP_ID=6828698183
TEAM_ID=76C669ZZ43
BETA_GROUPS="999cd162-98ca-47d5-afa4-4ae14abc12e8,3dabaa3b-22c2-4ce6-b1ee-2f6046878f6a" # BRICKS Team, Friends & Family
XCODE=${BRICKS_XCODE:-/Applications/Xcode-27.1.0.app}

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PBX="$ROOT/BRICKS.xcodeproj/project.pbxproj"
OUT="$ROOT/build/testflight"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }
say() { echo "==> $*"; }

NOTES="" NEW_VERSION="" BUMP=1 UPLOAD=1 DISTRIBUTE=1 DIRTY_OK=0 DRY=0 PLATFORMS=""
while [ $# -gt 0 ]; do
  case $1 in
    --notes) NOTES=${2:?--notes needs a file}; shift ;;
    --version) NEW_VERSION=${2:?--version needs X.Y}; shift ;;
    --no-bump) BUMP=0 ;;
    --upload-only) DISTRIBUTE=0 ;;
    --archive-only) UPLOAD=0 DISTRIBUTE=0 BUMP=0 ;;
    --allow-dirty) DIRTY_OK=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    all) PLATFORMS="ios mac tvos vision" ;;
    ios|mac|tvos|vision) PLATFORMS="$PLATFORMS $1" ;;
    *) die "unknown argument '$1' (see --help)" ;;
  esac
  shift
done
[ -n "$PLATFORMS" ] || die "name at least one platform: ios, mac, tvos, vision or all"
PLATFORMS=$(echo $PLATFORMS | tr ' ' '\n' | awk '!seen[$0]++' | tr '\n' ' ')

asc_platform() {
  case $1 in ios) echo IOS ;; mac) echo MAC_OS ;; tvos) echo TV_OS ;; vision) echo VISION_OS ;; esac
}
destination() {
  case $1 in ios) echo generic/platform=iOS ;; mac) echo generic/platform=macOS ;;
             tvos) echo generic/platform=tvOS ;; vision) echo generic/platform=visionOS ;; esac
}
# The app's profile UUID, read from the export options so there's one place to change it.
profile_uuid() {
  python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["provisioningProfiles"]["ca.wilsonlam.bricks"])' \
    "appstore/export/$1.plist"
}

# --- Checks ------------------------------------------------------------------------

[ -d "$XCODE" ] || die "no $XCODE. Install the Xcode release App Store Connect accepts (xcodes install 27.1) or set BRICKS_XCODE."
export DEVELOPER_DIR="$XCODE/Contents/Developer"

if [ $UPLOAD = 1 ] && [ $DISTRIBUTE = 1 ] && { [ $DRY = 0 ] || [ -n "$NOTES" ]; }; then
  [ -n "$NOTES" ] || die "--notes FILE is required: testers see it as What to Test"
  [ -s "$NOTES" ] || die "notes file '$NOTES' is missing or empty"
  [ "$(wc -c < "$NOTES")" -le 4000 ] || die "What to Test notes must be 4000 characters or fewer"
fi

if [ $DIRTY_OK = 0 ] && ! git diff --quiet HEAD -- . ; then
  msg="tracked files have uncommitted changes; commit first so the build matches a commit (or --allow-dirty)"
  if [ $DRY = 1 ]; then echo "warning: $msg" >&2; else die "$msg"; fi
fi

# xcodebuild signs and uploads with the same API key asc uses (the default profile in
# the Keychain); its .p8 is ~/.keys/AuthKey_<key id>.p8. Kept out of the repo and the output.
ASC_KEY_ID=$(asc auth status 2>/dev/null | python3 -c '
import json, sys
print(next(c["keyId"] for c in json.load(sys.stdin)["credentials"] if c.get("isDefault")))' 2>/dev/null) \
  || die "no default asc profile (asc auth status; asc auth login)"
ASC_ISSUER_ID=$(asc auth issuer-id 2>/dev/null) || die "asc auth issuer-id failed"
ASC_KEY_PATH=${BRICKS_ASC_KEY_PATH:-$HOME/.keys/AuthKey_$ASC_KEY_ID.p8}
[ -f "$ASC_KEY_PATH" ] || die "the API key's .p8 isn't at ~/.keys/AuthKey_<key id>.p8 (or set BRICKS_ASC_KEY_PATH)"
KEY=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

for p in $PLATFORMS; do
  [ $p = ios ] && continue  # iOS signs automatically at archive time
  u=$(profile_uuid $p) found=0
  for f in ~/Library/MobileDevice/Provisioning\ Profiles/"$u".* ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/"$u".*; do
    [ -e "$f" ] && found=1
  done
  [ $found = 1 ] || die "$p profile $u isn't installed (asc profiles local install --path ~/.keys/signing/...)"
done

# Every target shares one marketing version and one build number.
values() { grep -E "^[[:space:]]*$1 = " "$PBX" | sed -E "s/.*= \"?([^\";]*)\"?;/\1/" | sort -u; }
VERSION=$(values MARKETING_VERSION)
BUILD=$(values CURRENT_PROJECT_VERSION)
[ "$(echo "$VERSION" | wc -l)" -eq 1 ] || die "targets disagree on MARKETING_VERSION: $(echo $VERSION)"
[ "$(echo "$BUILD" | wc -l)" -eq 1 ] || die "targets disagree on CURRENT_PROJECT_VERSION: $(echo $BUILD)"
TARGET_VERSION=${NEW_VERSION:-$VERSION}
[[ $TARGET_VERSION =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "version '$TARGET_VERSION' should look like 1.7 or 1.7.1"

# A version's build train closes once Apple approves it: App Store Connect turns away
# any later upload with that version string (or a lower one), TestFlight included.
if [ $UPLOAD = 1 ]; then
  say "Checking App Store Connect for an approved $TARGET_VERSION or later"
  versions=$(asc versions list --app $APP_ID --paginate --output json) || die "asc versions list failed (asc auth status)"
  check=$(cat <<'EOF'
import json, sys
target, platforms = sys.argv[1], sys.argv[2:]
names = {"ios": "IOS", "mac": "MAC_OS", "tvos": "TV_OS", "vision": "VISION_OS"}
OPEN = {"PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "IN_REVIEW", "REJECTED",
        "DEVELOPER_REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
key = lambda v: tuple(int(x) for x in v.split("."))
closed = []
for v in json.load(sys.stdin)["data"]:
    a = v["attributes"]
    state = a.get("appVersionState") or a.get("appStoreState")
    if a["platform"] in {names[p] for p in platforms} and state not in OPEN \
            and key(a["versionString"]) >= key(target):
        closed.append(f'{a["platform"]} {a["versionString"]} is {state}')
if closed:
    print("error: " + "; ".join(closed) + f". Uploads of {target} would be refused.", file=sys.stderr)
    print("Pick the next version and rerun with --version (patch for fixes, minor for features).", file=sys.stderr)
    sys.exit(1)
print(f"    {target} is open on every platform being uploaded")
EOF
)
  echo "$versions" | python3 -c "$check" "$TARGET_VERSION" $PLATFORMS || exit 1
fi

# Build numbers only have to be unique per version and platform, but one number that
# only goes up is easier to talk about ("build 9"), so the next is above every upload.
if [ $BUMP = 1 ]; then
  REMOTE=$(asc builds list --app $APP_ID --limit 200 --sort -uploadedDate --output json |
    python3 -c 'import json,sys; print(max([int(b["attributes"]["version"]) for b in json.load(sys.stdin)["data"]] or [0]))')
  NEXT=$(( (BUILD > REMOTE ? BUILD : REMOTE) + 1 ))
else
  NEXT=$BUILD
fi

say "Plan: BRICKS! $TARGET_VERSION ($NEXT) for:$(for p in $PLATFORMS; do printf ' %s' "$(asc_platform $p)"; done)"
[ "$TARGET_VERSION" != "$VERSION" ] && echo "    MARKETING_VERSION $VERSION -> $TARGET_VERSION"
[ "$NEXT" != "$BUILD" ] && echo "    CURRENT_PROJECT_VERSION $BUILD -> $NEXT"
if [ $UPLOAD = 0 ]; then echo "    archive only, no upload"
elif [ $DISTRIBUTE = 0 ]; then echo "    upload only; no notes, groups or beta review"
else echo "    then: What to Test notes${NOTES:+ from $NOTES}, groups BRICKS Team + Friends & Family, beta review"; fi
[ $DRY = 1 ] && { say "Dry run: nothing changed"; exit 0; }

# --- Version and build number ------------------------------------------------------

set_all() { # setting old new
  local old=${2//./\\.} n
  n=$(grep -cE "^[[:space:]]*$1 = \"?$old\"?;" "$PBX" || true)
  sed -i '' -E "s/^([[:space:]]*$1 = )\"?$old\"?;/\1$3;/" "$PBX"
  [ "$(grep -cE "^[[:space:]]*$1 = ${3//./\\.};" "$PBX" || true)" -eq "$n" ] || die "couldn't set every $1 to $3"
  echo "    $1 = $3 in $n build configurations"
}
show_errors() { # log
  grep -E "error:|Error Domain|ERROR" "$1" | sort -u | head -10 >&2 || true
  grep -qE "error:|Error Domain|ERROR" "$1" || tail -20 "$1" >&2
}
[ "$TARGET_VERSION" != "$VERSION" ] && set_all MARKETING_VERSION "$VERSION" "$TARGET_VERSION"
[ "$NEXT" != "$BUILD" ] && set_all CURRENT_PROJECT_VERSION "$BUILD" "$NEXT"

# --- Archive and upload -------------------------------------------------------------

RUN="$OUT/$TARGET_VERSION-$NEXT"
mkdir -p "$RUN"
FAILED=""

for p in $PLATFORMS; do
  P=$(asc_platform $p)
  say "$P: archiving (log: $RUN/$p-archive.log)"
  if [ $p = ios ]; then
    signing=(-allowProvisioningUpdates "${KEY[@]}")
  else # The API key can't use cloud-managed certificates, so these sign manually.
    signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" DEVELOPMENT_TEAM=$TEAM_ID
             PROVISIONING_PROFILE_SPECIFIER="$(profile_uuid $p)")
  fi
  rm -rf "$RUN/$p.xcarchive" "$RUN/$p-export"
  if ! xcodebuild -project BRICKS.xcodeproj -scheme BRICKS -configuration Release \
      -destination "$(destination $p)" -archivePath "$RUN/$p.xcarchive" -derivedDataPath "$OUT/dd-$p" \
      archive "${signing[@]}" > "$RUN/$p-archive.log" 2>&1 || [ ! -d "$RUN/$p.xcarchive" ]; then
    show_errors "$RUN/$p-archive.log"
    FAILED="$FAILED $P(archive)"; continue
  fi
  app=$(ls -d "$RUN/$p.xcarchive/Products/Applications/"*.app | head -1)
  plist="$app/Info.plist"; [ -f "$plist" ] || plist="$app/Contents/Info.plist"
  got="$(plutil -extract CFBundleShortVersionString raw "$plist") ($(plutil -extract CFBundleVersion raw "$plist"))"
  [ "$got" = "$TARGET_VERSION ($NEXT)" ] || { echo "archive is $got, expected $TARGET_VERSION ($NEXT)" >&2; FAILED="$FAILED $P(version)"; continue; }
  echo "    archived $got"
  [ $UPLOAD = 1 ] || continue

  say "$P: uploading (log: $RUN/$p-upload.log)"
  # appstore/export/*.plist say destination=upload, so exporting is uploading.
  if ! xcodebuild -exportArchive -archivePath "$RUN/$p.xcarchive" -exportOptionsPlist "appstore/export/$p.plist" \
      -exportPath "$RUN/$p-export" "${KEY[@]}" > "$RUN/$p-upload.log" 2>&1; then
    show_errors "$RUN/$p-upload.log"
    FAILED="$FAILED $P(upload)"; continue
  fi
  echo "    uploaded"
done

# --- TestFlight -------------------------------------------------------------------

if [ $DISTRIBUTE = 1 ]; then
  WHATS_NEW=$(cat "$NOTES")
  for p in $PLATFORMS; do
    P=$(asc_platform $p)
    case " $FAILED " in *" $P("*) continue ;; esac
    say "$P: waiting for App Store Connect to process build $NEXT (usually 5-20 minutes)"
    if ! id=$(asc builds wait --app $APP_ID --build-number $NEXT --platform $P --version "$TARGET_VERSION" \
        --fail-on-invalid --timeout 60m --output json | python3 -c 'import json,sys; print(json.load(sys.stdin)["buildId"])'); then
      echo "build $NEXT didn't finish processing; finish its TestFlight steps by hand (docs/RELEASE-PLAYBOOK.md)" >&2
      FAILED="$FAILED $P(processing)"; continue
    fi
    echo "    build $id is VALID"
    asc builds test-notes create --build-id "$id" --locale en-US --whats-new "$WHATS_NEW" --output json > /dev/null \
      && echo "    What to Test notes added" || FAILED="$FAILED $P(notes)"
    asc builds add-groups --build-id "$id" --group "$BETA_GROUPS" --output json > /dev/null \
      && echo "    added to BRICKS Team and Friends & Family" || FAILED="$FAILED $P(groups)"
    # Friends & Family is external, so each build goes through Beta App Review.
    if out=$(asc testflight review submit --build-id "$id" --confirm --output json 2>&1); then
      echo "    submitted for beta review"
    elif echo "$out" | grep -qiE "already|ENTITY_ERROR.*state"; then
      echo "    beta review: already submitted or not needed"
    else
      echo "$out" | tail -3 >&2; FAILED="$FAILED $P(beta-review)"
    fi
  done
fi

if [ -n "$FAILED" ]; then
  say "Finished with problems:$FAILED"
  exit 1
fi
if [ $UPLOAD = 0 ]; then
  say "Done: archives of $TARGET_VERSION ($NEXT) are in $RUN"
else
  say "Done: $TARGET_VERSION ($NEXT). Commit the version change, e.g. \"Build $NEXT of $TARGET_VERSION for TestFlight\"."
fi
