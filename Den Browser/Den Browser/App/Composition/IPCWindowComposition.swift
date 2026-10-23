import DenApplication
import DenDomain
import DenModels
import Foundation

extension IPCWindowBindings {
    init(id: UUID, profileID: ProfileID, session: ProfileWindowSession) {
        self.init(
            id: id, profileID: profileID, resources: session.resources,
            presentedDeskID: { [navigation = session.navigation] in navigation.presentedDeskID },
            searchEngine: { [preferences = session.configuration.preferences] in preferences.searchEngine },
            inheritedBoardWidth: { [navigation = session.navigation] in
                navigation.focusedBoard?.width ?? BuiltInDeskPreset.boardWidth
            },
            board: Board(
                webRuntime: { session.runtimes.webRuntime(for: $0) },
                terminalRuntime: { session.runtimes.terminalRuntime(for: $0) },
                focus: {
                    session.connection.onWindowEffect?(.dismissTemporaryPresentation)
                    session.boardNavigation.focusBoard($0, exitsDenMode: true)
                    session.boardNavigation.centerFocusedBoard()
                },
                createInspection: { session.sideBoards.createInspectionBoard(targetBoardID: $0, focus: $1) },
                sendSignal: { try await session.runtimes.sendSignal($0, to: $1) },
                creationNotice: session.boardOpening.boardCreationNotifications(),
                removalNotice: session.boardRemoval.boardRemovalNotifications()),
            desk: Desk(
                isAvailable: { session.context.canPresentDesk?($0) ?? true },
                lifecycleNotice: session.desks.deskLifecycleNotifications()),
            drawer: Drawer(
                keepNotice: session.drawer.drawerItemNotifications(opensDrawer: false, selectsItem: false),
                itemNotice: session.drawer.drawerItemNotifications(),
                placementNotice: { session.drawer.drawerBoardCreationNotifications($0) },
                didKeep: { session.context.feedback.publish("Kept in Drawer.", severity: .success) },
                didPlace: { session.connection.onWindowEffect?(.dismissTemporaryPresentation) }))
    }
}
