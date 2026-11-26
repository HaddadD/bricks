# BRICKS!

SwiftUI block puzzle for iPhone, iPad, Mac, Apple TV, Vision Pro and Apple Watch
(see README.md). Published by Wilson Lam's developer account with the `asc` CLI.

## Shipping changes

Follow [docs/RELEASE-PLAYBOOK.md](docs/RELEASE-PLAYBOOK.md). In short:

- **Every app change goes to TestFlight straight away, without asking:** commit, then
  run `appstore/tools/testflight.sh --notes <file> <platforms>`, commit the build number,
  push, and report.
- **Then always ask the user, with AskUserQuestion, whether to also publish to the App
  Store.** Ask after every TestFlight upload, even if they said no last time. No answer
  means TestFlight only.
- **Never attach a build to an App Store version or submit for App Review without a
  yes for that release.**
- App Store releases move every platform together and release iOS last, because the
  in-app update check compares every platform against the iPhone version.

## Ground rules

- The app is in English, Simplified Chinese (`zh-Hans`) and Traditional Chinese
  (`zh-Hant`). Every new on-screen string needs both translations in
  `BRICKS/Localizable.xcstrings`. A `String` that reaches the screen must be looked up
  (`String(localized:)` or `LocalizedStringKey`); `Text("literal")` is looked up already.
  New App Store text goes in each `metadata/**/<locale>.json`, and new Game Center items
  in `metadata/gamecenter/<locale>.json`.
- The repo is public: keep API key and issuer IDs, `.p8` files, profiles and phone
  numbers out of it.
- `origin` is HaddadD/bricks, Daniel Haddad's repo; SuspectOnTheLam has write access
  (since 2026-11-26). Push working branches to both `origin` and `fork` (SuspectOnTheLam/bricks);
  work reaches `main` by pull request (PR #1 is `app-store-publishing`).
- Archive with the Xcode App Store Connect accepts (27.1, at
  `/Applications/Xcode-27.1.0.app`), not the newest one installed.
- Accounts, signing, Game Center, screenshots and one-time setup:
  [docs/PUBLISHING.md](docs/PUBLISHING.md).
