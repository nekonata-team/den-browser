import DenDomain
import DenPresentation
import Foundation

@MainActor
extension DenWindowModel {
    func toggleBoardActivity() {
        if isBoardActivityPresented {
            hideBoardActivity()
        } else {
            setTemporaryContext(.boardActivity)
        }
    }

    func hideBoardActivity() {
        if isBoardActivityPresented {
            setTemporaryContext(nil)
        }
    }

    func enterBoardFromActivity(_ boardID: BoardID) {
        guard controller.boardIndices(for: boardID) != nil else { return }
        setTemporaryContext(nil)
        controller.focusBoard(boardID, exitsDenMode: true)
    }
}
