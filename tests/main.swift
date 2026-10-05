import Foundation
import CoreGraphics

var failures: [String] = []

func check(_ condition: Bool, _ label: String) {
    if condition {
        print("  ok   \(label)")
    } else {
        print("  FAIL \(label)")
        failures.append(label)
    }
}

/// Lets the model's deferred clear/flash animations complete.
func pump(_ seconds: Double = 0.6) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

func bar(_ length: Int, vertical: Bool = false) -> Shape {
    vertical
        ? Shape(grid: Array(repeating: [true], count: length))
        : Shape(grid: [Array(repeating: true, count: length)])
}

func fresh() -> GameModel {
    let m = GameModel()
    m.newGame()          // also discards any run persisted by an earlier check
    for power in PowerUp.allCases { m.testSetPowerUp(power, 0) }  // they now carry over
    m.testSetTray([nil, nil, nil])
    return m
}

// MARK: - Piece set

print("\nPiece set")
check(Shape.all.count == 19, "19 shapes, matching 1010!")
check(Shape.all.map { $0.cellCount }.sorted() == [1, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 5, 5, 5, 5, 5, 5, 9],
      "cell counts: 1x1, bars 2-5, 2x2, 3x3, four 3-cell corners, four 5-cell corners")
check(Shape.all.contains(Shape(grid: Array(repeating: Array(repeating: true, count: 3), count: 3))), "3x3 square present")
check(Shape.all.contains(bar(5)) && Shape.all.contains(bar(5, vertical: true)), "5-bar in both orientations")

let corner = Shape(grid: [[true, true, true], [true, false, false], [true, false, false]])
check(corner.rotated().rotated().rotated().rotated() == corner, "four rotations return the original")
check(Set(Shape.all.map { $0.grid.description }).count == 19, "all 19 shapes are distinct")

// Colour is a property of the piece kind, not of the individual piece.
check(Set(Shape.all.map { $0.family }).count == 9, "the 19 shapes fall into 9 families")
check(bar(5).family == bar(5, vertical: true).family, "a five-bar is one family either way up")
check(bar(2).family == bar(2, vertical: true).family, "so is a two-bar")

var corner3s = Shape(grid: [[true, true, true], [true, false, false], [true, false, false]])
var corner3Families = Set<Int>()
for _ in 0..<4 { corner3Families.insert(corner3s.family); corner3s = corner3s.rotated() }
check(corner3Families.count == 1, "all four rotations of the five-cell corner share a family")

check(Set(Shape.all.map { TrayPiece(shape: $0).colorIndex }).count == 9,
      "the nine families map onto nine distinct colours")
check(Theme.blocks.count >= 9 && Theme.blockShades.count == Theme.blocks.count,
      "the palette has a colour and a shade for each")
check(TrayPiece(shape: bar(3)).colorIndex == TrayPiece(shape: bar(3, vertical: true)).colorIndex,
      "the same size piece is the same colour whichever orientation")
check(TrayPiece(shape: bar(3)).colorIndex != TrayPiece(shape: bar(4)).colorIndex,
      "different sizes are different colours")

// MARK: - Placement and scoring

print("\nPlacement and scoring")
let m1 = fresh()
m1.testSetTray([TrayPiece(shape: bar(5)), nil, nil])
check(m1.place(trayIndex: 0, atRow: 0, col: 0), "5-bar places at 0,0")
check(m1.score == 5, "score = cells placed (got \(m1.score))")
check(!m1.place(trayIndex: 0, atRow: 0, col: 0), "cannot place an already-used slot")

let m2 = fresh()
m2.testSetTray([TrayPiece(shape: bar(5)), TrayPiece(shape: bar(5)), nil])
_ = m2.place(trayIndex: 0, atRow: 0, col: 0)
_ = m2.place(trayIndex: 1, atRow: 0, col: 5)
pump()
check((0..<10).allSatisfy { !m2.testCell(row: 0, col: $0).isFilled }, "completed row clears")
check(m2.score == 20, "10 placed + 10 cleared cells, no line bonus = 20 (got \(m2.score))")

