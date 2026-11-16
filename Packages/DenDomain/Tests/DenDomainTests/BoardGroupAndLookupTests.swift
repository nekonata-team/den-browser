import DenDomain
import Foundation
import Testing

nonisolated struct BoardGroupAndLookupTests {
    @Test func boardGroupContainingResolvesPrimarySideSingleAndInvalidGroups() throws {
        // Arrange
        let primary = BoardState(label: "Primary", width: 520, workingDirectory: "/tmp")
        let side = BoardState(width: 390, targetBoardID: primary.id)
        let standalone = BoardState(label: "Standalone", width: 520, currentSheetURL: nil)
        let orphanSide = BoardState(width: 390, targetBoardID: BoardID())
        let boards = [primary, side, standalone, orphanSide]

        // Act
        let byPrimary = try #require(BoardGroup.containing(primary.id, in: boards))
        let bySide = try #require(BoardGroup.containing(side.id, in: boards))
        let single = try #require(BoardGroup.containing(standalone.id, in: boards))
        let orphan = try #require(BoardGroup.containing(orphanSide.id, in: boards))

        // Assert
        #expect(byPrimary.primaryBoard == primary)
        #expect(byPrimary.sideBoard == side)
        #expect(bySide == byPrimary)
        #expect(single.primaryBoard == standalone)
        #expect(single.sideBoard == nil)
        #expect(orphan.primaryBoard == orphanSide)
        #expect(orphan.sideBoard == nil)
        #expect(BoardGroup.containing(BoardID(), in: boards) == nil)
    }

    @Test func boardGroupContainingReturnsNilWhenMultipleSideBoardsTargetSamePrimary() {
        // Arrange
        let primary = BoardState(label: "Primary", width: 520, workingDirectory: "/tmp")
        let firstSide = BoardState(width: 390, targetBoardID: primary.id)
        let secondSide = BoardState(width: 390, targetBoardID: primary.id)

        // Act / Assert
        #expect(BoardGroup.containing(primary.id, in: [primary, firstSide, secondSide]) == nil)
    }

    @Test func denStateLookupFindsBoardAcrossDesksAndReturnsNilWhenMissing() {
        // Arrange
        let first = BoardState(label: "First", width: 520, currentSheetURL: nil)
        let second = BoardState(label: "Second", width: 640, workingDirectory: "/tmp")
        let firstDesk = DeskState(label: "One", boards: [first])
        let secondDesk = DeskState(label: "Two", boards: [first, second])
        let state = DenState(desks: [firstDesk, secondDesk], focusedDeskID: firstDesk.id)

        // Act
        let indices = state.boardIndices(for: second.id)
        let found = state.board(for: second.id)

        // Assert
        #expect(indices?.deskOffset == 1)
        #expect(indices?.boardOffset == 1)
        #expect(found == second)
        #expect(state.boardIndices(for: BoardID()) == nil)
        #expect(state.board(for: BoardID()) == nil)
    }
}
