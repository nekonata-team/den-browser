import Foundation

extension DenStore {
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

    func enterBoardFromActivity(_ boardID: UUID) {
        guard boardIndices(for: boardID) != nil else { return }
        setTemporaryContext(nil)
        focusBoard(boardID, exitsDenMode: true)
    }
}
