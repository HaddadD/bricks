import SwiftUI

struct Cell: Equatable, Codable {
    var colorIndex: Int?
    /// Moves a gift has left before it expires. `nil` means there is no gift here.
    var giftMovesLeft: Int? = nil

    var isFilled: Bool { colorIndex != nil }
    var hasGift: Bool { giftMovesLeft != nil }

    init(colorIndex: Int? = nil, giftMovesLeft: Int? = nil) {
        self.colorIndex = colorIndex
        self.giftMovesLeft = giftMovesLeft
    }
}

/// Everything needed to rewind one move.
private struct Snapshot {
    var board: [[Cell]]
    var tray: [TrayPiece?]
    var score: Int
    var giftThreshold: Int
    var pendingGift: Bool
}

final class GameModel: ObservableObject {

    static let size = 10
    /// Moves a gift survives on the board before it expires.
    static let giftLifespan = 10
    /// Points between background celebrations.
    static let milestoneStep = 1000
    /// Points over which the celebration fades back to the normal background.
    static let milestoneFade = 200
    /// Multiplier applied when a single placement clears more than one line.
    static let multiClearBonus = 1.5

    @Published private(set) var board: [[Cell]]
    @Published private(set) var tray: [TrayPiece?]
    @Published private(set) var score: Int = 0
    @Published private(set) var best: Int
    @Published private(set) var powerUps: [PowerUp: Int]
    @Published private(set) var isGameOver = false
    /// Score at which the most recent milestone fired; nil before the first one.
    @Published private(set) var milestoneScore: Int? = nil
    /// Which celebration background that milestone drew.
    @Published private(set) var milestoneTheme: Int? = nil

    /// Cells currently playing the clear animation.
    @Published private(set) var clearing: Set<GridPoint> = []
    /// Cells briefly flashed by the bomb / hammer.
    @Published private(set) var blasting: Set<GridPoint> = []

    @Published var activePower: PowerUp? = nil
    /// Short-lived banner shown when a gift is collected or a power-up fires.
    @Published var toast: String? = nil

    private var undoStack: Snapshot? = nil
    private var giftThreshold: Int = Int.random(in: 280...320)
    /// Set when a gift was earned but the board had nowhere to put it.
    private var pendingGift = false
    /// True once the armed rotate session has actually spent its charge.
    private var rotateCharged = false

    private let bestKey = "bricks.bestScore"
    private let saveKey = "bricks.savedGame"

    // MARK: - Lifecycle

    init() {
        board = Array(
            repeating: Array(repeating: Cell(), count: GameModel.size),
            count: GameModel.size
        )
        tray = [TrayPiece.random(), TrayPiece.random(), TrayPiece.random()]
        best = UserDefaults.standard.integer(forKey: bestKey)
        powerUps = Dictionary(uniqueKeysWithValues: PowerUp.allCases.map { ($0, 0) })

        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        // `-celebrate <n>` seeds a board mid-celebration on background n, for checking
        // how each one looks without playing to a milestone.
        if let i = args.firstIndex(of: "-celebrate"), i + 1 < args.count,
           let n = Int(args[i + 1]) {
            seedDemoBoard()
            milestoneScore = score
            milestoneTheme = n
            return
        }
        if args.contains("-demo") {
            seedDemoBoard()
            return
        }
        #endif

        restore()
    }

    #if DEBUG
    /// Populates a representative board so the UI can be inspected without playing.
    private func seedDemoBoard() {
        let sprinkle: [(Int, Int, Int)] = [
            (2, 1, 0), (2, 2, 0), (3, 2, 5), (3, 3, 5), (4, 0, 6), (4, 1, 6), (4, 2, 6),
            (5, 6, 3), (5, 7, 3), (6, 6, 3), (6, 7, 3), (7, 2, 4), (7, 3, 4), (8, 8, 7),
            (9, 0, 1), (9, 1, 1), (9, 2, 1), (9, 3, 1), (9, 4, 1), (9, 5, 2), (9, 6, 2),
            (9, 7, 2), (9, 8, 2)
        ]
        for (r, c, color) in sprinkle { board[r][c].colorIndex = color }
        board[9][3].giftMovesLeft = 7   // gift already covered, waiting on its line
        board[1][7].giftMovesLeft = 3   // gift still sitting on an open square
        score = 1240
        powerUps = [.hammer: 3, .bomb: 5, .shuffle: 1, .rotate: 0, .undo: 2]
    }
    #endif

