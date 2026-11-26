import Foundation

// The game's Game Center catalog and the rules for earning it, with no GameKit or UI in
// sight: the app reports against it (GameCenter.swift), the headless tests check it, and
// appstore/tools/gamecenter.swift reads the same list to draw the badges and set
// everything up in App Store Connect. App Store Connect never lets an identifier be used
// twice, even after deleting it, so ids here are permanent once created.

/// Something that happened in a game, as GameModel reports it.
enum GameEvent: Equatable {
    /// A fresh board. Any game in progress counts as played.
    case newGame
    /// A piece went down; `family` is `Shape.family`.
    case placed(family: Int)
    /// That piece completed lines. `filled` is how many squares were filled just before
    /// they cleared; `emptied` is whether the board was left completely empty.
    case cleared(rows: Int, cols: Int, gifts: Int, filled: Int, emptied: Bool, points: Int)
    /// That piece completed nothing.
    case missed
    case score(Int)
    /// A gift was won; `stock` is how many of each power-up the player then holds.
    case giftClaimed(stock: [Int])
    /// `bricks` is how many the hammer or bomb removed (0 for the others).
    case usedPowerUp(String, bricks: Int)
    /// A milestone celebration, by its index in `Theme.celebrations`.
    case celebration(Int)
    case gameOver
}

enum Achievement: String, CaseIterable {
    // Score in one game
    case score100 = "score.100", score500 = "score.500", score1000 = "score.1000"
    case score2500 = "score.2500", score5000 = "score.5000", score10000 = "score.10000"
    case score25000 = "score.25000"
    // Lines, ever
    case lines1 = "lines.1", lines50 = "lines.50", lines250 = "lines.250"
    case lines1000 = "lines.1000", lines5000 = "lines.5000"
    // Lines in one game
    case gameLines50 = "game_lines.50", gameLines150 = "game_lines.150"
    // One piece
    case double = "combo.2", triple = "combo.3", quad = "combo.4", spectacular = "combo.5"
    case crossroads = "cross", cleanSlate = "clean_slate", closeCall = "close_call"
    // Clearing with piece after piece
    case streak5 = "streak.5", streak10 = "streak.10"
    // Pieces
    case pieces1 = "pieces.1", pieces500 = "pieces.500", pieces5000 = "pieces.5000"
    case fullSet = "full_set"
    // Coming back
    case games10 = "games.10", games50 = "games.50", games200 = "games.200"
    case days7 = "days.7", days30 = "days.30"
    // Gifts
    case gift1 = "gifts.1", gifts25 = "gifts.25", gifts100 = "gifts.100"
    case doubleGift = "double_gift", fullyStocked = "fully_stocked"
    // Power-ups
    case hammer = "power.hammer", bomb = "power.bomb", shuffle = "power.shuffle"
    case rotate = "power.rotate", undo = "power.undo"
    case toolbox = "toolbox", directHit = "direct_hit", purist = "purist"
    // Celebrations
    case lightShow = "light_show"
    // Every device
    case iPhone = "device.iphone", iPad = "device.ipad", mac = "device.mac"
    case tv = "device.tv", vision = "device.vision", watch = "device.watch"

    static let prefix = "ca.wilsonlam.bricks."
    var id: String { Achievement.prefix + rawValue }

    /// Theme's brick colours by name (face, shade), which `Info.color` picks from.
    static let palette: [String: (face: UInt32, shade: UInt32)] = [
        "blush": (0xFFA8C5, 0xE98BA9), "coral": (0xFFB59E, 0xE99A82), "apricot": (0xFFCF9E, 0xE9B482),
        "butter": (0xF3DE84, 0xDCC46A), "mint": (0xA8E6B8, 0x8DCB9D), "aqua": (0x8FDDE7, 0x74C2CC),
        "cornflower": (0xA6BDF7, 0x8BA2DC), "lilac": (0xC8AEF0, 0xAD93D5),
    ]

    struct Info {
        let name: String
        /// Shown before it's earned (hidden ones show only once earned).
        let goal: String
        let earned: String
        let points: Int
        let hidden: Bool
        /// Badge artwork: an SF Symbol or short text, on a palette colour from Theme.
        let symbol: String
        let label: String?
        let color: String
    }

