import SwiftUI

/// The handful of preferences behind the gear icon. Each one writes straight to
/// `UserDefaults`, so a choice survives quitting the app the same way a game does.
final class Settings: ObservableObject {

    private enum Key {
        static let dark = "bricks.darkMode"
        static let vibrations = "bricks.vibrations"
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

    init() {
        let defaults = UserDefaults.standard
        isDark = defaults.bool(forKey: Key.dark)
        // Vibrations default to on, so read the stored value only once one exists.
        vibrations = defaults.object(forKey: Key.vibrations) as? Bool ?? true
        Haptics.enabled = vibrations
    }

    var colorScheme: ColorScheme { isDark ? .dark : .light }
}