let m3 = fresh()
for r in 0..<9 { m3.testSetCell(row: r, col: 3, colorIndex: 4) }
m3.testSetTray([TrayPiece(shape: bar(1)), nil, nil])
_ = m3.place(trayIndex: 0, atRow: 9, col: 3)
pump()
check((0..<10).allSatisfy { !m3.testCell(row: $0, col: 3).isFilled }, "completed column clears")

// Two lines at once pay exactly their cells — no multi-line bonus.
let m2b = fresh()
for c in 0..<9 { m2b.testSetCell(row: 4, col: c, colorIndex: 2) }   // row 4 needs one cell
for r in 0..<10 where r != 4 { m2b.testSetCell(row: r, col: 9, colorIndex: 2) }  // col 9 too
m2b.testSetScore(0)
m2b.testSetTray([TrayPiece(shape: bar(1)), nil, nil])
_ = m2b.place(trayIndex: 0, atRow: 4, col: 9)
pump()
check(m2b.score == 1 + 19, "a row and column together pay 1 placed + 19 cleared cells (got \(m2b.score))")

// MARK: - Gifts

print("\nGift mechanic")
let m4 = fresh()
m4.testSetCell(row: 0, col: 3, colorIndex: nil, gift: true)
m4.testSetTray([TrayPiece(shape: bar(5)), TrayPiece(shape: bar(5)), nil])
check(m4.canPlace(bar(5), atRow: 0, col: 0), "a gift square is still free to build on")
_ = m4.place(trayIndex: 0, atRow: 0, col: 0)
check(m4.testCell(row: 0, col: 3).isFilled && m4.testCell(row: 0, col: 3).hasGift,
      "gift survives under the brick placed on it")
_ = m4.place(trayIndex: 1, atRow: 0, col: 5)
pump()
check(PowerUp.allCases.reduce(0) { $0 + m4.count(of: $1) } == 1, "clearing the gift's line earns one power-up")

let m5 = fresh()
m5.testSetCell(row: 5, col: 5, colorIndex: nil, gift: true)
m5.testSetTray([TrayPiece(shape: bar(5)), TrayPiece(shape: bar(5)), nil])
_ = m5.place(trayIndex: 0, atRow: 0, col: 0)
_ = m5.place(trayIndex: 1, atRow: 0, col: 5)
pump()
check(PowerUp.allCases.reduce(0) { $0 + m5.count(of: $1) } == 0, "an uncleared gift earns nothing")
check(m5.testCell(row: 5, col: 5).hasGift, "the uncleared gift stays on the board")

let m6 = fresh()
for p in PowerUp.allCases { m6.testSetPowerUp(p, PowerUp.maxPerType) }
m6.testSetCell(row: 0, col: 3, colorIndex: nil, gift: true)
m6.testSetTray([TrayPiece(shape: bar(5)), TrayPiece(shape: bar(5)), nil])
_ = m6.place(trayIndex: 0, atRow: 0, col: 0)
_ = m6.place(trayIndex: 1, atRow: 0, col: 5)
pump()
check(PowerUp.allCases.allSatisfy { m6.count(of: $0) == 5 }, "power-ups cap at 5 each")
check(m6.score == 120, "a gift won at the cap pays 100 bonus instead (got \(m6.score))")

func giftCount(_ m: GameModel) -> Int {
    var n = 0
    for r in 0..<10 { for c in 0..<10 where m.testCell(row: r, col: c).hasGift { n += 1 } }
    return n
}

let m7 = fresh()
m7.testSetTray([TrayPiece(shape: bar(1)), nil, nil])
_ = m7.place(trayIndex: 0, atRow: 9, col: 9)
pump(0.3)
check(giftCount(m7) == 0, "no gift before the first threshold")

m7.testSetScore(400)                       // past any starting threshold (280-320)
m7.testSetTray([TrayPiece(shape: bar(1)), nil, nil])
_ = m7.place(trayIndex: 0, atRow: 9, col: 8)
pump(0.3)
check(giftCount(m7) == 1, "a gift appears once ~300 points is passed (got \(giftCount(m7)))")

