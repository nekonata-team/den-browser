import DenApplication
import DenDomain
import DenModels
import Foundation

@MainActor
final class BoardRemovalPresentation {
    private let context: WindowNativeContext
    private let boardNavigation: BoardNavigation
    private var runtimes: BoardRuntimeAccess { context.runtimes }
    private var storage: DenProfileResources { context.storage }
    private var focusedDesk: DeskState? { context.focusedDesk }
    private var presentedDeskID: DeskID { context.navigation.presentedDeskID }
    private var navigation: WindowNavigationBindings { context.navigation }
    private var inputSourceTracker: BoardInputSourceTracker { context.inputSourceTracker }
    private var onWindowEffect: ((DenWindowEffect) -> Void)? { context.connection.onWindowEffect }
    private var webRuntimes: [BoardID: WebRuntime] {
        get { context.storage.webRuntimes }
        set { context.storage.webRuntimes = newValue }
    }

    init(context: WindowNativeContext, boardNavigation: BoardNavigation) {
        self.context = context
        self.boardNavigation = boardNavigation
    }

    func boardRemovalNotifications() -> (BoardRemoval.Notice) -> Void {
        { [self] notice in
            switch notice {
            case .suppressMutationAnimation:
                onWindowEffect?(.suppressBoardMutationAnimation)
            case .prepareRemoval(let origin):
                _ = prepareBoardRemoval(origin: origin)
            case .removed(let source, let result):
                let removedIDs = Set(result.removedBoards.map(\.id))
                if source.anchorBoardID.map(removedIDs.contains) == true
                    || navigation.anchorJumpOriginBoardIDByDesk[source.id].map(removedIDs.contains) == true
                {
                    navigation.anchorJumpOriginBoardIDByDesk.removeValue(forKey: source.id)
                }
                for board in result.removedBoards {
                    if board.isInspection, let target = board.sideBoardTargetBoardID {
                        webRuntimes[target]?.stopInspection()
                    }
                    runtimes.disposeRuntime(for: board.id)
                    inputSourceTracker.boardWillRemove(board.id)
                }
                onWindowEffect?(
                    .overviewBoardRemoved(
                        boardID: result.historyEntry.board.id, deskID: source.id,
                        oldIndex: result.historyEntry.sourceBoardIndex))
                storage.invalidateReferences(toRemovedBoardIDs: removedIDs)
            case .restored(let board, let deskID, let present):
                let changedDesk = present && boardNavigation.setFocusedDesk(deskID)
                if !changedDesk && presentedDeskID == deskID {
                    storage.notificationOperations.markAllRead(for: board.id)
                }
            }
        }
    }

    func handleBoardRestorationResult(_ result: BoardRemoval.RestoreResult, present: Bool) -> BoardID? {
        switch result {
        case .restored(let id):
            return id
        case .existingTutorial(let id):
            if present { boardNavigation.focusBoard(id, exitsDenMode: true) }
            context.feedback.publish("Tutorial Board is already open.", severity: .warning)
            return id
        case .emptyHistory:
            context.feedback.publish("No removed board to restore.", severity: .warning)
            return nil
        case .rejected(let failure):
            switch failure {
            case .sideBoardAlreadyExists:
                context.feedback.publish("A Side Board already exists for this Board.", severity: .warning)
            case .targetBoardMissing:
                context.feedback.publish("The target Board no longer exists.", severity: .warning)
            case .destinationDeskMissing:
                break
            }
            return nil
        }
    }

    func removeFocusedBoard(focusNext: Bool = false) {
        guard let boardID = focusedDesk?.focusedBoardID else { return }
        removeBoard(boardID, focusNext: focusNext)
    }

    func removeBoard(
        _ boardID: BoardID,
        focusNext: Bool = false,
        origin: BoardOperationOrigin = .interactive
    ) {
        storage.boardRemoval.remove(
            boardID, presentedDeskID: presentedDeskID, focusNext: focusNext, origin: origin,
            notify: boardRemovalNotifications())
    }

    @discardableResult
    func restoreRecentlyRemovedBoard(present: Bool = true) -> BoardID? {
        let result = storage.boardRemoval.restore(
            presentedDeskID: presentedDeskID, present: present, notify: boardRemovalNotifications())
        return handleBoardRestorationResult(result, present: present)
    }

    @discardableResult
    func prepareBoardRemoval(origin: BoardOperationOrigin) -> BoardRemovalIntent {
        let intent = BoardRemovalIntent(origin: origin)
        onWindowEffect?(.boardRemovalRequested(intent))
        return intent
    }
}
