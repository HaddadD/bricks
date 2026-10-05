import CoreGraphics

/// Pure geometry for translating a finger position into a board coordinate.
enum DragTargeting {

    /// How far above the finger the dragged piece floats, so the hand never covers it
    /// or the square it is about to land on.
    static func lift(cellSize: CGFloat) -> CGFloat { cellSize * 2.9 }

    /// Top-left board cell that the dragged piece's bounding box currently sits on.
    /// The piece is drawn centred on a point `lift` above the finger.
    static func target(
        finger: CGPoint,
        shapeRows: Int,
        shapeCols: Int,
        gridOrigin: CGPoint,
        cellSize: CGFloat
    ) -> (row: Int, col: Int) {
        let centerY = finger.y - lift(cellSize: cellSize)
        let originX = finger.x - CGFloat(shapeCols) * cellSize / 2
        let originY = centerY - CGFloat(shapeRows) * cellSize / 2

        let col = Int(((originX - gridOrigin.x) / cellSize).rounded())
        let row = Int(((originY - gridOrigin.y) / cellSize).rounded())
        return (row, col)
    }
}
