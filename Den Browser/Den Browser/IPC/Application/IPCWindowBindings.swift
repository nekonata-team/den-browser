import DenApplication
import DenDomain
import Foundation

@MainActor
struct IPCWindowBindings {
    struct Board {
        let webRuntime: (BoardState) -> WebRuntime
        let terminalRuntime: (BoardState) -> TerminalRuntime
        let focus: (BoardID) -> Void
        let createInspection: (BoardID, Bool) -> BoardID?
        let sendSignal: (Int32, BoardState) async throws -> Int32
        let creationNotice: (BoardCreation.Notice) -> Void
        let removalNotice: (BoardRemoval.Notice) -> Void
    }

    struct Desk {
        let isAvailable: (DeskID) -> Bool
        let lifecycleNotice: (DeskLifecycle.Notice) -> Void
    }

    struct Drawer {
        let keepNotice: (DrawerItems.Notice) -> Void
        let itemNotice: (DrawerItems.Notice) -> Void
        let placementNotice: (UUID) -> (BoardCreation.Notice) -> Void
        let didKeep: () -> Void
        let didPlace: () -> Void
    }

    let id: UUID
    let profileID: ProfileID
    let resources: DenProfileResources
    let presentedDeskID: () -> DeskID
    let searchEngine: () -> SearchEngine
    let inheritedBoardWidth: () -> Double
    let board: Board
    let desk: Desk
    let drawer: Drawer
}
