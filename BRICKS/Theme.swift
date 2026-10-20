import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// A colour that resolves differently in light and dark mode. The scheme comes from
    /// the view's trait collection, which the root view drives from the user's setting,
    /// so every surface flips without any call site knowing about it.
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        // The headless rule tests build for macOS, where appearance does not matter.
        return Color(hex: light)
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

/// Pastel palette for BRICKS!
enum Theme {

    // Nine pastel block colours — one per piece family.
    static let blocks: [Color] = [
        Color(hex: 0xFFA8C5), // blush
        Color(hex: 0xFFB59E), // coral
        Color(hex: 0xFFCF9E), // apricot
        Color(hex: 0xF3DE84), // butter
        Color(hex: 0xA8E6B8), // mint
        Color(hex: 0x8FDDE7), // aqua
        Color(hex: 0xA6BDF7), // cornflower
        Color(hex: 0xC8AEF0), // lilac
        Color(hex: 0x7FCDCD)  // teal
    ]

    /// Slightly deeper version of each block colour, used for the bottom bevel.
    static let blockShades: [Color] = [
        Color(hex: 0xE98BA9),
        Color(hex: 0xE99A82),
        Color(hex: 0xE9B482),
        Color(hex: 0xDCC46A),
        Color(hex: 0x8DCB9D),
        Color(hex: 0x74C2CC),
        Color(hex: 0x8BA2DC),
        Color(hex: 0xAD93D5),
        Color(hex: 0x63B0B0)
    ]

    static let backgroundTop = Color.adaptive(0xFDF7F2, 0x241F2E)
    static let backgroundBottom = Color.adaptive(0xF0E8F4, 0x191622)

    /// Backgrounds shown for 200 points after each 1000-point milestone.
    /// One is picked at random each time, never the same one twice running.
    struct Celebration {
        let name: String
        let top: Color
        let bottom: Color
    }

    /// Every celebration fades to the same near-white foot, which keeps the tray
    /// readable whatever colour is running at the top.
    static let celebrationFoot = Color.adaptive(0xFCFCFB, 0x191622)

    static let celebrations: [Celebration] = [
        Celebration(name: "blush",  top: Color(hex: 0xFFA3C6), bottom: celebrationFoot),
        Celebration(name: "coral",  top: Color(hex: 0xFFB098), bottom: celebrationFoot),
        Celebration(name: "teal",   top: Color(hex: 0xA0E2E1), bottom: celebrationFoot),
        Celebration(name: "aqua",   top: Color(hex: 0x73DFE8), bottom: celebrationFoot),
        Celebration(name: "mint",   top: Color(hex: 0x95E8B4), bottom: celebrationFoot),
        Celebration(name: "yellow", top: Color(hex: 0xF8DC74), bottom: celebrationFoot),
        Celebration(name: "lilac",  top: Color(hex: 0xCCACF5), bottom: celebrationFoot)
    ]

    static func celebration(_ index: Int?) -> Celebration {
        celebrations[(index ?? 0) % celebrations.count]
    }

    static let boardBackground = Color.adaptive(0xF6EDE6, 0x2E2839)
    static let emptyCell = Color.adaptive(0xE7DCD3, 0x3B3449)
    static let emptyCellHighlight = Color.adaptive(0xD6C8BD, 0x4C4360)

    static let ink = Color.adaptive(0x5C5059, 0xF2EDF5)
    static let inkSoft = Color.adaptive(0x9A8D95, 0xA79DB3)

    static let gift = Color.adaptive(0xFF7FA6, 0xFF8FB2)
    static let giftGlow = Color.adaptive(0xFFD4E2, 0x5A2F42)

    /// Very light brown, for the version stamp under the board.
    static let versionInk = Color.adaptive(0xCBBAAE, 0x5B5170)

    static let trayWell = Color.adaptive(0xF6EDE6, 0x2E2839)
    static let chip = Color.adaptive(0xFFFFFF, 0x332C40)
    static let chipActive = Color.adaptive(0xFFE6EF, 0x45374F)
    /// Raised surfaces: the game-over card, the settings sheet, the toast capsule.
    static let card = Color.adaptive(0xFFFFFF, 0x2A2436)
    static let chipBorder = Color.adaptive(0xE6DAD1, 0x453D54)
    static let shadow = Color.adaptive(0xC9B8AC, 0x000000)

    /// Palette slot for each of the nine piece families, ordered so that pieces which
    /// are easy to confuse by silhouette — the bars especially — land on clearly
    /// different hues rather than neighbouring ones.
    private static let familyPalette = [8, 5, 3, 6, 1, 4, 7, 2, 0]

    static func familyColor(_ family: Int) -> Int {
        familyPalette[family % familyPalette.count]
    }

    static func block(_ index: Int) -> Color { blocks[index % blocks.count] }
    static func shade(_ index: Int) -> Color { blockShades[index % blockShades.count] }
}

/// A single rounded pastel brick, used on the board, in the tray and while dragging.
struct BrickView: View {
    let colorIndex: Int
    let size: CGFloat
    var giftMovesLeft: Int? = nil

    private var corner: CGFloat { max(3, size * 0.22) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Theme.shade(colorIndex))

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.block(colorIndex).opacity(0.98), Theme.block(colorIndex)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.bottom, max(1, size * 0.09))

            RoundedRectangle(cornerRadius: corner * 0.8, style: .continuous)
                .fill(Color.white.opacity(0.35))
                .padding(.horizontal, size * 0.16)
                .padding(.top, size * 0.13)
                .frame(height: size * 0.2)
                .frame(maxHeight: .infinity, alignment: .top)

            if let movesLeft = giftMovesLeft {
                GiftMark(movesLeft: movesLeft, size: size, onBrick: true)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The gift marker: a wrapped-gift glyph with the moves it has left before expiring.
/// Shown both on an open square and on top of the brick that covers it.
struct GiftMark: View {
    let movesLeft: Int
    let size: CGFloat
    var onBrick: Bool = false

    /// Runs hot as the gift is about to expire.
    private var urgent: Bool { movesLeft <= 3 }

    var body: some View {
        ZStack {
            if !onBrick {
                Circle()
                    .fill(urgent ? Color(hex: 0xFFD0D0) : Theme.giftGlow)
                    .frame(width: size * 0.95, height: size * 0.95)
            }

            Image(systemName: "gift.fill")
                .font(.system(size: size * (onBrick ? 0.44 : 0.5), weight: .bold))
                .foregroundColor(onBrick ? .white : (urgent ? Color(hex: 0xE8555F) : Theme.gift))
                .shadow(color: onBrick ? Theme.gift.opacity(0.9) : .clear, radius: size * 0.1)
                .offset(y: -size * 0.09)

            Text("\(movesLeft)")
                .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, size * 0.09)
                .background(
                    Capsule().fill(urgent ? Color(hex: 0xE8555F) : Theme.gift)
                )
                .offset(y: size * 0.28)
        }
        .frame(width: size, height: size)
    }
}
