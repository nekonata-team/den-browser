import DenDomain
import Foundation

enum DenWindowEffect {
    case feedback(DenFeedback?)
    case presentOpenBoard(initialURL: URL?, afterBoardID: BoardID?)
    case presentOverview(deskID: DeskID?, boardID: BoardID?)
    case presentEditBoardLink
    case presentEssentialsPrefix
    case presentZmxSessions(returnsToOpenBoard: Bool, selectedSessionName: String?)
    case presentZmxDuplicationPanel(rootSessionName: String)
    case openBoardResult(String?)
    case dismissTemporaryPresentation
    case exitDenMode
    case centerFocusedBoard
    case revealPreviousBoard
    case revealNextBoard
    case requestConfirmation(DenConfirmationRequest)
    case openDrawerItem(UUID)
    case notificationAdded(UUID)
    case resetPresentation
    case fullscreenChanged(Bool)
    case cancelBoardDrag
    case cancelDeskDrag
    case dismissDeskFilter
    case clearMaximizedBoard
    case runtimeFocusedBoard(BoardID)
    case drawerItemRemoved(UUID, previousItems: [DrawerItem], advancesPreview: Bool, focusNext: Bool)
    case drawerCleared
    case drawerItemKept(UUID, opensDrawer: Bool, selectsItem: Bool)
    case drawerItemRestored(UUID)
    case boardLinkFocusRequested(BoardLinkFocusIntent)
    case boardRemovalRequested(BoardRemovalIntent)
    case clearBoardInputRequests
    case suppressBoardMutationAnimation
    case boardRemoved(BoardID)
    case deskRemoved(DeskID)
    case overviewBoardRemoved(boardID: BoardID, deskID: DeskID, oldIndex: Int)
}
