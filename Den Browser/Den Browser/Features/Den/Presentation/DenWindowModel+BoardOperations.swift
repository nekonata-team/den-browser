import DenDomain
import DenPresentation
import Foundation

@MainActor
extension DenWindowModel {
    func toggleFocusedBoardMaximized() {
        guard let focusedBoardID = inputs.focusedDesk()?.focusedBoardID else { return }
        maximizedBoardID = maximizedBoardID == focusedBoardID ? nil : focusedBoardID
        centerFocusedBoard()
    }

    func centerFocusedBoard() {
        boardActions.centerFocusedBoard()
    }

    func revealPreviousBoard() {
        guard inputs.focusedDesk()?.focusedBoardID != nil else { return }
        revealPreviousBoardRequest &+= 1
    }

    func revealNextBoard() {
        guard inputs.focusedDesk()?.focusedBoardID != nil else { return }
        revealNextBoardRequest &+= 1
    }

    func requestBoardDragCancellation() {
        boardActions.cancelBoardDrag()
    }

    func requestDeskDragCancellation() {
        boardActions.cancelDeskDrag()
    }
}
