import DenDomain
import DenPresentationModels
import SwiftUI

struct ActivatedBoardView: View {
    @Environment(DenController.self) private var controller

    let board: BoardState
    let isFocused: Bool
    let focusRequest: BoardFocusRequest?
    let isDragging: Bool
    let isPointerFocusEnabled: Bool
    let profileColor: Color
    let size: CGSize
    let isVisible: Bool
    let onFocus: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        switch board.kind {
        case .inspection:
            if let targetBoardID = board.sideBoardTargetBoardID {
                InspectionBoardView(
                    board: board,
                    isFocused: isFocused,
                    focusRequest: focusRequest,
                    isDragging: isDragging,
                    isPointerFocusEnabled: isPointerFocusEnabled,
                    profileColor: profileColor,
                    width: size.width,
                    height: size.height,
                    isVisibleInViewport: isVisible,
                    targetBoardID: targetBoardID,
                    onFocus: onFocus,
                    onRemove: { controller.removeBoard(board.id) },
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded
                )
            } else {
                Color.clear.frame(width: size.width, height: size.height)
            }
        case .tutorial:
            TutorialBoardView(
                board: board,
                isFocused: isFocused,
                isDragging: isDragging,
                profileColor: profileColor,
                width: size.width,
                height: size.height,
                isPointerFocusEnabled: isPointerFocusEnabled,
                onFocus: onFocus,
                onRemove: { controller.removeBoard(board.id) },
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded
            )
        case .terminal:
            TerminalBoardView(
                board: board,
                isFocused: isFocused,
                focusRequest: focusRequest,
                isDragging: isDragging,
                runtime: controller.terminalRuntime(for: board),
                profileColor: profileColor,
                width: size.width,
                height: size.height,
                isPointerFocusEnabled: isPointerFocusEnabled,
                isVisibleInViewport: isVisible,
                onFocus: onFocus,
                onRemove: { controller.removeBoard(board.id) },
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded
            )
        case .web:
            if let runtime = controller.webRuntimes[board.id] {
                WebBoardView(
                    board: board,
                    isFocused: isFocused,
                    focusRequest: focusRequest,
                    isDragging: isDragging,
                    runtime: runtime,
                    profileColor: profileColor,
                    width: size.width,
                    height: size.height,
                    isPointerFocusEnabled: isPointerFocusEnabled,
                    isVisibleInViewport: isVisible,
                    onFocus: onFocus,
                    onGoToFirst: { controller.goToFirstSheetInBoard(board.id) },
                    onGoBack: { controller.goBackInBoard(board.id) },
                    onGoForward: { controller.goForwardInBoard(board.id) },
                    onRemove: { controller.removeBoard(board.id) },
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded
                )
            } else {
                Color.clear.frame(width: size.width, height: size.height)
            }
        }
    }
}
