import SwiftUI

enum PowerUp: String, CaseIterable, Identifiable {
    case hammer
    case bomb
    case shuffle
    case rotate
    case undo

    var id: String { rawValue }

    static let maxPerType = 5

    var title: String {
        switch self {
        case .hammer:  return String(localized: "Hammer")
        case .bomb:    return String(localized: "Bomb")
        case .shuffle: return String(localized: "Shuffle")
        case .rotate:  return String(localized: "Rotate")
        case .undo:    return String(localized: "Undo")
        }
    }

    var icon: String {
        switch self {
        case .hammer:  return "hammer.fill"
        case .bomb:    return "burst.fill"
        case .shuffle: return "shuffle"
        case .rotate:  return "arrow.clockwise"
        case .undo:    return "arrow.uturn.backward"
        }
    }

    var tintHex: UInt32 {
        switch self {
        case .hammer:  return 0xFFB59E
        case .bomb:    return 0xFFA8C5
        case .shuffle: return 0x8FDDE7
        case .rotate:  return 0xA8E6B8
        case .undo:    return 0xC8AEF0
        }
    }

    var tint: Color { Color(hex: tintHex) }

    /// The same colour taken deep enough to carry white text, for a banner filled with
    /// it rather than merely outlined in it.
    var bannerTint: Color { Color(hex: tintHex, deepened: 0.66) }

    /// Instant power-ups fire the moment they are tapped; the others wait for a target.
    var isInstant: Bool {
        switch self {
        case .shuffle, .undo: return true
        case .hammer, .bomb, .rotate: return false
        }
    }

    /// One line on what it does, for the how-to-play deck.
    var summary: String {
        switch self {
        case .hammer:  return String(localized: "Smash a single brick")
        case .bomb:    return String(localized: "Clear a 3×3 area — aim it, then confirm")
        case .shuffle: return String(localized: "Deal three new pieces")
        case .rotate:  return String(localized: "Turn all three pieces a quarter turn, as often as you like")
        case .undo:    return String(localized: "Rewind your last move, the pieces you were holding and all")
        }
    }

    /// What to do next once armed, in the words of each platform's controls.
    ///
    /// The bomb's is only its first step — aiming. Confirming it is `confirmHint`.
    var targetHint: String {
        switch (self, Platform.input) {
        case (.hammer, .drag), (.hammer, .tap): return String(localized: "Tap a brick to smash it")
        case (.hammer, .remote):                return String(localized: "Move to a brick and press to smash it")
        case (.bomb, .drag), (.bomb, .tap):     return String(localized: "Tap where you want the 3×3 blast")
        case (.bomb, .remote):                  return String(localized: "Move to a spot and press to aim the blast")
        case (.rotate, .drag):                  return String(localized: "Tap to turn all three — drag a piece when done")
        case (.rotate, .remote):                return String(localized: "Press a piece to turn all three — Menu when done")
        case (.rotate, .tap):                   return String(localized: "Tap a piece to turn all three")
        case (.shuffle, _), (.undo, _):         return ""
        }
    }

    /// The second step, for a power-up that asks twice before it fires. Only the bomb
    /// does: nine bricks is a lot to lose to a fat finger.
    var confirmHint: String {
        switch Platform.input {
        case .remote:     return String(localized: "Press again to set it off")
        case .drag, .tap: return String(localized: "Tap the tick to set it off")
        }
    }
}