    func newGame() {
        withAnimation(.easeOut(duration: 0.25)) {
            board = Array(
                repeating: Array(repeating: Cell(), count: GameModel.size),
                count: GameModel.size
            )
            tray = dealTray()
            score = 0
            isGameOver = false
            clearing = []
            blasting = []
            activePower = nil
            // Power-ups deliberately survive into the next game.
        }
        undoStack = nil
        pendingGift = false
        milestoneScore = nil
        milestoneTheme = nil
        giftThreshold = Int.random(in: 280...320)
        persist()
    }

    // MARK: - Saving the run in progress

    /// The whole run, so closing the app (or a lapsed 7-day signature) doesn't cost a game.
    private struct SavedGame: Codable {
        var board: [[Cell]]
        var tray: [TrayPiece?]
        var score: Int
        var powerUps: [String: Int]
        var giftThreshold: Int
        var pendingGift: Bool
        var isGameOver: Bool
        var milestoneScore: Int?
        var milestoneTheme: Int?
    }

    private func persist() {
        let save = SavedGame(
            board: board,
            tray: tray,
            score: score,
            powerUps: Dictionary(uniqueKeysWithValues: powerUps.map { ($0.key.rawValue, $0.value) }),
            giftThreshold: giftThreshold,
            pendingGift: pendingGift,
            isGameOver: isGameOver,
            milestoneScore: milestoneScore,
            milestoneTheme: milestoneTheme
        )
        if let data = try? JSONEncoder().encode(save) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    /// Reloads the last run. A save written by an older build simply starts a fresh game.
    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let save = try? JSONDecoder().decode(SavedGame.self, from: data),
              save.board.count == GameModel.size,
              save.board.allSatisfy({ $0.count == GameModel.size }),
              save.tray.count == 3
        else { return }

        board = save.board
        tray = save.tray
        score = save.score
        giftThreshold = save.giftThreshold
        pendingGift = save.pendingGift
        isGameOver = save.isGameOver
        milestoneScore = save.milestoneScore
        milestoneTheme = save.milestoneTheme

        var restored = Dictionary(uniqueKeysWithValues: PowerUp.allCases.map { ($0, 0) })
        for (raw, count) in save.powerUps {
            if let power = PowerUp(rawValue: raw) {
                restored[power] = min(count, PowerUp.maxPerType)
            }
        }
        powerUps = restored
    }

    // MARK: - Dealing

    /// Deals three pieces, guaranteeing at least one of them fits the board as it
    /// stands. Being handed three dead pieces is never the thing that ends a game —
    /// one or two of the three may be unplaceable, but never all three.
    ///
    /// There is always some shape that fits: a board with no empty square at all would
    /// have completed every row and column and cleared itself, so a 1x1 always has
    /// somewhere to go.
    private func dealTray() -> [TrayPiece?] {
        var deal = [TrayPiece.random(), TrayPiece.random(), TrayPiece.random()]
        if deal.contains(where: { canPlaceAnywhere($0.shape) }) {
            return deal
        }

        let fitting = Shape.all.filter { canPlaceAnywhere($0) }
        if let rescue = fitting.randomElement() {
            deal[Int.random(in: 0..<deal.count)] = TrayPiece(shape: rescue)
        }
        return deal
    }

    // MARK: - Placement

    func canPlace(_ shape: Shape, atRow row: Int, col: Int) -> Bool {
        for p in shape.points {
            let r = row + p.r
            let c = col + p.c
            guard r >= 0, r < GameModel.size, c >= 0, c < GameModel.size else { return false }
            if board[r][c].isFilled { return false }
        }
        return true
    }