m7.testSetScore(500)                       // only ~100 further on: too soon for another
m7.testSetTray([TrayPiece(shape: bar(1)), nil, nil])
_ = m7.place(trayIndex: 0, atRow: 9, col: 7)
pump(0.3)
check(giftCount(m7) == 1, "no second gift after only ~100 more points")

m7.testSetScore(1000)                      // past the next ~300 step
m7.testSetTray([TrayPiece(shape: bar(1)), nil, nil])
_ = m7.place(trayIndex: 0, atRow: 9, col: 6)
pump(0.3)
check(giftCount(m7) == 2, "a second gift appears ~300 points later (got \(giftCount(m7)))")

// MARK: - Power-ups

print("\nPower-ups")
let m8 = fresh()
m8.testSetCell(row: 5, col: 5, colorIndex: 3)
m8.testSetPowerUp(.hammer, 1)
m8.activePower = .hammer
m8.applyTargetedPower(atRow: 5, col: 5)
pump(0.4)
check(!m8.testCell(row: 5, col: 5).isFilled, "hammer smashes one brick")
check(m8.count(of: .hammer) == 0, "hammer is consumed")

let m9 = fresh()
for r in 4...6 { for c in 4...6 { m9.testSetCell(row: r, col: c, colorIndex: 2) } }
m9.testSetCell(row: 4, col: 5, colorIndex: nil, gift: true)
m9.testSetPowerUp(.bomb, 2)
m9.activePower = .bomb
m9.applyTargetedPower(atRow: 5, col: 5)
pump(0.4)
var remaining = 0
for r in 0..<10 { for c in 0..<10 where m9.testCell(row: r, col: c).isFilled { remaining += 1 } }
check(remaining == 0, "bomb clears a 3x3 area (got \(remaining) left)")
check(m9.count(of: .bomb) == 1, "bomb is consumed once")
check(m9.testCell(row: 4, col: 5).hasGift, "a gift under blasted bricks is not destroyed")

let m10 = fresh()
m10.testSetTray([TrayPiece(shape: bar(5)), nil, nil])
_ = m10.place(trayIndex: 0, atRow: 3, col: 0)
pump(0.3)
m10.testSetPowerUp(.undo, 1)
m10.tapPowerUp(.undo)
pump(0.3)
check(m10.score == 0 && !m10.testCell(row: 3, col: 0).isFilled, "undo rewinds the last move")
check(m10.count(of: .undo) == 0, "undo is consumed")

let m11 = fresh()
m11.testSetTray([TrayPiece(shape: bar(5)),
                 TrayPiece(shape: bar(3)),
                 TrayPiece(shape: bar(2))])
m11.testSetPowerUp(.rotate, 2)
m11.tapPowerUp(.rotate)
check(m11.activePower == .rotate, "tapping rotate arms a rotating session")
check(m11.count(of: .rotate) == 2, "arming alone does not spend the charge")

m11.rotateTray()
check(m11.tray[0]?.shape == bar(5, vertical: true)
      && m11.tray[1]?.shape == bar(3, vertical: true)
      && m11.tray[2]?.shape == bar(2, vertical: true),
      "one tap turns all three pieces together")
check(m11.count(of: .rotate) == 1, "the first turn spends one charge")

m11.rotateTray()
m11.rotateTray()
check(m11.tray[0]?.shape == bar(5, vertical: true), "three taps leave the tray a quarter turn on")
check(m11.count(of: .rotate) == 1, "extra taps in the same session are free")
check(m11.activePower == .rotate, "the session stays armed while tapping")

m11.endRotateMode()
check(m11.activePower == nil, "starting a drag ends the session")
m11.rotateTray()
check(m11.tray[0]?.shape == bar(5, vertical: true), "rotating does nothing once the session ended")
check(m11.count(of: .rotate) == 1, "and costs nothing")

// Arming then changing your mind is free.
let m11b = fresh()
m11b.testSetPowerUp(.rotate, 1)
m11b.tapPowerUp(.rotate)
m11b.tapPowerUp(.rotate)
check(m11b.activePower == nil && m11b.count(of: .rotate) == 1,
      "arming and disarming without turning costs nothing")

