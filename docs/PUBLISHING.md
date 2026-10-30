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

- **API key** (most commands): profile `bricks`, key ID `<key ID>`, issuer
  `<issuer ID>`, App Manager role or higher. Check with
  `asc auth status`. The `.p8` lives at `~/.keys/AuthKey_<key ID>.p8` — never commit it.
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

### Status (2026-10-29)

Done — the app record exists and the listing is filled in. Only these remain:

- [ ] **App Review details** (needs Wilson's phone number), step 8
- [ ] **Upload a build** and attach it to 1.5 — see [Every release](#every-release)
- [ ] Submit for review

`asc validate --app 6828698183 --version 1.5 --output table` shows what's still
blocking. Its "what's new is empty" warning is expected: Apple doesn't allow release notes
on an app's first version.

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

8. **App Review details** — *not done yet*: contact name, email and phone for App Review.
   No sign-in is needed, so no demo account.

   ```bash
   asc review details-create --version-id VERSION_ID --contact-first-name Wilson --contact-last-name Lam \
     --contact-email mail@wilsonlam.ca --contact-phone "+1 ..." \
     --notes "Single-player offline puzzle game. No account, no network access, no purchases."
   ```

## Every release

1. Bump `MARKETING_VERSION` (and/or `CURRENT_PROJECT_VERSION`) in Xcode. Every upload
   needs a build number that hasn't been used before for that version.
2. Copy `metadata/version/<old>/` to `metadata/version/<new>/` and add `whatsNew`
   (the `asc-whats-new-writer` skill drafts it from `git log`). `whatsNew` is not allowed
   on the very first version.
3. Build, upload and submit. Always dry-run first:

   ```bash
   asc publish appstore --app 6828698183 --project BRICKS.xcodeproj --scheme BRICKS \
     --version 1.5 --metadata-dir ./metadata/version/1.5 --submit --dry-run --output table
   asc publish appstore --app 6828698183 --project BRICKS.xcodeproj --scheme BRICKS \
     --version 1.5 --metadata-dir ./metadata/version/1.5 --submit --wait --confirm
   ```

   Drop `--submit` to upload for TestFlight only. If archiving fails on signing, open the
   project in Xcode once with the Wilson Lam team selected so automatic signing can
   create the distribution profile (the Apple Distribution certificate on the account is
   `Q4L36FD425`; its private key must be in this Mac's Keychain).
4. `asc validate --app 6828698183 --version 1.5 --output table` before submitting, and
   `asc review status --app 6828698183` afterwards. If something blocks, use the
   `asc-submission-health` skill.

### Things that can fail validation

- **iPad orientations.** The app is portrait-only but targets iPad too
  (`TARGETED_DEVICE_FAMILY = 1,2`). If upload fails with ITMS-90474 (iPad multitasking
  needs all four orientations), either add `INFOPLIST_KEY_UIRequiresFullScreen = YES` or
  make the app iPhone-only (`TARGETED_DEVICE_FAMILY = 1`) and drop the iPad screenshots.
  Decide with the owners; don't change it unilaterally.
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