    var info: Info {
        func i(_ name: String, _ goal: String, _ earned: String, _ points: Int, _ symbol: String,
               _ color: String, label: String? = nil, hidden: Bool = false) -> Info {
            Info(name: name, goal: goal, earned: earned, points: points, hidden: hidden,
                 symbol: symbol, label: label, color: color)
        }
        switch self {
        case .score100:   return i("Off the Ground", "Score 100 points in one game.", "You scored 100 points in one game.", 5, "star.fill", "cornflower", label: "100")
        case .score500:   return i("Warming Up", "Score 500 points in one game.", "You scored 500 points in one game.", 10, "star.fill", "cornflower", label: "500")
        case .score1000:  return i("Party Time", "Score 1,000 points in one game.", "1,000 points and your first celebration.", 15, "star.fill", "cornflower", label: "1K")
        case .score2500:  return i("High Roller", "Score 2,500 points in one game.", "You scored 2,500 points in one game.", 20, "star.fill", "cornflower", label: "2.5K")
        case .score5000:  return i("Brick Star", "Score 5,000 points in one game.", "You scored 5,000 points in one game.", 30, "star.fill", "cornflower", label: "5K")
        case .score10000: return i("Five Digits", "Score 10,000 points in one game.", "You scored 10,000 points in one game.", 40, "star.fill", "cornflower", label: "10K")
        case .score25000: return i("Legend of the Grid", "Score 25,000 points in one game.", "25,000 points in one game. Legendary.", 60, "crown.fill", "butter", label: "25K")

        case .lines1:     return i("First Clear", "Clear a line.", "You cleared your first line.", 5, "line.3.horizontal", "mint", label: "1")
        case .lines50:    return i("Tidy", "Clear 50 lines.", "You've cleared 50 lines.", 10, "line.3.horizontal", "mint", label: "50")
        case .lines250:   return i("Neat Freak", "Clear 250 lines.", "You've cleared 250 lines.", 15, "line.3.horizontal", "mint", label: "250")
        case .lines1000:  return i("Line Cleaner", "Clear 1,000 lines.", "You've cleared 1,000 lines.", 25, "line.3.horizontal", "mint", label: "1K")
        case .lines5000:  return i("Sweeper Supreme", "Clear 5,000 lines.", "You've cleared 5,000 lines.", 40, "sparkles", "mint", label: "5K")

        case .gameLines50:  return i("Long Haul", "Clear 50 lines in one game.", "50 lines in one game.", 20, "flag.fill", "aqua", label: "50")
        case .gameLines150: return i("Marathon", "Clear 150 lines in one game.", "150 lines in one game.", 35, "flag.checkered", "aqua", label: "150")

        case .double:      return i("Double", "Clear 2 lines with one piece.", "Two lines with one piece.", 10, "square.stack", "blush", label: "×2")
        case .triple:      return i("Triple", "Clear 3 lines with one piece.", "Three lines with one piece.", 15, "square.stack.3d.up", "blush", label: "×3")
        case .quad:        return i("Quad", "Clear 4 lines with one piece.", "Four lines with one piece.", 25, "square.stack.3d.up.fill", "blush", label: "×4")
        case .spectacular: return i("Spectacular", "Clear 5 or more lines with one piece.", "Five lines with one piece!", 35, "burst.fill", "blush", label: "×5", hidden: true)
        case .crossroads:  return i("Crossroads", "Clear a row and a column with one piece.", "A row and a column, both at once.", 10, "plus", "lilac")
        case .cleanSlate:  return i("Clean Slate", "Clear every brick off the board.", "Not a brick left on the board.", 40, "sparkles", "aqua", hidden: true)
        case .closeCall:   return i("Close Call", "Clear a line with 70 or more squares filled.", "Cleared a line from a nearly full board.", 20, "exclamationmark.triangle.fill", "apricot", hidden: true)

        case .streak5:  return i("On a Roll", "Clear lines with 5 pieces in a row.", "Five clearing pieces in a row.", 20, "flame.fill", "coral", label: "5")
        case .streak10: return i("Unstoppable", "Clear lines with 10 pieces in a row.", "Ten clearing pieces in a row.", 30, "flame.fill", "coral", label: "10")

        case .pieces1:    return i("First Brick", "Place a piece.", "Your first piece is down.", 5, "square.fill", "butter")
        case .pieces500:  return i("Builder", "Place 500 pieces.", "You've placed 500 pieces.", 10, "square.grid.2x2.fill", "butter", label: "500")
        case .pieces5000: return i("Architect", "Place 5,000 pieces.", "You've placed 5,000 pieces.", 30, "building.columns.fill", "butter", label: "5K")
        case .fullSet:    return i("Full Set", "Place all nine kinds of piece in one game.", "Every kind of piece in one game.", 15, "square.grid.3x3.fill", "butter")

        case .games10:  return i("Regular", "Play 10 games.", "You've played 10 games.", 10, "gamecontroller.fill", "lilac", label: "10")
        case .games50:  return i("Devoted", "Play 50 games.", "You've played 50 games.", 20, "gamecontroller.fill", "lilac", label: "50")
        case .games200: return i("Brick Addict", "Play 200 games.", "You've played 200 games.", 40, "heart.fill", "lilac", label: "200")
        case .days7:    return i("Week of Bricks", "Play on 7 different days.", "You've played on 7 different days.", 15, "calendar", "cornflower", label: "7")
        case .days30:   return i("Habit Forming", "Play on 30 different days.", "You've played on 30 different days.", 30, "calendar", "cornflower", label: "30")

        case .gift1:        return i("Unwrapped", "Claim a gift.", "You claimed your first gift.", 5, "gift.fill", "coral")
        case .gifts25:      return i("Gift Hunter", "Claim 25 gifts.", "You've claimed 25 gifts.", 15, "gift.fill", "coral", label: "25")
        case .gifts100:     return i("Santa's Helper", "Claim 100 gifts.", "You've claimed 100 gifts.", 30, "gift.fill", "coral", label: "100")
        case .doubleGift:   return i("Double Delivery", "Claim two gifts with one piece.", "Two gifts with one piece.", 20, "gift.fill", "blush", label: "×2")
        case .fullyStocked: return i("Fully Stocked", "Hold 5 of every power-up.", "Every power-up, five times over.", 30, "shippingbox.fill", "apricot", hidden: true)

        case .hammer:    return i("Smash", "Use a hammer.", "Smashed a brick with the hammer.", 5, "hammer.fill", "coral")
        case .bomb:      return i("Kaboom", "Use a bomb.", "Blew up bricks with a bomb.", 5, "burst.fill", "blush")
        case .shuffle:   return i("Fresh Hand", "Use a shuffle.", "Shuffled your pieces.", 5, "shuffle", "aqua")
        case .rotate:    return i("Twist", "Use a rotate.", "Turned your pieces around.", 5, "arrow.clockwise", "mint")
        case .undo:      return i("Second Thoughts", "Use an undo.", "Took a move back.", 5, "arrow.uturn.backward", "lilac")
        case .toolbox:   return i("Toolbox", "Use all five power-ups in one game.", "All five power-ups in one game.", 15, "wrench.and.screwdriver.fill", "apricot")
        case .directHit: return i("Direct Hit", "Blow up 9 bricks with one bomb.", "Nine bricks, one bomb.", 10, "scope", "blush", hidden: true)
        case .purist:    return i("Purist", "Score 2,500 in a game without using a power-up.", "2,500 points, no power-ups.", 30, "hand.raised.fill", "cornflower")

        case .lightShow: return i("Light Show", "See every celebration colour.", "You've seen every celebration colour.", 20, "rainbow", "lilac")

        case .iPhone: return i("Pocket Puzzler", "Play on iPhone.", "You played on iPhone.", 5, "iphone", "aqua")
        case .iPad:   return i("Big Board", "Play on iPad.", "You played on iPad.", 5, "ipad", "aqua")
        case .mac:    return i("Desk Job", "Play on a Mac.", "You played on a Mac.", 10, "macbook", "aqua")
        case .tv:     return i("Couch Co-op", "Play on Apple TV.", "You played on Apple TV.", 10, "appletv.fill", "aqua")
        case .vision: return i("Spatial Bricks", "Play on Apple Vision Pro.", "You played on Apple Vision Pro.", 10, "visionpro", "aqua")
        case .watch:  return i("On Your Wrist", "Play on Apple Watch.", "You played on Apple Watch.", 10, "applewatch", "aqua")
        }
    }

