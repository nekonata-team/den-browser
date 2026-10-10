import DenApplication
import DenDomain
import Testing

@MainActor
struct BoardMovementTests {
    @Test(arguments: [false, true], [false, true])
    func reorderingEitherMemberMovesWholeGroupAcrossAnotherGroup(_ selectsSide: Bool, _ movesRight: Bool) {
        // Arrange
        let first = BoardState(label: "First", width: 520, currentSheetURL: nil)
        let firstSide = BoardState(width: 390, targetBoardID: first.id)
        let second = BoardState(label: "Second", width: 520, currentSheetURL: nil)
        let secondSide = BoardState(width: 390, targetBoardID: second.id)
        let desk = DeskState(label: "Desk", boards: [first, firstSide, second, secondSide])
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let movement = BoardMovement(state: shared.store, writer: shared.writer)
        let selected = movesRight ? (selectsSide ? firstSide : first) : (selectsSide ? secondSide : second)

        // Act
        movement.reorder(selected.id, to: BoardIndex(rawValue: movesRight ? 3 : 0), in: desk.id)

        // Assert
        #expect(
            shared.store.snapshot.den.desks[0].boards.map(\.id) == [second.id, secondSide.id, first.id, firstSide.id])
        #expect(shared.store.snapshot.den.desks[0].focusedBoardID == desk.focusedBoardID)
        #expect(!movement.canMove(secondSide.id, by: -1))
        #expect(!movement.canMove(first.id, by: 1))
    }

    @Test(arguments: [false, true])
    func transferKeepsGroupsAdjacentAndReassignsOnlyRemovedSourceFocus(_ sourceFocusesGroup: Bool) {
        // Arrange
        let before = BoardState(label: "Before", width: 520, currentSheetURL: nil)
        let moved = BoardState(label: "Moved", width: 520, currentSheetURL: nil)
        let movedSide = BoardState(width: 390, targetBoardID: moved.id)
        let after = BoardState(label: "After", width: 520, currentSheetURL: nil)
        let source = DeskState(
            label: "Source", boards: [before, moved, movedSide, after],
            focusedBoardID: sourceFocusesGroup ? movedSide.id : before.id, scrollOffsetX: 180)
        let targetBoard = BoardState(label: "Target", width: 520, currentSheetURL: nil)
        let targetSide = BoardState(width: 390, targetBoardID: targetBoard.id)
        let tail = BoardState(label: "Tail", width: 520, currentSheetURL: nil)
        let target = DeskState(
            label: "Target", boards: [targetBoard, targetSide, tail], focusedBoardID: tail.id, scrollOffsetX: 190)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [source, target], focusedDeskID: source.id)))
        let movement = BoardMovement(state: shared.store, writer: shared.writer)

        // Act
        movement.transfer(movedSide.id, from: source.id, to: target.id, at: BoardIndex(rawValue: 1))

        // Assert
        let desks = shared.store.snapshot.den.desks
        #expect(desks[0].boards.map(\.id) == [before.id, after.id])
        #expect(desks[0].focusedBoardID == (sourceFocusesGroup ? after.id : before.id))
        #expect(desks[0].scrollOffsetX == (sourceFocusesGroup ? nil : source.scrollOffsetX))
        #expect(desks[1].boards.map(\.id) == [targetBoard.id, targetSide.id, moved.id, movedSide.id, tail.id])
        #expect(desks[1].focusedBoardID == target.focusedBoardID)
        #expect(desks[1].scrollOffsetX == target.scrollOffsetX)
    }

    @Test func restoringOrderRetainsUpdatedBoardDataAndNewBoards() {
        // Arrange
        var first = BoardState(label: "First", width: 520, currentSheetURL: nil)
        let second = BoardState(label: "Second", width: 520, currentSheetURL: nil)
        let added = BoardState(label: "Added", width: 520, currentSheetURL: nil)
        first.width = 900
        let desk = DeskState(label: "Desk", boards: [second, added, first])
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let movement = BoardMovement(state: shared.store, writer: shared.writer)

        // Act
        movement.restoreOrder([first.id, second.id], in: desk.id)

        // Assert
        #expect(shared.store.snapshot.den.desks[0].boards == [first, second, added])
    }
}
