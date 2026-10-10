import DenDomain
import DenPresentationModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenControllerBoardActivityTests {

    @Test func enteringBoardFromActivityFocusesItsDeskAndClosesActivity() {
        // Arrange
        let first = BoardState(label: "First", width: 520, currentSheetURL: nil)
        let second = BoardState(label: "Second", width: 520, currentSheetURL: nil)
        let firstDesk = DeskState(label: "First Desk", boards: [first], focusedBoardID: first.id)
        let secondDesk = DeskState(label: "Second Desk", boards: [second], focusedBoardID: second.id)
        let controller = DenController(
            state: DenState(
                desks: [firstDesk, secondDesk],
                focusedDeskID: firstDesk.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.toggleBoardActivity()

        // Act
        windowModel.enterBoardFromActivity(second.id)

        // Assert
        #expect(!windowModel.isBoardActivityPresented)
        #expect(controller.focusedDesk?.id == secondDesk.id)
        #expect(controller.focusedBoard?.id == second.id)
        #expect(!windowModel.isDenMode)
    }
}
