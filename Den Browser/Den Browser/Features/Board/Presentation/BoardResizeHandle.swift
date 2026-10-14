import AppKit
import DenDomain
import SwiftUI

struct BoardResizeHandle: View {
    @State private var isHovering = false
    @State private var widthAtDragStart: Double?
    @State private var resizeWithNextBoardAtDragStart = false

    let board: BoardState
    let height: Double
    let width: Double
    let canResizeWithNextBoard: Bool
    let onResizeStart: () -> Void
    let onResize: (Double, Bool) -> Void
    let onResizeEnd: () -> Void

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(Color.primary.opacity(0.38))
                    .frame(width: 2, height: 34)
                    .opacity(isHovering || widthAtDragStart != nil ? 1 : 0)
            }
            .onHover { isHovering = $0 }
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if widthAtDragStart == nil {
                            widthAtDragStart = board.width
                            resizeWithNextBoardAtDragStart =
                                canResizeWithNextBoard && NSEvent.modifierFlags.contains(.shift)
                            onResizeStart()
                        }
                        onResize(
                            (widthAtDragStart ?? board.width) + value.translation.width,
                            resizeWithNextBoardAtDragStart)
                    }
                    .onEnded { _ in
                        widthAtDragStart = nil
                        resizeWithNextBoardAtDragStart = false
                        onResizeEnd()
                    }
            )
            .help(
                canResizeWithNextBoard
                    ? "Drag to resize Board; hold Shift to resize with next Board"
                    : "Drag to resize Board"
            )
            .accessibilityLabel("Resize \(board.displayName) Board")
            .accessibilityValue("\(Int(board.width.rounded())) points")
            .accessibilityAdjustableAction { adjustWidth(for: $0) }
    }

    private func adjustWidth(for direction: AccessibilityAdjustmentDirection) {
        guard (BoardState.minimumWidth...BoardState.maximumWidth).contains(board.width) else { return }
        let delta = direction == .increment ? 80.0 : -80.0
        let adjustedWidth = BoardState.constrainedWidth(board.width + delta)
        guard adjustedWidth != board.width else { return }
        onResizeStart()
        onResize(adjustedWidth, false)
        onResizeEnd()
    }
}
