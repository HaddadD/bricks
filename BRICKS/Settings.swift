import SwiftUI

/// The handful of preferences behind the gear icon. Each one writes straight to
/// `UserDefaults`, so a choice survives quitting the app the same way a game does.
final class Settings: ObservableObject {

    private enum Key {
        static let dark = "bricks.darkMode"
        static let vibrations = "bricks.vibrations"
        static let floatPieces = "bricks.floatPieces"
        static let sensory = "bricks.sensory"
        static let sensoryMode = "bricks.sensoryMode"
        static let runnerStyle = "bricks.runnerStyle"
    }

    @Published var isDark: Bool {
        didSet { UserDefaults.standard.set(isDark, forKey: Key.dark) }
    }

    @Published var vibrations: Bool {
        didSet {
            UserDefaults.standard.set(vibrations, forKey: Key.vibrations)
            Haptics.enabled = vibrations
        }
    }

    /// Whether a dragged piece floats above the finger instead of sitting under it. On by
    /// default. It only applies, and is only offered, on an iPhone with room under the
    /// board for it; elsewhere it's off without touching this, so the player's choice is
    /// back whenever the room is.
    @Published var floatPieces: Bool {
        didSet { UserDefaults.standard.set(floatPieces, forKey: Key.floatPieces) }
    }

    /// Whether the widget (Home Screen, StandBy, CarPlay) may show the game. iPhone and
    /// iPad only; the setting lives in the App Group so the widget can see it too.
    @Published var widgetEnabled: Bool {
        didSet { WidgetSnapshot.isEnabled = widgetEnabled }
    }

    #if os(iOS)
    /// Sensory enhancement: something to watch under the board, which can also float in
    /// Picture in Picture. Off by default. iPhone and iPad only.
    @Published var sensory: Bool {
        didSet { UserDefaults.standard.set(sensory, forKey: Key.sensory) }
    }

    /// What plays: the runner, or one of the satisfying shows.
    @Published var sensoryMode: SensoryMode {
        didSet { UserDefaults.standard.set(sensoryMode.rawValue, forKey: Key.sensoryMode) }
    }

    /// Which world the runner runs through. Kept while something else is chosen.
    @Published var runnerStyle: RunnerStyle {
        didSet { UserDefaults.standard.set(runnerStyle.rawValue, forKey: Key.runnerStyle) }
    }
    #endif

    init() {
        let defaults = UserDefaults.standard
        isDark = defaults.bool(forKey: Key.dark)
        // Vibrations default to on, so read the stored value only once one exists.
        vibrations = defaults.object(forKey: Key.vibrations) as? Bool ?? true
        // On until the player says otherwise. `bool(forKey:)` also reads a launch
        // argument's "NO", which `as? Bool` wouldn't.
        floatPieces = defaults.object(forKey: Key.floatPieces) == nil ? true : defaults.bool(forKey: Key.floatPieces)
        widgetEnabled = WidgetSnapshot.isEnabled
        #if os(iOS)
        sensory = defaults.bool(forKey: Key.sensory)
        sensoryMode = defaults.string(forKey: Key.sensoryMode).flatMap(SensoryMode.init) ?? .runner
        runnerStyle = defaults.string(forKey: Key.runnerStyle).flatMap(RunnerStyle.init) ?? .trail
        #endif
        Haptics.enabled = vibrations
    }

    var colorScheme: ColorScheme { isDark ? .dark : .light }
}
