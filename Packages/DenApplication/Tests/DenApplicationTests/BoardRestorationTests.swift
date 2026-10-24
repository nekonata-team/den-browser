import DenApplication
import DenDomain
import Testing

nonisolated struct BoardRestorationTests {
    @Test
    func restorationInsertsAfterExistingGroup() {
        // Arrange
        let primary = BoardState(label: "Primary", width: 520, currentSheetURL: nil)
        let side = BoardState(width: 390, targetBoardID: primary.id)
        let inserted = BoardState(label: "Inserted", width: 520, currentSheetURL: nil)
        let target = DeskState(label: "Target", boards: [primary, side])
        let history = RecentlyRemovedBoard(
            board: inserted, sourceDeskID: target.id, sourceBoardIndex: BoardIndex(rawValue: 1))

        // Act
        let outcome = BoardRestoration.restore(history, in: [target], presentedDeskID: target.id)
        guard case .restored(_, let desk) = outcome else {
            Issue.record("The removed Board should be restored.")
            return
        }
        let result = desk.boards

        // Assert
        #expect(result.map(\.id) == [primary.id, side.id, inserted.id])
    }

    @Test func restoresGroupToOriginalDeskAndFocusesPrimary() {
        // Arrange
        let primary = BoardState(label: "Primary", width: 520, currentSheetURL: nil)
        let side = BoardState(width: 390, targetBoardID: primary.id)
        let before = BoardState(label: "Before", width: 520, currentSheetURL: nil)
        let after = BoardState(label: "After", width: 520, currentSheetURL: nil)
        let source = DeskState(
            label: "Source", boards: [before, after], focusedBoardID: after.id,
            scrollOffsetX: 180, anchorBoardID: after.id)
        let presented = DeskState(label: "Presented", boards: [])
        let history = RecentlyRemovedBoard(
            board: primary, sideBoard: side, sourceDeskID: source.id, sourceBoardIndex: BoardIndex(rawValue: 1))

        // Act
        let outcome = BoardRestoration.restore(history, in: [presented, source], presentedDeskID: presented.id)

        // Assert
        guard case .restored(let deskIndex, let desk) = outcome else {
            Issue.record("The removed Board group should be restored.")
            return
        }
        #expect(deskIndex.rawValue == 1)
        #expect(desk.id == source.id)
        #expect(desk.boards.map(\.id) == [before.id, primary.id, side.id, after.id])
        #expect(desk.focusedBoardID == primary.id)
        #expect(desk.scrollOffsetX == nil)
        #expect(desk.anchorBoardID == after.id)
    }

    @Test(arguments: [false, true])
    func rejectsSideBoardRestorationWhenTargetIsMissingOrOccupied(_ targetHasSide: Bool) {
        // Arrange
        let target = BoardState(label: "Target", width: 520, currentSheetURL: nil)
        let removed = BoardState(width: 390, targetBoardID: target.id)
        let existingSide = BoardState(width: 390, targetBoardID: target.id)
        let desk = DeskState(label: "Desk", boards: targetHasSide ? [target, existingSide] : [])
        let history = RecentlyRemovedBoard(
            board: removed, sourceDeskID: desk.id, sourceBoardIndex: BoardIndex(rawValue: 1))

        // Act
        let outcome = BoardRestoration.restore(history, in: [desk], presentedDeskID: desk.id)

        // Assert
        switch outcome {
        case .rejected(.sideBoardAlreadyExists):
            #expect(targetHasSide)
        case .rejected(.targetBoardMissing):
            #expect(!targetHasSide)
        default:
            Issue.record("Restoring a Side Board requires an available target.")
        }
    }

    @Test func existingTutorialTakesPrecedenceOverOriginalDestination() {
        // Arrange
        let removed = BoardState(width: 520, tutorial: TutorialBoardState())
        let existing = BoardState(width: 520, tutorial: TutorialBoardState())
        let desk = DeskState(label: "Desk", boards: [existing])
        let history = RecentlyRemovedBoard(
            board: removed, sourceDeskID: DeskID(), sourceBoardIndex: BoardIndex(rawValue: 0))

        // Act
        let outcome = BoardRestoration.restore(history, in: [desk], presentedDeskID: DeskID())

        // Assert
        guard case .focusExistingTutorial(let boardID) = outcome else {
            Issue.record("The existing Tutorial Board should be focused.")
            return
        }
        #expect(boardID == existing.id)
    }

    @Test func rejectsRestorationWhenSourceAndPresentedDesksAreMissing() {
        // Arrange
        let removed = BoardState(label: "Removed", width: 520, currentSheetURL: nil)
        let history = RecentlyRemovedBoard(
            board: removed, sourceDeskID: DeskID(), sourceBoardIndex: BoardIndex(rawValue: 0))

        // Act
        let outcome = BoardRestoration.restore(history, in: [], presentedDeskID: DeskID())

        // Assert
        guard case .rejected(.destinationDeskMissing) = outcome else {
            Issue.record("Restoration requires an existing destination Desk.")
            return
        }
    }
}
