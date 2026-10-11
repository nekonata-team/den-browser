import DenDomain
import DenPresentationModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct UniversalSearchActionsTests {
    @Test func switchingToBoardDoesNotCreateOrDuplicateIt() {
        // Arrange
        let target = BoardState(label: "Target", width: 520, currentSheetURL: URL(string: "https://example.com/"))
        let initial = BoardState(label: "First", width: 520, currentSheetURL: URL(string: "https://example.org/"))
        let first = DeskState(label: "First", boards: [initial], focusedBoardID: initial.id)
        let second = DeskState(label: "Second", boards: [target], focusedBoardID: target.id)
        withTestWindowModel(desks: [first, second]) { model, controller in
            model.isDenMode = true
            model.showUniversalSearch()

            // Act
            let error = UniversalSearchActions.perform(
                .board(target.id), controller: controller, windowModel: model,
                openProfile: { _ in false }, openSettings: {})

            // Assert
            #expect(error == nil)
            #expect(controller.focusedBoard?.id == target.id)
            #expect(controller.state.desks.flatMap(\.boards).count == 2)
            #expect(model.temporaryContext == nil)
            #expect(!model.isDenMode)
        }
    }

    @Test func essentialCreatesBoardEvenWhenMatchingBoardExists() throws {
        // Arrange
        let input = "https://example.com/"
        let existing = BoardState(label: "Existing", width: 520, currentSheetURL: URL(string: input))
        let desk = DeskState(label: "Desk", boards: [existing], focusedBoardID: existing.id)
        try withTestWindowModel(desks: [desk]) { model, controller in
            #expect(controller.saveEssential(name: "Example", key: "e", input: input))
            let essential = try #require(controller.essentials.first)
            model.showUniversalSearch()

            // Act
            let error = UniversalSearchActions.perform(
                .essential(essential.id), controller: controller, windowModel: model,
                openProfile: { _ in false }, openSettings: {})

            // Assert
            #expect(error == nil)
            #expect(controller.focusedDesk?.boards.count == 2)
            #expect(controller.focusedBoard?.id != existing.id)
            #expect(controller.focusedBoard?.currentSheetURL?.absoluteString == input)
            #expect(model.temporaryContext == nil)
        }
    }

    @Test func rejectedCreationKeepsPaletteAndDoesNotChangeBoards() {
        // Arrange
        let existing = BoardState(label: "Existing", width: 520, currentSheetURL: URL(string: "https://example.com/"))
        let desk = DeskState(label: "Desk", boards: [existing], focusedBoardID: existing.id)
        withTestWindowModel(desks: [desk]) { model, controller in
            model.showUniversalSearch()

            // Act
            let error = UniversalSearchActions.perform(
                .createBoard("unsupported://example"), controller: controller, windowModel: model,
                openProfile: { _ in false }, openSettings: {})

            // Assert
            #expect(error != nil)
            #expect(controller.focusedDesk?.boards.map(\.id) == [existing.id])
            #expect(model.temporaryContext == .universalSearch)
        }
    }
}
