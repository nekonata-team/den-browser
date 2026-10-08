import DenDomain
import DenPresentation
import Foundation

@MainActor
extension DenWindowModel {
    func toggleOverview() {
        if isOverviewPresented {
            hideOverview()
        } else {
            showOverview()
        }
    }

    func showOverview(deskID: DeskID? = nil, boardID: BoardID? = nil) {
        setTemporaryContext(.overview)
        overview.preparePresentation(deskID: deskID, boardID: boardID)
    }

    func hideOverview() {
        if temporaryContext == .overview { setTemporaryContext(nil) }
    }

    func beginOverviewBoardDrag(_ boardID: BoardID) -> Bool {
        guard temporaryContext == .overview else { return false }
        return overview.beginBoardDrag(boardID)
    }
}
