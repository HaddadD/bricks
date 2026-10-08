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
}

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

    static let backgroundTop = Color(hex: 0xFDF7F2)
    static let backgroundBottom = Color(hex: 0xF0E8F4)

    /// Shown behind the board for 200 points after each 1000-point milestone.
    static let celebrationTop = Color(hex: 0xA0E2E1)
    static let celebrationBottom = Color(hex: 0x61CFCD)

    static let boardBackground = Color(hex: 0xF6EDE6)
    static let emptyCell = Color(hex: 0xE7DCD3)
    static let emptyCellHighlight = Color(hex: 0xD6C8BD)

    static let ink = Color(hex: 0x5C5059)
    static let inkSoft = Color(hex: 0x9A8D95)

    static let gift = Color(hex: 0xFF7FA6)
    static let giftGlow = Color(hex: 0xFFD4E2)

    /// Very light brown, for the version stamp under the board.
    static let versionInk = Color(hex: 0xCBBAAE)

    static let trayWell = Color(hex: 0xF6EDE6)
    static let chip = Color(hex: 0xFFFFFF)
    static let chipActive = Color(hex: 0xFFE6EF)

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
