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

    var tint: Color {
        switch self {
        case .hammer:  return Color(hex: 0xFFB59E)
        case .bomb:    return Color(hex: 0xFFA8C5)
        case .shuffle: return Color(hex: 0x8FDDE7)
        case .rotate:  return Color(hex: 0xA8E6B8)
        case .undo:    return Color(hex: 0xC8AEF0)
        }
    }

    /// Instant power-ups fire the moment they are tapped; the others wait for a target.
    var isInstant: Bool {
        switch self {
        case .shuffle, .undo: return true
        case .hammer, .bomb, .rotate: return false
        }
    }

    /// What to do next once armed, in the words of each platform's controls.
    var targetHint: String {
        switch (self, Platform.input) {
        case (.hammer, .drag), (.hammer, .tap): return String(localized: "Tap a brick to smash it")
        case (.hammer, .remote):                return String(localized: "Move to a brick and press to smash it")
        case (.bomb, .drag), (.bomb, .tap):     return String(localized: "Tap the board to blast a 3×3 area")
        case (.bomb, .remote):                  return String(localized: "Move to a spot and press to blast it")
        case (.rotate, .drag):                  return String(localized: "Tap to turn all three — drag a piece when done")
        case (.rotate, .remote):                return String(localized: "Press a piece to turn all three — Menu when done")
        case (.rotate, .tap):                   return String(localized: "Tap a piece to turn all three")
        case (.shuffle, _), (.undo, _):         return ""
        }
    }
}
