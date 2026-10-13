# BRICKS!

A pastel take on **1010!** for iPhone — SwiftUI, iOS 16+, no dependencies.

## Running it

```bash
open BRICKS.xcodeproj
```

Pick a simulator or your iPhone and hit ⌘R.

To run it on your own iPhone you need to set a signing team: select the **BRICKS**
target → **Signing & Capabilities** → tick *Automatically manage signing* → choose your
team. A free Apple ID works; no paid developer account needed. You will probably also
want to change the bundle identifier from `com.danielhaddad.BRICKS` to something of your
own, since bundle ids have to be unique.

With a free Apple ID the app stops launching after 7 days — plug in and hit ⌘R again to
re-sign it. Your saved game and high score survive that, since re-installing over the top
keeps the app's data.

Requires Xcode 26 or later to deploy to an iPhone running iOS 26.

The home-screen icon is `AppCover.png`, flattened and resized to a 1024×1024 opaque PNG
at `BRICKS/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. To swap it, replace that
file with another 1024×1024 PNG that has no alpha channel.

## The game

- 10×10 board, three pieces in the tray at a time. Drag a piece onto the board; the
  tray refills only once all three are used.
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
- A dragged piece floats well above your finger so neither your hand nor the piece hides
  the square it will land on, and the rows or columns a placement would complete are
  highlighted before you let go.
- Every tray slot has the same grab area — the footprint of the largest piece — so a 1x1
  is no harder to pick up than a 3x3.

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

## Source

| File | |
|---|---|
| `Piece.swift` | the 19 shapes and rotation |
| `GameModel.swift` | board, scoring, clears, gifts, power-ups, game over |
| `DragTargeting.swift` | pure finger-position → board-cell geometry |
| `Theme.swift` | pastel palette and the brick |
| `GameView.swift` | layout and the drag gesture |
| `BoardView.swift` / `TrayView.swift` / `PowerUpBar.swift` / `GameOverView.swift` | UI |

### Dev affordances (DEBUG only)

`-celebrate <0-6>` seeds that board mid-celebration on the given background, for
checking each one without playing to a milestone. `-demo` seeds a representative board — bricks, both gift states,
assorted power-up counts — for inspecting the UI without playing. `GameModel` also
exposes `testSet*` seams used by the headless rule tests:

```bash
swiftc -D DEBUG -o /tmp/rules_test \
  BRICKS/Piece.swift BRICKS/PowerUp.swift BRICKS/Theme.swift \
  BRICKS/GameModel.swift BRICKS/DragTargeting.swift tests/main.swift && /tmp/rules_test
```
