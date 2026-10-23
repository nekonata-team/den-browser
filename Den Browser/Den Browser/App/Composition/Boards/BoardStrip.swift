import DenApplication
import DenDomain
import DenPresentationModels
import DenViews
import SwiftUI

struct BoardStrip: View {
    @Environment(ProfileWindowSession.self) private var session
    let size: CGSize
    let shouldShowHeader: Bool
    let profileColor: Color
    let boardSpacing: CGFloat
    let boardHorizontalPadding: CGFloat
    let onOpenBoardAtEnd: (BoardID) -> Void

    var body: some View {
        DenViews.BoardStrip(
            model: BoardStripModel(
                state: session.resources.data, movement: session.resources.boardMovement,
                sizing: session.resources.boardSizing, deskUpdates: session.resources.deskUpdates,
                presentedDeskID: { [navigation = session.navigation] in navigation.presentedDeskID },
                prepareDrag: { session.connection.onWindowEffect?(.clearMaximizedBoard) },
                focus: { session.boardNavigation.focusBoard($0, exitsDenMode: true) },
                remove: { session.boardRemoval.removeBoard($0) },
                hasWebRuntime: { session.resources.webRuntimes[$0] != nil },
                activateWebRuntime: { _ = session.runtimes.webRuntime(for: $0) },
                centering: { session.configuration.preferences.boardCentering },
                motion: { session.configuration.preferences.motionPreference }),
            size: size, shouldShowHeader: shouldShowHeader, profileColor: profileColor,
            boardSpacing: boardSpacing, boardHorizontalPadding: boardHorizontalPadding,
            onOpenBoardAtEnd: onOpenBoardAtEnd
        ) { presentation in
            ActivatedBoardView(
                board: presentation.board, isFocused: presentation.isFocused,
                focusRequest: presentation.focusRequest, isDragging: presentation.isDragging,
                isPointerFocusEnabled: presentation.isPointerFocusEnabled,
                profileColor: presentation.profileColor, size: presentation.size,
                isVisible: presentation.isVisible, onFocus: presentation.onFocus,
                onDragChanged: presentation.onDragChanged, onDragEnded: presentation.onDragEnded)
        }
    }
}
