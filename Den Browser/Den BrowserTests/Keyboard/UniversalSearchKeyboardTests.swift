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
struct UniversalSearchKeyboardTests {
    @Test func universalSearchForwardsMarkedTextConfirmationInsteadOfExecuting() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("Board")])
        let model = DenWindowComposition(session: session).model
        model.showUniversalSearch()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        window.contentView?.addSubview(editor)
        #expect(window.makeFirstResponder(editor))
        editor.setMarkedText(
            "検索",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )
        )
        #expect(KeyEvent(event).hasMarkedText)

        // Act
        let decision = KeyboardController.decision(for: event, session: session, windowModel: model)

        // Assert
        #expect(decision == .forward(.temporaryTextInput))
        #expect(model.universalSearch.submissionRequest == 0)
    }

    @Test func universalSearchEntrancesRouteToTheSamePresentation() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("Board")])
        let composition = DenWindowComposition(session: session)
        let model = composition.model
        let search = try keyEvent(
            characters: "p",
            charactersIgnoringModifiers: "p",
            modifiers: [.command],
            keyCode: 35
        )
        let commands = try keyEvent(
            characters: "P",
            charactersIgnoringModifiers: "P",
            modifiers: [.command, .shift],
            keyCode: 35
        )
        let colon = try keyEvent(
            characters: ":",
            charactersIgnoringModifiers: ":",
            modifiers: [.shift],
            keyCode: 41
        )

        // Act
        let searchDecision = KeyboardController.decision(for: search, session: session, windowModel: model)
        let commandDecision = KeyboardController.decision(for: commands, session: session, windowModel: model)
        model.isDenMode = true
        let colonDecision = KeyboardController.decision(for: colon, session: session, windowModel: model)

        // Assert
        #expect(searchDecision == .perform(.application(.showUniversalSearch(commandsOnly: false))))
        #expect(commandDecision == .perform(.application(.showUniversalSearch(commandsOnly: true))))
        #expect(colonDecision == searchDecision)
    }

    @Test func universalSearchOwnsInputAndCancelPreservesDenMode() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("Board")])
        let composition = DenWindowComposition(session: session)
        let model = composition.model
        model.isDenMode = true
        model.showUniversalSearch(commandsOnly: true)
        let letter = try keyEvent(characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let enter = try keyEvent(characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let escape = try keyEvent(characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)

        // Act
        let letterDecision = KeyboardController.decision(for: letter, session: session, windowModel: model)
        let enterDecision = KeyboardController.decision(for: enter, session: session, windowModel: model)
        let escapeDecision = KeyboardController.decision(for: escape, session: session, windowModel: model)
        AppActionHandler.perform(.application(.hideUniversalSearch), session: session, windowModel: model)

        // Assert
        #expect(model.universalSearch.commandsOnly)
        #expect(letterDecision == .forward(.temporaryTextInput))
        #expect(enterDecision == .perform(.application(.submitSearch)))
        #expect(escapeDecision == .perform(.application(.hideUniversalSearch)))
        #expect(model.temporaryContext == nil)
        #expect(model.isDenMode)
    }

    @Test func universalSearchOptionReturnRequestsDrawerAndIgnoresRepeats() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let model = composition.model
        model.showUniversalSearch()
        let enter = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.option],
            keyCode: 36
        )
        let repeated = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.option],
            isARepeat: true,
            keyCode: 36
        )

        // Act
        let decision = KeyboardController.decision(for: enter, session: session, windowModel: model)
        let repeatedDecision = KeyboardController.decision(for: repeated, session: session, windowModel: model)
        let handled = KeyboardController.handle(enter, session: session, windowModel: model)

        // Assert
        #expect(decision == .perform(.application(.submitSearchInDrawer)))
        #expect(repeatedDecision == .consume(.ignoredRepeat))
        #expect(handled)
        #expect(model.universalSearch.submitsInDrawer)
        #expect(model.universalSearch.submissionRequest == 1)
    }
}
