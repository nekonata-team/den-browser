import DenApplication
import DenDomain
import DenModels
import DenViews
import SwiftUI

struct BoardRail: View {
    let profileColor: Color
    @Environment(ProfileWindowSession.self) private var session
    var body: some View {
        DenViews.BoardRail(
            profileColor: profileColor,
            boardModel: { BoardSurfaceModel(board: $0, session: session) },
            focusBoard: { session.boardNavigation.focusBoard($0) },
            reorderBoard: { boardID, index, deskID, overview in
                if overview {
                    session.resources.boardMovement.reorder(boardID, to: index, in: deskID)
                } else {
                    session.boardNavigation.focusBoard(boardID)
                    session.resources.boardMovement.preview(
                        boardID, to: index, in: session.navigation.presentedDeskID)
                }
                session.resources.save()
            }, toggleAnchor: { session.boardNavigation.toggleAnchorBoard($0, in: $1) },
            favicon: { id in
                if let runtime = session.resources.webRuntimes[id] {
                    ObservedBoardRailFavicon(runtime: runtime)
                } else {
                    DenViews.BoardRailFavicon(url: nil)
                }
            })
    }
}

private struct ObservedBoardRailFavicon: View {
    @ObservedObject var runtime: WebRuntime
    var body: some View { DenViews.BoardRailFavicon(url: runtime.faviconURL) }
}
