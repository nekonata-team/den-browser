import DenDomain
import Foundation

@MainActor
public extension DenWindowModel {
    var focusedDesk: DeskState? { navigation.focusedDesk }
    var focusedBoard: BoardState? { navigation.focusedBoard }
    func focusBoard(_ id: BoardID, exitsDenMode: Bool = false) { boardActions.focusBoard(id, exitsDenMode) }

    func toggleFocusedBoardMaximized() {
        guard let focusedBoardID = navigation.focusedDesk?.focusedBoardID else { return }
        maximizedBoardID = maximizedBoardID == focusedBoardID ? nil : focusedBoardID
        centerFocusedBoard()
    }

    func centerFocusedBoard() {
        boardActions.centerFocusedBoard()
    }

    func revealPreviousBoard() {
        guard navigation.focusedDesk?.focusedBoardID != nil else { return }
        revealPreviousBoardRequest &+= 1
    }

    func revealNextBoard() {
        guard navigation.focusedDesk?.focusedBoardID != nil else { return }
        revealNextBoardRequest &+= 1
    }

    func requestBoardDragCancellation() {
        boardActions.cancelBoardDrag()
    }

    func requestDeskDragCancellation() {
        boardActions.cancelDeskDrag()
    }
}
