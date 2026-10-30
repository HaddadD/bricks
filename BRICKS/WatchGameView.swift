#if os(watchOS)
import SwiftUI

/// The game on Apple Watch. Everything a move needs fits on one screen: the board on
/// the left, the three tray pieces stacked beside it, and the power-ups underneath. A
/// wrist is too small to drag on, so pieces are placed by tapping: tap a piece, tap the
/// board to aim it, then tap the outline to put it down.
struct WatchGameView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var model: GameModel

    /// The tray piece being placed, and where it is aimed.
    @State private var selected: Int? = nil
    @State private var cursor: PlacementCursor? = nil
    @State private var showingSettings = false

    /// Score row and power-up row, around the board.
    private static let chromeHeight: CGFloat = 62
    private static let chip: CGFloat = 27

    var body: some View {
        GeometryReader { geo in
            // Across: the board (10.36 cells) plus a tray column wide enough for a 3x3
            // piece. Down: the board plus the score and power-up rows.
            let board = CGFloat(GameModel.size) + 0.36
            let cell = max(1, floor(min((geo.size.width - 4) / (board + 2.4), (geo.size.height - Self.chromeHeight) / board)))
            let boardWidth = cell * board

            VStack(spacing: 4) {
                scoreRow

                HStack(spacing: 4) {
                    BoardView(model: model, cellSize: cell, ghost: ghost, aim: aim, onTapCell: tapCell)
                        .allowsHitTesting(!model.isGameOver)
                        .accessibilityIdentifier("board")

                    TrayView(
                        model: model,
                        cellSize: cell,
                        slotWidth: geo.size.width - boardWidth - 4,
                        vertical: true,
                        selectedIndex: selected,
                        onSelect: select
                    )
                    .allowsHitTesting(!model.isGameOver)
                }

                // The chips make way for instructions while something is being aimed;
                // tapping the instructions backs out.
                if let hint {
                    Button(action: cancelAiming) {
                        HStack(spacing: 4) {
                            Text(hint)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            Image(systemName: "xmark.circle.fill")
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.inkSoft)
                        .frame(maxWidth: .infinity, minHeight: Self.chip)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hint")
                } else {
                    powerUps
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.easeOut(duration: 0.2), value: hint)
        }
        // The bottom row can sit in the rounded corners' band; the board can't spare it.
        .ignoresSafeArea(edges: .bottom)
        .background(background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.card))
                    .padding(.top, 34)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay { if model.isGameOver { gameOver } }
        .onReceive(model.$tray) { _ in
            // Any change to the tray (a placement, shuffle, undo, rotate) invalidates
            // what was picked and where it was aimed.
            selected = nil
            cursor = nil
        }
        .sheet(isPresented: $showingSettings) {
            WatchSettingsView(settings: settings) { model.newGame() }
        }
    }

    private func cancelAiming() {
        if model.activePower != nil {
            model.cancelPower()
        }
        selected = nil
        cursor = nil
    }

    // MARK: - Pieces

    private func select(_ index: Int) {
        if selected == index {
            selected = nil
        } else {
            selected = index
            Haptics.tap()
        }
        cursor = nil
    }

    private func tapCell(_ row: Int, _ col: Int) {
        if model.activePower == .hammer || model.activePower == .bomb {
            model.applyTargetedPower(atRow: row, col: col)
            return
        }
        guard let index = selected, let piece = model.tray[index] else { return }

        // A second tap inside the outline puts the piece down; anywhere else re-aims.
        if let c = cursor, c.covers(row: row, col: col),
           model.place(trayIndex: index, atRow: c.row, col: c.col) {
            return
        }
        var c = cursor ?? PlacementCursor(rows: piece.shape.rows, cols: piece.shape.cols, boardSize: GameModel.size)
        c.centre(onRow: row, col: col)
        cursor = c
    }

    private var ghost: Ghost? {
        guard let index = selected, let piece = model.tray[index], let c = cursor else { return nil }
        return Ghost.preview(of: piece, atRow: c.row, col: c.col, on: model)
    }

    private var aim: Aim? {
        guard let index = selected, let piece = model.tray[index], let c = cursor else { return nil }
        let cells = Set(piece.shape.points.map { GridPoint(r: c.row + $0.r, c: c.col + $0.c) })
        return Aim(cells: cells, blocked: !model.canPlace(piece.shape, atRow: c.row, col: c.col))
    }

    private var hint: String? {
        if let power = model.activePower, !power.targetHint.isEmpty { return power.targetHint }
        guard selected != nil else { return nil }
        if cursor == nil { return "Tap the board to aim" }
        return aim?.blocked == true ? "Doesn't fit there" : "Tap the outline to place"
    }

    // MARK: - Chrome

    private var scoreRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("\(model.score)")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.ink)
                .contentTransition(.numericText())
                .accessibilityIdentifier("score")
            Text("best \(model.best)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.inkSoft)
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.inkSoft)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.chip))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .frame(height: 26)
        .padding(.horizontal, 4)
    }

    private var powerUps: some View {
        HStack(spacing: 4) {
            ForEach(PowerUp.allCases) { power in
                let count = model.count(of: power)
                let active = model.activePower == power
                Button {
                    model.tapPowerUp(power)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Circle()
                            .fill(active ? power.tint.opacity(0.35) : Theme.chip)
                            .overlay(Circle().stroke(active ? power.tint : .clear, lineWidth: 2))
                            .overlay(
                                Image(systemName: power.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(count > 0 ? power.tint : Theme.inkSoft.opacity(0.45))
                            )
                        Text("\(count)")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(count > 0 ? power.tint : Theme.inkSoft.opacity(0.35)))
                            .offset(x: 3, y: -3)
                    }
                    .frame(width: Self.chip, height: Self.chip)
                }
                .buttonStyle(.plain)
                .disabled(count == 0 || model.isGameOver)
                .accessibilityLabel("\(power.title), \(count) left")
                .accessibilityIdentifier("power-\(power.rawValue)")
            }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
            let party = Theme.celebration(model.milestoneTheme)
            LinearGradient(colors: [party.top, party.bottom], startPoint: .top, endPoint: .bottom)
                .opacity(model.celebrationLevel)
        }
        .animation(.easeInOut(duration: 0.7), value: model.celebrationLevel)
    }

    private var gameOver: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 8) {
                Text("No more moves")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                HStack(spacing: 18) {
                    stat("SCORE", model.score)
                    stat("BEST", model.best)
                }
                Button("Play again") { model.newGame() }
                    .tint(Color(hex: 0xF08FB4))
            }
            .foregroundColor(Theme.ink)
            .padding()
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Theme.inkSoft)
            Text("\(value)")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
        }
    }
}

/// Apple Watch's settings: vibrations and starting over. (The watch is always dark.)
private struct WatchSettingsView: View {
    @ObservedObject var settings: Settings
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    var body: some View {
        List {
            Toggle("Vibrations", isOn: $settings.vibrations)
            Button("Reset game", role: .destructive) { confirmingReset = true }
            Text(GameView.versionLabel)
                .font(.footnote)
                .foregroundColor(Theme.inkSoft)
        }
        .confirmationDialog("Start a new game?", isPresented: $confirmingReset) {
            Button("New Game", role: .destructive) {
                onReset()
                dismiss()
            }
        } message: {
            Text("This board and your score will be lost. Your power-ups are kept.")
        }
    }
}
#endif
