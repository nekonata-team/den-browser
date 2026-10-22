import DenApplication
import DenDomain
import DenPresentationModels

extension DenController {
    func deskLifecycleNotifications() -> (DeskLifecycle.Notice) -> Void {
        { [self] notice in
            switch notice {
            case .presentCreatedDesk(let id):
                setFocusedDesk(id)
                onWindowEffect?(.dismissTemporaryPresentation)
                onWindowEffect?(.exitDenMode)
            case .didCreateDesk:
                dispatchDenOperationEvent(.deskCreated)
            case .willReplace(let boards):
                onWindowEffect?(.suppressBoardMutationAnimation)
                for board in boards { disposeRuntime(for: board.id) }
            case .didReplace(let deskID, let boards):
                anchorJumpOriginBoardIDByDesk.removeValue(forKey: deskID)
                invalidateReferences(toRemovedBoardIDs: Set(boards.map(\.id)))
                onWindowEffect?(.dismissTemporaryPresentation)
                onWindowEffect?(.exitDenMode)
            case .willDelete(let desk, let replacementID, let wasPresented):
                onWindowEffect?(.suppressBoardMutationAnimation)
                for board in desk.boards { disposeRuntime(for: board.id) }
                if wasPresented { setFocusedDesk(replacementID, autoPIP: false) }
            case .didDelete(let desk, let wasPresented):
                anchorJumpOriginBoardIDByDesk.removeValue(forKey: desk.id)
                invalidateReferences(toRemovedBoardIDs: Set(desk.boards.map(\.id)))
                invalidateReferences(toRemovedDeskID: desk.id)
                if wasPresented { onWindowEffect?(.exitDenMode) }
            }
        }
    }
}
