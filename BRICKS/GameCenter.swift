import SwiftUI
import GameKit

/// Keeps the player's stats (Achievements.swift) from the game's events, saves them, and
/// passes achievement progress and leaderboard scores on to Game Center. Works the same
/// signed out: progress is kept locally and reported once the player signs in.
@MainActor
final class PlayerProgress: ObservableObject {
    @Published private(set) var stats: PlayerStats
    /// Achievements completed since this game started, for the game-over card.
    @Published private(set) var earnedThisGame: [Achievement] = []

    private let gameCenter: GameCenter
    private static let key = "bricks.playerStats"

    init(gameCenter: GameCenter = .shared) {
        self.gameCenter = gameCenter
        stats = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(PlayerStats.self, from: $0) } ?? PlayerStats()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-gameOver") {
            earnedThisGame = [.double, .crossroads, .lines50, .gift1, .hammer]
        }
        #endif
    }

    /// Starts listening to the game. A best score from before achievements existed still
    /// counts towards the score ones.
    func attach(to model: GameModel) {
        stats.bestScore = max(stats.bestScore, model.best)
        stats.game.score = model.score
        model.onEvent = { [weak self] event in self?.record(event) }
        gameCenter.report(stats)
    }

    func record(_ event: GameEvent) {
        // An abandoned game's scores still go on the leaderboards, before they're reset.
        if event == .newGame { gameCenter.submitScores(stats) }

        let before = Set(Achievement.allCases.filter { $0.percent(stats) >= 100 })
        stats.record(event, device: Platform.device, day: PlayerStats.day(Date()))
        let newlyEarned = Achievement.allCases.filter { !before.contains($0) && $0.percent(stats) >= 100 }

        switch event {
        case .newGame:
            earnedThisGame = []
            gameCenter.gameEnded()
        case .placed:
            gameCenter.gameStarted()
        case .gameOver:
            gameCenter.submitScores(stats)
            gameCenter.gameEnded()
        default:
            break
        }
        earnedThisGame += newlyEarned

        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        gameCenter.report(stats)
    }

    /// Going to the background: put the game so far on the leaderboards.
    func checkpoint() {
        gameCenter.submitScores(stats)
    }
}

/// Signing in to Game Center, reporting to it, and showing its screens.
@MainActor
final class GameCenter: NSObject, ObservableObject {
    static let shared = GameCenter()

    @Published private(set) var isSignedIn = false
    /// The Games app asked to play (an activity or a challenge).
    var onWantsToPlay: (() -> Void)?

    /// Percent last reported for each achievement id, so only progress is sent.
    private var reported: [String: Double] =
        UserDefaults.standard.dictionary(forKey: "bricks.gc.reported") as? [String: Double] ?? [:]
    private var latest: PlayerStats?
    private var reporting: Task<Void, Never>?
    /// The GKGameActivity in progress, and what hears the Games app (iOS 26 and later).
    fileprivate var activity: AnyObject?
    private var listener: AnyObject?

    func signIn() {
        #if DEBUG
        // UI tests and screenshots run signed out, without the sign-in sheet over the game.
        if ProcessInfo.processInfo.arguments.contains("-noGameCenter") { return }
        // `-gameCenterPreview` shows the Game Center buttons without signing in.
        if ProcessInfo.processInfo.arguments.contains("-gameCenterPreview") { isSignedIn = true; return }
        #endif
        #if os(watchOS)
        GKLocalPlayer.local.authenticateHandler = { [weak self] _ in
            Task { @MainActor in self?.authenticated() }
        }
        #else
        GKLocalPlayer.local.authenticateHandler = { [weak self] signIn, _ in
            Task { @MainActor in
                if let signIn { Self.present(signIn) }
                self?.authenticated()
            }
        }
        #endif
    }

