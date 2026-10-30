# Publishing BRICKS! to the App Store

BRICKS! is made by Daniel Haddad and published under **Wilson Lam**'s Apple Developer
account. This is the runbook for getting a build from this repo onto the App Store, written
so an agent (or a person) can pick it up cold.

Everything goes through the [`asc` CLI](https://github.com/rorkai/App-Store-Connect-CLI)
(`brew install asc`). Its agent skills (`asc install-skills`) cover each step in more
depth: `asc-release-flow`, `asc-xcode-build`, `asc-metadata-sync`,
`asc-submission-health`, `asc-testflight-orchestration`.

## Accounts and identifiers

| | |
|---|---|
| Developer account | Wilson Lam, team ID `76C669ZZ43` (Account Holder: mail@wilsonlam.ca) |
| Bundle ID | `ca.wilsonlam.bricks` (registered, ASC id `ARK93CR9HR`) |
| App Store name | `BRICKS! Block Puzzle` (plain `BRICKS!` is taken by another developer) |
| App ID | `6828698183` — https://appstoreconnect.apple.com/apps/6828698183 |
| SKU | `bricks-ios` |
| Version 1.5 ID | `3efad04d-e98c-4e92-a8c5-5292972b60e8` |
| Age rating | 4+ (every questionnaire answer none/false) |
| App Privacy | Data Not Collected (published) |
| Content rights | Does not use third-party content |
| Primary locale | en-US |
| Category | Games, subcategories Puzzle and Casual |
| Price | Free, all territories |
| Copyright | `2026 Daniel Haddad` |
| Support URL | https://www.wilsonlam.ca/bricks/support.html |
| Privacy policy URL | https://www.wilsonlam.ca/bricks/privacy.html |
| Marketing URL | https://www.wilsonlam.ca/bricks/ |

The original `com.danielhaddad.BRICKS` bundle ID is already taken by another team, which is
why the project now uses `ca.wilsonlam.bricks`. The support, privacy and marketing pages
live in the `SuspectOnTheLam/wilsonlam.ca` repo under `bricks/` (GitHub Pages; the apex
domain redirects to `www`).

The project sets `DEVELOPMENT_TEAM = 76C669ZZ43` and
`ITSAppUsesNonExemptEncryption = NO` (the app uses no encryption, so uploads skip the
export-compliance question).

## Authentication

Two separate logins, both stored in the macOS Keychain:

- **API key** (most commands): `asc` profile `bricks`, App Manager role or higher. Check
  with `asc auth status`, which also shows the key ID; the issuer ID is on App Store
  Connect's Integrations page. The `.p8` lives in `~/.keys/` — never commit it, and keep
  key and issuer IDs out of this public repo too.
- **Apple ID web session** (only for things Apple's API can't do: creating the app record
  and the App Privacy declaration). A human has to run this in a real terminal
  (Terminal.app — not Claude Code's `!` prefix, which has no TTY), because it asks for
  the password and a 2FA code:

  ```bash
  asc web auth login --apple-id mail@wilsonlam.ca --provider-id 129695246
  ```

  `129695246` is the Wilson Lam App Store Connect provider. Note that
  `--public-provider-id` is *not* the developer team ID; leave it out. Agents can open the
  window for the human with
  `osascript -e 'tell application "Terminal" to do script "asc web auth login ..."'`.
  Check with `asc web auth status`.

## What's in the repo

| Path | |
|---|---|
| `metadata/app-info/en-US.json` | name, subtitle, privacy policy URL |
| `metadata/version/<version>/en-US.json` | description, keywords, promo text, support and marketing URLs |
| `metadata/privacy.json` | App Privacy declaration: **Data Not Collected** |
| `appstore/screenshots/iphone-6.9/` | 5 screenshots, 1320×2868 (iPhone 6.9″, scales down to every smaller iPhone) |
| `appstore/screenshots/ipad-13/` | 5 screenshots, 2064×2752 (iPad 13″) |
| `appstore/art/` | the generated backdrops the screenshots are built on |
| `appstore/tools/` | the scripts that rebuild the screenshots (below) |

Validate metadata any time with `asc metadata validate --dir ./metadata --output table`.

## First release: one-time setup

### Status (2026-10-30)

**1.5 (build 1) is submitted and waiting for App Review** (submission
`83aa570d-7ca8-4b8c-bee2-918e1dd7cb41`, build `5748387a-06ff-4703-8c41-5552795a3c57`).
Release type is *after approval*, so it goes live as soon as Apple approves it. Check with
`asc review status --app 6828698183`; if it's rejected, read Apple's message with
`asc web review show --app 6828698183` and use the `asc-submission-health` skill.

`asc validate` reports two non-blocking notes, both expected: "what's new is empty"
(Apple doesn't allow release notes on an app's first version) and "App Privacy publish
state unverified" (it is published; the public API just can't see that).

### 1.6: every platform, in TestFlight

1.6 adds Mac (native), Apple TV, Vision Pro, Apple Watch and iPhone Duo support (see the
README's Platforms section). It goes to TestFlight first; 1.5 stays the App Store build.

| TestFlight group | Type | Testers |
|---|---|---|
| BRICKS Team | internal (no review) | mail@wilsonlam.ca |
| Friends & Family | external (needs Beta App Review per version) | two invited testers (see App Store Connect) |

The beta description, feedback email and Beta App Review contact are set in App Store
Connect (`asc testflight app-localizations`, `asc testflight review`).

**Xcode for uploads:** App Store Connect only accepts builds from a released Xcode. When
this was written that was 27.1, while the installed Xcode was a newer 27.2 it rejected
("Unsupported SDK or Xcode version"). Keep the accepted release next to the newer one
(`xcodes install 27.1`) and archive with
`DEVELOPER_DIR=/Applications/Xcode-27.1.0.app/Contents/Developer`.

**Per platform:** iPhone/iPad, Mac, Apple TV and Vision Pro are separate archives and
uploads of the `BRICKS` scheme (`-destination 'generic/platform=iOS'`, `…=macOS`,
`…=tvOS`, `…=visionOS`). The Watch app needs no upload of its own: it's embedded in the
iPhone archive. Each platform also needs its version in App Store Connect before it can
go to the App Store (`asc versions create --platform MAC_OS|TV_OS|VISION_OS`), with its
own screenshots.

The 1.6 versions for Mac, Apple TV and Vision Pro exist (release after approval,
build 3 attached). Their listing text is in `metadata/platforms/<mac|tv|vision>/1.6/`:
the iPhone description with each platform's controls in place of the finger and haptics
lines, plus a Game Center section. `asc metadata` has no per-platform layout, so these
were applied with `asc api PATCH /v1/appStoreVersionLocalizations/<id>`. "What's New"
stays empty, as it's each platform's first version. `asc validate --app 6828698183
--version 1.6 --platform MAC_OS|TV_OS|VISION_OS` now only lacks screenshots.

**CarPlay:** the game itself isn't eligible. Apple only allows navigation, audio, video
(parked), messaging and driving-task apps in CarPlay, each behind an entitlement Apple
grants on request, and TestFlight builds need the same entitlement as App Store ones.
Instead, the BRICKS! widget shows there: iOS 27 puts any app's small widgets in CarPlay.

**Widget:** an app extension (`ca.wilsonlam.bricks.widget`) embedded in the iPhone/iPad
build. It and the app share the `group.ca.wilsonlam.bricks` App Group (App Group ID
`UT3D68C3HW`, created with `asc web app-groups create`); both bundle IDs have the
App Groups capability. Changing an App ID's capabilities invalidates its profiles, so
regenerate them afterwards (`asc profiles list` shows `INVALID`).

**Game Center:** both app IDs (the app and the Watch app) have the Game Center
capability, and the app's Game Center record (detail `d4450439-…`) holds the catalog
from `BRICKS/Achievements.swift`. To add to it, extend the catalog, then:

```bash
swiftc -O -parse-as-library BRICKS/Achievements.swift appstore/tools/gamecenter.swift -o /tmp/gamecenter
/tmp/gamecenter render appstore/gamecenter          # artwork (git-ignored)
/tmp/gamecenter catalog appstore/gamecenter > /tmp/catalog.json
python3 appstore/tools/gamecenter-setup.py /tmp/catalog.json
```

What the API insists on, found the hard way: vendor ids allow only letters, digits,
underscores and periods; recurring leaderboards need `recurrenceDuration` in hours
(`PT24H`, `PT168H`) plus `recurrenceRule` (`FREQ=DAILY;INTERVAL=1` or `…INTERVAL=7`, as
there's no weekly frequency); and `asc`'s `--create-initial-version` fails, so challenge
and activity versions are created separately. TestFlight builds use the Game Center
sandbox, where everything works as soon as it's created. For the App Store, the items go
live with the first version that includes them: in App Store Connect, add them to the
version's Game Center section before submitting.

The Game Center entitlement is restricted, so Mac debug builds leave it out
(`CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` is empty in Debug); without a registered Mac there's
no development profile to carry it. Test Game Center on a Mac through TestFlight.

### What was run (for reference, or to redo on a new app)

`APP_ID` is `6828698183`, `VERSION_ID` is `3efad04d-e98c-4e92-a8c5-5292972b60e8`.

1. **Create the app record** (web session):

   ```bash
   asc web apps create --name "BRICKS! Block Puzzle" --bundle-id ca.wilsonlam.bricks \
     --sku bricks-ios --primary-locale en-US --platform IOS --auto-rename=false
   ```

   `--auto-rename` defaults to **true**, which would quietly use a suffixed name — keep
   it off. The `--version` flag was ignored and the record started at 1.0, so rename it:
   `asc versions update --version-id VERSION_ID --version 1.5`.

2. **Category, price, availability**:

   ```bash
   asc app-setup categories set --app APP_ID --primary GAMES \
     --primary-subcategory-one GAMES_PUZZLE --primary-subcategory-two GAMES_CASUAL
   asc app-setup pricing set --app APP_ID --free --base-territory USA
   asc pricing availability create --app APP_ID --all-territories --available true \
     --available-in-new-territories true
   ```

   On a new app, availability has to be *created*; `asc app-setup availability edit`
   only works once a record exists.

3. **Age rating** — all none/false (no violence, gambling, user content or web access;
   gifts award random power-ups but nothing is bought, so no loot boxes): 4+.
   `asc age-rating edit --app APP_ID --all-none`

4. **App Privacy** (web session): Data Not Collected.

   ```bash
   asc web privacy plan --app APP_ID --file metadata/privacy.json
   asc web privacy apply --app APP_ID --file metadata/privacy.json
   asc web privacy publish --app APP_ID --confirm
   ```

5. **Content rights**:
   `asc apps update --id APP_ID --content-rights DOES_NOT_USE_THIRD_PARTY_CONTENT`

6. **Metadata and copyright**:

   ```bash
   asc metadata push --app APP_ID --version 1.5 --platform IOS --dir ./metadata --dry-run --output table
   asc metadata push --app APP_ID --version 1.5 --platform IOS --dir ./metadata
   asc versions update --version-id VERSION_ID --copyright "2026 Daniel Haddad"
   ```

   Keep keywords free of words already in the name or subtitle (Apple indexes those
   anyway; `asc validate` warns on overlap) and under 100 characters.

7. **Screenshots** (uploaded in file order; `asc screenshots sizes --all` lists the
   display types):

   ```bash
   asc screenshots upload --app APP_ID --version 1.5 --locale en-US \
     --path appstore/screenshots/iphone-6.9 --device-type IPHONE_67
   asc screenshots upload --app APP_ID --version 1.5 --locale en-US \
     --path appstore/screenshots/ipad-13 --device-type IPAD_PRO_3GEN_129
   ```

   Re-uploading a set needs `--replace --confirm`.

8. **App Review details** (contact for App Review; no sign-in, so no demo account):

   ```bash
   asc review details-create --version-id VERSION_ID --contact-first-name Wilson --contact-last-name Lam \
     --contact-email mail@wilsonlam.ca --contact-phone "<Wilson's phone>" --demo-account-required=false \
     --notes "Single-player offline puzzle game. No account, sign-in, network access or purchases. ..."
   ```

## Signing

Builds are signed manually with an Apple Distribution certificate whose private key is
in this Mac's login keychain:

| | |
|---|---|
| Certificate | `Z88Z2MBTWF` "Apple Distribution: Wilson Lam (76C669ZZ43)", expires 2027-10-30 |
| Mac installer | "Mac Installer Distribution" (signs the Mac `.pkg`), made by `create-distribution-cert.sh installer` |
| iPhone/iPad and Vision Pro profile | `75RKJVG2A4` "BRICKS App Store 1.6 GC", UUID `592ebbab-f1ac-4bed-939c-2e672f19db70` |
| Widget profile | `W9B49BQ523` "BRICKS Widget App Store", UUID `11987362-c1dd-461a-a089-3d161405fdb3` |
| Apple Watch profile | `HQJ95L3AY3` "BRICKS Watch App Store GC", UUID `41bbfdb5-1b9f-460e-819c-ffb29f3a35d3` |
| Apple TV profile | `53YXD8GJFL` "BRICKS tvOS App Store GC", UUID `ae27f3f5-ec38-4a92-9422-fcb7cd316ea4` |
| Mac profile | `5R2TY549TF` "BRICKS Mac App Store GC", UUID `775341d2-0e42-43d9-9d33-c31f34ca10bb` |
| Key material | `~/.keys/signing/` (owner-only; never commit) |

Why manual: the API key isn't allowed to use Apple's cloud-managed distribution
certificates ("Cloud signing permission error"), so automatic export fails. The older
distribution certificate `Q4L36FD425` has its private key on another Mac.

On a new Mac, run `appstore/tools/create-distribution-cert.sh` (creates a certificate
and imports it), then create and install a profile for it:

```bash
asc profiles create --name "BRICKS App Store" --profile-type IOS_APP_STORE --bundle ARK93CR9HR --certificate CERT_ID
asc profiles download --id PROFILE_ID --output ~/.keys/signing/BRICKS_AppStore.mobileprovision
asc profiles local install --path ~/.keys/signing/BRICKS_AppStore.mobileprovision
```

and put the new profile UUID in the matching `appstore/export/*.plist`. Profiles expire with
their certificate.

## Every release

1. Bump `MARKETING_VERSION` (and/or `CURRENT_PROJECT_VERSION`) in Xcode. Every upload
   needs a build number that hasn't been used before for that version.
2. Copy `metadata/version/<old>/` to `metadata/version/<new>/` and add `whatsNew`
   (the `asc-whats-new-writer` skill drafts it from `git log`). `whatsNew` is not allowed
   on the very first version.
3. Archive and upload (this is what shipped 1.5; see [Signing](#signing)):

   ```bash
   # ASC_KEY_ID / ASC_ISSUER_ID: see Authentication above.
   KEY=(-authenticationKeyPath ~/.keys/AuthKey_$ASC_KEY_ID.p8 -authenticationKeyID $ASC_KEY_ID
        -authenticationKeyIssuerID $ASC_ISSUER_ID)
   xcodebuild -project BRICKS.xcodeproj -scheme BRICKS -configuration Release \
     -destination 'generic/platform=iOS' -archivePath build/BRICKS.xcarchive archive \
     -allowProvisioningUpdates "${KEY[@]}"
   xcodebuild -exportArchive -archivePath build/BRICKS.xcarchive \
     -exportOptionsPlist appstore/export/ios.plist -exportPath build/export "${KEY[@]}"
   ```

   With `destination = upload` in the export options, the export *is* the upload.
4. Wait for processing, attach the build, check, and submit:

   ```bash
   asc builds wait --app 6828698183 --build-number N --platform IOS --version X.Y --fail-on-invalid
   asc versions attach-build --app 6828698183 --version X.Y --build-number N
   asc validate --app 6828698183 --version X.Y --output table
   asc review submit --app 6828698183 --version X.Y --dry-run --output table
   asc review submit --app 6828698183 --version X.Y --confirm
   asc review status --app 6828698183
   ```

   If something blocks, use the `asc-submission-health` skill.

### Things that can fail validation

- **iPad orientations.** iPad multitasking requires all four orientations (ITMS-90474),
  so the iPad build supports every orientation and resizable windows, with a wide
  side-by-side layout (see the README). iPhone stays portrait-only. Don't fall back on
  `UIRequiresFullScreen`: it's deprecated and ignored in future releases.
- **Mentioning other games.** The README calls the game a take on another title; keep
  that name out of the App Store metadata and keywords (Guideline 2.3.7 / trademarks).

## Rebuilding the screenshots

The screenshots are real simulator captures placed inside generated marketing art. The
model only ever draws the backdrop and a device with a solid green screen; the app UI is
composited in afterwards, pixel for pixel, so it always matches the shipping app.

```bash
appstore/tools/capture.sh        # build for the simulator, capture appstore/raw/*.png
appstore/tools/generate-art.sh   # GPT Image 2 backdrops into appstore/art/ (skips existing)
appstore/tools/compose.sh        # composite and write appstore/screenshots/
```

- `capture.sh` stages each state with the DEBUG launch arguments (`-demo`,
  `-celebrate <n>`) plus `-bricks.darkMode` / `-bricks.bestScore`. The tray is dealt at
  random, so recaptures won't match the committed images exactly.
- `generate-art.sh` uses the `gpt-image-2` skill (Codex CLI on a ChatGPT subscription,
  never the paid API). Codex fails with `model_not_found` if `~/.codex/config.toml` pins a
  model ChatGPT logins can't use; pass a supported one by adding `-m <model>` to the
  `codex exec` call in the skill's `gen.sh` (models listed in
  `~/.codex/models_cache.json`).
- The art is optional: if image generation isn't available, any 1320×2868 / 2064×2752
  backdrop with a solid `#00FF00` screen area works with `compose.sh`.
- Always look at every composed image before uploading.
