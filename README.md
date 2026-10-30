# BRICKS!

A pastel take on **1010!** for every Apple platform — iPhone (including iPhone Duo), iPad,
Mac, Apple TV, Apple Vision Pro and Apple Watch. SwiftUI, no dependencies.

## Running it

```bash
open BRICKS.xcodeproj
```

Pick the **BRICKS** scheme and a destination (an iPhone, iPad, *My Mac*, Apple TV or
Apple Vision Pro simulator or device), or the **BRICKS Watch** scheme for Apple Watch, and
hit ⌘R.

To run it on your own iPhone you need to set a signing team: select the **BRICKS**
target → **Signing & Capabilities** → tick *Automatically manage signing* → choose your
team. A free Apple ID works; no paid developer account needed. You will probably also
want to change the bundle identifier from `ca.wilsonlam.bricks` to something of your
own, since bundle ids have to be unique.

Publishing to the App Store is covered in [docs/PUBLISHING.md](docs/PUBLISHING.md).

With a free Apple ID the app stops launching after 7 days — plug in and hit ⌘R again to
re-sign it. Your saved game and high score survive that, since re-installing over the top
keeps the app's data.

Requires Xcode 27.1 or later (the iOS 27.1 SDK is what gives the iPhone Duo's inner
display the whole screen). Minimums: iOS 16.6, macOS 13, tvOS 17, visionOS 1, watchOS 10.

