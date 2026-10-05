import SwiftUI

/// Draws a piece's footprint at an arbitrary brick size.
struct PieceView: View {
    let shape: Shape
    let colorIndex: Int
    let brickSize: CGFloat
    var gap: CGFloat = 2

    var body: some View {
        VStack(spacing: gap) {
            ForEach(0..<shape.rows, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<shape.cols, id: \.self) { c in
                        if shape.grid[r][c] {
                            BrickView(colorIndex: colorIndex, size: brickSize)
                        } else {
                            Color.clear.frame(width: brickSize, height: brickSize)
                        }
                    }
                }
            }
        }
    }
}

struct TrayView: View {
    @ObservedObject var model: GameModel
    let cellSize: CGFloat
    let slotWidth: CGFloat
    /// Index currently being dragged, hidden from the tray.
    let draggingIndex: Int?
    let onDragChanged: (Int, CGPoint) -> Void
    let onDragEnded: (Int) -> Void

    private var trayBrick: CGFloat { cellSize * 0.62 }
    private var trayGap: CGFloat { 2 }
    /// Side of the largest piece (3x3) at tray scale — the hit area every slot gets.
    private var grabSide: CGFloat { trayBrick * 3 + trayGap * 2 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                slot(i)
                    .frame(width: slotWidth, height: cellSize * 2.7)
            }
        }
    }

    @ViewBuilder
    private func slot(_ i: Int) -> some View {
        ZStack {
            if let piece = model.tray[i] {
                TraySlot(
                    model: model,
                    index: i,
                    piece: piece,
                    brickSize: trayBrick,
                    grabSide: grabSide,
                    hidden: draggingIndex == i,
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded
                )
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.tray[i]?.id)
    }
}

/// One tray slot.
///
/// Tapping and dragging share a single gesture on purpose. Attaching a TapGesture
/// alongside a DragGesture lets the tap win arbitration on release, which cancels the
/// drag before it can commit — so movement past a small threshold is what separates
/// "this is a drag" from "this is a tap".
private struct TraySlot: View {
    @ObservedObject var model: GameModel
    let index: Int
    let piece: TrayPiece
    let brickSize: CGFloat
    let grabSide: CGFloat
    let hidden: Bool
    let onDragChanged: (Int, CGPoint) -> Void
    let onDragEnded: (Int) -> Void

    @State private var dragging = false

    /// Movement past this many points counts as a drag rather than a tap.
    private let dragThreshold: CGFloat = 8

    private var rotating: Bool { model.activePower == .rotate }

    var body: some View {
        PieceView(shape: piece.shape, colorIndex: piece.colorIndex, brickSize: brickSize)
            .opacity(hidden ? 0 : (model.canPlaceAnywhere(piece.shape) ? 1 : 0.32))
            .scaleEffect(rotating ? 1.06 : 1)
            .overlay(rotateBadge)
            // The grab area is always the footprint of the largest piece (3x3), so a 1x1
            // is as easy to pick up as a 3x3 rather than being a tiny target.
            .frame(width: grabSide, height: grabSide)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("game"))
                    .onChanged { value in
                        guard model.activePower == nil || rotating else { return }
                        if !dragging {
                            let moved = hypot(value.translation.width, value.translation.height)
                            guard moved > dragThreshold else { return }
                            dragging = true
                            // Dragging is what ends a rotating session.
                            model.endRotateMode()
                        }
                        onDragChanged(index, value.location)
                    }
                    .onEnded { _ in
                        if dragging {
                            dragging = false
                            onDragEnded(index)
                        } else if rotating {
                            model.rotateTray()
                        }
                    }
            )
    }

    @ViewBuilder
    private var rotateBadge: some View {
        if rotating {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PowerUp.rotate.tint, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .padding(-6)
        }
    }
}
