import SwiftUI

struct PowerUpBar: View {
    @ObservedObject var model: GameModel
    /// Stacks the chips top to bottom, for the side rail.
    var vertical = false
    /// Called after a chip is pressed, so a rail can fold itself away.
    var onUse: () -> Void = {}

    private var scale: CGFloat { Platform.uiScale }

    var body: some View {
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: 10 * scale))
            : AnyLayout(HStackLayout(spacing: 10 * scale))
        layout {
            ForEach(PowerUp.allCases) { power in
                chip(power)
            }
        }
    }

    private func chip(_ power: PowerUp) -> some View {
        let count = model.count(of: power)
        let owned = count > 0
        let active = model.activePower == power

        return Button {
            model.tapPowerUp(power)
            onUse()
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(active ? power.tint.opacity(0.35) : Theme.chip)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(active ? power.tint : Theme.chipBorder, lineWidth: active ? 2.5 : 1)
                    )
                    .shadow(color: Theme.shadow.opacity(owned ? 0.3 : 0.1), radius: 4, y: 2)

                Image(systemName: power.icon)
                    .font(.system(size: 20 * scale, weight: .semibold))
                    .foregroundColor(owned ? power.tint : Theme.inkSoft.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text("\(count)")
                    .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 19 * scale, height: 19 * scale)
                    .background(
                        Circle().fill(
                            count >= PowerUp.maxPerType
                                ? Theme.gift
                                : (owned ? power.tint : Theme.inkSoft.opacity(0.35))
                        )
                    )
                    .offset(x: 6 * scale, y: -6 * scale)
            }
            .frame(height: 52 * scale)
            .scaleEffect(active ? 1.06 : 1)
        }
        .buttonStyle(FocusLiftStyle())
        .disabled(!owned)
        .accessibilityLabel("\(power.title), \(count) left")
        .accessibilityIdentifier("power-\(power.rawValue)")
    }
}

/// The power-ups folded into one button in the screen's trailing system column, for the
/// iPhone Duo's outer display, where a bar along the bottom would squeeze the board.
/// Folded by default so a stray tap can't fire anything; pressing it fans the chips
/// out, and using one folds them away again.
struct PowerUpRail: View {
    @ObservedObject var model: GameModel
    let width: CGFloat

    @State private var expanded = false

    private var held: Int { PowerUp.allCases.reduce(0) { $0 + model.count(of: $1) } }

    var body: some View {
        VStack(spacing: 10) {
            if expanded {
                PowerUpBar(model: model, vertical: true) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { expanded = false }
                }
                .frame(width: width)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { expanded.toggle() }
            } label: {
                toggleFace
            }
            .buttonStyle(FocusLiftStyle())
            .accessibilityIdentifier("power-rail")
            .accessibilityLabel(expanded ? "Hide power-ups" : "Show power-ups")
            .accessibilityValue("\(held) held")
        }
    }

    /// Shows the armed power-up while one is waiting for a target, so it's clear what a
    /// tap on the board will do even with the rail folded.
    private var toggleFace: some View {
        let armed = model.activePower
        let tint = armed?.tint ?? Theme.inkSoft
        return ZStack(alignment: .topTrailing) {
            Circle()
                .fill(armed != nil ? tint.opacity(0.35) : Theme.chip)
                .overlay(Circle().stroke(armed != nil ? tint : Theme.chipBorder, lineWidth: armed != nil ? 2.5 : 1))
                .shadow(color: Theme.shadow.opacity(0.3), radius: 4, y: 2)
                .overlay(
                    Image(systemName: expanded ? "chevron.down" : (armed?.icon ?? "sparkles"))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(armed != nil ? tint : Theme.inkSoft)
                )

            if !expanded && held > 0 {
                Text("\(held)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(minWidth: 19, minHeight: 19)
                    .background(Capsule().fill(Theme.gift))
                    .offset(x: 4, y: -4)
            }
        }
        .frame(width: width, height: width)
    }
}
