import CoreGraphics

/// Pure geometry for translating a finger position into a board coordinate.
enum DragTargeting {

    /// Top-left board cell that the dragged piece's bounding box currently sits on.
    /// The piece is drawn centred right under the finger, pointer or pinch.
    static func target(
        finger: CGPoint,
        shapeRows: Int,
        shapeCols: Int,
        gridOrigin: CGPoint,
        cellSize: CGFloat
    ) -> (row: Int, col: Int) {
        let originX = finger.x - CGFloat(shapeCols) * cellSize / 2
        let originY = finger.y - CGFloat(shapeRows) * cellSize / 2

        let col = Int(((originX - gridOrigin.x) / cellSize).rounded())
        let row = Int(((originY - gridOrigin.y) / cellSize).rounded())
        return (row, col)
    }
}
