import SwiftUI

struct GameOverView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("No more moves")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(Theme.ink)

                HStack(spacing: 26) {
                    stat("SCORE", model.score)
                    stat("BEST", model.best)
                }

                if PowerUp.allCases.contains(where: { model.count(of: $0) > 0 }) {
                    VStack(spacing: 7) {
                        Text("Kept for your next game")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.inkSoft)

                        HStack(spacing: 9) {
                            ForEach(PowerUp.allCases.filter { model.count(of: $0) > 0 }) { power in
                                HStack(spacing: 3) {
                                    Image(systemName: power.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("\(model.count(of: power))")
                                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                                }
                                .foregroundColor(power.tint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(power.tint.opacity(0.16))
                                )
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                Button {
                    model.newGame()
                } label: {
                    Text("Play again")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: 0xF08FB4), Color(hex: 0xB39BF0)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color(hex: 0x9E8B7E).opacity(0.3), radius: 22, y: 10)
            )
            .padding(.horizontal, 30)
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.inkSoft)
            Text("\(value)")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.ink)
        }
    }
}
