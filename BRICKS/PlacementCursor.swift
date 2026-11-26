/// Where a footprint sits on the board while it is positioned by remote or by taps
/// instead of dragged: Apple TV and Apple Watch. The footprint is a piece's bounding box,
/// or a single cell when aiming a hammer or a bomb.
///
/// `row`/`col` is the footprint's top-left cell, and it is always kept fully on the board.
struct PlacementCursor: Equatable {
    private(set) var row: Int
    private(set) var col: Int
    let rows: Int
    let cols: Int
    let boardSize: Int

    /// Starts centred on the board.
    init(rows: Int, cols: Int, boardSize: Int) {
        self.rows = rows
        self.cols = cols
        self.boardSize = boardSize
        row = (boardSize - rows) / 2
        col = (boardSize - cols) / 2
    }

    /// Nudges the footprint, stopping at the edges rather than wrapping.
    mutating func move(rows dRow: Int, cols dCol: Int) {
        row = clamp(row + dRow, max: boardSize - rows)
        col = clamp(col + dCol, max: boardSize - cols)
    }

    /// Centres the footprint on a cell, as far as the edges allow; used for tap-to-aim.
    mutating func centre(onRow r: Int, col c: Int) {
        row = clamp(r - (rows - 1) / 2, max: boardSize - rows)
        col = clamp(c - (cols - 1) / 2, max: boardSize - cols)
    }

    /// Whether a cell lies inside the footprint's bounding box.
    func covers(row r: Int, col c: Int) -> Bool {
        (row..<row + rows).contains(r) && (col..<col + cols).contains(c)
    }

    private func clamp(_ value: Int, max upper: Int) -> Int {
        min(Swift.max(value, 0), upper)
    }
}
