import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenStoreBoardActivityTests {

    @Test func enteringBoardFromActivityFocusesItsDeskAndClosesActivity() {
        // Arrange
        let first = BoardState(label: "First", width: 520, currentSheetURL: nil)
        let second = BoardState(label: "Second", width: 520, currentSheetURL: nil)
        let firstDesk = DeskState(label: "First Desk", boards: [first], focusedBoardID: first.id)
        let secondDesk = DeskState(label: "Second Desk", boards: [second], focusedBoardID: second.id)
        let store = DenStore(
            state: DenState(
                desks: [firstDesk, secondDesk],
                focusedDeskID: firstDesk.id))
        store.toggleBoardActivity()

        // Act
        store.enterBoardFromActivity(second.id)

        // Assert
        #expect(!store.isBoardActivityPresented)
        #expect(store.focusedDesk?.id == secondDesk.id)
        #expect(store.focusedBoard?.id == second.id)
        #expect(!store.isDenMode)
    }
}
