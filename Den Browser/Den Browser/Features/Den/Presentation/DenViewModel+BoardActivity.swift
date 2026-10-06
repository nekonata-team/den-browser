import Foundation

@MainActor
extension DenViewModel {
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
        guard store.boardIndices(for: boardID) != nil else { return }
        setTemporaryContext(nil)
        store.focusBoard(boardID, exitsDenMode: true)
    }
}
