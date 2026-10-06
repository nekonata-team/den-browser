import Foundation

@MainActor
extension DenViewModel {
    func toggleOverview() {
        if isOverviewPresented {
            hideOverview()
        } else {
            showOverview()
        }
    }

    func showOverview(deskID: UUID? = nil, boardID: UUID? = nil) {
        setTemporaryContext(.overview)
        overview.preparePresentation(deskID: deskID, boardID: boardID)
    }

    func hideOverview() {
        if temporaryContext == .overview { setTemporaryContext(nil) }
    }

    func beginOverviewBoardDrag(_ boardID: UUID) -> Bool {
        guard temporaryContext == .overview else { return false }
        return overview.beginBoardDrag(boardID)
    }
}
