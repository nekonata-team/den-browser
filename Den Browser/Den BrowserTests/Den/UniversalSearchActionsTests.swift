import DenApplication
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
    @Test(arguments: [false, true])
    func webInputOpensInDrawerWithoutCreatingBoard(fromEssential: Bool) throws {
        // Arrange
        let existing = BoardState(
            label: "Existing", width: 520, currentSheetURL: URL(string: "https://existing.example/"))
        let desk = DeskState(label: "Desk", boards: [existing], focusedBoardID: existing.id)
        try withTestWindowModel(desks: [desk]) { model, controller in
            let input = "Swift concurrency"
            let essential = Essential(name: "Search", key: "s", input: input)
            #expect(controller.preferences.setEssentials([essential]))
            model.showUniversalSearch()
            let target: UniversalSearchItem.Target = fromEssential ? .essential(essential.id) : .createBoard(input)

            // Act
            let error = UniversalSearchActions.perform(
                target, controller: controller, windowModel: model, inDrawer: true,
                openProfile: { _ in false }, openSettings: {})

            // Assert
            #expect(error == nil)
            let item = try #require(controller.state.drawerItems.first)
            #expect(
                item.url
                    == BoardInputResolver.normalizedURL(from: input, searchEngine: controller.preferences.searchEngine))
            #expect(controller.focusedDesk?.boards.map(\.id) == [existing.id])
            #expect(model.isDrawerOpen)
            #expect(model.drawer.expandedItemID == item.id)
        }
    }

    @Test(arguments: [
        UniversalSearchItem.Target.createBoard(":terminal"), .desk(DeskID()), .profile(ProfileID()),
        .board(BoardID()), .command(.toggleZenView),
    ])
    func drawerSubmissionRejectsCommandsAndNavigation(target: UniversalSearchItem.Target) {
        // Arrange
        let desk = DeskState(label: "Desk", boards: [])
        withTestWindowModel(desks: [desk]) { model, controller in
            model.showUniversalSearch()
            var openedProfile = false
            var openedSettings = false

            // Act
            let error = UniversalSearchActions.perform(
                target, controller: controller, windowModel: model, inDrawer: true,
                openProfile: { _ in
                    openedProfile = true
                    return true
                }, openSettings: { openedSettings = true })

            // Assert
            #expect(error != nil)
            #expect(model.temporaryContext == .universalSearch)
            #expect(controller.state.drawerItems.isEmpty)
            #expect(controller.focusedDesk?.boards.isEmpty == true)
            #expect(!model.isZenViewPresented)
            #expect(!openedProfile)
            #expect(!openedSettings)
        }
    }
}
