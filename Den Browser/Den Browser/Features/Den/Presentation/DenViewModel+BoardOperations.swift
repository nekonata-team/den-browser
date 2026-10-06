import DenDomain
import Foundation

@MainActor
extension DenViewModel {
    func toggleFocusedBoardMaximized() {
        guard let focusedBoardID = store.focusedDesk?.focusedBoardID else { return }
        maximizedBoardID = maximizedBoardID == focusedBoardID ? nil : focusedBoardID
        centerFocusedBoard()
    }

    func centerFocusedBoard() {
        store.centerFocusedBoard()
    }

    func revealPreviousBoard() {
        guard store.focusedDesk?.focusedBoardID != nil else { return }
        revealPreviousBoardRequest &+= 1
    }

    func revealNextBoard() {
        guard store.focusedDesk?.focusedBoardID != nil else { return }
        revealNextBoardRequest &+= 1
    }

    func requestBoardDragCancellation() {
        store.requestBoardDragCancellation()
    }

    func requestDeskDragCancellation() {
        store.requestDeskDragCancellation()
    }
}