    func canPlaceAnywhere(_ shape: Shape) -> Bool {
        for r in 0..<GameModel.size {
            for c in 0..<GameModel.size where canPlace(shape, atRow: r, col: c) {
                return true
            }
        }
        return false
    }

    private var hasAnyMove: Bool {
        tray.compactMap { $0 }.contains { canPlaceAnywhere($0.shape) }
    }

    /// Drops a tray piece onto the board. Returns false if the position is illegal.
    @discardableResult
    func place(trayIndex: Int, atRow row: Int, col: Int) -> Bool {
        guard tray.indices.contains(trayIndex), let piece = tray[trayIndex] else { return false }
        guard canPlace(piece.shape, atRow: row, col: col) else { return false }

        undoStack = Snapshot(
            board: board,
            tray: tray,
            score: score,
            giftThreshold: giftThreshold,
            pendingGift: pendingGift
        )

        withAnimation(.spring(response: 0.24, dampingFraction: 0.7)) {
            for p in piece.shape.points {
                board[row + p.r][col + p.c].colorIndex = piece.colorIndex
            }
            score += piece.shape.cellCount
            tray[trayIndex] = nil
        }

        Haptics.tap()
        resolveClears()
        return true
    }

    // MARK: - Line clearing

    private func resolveClears() {
        var fullRows: [Int] = []
        var fullCols: [Int] = []

        for r in 0..<GameModel.size where board[r].allSatisfy({ $0.isFilled }) {
            fullRows.append(r)
        }
        for c in 0..<GameModel.size where (0..<GameModel.size).allSatisfy({ board[$0][c].isFilled }) {
            fullCols.append(c)
        }

        guard !fullRows.isEmpty || !fullCols.isEmpty else {
            finishTurn()
            return
        }

        var cells: Set<GridPoint> = []
        for r in fullRows {
            for c in 0..<GameModel.size { cells.insert(GridPoint(r: r, c: c)) }
        }
        for c in fullCols {
            for r in 0..<GameModel.size { cells.insert(GridPoint(r: r, c: c)) }
        }

        // Any gift sitting in a cleared line is earned.
        let giftsWon = cells.filter { board[$0.r][$0.c].hasGift }.count

        let lines = fullRows.count + fullCols.count

        // Clearing more than one line in a single placement is worth 1.5x the cells it
        // clears. It applies to that clear alone — the next one starts from scratch.
        let cleared = cells.count
        let award = lines > 1
            ? Int((Double(cleared) * GameModel.multiClearBonus).rounded())
            : cleared

        withAnimation(.easeOut(duration: 0.16)) {
            clearing = cells
        }
        Haptics.clear(lines: lines)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            guard let self = self else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                for p in cells {
                    self.board[p.r][p.c] = Cell()
                }
                self.clearing = []
                self.score += award
            }
            if lines > 1 {
                self.showToast("+\(award) points")
            }
            if giftsWon > 0 {
                for _ in 0..<giftsWon { self.awardGift() }
            }
            self.finishTurn()
        }
    }

    /// Refills the tray when empty, spawns gifts, and checks for game over.
    private func finishTurn() {
        if tray.allSatisfy({ $0 == nil }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                tray = dealTray()
            }
        }

        if score > best {
            best = score
            UserDefaults.standard.set(best, forKey: bestKey)
        }

        checkMilestone()
        ageGifts()
        maybeSpawnGift()

        if !hasAnyMove {
            withAnimation(.easeOut(duration: 0.3).delay(0.25)) {
                isGameOver = true
            }
        }

        persist()
    }

    // MARK: - Milestones

    /// 1 immediately after a milestone, easing to 0 once `milestoneFade` more points
    /// have been scored. The background reads this to blend the celebration away.
    var celebrationLevel: Double {
        guard let from = milestoneScore else { return 0 }
        let progress = Double(score - from) / Double(GameModel.milestoneFade)
        return min(1, max(0, 1 - progress))
    }

    /// Fires each time the score passes another whole `milestoneStep`.
    private func checkMilestone() {
        let alreadyFired = (milestoneScore ?? 0) / GameModel.milestoneStep
        let reached = score / GameModel.milestoneStep
        guard reached > alreadyFired else { return }

        // Draw a different background from the one the last milestone used.
        let choices = Theme.celebrations.indices.filter { $0 != milestoneTheme }
        let picked = choices.randomElement() ?? 0

        withAnimation(.easeOut(duration: 0.5)) {
            milestoneScore = score
            milestoneTheme = picked
        }
        showToast("\(reached * GameModel.milestoneStep) points!")
        Haptics.reward()
    }

    // MARK: - Gifts

    /// Every ~300 points a gift appears on an unclaimed square.
    private func maybeSpawnGift() {
        guard pendingGift || score >= giftThreshold else { return }

        var empties: [GridPoint] = []
        for r in 0..<GameModel.size {
            for c in 0..<GameModel.size where !board[r][c].isFilled && !board[r][c].hasGift {
                empties.append(GridPoint(r: r, c: c))
            }
        }

        guard let spot = empties.randomElement() else {
            // Nowhere to put it right now — try again after the next move.
            pendingGift = true
            if score >= giftThreshold { giftThreshold = score + Int.random(in: 280...320) }
            return
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            board[spot.r][spot.c].giftMovesLeft = GameModel.giftLifespan
        }
        if score >= giftThreshold { giftThreshold = score + Int.random(in: 280...320) }
        pendingGift = false
        showToast("A gift appeared — clear its line!")
    }

    /// Ticks every gift down one move, clearing any that run out.
    private func ageGifts() {
        var expired = false
        for r in 0..<GameModel.size {
            for c in 0..<GameModel.size {
                guard let left = board[r][c].giftMovesLeft else { continue }
                if left <= 1 {
                    board[r][c].giftMovesLeft = nil
                    expired = true
                } else {
                    board[r][c].giftMovesLeft = left - 1
                }
            }
        }
        if expired { showToast("A gift expired") }
    }

    /// Grants one random power-up, respecting the cap of 5 per type.
    private func awardGift() {
        let available = PowerUp.allCases.filter { (powerUps[$0] ?? 0) < PowerUp.maxPerType }

        guard let won = available.randomElement() else {
            score += 100
            showToast("All power-ups full — +100 bonus!")
            Haptics.reward()
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            powerUps[won, default: 0] += 1
        }
        showToast("Gift claimed — \(won.title) +1")
        Haptics.reward()
    }

    // MARK: - Power-ups

    func count(of power: PowerUp) -> Int { powerUps[power] ?? 0 }

    func tapPowerUp(_ power: PowerUp) {
        // A lost game is lost: power-ups keep for the next one instead.
        guard !isGameOver, count(of: power) > 0 else { return }

        if activePower == power {
            cancelPower()
            return
        }

        if power.isInstant {
            switch power {
            case .shuffle: applyShuffle()
            case .undo: applyUndo()
            default: break
            }
        } else {
            if power == .undo || power == .shuffle { return }
            rotateCharged = false
            withAnimation(.easeOut(duration: 0.15)) { activePower = power }
        }
    }

    private func consume(_ power: PowerUp) {
        withAnimation(.easeOut(duration: 0.2)) {
            powerUps[power, default: 0] = max(0, (powerUps[power] ?? 0) - 1)
            activePower = nil
        }
    }

    private func applyShuffle() {
        consume(.shuffle)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            tray = dealTray()
        }
        Haptics.tap()
        showToast("Pieces shuffled")
        recheckGameOver()
    }

    private func applyUndo() {
        guard let snap = undoStack else {
            showToast("Nothing to undo")
            return
        }
        consume(.undo)
        withAnimation(.easeOut(duration: 0.25)) {
            board = snap.board
            tray = snap.tray
            score = snap.score
            clearing = []
        }
        giftThreshold = snap.giftThreshold
        pendingGift = snap.pendingGift
        undoStack = nil
        Haptics.tap()
        showToast("Move undone")
        recheckGameOver()
    }

    /// Handles a board tap while Hammer or Bomb is armed.
    func applyTargetedPower(atRow row: Int, col: Int) {
        guard !isGameOver, let power = activePower else { return }

        switch power {
        case .hammer:
            guard board[row][col].isFilled else { return }
            consume(.hammer)
            flash([GridPoint(r: row, c: col)])

        case .bomb:
            var hit: [GridPoint] = []
            for r in (row - 1)...(row + 1) {
                for c in (col - 1)...(col + 1) {
                    guard r >= 0, r < GameModel.size, c >= 0, c < GameModel.size else { continue }
                    if board[r][c].isFilled { hit.append(GridPoint(r: r, c: c)) }
                }
            }
            guard !hit.isEmpty else { return }
            consume(.bomb)
            flash(hit)

        default:
            return
        }
    }

    /// Removes cells with a short flash, preserving any gifts underneath.
    private func flash(_ cells: [GridPoint]) {
        withAnimation(.easeOut(duration: 0.14)) {
            blasting = Set(cells)
        }
        Haptics.clear(lines: 1)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self = self else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                for p in cells {
                    let gift = self.board[p.r][p.c].giftMovesLeft
                    self.board[p.r][p.c] = Cell(colorIndex: nil, giftMovesLeft: gift)
                }
                self.blasting = []
            }
            self.recheckGameOver()
        }
    }

    /// Turns all three tray pieces 90° at once (Rotate power-up).
    ///
    /// One charge buys a whole rotating session: tap as many times as you like, each tap
    /// turning the whole tray another quarter turn. Starting a drag ends the session.
    func rotateTray() {
        guard !isGameOver, activePower == .rotate else { return }

        // The charge is spent on the first turn, not on arming, so arming and changing
        // your mind costs nothing.
        if !rotateCharged {
            guard count(of: .rotate) > 0 else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                powerUps[.rotate] = count(of: .rotate) - 1
            }
            rotateCharged = true
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            for i in tray.indices where tray[i] != nil {
                tray[i]?.shape = tray[i]!.shape.rotated()
            }
        }
        Haptics.tap()
        // No game-over check mid-session: an awkward quarter turn must be rotatable out of.
        persist()
    }

    /// Ends a rotating session — called when the player starts dragging a piece, which is
    /// what finishes that use of the prize.
    func endRotateMode() {
        guard activePower == .rotate else { return }
        withAnimation(.easeOut(duration: 0.15)) { activePower = nil }
        rotateCharged = false
        recheckGameOver()
    }

    /// Disarms whatever power-up is armed, refunding an unused rotate session.
    func cancelPower() {
        guard activePower != nil else { return }
        let wasRotate = activePower == .rotate
        withAnimation(.easeOut(duration: 0.15)) { activePower = nil }
        rotateCharged = false
        if wasRotate { recheckGameOver() }
    }

    private func recheckGameOver() {
        withAnimation(.easeOut(duration: 0.25)) {
            isGameOver = !hasAnyMove
        }
        persist()
    }

    // MARK: - Toast

    private var toastToken = 0

    private func showToast(_ text: String) {
        toastToken += 1
        let token = toastToken
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { [weak self] in
            guard let self = self, self.toastToken == token else { return }
            withAnimation(.easeIn(duration: 0.3)) { self.toast = nil }
        }
    }
}

enum Haptics {
    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func clear(lines: Int) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: lines > 1 ? .heavy : .medium).impactOccurred()
        #endif
    }

    static func reward() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

#if DEBUG
/// Seams used by the headless rule tests. Same file, so `private(set)` stays writable.
extension GameModel {
    func testSetTray(_ pieces: [TrayPiece?]) { tray = pieces }

    func testSetCell(row: Int, col: Int, colorIndex: Int?, gift: Bool = false) {
        board[row][col] = Cell(colorIndex: colorIndex, giftMovesLeft: gift ? GameModel.giftLifespan : nil)
    }

    func testSetPowerUp(_ power: PowerUp, _ count: Int) { powerUps[power] = count }

    func testSetScore(_ value: Int) { score = value }

    func testCell(row: Int, col: Int) -> Cell { board[row][col] }

    func testDeal() -> [TrayPiece?] { dealTray() }
}
#endif
