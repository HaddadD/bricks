import SwiftUI

/// A preview of the piece currently hovering over the board.
struct Ghost: Equatable {
    var points: Set<GridPoint>
    var colorIndex: Int
    /// Rows / columns that this placement would complete.
    var completedRows: Set<Int>
    var completedCols: Set<Int>
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

    private var pad: CGFloat { max(5, cellSize * 0.18) }
    private var gap: CGFloat { max(2, cellSize * 0.09) }
    private var inner: CGFloat { cellSize - gap }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cellSize * 0.5, style: .continuous)
                .fill(Theme.boardBackground)
                .shadow(color: Color(hex: 0xC9B8AC).opacity(0.35), radius: 10, y: 4)

            grid
        }
        .frame(
            width: cellSize * CGFloat(GameModel.size) + pad * 2,
            height: cellSize * CGFloat(GameModel.size) + pad * 2
        )
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
        .onTapGesture(coordinateSpace: .local) { point in
            guard model.activePower == .hammer || model.activePower == .bomb else { return }
            let c = Int(floor(point.x / cellSize))
            let r = Int(floor(point.y / cellSize))
            guard r >= 0, r < GameModel.size, c >= 0, c < GameModel.size else { return }
            model.applyTargetedPower(atRow: r, col: c)
        }
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
        }
        .frame(width: cellSize, height: cellSize)
    }
}
