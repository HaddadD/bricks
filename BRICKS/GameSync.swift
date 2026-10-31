import Foundation
#if os(iOS) || os(watchOS)
import WatchConnectivity
#endif

/// Carries the game in progress between every device signed in to the same iCloud
/// account, so a game started on one carries on on any other: iPhone, iPad, Mac, Apple
/// TV, Vision Pro and Apple Watch. Every save goes to iCloud's key-value store, and an
/// iPhone and its Apple Watch also hand it straight to each other, which is quicker than
/// waiting on iCloud when they're together. Whichever device played last wins, and the
/// best score is the best of them all.
final class GameSync: NSObject {
    static let shared = GameSync()

    /// The save as it travels: one dictionary, so a game and its time always arrive
    /// together.
    private enum Key {
        static let cloud = "bricks.game"
        static let game = "game"
        static let savedAt = "savedAt"
        static let best = "best"
    }

    private weak var model: GameModel?
    private let cloud = NSUbiquitousKeyValueStore.default

    func attach(to model: GameModel) {
        #if DEBUG
        // A staged board (screenshots, UI tests) stays on this device.
        let staged = ["-demo", "-celebrate", "-gameOver"]
        if ProcessInfo.processInfo.arguments.contains(where: staged.contains) { return }
        #endif
        self.model = model
        model.onSaved = { [weak self] data, savedAt in self?.send(data, savedAt: savedAt) }

        NotificationCenter.default.addObserver(
            self, selector: #selector(cloudChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud)
        refresh()

        #if os(iOS) || os(watchOS)
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        #endif
    }

    /// Picks up a game played elsewhere since this device last looked, and offers this
    /// device's game in case it's the newer one. Called at launch and on coming back to
    /// the foreground.
    func refresh() {
        guard let model else { return }
        cloud.synchronize()
        receive(cloud.dictionary(forKey: Key.cloud))
        if let data = model.savedGame, model.savedAt > Self.savedAt(of: cloud.dictionary(forKey: Key.cloud)) {
            send(data, savedAt: model.savedAt)
        }
    }

    private func package(_ data: Data, savedAt: Date) -> [String: Any] {
        [Key.game: data, Key.savedAt: savedAt.timeIntervalSince1970, Key.best: model?.best ?? 0]
    }

    private static func savedAt(of package: [String: Any]?) -> Date {
        Date(timeIntervalSince1970: package?[Key.savedAt] as? TimeInterval ?? 0)
    }

    private func send(_ data: Data, savedAt: Date) {
        let save = package(data, savedAt: savedAt)
        cloud.set(save, forKey: Key.cloud)
        #if os(iOS) || os(watchOS)
        sendToCounterpart(save)
        #endif
    }

    /// Takes a game from another device if it's newer than this one's. May arrive off
    /// the main thread.
    private func receive(_ package: [String: Any]?) {
        guard let package, let data = package[Key.game] as? Data else { return }
        let savedAt = Self.savedAt(of: package)
        let best = package[Key.best] as? Int ?? 0
        DispatchQueue.main.async { [weak self] in
            self?.model?.adopt(data, savedAt: savedAt, best: best)
        }
    }

    @objc private func cloudChanged(_ note: Notification) {
        let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
        if changed.contains(Key.cloud) { receive(cloud.dictionary(forKey: Key.cloud)) }
    }
}

// MARK: - iPhone and Apple Watch, directly

#if os(iOS) || os(watchOS)
extension GameSync: WCSessionDelegate {
    /// The session's application context keeps only the latest save and arrives whenever
    /// the other side next runs, straight away if it's open.
    private func sendToCounterpart(_ save: [String: Any]) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #else
        guard session.isCompanionAppInstalled else { return }
        #endif
        try? session.updateApplicationContext(save)
    }

    /// Once the session is up: take whatever arrived while this side was closed, then
    /// offer this side's game in case it's the newer one.
    private func activated(_ session: WCSession) {
        receive(session.receivedApplicationContext)
        DispatchQueue.main.async { [weak self] in
            guard let self, let model = self.model, let data = model.savedGame else { return }
            self.sendToCounterpart(self.package(data, savedAt: model.savedAt))
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if state == .activated { activated(session) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        receive(context)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { }

    /// Switching to another watch deactivates the session; start one for the new watch.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// A watch was just paired or the watch app installed: offer it the game.
    func sessionWatchStateDidChange(_ session: WCSession) {
        if session.activationState == .activated { activated(session) }
    }
    #endif
}
#endif