    private func authenticated() {
        let signedIn = GKLocalPlayer.local.isAuthenticated
        guard signedIn != isSignedIn else { return }
        isSignedIn = signedIn
        guard signedIn else { return }
        #if !os(watchOS)
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            let listener = ActivityListener()
            listener.gameCenter = self
            GKLocalPlayer.local.register(listener)
            self.listener = listener
        }
        #endif
        Task {
            // Seed from what Game Center already has (from this or another device), so
            // nothing is sent again.
            if let earned = try? await GKAchievement.loadAchievements() {
                for a in earned { reported[a.identifier] = max(reported[a.identifier] ?? 0, a.percentComplete) }
            }
            if let latest { report(latest) }
        }
    }

    // MARK: - Achievements and leaderboards

    func report(_ stats: PlayerStats) {
        latest = stats
        guard isSignedIn else { return }
        // A burst of events (a clear, a gift, a score) goes out as one report.
        reporting?.cancel()
        reporting = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await sendAchievements(stats)
        }
    }

    private func sendAchievements(_ stats: PlayerStats) async {
        var batch: [GKAchievement] = []
        for a in Achievement.allCases {
            let percent = a.percent(stats).rounded(.down)
            guard percent > (reported[a.id] ?? 0) else { continue }
            let achievement = GKAchievement(identifier: a.id)
            achievement.percentComplete = percent
            achievement.showsCompletionBanner = true
            batch.append(achievement)
        }
        guard !batch.isEmpty else { return }
        do {
            try await GKAchievement.report(batch)
            for a in batch { reported[a.identifier] = a.percentComplete }
            UserDefaults.standard.set(reported, forKey: "bricks.gc.reported")
        } catch {
            // Offline or signed out mid-game: the next report sends it again.
        }
    }

    func submitScores(_ stats: PlayerStats) {
        guard isSignedIn else { return }
        let byValue = Dictionary(grouping: Leaderboard.allCases, by: { $0.value(stats) })
        Task {
            for (value, boards) in byValue where value > 0 {
                try? await GKLeaderboard.submitScore(
                    value, context: 0, player: GKLocalPlayer.local, leaderboardIDs: boards.map(\.id)
                )
            }
        }
    }

    // MARK: - Activities

    /// A game is under way: it shows as an activity in the Games app.
    func gameStarted() {
        #if !os(watchOS)
        guard isSignedIn, activity == nil else { return }
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            activity = NSNull()   // claimed while the definition loads
            Task {
                let definitions = try? await GKGameActivityDefinition.loadGameActivityDefinitions(IDs: [GameActivity.id])
                if let definition = definitions?.first {
                    activity = try? GKGameActivity.start(definition: definition)
                } else {
                    activity = nil
                }
            }
        }
        #endif
    }

    func gameEnded() {
        #if !os(watchOS)
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            (activity as? GKGameActivity)?.end()
        }
        #endif
        activity = nil
    }

    // MARK: - Screens

    enum Screen { case dashboard, achievements, leaderboards, challenges, friends }

    /// Opens Game Center over the game. Not on Apple Watch, which has no Game Center UI.
    func show(_ screen: Screen) {
        #if !os(watchOS)
        let point = GKAccessPoint.shared
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch screen {
            case .challenges: point.triggerForChallenges {}; return
            case .friends: point.triggerForFriending {}; return
            default: break
            }
        }
        #endif
        switch screen {
        case .achievements: point.trigger(state: .achievements) {}
        case .leaderboards: point.trigger(state: .leaderboards) {}
        case .friends: point.trigger(state: .localPlayerFriendsList) {}
        case .dashboard, .challenges: point.trigger(state: .dashboard) {}
        }
        #endif
    }

    /// Challenges and friends have their own Game Center screens on iPhone, iPad and Mac.
    static var hasChallenges: Bool {
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) { return true }
        #endif
        return false
    }

    // MARK: - Presenting the sign-in sheet

    #if os(macOS)
    private static func present(_ controller: NSViewController) {
        NSApp.keyWindow?.contentViewController?.presentAsSheet(controller)
    }
    #elseif !os(watchOS)
    private static func present(_ controller: UIViewController) {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController
        var top = root
        while let shown = top?.presentedViewController { top = shown }
        top?.present(controller, animated: true)
    }
    #endif
}

#if !os(watchOS)
/// Hears the Games app's Play button for the game's activity (iOS 26 and later). The
/// listener protocol is older than activities, so this lives in its own iOS 26 type.
@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
private final class ActivityListener: NSObject, GKLocalPlayerListener {
    weak var gameCenter: GameCenter?

    func player(_ player: GKPlayer, wantsToPlay activity: GKGameActivity, completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            self.gameCenter?.play(activity)
            completionHandler(true)
        }
    }
}

extension GameCenter {
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
    fileprivate func play(_ activity: GKGameActivity) {
        (self.activity as? GKGameActivity)?.end()
        self.activity = activity
        activity.start()
        onWantsToPlay?()
    }
}
#endif
