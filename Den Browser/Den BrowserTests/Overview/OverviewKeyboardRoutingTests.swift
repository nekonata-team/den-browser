import AppKit
import DenDomain
import DenPresentationModels
import Testing

@testable import Den_Browser

@MainActor
struct OverviewKeyboardRoutingTests {
    @Test(arguments: ["=", "+", "-", "0"])
    func zoomKeysBelongToOverviewContext(character: String) throws {
        // Arrange
        let board = BoardState(label: "Board", width: 520)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        try withTestWindowModel(desks: [desk]) { model, controller in
            model.showOverview()
            let event = try key(character)

            // Act
            let decision = route(event, model: model, controller: controller)

            // Assert
            let action: OverviewAction = character == "0" ? .resetZoom : (character == "-" ? .zoomOut : .zoomIn)
            #expect(decision == .perform(.overview(action)))
        }
    }

    @Test(arguments: ["=", "-", "0", "x", "d", "u"])
    func plainZoomKeysRemainTextWhileFiltering(character: String) throws {
        // Arrange
        let board = BoardState(label: "Board", width: 520)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        try withTestWindowModel(desks: [desk]) { model, controller in
            model.showOverview()
            model.overview.enterFilterMode()
            let event = try key(character)

            // Act
            let decision = route(event, model: model, controller: controller)

            // Assert
            #expect(decision == .forward(.filterTextInput))
        }
    }

    @Test(arguments: ["=", "-", "0"])
    func commandZoomKeysStayInOverviewWhileFiltering(character: String) throws {
        // Arrange
        let board = BoardState(label: "Board", width: 520)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        try withTestWindowModel(desks: [desk]) { model, controller in
            model.showOverview()
            model.overview.enterFilterMode()
            let event = try key(character, modifiers: .command)

            // Act
            let decision = route(event, model: model, controller: controller)

            // Assert
            let action: OverviewAction = character == "0" ? .resetZoom : (character == "-" ? .zoomOut : .zoomIn)
            #expect(decision == .perform(.overview(action)))
        }
    }

    @Test(arguments: ["x", "d", "u"])
    func removalKeysTargetOverviewSelection(character: String) throws {
        // Arrange
        let board = BoardState(label: "Board", width: 520)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        try withTestWindowModel(desks: [desk]) { model, controller in
            model.showOverview()
            let event = try key(character)

            // Act
            let decision = route(event, model: model, controller: controller)

            // Assert
            let action: OverviewAction =
                character == "u" ? .restoreRemovedBoard : .removeSelection(focusNext: character == "d")
            #expect(decision == .perform(.overview(action)))
        }
    }

    @Test func sheetInputKeepsPlainEquals() throws {
        // Arrange
        let board = BoardState(label: "Board", width: 520)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        try withTestWindowModel(desks: [desk]) { model, controller in
            model.exitDenMode()
            let event = try key("=")

            // Act
            let decision = route(event, model: model, controller: controller)

            // Assert
            #expect(decision == .forward(.sheet))
        }
    }

    private func route(_ event: NSEvent, model: DenWindowModel, controller: DenController) -> InputDecision {
        KeyboardRouter.route(
            event: KeyEvent(event),
            context: InputContext(controller: controller, windowModel: model, event: event),
            shortcuts: ShortcutConfiguration(preferences: controller.preferences))
    }

    private func key(_ character: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character,
                isARepeat: false, keyCode: character == "-" ? 27 : (character == "0" ? 29 : 24)))
    }
}
