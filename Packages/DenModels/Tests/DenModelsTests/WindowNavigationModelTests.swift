import DenApplication
import DenDomain
import DenModels
import Testing

@MainActor
struct WindowNavigationModelTests {
    @Test func switchingRemembersThePreviousDeskWithoutChangingAnotherWindow() {
        // Arrange
        let firstDesk = DeskID()
        let secondDesk = DeskID()
        let first = WindowNavigationModel(
            state: DenStateStore.make(initialState: DenSharedState(den: .sample)).store, presentedDeskID: firstDesk)
        let other = WindowNavigationModel(
            state: DenStateStore.make(initialState: DenSharedState(den: .sample)).store, presentedDeskID: firstDesk)

        // Act
        first.present(secondDesk)
        first.present(secondDesk)

        // Assert
        #expect(first.presentedDeskID == secondDesk)
        #expect(first.previousFocusedDeskID == firstDesk)
        #expect(other.presentedDeskID == firstDesk)
        #expect(other.previousFocusedDeskID == nil)
    }

    @Test func sharedBoardUpdatesRemainLiveWhilePresentedDesksStayWindowLocal() {
        // Arrange
        let firstBoard = BoardState(label: "First", width: 640, workingDirectory: "/tmp")
        let secondBoard = BoardState(label: "Second", width: 640, workingDirectory: "/tmp")
        let firstDesk = DeskState(label: "First", boards: [firstBoard], focusedBoardID: firstBoard.id)
        let secondDesk = DeskState(label: "Second", boards: [secondBoard], focusedBoardID: secondBoard.id)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [firstDesk, secondDesk], focusedDeskID: firstDesk.id)))
        let first = WindowNavigationModel(state: shared.store, presentedDeskID: firstDesk.id)
        let other = WindowNavigationModel(state: shared.store, presentedDeskID: secondDesk.id)
        let updates = BoardUpdates(store: shared.store, writer: shared.writer)

        // Act
        updates.rename(secondBoard.id, to: "Renamed", beforeSave: {})

        // Assert
        #expect(first.focusedDesk?.id == firstDesk.id)
        #expect(first.focusedBoard?.id == firstBoard.id)
        #expect(other.focusedDesk?.id == secondDesk.id)
        #expect(other.focusedBoard?.customLabel == "Renamed")
        #expect(first.board(for: secondBoard.id)?.customLabel == "Renamed")
        #expect(shared.store.snapshot.den.focusedDeskID == firstDesk.id)
    }

    @Test func removalInvalidatesOnlyMatchingReturnReferences() {
        // Arrange
        let currentDesk = DeskID()
        let removedDesk = DeskID()
        let retainedDesk = DeskID()
        let removedBoard = BoardID()
        let retainedBoard = BoardID()
        let model = WindowNavigationModel(
            state: DenStateStore.make(initialState: DenSharedState(den: .sample)).store, presentedDeskID: currentDesk)
        model.previousFocusedDeskID = removedDesk
        model.anchorJumpOriginBoardIDByDesk = [
            currentDesk: removedBoard, removedDesk: retainedBoard, retainedDesk: retainedBoard,
        ]

        // Act
        model.invalidateBoards([removedBoard])
        model.invalidateDesk(removedDesk)

        // Assert
        #expect(model.presentedDeskID == currentDesk)
        #expect(model.previousFocusedDeskID == nil)
        #expect(model.anchorJumpOriginBoardIDByDesk == [retainedDesk: retainedBoard])
    }

    @Test func resetCanReplaceSelectionBeforeClearingHistory() {
        // Arrange
        let first = DeskID()
        let second = DeskID()
        let replacement = DeskID()
        let model = WindowNavigationModel(
            state: DenStateStore.make(initialState: DenSharedState(den: .sample)).store, presentedDeskID: first)
        model.present(second)
        model.anchorJumpOriginBoardIDByDesk[first] = BoardID()

        // Act
        model.replacePresentedDesk(replacement)

        // Assert
        #expect(model.presentedDeskID == replacement)
        #expect(model.previousFocusedDeskID == first)
        #expect(!model.anchorJumpOriginBoardIDByDesk.isEmpty)

        // Act
        model.clearHistory()

        // Assert
        #expect(model.presentedDeskID == replacement)
        #expect(model.previousFocusedDeskID == nil)
        #expect(model.anchorJumpOriginBoardIDByDesk.isEmpty)
    }
}
