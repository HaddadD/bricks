import SwiftUI

private struct DragInfo: Equatable {
    var trayIndex: Int
    var location: CGPoint
}

struct GameView: View {
    @ObservedObject var settings: Settings
    @StateObject private var model = GameModel()

    @State private var gridFrame: CGRect = .zero
    @State private var drag: DragInfo? = nil
    #if DEBUG
    /// `-settings` opens the sheet straight away, for inspecting it without tapping.
    @State private var showingSettings = ProcessInfo.processInfo.arguments.contains("-settings")
    #else
    @State private var showingSettings = false
    #endif


    var body: some View {
        GeometryReader { geo in
            let wide = Self.isWide(geo.size)
            let cell = wide ? wideCellSize(for: geo.size) : cellSize(for: geo.size)

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

                if wide {
                    wideLayout(size: geo.size, cell: cell)
                } else {
                    tallLayout(width: geo.size.width, cell: cell)
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
                    .shadow(color: Theme.shadow.opacity(0.35), radius: 8, y: 6)
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
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings) { model.newGame() }
                    .presentationDetents([.height(330)])
                    .presentationDragIndicator(.hidden)
            }
        }
    }

    // MARK: - Layout

    /// Space between the board and the side column in the wide layout.
    private static let wideGutter: CGFloat = 40

    /// Landscape iPad, a Mac window or anything else wider than it is tall gets the
    /// side-by-side layout; everything else stacks.
    private static func isWide(_ size: CGSize) -> Bool { size.width > size.height }

    private func cellSize(for size: CGSize) -> CGFloat {
        let byWidth = (size.width - 30) / CGFloat(GameModel.size)
        let byHeight = (size.height * 0.47) / CGFloat(GameModel.size)
        return floor(min(byWidth, byHeight))
    }

    /// The board is 10 cells plus 0.36 cells of padding. Header, score and margins take
    /// about 170pt of the height; across, the side column wants at least 5 cells (room
    /// for five power-up chips) plus the gutter and outer margins.
    private func wideCellSize(for size: CGSize) -> CGFloat {
        let board = CGFloat(GameModel.size) + 0.36
        let byHeight = (size.height - 170) / board
        let byWidth = (size.width - Self.wideGutter - 44) / (board + 5)
        return max(1, floor(min(byHeight, byWidth)))
    }

    /// Whatever width the board leaves, capped so the tray doesn't sprawl.
    private func sideColumnWidth(for size: CGSize, cell: CGFloat) -> CGFloat {
        let boardWidth = cell * CGFloat(GameModel.size) + BoardView.padding(cellSize: cell) * 2
        return max(0, min(size.width - boardWidth - Self.wideGutter - 44, cell * 5.5))
    }

    /// Phones and narrow windows: header, score and board, then the tray and power-ups.
    private func tallLayout(width: CGFloat, cell: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 4)

            Spacer(minLength: 6)

            boardBlock(cell: cell)
                // Nudges the block 12pt down. The three flexible spacers each give
                // back a third of any padding added here, so the value is 18.
                .padding(.top, 18)

            Spacer(minLength: 6)

            tray(cell: cell, slotWidth: width / 3, vertical: false)

            Spacer(minLength: 4)

            PowerUpBar(model: model)
                .allowsHitTesting(!model.isGameOver)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
        }
    }

    /// Wide spaces: the header across the top, the board on the left, and the tray
    /// stacked in a column beside it with the power-ups underneath.
    private func wideLayout(size: CGSize, cell: CGFloat) -> some View {
        let side = sideColumnWidth(for: size, cell: cell)

        return VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 4)

            Spacer(minLength: 6)

            HStack(alignment: .center, spacing: Self.wideGutter) {
                boardBlock(cell: cell)

                VStack(spacing: 14) {
                    tray(cell: cell, slotWidth: side, vertical: true)

                    PowerUpBar(model: model)
                        .allowsHitTesting(!model.isGameOver)
                        .frame(width: side)
                }
            }

            Spacer(minLength: 6)
        }
    }

    /// The score centred over the board, with the version stamped under its corner.
    private func boardBlock(cell: CGFloat) -> some View {
        VStack(spacing: 8) {
            scoreBoard

            VStack(alignment: .leading, spacing: 3) {
                BoardView(model: model, cellSize: cell, ghost: ghost(cellSize: cell))
                    .allowsHitTesting(!model.isGameOver)

                Text(Self.versionLabel)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.versionInk)
                    .padding(.leading, 6)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func tray(cell: CGFloat, slotWidth: CGFloat, vertical: Bool) -> some View {
        TrayView(
            model: model,
            cellSize: cell,
            slotWidth: slotWidth,
            vertical: vertical,
            draggingIndex: drag?.trayIndex,
            onDragChanged: { index, location in
                drag = DragInfo(trayIndex: index, location: location)
            },
            onDragEnded: { index in
                commitDrag(index: index, cellSize: cell)
            }
        )
        .allowsHitTesting(!model.isGameOver)
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

            Button {
                Haptics.tap()
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Theme.inkSoft)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.chip))
            }
            .buttonStyle(.plain)
        }
    }

    /// The running score, centred directly above the board.
    private var scoreBoard: some View {
        Text("\(model.score)")
            .font(.system(size: 42, weight: .heavy, design: .rounded))
            .foregroundColor(Theme.ink)
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity)
    }

    private func banner(text: String, tint: Color) -> some View {
        VStack {
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(Theme.card)
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
