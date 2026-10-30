import SwiftUI

private struct DragInfo: Equatable {
    var trayIndex: Int
    var location: CGPoint
}

/// A piece, or a hammer or bomb's target, being moved around the board with Apple TV's
/// remote. `trayIndex` is nil when aiming a power-up.
private struct Placing: Equatable {
    var trayIndex: Int?
    var cursor: PlacementCursor
}

/// The game on every platform except Apple Watch, which has `WatchGameView`.
struct GameView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var model: GameModel

    @State private var gridFrame: CGRect = .zero
    @State private var drag: DragInfo? = nil
    @State private var placing: Placing? = nil
    @FocusState private var boardFocused: Bool
    @State private var confirmingNewGame = false
    #if DEBUG
    /// `-settings` opens the sheet straight away, for inspecting it without tapping.
    @State private var showingSettings = ProcessInfo.processInfo.arguments.contains("-settings")
    #else
    @State private var showingSettings = false
    #endif

    private var scale: CGFloat { Platform.uiScale }
    private var usesRemote: Bool { Platform.input == .remote }
    /// While the remote is moving something on the board, everything else is off limits,
    /// so the remote's arrows can't wander out of the board.
    private var controlsLocked: Bool { usesRemote && (placing != nil || model.isGameOver) }

    var body: some View {
        GeometryReader { geo in
            let wide = Self.isWide(geo.size)
            let rail = Self.usesRail(geo, wide: wide)
            let cell = wide ? wideCellSize(for: geo.size) : cellSize(for: geo.size, withBar: !rail)

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
                #if !os(tvOS)
                .onTapGesture {
                    // Tapping empty space cancels an armed power-up.
                    model.cancelPower()
                }
                #endif

                if wide {
                    wideLayout(size: geo.size, cell: cell)
                } else {
                    tallLayout(width: geo.size.width, cell: cell, showsBar: !rail)
                }

                if rail {
                    let column = geo.safeAreaInsets.trailing
                    PowerUpRail(model: model, width: min(column - 16, 56))
                        .frame(width: column)
                        .padding(.bottom, 12)
                        // Reaches out of the safe area into the system's trailing column.
                        .padding(.trailing, -column)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .allowsHitTesting(!model.isGameOver)
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
                        y: d.location.y - DragTargeting.lift(cellSize: cell, lifted: Platform.liftsDraggedPiece)
                    )
                    .shadow(color: Theme.shadow.opacity(0.35), radius: 8, y: 6)
                    .allowsHitTesting(false)
                }

                if let hint = currentHint {
                    banner(text: hint, tint: model.activePower?.tint ?? Theme.gift, wide: wide, short: rail)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let toast = model.toast, model.activePower == nil, placing == nil {
                    banner(text: toast, tint: Theme.gift, wide: wide, short: rail)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if model.isGameOver {
                    GameOverView(model: model)
                        .scaleEffect(scale)
                        .transition(.opacity)
                }
            }
            .coordinateSpace(name: "game")
            .onPreferenceChange(GridFrameKey.self) { gridFrame = $0 }
            .onReceive(model.$activePower) { power in powerChanged(to: power) }
            #if os(tvOS)
            // Menu finishes a Rotate session; otherwise it does what it always does.
            .onExitCommand(perform: model.activePower == .rotate ? { model.endRotateMode() } : nil)
            #endif
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings) { model.newGame() }
                    #if os(iOS)
                    .presentationDetents([.height(Haptics.isSupported ? 330 : 270)])
                    .presentationDragIndicator(.hidden)
                    #endif
            }
            .alert("Start a new game?", isPresented: $confirmingNewGame) {
                Button("Cancel", role: .cancel) { }
                Button("New Game", role: .destructive) { model.newGame() }
            } message: {
                Text("This board and your score will be lost. Your power-ups are kept.")
            }
            .focusedSceneValue(\.gameActions, gameActions)
        }
    }

    // MARK: - Layout

    /// Space between the board and the side column in the wide layout.
    private static let wideGutter: CGFloat = 40

    /// Landscape iPad, a Mac or Vision Pro window, Apple TV, or anything else wider than
    /// it is tall gets the side-by-side layout; everything else stacks.
    private static func isWide(_ size: CGSize) -> Bool { size.width > size.height }

    /// The iPhone Duo's outer display keeps its clock and camera in a column down the
    /// right side. Where a column like that is there and the stacked layout is short of
    /// height, the power-ups fold into the column instead of a bar along the bottom.
    private static func usesRail(_ geo: GeometryProxy, wide: Bool) -> Bool {
        Platform.input == .drag && !wide
            && geo.safeAreaInsets.trailing >= 50
            && geo.size.height < geo.size.width * 1.7
    }

    private func cellSize(for size: CGSize, withBar: Bool) -> CGFloat {
        let byWidth = (size.width - 30) / CGFloat(GameModel.size)
        // Without the bottom bar, the board gets that height back.
        let byHeight = (size.height * (withBar ? 0.47 : 0.53)) / CGFloat(GameModel.size)
        return floor(min(byWidth, byHeight))
    }

    /// The board is 10 cells plus 0.36 cells of padding. Header, score and margins take
    /// about 170pt of the height (scaled up on Apple TV); across, the side column wants
    /// at least 5 cells (room for five power-up chips) plus the gutter and outer margins.
    private func wideCellSize(for size: CGSize) -> CGFloat {
        let board = CGFloat(GameModel.size) + 0.36
        let byHeight = (size.height - 170 * scale) / board
        let byWidth = (size.width - Self.wideGutter - 44) / (board + 5)
        return max(1, floor(min(byHeight, byWidth)))
    }

    /// Whatever width the board leaves, capped so the tray doesn't sprawl.
    private func sideColumnWidth(for size: CGSize, cell: CGFloat) -> CGFloat {
        let boardWidth = cell * CGFloat(GameModel.size) + BoardView.padding(cellSize: cell) * 2
        return max(0, min(size.width - boardWidth - Self.wideGutter - 44, cell * 5.5))
    }

    /// Phones and narrow windows: header, score and board, then the tray and power-ups.
    private func tallLayout(width: CGFloat, cell: CGFloat, showsBar: Bool) -> some View {
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

            if showsBar {
                powerUps
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
            }
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

                VStack(spacing: 14 * scale) {
                    tray(cell: cell, slotWidth: side, vertical: true)

                    powerUps
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
                board(cell: cell)

                Text(Self.versionLabel)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.versionInk)
                    .padding(.leading, 6)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func board(cell: CGFloat) -> some View {
        let view = BoardView(model: model, cellSize: cell, ghost: ghost(cellSize: cell), aim: aim)

        if usesRemote {
            // The remote presses the board to drop what it is moving; arrows move it.
            Button(action: pressBoard) { view }
                .buttonStyle(FocusLiftStyle(focusedScale: 1))
                .focused($boardFocused)
                .disabled(placing == nil)
                .accessibilityIdentifier("board")
                .accessibilityLabel("Board")
                .accessibilityValue(aimDescription)
                #if os(tvOS)
                .onMoveCommand(perform: moveCursor)
                .onExitCommand(perform: cancelPlacing)
                #endif
        } else {
            view
                .allowsHitTesting(!model.isGameOver)
                .accessibilityIdentifier("board")
        }
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
            },
            selectedIndex: placing?.trayIndex,
            onSelect: usesRemote ? { pick(trayIndex: $0) } : nil
        )
        .allowsHitTesting(!model.isGameOver)
        .disabled(controlsLocked)
    }

    private var powerUps: some View {
        PowerUpBar(model: model)
            .allowsHitTesting(!model.isGameOver)
            .disabled(controlsLocked)
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
            VStack(alignment: .leading, spacing: -2 * scale) {
                Text("BRICKS!")
                    .font(.system(size: 34 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: 0xF08FB4), Color(hex: 0xA6BDF7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("best \(model.best)")
                    .font(.system(size: 13 * scale, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.inkSoft)
            }

            Spacer()

            Button {
                Haptics.tap()
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 19 * scale, weight: .semibold))
                    .foregroundColor(Theme.inkSoft)
                    .frame(width: 42 * scale, height: 42 * scale)
                    .background(Circle().fill(Theme.chip))
            }
            .buttonStyle(FocusLiftStyle())
            .disabled(controlsLocked)
            .accessibilityLabel("Settings")
        }
    }

    /// The running score, centred directly above the board.
    private var scoreBoard: some View {
        Text("\(model.score)")
            .font(.system(size: 42 * scale, weight: .heavy, design: .rounded))
            .foregroundColor(Theme.ink)
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("score")
    }

    /// A message capsule. Phones show it in the gap between the header and the score; wide
    /// layouts have no such gap, so it sits in the header row's empty middle instead. A
    /// short screen (the Duo's outer display) has neither, so it goes over the tray.
    private func banner(text: String, tint: Color, wide: Bool, short: Bool) -> some View {
        VStack {
            if short { Spacer() }
            Text(text)
                .font(.system(size: 14 * scale, weight: .bold, design: .rounded))
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 16 * scale)
                .padding(.vertical, 9 * scale)
                .background(
                    Capsule().fill(Theme.card)
                        .shadow(color: tint.opacity(0.45), radius: 8, y: 3)
                )
                .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 1.5))
                .padding(.top, short ? 0 : (wide ? 14 : 78) * scale)
                .padding(.bottom, short ? 40 : 0)
            if !short { Spacer() }
        }
        .allowsHitTesting(false)
    }

    /// What the banner says: an armed power-up's instructions, or how to place a piece
    /// with the remote.
    private var currentHint: String? {
        if let power = model.activePower, !power.targetHint.isEmpty { return power.targetHint }
        if placing?.trayIndex != nil { return "Move it with the remote, then press to place" }
        return nil
    }

    // MARK: - Drag targeting

    /// Top-left board coordinate the dragged piece currently sits on.
    private func dragTarget(cellSize: CGFloat) -> (row: Int, col: Int)? {
        guard let d = drag, let piece = model.tray[d.trayIndex], gridFrame != .zero else { return nil }

        return DragTargeting.target(
            finger: d.location,
            shapeRows: piece.shape.rows,
            shapeCols: piece.shape.cols,
            gridOrigin: gridFrame.origin,
            cellSize: cellSize,
            lifted: Platform.liftsDraggedPiece
        )
    }

    private func ghost(cellSize: CGFloat) -> Ghost? {
        if let p = placing, let index = p.trayIndex, let piece = model.tray[index] {
            return Ghost.preview(of: piece, atRow: p.cursor.row, col: p.cursor.col, on: model)
        }
        guard let d = drag, let piece = model.tray[d.trayIndex], let t = dragTarget(cellSize: cellSize)
        else { return nil }
        return Ghost.preview(of: piece, atRow: t.row, col: t.col, on: model)
    }

    private func commitDrag(index: Int, cellSize: CGFloat) {
        defer { drag = nil }
        guard let t = dragTarget(cellSize: cellSize) else { return }
        model.place(trayIndex: index, atRow: t.row, col: t.col)
    }

    // MARK: - Remote (Apple TV)

    /// The cells outlined while the remote is aiming.
    private var aim: Aim? {
        guard let p = placing else { return nil }
        let c = p.cursor

        if let index = p.trayIndex, let piece = model.tray[index] {
            let cells = Set(piece.shape.points.map { GridPoint(r: c.row + $0.r, c: c.col + $0.c) })
            return Aim(cells: cells, blocked: !model.canPlace(piece.shape, atRow: c.row, col: c.col))
        }

        // A hammer hits one cell; a bomb hits the 3x3 around it.
        let reach = model.activePower == .bomb ? 1 : 0
        var cells = Set<GridPoint>()
        for r in (c.row - reach)...(c.row + reach) where (0..<GameModel.size).contains(r) {
            for col in (c.col - reach)...(c.col + reach) where (0..<GameModel.size).contains(col) {
                cells.insert(GridPoint(r: r, c: col))
            }
        }
        return Aim(cells: cells)
    }

    /// Where the remote is aiming, for VoiceOver (and the UI tests).
    private var aimDescription: String {
        guard let p = placing else { return "" }
        let spot = "row \(p.cursor.row + 1), column \(p.cursor.col + 1)"
        return aim?.blocked == true ? "\(spot), doesn't fit" : spot
    }

    /// Picks a tray piece up and puts it on the board where it fits nearest the middle.
    private func pick(trayIndex index: Int) {
        guard let piece = model.tray[index] else { return }
        var cursor = PlacementCursor(rows: piece.shape.rows, cols: piece.shape.cols, boardSize: GameModel.size)
        if let spot = nearestFit(for: piece.shape, to: cursor) {
            cursor.move(rows: spot.row - cursor.row, cols: spot.col - cursor.col)
        }
        Haptics.tap()
        placing = Placing(trayIndex: index, cursor: cursor)
        boardFocused = true
    }

    /// The legal spot closest to the cursor's starting point, so a press usually works
    /// straight away.
    private func nearestFit(for shape: Shape, to cursor: PlacementCursor) -> (row: Int, col: Int)? {
        let last = GameModel.size
        var best: (row: Int, col: Int, distance: Int)? = nil
        for r in 0...(last - shape.rows) {
            for c in 0...(last - shape.cols) where model.canPlace(shape, atRow: r, col: c) {
                let d = abs(r - cursor.row) + abs(c - cursor.col)
                if best == nil || d < best!.distance { best = (r, c, d) }
            }
        }
        return best.map { ($0.row, $0.col) }
    }

    /// Hammer and bomb need a target, so arming one hands the remote to the board.
    private func powerChanged(to power: PowerUp?) {
        guard usesRemote else { return }
        if power == .hammer || power == .bomb {
            placing = Placing(
                trayIndex: nil,
                cursor: PlacementCursor(rows: 1, cols: 1, boardSize: GameModel.size)
            )
            boardFocused = true
        } else if placing?.trayIndex == nil {
            placing = nil
        }
    }

    #if os(tvOS)
    private func moveCursor(_ direction: MoveCommandDirection) {
        guard var p = placing else { return }
        switch direction {
        case .up: p.cursor.move(rows: -1, cols: 0)
        case .down: p.cursor.move(rows: 1, cols: 0)
        case .left: p.cursor.move(rows: 0, cols: -1)
        case .right: p.cursor.move(rows: 0, cols: 1)
        @unknown default: return
        }
        placing = p
    }
    #endif

    private func pressBoard() {
        guard let p = placing else { return }
        if let index = p.trayIndex {
            guard model.place(trayIndex: index, atRow: p.cursor.row, col: p.cursor.col) else { return }
        } else {
            model.applyTargetedPower(atRow: p.cursor.row, col: p.cursor.col)
        }
        placing = nil
        boardFocused = false
    }

    private func cancelPlacing() {
        if placing?.trayIndex == nil { model.cancelPower() }
        placing = nil
        boardFocused = false
    }

    // MARK: - Menu commands (Mac, iPad keyboard, Vision Pro)

    private var gameActions: GameActions {
        GameActions(
            newGame: { confirmingNewGame = true },
            undo: { model.tapPowerUp(.undo) },
            canUndo: model.count(of: .undo) > 0 && !model.isGameOver,
            showSettings: { showingSettings = true }
        )
    }
}

/// What the app's menu commands can do to the game in the focused window.
struct GameActions {
    let newGame: () -> Void
    let undo: () -> Void
    let canUndo: Bool
    let showSettings: () -> Void
}

private struct GameActionsKey: FocusedValueKey {
    typealias Value = GameActions
}

extension FocusedValues {
    var gameActions: GameActions? {
        get { self[GameActionsKey.self] }
        set { self[GameActionsKey.self] = newValue }
    }
}