// A fresh session needs a charge of its own.
let m11c = fresh()
m11c.testSetTray([TrayPiece(shape: bar(3)), nil, nil])
m11c.testSetPowerUp(.rotate, 1)
m11c.tapPowerUp(.rotate)
m11c.rotateTray()
m11c.endRotateMode()
check(m11c.count(of: .rotate) == 0, "the session spent the last charge")
m11c.tapPowerUp(.rotate)
check(m11c.activePower == nil, "with none left, rotate cannot be armed again")

let m12 = fresh()
let before = m12.tray.compactMap { $0?.id }
m12.testSetPowerUp(.shuffle, 1)
m12.tapPowerUp(.shuffle)
check(m12.tray.compactMap { $0?.id } != before && m12.tray.compactMap { $0 }.count == 3, "shuffle deals three new pieces")

let m13 = fresh()
m13.testSetPowerUp(.hammer, 3)
m13.tapPowerUp(.hammer)
check(m13.activePower == .hammer, "tapping hammer arms it")
m13.tapPowerUp(.hammer)
check(m13.activePower == nil, "tapping again disarms it")
m13.testSetPowerUp(.bomb, 0)
m13.tapPowerUp(.bomb)
check(m13.activePower == nil, "an empty power-up cannot be armed")

// MARK: - Game over

print("\nGame over")
let m14 = fresh()
for r in 0..<10 { for c in 0..<10 { m14.testSetCell(row: r, col: c, colorIndex: 0) } }
m14.testSetPowerUp(.shuffle, 1)
m14.tapPowerUp(.shuffle)
pump(0.3)
check(m14.isGameOver, "full board with no fit ends the game")

// A lost game is lost: power-ups cannot be spent to dig out of it.
m14.testSetPowerUp(.bomb, 1)
m14.tapPowerUp(.bomb)
check(m14.activePower == nil, "a power-up cannot be armed once the game is over")
m14.activePower = .bomb                 // even if something forced it through
m14.applyTargetedPower(atRow: 5, col: 5)
pump(0.5)
check(m14.isGameOver, "the board stays lost")
check(m14.count(of: .bomb) == 1, "the unusable power-up is not consumed")

// ...but it carries into the next game.
m14.newGame()
check(!m14.isGameOver && m14.score == 0, "New game starts clean")
check(m14.count(of: .bomb) == 1, "power-ups carry over into the next game")
check(m14.canPlaceAnywhere(bar(1)), "the new board is empty")

// MARK: - Gift expiry

print("\nGift expiry")

let g1 = fresh()
g1.testSetCell(row: 0, col: 0, colorIndex: nil, gift: true)
check(g1.testCell(row: 0, col: 0).giftMovesLeft == 10, "a new gift starts at 10 moves")

// Each placement ticks it down one.
for expected in [9, 8, 7] {
    g1.testSetTray([TrayPiece(shape: bar(1)), nil, nil])
    _ = g1.place(trayIndex: 0, atRow: 9, col: 9 - (9 - expected))
    pump(0.3)
    check(g1.testCell(row: 0, col: 0).giftMovesLeft == expected,
          "after a move the gift reads \(expected) (got \(String(describing: g1.testCell(row: 0, col: 0).giftMovesLeft)))")
}

// Run the remaining moves out and it should vanish.
let g2 = fresh()
g2.testSetCell(row: 0, col: 0, colorIndex: nil, gift: true)
for i in 0..<9 {
    g2.testSetTray([TrayPiece(shape: bar(1)), nil, nil])
    _ = g2.place(trayIndex: 0, atRow: 9, col: i)
    pump(0.25)
}
check(g2.testCell(row: 0, col: 0).giftMovesLeft == 1, "the gift survives nine moves, reading 1")
g2.testSetTray([TrayPiece(shape: bar(1)), nil, nil])
_ = g2.place(trayIndex: 0, atRow: 9, col: 9)
pump(0.25)
check(!g2.testCell(row: 0, col: 0).hasGift, "the gift expires on the tenth move")
check(PowerUp.allCases.reduce(0) { $0 + g2.count(of: $1) } == 0, "an expired gift pays nothing")

