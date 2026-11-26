import CoreGraphics

/// Pure geometry for translating a finger position into a board coordinate.
enum DragTargeting {

    /// How far above the finger a floating piece is drawn, when the player has turned
    /// "Float pieces" on, so the finger doesn't cover it or the square it will land on.
    static func lift(cellSize: CGFloat, floating: Bool = true) -> CGFloat {
        floating ? cellSize * 2.9 : 0
    }

    /// Whether there's room under the board to float pieces. A floating one-row piece
    /// reaches the bottom row with the finger 2.4 cells below the board, so the screen
    /// has to leave at least the whole lift there, which keeps the finger half a cell
    /// clear of the bottom edge.
    static func hasRoomToFloat(below spaceUnderBoard: CGFloat, cellSize: CGFloat) -> Bool {
        cellSize > 0 && spaceUnderBoard >= lift(cellSize: cellSize)
    }

    /// Top-left board cell that the dragged piece's bounding box currently sits on.
    /// The piece is drawn centred under the finger, pointer or pinch, or `lift` above
    /// it when floating.
    static func target(
        finger: CGPoint,
        shapeRows: Int,
        shapeCols: Int,
        gridOrigin: CGPoint,
        cellSize: CGFloat,
        floating: Bool = false
    ) -> (row: Int, col: Int) {
        let centerY = finger.y - lift(cellSize: cellSize, floating: floating)
        let originX = finger.x - CGFloat(shapeCols) * cellSize / 2
        let originY = centerY - CGFloat(shapeRows) * cellSize / 2

        let col = Int(((originX - gridOrigin.x) / cellSize).rounded())
        let row = Int(((originY - gridOrigin.y) / cellSize).rounded())
        return (row, col)
    }
}