    /// How far along the player is, 0...100, which is what Game Center takes.
    func percent(_ s: PlayerStats) -> Double {
        func of(_ value: Int, _ goal: Int) -> Double { min(100, Double(value) * 100 / Double(goal)) }
        func flag(_ done: Bool) -> Double { done ? 100 : 0 }
        switch self {
        case .score100:   return of(s.bestScore, 100)
        case .score500:   return of(s.bestScore, 500)
        case .score1000:  return of(s.bestScore, 1000)
        case .score2500:  return of(s.bestScore, 2500)
        case .score5000:  return of(s.bestScore, 5000)
        case .score10000: return of(s.bestScore, 10000)
        case .score25000: return of(s.bestScore, 25000)
        case .lines1:     return of(s.lines, 1)
        case .lines50:    return of(s.lines, 50)
        case .lines250:   return of(s.lines, 250)
        case .lines1000:  return of(s.lines, 1000)
        case .lines5000:  return of(s.lines, 5000)
        case .gameLines50:  return of(s.bestGameLines, 50)
        case .gameLines150: return of(s.bestGameLines, 150)
        case .double:      return flag(s.biggestClear >= 2)
        case .triple:      return flag(s.biggestClear >= 3)
        case .quad:        return flag(s.biggestClear >= 4)
        case .spectacular: return flag(s.biggestClear >= 5)
        case .streak5:  return of(s.bestStreak, 5)
        case .streak10: return of(s.bestStreak, 10)
        case .pieces1:    return of(s.pieces, 1)
        case .pieces500:  return of(s.pieces, 500)
        case .pieces5000: return of(s.pieces, 5000)
        case .games10:  return of(s.games, 10)
        case .games50:  return of(s.games, 50)
        case .games200: return of(s.games, 200)
        case .days7:    return of(s.days.count, 7)
        case .days30:   return of(s.days.count, 30)
        case .gift1:    return of(s.gifts, 1)
        case .gifts25:  return of(s.gifts, 25)
        case .gifts100: return of(s.gifts, 100)
        case .hammer, .bomb, .shuffle, .rotate, .undo:
            return flag(s.powerUpsUsed.contains(String(rawValue.dropFirst("power.".count))))
        case .lightShow: return of(s.celebrations.count, PlayerStats.celebrationCount)
        case .iPhone, .iPad, .mac, .tv, .vision, .watch:
            return flag(s.devices.contains(String(rawValue.dropFirst("device.".count))))
        case .fullSet, .crossroads, .cleanSlate, .closeCall, .doubleGift, .fullyStocked,
             .toolbox, .directHit, .purist:
            return flag(s.feats.contains(rawValue))
        }
    }
}

