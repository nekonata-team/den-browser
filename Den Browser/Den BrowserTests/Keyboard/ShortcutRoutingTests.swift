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
struct ShortcutRoutingTests {
    @Test func keyboardShortcutGuideForwardsTextInputAndKeepsEscapeToClose() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showKeyboardShortcuts()
        let letterA = try keyEvent(
            characters: "a",
            charactersIgnoringModifiers: "a",
            keyCode: 0
        )
        let commandA = try keyEvent(
            characters: "a",
            charactersIgnoringModifiers: "a",
            modifiers: [.command],
            keyCode: 0
        )
        let commandT = try keyEvent(
            characters: "t",
            charactersIgnoringModifiers: "t",
            modifiers: [.command],
            keyCode: 17
        )
        let questionMark = try keyEvent(
            characters: "?",
            charactersIgnoringModifiers: "/",
            modifiers: [.shift],
            keyCode: 44
        )
        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53
        )

        // Act
        let letterDecision = KeyboardController.decision(for: letterA, session: session, windowModel: windowModel)
        let selectAllDecision = KeyboardController.decision(
            for: commandA,
            session: session,
            windowModel: windowModel
        )
        let commandTDecision = KeyboardController.decision(
            for: commandT,
            session: session,
            windowModel: windowModel
        )
        let questionDecision = KeyboardController.decision(
            for: questionMark,
            session: session,
            windowModel: windowModel
        )
        let escapeDecision = KeyboardController.decision(for: escape, session: session, windowModel: windowModel)

        // Assert
        #expect(letterDecision == .forward(.filterTextInput))
        #expect(selectAllDecision == .forward(.filterTextInput))
        #expect(commandTDecision == .forward(.filterTextInput))
        #expect(questionDecision == .forward(.filterTextInput))
        #expect(escapeDecision == .perform(.application(.hideKeyboardShortcuts)))
    }

    @Test func nativeCommandShortcutsPassThroughWithoutExecuting() throws {
        let first = makeTestBoard("First")
        let second = makeTestBoard("Second")
        let session = try makeKeyboardTestSession(boards: [first, second])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let commands = [
            try keyEvent(
                characters: "w",
                charactersIgnoringModifiers: "w",
                modifiers: [.command],
                keyCode: 13
            ),
            try keyEvent(
                characters: "t",
                charactersIgnoringModifiers: "t",
                modifiers: [.command],
                keyCode: 17
            ),
            try keyEvent(
                characters: "l",
                charactersIgnoringModifiers: "l",
                modifiers: [.command],
                keyCode: 37
            ),
            try keyEvent(
                characters: "r",
                charactersIgnoringModifiers: "r",
                modifiers: [.command],
                keyCode: 15
            ),
        ]
        let closeWindow = try keyEvent(
            characters: "W",
            charactersIgnoringModifiers: "w",
            modifiers: [.command, .shift],
            keyCode: 13
        )

        for command in commands {
            #expect(!KeyboardController.handle(command, session: session, windowModel: windowModel))
        }
        #expect(!KeyboardController.handle(closeWindow, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [first.id, second.id])
        #expect(windowModel.temporaryContext == nil)
    }

    @Test func denModeCommaPerformsSettingsWithoutForwarding() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let comma = try keyEvent(
            characters: ",",
            charactersIgnoringModifiers: ",",
            modifiers: [],
            keyCode: 43
        )

        #expect(!KeyboardController.handle(comma, session: session, windowModel: windowModel))

        windowModel.isDenMode = true
        #expect(
            KeyboardController.decision(for: comma, session: session, windowModel: windowModel)
                == .perform(.application(.openSettings))
        )
        var didOpenSettings = false
        let handled = KeyboardController.handle(
            comma,
            session: session,
            windowModel: windowModel,
            openSettings: { didOpenSettings = true }
        )
        #expect(handled)
        #expect(didOpenSettings)

        windowModel.showOverview()
        #expect(KeyboardController.handle(comma, session: session, windowModel: windowModel))
        #expect(
            KeyboardController.decision(for: comma, session: session, windowModel: windowModel)
                == .consume(.exclusiveContext)
        )
    }

    @Test func denModeUnmappedKeyIsConsumedByRouter() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let unmapped = try keyEvent(
            characters: "\\",
            charactersIgnoringModifiers: "\\",
            modifiers: [],
            keyCode: 42
        )

        #expect(
            KeyboardController.decision(for: unmapped, session: session, windowModel: windowModel)
                == .consume(.denModeUnmapped)
        )
    }

    @Test func denModeAddsSpaceGuideAndZenViewWithoutPersistedStateChanges() throws {
        let preferences = try makeKeyboardTestPreferences()
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let state = session.resources.state

        let zen = try keyEvent(characters: "z", charactersIgnoringModifiers: "z", keyCode: 6)
        #expect(
            KeyboardController.handle(zen, session: session, windowModel: windowModel, preferences: preferences)
        )
        #expect(windowModel.isZenViewPresented)
        let repeatedZen = try keyEvent(
            characters: "z",
            charactersIgnoringModifiers: "z",
            isARepeat: true,
            keyCode: 6
        )
        #expect(
            KeyboardController.handle(
                repeatedZen,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(windowModel.isZenViewPresented)

        let question = try keyEvent(
            characters: "?",
            charactersIgnoringModifiers: "/",
            modifiers: [.shift],
            keyCode: 44
        )
        #expect(
            KeyboardController.handle(
                question,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(windowModel.isKeyboardShortcutsPresented)
        let movement = try keyEvent(characters: "h", charactersIgnoringModifiers: "h", keyCode: 4)
        #expect(
            !KeyboardController.handle(
                movement,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(windowModel.isKeyboardShortcutsPresented)
        #expect(
            !KeyboardController.handle(
                question,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(windowModel.isKeyboardShortcutsPresented)
        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53
        )
        #expect(
            KeyboardController.handle(
                escape,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(!windowModel.isKeyboardShortcutsPresented)

        let space = try keyEvent(characters: " ", charactersIgnoringModifiers: " ", keyCode: 49)
        #expect(
            KeyboardController.handle(space, session: session, windowModel: windowModel, preferences: preferences)
        )
        #expect(windowModel.isOpenBoardPanelPresented)
        #expect(session.resources.state == state)
    }

    @Test func fullscreenBypassesAllShortcutsAndClearsDenMode() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        session.boardNavigation.updateFullscreenStatus(boardID: BoardID(), isFullscreen: true)
        #expect(!windowModel.isDenMode)
        #expect(windowModel.isFullscreenActive)

        let commandW = try keyEvent(
            characters: "w",
            charactersIgnoringModifiers: "w",
            modifiers: [.command],
            keyCode: 13
        )
        #expect(!KeyboardController.handle(commandW, session: session, windowModel: windowModel))
    }
}
