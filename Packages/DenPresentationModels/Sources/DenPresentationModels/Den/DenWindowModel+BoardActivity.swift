import DenDomain
import Foundation

@MainActor
public extension DenWindowModel {
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
        guard inputs.board(boardID) != nil else { return }
        setTemporaryContext(nil)
        boardActions.focusBoard(boardID, true)
    }
}
