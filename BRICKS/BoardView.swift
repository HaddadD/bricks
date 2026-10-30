import SwiftUI

/// A preview of the piece currently hovering over the board.
struct Ghost: Equatable {
    var points: Set<GridPoint>
    var colorIndex: Int
    /// Rows / columns that this placement would complete.
    var completedRows: Set<Int>
    var completedCols: Set<Int>
}

extension Ghost {
    /// The preview for `piece` with its top-left on (row, col), including the lines the
    /// placement would complete, or nil if it doesn't fit there.
    static func preview(of piece: TrayPiece, atRow row: Int, col: Int, on model: GameModel) -> Ghost? {
        guard model.canPlace(piece.shape, atRow: row, col: col) else { return nil }

        let points = Set(piece.shape.points.map { GridPoint(r: row + $0.r, c: col + $0.c) })

        var filled = points
        for r in 0..<GameModel.size {
            for c in 0..<GameModel.size where model.board[r][c].isFilled {
                filled.insert(GridPoint(r: r, c: c))
            }
        }

        let all = 0..<GameModel.size
        let rows = Set(all.filter { r in all.allSatisfy { filled.contains(GridPoint(r: r, c: $0)) } })
        let cols = Set(all.filter { c in all.allSatisfy { filled.contains(GridPoint(r: $0, c: c)) } })

        return Ghost(points: points, colorIndex: piece.colorIndex, completedRows: rows, completedCols: cols)
    }
}

/// Cells outlined while aiming by remote or by tapping (Apple TV, Apple Watch): where a
/// piece would go, or what a hammer or bomb would hit.
struct Aim: Equatable {
    var cells: Set<GridPoint>
    /// The piece doesn't fit here, so pressing would do nothing.
    var blocked = false
}

/// Reports the grid's frame in the shared "game" coordinate space.
struct GridFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    /// Only the board actually reports a frame; sibling views in the ZStack contribute
    /// the default, so an empty rect must never overwrite a real one.
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct BoardView: View {
    @ObservedObject var model: GameModel
    let cellSize: CGFloat
    let ghost: Ghost?
    var aim: Aim? = nil
    /// Called with a tapped cell, when tapping the board should do something other than
    /// fire an armed hammer or bomb (Apple Watch's tap-to-aim).
    var onTapCell: ((Int, Int) -> Void)? = nil

    /// Inset between the board's edge and its grid.
    static func padding(cellSize: CGFloat) -> CGFloat { max(5, cellSize * 0.18) }

    private var pad: CGFloat { Self.padding(cellSize: cellSize) }
    private var gap: CGFloat { max(2, cellSize * 0.09) }
    private var inner: CGFloat { cellSize - gap }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cellSize * 0.5, style: .continuous)
                .fill(Theme.boardBackground)
                .shadow(color: Theme.shadow.opacity(0.35), radius: 10, y: 4)

            grid
        }
        .frame(
            width: cellSize * CGFloat(GameModel.size) + pad * 2,
            height: cellSize * CGFloat(GameModel.size) + pad * 2
        )
        // One element for VoiceOver and UI tests, rather than a hundred cells.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Board")
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<GameModel.size, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<GameModel.size, id: \.self) { c in
                        cellView(r, c)
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: GridFrameKey.self, value: geo.frame(in: .named("game")))
            }
        )
        .contentShape(Rectangle())
        #if !os(tvOS)
        // Apple TV aims with the remote instead; see GameView.
        .onTapGesture(coordinateSpace: .local) { point in
            let c = Int(floor(point.x / cellSize))
            let r = Int(floor(point.y / cellSize))
            guard r >= 0, r < GameModel.size, c >= 0, c < GameModel.size else { return }
            if let onTapCell {
                onTapCell(r, c)
            } else if model.activePower == .hammer || model.activePower == .bomb {
                model.applyTargetedPower(atRow: r, col: c)
            }
        }
        #endif
    }

    @ViewBuilder
    private func cellView(_ r: Int, _ c: Int) -> some View {
        let point = GridPoint(r: r, c: c)
        let cell = model.board[r][c]
        let isClearing = model.clearing.contains(point)
        let isBlasting = model.blasting.contains(point)
        let ghostHit = ghost?.points.contains(point) ?? false
        let lineHint = (ghost?.completedRows.contains(r) ?? false)
            || (ghost?.completedCols.contains(c) ?? false)

        ZStack {
            // Empty well
            RoundedRectangle(cornerRadius: inner * 0.22, style: .continuous)
                .fill(lineHint && !cell.isFilled ? Theme.emptyCellHighlight : Theme.emptyCell)
                .frame(width: inner, height: inner)

            if let colorIndex = cell.colorIndex {
                BrickView(colorIndex: colorIndex, size: inner, giftMovesLeft: cell.giftMovesLeft)
                    .scaleEffect(isClearing ? 1.28 : (isBlasting ? 0.6 : 1))
                    .opacity(isClearing || isBlasting ? 0 : 1)
                    .brightness(lineHint ? 0.06 : 0)
            } else if ghostHit, let g = ghost {
                BrickView(colorIndex: g.colorIndex, size: inner)
                    .opacity(0.45)
                    .scaleEffect(0.92)
            } else if let movesLeft = cell.giftMovesLeft {
                GiftMark(movesLeft: movesLeft, size: inner)
            }

            if let aim, aim.cells.contains(point) {
                RoundedRectangle(cornerRadius: inner * 0.22, style: .continuous)
                    .stroke(aim.blocked ? Theme.aimBlocked : Theme.aim, lineWidth: max(2, cellSize * 0.07))
                    .frame(width: inner, height: inner)
            }
        }
        .frame(width: cellSize, height: cellSize)
    }
}
