import DenApplication
import DenDomain
import Foundation
import Testing

@MainActor
struct DenStateNormalizationTests {
    @Test func emptyStateRestoresAnInitialDesk() {
        // Arrange
        let state = DenState(desks: [], focusedDeskID: DeskID())

        // Act
        let normalized = DenStateNormalization.normalize(state)

        // Assert
        #expect(normalized.desks.count == 1)
        #expect(normalized.desks.first?.id == normalized.focusedDeskID)
    }

    @Test func normalizationRemovesSessionOnlyBoardsAndRepairsReferencesWithoutChangingLiveState() {
        // Arrange
        let board = BoardState(label: "Web", width: 640, currentSheetURL: URL(string: "https://example.com/"))
        let tutorial = BoardState(label: "Tutorial", width: 640, tutorial: TutorialBoardState())
        var desk = DeskState(label: "Desk", boards: [tutorial, board], focusedBoardID: tutorial.id)
        desk.anchorBoardID = tutorial.id
        desk.scrollOffsetX = 180
        let state = DenState(desks: [desk], focusedDeskID: DeskID())

        // Act
        let normalized = DenStateNormalization.normalize(state)

        // Assert
        #expect(normalized.focusedDeskID == desk.id)
        #expect(normalized.desks[0].boards == [board])
        #expect(normalized.desks[0].focusedBoardID == board.id)
        #expect(normalized.desks[0].anchorBoardID == nil)
        #expect(normalized.desks[0].scrollOffsetX == nil)
        #expect(state.desks[0] == desk)
    }
}
