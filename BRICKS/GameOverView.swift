import SwiftUI

struct GameOverView: View {
    @ObservedObject var model: GameModel
    @EnvironmentObject private var progress: PlayerProgress
    @EnvironmentObject private var gameCenter: GameCenter

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

                if !progress.earnedThisGame.isEmpty {
                    earned
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

                if gameCenter.isSignedIn {
                    HStack(spacing: 8) {
                        gameCenterButton("Leaderboards", "list.number") { gameCenter.show(.leaderboards) }
                        gameCenterButton("Achievements", "rosette") { gameCenter.show(.achievements) }
                        if GameCenter.hasChallenges {
                            gameCenterButton("Challenge", "flag.2.crossed.fill") { gameCenter.show(.challenges) }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: Theme.shadow.opacity(0.3), radius: 22, y: 10)
            )
            .padding(.horizontal, 30)
        }
    }

    /// The achievements this game earned, up to three, then a count of the rest.
    private var earned: some View {
        let list = progress.earnedThisGame
        return VStack(spacing: 6) {
            Text(list.count == 1 ? "Achievement earned" : "\(list.count) achievements earned")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.inkSoft)
            ForEach(list.prefix(3), id: \.self) { achievement in
                let info = achievement.info
                let tint = Color(hex: Achievement.palette[info.color]?.shade ?? 0xAD93D5)
                HStack(spacing: 6) {
                    Image(systemName: info.symbol)
                        .font(.system(size: 12, weight: .bold))
                    Text(info.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(0.16)))
            }
            if list.count > 3 {
                Text("+\(list.count - 3) more")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("earned")
    }

    private func gameCenterButton(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(Theme.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.emptyCell.opacity(0.55)))
        }
        .buttonStyle(FocusLiftStyle())
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
