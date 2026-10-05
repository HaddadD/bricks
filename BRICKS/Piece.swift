import Foundation

struct GridPoint: Hashable {
    var r: Int
    var c: Int
}

/// The footprint of a piece, stored as a small boolean matrix.
struct Shape: Equatable, Codable {
    let grid: [[Bool]]

    var rows: Int { grid.count }
    var cols: Int { grid.first?.count ?? 0 }

    var points: [GridPoint] {
        var out: [GridPoint] = []
        for r in 0..<rows {
            for c in 0..<cols where grid[r][c] {
                out.append(GridPoint(r: r, c: c))
            }
        }
        return out
    }

    var cellCount: Int { points.count }

    /// 90° clockwise rotation, used by the Rotate power-up.
    func rotated() -> Shape {
        var new = Array(repeating: Array(repeating: false, count: rows), count: cols)
        for r in 0..<rows {
            for c in 0..<cols where grid[r][c] {
                new[c][rows - 1 - r] = true
            }
        }
        return Shape(grid: new)
    }

    private static func filled(_ r: Int, _ c: Int) -> Shape {
        Shape(grid: Array(repeating: Array(repeating: true, count: c), count: r))
    }

    /// The complete 1010! piece set: 19 shapes.
    static let all: [Shape] = {
        var shapes: [Shape] = []

        // Single, plus horizontal and vertical bars of length 2...5.
        shapes.append(filled(1, 1))
        for n in 2...5 {
            shapes.append(filled(1, n))
            shapes.append(filled(n, 1))
        }

        // Squares.
        shapes.append(filled(2, 2))
        shapes.append(filled(3, 3))

        // 2x2 corners (3 cells), all four rotations.
        var corner2 = Shape(grid: [[true, true],
                                   [true, false]])
        for _ in 0..<4 {
            shapes.append(corner2)
            corner2 = corner2.rotated()
        }

        // 3x3 corners (5 cells), all four rotations.
        var corner3 = Shape(grid: [[true, true, true],
                                   [true, false, false],
                                   [true, false, false]])
        for _ in 0..<4 {
            shapes.append(corner3)
            corner3 = corner3.rotated()
        }

        return shapes
    }()

    static func random() -> Shape {
        all.randomElement() ?? filled(1, 1)
    }
}

extension Shape {
    /// Which of the nine piece kinds this is. Rotating a piece never changes its family,
    /// so a given size always wears the same colour whichever way round it sits.
    ///
    /// 0 single · 1 two-bar · 2 three-bar · 3 four-bar · 4 five-bar
    /// 5 2x2 square · 6 3x3 square · 7 three-cell corner · 8 five-cell corner
    var family: Int {
        let straight = (rows == 1 || cols == 1)
        switch cellCount {
        case 1:  return 0
        case 2:  return 1
        case 3:  return straight ? 2 : 7
        case 4:  return straight ? 3 : 5
        case 5:  return straight ? 4 : 8
        case 9:  return 6
        default: return 0
        }
    }
}

/// A piece sitting in the tray, waiting to be dragged onto the board.
struct TrayPiece: Identifiable, Equatable, Codable {
    let id: UUID
    var shape: Shape

    /// Colour follows the piece's family rather than being random, so every five-bar is
    /// the same colour as every other five-bar, upright or on its side.
    var colorIndex: Int { Theme.familyColor(shape.family) }

    init(shape: Shape) {
        self.id = UUID()
        self.shape = shape
    }

    static func random() -> TrayPiece {
        TrayPiece(shape: .random())
    }
}
