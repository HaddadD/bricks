import CoreGraphics

/// Pure geometry for translating a finger position into a board coordinate.
enum DragTargeting {

    /// How far above the finger, pointer or pinch a floating piece is drawn, when the
    /// player has turned "Float pieces" on, so the hand doesn't cover it or the square it
    /// will land on.
    ///
    /// - `room`: the space between the board and the bottom edge of the game.
    /// - `toEdge`: how far the finger is from that edge.
    ///
    /// The piece floats 2.9 cells up. With that much room under the board, the finger can
    /// always carry it to the bottom row and it never changes. With less (the iPhone Duo,
    /// a wide iPad or Mac window, where the tray sits beside the board), the piece settles
    /// back toward the finger as the finger nears the edge, down to the room there is.
    /// At half a cell from the edge it's exactly `room` up, which puts a one-row piece on
    /// the bottom row, so every row stays in reach.
    static func lift(cellSize: CGFloat, floating: Bool = true,
                     room: CGFloat = .infinity, toEdge: CGFloat = .infinity) -> CGFloat {
        guard floating else { return 0 }
        let full = cellSize * 2.9
        let settled = max(0, min(full, room))
        return min(full, max(settled, toEdge - cellSize / 2))
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
        floating: Bool = false,
        room: CGFloat = .infinity,
        edge: CGFloat = .infinity
    ) -> (row: Int, col: Int) {
        let centerY = finger.y - lift(cellSize: cellSize, floating: floating, room: room, toEdge: edge - finger.y)
        let originX = finger.x - CGFloat(shapeCols) * cellSize / 2
        let originY = centerY - CGFloat(shapeRows) * cellSize / 2

        let col = Int(((originX - gridOrigin.x) / cellSize).rounded())
        let row = Int(((originY - gridOrigin.y) / cellSize).rounded())
        return (row, col)
    }
}
