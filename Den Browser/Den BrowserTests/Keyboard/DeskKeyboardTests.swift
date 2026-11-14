import AppKit
import DenApplication
import DenDomain
import DenModels
import DenViews
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DeskKeyboardTests {
    @Test(arguments: [false, true], [false, true])
    func denModeShiftVerticalMovementReordersDesk(movesUp: Bool, arrow: Bool) throws {
        // Arrange
        let focused = makeTestBoard("Focused")
        let first = DeskState(label: "First", boards: [])
        let middle = DeskState(label: "Middle", boards: [focused], focusedBoardID: focused.id)
        let last = DeskState(label: "Last", boards: [])
        var savedState: DenState?
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, middle, last])),
                onSave: {
                    savedState = $0
                    return true
                }
            )
        ) { session, model in
            session.boardNavigation.focusDesk(middle.id)
            model.isDenMode = true
            let event =
                try arrow
                ? arrowEvent(movesUp ? .upArrow : .downArrow, modifiers: .shift)
                : keyEvent(
                    characters: movesUp ? "K" : "J",
                    charactersIgnoringModifiers: movesUp ? "k" : "j",
                    modifiers: .shift,
                    keyCode: movesUp ? 40 : 38
                )

            // Act
            let decision = KeyboardController.decision(
                for: event,
                session: session,
                windowModel: model
            )
            let handled = KeyboardController.handle(event, session: session, windowModel: model)

            // Assert
            #expect(decision == .perform(.desk(movesUp ? .movePrevious : .moveNext)))
            #expect(handled)
            #expect(
                session.resources.state.desks.map(\.id)
                    == (movesUp ? [middle.id, first.id, last.id] : [first.id, last.id, middle.id])
            )
            #expect(session.navigation.focusedDesk?.id == middle.id)
            #expect(session.navigation.focusedDesk?.boards == [focused])
            #expect(session.navigation.focusedBoard?.id == focused.id)
            #expect(model.isDenMode)
            #expect(savedState == session.resources.state)
        }
    }

    @Test func denModeShiftDigitMovesFocusedBoardToDesk() throws {
        let movedBoard = makeTestBoard("Moved")
        let firstDesk = DeskState(label: "First", boards: [], focusedBoardID: nil)
        let secondDesk = DeskState(
            label: "Second",
            boards: [movedBoard],
            focusedBoardID: movedBoard.id
        )
        let session = try makeKeyboardTestSession(desks: [firstDesk, secondDesk])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.boardNavigation.focusDesk(secondDesk.id)
        windowModel.isDenMode = true

        let shiftOne = try keyEvent(
            characters: "!",
            charactersIgnoringModifiers: "!",
            modifiers: [.shift],
            keyCode: 18
        )

        #expect(KeyboardController.handle(shiftOne, session: session, windowModel: windowModel))
        #expect(session.resources.state.focusedDeskID == firstDesk.id)
        #expect(session.navigation.focusedDesk?.focusedBoardID == movedBoard.id)
        #expect(session.resources.state.desks[0].boards.map(\.id) == [movedBoard.id])
        #expect(!windowModel.isDenMode)
    }

    @Test func sheetInputCommandOptionDigitFocusesDeskAndLeavesCommandZeroAvailable() throws {
        let movedBoard = makeTestBoard("Moved")
        let firstDesk = DeskState(label: "First", boards: [], focusedBoardID: nil)
        let secondDesk = DeskState(
            label: "Second",
            boards: [movedBoard],
            focusedBoardID: movedBoard.id
        )
        let session = try makeKeyboardTestSession(desks: [firstDesk, secondDesk])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.boardNavigation.focusDesk(secondDesk.id)
        let preferences = session.configuration.preferences
        let commandOptionOne = try keyEvent(
            characters: "1",
            charactersIgnoringModifiers: "1",
            modifiers: [.command, .option],
            keyCode: 18
        )
        let commandZero = try keyEvent(
            characters: "0",
            charactersIgnoringModifiers: "0",
            modifiers: [.command],
            keyCode: 29
        )

        #expect(
            KeyboardController.handle(
                commandOptionOne,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(session.resources.state.focusedDeskID == firstDesk.id)
        #expect(!windowModel.isDenMode)
        #expect(
            !KeyboardController.handle(
                commandZero,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(session.resources.state.focusedDeskID == firstDesk.id)
    }

    @Test func controlTabDeskShortcutsNavigateAndReturn() throws {
        let firstDesk = DeskState(label: "First", boards: [])
        let secondDesk = DeskState(label: "Second", boards: [])
        let thirdDesk = DeskState(label: "Third", boards: [])
        let session = try makeKeyboardTestSession(desks: [firstDesk, secondDesk, thirdDesk])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let preferences = session.configuration.preferences

        let next = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.control],
            keyCode: 48
        )
        #expect(
            KeyboardController.handle(next, session: session, windowModel: windowModel, preferences: preferences)
        )
        #expect(session.navigation.focusedDesk?.id == secondDesk.id)

        let previous = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.control, .shift],
            keyCode: 48
        )
        #expect(
            KeyboardController.handle(
                previous,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(session.navigation.focusedDesk?.id == firstDesk.id)

        let returnToPrevious = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.command, .option],
            keyCode: 48
        )
        #expect(
            KeyboardController.handle(
                returnToPrevious,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(session.navigation.focusedDesk?.id == secondDesk.id)
    }

    @Test(arguments: [false, true])
    func denModePOpensDeskPresetPanelWithOrWithoutBoards(_ isEmpty: Bool) throws {
        // Arrange
        let save = try keyEvent(characters: "p", charactersIgnoringModifiers: "p", keyCode: 35)
        let session = try makeKeyboardTestSession(boards: isEmpty ? [] : [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        // Act
        let handled = KeyboardController.handle(save, session: session, windowModel: windowModel)

        // Assert
        #expect(handled)
        #expect(windowModel.isSaveDeskPresetPanelPresented)
    }

    @Test func denModeShiftPOpensDeskReplacement() throws {
        let replace = try keyEvent(
            characters: "P",
            charactersIgnoringModifiers: "p",
            modifiers: [.shift],
            keyCode: 35
        )
        let session = try makeKeyboardTestSession(boards: [])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        #expect(KeyboardController.handle(replace, session: session, windowModel: windowModel))
        #expect(windowModel.isReplaceDeskPanelPresented)
        #expect(windowModel.isNewDeskPanelPresented)
        #expect(!windowModel.isDeskPresetManagementPresented)
    }

    @Test func denModeBHasNoPresetAction() throws {
        let legacy = try keyEvent(characters: "b", charactersIgnoringModifiers: "b", keyCode: 11)
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        #expect(KeyboardController.handle(legacy, session: session, windowModel: windowModel))
        #expect(!windowModel.isSaveDeskPresetPanelPresented)
        #expect(!windowModel.isDeskPresetManagementPresented)
    }

    @Test func presetConfirmationsSuspendBoardRemovalShortcuts() throws {
        let commandW = try keyEvent(
            characters: "w",
            charactersIgnoringModifiers: "w",
            modifiers: [.command],
            keyCode: 13
        )
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        #expect(session.presets.saveFocusedDeskAsPreset(label: "Routine") == .created)
        #expect(session.presets.saveFocusedDeskAsPreset(label: "Routine") == .replacementPending)
        #expect(!KeyboardController.handle(commandW, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedDesk?.boards.count == 1)

        windowModel.cancelDeskPresetReplacement()
        let presetID = try #require(session.resources.deskPresets.first?.id)
        session.presets.requestDeskPresetDeletion(presetID)
        #expect(!KeyboardController.handle(commandW, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedDesk?.boards.count == 1)
    }
}
