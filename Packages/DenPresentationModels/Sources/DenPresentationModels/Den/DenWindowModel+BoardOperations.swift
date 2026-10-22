import DenDomain
import Foundation

@MainActor
public extension DenWindowModel {
    var focusedDesk: DeskState? { inputs.focusedDesk() }
    var focusedBoard: BoardState? { inputs.focusedBoard() }
    func focusBoard(_ id: BoardID, exitsDenMode: Bool = false) { boardActions.focusBoard(id, exitsDenMode) }

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
