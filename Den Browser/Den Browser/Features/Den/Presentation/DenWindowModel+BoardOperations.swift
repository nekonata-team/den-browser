import DenDomain
import DenPresentation
import Foundation

@MainActor
extension DenWindowModel {
    func toggleFocusedBoardMaximized() {
        guard let focusedBoardID = controller.focusedDesk?.focusedBoardID else { return }
        maximizedBoardID = maximizedBoardID == focusedBoardID ? nil : focusedBoardID
        centerFocusedBoard()
    }

    func centerFocusedBoard() {
        controller.centerFocusedBoard()
    }

    func revealPreviousBoard() {
        guard controller.focusedDesk?.focusedBoardID != nil else { return }
        revealPreviousBoardRequest &+= 1
    }

    func revealNextBoard() {
        guard controller.focusedDesk?.focusedBoardID != nil else { return }
        revealNextBoardRequest &+= 1
    }

    func requestBoardDragCancellation() {
        controller.requestBoardDragCancellation()
    }

    func requestDeskDragCancellation() {
        controller.requestDeskDragCancellation()
    }
}
