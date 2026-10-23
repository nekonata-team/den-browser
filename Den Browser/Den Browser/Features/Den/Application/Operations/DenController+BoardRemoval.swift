import DenApplication
import DenDomain
import DenPresentationModels

extension DenController {
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
                    disposeRuntime(for: board.id)
                    inputSourceTracker.boardWillRemove(board.id)
                }
                onWindowEffect?(
                    .overviewBoardRemoved(
                        boardID: result.historyEntry.board.id, deskID: source.id,
                        oldIndex: result.historyEntry.sourceBoardIndex))
                invalidateReferences(toRemovedBoardIDs: removedIDs)
            case .restored(let board, let deskID, let present):
                let changedDesk = present && setFocusedDesk(deskID)
                if !changedDesk && presentedDeskID == deskID { markNotificationsRead(for: board.id) }
            }
        }
    }

    func handleBoardRestorationResult(_ result: BoardRemoval.RestoreResult, present: Bool) -> BoardID? {
        switch result {
        case .restored(let id):
            return id
        case .existingTutorial(let id):
            if present { focusBoard(id, exitsDenMode: true) }
            reportFeedback("Tutorial Board is already open.", severity: .warning)
            return id
        case .emptyHistory:
            reportFeedback("No removed board to restore.", severity: .warning)
            return nil
        case .rejected(let failure):
            switch failure {
            case .sideBoardAlreadyExists:
                reportFeedback("A Side Board already exists for this Board.", severity: .warning)
            case .targetBoardMissing:
                reportFeedback("The target Board no longer exists.", severity: .warning)
            case .destinationDeskMissing:
                break
            }
            return nil
        }
    }
}
