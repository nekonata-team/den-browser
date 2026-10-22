import DenApplication
import DenDomain
import Testing

@MainActor
struct BoardRemovalPlanTests {
    @Test(arguments: [false, true])
    func removingPrimaryIncludesSideWhileRemovingSideKeepsPrimary(_ removesSide: Bool) throws {
        // Arrange
        let before = BoardState(label: "Before", width: 520, currentSheetURL: nil)
        let primary = BoardState(label: "Primary", width: 520, currentSheetURL: nil)
        let side = BoardState(width: 390, targetBoardID: primary.id)
        let after = BoardState(label: "After", width: 520, currentSheetURL: nil)
        let desk = DeskState(
            label: "Desk", boards: [before, primary, side, after], focusedBoardID: side.id,
            scrollOffsetX: 180, anchorBoardID: side.id)
        let selected = removesSide ? side : primary

        // Act
        let removal = try #require(BoardRemoval.planRemoval(selected.id, from: desk))

        // Assert
        #expect(
            removal.desk.boards.map(\.id) == (removesSide ? [before.id, primary.id, after.id] : [before.id, after.id]))
        #expect(removal.desk.focusedBoardID == (removesSide ? primary.id : before.id))
        #expect(removal.desk.anchorBoardID == nil)
        #expect(removal.desk.scrollOffsetX == nil)
        #expect(removal.removedBoards.map(\.id) == (removesSide ? [side.id] : [primary.id, side.id]))
        #expect(removal.historyEntry.board == selected)
        #expect(removal.historyEntry.sideBoard == (removesSide ? nil : side))
        #expect(removal.historyEntry.sourceDeskID == desk.id)
        #expect(removal.historyEntry.sourceBoardIndex.rawValue == (removesSide ? 2 : 1))
    }

    @Test(arguments: [false, true])
    func focusedRemovalHonorsPreferredNeighbor(_ focusNext: Bool) throws {
        // Arrange
        let before = BoardState(label: "Before", width: 520, currentSheetURL: nil)
        let selected = BoardState(label: "Selected", width: 520, currentSheetURL: nil)
        let after = BoardState(label: "After", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: [before, selected, after], focusedBoardID: selected.id)

        // Act
        let removal = try #require(BoardRemoval.planRemoval(selected.id, from: desk, focusNext: focusNext))

        // Assert
        #expect(removal.desk.focusedBoardID == (focusNext ? after.id : before.id))
    }

    @Test func unfocusedRemovalPreservesFocusScrollAndAnchor() throws {
        // Arrange
        let removed = BoardState(label: "Removed", width: 520, currentSheetURL: nil)
        let focused = BoardState(label: "Focused", width: 520, currentSheetURL: nil)
        let desk = DeskState(
            label: "Desk", boards: [removed, focused], focusedBoardID: focused.id,
            scrollOffsetX: 180, anchorBoardID: focused.id)

        // Act
        let removal = try #require(BoardRemoval.planRemoval(removed.id, from: desk))

        // Assert
        #expect(removal.desk.focusedBoardID == focused.id)
        #expect(removal.desk.scrollOffsetX == desk.scrollOffsetX)
        #expect(removal.desk.anchorBoardID == focused.id)
    }

    @Test func removingOnlyBoardClearsFocusAndScroll() throws {
        // Arrange
        let removed = BoardState(label: "Removed", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: [removed], scrollOffsetX: 180)

        // Act
        let removal = try #require(BoardRemoval.planRemoval(removed.id, from: desk))

        // Assert
        #expect(removal.desk.boards.isEmpty)
        #expect(removal.desk.focusedBoardID == nil)
        #expect(removal.desk.scrollOffsetX == nil)
    }

    @Test func missingBoardProducesNoRemoval() {
        let desk = DeskState(label: "Desk", boards: [])
        #expect(BoardRemoval.planRemoval(BoardID(), from: desk) == nil)
    }
}
