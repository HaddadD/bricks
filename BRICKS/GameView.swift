import SwiftUI

private struct DragInfo: Equatable {
    var trayIndex: Int
    var location: CGPoint
}

struct GameView: View {
    @StateObject private var model = GameModel()

    @State private var gridFrame: CGRect = .zero
    @State private var drag: DragInfo? = nil
    @State private var confirmingReset = false


    var body: some View {
        GeometryReader { geo in
            let cell = cellSize(for: geo.size)
            let slotWidth = geo.size.width / 3

            ZStack {
                ZStack {
                    LinearGradient(
                        colors: [Theme.backgroundTop, Theme.backgroundBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Milestone celebration, fading out over the next 200 points.
                    let party = Theme.celebration(model.milestoneTheme)
                    LinearGradient(
                        colors: [party.top, party.bottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .opacity(model.celebrationLevel)
                }
                .animation(.easeInOut(duration: 0.7), value: model.celebrationLevel)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    // Tapping empty space cancels an armed power-up.
                    model.cancelPower()
                }

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 22)
                        .padding(.top, 4)

                    Spacer(minLength: 6)

                    VStack(alignment: .leading, spacing: 3) {
                        BoardView(model: model, cellSize: cell, ghost: ghost(cellSize: cell))
                            .allowsHitTesting(!model.isGameOver)
                            // Nudges the board 12pt down. The three flexible spacers
                            // each give back a third of any padding added here, so the
                            // value is 18 to land a true 12pt on screen.
                            .padding(.top, 18)

                        Text(Self.versionLabel)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.versionInk)
                            .padding(.leading, 6)
                    }

                    Spacer(minLength: 6)

                    TrayView(
                        model: model,
                        cellSize: cell,
                        slotWidth: slotWidth,
                        draggingIndex: drag?.trayIndex,
                        onDragChanged: { index, location in
                            drag = DragInfo(trayIndex: index, location: location)
                        },
                        onDragEnded: { index in
                            commitDrag(index: index, cellSize: cell)
                        }
                    )
                    .allowsHitTesting(!model.isGameOver)

                    Spacer(minLength: 4)

                    PowerUpBar(model: model)
                        .allowsHitTesting(!model.isGameOver)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 6)
                }

                // Piece floating under the finger.
                if let d = drag, let piece = model.tray[d.trayIndex] {
                    PieceView(
                        shape: piece.shape,
                        colorIndex: piece.colorIndex,
                        brickSize: cell - max(2, cell * 0.09),
                        gap: max(2, cell * 0.09)
                    )
                    .position(
                        x: d.location.x,
                        y: d.location.y - liftAmount(cellSize: cell)
                    )
                    .shadow(color: Color(hex: 0x9E8B7E).opacity(0.35), radius: 8, y: 6)
                    .allowsHitTesting(false)
                }

                if let hint = model.activePower?.targetHint, !hint.isEmpty {
                    banner(text: hint, tint: model.activePower?.tint ?? Theme.gift)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let toast = model.toast, model.activePower == nil {
                    banner(text: toast, tint: Theme.gift)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if model.isGameOver {
                    GameOverView(model: model)
                        .transition(.opacity)
                }
            }
            .coordinateSpace(name: "game")
            .onPreferenceChange(GridFrameKey.self) { gridFrame = $0 }
            .alert("Start a new game?", isPresented: $confirmingReset) {
                Button("Cancel", role: .cancel) { }
                Button("Yes", role: .destructive) { model.newGame() }
            } message: {
                Text("This board and your score of \(model.score) will be lost. Your power-ups are kept.")
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Layout

    private func cellSize(for size: CGSize) -> CGFloat {
        let byWidth = (size.width - 30) / CGFloat(GameModel.size)
        let byHeight = (size.height * 0.47) / CGFloat(GameModel.size)
        return floor(min(byWidth, byHeight))
    }

    private func liftAmount(cellSize: CGFloat) -> CGFloat {
        DragTargeting.lift(cellSize: cellSize)
    }

    /// Marketing version and build, e.g. "v1.0 (1)".
    static let versionLabel: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }()

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: -2) {
                Text("BRICKS!")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: 0xF08FB4), Color(hex: 0xA6BDF7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("best \(model.best)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.inkSoft)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: -2) {
                Text("\(model.score)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.ink)
                    .contentTransition(.numericText())
                Button {
                    confirmingReset = true
                } label: {
                    Label("New", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.inkSoft)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func banner(text: String, tint: Color) -> some View {
        VStack {
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(Color.white)
                        .shadow(color: tint.opacity(0.45), radius: 8, y: 3)
                )
                .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 1.5))
                .padding(.top, 78)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drag targeting

    /// Top-left board coordinate the dragged piece currently sits on.
    private func target(cellSize: CGFloat) -> (row: Int, col: Int)? {
        guard let d = drag, let piece = model.tray[d.trayIndex], gridFrame != .zero else { return nil }

        return DragTargeting.target(
            finger: d.location,
            shapeRows: piece.shape.rows,
            shapeCols: piece.shape.cols,
            gridOrigin: gridFrame.origin,
            cellSize: cellSize
        )
    }

    private func ghost(cellSize: CGFloat) -> Ghost? {
        guard let d = drag,
              let piece = model.tray[d.trayIndex],
              let t = target(cellSize: cellSize),
              model.canPlace(piece.shape, atRow: t.row, col: t.col)
        else { return nil }

        let points = Set(piece.shape.points.map { GridPoint(r: t.row + $0.r, c: t.col + $0.c) })

        // Work out which lines this placement would complete, to hint the clear.
        var filled = Set<GridPoint>()
        for r in 0..<GameModel.size {
            for c in 0..<GameModel.size where model.board[r][c].isFilled {
                filled.insert(GridPoint(r: r, c: c))
            }
        }
        filled.formUnion(points)

        var rows = Set<Int>()
        var cols = Set<Int>()
        for r in 0..<GameModel.size where (0..<GameModel.size).allSatisfy({ filled.contains(GridPoint(r: r, c: $0)) }) {
            rows.insert(r)
        }
        for c in 0..<GameModel.size where (0..<GameModel.size).allSatisfy({ filled.contains(GridPoint(r: $0, c: c)) }) {
            cols.insert(c)
        }

        return Ghost(points: points, colorIndex: piece.colorIndex, completedRows: rows, completedCols: cols)
    }

    private func commitDrag(index: Int, cellSize: CGFloat) {
        defer { drag = nil }
        guard let t = target(cellSize: cellSize) else { return }
        model.place(trayIndex: index, atRow: t.row, col: t.col)
    }
}