enum Leaderboard: String, CaseIterable {
    case highScore = "lb.high_score"
    case daily = "lb.daily"
    case weekly = "lb.weekly"
    case gameLines = "lb.game_lines"
    case bestMove = "lb.best_move"
    case lifetimeLines = "lb.lifetime_lines"

    var id: String { Achievement.prefix + rawValue }

    struct Info {
        let name: String
        let description: String
        /// One "point" or "line", and more than one.
        let unit: (one: String, many: String)
        /// Best score each period, or the latest total.
        let keepsBest: Bool
        /// How long each round lasts and how often a new one starts, for leaderboards
        /// that start over (App Store Connect's format); nil for all-time.
        let recurrence: (duration: String, rule: String)?
        let symbol: String
        let color: String
    }

    var info: Info {
        switch self {
        case .highScore:     return Info(name: "High Score", description: "Your best game ever.", unit: (" point", " points"), keepsBest: true, recurrence: nil, symbol: "trophy.fill", color: "butter")
        case .daily:         return Info(name: "Today's Best", description: "Best game today. Starts over every day.", unit: (" point", " points"), keepsBest: true, recurrence: ("PT24H", "FREQ=DAILY;INTERVAL=1"), symbol: "sun.max.fill", color: "apricot")
        case .weekly:        return Info(name: "This Week", description: "Best game this week. Starts over every week.", unit: (" point", " points"), keepsBest: true, recurrence: ("PT168H", "FREQ=DAILY;INTERVAL=7"), symbol: "calendar", color: "cornflower")
        case .gameLines:     return Info(name: "Most Lines in a Game", description: "The most lines cleared in one game.", unit: (" line", " lines"), keepsBest: true, recurrence: nil, symbol: "line.3.horizontal", color: "mint")
        case .bestMove:      return Info(name: "Biggest Move", description: "The most points from a single piece.", unit: (" point", " points"), keepsBest: true, recurrence: nil, symbol: "burst.fill", color: "blush")
        case .lifetimeLines: return Info(name: "Lifetime Lines", description: "Every line you've ever cleared.", unit: (" line", " lines"), keepsBest: false, recurrence: nil, symbol: "infinity", color: "lilac")
        }
    }

