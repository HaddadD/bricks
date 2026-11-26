import SwiftUI
#if os(iOS)
import CoreHaptics
#elseif os(watchOS)
import WatchKit
#endif

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
    var combo: Int
    /// The deal this move's placement emptied the tray into, if it emptied it. Rewinding
    /// puts that deal back in the deck so it comes round again, rather than letting the
    /// undo roll a fresh one.
    var dealt: [TrayPiece?]? = nil
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
    /// Lines in one placement that repaint the survivors as a rainbow rather than one colour.
    static let rainbowLines = 5
    /// Every this many combos the board goes rainbow — at 5, 10, 15 and so on.
    static let comboRainbow = 5

    @Published private(set) var board: [[Cell]]
    @Published private(set) var tray: [TrayPiece?]
    @Published private(set) var score: Int = 0
    @Published private(set) var best: Int
    @Published private(set) var powerUps: [PowerUp: Int]
    @Published private(set) var isGameOver = false
    /// Placements in a row that have cleared something. One clear is not a combo yet —
    /// it takes a second clear on the very next placement for the streak to start, so
    /// nothing is shown below 2. Any placement that clears nothing drops it to 0.
    @Published private(set) var combo: Int = 0
    /// True while the badge is showing the step that went through a multiple of five —
    /// the one that put the rainbow on the board. With several lines counting at once
    /// the streak can jump past five without landing on it, so the badge cannot work
    /// this out from the number alone.
    @Published private(set) var comboFlared = false
    /// Score at which the most recent milestone fired; nil before the first one.
    @Published private(set) var milestoneScore: Int? = nil
    /// Which celebration background that milestone drew.
    @Published private(set) var milestoneTheme: Int? = nil

    /// Cells currently playing the clear animation.
    @Published private(set) var clearing: Set<GridPoint> = []
    /// Cells briefly flashed by the bomb / hammer.
    @Published private(set) var blasting: Set<GridPoint> = []

    @Published var activePower: PowerUp? = nil
    /// Where the bomb is pointed, once it has been aimed but not yet set off. The bomb
    /// takes two taps — one to aim, one to confirm — since five bricks are a lot to lose
    /// to a fat finger.
    @Published private(set) var bombAim: GridPoint? = nil
    /// Short-lived banner shown when a gift is collected or a power-up fires.
    @Published var toast: String? = nil
    /// Set when the toast is about a particular power-up, so its capsule can glow in
    /// that power-up's colour the way an armed hint does. nil glows the usual pink.
    @Published private(set) var toastPower: PowerUp? = nil

    /// Hears everything achievements are measured on (see PlayerProgress).
    var onEvent: ((GameEvent) -> Void)?
    /// Hears every save, with when it was made, so GameSync can hand it to the other
    /// device.
    var onSaved: ((Data, Date) -> Void)?

    private var undoStack: Snapshot? = nil
    /// A deal an undo took back off the tray, waiting to be handed out again.
    private var nextDeal: [TrayPiece?]? = nil
    private var giftThreshold: Int = Int.random(in: 280...320)
    /// Set when a gift was earned but the board had nowhere to put it.
    private var pendingGift = false
    /// True once the armed rotate session has actually spent its charge.
    private var rotateCharged = false

    private let bestKey = "bricks.bestScore"
    private let saveKey = "bricks.savedGame"
    private let savedAtKey = "bricks.savedAt"

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
        // `-repaint <lines>` seeds a board as it looks after a clear of that many lines,
        // for checking the repaint without engineering a five-line break by hand.
        if let i = args.firstIndex(of: "-repaint"), i + 1 < args.count,
           let n = Int(args[i + 1]) {
            seedDemoBoard()
            repaintSurvivors(rainbow: n >= GameModel.rainbowLines)
            return
        }
        // `-combo <n>` seeds a board mid-streak, for checking the badge.
        if let i = args.firstIndex(of: "-combo"), i + 1 < args.count,
           let n = Int(args[i + 1]) {
            seedDemoBoard()
            combo = n
            if n % GameModel.comboRainbow == 0 {
                comboFlared = true
                repaintSurvivors(rainbow: true)
            }
            return
        }
        if args.contains("-demo") {
            seedDemoBoard()
            return
        }
        // `-gameOver` shows the game-over card over the demo board.
        if args.contains("-gameOver") {
            seedDemoBoard()
            isGameOver = true
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
        onEvent?(.newGame)
        withAnimation(.easeOut(duration: 0.25)) {
            board = Array(
                repeating: Array(repeating: Cell(), count: GameModel.size),
                count: GameModel.size
            )
            tray = dealTray()
            score = 0
            combo = 0
            comboFlared = false
            isGameOver = false
            clearing = []
            blasting = []
            activePower = nil
            bombAim = nil
            // Power-ups deliberately survive into the next game.
        }
        undoStack = nil
        nextDeal = nil
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
        var combo: Int?
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
            milestoneTheme: milestoneTheme,
            combo: combo
        )
        if let data = try? JSONEncoder().encode(save) {
            let now = Date()
            UserDefaults.standard.set(data, forKey: saveKey)
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: savedAtKey)
            onSaved?(data, now)
        }
        publishWidget()
    }

    /// The game as last saved, in the form `adopt` takes.
    var savedGame: Data? { UserDefaults.standard.data(forKey: saveKey) }

    /// When this device last saved the game; the distant past before its first save.
    var savedAt: Date {
        Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: savedAtKey))
    }

    /// Carries on with a game saved on the other device (iPhone and Apple Watch), if it
    /// was saved after this one, and keeps the better of the two best scores. Returns
    /// whether the game was taken over.
    @discardableResult
    func adopt(_ data: Data, savedAt otherSavedAt: Date, best otherBest: Int) -> Bool {
        if otherBest > best {
            best = otherBest
            UserDefaults.standard.set(best, forKey: bestKey)
        }
        guard otherSavedAt > savedAt, let save = Self.decode(data) else { return false }

        apply(save)
        activePower = nil
        clearing = []
        blasting = []
        undoStack = nil
        UserDefaults.standard.set(data, forKey: saveKey)
        UserDefaults.standard.set(otherSavedAt.timeIntervalSince1970, forKey: savedAtKey)
        publishWidget()
        return true
    }

    /// Shares the board and score with the widget (iPhone and iPad), unless the player has
    /// switched the widget off.
    func publishWidget() {
        #if os(iOS)
        WidgetSnapshot(
            cells: board.map { $0.map(\.colorIndex) },
            score: score,
            best: best,
            isGameOver: isGameOver
        ).publish()
        #endif
    }

    /// Reloads the last run. A save written by an older build simply starts a fresh game.
    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: saveKey), let save = Self.decode(data)
        else { return }
        apply(save)
    }

    private static func decode(_ data: Data) -> SavedGame? {
        guard let save = try? JSONDecoder().decode(SavedGame.self, from: data),
              save.board.count == GameModel.size,
              save.board.allSatisfy({ $0.count == GameModel.size }),
              save.tray.count == 3
        else { return nil }
        return save
    }

    private func apply(_ save: SavedGame) {
        board = save.board
        tray = save.tray
        score = save.score
        giftThreshold = save.giftThreshold
        pendingGift = save.pendingGift
        isGameOver = save.isGameOver
        milestoneScore = save.milestoneScore
        milestoneTheme = save.milestoneTheme
        combo = save.combo ?? 0

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
    /// The deal an undo put back, if there is one, otherwise a fresh one.
    ///
    /// Rewinding a move hands its deal back to the deck so that replaying the move gives
    /// you the same three pieces — undo is a rewind, not a reroll. The held deal is
    /// dropped if the board has since changed enough that none of it fits, since the
    /// promise that a deal always contains a playable piece outranks it.
    private func heldOrFreshDeal() -> [TrayPiece?] {
        defer { nextDeal = nil }
        if let held = nextDeal,
           held.compactMap({ $0 }).contains(where: { canPlaceAnywhere($0.shape) }) {
            return held
        }
        return dealTray()
    }

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
            pendingGift: pendingGift,
            combo: combo
        )

        withAnimation(.spring(response: 0.24, dampingFraction: 0.7)) {
            for p in piece.shape.points {
                board[row + p.r][col + p.c].colorIndex = piece.colorIndex
            }
            score += piece.shape.cellCount
            tray[trayIndex] = nil
            // Playing a piece settles it: a bomb left half-aimed is no longer pointed at
            // the board it was aimed at.
            bombAim = nil
        }

        Haptics.tap()
        Sound.place()
        onEvent?(.placed(family: piece.shape.family))
        resolveClears(placedCells: piece.shape.cellCount)
        return true
    }

    // MARK: - Line clearing

    private func resolveClears(placedCells: Int) {
        var fullRows: [Int] = []
        var fullCols: [Int] = []

        for r in 0..<GameModel.size where board[r].allSatisfy({ $0.isFilled }) {
            fullRows.append(r)
        }
        for c in 0..<GameModel.size where (0..<GameModel.size).allSatisfy({ board[$0][c].isFilled }) {
            fullCols.append(c)
        }

        guard !fullRows.isEmpty || !fullCols.isEmpty else {
            onEvent?(.missed)
            // A placement that clears nothing ends the streak.
            withAnimation(.easeOut(duration: 0.2)) {
                combo = 0
                comboFlared = false
            }
            finishTurn()
            return
        }
        let filled = board.joined().filter(\.isFilled).count

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
        Sound.lineClear()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            guard let self = self else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                for p in cells {
                    self.board[p.r][p.c] = Cell()
                }
                self.clearing = []
                self.score += award
            }
            self.onEvent?(.cleared(
                rows: fullRows.count, cols: fullCols.count, gifts: giftsWon, filled: filled,
                emptied: !self.board.joined().contains(where: \.isFilled), points: placedCells + award
            ))
            // Every line counts, so breaking three at once moves the streak on three.
            let before = self.combo
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                self.combo += lines
            }

            // Either a big break or every fifth combo turns the board rainbow; a
            // smaller multi-line break settles it on one colour. Passing a multiple of
            // five counts, not just landing on one — a three-line break that takes the
            // streak from 4 to 7 has gone through 5.
            let streak = self.combo / GameModel.comboRainbow > before / GameModel.comboRainbow
            withAnimation(.easeOut(duration: 0.3)) { self.comboFlared = streak }
            if streak || lines > 1 {
                withAnimation(.easeInOut(duration: 0.45)) {
                    self.repaintSurvivors(rainbow: streak || lines >= GameModel.rainbowLines)
                }
            }
            if lines > 1 {
                self.showToast("+\(award) pts")
            }
            if giftsWon > 0 {
                for _ in 0..<giftsWon { self.awardGift() }
            }
            self.finishTurn()
        }
    }

    /// Repaints every brick still standing: diagonal rainbow bands after a five-line
    /// break or every fifth combo, otherwise one random colour.
    ///
    /// Only the board is repainted. Tray pieces keep their family colour, so you can
    /// still tell a four-bar from a five-bar while the board is all one shade.
    private func repaintSurvivors(rainbow: Bool) {
        var standing: [GridPoint] = []
        for r in 0..<GameModel.size {
            for c in 0..<GameModel.size where board[r][c].isFilled {
                standing.append(GridPoint(r: r, c: c))
            }
        }
        guard !standing.isEmpty else { return }

        if rainbow {
            for p in standing {
                board[p.r][p.c].colorIndex = Theme.rainbowIndex(row: p.r, col: p.c)
            }
            return
        }

        // If the board is already a single colour — which it is after any earlier
        // multi-clear — draw a different one so the repaint is visible.
        let present = Set(standing.compactMap { board[$0.r][$0.c].colorIndex })
        let colour = Theme.randomBlock(avoiding: present.count == 1 ? present.first : nil)
        for p in standing {
            board[p.r][p.c].colorIndex = colour
        }
    }

    /// Refills the tray when empty, spawns gifts, and checks for game over.
    private func finishTurn() {
        if tray.allSatisfy({ $0 == nil }) {
            let deal = heldOrFreshDeal()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                tray = deal
            }
            // Remember what this turn dealt, so undoing it can hand the same three
            // pieces back rather than drawing new ones.
            undoStack?.dealt = deal
        }

        if score > best {
            best = score
            UserDefaults.standard.set(best, forKey: bestKey)
        }

        checkMilestone()
        ageGifts()
        maybeSpawnGift()
        onEvent?(.score(score))

        if !hasAnyMove {
            if !isGameOver { Sound.gameOver() }
            withAnimation(.easeOut(duration: 0.3).delay(0.25)) {
                isGameOver = true
            }
            onEvent?(.gameOver)
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
        showToast("\(reached * GameModel.milestoneStep) pts!")
        Haptics.reward()
        onEvent?(.celebration(picked))
        Sound.milestone()
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
        showToast("A gift appeared!")
    }

    /// Ticks every gift down one move, clearing any that run out. Expiry is silent —
    /// the countdown on the badge has already been saying it for ten moves.
    private func ageGifts() {
        for r in 0..<GameModel.size {
            for c in 0..<GameModel.size {
                guard let left = board[r][c].giftMovesLeft else { continue }
                if left <= 1 {
                    board[r][c].giftMovesLeft = nil
                } else {
                    board[r][c].giftMovesLeft = left - 1
                }
            }
        }
    }

    /// Grants one random power-up, respecting the cap of 5 per type.
    private func awardGift() {
        let available = PowerUp.allCases.filter { (powerUps[$0] ?? 0) < PowerUp.maxPerType }

        guard let won = available.randomElement() else {
            score += 100
            showToast("+100 bonus!")
            Haptics.reward()
            onEvent?(.giftClaimed(stock: PowerUp.allCases.map(count(of:))))
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            powerUps[won, default: 0] += 1
        }
        showToast("\(won.title) +1", from: won)
        Haptics.reward()
        onEvent?(.giftClaimed(stock: PowerUp.allCases.map(count(of:))))
        Sound.powerUp()
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
            withAnimation(.easeOut(duration: 0.15)) {
                activePower = power
                bombAim = nil
            }
        }
    }

    /// What the banner says for whatever is armed. The bomb has two steps, so it has two
    /// things to say.
    var powerHint: String? {
        guard let power = activePower else { return nil }
        if power == .bomb && bombAim != nil { return power.confirmHint }
        return power.targetHint.isEmpty ? nil : power.targetHint
    }

    /// Spends one charge. Every power-up but Rotate goes through here, so this is where
    /// the sound of using one lives; Rotate charges itself on its first turn instead.
    private func consume(_ power: PowerUp) {
        Sound.powerUp()
        withAnimation(.easeOut(duration: 0.2)) {
            powerUps[power, default: 0] = max(0, (powerUps[power] ?? 0) - 1)
            activePower = nil
            bombAim = nil
        }
    }

    private func applyShuffle() {
        consume(.shuffle)
        onEvent?(.usedPowerUp(PowerUp.shuffle.rawValue, bricks: 0))
        // Asking for new pieces throws away a deal an undo was holding back, which is
        // the whole point of asking.
        nextDeal = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            tray = dealTray()
        }
        Haptics.tap()
        showToast("Pieces shuffled", from: .shuffle)
        recheckGameOver()
    }

    private func applyUndo() {
        // A clear or a blast still settling finishes by writing into the board a
        // fraction of a second from now, which would land on top of whatever this puts
        // back. Nothing is spent, so the next tap works.
        guard clearing.isEmpty, blasting.isEmpty else { return }

        guard let snap = undoStack else {
            showToast("Nothing to undo", from: .undo)
            return
        }
        consume(.undo)
        onEvent?(.usedPowerUp(PowerUp.undo.rawValue, bricks: 0))
        withAnimation(.easeOut(duration: 0.25)) {
            board = snap.board
            tray = snap.tray
            score = snap.score
            combo = snap.combo
            // Whether the step being rewound to was itself a rainbow one is not worth
            // tracking; the badge simply stops flaring.
            comboFlared = false
            clearing = []
        }
        giftThreshold = snap.giftThreshold
        pendingGift = snap.pendingGift
        // If the move being rewound emptied the tray, the deal it drew is put back and
        // comes round again on the next refill.
        nextDeal = snap.dealt
        undoStack = nil
        Haptics.tap()
        showToast("Move undone")
        onEvent?(.score(score))
        showToast("Move undone", from: .undo)
        recheckGameOver()
    }

    /// Handles a board tap while Hammer or Bomb is armed.
    func applyTargetedPower(atRow row: Int, col: Int) {
        guard !isGameOver, let power = activePower else { return }

        switch power {
        case .hammer:
            guard board[row][col].isFilled else { return }
            consume(.hammer)
            onEvent?(.usedPowerUp(PowerUp.hammer.rawValue, bricks: 1))
            flash([GridPoint(r: row, c: col)])

        case .bomb:
            let spot = GridPoint(r: row, c: col)
            let hit = bombBlast(atRow: row, col: col)

            // Two taps: the first aims, the second sets it off. Tapping anywhere else
            // moves the aim there instead, so changing your mind costs nothing. Aiming
            // over empty board is allowed — seeing the footprint is the point of the
            // first tap — but there is nothing to confirm, which the missing tick says.
            if bombAim == spot, !hit.isEmpty {
                withAnimation(.easeOut(duration: 0.15)) { bombAim = nil }
                consume(.bomb)
                onEvent?(.usedPowerUp(PowerUp.bomb.rawValue, bricks: hit.count))
                flash(hit)
            } else {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.7)) {
                    bombAim = spot
                }
                Haptics.tap()
            }

        default:
            return
        }
    }

    /// The bricks a bomb centred on this square would take, clipped to the board.
    /// The view asks too, to decide whether the aim gets a tick to tap.
    func bombBlast(atRow row: Int, col: Int) -> [GridPoint] {
        var hit: [GridPoint] = []
        for r in (row - 1)...(row + 1) {
            for c in (col - 1)...(col + 1) {
                guard r >= 0, r < GameModel.size, c >= 0, c < GameModel.size else { continue }
                if board[r][c].isFilled { hit.append(GridPoint(r: r, c: c)) }
            }
        }
        return hit
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
            Sound.powerUp()
            rotateCharged = true
            onEvent?(.usedPowerUp(PowerUp.rotate.rawValue, bricks: 0))
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
        withAnimation(.easeOut(duration: 0.15)) {
            activePower = nil
            bombAim = nil
        }
        rotateCharged = false
        if wasRotate { recheckGameOver() }
    }

    private func recheckGameOver() {
        let wasOver = isGameOver
        let over = !hasAnyMove
        if over && !wasOver { Sound.gameOver() }
        withAnimation(.easeOut(duration: 0.25)) {
            isGameOver = over
        }
        if isGameOver && !wasOver { onEvent?(.gameOver) }
        persist()
    }

    // MARK: - Toast

    private var toastToken = 0

    /// `from` tints the capsule in a power-up's own colour; nil leaves it the usual pink.
    private func showToast(_ message: String.LocalizationValue, from power: PowerUp? = nil) {
        let text = String(localized: message)
        toastToken += 1
        let token = toastToken
        toastPower = power
        withAnimation(.easeOut(duration: 0.2)) { toast = text }

        #if DEBUG
        // A toast is gone in under two seconds, which is quicker than a screenshot can
        // be taken. `-stickytoast` holds it up so the styling can be looked at.
        if ProcessInfo.processInfo.arguments.contains("-stickytoast") { return }
        #endif

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { [weak self] in
            guard let self = self, self.toastToken == token else { return }
            withAnimation(.easeIn(duration: 0.3)) { self.toast = nil }
        }
    }
}

enum Haptics {
    /// Mirrors the Vibrations setting; every call below is a no-op when it is off.
    static var enabled = true

    /// Whether this device can vibrate at all: iPhones and Apple Watch can; iPad, Mac,
    /// Apple TV and Vision Pro can't.
    static let isSupported: Bool = {
        #if os(iOS)
        return CHHapticEngine.capabilitiesForHardware().supportsHaptics
        #elseif os(watchOS)
        return true
        #else
        return false
        #endif
    }()

    static func tap() {
        guard enabled else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    static func clear(lines: Int) {
        guard enabled else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: lines > 1 ? .heavy : .medium).impactOccurred()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(lines > 1 ? .success : .directionUp)
        #endif
    }

    static func reward() {
        guard enabled else { return }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.notification)
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

    func testSetCombo(_ value: Int) { combo = value }

    func testCell(row: Int, col: Int) -> Cell { board[row][col] }

    func testDeal() -> [TrayPiece?] { dealTray() }
}
#endif
