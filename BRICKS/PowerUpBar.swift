import SwiftUI

struct PowerUpBar: View {
    @ObservedObject var model: GameModel

    var body: some View {
        HStack(spacing: 10) {
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(owned ? power.tint : Theme.inkSoft.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text("\(count)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 19, height: 19)
                    .background(
                        Circle().fill(
                            count >= PowerUp.maxPerType
                                ? Theme.gift
                                : (owned ? power.tint : Theme.inkSoft.opacity(0.35))
                        )
                    )
                    .offset(x: 6, y: -6)
            }
            .frame(height: 52)
            .scaleEffect(active ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!owned)
    }
}
