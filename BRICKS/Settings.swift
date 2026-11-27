import SwiftUI

/// The handful of preferences behind the gear icon. Each one writes straight to
/// `UserDefaults`, so a choice survives quitting the app the same way a game does.
final class Settings: ObservableObject {

    private enum Key {
        static let dark = "bricks.darkMode"
        static let vibrations = "bricks.vibrations"
        static let floatPieces = "bricks.floatPieces"
        static let sounds = "bricks.sounds"
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

    /// Whether a dragged piece floats above the finger, pointer or pinch instead of
    /// sitting under it. Offered wherever pieces are dragged; on by default on iPhone.
    @Published var floatPieces: Bool {
        didSet { UserDefaults.standard.set(floatPieces, forKey: Key.floatPieces) }
    }

    /// Whether the widget (Home Screen, StandBy, CarPlay) may show the game. iPhone and
    /// iPad only; the setting lives in the App Group so the widget can see it too.
    @Published var widgetEnabled: Bool {
        didSet { WidgetSnapshot.isEnabled = widgetEnabled }
    }

    @Published var sounds: Bool {
        didSet {
            UserDefaults.standard.set(sounds, forKey: Key.sounds)
            Sound.enabled = sounds
        }
    }

    init() {
        let defaults = UserDefaults.standard
        isDark = defaults.bool(forKey: Key.dark)
        // Vibrations and sounds default to on, so read the stored value only once one exists.
        vibrations = defaults.object(forKey: Key.vibrations) as? Bool ?? true
        // On iPhone, on until the player says otherwise; elsewhere a pointer, pinch or
        // big iPad cell hides less, so it's off until asked for. `bool(forKey:)` also
        // reads a launch argument's "NO", which `as? Bool` wouldn't.
        floatPieces = defaults.object(forKey: Key.floatPieces) == nil ? Platform.isPhone : defaults.bool(forKey: Key.floatPieces)
        widgetEnabled = WidgetSnapshot.isEnabled
        sounds = defaults.object(forKey: Key.sounds) as? Bool ?? true
        Haptics.enabled = vibrations
        Sound.enabled = sounds
    }

    var colorScheme: ColorScheme { isDark ? .dark : .light }
}
