#if os(iOS)
import SwiftUI

/// The widget's face: the board in progress with the score, drawn with the game's own
/// bricks. Small (Home Screen, StandBy, CarPlay) shows the board under a score line;
/// medium puts the score and best beside it. Shared with the app so `-widgetPreview`
/// can show it in DEBUG builds.
struct WidgetFace: View {
    /// nil when there's nothing to show yet.
    let snapshot: WidgetSnapshot?
    let enabled: Bool
    let wide: Bool

    var body: some View {
        if !enabled {
            off
        } else if wide {
            HStack(spacing: 14) {
                MiniBoard(cells: snapshot?.cells)
                VStack(alignment: .leading, spacing: 4) {
                    title(size: 20)
                    Spacer(minLength: 0)
                    stat("SCORE", snapshot?.score)
                    stat("BEST", snapshot?.best)
                    if snapshot?.isGameOver == true {
                        Text("No more moves")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    title(size: 14)
                    Spacer(minLength: 4)
                    Text(snapshot.map { "\($0.score)" } ?? "")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                MiniBoard(cells: snapshot?.cells)
            }
        }
    }

    private func title(size: CGFloat) -> some View {
        Text("BRICKS!")
            .font(.system(size: size, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(colors: [Color(hex: 0xF08FB4), Color(hex: 0xA6BDF7)], startPoint: .leading, endPoint: .trailing)
            )
            .lineLimit(1)
    }

    private func stat(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.inkSoft)
            Text(value.map { "\($0)" } ?? "–")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// Switched off in Settings: say so, and where to turn it back on.
    private var off: some View {
        VStack(spacing: 6) {
            title(size: wide ? 20 : 15)
            Image(systemName: "eye.slash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.inkSoft)
            Text("Widget is off.\nTurn it on in BRICKS! settings.")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The 10x10 board in miniature. Empty when there's no game to show.
struct MiniBoard: View {
    let cells: [[Int?]]?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 10
            VStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<10, id: \.self) { c in
                            Group {
                                if let color = cells?[safe: r]?[safe: c] ?? nil {
                                    BrickView(colorIndex: color, size: cell * 0.86)
                                } else {
                                    RoundedRectangle(cornerRadius: cell * 0.2, style: .continuous)
                                        .fill(Theme.emptyCell)
                                        .frame(width: cell * 0.86, height: cell * 0.86)
                                }
                            }
                            .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

#if DEBUG
/// `-widgetPreview` shows both widget sizes in the app, since the simulator's Home Screen
/// can't be screenshotted with a widget on it from the command line.
struct WidgetPreviewScreen: View {
    var body: some View {
        VStack(spacing: 30) {
            ForEach([false, true], id: \.self) { wide in
                WidgetFace(snapshot: WidgetSnapshot.load() ?? .sample, enabled: WidgetSnapshot.isEnabled, wide: wide)
                    .padding(16)
                    .frame(width: wide ? 338 : 158, height: 158)
                    .background(
                        LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.3).ignoresSafeArea())
    }
}
#endif
#endif
