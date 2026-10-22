import AppKit
import DenDomain
import SwiftUI

public struct BoardResizeHandle: View {
    @State private var isHovering = false
    @State private var widthAtDragStart: Double?
    @State private var resizeWithNextBoardAtDragStart = false

    public let board: BoardState
    public let height: Double
    public let width: Double
    public let canResizeWithNextBoard: Bool
    public let onResizeStart: () -> Void
    public let onResize: (Double, Bool) -> Void
    public let onResizeEnd: () -> Void

    public init(
        board: BoardState, height: Double, width: Double, canResizeWithNextBoard: Bool,
        onResizeStart: @escaping () -> Void, onResize: @escaping (Double, Bool) -> Void,
        onResizeEnd: @escaping () -> Void
    ) {
        self.board = board
        self.height = height
        self.width = width
        self.canResizeWithNextBoard = canResizeWithNextBoard
        self.onResizeStart = onResizeStart
        self.onResize = onResize
        self.onResizeEnd = onResizeEnd
    }

    public var body: some View {
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