    func value(_ s: PlayerStats) -> Int {
        switch self {
        case .highScore, .daily, .weekly: return s.game.score
        case .gameLines: return s.game.lines
        case .bestMove: return s.game.bestMove
        case .lifetimeLines: return s.lines
        }
    }
}

/// Game Center challenges (players send them to friends from the Games app), each built
/// on a leaderboard.
enum Challenge: String, CaseIterable {
    case beatMyScore = "challenge.beat_my_score"
    case lineShowdown = "challenge.line_showdown"

    var id: String { Achievement.prefix + rawValue }
    var leaderboard: Leaderboard { self == .beatMyScore ? .highScore : .gameLines }
    var name: String { self == .beatMyScore ? "Beat My Score" : "Line Showdown" }
    var description: String {
        self == .beatMyScore ? "Score more than your friends in one game." : "Clear more lines than your friends in one game."
    }
}

/// The Game Center activity the Games app offers to start a game with.
enum GameActivity {
    static let id = Achievement.prefix + "activity.classic"
    static let name = "Classic Game"
    static let description = "Fill rows and columns to clear them. How high can you score?"
}

/// Everything the achievements are measured against, kept across launches.
struct PlayerStats: Codable, Equatable {
    static let celebrationCount = 7

    var bestScore = 0
    var bestGameLines = 0
    var lines = 0
    var pieces = 0
    var games = 0
    var gifts = 0
    /// Most lines one piece has cleared.
    var biggestClear = 0
    var bestStreak = 0
    /// Days with at least one piece placed, as "y-m-d".
    var days: Set<String> = []
    var celebrations: Set<Int> = []
    var powerUpsUsed: Set<String> = []
    /// Platform.device values the player has placed a piece on.
    var devices: Set<String> = []
    /// One-off achievements, by raw value.
    var feats: Set<String> = []
    var game = GameStats()

    struct GameStats: Codable, Equatable {
        var score = 0
        var lines = 0
        var pieces = 0
        var streak = 0
        var bestMove = 0
        var families: Set<Int> = []
        var powerUps: Set<String> = []
        /// Already counted in `games`, by game over.
        var counted = false
    }

    mutating func record(_ event: GameEvent, device: String, day: String) {
        switch event {
        case .newGame:
            countGame()
            game = GameStats()

        case .placed(let family):
            pieces += 1
            game.pieces += 1
            game.families.insert(family)
            if game.families.count >= 9 { feats.insert(Achievement.fullSet.rawValue) }
            days.insert(day)
            devices.insert(device)

        case let .cleared(rows, cols, gifts, filled, emptied, points):
            let count = rows + cols
            lines += count
            game.lines += count
            bestGameLines = max(bestGameLines, game.lines)
            biggestClear = max(biggestClear, count)
            game.streak += 1
            bestStreak = max(bestStreak, game.streak)
            game.bestMove = max(game.bestMove, points)
            if rows > 0 && cols > 0 { feats.insert(Achievement.crossroads.rawValue) }
            if emptied { feats.insert(Achievement.cleanSlate.rawValue) }
            if filled >= 70 { feats.insert(Achievement.closeCall.rawValue) }
            if gifts >= 2 { feats.insert(Achievement.doubleGift.rawValue) }

        case .missed:
            game.streak = 0

        case .score(let score):
            game.score = score
            bestScore = max(bestScore, score)
            if score >= 2500 && game.powerUps.isEmpty { feats.insert(Achievement.purist.rawValue) }

        case .giftClaimed(let stock):
            gifts += 1
            if !stock.isEmpty && stock.allSatisfy({ $0 >= 5 }) { feats.insert(Achievement.fullyStocked.rawValue) }

        case let .usedPowerUp(name, bricks):
            powerUpsUsed.insert(name)
            game.powerUps.insert(name)
            if game.powerUps.count >= 5 { feats.insert(Achievement.toolbox.rawValue) }
            if name == "bomb" && bricks >= 9 { feats.insert(Achievement.directHit.rawValue) }

        case .celebration(let index):
            celebrations.insert(index)

        case .gameOver:
            countGame()
        }
    }

    /// A game counts once, when it ends or is abandoned with a piece on the board.
    private mutating func countGame() {
        guard !game.counted, game.pieces > 0 else { return }
        games += 1
        game.counted = true
    }

    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(d.year ?? 0)-\(d.month ?? 0)-\(d.day ?? 0)"
    }
}
