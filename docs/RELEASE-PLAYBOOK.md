# Release playbook

How every change to BRICKS! reaches testers, and then the App Store. It's written for
the agent (or person) making the change, and assumes the one-time setup in
[PUBLISHING.md](PUBLISHING.md) is done: accounts, signing, the `asc` login.

```
change committed ──► TestFlight (always, without asking) ──► ask: App Store too?
                                                              ├─ no  → done
                                                              └─ yes → App Store release
```

## The rules

1. **Every app change goes to TestFlight straight away.** Don't ask first. It's the
   last step of the change.
2. **Then always ask whether to publish to the App Store as well.** Agents ask with
   their question tool (in Claude Code, `AskUserQuestion`), using the
   [question below](#2-ask-about-the-app-store), every time, even if the answer was
   no last time. No answer means no.
3. **Never attach a build to an App Store version, or submit one for App Review,
   without a yes for that release.** A yes for one release doesn't carry over to the
   next.
4. **Every platform goes to the App Store together, iOS last.** The in-app update check
   (`BRICKS/UpdateCheck.swift`) compares every platform against the iPhone listing's
   version. If iOS goes live with a version the Mac doesn't have, Mac players are told
   to update to something they can't download.
5. **Keep secrets out of this public repo:** API key and issuer IDs, the `.p8`,
   profiles, and phone numbers.

**What counts as an app change:** anything that changes what's built: `BRICKS/`,
`BRICKSWidget/`, `BRICKS.xcodeproj`, entitlements, asset catalogs. Docs, `metadata/`,
`appstore/` art and screenshots, and review notes don't need a build.

## Before you start

```bash
asc auth status                     # profile "bricks", in the Keychain
asc status --app 6828698183         # what's live, in review and in TestFlight
ls /Applications/Xcode-27.1.0.app   # the Xcode App Store Connect accepts
```

App Store Connect only takes builds from a released Xcode. If 27.1 stops being
accepted, install the new release with `xcodes` and pass `BRICKS_XCODE=/Applications/Xcode-X.app`
to the script.

## 1. TestFlight (every change)

1. **Commit the change.** The script refuses to build uncommitted tracked files, so
   every build matches a commit.

2. **Pick the platforms.** Shared code (most of `BRICKS/`) affects them all: use `all`.
   iPhone-, iPad-, Watch- or widget-only changes need just `ios`; the iOS upload
   carries the Watch app and the widget. When unsure, use `all`.

3. **Write the What to Test notes** to a file outside the repo (testers read them in
   TestFlight; 4000 characters at most). Keep to the format testers know:

   ```text
   TestFlight build 9 (iPhone and iPad). New since build 8: <what changed, in a sentence or two>.

   Please try:
   • <the thing to try, and where it is: Settings › …>
   • <what might break and how to check it>
   Send feedback (with a screenshot) from TestFlight.
   ```

4. **Check the plan, then run it:**

   ```bash
   appstore/tools/testflight.sh --dry-run --notes /tmp/notes.txt all
   appstore/tools/testflight.sh --notes /tmp/notes.txt all
   ```

   The script:
   - stops if Apple has already approved this version on any of those platforms. An
     approved version's build train is closed and App Store Connect refuses even
     TestFlight uploads of it. Rerun with the next version, `--version 1.7` (minor,
     for new features) or `--version 1.6.1` (patch, for fixes). Pick one and say
     which in your report.
   - sets the build number one above every build ever uploaded, in every target;
   - archives each platform (iOS signs automatically; Mac, Apple TV and Vision Pro
     sign manually with the profiles in `appstore/export/*.plist`), checks the archive
     carries the right version, and uploads it;
   - waits for processing, adds the notes, adds the build to **BRICKS Team** (internal)
     and **Friends & Family** (external), and submits it for Beta App Review.

   It takes about 5 minutes per platform plus processing time, so run it in the
   background. Logs and archives are in `build/testflight/<version>-<build>/`.

5. **Commit the version change** and push to the PR branch:

   ```bash
   git commit -am "Build 9 of 1.7 for TestFlight"
   git push origin HEAD && git push fork HEAD
   ```

6. **Report** the version and build, the platforms, and the beta review state
   (`asc status --app 6828698183`).

If a step fails halfway, the script says which platform and step failed. Fix the
cause and finish by hand. Don't rerun the whole script, because it would bump the build
number again. Use `--no-bump` to upload a platform that failed, or the commands in
[Finishing by hand](#finishing-a-testflight-build-by-hand).

## 2. Ask about the App Store

After every TestFlight upload, ask. Agents use the question tool, so the answer is
a button, not a guess:

> **Build 9 (1.7) is in TestFlight for iPhone/iPad, Mac, Apple TV and Vision Pro. Also
> publish 1.7 to the App Store?**
>
> - **TestFlight only.** Keep testing; the App Store stays on 1.6.
> - **Submit to the App Store.** Submit 1.7 on every platform for App Review, then
>   release it everywhere together once Apple approves all of them.

Say in the question what's live now (`asc status`), and anything that makes this build a
risky release (an untested feature, or something only testable on a device).
"TestFlight only" is the default. On "Submit", carry on below.

## 3. App Store release (only after a yes)

`V` is the new version, `PREV` the version live now, `N` the build. Releases need
the build processed (`VALID`) on **every** platform that's live: iOS, Mac, Vision Pro,
and Apple TV once it's approved. If the TestFlight run skipped one, upload it first with
`appstore/tools/testflight.sh --no-bump --notes … mac`.

1. **What's New.** Copy last release's text and add `whatsNew` in every language
   (plain, specific, a few lines; the `asc-whats-new-writer` skill drafts it from
   `git log`). The listing is in English (`en-US`), Simplified Chinese (`zh-Hans`,
   China mainland) and Traditional Chinese (`zh-Hant`, Hong Kong, Macao and Taiwan):

   ```bash
   cp -R metadata/version/PREV metadata/version/V
   for p in mac tv vision; do cp -R metadata/platforms/$p/PREV metadata/platforms/$p/V; done
   # add "whatsNew" to each <locale>.json; update anything else that changed
   asc metadata validate --dir ./metadata --output table
   ```

2. **Create the versions,** copying last release's text and screenshots, held for
   manual release:

   ```bash
   for P in IOS MAC_OS VISION_OS; do
     asc versions create --app 6828698183 --platform $P --version V --copy-metadata-from PREV \
       --exclude-fields whatsNew --release-type MANUAL --copyright "2026 Daniel Haddad" --if-exists skip
   done
   ```

   Apple TV: if its last version never went live (1.6 was rejected), rename that
   version instead of creating one, as 1.5 became 1.6:
   `asc versions update --version-id TV_VERSION_ID --version V --release-type MANUAL`.
   A first version can't have What's New.

3. **Push the text,** every language, after a dry run. The iPhone/iPad text and the
   app info (name, subtitle, privacy text) push straight from `metadata/`:

   ```bash
   asc metadata push --app 6828698183 --version V --platform IOS --dir ./metadata --dry-run --output table
   asc metadata push --app 6828698183 --version V --platform IOS --dir ./metadata
   ```

   `asc metadata` expects one `version/` folder, so each other platform's text is staged
   in that layout first:

   ```bash
   for p in mac:MAC_OS vision:VISION_OS tv:TV_OS; do
     dir=$(mktemp -d); mkdir -p $dir/version/V; cp metadata/platforms/${p%:*}/V/*.json $dir/version/V/
     asc metadata push --app 6828698183 --version V --platform ${p#*:} --dir $dir --dry-run --output table
     asc metadata push --app 6828698183 --version V --platform ${p#*:} --dir $dir
   done
   ```

   Read each dry run: it lists every field it will add or change, per language.

   **Game Center text** in Chinese is in `metadata/gamecenter/<locale>.json` (achievement
   names match the in-game ones in `BRICKS/Localizable.xcstrings`). Add it to any
   achievement, leaderboard, challenge or activity that doesn't have it yet:

   ```bash
   swiftc -O -parse-as-library BRICKS/Achievements.swift appstore/tools/gamecenter.swift -o /tmp/gamecenter
   /tmp/gamecenter render appstore/gamecenter && /tmp/gamecenter catalog > /tmp/catalog.json
   for l in zh-Hans zh-Hant; do python3 appstore/tools/gamecenter-localize.py /tmp/catalog.json $l; done          # dry run
   for l in zh-Hans zh-Hant; do python3 appstore/tools/gamecenter-localize.py /tmp/catalog.json $l --apply; done
   ```

   **Screenshots:** a language without its own screenshots shows the English ones. To
   make Chinese ones, capture with `-AppleLanguages "(zh-Hans)"` and upload them to that
   version localization with `asc screenshots upload --locale zh-Hans` (PUBLISHING.md,
   Rebuilding the screenshots).

4. **App Review notes.** Each version needs App Review Information. Check it, and
   bring the notes up to date if the change affects anything they describe (features,
   services the app talks to, background modes):

   ```bash
   asc review details-for-version --version-id VERSION_ID
   asc review details-update --id DETAIL_ID --notes "$(cat metadata/review-notes/ios.txt)"
   ```

   If a version has none, create it with `asc review details-create`; copy the contact
   details from the previous version's details, not from this repo.

5. **Attach the build and validate,** for each platform:

   ```bash
   asc versions attach-build --app 6828698183 --version V --platform IOS --build-number N
   asc validate --app 6828698183 --version V --platform IOS --output table
   ```

   New Game Center achievements, leaderboards, challenges or activities must ride on
   the iOS submission (see [PUBLISHING.md](PUBLISHING.md), Game Center).

6. **Submit,** for each platform, after a dry run:

   ```bash
   asc review submit --app 6828698183 --version V --platform IOS --build-number N --dry-run --output table
   asc review submit --app 6828698183 --version V --platform IOS --build-number N --confirm
   ```

7. **Watch review:** `asc status --app 6828698183`, `asc review status --app 6828698183`.
   If Apple rejects a platform or asks for information, read the message with
   `asc web review show --app 6828698183`. That needs the web session, which Wilson
   signs in to in Terminal.app (see PUBLISHING.md, Authentication). Fix it and resubmit;
   the `asc-submission-health` skill covers this.

8. **Release together.** Once every submitted platform is `PENDING_DEVELOPER_RELEASE`,
   release Mac, Vision Pro and Apple TV, then iOS last:

   ```bash
   asc versions list --app 6828698183 --version V --output table
   asc versions release --version-id VERSION_ID --confirm
   ```

   If one platform is stuck in review, hold the rest. Releasing iOS ahead of a live
   platform prompts that platform's players for an update they can't get (rule 4).

9. **Commit** the metadata (`Submit V to the App Store`) and report what's in review.

### Listing-only changes

Promotional text can change any time, with no review:
`asc localizations update --app 6828698183 --version PREV --platform IOS --locale en-US --promotional-text "…"`.
Description, keywords, screenshots and What's New only change with a new version, so
they wait for the next release. Ask before changing anything on the public listing.

## Finishing a TestFlight build by hand

When the script stops after the upload, finish the rest for each platform (`P` is
`IOS`, `MAC_OS`, `TV_OS` or `VISION_OS`):

```bash
asc builds wait --app 6828698183 --build-number N --platform P --version V --fail-on-invalid --timeout 60m
asc builds test-notes create --build-id BUILD_ID --locale en-US --whats-new "$(cat /tmp/notes.txt)"
asc builds add-groups --build-id BUILD_ID --group 999cd162-98ca-47d5-afa4-4ae14abc12e8,3dabaa3b-22c2-4ce6-b1ee-2f6046878f6a
asc testflight review submit --build-id BUILD_ID --confirm
```

The groups are BRICKS Team (internal, no review) and Friends & Family (external,
public link `https://testflight.apple.com/join/BG2FsjtA`, needs Beta App Review).
TestFlight builds expire after 90 days.

## When things go wrong

| Symptom | Cause and fix |
|---|---|
| "Unsupported SDK or Xcode version" | Archived with a newer Xcode than App Store Connect accepts. Use the release (`BRICKS_XCODE`). |
| ITMS-90062 / "train … is closed" | The version is already approved. Rerun with `--version` (the script checks for this first). |
| "Cloud signing permission error" | Export tried automatic signing; the export plists must stay `signingStyle = manual`. |
| A profile is `INVALID` in `asc profiles list` | A capability changed. Regenerate and install it, and put the new UUID in `appstore/export/<platform>.plist` (PUBLISHING.md, Signing). |
| Build stuck in processing over an hour | Check `asc builds list --app 6828698183 --platform P`; an `INVALID` build has an email from Apple saying why. |
| App Review "Information Needed" (Guideline 2.1) | Update `metadata/review-notes/<platform>.txt` and the version's notes; attach a device screen recording if asked. |
