import DenDomain
import DenViews
import SwiftUI

struct BoardRail: View {
    let profileColor: Color
    @Environment(DenController.self) private var controller
    var body: some View {
        DenViews.BoardRail(
            profileColor: profileColor,
            boardModel: { controller.boardSurfaceModel(for: $0) },
            focusBoard: { controller.focusBoard($0) },
            reorderBoard: { boardID, index, deskID, overview in
                if overview {
                    guard let deskIndex = controller.state.desks.firstIndex(where: { $0.id == deskID }) else { return }
                    controller.reorderBoardGroup(containing: boardID, to: index, in: DeskIndex(rawValue: deskIndex))
                } else {
                    controller.focusBoard(boardID)
                    controller.previewBoardMove(boardID, to: index)
                }
                controller.save()
            }, toggleAnchor: { controller.toggleAnchorBoard($0, in: $1) },
            favicon: { id in
                if let runtime = controller.webRuntimes[id] {
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