// Claiming it in time still works.
let g3 = fresh()
g3.testSetCell(row: 0, col: 3, colorIndex: nil, gift: true)
g3.testSetTray([TrayPiece(shape: bar(5)), TrayPiece(shape: bar(5)), nil])
_ = g3.place(trayIndex: 0, atRow: 0, col: 0)
_ = g3.place(trayIndex: 1, atRow: 0, col: 5)
pump()
check(PowerUp.allCases.reduce(0) { $0 + g3.count(of: $1) } == 1, "a gift claimed in time still pays out")

// MARK: - Drag targeting

print("\nDrag targeting")
let origin = CGPoint(x: 20, y: 100)
let cell: CGFloat = 36
let lift = DragTargeting.lift(cellSize: cell)

let t1 = DragTargeting.target(
    finger: CGPoint(x: 20 + 3 * cell + cell / 2, y: 100 + 4 * cell + cell / 2 + lift),
    shapeRows: 1, shapeCols: 1, gridOrigin: origin, cellSize: cell)
check(t1.row == 4 && t1.col == 3, "1x1 lands on the cell under the lifted piece (got \(t1))")

let t2 = DragTargeting.target(
    finger: CGPoint(x: 20 + 2 * cell + 1.5 * cell, y: 100 + 7 * cell + cell / 2 + lift),
    shapeRows: 1, shapeCols: 3, gridOrigin: origin, cellSize: cell)
check(t2.row == 7 && t2.col == 2, "3-wide bar anchors on its left cell (got \(t2))")

let t3 = DragTargeting.target(
    finger: CGPoint(x: 20 + 1.5 * cell + 8, y: 100 + 1.5 * cell + lift - 8),
    shapeRows: 3, shapeCols: 3, gridOrigin: origin, cellSize: cell)
check(t3.row == 0 && t3.col == 0, "3x3 snaps to the nearest cell within a quarter-cell (got \(t3))")


// MARK: - Saving the run in progress

print("\nPersistence")

// Each GameModel reads/writes the same UserDefaults, so a second instance stands in
// for relaunching the app.
let p1 = GameModel()
p1.newGame()
p1.testSetTray([TrayPiece(shape: bar(4)), TrayPiece(shape: bar(2)), nil])
_ = p1.place(trayIndex: 0, atRow: 6, col: 2)
pump(0.3)
p1.testSetPowerUp(.bomb, 4)
p1.testSetCell(row: 1, col: 1, colorIndex: nil, gift: true)
_ = p1.place(trayIndex: 1, atRow: 8, col: 0)   // a real move, which is what triggers a save
pump(0.3)
let savedScore = p1.score

let p2 = GameModel()             // simulates a relaunch
check(p2.score == savedScore, "score survives a relaunch (\(p2.score) vs \(savedScore))")
check((2...5).allSatisfy { p2.testCell(row: 6, col: $0).isFilled }, "placed bricks survive a relaunch")
check(p2.testCell(row: 1, col: 1).hasGift, "an unclaimed gift survives a relaunch")
check(p2.count(of: .bomb) == 4, "power-up counts survive a relaunch (got \(p2.count(of: .bomb)))")
check(p2.tray.compactMap { $0 }.count == p1.tray.compactMap { $0 }.count, "the tray survives a relaunch")

let p3 = GameModel()
p3.newGame()
let p4 = GameModel()
check(p4.score == 0 && !p4.testCell(row: 6, col: 2).isFilled, "New game clears the saved run")

// A save from an older build must not wedge the app.
UserDefaults.standard.set(Data("not a game".utf8), forKey: "bricks.savedGame")
let p5 = GameModel()
check(p5.score == 0 && p5.tray.compactMap { $0 }.count == 3, "a corrupt save falls back to a fresh game")

print("\n\(failures.isEmpty ? "All checks passed" : "\(failures.count) FAILED: \(failures)")")
exit(failures.isEmpty ? 0 : 1)
