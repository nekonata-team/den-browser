import DenDomain
import DenPresentationModels
import Foundation

extension IPCWindowBindings {
    init(id: UUID, profileID: ProfileID, controller: DenController) {
        self.init(
            id: id, profileID: profileID, resources: controller.storage,
            presentedDeskID: { [navigation = controller.navigation] in navigation.presentedDeskID },
            searchEngine: { [preferences = controller.preferences] in preferences.searchEngine },
            inheritedBoardWidth: { [navigation = controller.navigation] in
                navigation.focusedBoard?.width ?? BuiltInDeskPreset.boardWidth
            },
            board: Board(
                webRuntime: { controller.webRuntime(for: $0) },
                terminalRuntime: { controller.terminalRuntime(for: $0) },
                focus: {
                    controller.onWindowEffect?(.dismissTemporaryPresentation)
                    controller.focusBoard($0, exitsDenMode: true)
                    controller.centerFocusedBoard()
                },
                createInspection: { controller.createInspectionBoard(targetBoardID: $0, focus: $1) },
                sendSignal: { try await controller.sendSignal($0, to: $1) },
                creationNotice: controller.boardCreationNotifications(),
                removalNotice: controller.boardRemovalNotifications()),
            desk: Desk(
                isAvailable: { controller.canPresentDesk?($0) ?? true },
                lifecycleNotice: controller.deskLifecycleNotifications()),
            drawer: Drawer(
                keepNotice: controller.drawerItemNotifications(opensDrawer: false, selectsItem: false),
                itemNotice: controller.drawerItemNotifications(),
                placementNotice: { controller.drawerBoardCreationNotifications($0) },
                didKeep: { controller.reportFeedback("Kept in Drawer.", severity: .success) },
                didPlace: { controller.onWindowEffect?(.dismissTemporaryPresentation) }))
    }
}
