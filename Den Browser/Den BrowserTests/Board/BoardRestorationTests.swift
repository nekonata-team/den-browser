import DenApplication
import DenDomain
import Testing

@MainActor
struct BoardRestorationTests {
    @Test(arguments: [false, true])
    func rejectsSideBoardRestorationWhenTargetIsMissingOrOccupied(_ targetHasSide: Bool) {
        // Arrange
        let target = BoardState(label: "Target", width: 520, currentSheetURL: nil)
        let removed = BoardState(width: 390, targetBoardID: target.id)
        let existingSide = BoardState(width: 390, targetBoardID: target.id)
        let desk = DeskState(label: "Desk", boards: targetHasSide ? [target, existingSide] : [])
        let history = RecentlyRemovedBoard(board: removed, sourceDeskID: desk.id, sourceBoardIndex: 1)

        // Act
        let outcome = BoardRestoration.resolve(history, in: [desk], presentedDeskID: desk.id)

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
        let history = RecentlyRemovedBoard(board: removed, sourceDeskID: DeskID(), sourceBoardIndex: 0)

        // Act
        let outcome = BoardRestoration.resolve(history, in: [desk], presentedDeskID: DeskID())

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
        let history = RecentlyRemovedBoard(board: removed, sourceDeskID: DeskID(), sourceBoardIndex: 0)

        // Act
        let outcome = BoardRestoration.resolve(history, in: [], presentedDeskID: DeskID())

        // Assert
        guard case .rejected(.destinationDeskMissing) = outcome else {
            Issue.record("Restoration requires an existing destination Desk.")
            return
        }
    }
}
