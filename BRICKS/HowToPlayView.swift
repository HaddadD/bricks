import SwiftUI

/// The rules, as a deck you swipe through from the settings sheet.
struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    /// One card of the deck. `powers` is filled on the power-up card only, which lists
    /// them from `PowerUp` itself rather than repeating their names here.
    private struct Rule: Identifiable {
        let id: Int
        let icon: String
        let tint: Color
        let title: String
        let blurb: String
        var powers: [PowerUp] = []
    }

    private static let rules: [Rule] = [
        Rule(
            id: 0,
            icon: "square.grid.3x3.fill",
            tint: Color(hex: 0xA6BDF7),
            title: "The board",
            blurb: """
            Drag a piece from the tray onto the 10×10 board. Fill a whole row or \
            column and it clears away.

            The tray only refills once all three pieces are gone, and a fresh deal \
            always holds at least one piece that fits somewhere.
            """
        ),
        Rule(
            id: 1,
            icon: "number",
            tint: Color(hex: 0xF3DE84),
            title: "Scoring",
            blurb: """
            A point for every brick you place, and a point for every cell you clear.

            Break more than one line with a single piece and those cleared cells pay \
            one and a half times — a row and a column crossing counts as 19 cells, \
            not 20.
            """
        ),
        Rule(
            id: 2,
            icon: "flame.fill",
            tint: Color(hex: 0xFFB59E),
            title: "Combos",
            blurb: """
            Clear on one turn and clear again on the very next one and a combo \
            starts, counting up beside your score.

            Every line counts, so breaking three at once moves it on three. Every \
            fifth combo turns the whole board rainbow. A turn that clears nothing \
            ends the streak.
            """
        ),
        Rule(
            id: 3,
            icon: "gift.fill",
            tint: Color(hex: 0xFFA8C5),
            title: "Gifts",
            blurb: """
            Every 300 points or so a gift lands on an empty square, counting down \
            from 10 moves.

            Build over it and clear that row or column before the counter runs out \
            and it pays a power-up. Smashing the brick on top only uncovers it again.
            """
        ),
        Rule(
            id: 4,
            icon: "sparkles",
            tint: Color(hex: 0xC8AEF0),
            title: "Power-ups",
            blurb: "Five of each, at most. Tap one to use it.",
            powers: PowerUp.allCases
        ),
        Rule(
            id: 5,
            icon: "flag.checkered",
            tint: Color(hex: 0x8FDDE7),
            title: "Running out",
            blurb: """
            When none of your three pieces fit anywhere, the game is over — a \
            power-up cannot dig you out of it.

            Whatever you were holding carries into the next game, and your board is \
            saved as you go, so closing the app never costs you a run.
            """
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.backgroundTop, Theme.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                deck
                #if !os(macOS) && !os(tvOS)
                dots
                    .padding(.bottom, 24)
                #endif
            }
        }
    }

    /// A deck you swipe through where the platform has a paged `TabView`. The Mac and
    /// Apple TV don't, and neither of them swipes anyway, so there the cards simply
    /// stack in a scroll view and the dots go with the swiping.
    @ViewBuilder
    private var deck: some View {
        #if os(macOS) || os(tvOS)
        ScrollView {
            VStack(spacing: 30) {
                ForEach(Self.rules) { card($0) }
            }
            .padding(.vertical, 16)
        }
        #else
        TabView(selection: $page) {
            ForEach(Self.rules) { rule in
                card(rule).tag(rule.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }

    private var header: some View {
        HStack {
            Text("How to play")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(Theme.ink)

            Spacer()

            Button("Done") { dismiss() }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.gift)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    private func card(_ rule: Rule) -> some View {
        VStack(spacing: 16) {
            // Spacers either side centre the short cards without squashing the long
            // power-up one, which simply pushes them to nothing.
            Spacer(minLength: 0)

            Image(systemName: rule.icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(rule.tint)
                .frame(width: 72, height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(rule.tint.opacity(0.22))
                )

            Text(rule.title)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(Theme.ink)

            Text(rule.blurb)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if !rule.powers.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rule.powers.enumerated()), id: \.element) { index, power in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.chipBorder)
                                .frame(height: 1)
                                .padding(.leading, 46)
                        }
                        powerRow(power)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.card)
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
    }

    private func powerRow(_ power: PowerUp) -> some View {
        HStack(spacing: 10) {
            Image(systemName: power.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(power.tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(power.tint.opacity(0.22))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(power.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.ink)
                Text(power.summary)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    /// Hand-drawn rather than the system page control, which cannot be tinted without
    /// reaching into UIPageControl's global appearance.
    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(Self.rules) { rule in
                Capsule()
                    .fill(rule.id == page ? Theme.gift : Theme.inkSoft.opacity(0.3))
                    .frame(width: rule.id == page ? 20 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
    }
}
