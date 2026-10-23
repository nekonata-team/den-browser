import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct NativeBoardActivityTests {
    @Test func enteringBoardFromActivityFocusesItsDeskAndClosesActivity() {
        // Arrange
        let first = BoardState(label: "First", width: 520, currentSheetURL: nil)
        let second = BoardState(label: "Second", width: 520, currentSheetURL: nil)
        let firstDesk = DeskState(label: "First Desk", boards: [first], focusedBoardID: first.id)
        let secondDesk = DeskState(label: "Second Desk", boards: [second], focusedBoardID: second.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [firstDesk, secondDesk],
                        focusedDeskID: firstDesk.id))), configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.toggleBoardActivity()

        // Act
        windowModel.enterBoardFromActivity(second.id)

        // Assert
        #expect(!windowModel.isBoardActivityPresented)
        #expect(session.navigation.focusedDesk?.id == secondDesk.id)
        #expect(session.navigation.focusedBoard?.id == second.id)
        #expect(!windowModel.isDenMode)
    }
}
