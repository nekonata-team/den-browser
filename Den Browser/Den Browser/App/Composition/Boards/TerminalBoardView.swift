import DenApplication
import DenDomain
import DenModels
import DenViews
import SwiftUI

struct TerminalBoardView: View {
    @Environment(ProfileWindowSession.self) private var session

    let board: BoardState
    let isFocused: Bool
    let focusRequest: BoardFocusRequest?
    let isDragging: Bool
    @ObservedObject var runtime: TerminalRuntime
    let profileColor: Color
    let width: Double
    let height: Double
    let isPointerFocusEnabled: Bool
    var isVisibleInViewport: Bool = true
    let onFocus: () -> Void
    let onRemove: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        DenViews.TerminalBoardView(
            model: BoardSurfaceModel(board: board, session: session),
            board: board,
            isFocused: isFocused,
            focusRequest: focusRequest,
            isDragging: isDragging,
            profileColor: profileColor,
            width: width,
            height: height,
            isPointerFocusEnabled: isPointerFocusEnabled,
            isVisibleInViewport: isVisibleInViewport,
            onFocus: onFocus,
            onRemove: onRemove,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded,
            surface: runtime.terminalView,
            onSurfaceReady: { window in
                guard
                    needsFirstResponderActivation(
                        window.firstResponder,
                        target: runtime.terminalView
                    )
                else { return true }
                return window.makeFirstResponder(runtime.terminalView)
            },
            onBeforeHide: {
                guard session.resources.data.snapshot.activeDrag == nil,
                    session.resources.terminalRuntimes[board.id] === runtime
                else { return }
                session.resources.facingCapture.captureTerminal(
                    boardID: board.id, terminalView: runtime.terminalView)
            },
            onSurfaceVisibilityChange: { runtime.setSurfaceVisible($0) },
            onAdjustFontSize: { runtime.adjustFontSize(by: $0) }
        )
    }
}
