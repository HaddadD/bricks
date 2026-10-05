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
        case .hammer:  return "Hammer"
        case .bomb:    return "Bomb"
        case .shuffle: return "Shuffle"
        case .rotate:  return "Rotate"
        case .undo:    return "Undo"
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

    var targetHint: String {
        switch self {
        case .hammer:  return "Tap a brick to smash it"
        case .bomb:    return "Tap the board to blast a 3×3 area"
        case .rotate:  return "Tap to turn all three — drag a piece when done"
        case .shuffle, .undo: return ""
        }
    }
}
