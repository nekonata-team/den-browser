import DenDomain
import DenPresentationModels
import DenViews
import SwiftUI

struct BoardStrip: View {
    @Environment(DenController.self) private var controller
    let size: CGSize
    let shouldShowHeader: Bool
    let profileColor: Color
    let boardSpacing: CGFloat
    let boardHorizontalPadding: CGFloat
    let onOpenBoardAtEnd: (BoardID) -> Void

    var body: some View {
        DenViews.BoardStrip(
            model: BoardStripModel(
                state: controller.storage.data, movement: controller.storage.boardMovement,
                sizing: controller.storage.boardSizing, deskUpdates: controller.storage.deskUpdates,
                presentedDeskID: { [navigation = controller.navigation] in navigation.presentedDeskID },
                prepareDrag: { controller.onWindowEffect?(.clearMaximizedBoard) },
                focus: { controller.focusBoard($0, exitsDenMode: true) },
                remove: { controller.removeBoard($0) },
                hasWebRuntime: { controller.webRuntimes[$0] != nil },
                activateWebRuntime: { _ = controller.webRuntime(for: $0) },
                centering: { controller.preferences.boardCentering },
                motion: { controller.preferences.motionPreference }),
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