The home-screen icon is `AppCover.png`, flattened and resized to a 1024×1024 opaque PNG
at `BRICKS/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. To swap it, replace that
file with another 1024×1024 PNG that has no alpha channel.

## The game

- 10×10 board, three pieces in the tray at a time. Drag a piece onto the board; the
  tray refills only once all three are used.
- **A deal always contains at least one piece you can place.** One or two of the three
  may not fit, but never all three — being handed a dead hand is never what ends a game.
  You can still get stuck after placing one or two of them.
- The full 1010! piece set, same sizes: 1×1, bars of 2–5 in both orientations, 2×2 and
  3×3 squares, the 3-cell corner and the 5-cell corner, each in four rotations —
  19 shapes falling into 9 families.
- Colour is a property of the family, not the individual piece: every five-bar is the
  same colour as every other five-bar, upright or on its side. `Shape.family` derives
  this from the footprint, and `Theme.familyPalette` maps the nine families onto nine
  pastels, ordered so pieces that are easy to confuse by silhouette get clearly
  different hues.
- **New** asks for confirmation before throwing away the board.
- The app version is stamped under the board's bottom-left corner, read from the bundle,
  so bumping Marketing Version in Xcode updates it.
- Filling a row or column clears it. Scoring is 1 point per brick placed, plus 1 per
  cleared cell — counted as a union, so a row and column crossing is 19, not 20.
- **Clearing more than one line with a single piece pays 1.5x the cells it clears**,
  rounded to the nearest point. The multiplier is flat whether it is 2 lines or 5, it
  applies to the cleared cells rather than the piece you placed, and it applies to that
  clear alone — the next one starts from scratch. There is no streak between turns.
- A dragged piece sits right under your finger (or pointer, or pinch), exactly where it
  will land, and the rows or columns a placement would complete are highlighted before
  you let go.
- Every tray slot has the same grab area — the footprint of the largest piece — so a 1x1
  is no harder to pick up than a 3x3.

## Platforms

The rules, pieces, scoring and saving are shared; what differs is how a piece gets onto
the board and how the screen is laid out. Those decisions live in `Platform.swift`.

| | Controls | Layout |
|---|---|---|
| iPhone | drag, piece right under your finger | tall, portrait-only |
| iPhone Duo | drag | outer display: tall, with the power-ups folded into the trailing system column; inner display: tall or wide by orientation |
| iPad | drag, piece right under your finger | tall or wide, every orientation, resizable windows |
| Mac | mouse drag, piece right under the pointer; ⌘N new game, ⌘Z undo, ⌘, settings | wide, resizable window |
| Vision Pro | look and pinch to drag, piece right under the pinch | wide window |
| Apple TV | press a piece, move it with the remote, press to place, Menu to cancel; hammer and bomb aim the same way | wide, text and chrome scaled ×1.6 |
| Apple Watch | tap a piece, tap the board to aim it, tap the outline to place | board and tray side by side, one screen |

`GameView` picks its layout from the space it is given, never from the device: taller
than wide stacks header, board, tray and power-ups; wider than tall puts the board on the
left with the tray stacked in a column beside it and the power-ups underneath. Apple
Watch has its own `WatchGameView`.

On the iPhone Duo's outer display the clock and camera sit in a column down the right
side. When a column like that is present and the stacked layout is short of height,
`PowerUpRail` folds the power-ups into it as a single button: it stays folded so a
stray tap can't fire anything, fans the chips out when pressed, and folds again after
one is used. Everywhere else the power-ups stay in a bar.

Haptics play on iPhone and Apple Watch only; Settings shows only what the device can use
(no Vibrations without haptics hardware, no Dark mode on the always-dark Watch).

## Widget

On iPhone and iPad, a small and a medium widget show the game in progress — the board in
miniature, drawn with the game's bricks — with the score and best. In iOS 27 the small
one also appears in CarPlay and StandBy. (CarPlay doesn't allow games, so the widget is
how BRICKS! gets there.)

After every save the app writes a `WidgetSnapshot` into the `group.ca.wilsonlam.bricks`
App Group, which the widget extension (`BRICKSWidget/`) reads, and asks it to redraw.
Settings has a **Widget** switch: off clears what was shared and the widget shows a note
instead of the game; on shares the current game straight away. `-widgetPreview` (DEBUG)
shows both sizes in the app.

## Settings

The gear in the top right opens a sheet with:

- **Dark mode** — every surface colour in `Theme` is declared with a light and a dark
  value via `Color.adaptive`, resolved from the view's trait collection. The root view
  drives that from the setting, so the whole tree flips without any call site knowing
  about it. The pastel bricks keep the same colours in both modes.
- **Vibrations** — gates every call in `Haptics`. Hidden on devices without haptics
  hardware (iPad, Mac).
- **Reset game** — asks for confirmation first.

Both preferences are stored in `UserDefaults` and survive quitting. The score sits
centred directly above the board.

## Saving

The run in progress — board, tray, score, power-ups and pending gift — is written to
`UserDefaults` (`bricks.savedGame`) after every move and every power-up, and reloaded on
launch. Quitting the app, a reboot, or a lapsed development signature all resume exactly
where you left off. Your best score is kept separately under `bricks.bestScore`.

Both live in the app's data container, so they survive re-installing over the top from
Xcode. Deleting the app from the phone is what clears them. **New** starts a fresh run
and discards the saved one.

## Milestones

Every 1000 points the background switches to one of seven pastel gradients — blush,
coral, teal, aqua, mint, yellow or lilac — picked at random, never the same one twice
running. Each runs from its colour at the top to the same near-white foot, which keeps
the tray readable whatever is happening above it. It then fades back to the normal background over the next 200 points scored,
measured from the score it actually fired at. The choice is saved with the run.

## Gifts

Roughly every 300 points a gift appears on an **unclaimed** square, showing a countdown
that starts at 10. Build over it, then clear that gift's row or column before the
counter runs out — the gift is collected and pays out one random power-up. Every piece
you place ticks every gift down by one; the badge turns red at 3 and the gift is gone
after its tenth move. Bombing or hammering the brick on top of a gift uncovers it again
rather than destroying it. If every power-up is already at its cap, a claimed gift pays
100 bonus points instead.

## Power-ups

Stored along the bottom, **max 5 of each**.

| | | |
|---|---|---|
| **Hammer** | smash a single brick | tap the chip, then tap a brick |
| **Bomb** | clear a 3×3 area | tap the chip, then tap the board |
| **Shuffle** | deal three new tray pieces | instant |
| **Rotate** | turn **all three** tray pieces 90° | tap the chip, then tap the tray — tap again for another quarter turn |
| **Undo** | rewind the last placement | instant |

Tapping an armed chip again — or tapping empty space — cancels it.

One Rotate charge buys a whole session: every tap turns the whole tray another quarter
turn, and the charge is spent on the first turn rather than on arming — so arming and
changing your mind is free. Dragging a piece ends the session and finishes that use.

**Power-ups carry over between games.** When you run out of moves the game is over —
they cannot be spent to dig out of a lost board — but whatever you were holding is
waiting for you in the next one. Starting a new game keeps them and resets everything
else.

## Game Center

BRICKS! shows up in the Games app with:

- **52 achievements** worth 960 of Game Center's 1,000 points: score in a game (100 up to
  25,000), lines ever and in one game, clearing 2–5 lines with one piece, a row and a column
  at once, an empty board, a clear from a nearly full board, clearing streaks, pieces placed,
  every kind of piece in one game, games played, days played, gifts (including two at once
  and holding five of everything), each power-up, all five in one game, a nine-brick bomb,
  2,500 without power-ups, every celebration colour, and playing on each kind of device.
  Five are hidden until earned. Progress shows as it builds (Tidy at 4% after two lines).
- **6 leaderboards**: High Score, Today's Best and This Week (they start over daily and
  weekly), Most Lines in a Game, Biggest Move (points from one piece) and Lifetime Lines.
- **2 challenges** players send friends from the Games app: Beat My Score and Line Showdown.
- **An activity**, Classic Game, that the Games app's Play button starts; a game in
  progress shows as that activity.

In the game, a trophy button beside Settings opens Game Center once you're signed in. The
game-over card lists the achievements that game earned and links to the leaderboards,
achievements and challenges. Game Center shows its own banner the moment one's earned.

Signed out, nothing is lost: stats are kept on the device and reported when you sign in,
and an existing best score counts towards the score achievements. Apple Watch reports
progress too but has no Game Center screens.

`BRICKS/Achievements.swift` is the whole catalog and the rules for earning it, in plain
Swift the headless tests check. `appstore/tools/gamecenter.swift` draws each badge from it
(the game's brick and a symbol on the brick's colour) and prints the catalog;
`appstore/tools/gamecenter-setup.py` creates it all in App Store Connect and only fills in
what's missing on a second run. App Store Connect never lets an id be reused, even after
deleting it, so ids in the catalog are permanent. Ids use letters, digits, underscores and
periods only.

## Source

| File | |
|---|---|
| `Piece.swift` | the 19 shapes and rotation |
| `GameModel.swift` | board, scoring, clears, gifts, power-ups, game over |
| `DragTargeting.swift` | pure finger-position → board-cell geometry |
| `PlacementCursor.swift` | pure board cursor for Apple TV's remote and Apple Watch's taps |
| `Platform.swift` | how each platform plays: input, lift, scale, settings |
| `Theme.swift` | pastel palette and the brick |
| `GameView.swift` | layout, drag and remote controls, menu commands |
| `WatchGameView.swift` | Apple Watch's one-screen layout and tap controls |
| `FocusLiftStyle.swift` | the focus lift for Apple TV's remote and keyboards |
| `Achievements.swift` / `GameCenter.swift` | Game Center's catalog and rules; signing in, reporting, its screens |
| `UpdateCheck.swift` / `AppVersion.swift` | App Store copies must be the latest version (below) |
| `WidgetSnapshot.swift` / `WidgetViews.swift` | what the widget shows, and how; `BRICKSWidget/` is the extension |
| `BoardView.swift` / `TrayView.swift` / `PowerUpBar.swift` / `GameOverView.swift` | UI |

### Required updates

A copy downloaded from the App Store can't be played once the store has a newer version:
on launch and on coming back to the foreground (at most hourly) it asks the public
iTunes lookup API for the live version, and if the installed one is older, an "Update"
screen covers the game and opens the App Store page (Apple TV and Apple Watch can't open
the store from an app, so there it says where to go). The game is saved underneath.

- Only App Store downloads check (`AppTransaction.environment == .production`);
  TestFlight, Xcode and DEBUG builds never do.
- A new version is enforced 24 hours after release, once every storefront can download
  it. Until then players can keep going.
- Anything that fails (offline, the lookup is down, the app isn't in the player's
  storefront) lets the player in.
- The lookup reports one version for the whole app, so release every platform's version
  together, or Mac, Apple TV and Vision Pro players will be told to update to a version
  they can't get yet.

### Dev affordances (DEBUG only)

On the Mac, give every flag a value (`-demo YES`, not `-demo`): AppKit pairs each `-key`
with the word after it, and a leftover word is taken as a file to open, so the app
launches without a window.

`-updateRequired` shows the update screen. `-gameOver` shows the game-over card with some achievements earned, and `-gameCenterPreview` shows the Game Center buttons without signing in (`-noGameCenter`, which the UI tests use, skips Game Center entirely). `-celebrate <0-6>` seeds that board mid-celebration on the given background, for
checking each one without playing to a milestone. `-settings` opens the settings sheet
on launch. `-demo` seeds a representative board — bricks, both gift states,
assorted power-up counts — for inspecting the UI without playing. To check the wide
layout, rotate the iPad simulator with Device › Rotate Left (iPadOS 26 windowing refuses
programmatic rotation, so a launch argument can't do it). `GameModel` also
exposes `testSet*` seams used by the headless rule tests:

```bash
swiftc -D DEBUG -o /tmp/rules_test \
  BRICKS/Platform.swift BRICKS/Piece.swift BRICKS/PowerUp.swift BRICKS/Theme.swift \
  BRICKS/GameModel.swift BRICKS/DragTargeting.swift BRICKS/PlacementCursor.swift \
  BRICKS/AppVersion.swift BRICKS/Achievements.swift tests/main.swift && /tmp/rules_test
```

`UITests/BRICKSUITests.swift` plays a real move on each platform with its own controls —
Siri Remote presses on Apple TV, taps on Apple Watch, a mouse drag on the Mac, a finger
drag on iPhone and iPad — plus the Duo's folding power-up rail:

```bash
xcodebuild test -project BRICKS.xcodeproj -scheme BRICKS -destination 'platform=macOS'
xcodebuild test -project BRICKS.xcodeproj -scheme BRICKS -destination 'platform=tvOS Simulator,name=Apple TV 4K (4th generation)'
xcodebuild test -project BRICKS.xcodeproj -scheme BRICKS -destination 'platform=iOS Simulator,name=iPhone Duo'
xcodebuild test -project BRICKS.xcodeproj -scheme 'BRICKS Watch' -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)'
```

The Apple TV and Vision Pro layered icons and the Mac and Watch icon sizes are drawn
from the game's own bricks by `appstore/tools/render-icons.swift`.
