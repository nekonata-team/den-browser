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
struct PanelKeyboardTests {
    @Test func denModeIOpensNotifications() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("Terminal")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let open = try keyEvent(
            characters: "i",
            charactersIgnoringModifiers: "i",
            keyCode: 34
        )

        #expect(KeyboardController.handle(open, session: session, windowModel: windowModel))
        #expect(windowModel.isNotificationListPresented)
        #expect(windowModel.isDenMode)
    }

    @Test func notificationArrowsMoveSelectionAndReturnOpensIt() throws {
        let first = makeTestBoard("First")
        let second = makeTestBoard("Second")
        let session = try makeKeyboardTestSession(boards: [first, second])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.notifications.recordNotification(title: "First", body: "Done", boardID: first.id)
        session.notifications.recordNotification(title: "Second", body: "Done", boardID: second.id)
        windowModel.isDenMode = true
        let preferences = try makeKeyboardTestPreferences()

        let open = try keyEvent(
            characters: "i",
            charactersIgnoringModifiers: "i",
            keyCode: 34
        )
        let down = try keyEvent(
            characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}",
            keyCode: 125
        )
        let enter = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36
        )

        #expect(
            KeyboardController.handle(open, session: session, windowModel: windowModel, preferences: preferences)
        )
        #expect(windowModel.notificationList.selectedNotificationID == session.resources.notifications[0].id)
        #expect(
            KeyboardController.handle(down, session: session, windowModel: windowModel, preferences: preferences)
        )
        #expect(windowModel.notificationList.selectedNotificationID == session.resources.notifications[1].id)
        #expect(
            KeyboardController.handle(enter, session: session, windowModel: windowModel, preferences: preferences)
        )
        #expect(session.navigation.focusedBoard?.id == first.id)
        #expect(!windowModel.isNotificationListPresented)
    }

    @Test func openProfilePanelForwardsKeyboardNavigationToItsTextField() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        windowModel.deskFilter.enter()
        windowModel.isNotificationListPresented = true
        windowModel.setTemporaryContext(.profilePicker)
        #expect(windowModel.temporaryContext == .profilePicker)
        #expect(windowModel.deskFilter.phase == .inactive)
        #expect(!windowModel.isNotificationListPresented)
        let down = try arrowEvent(.downArrow, modifiers: [])
        let returnKey = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36
        )
        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53
        )

        #expect(
            KeyboardController.decision(for: down, session: session, windowModel: windowModel)
                == .forward(.temporaryTextInput)
        )
        #expect(
            KeyboardController.decision(for: returnKey, session: session, windowModel: windowModel)
                == .forward(.temporaryTextInput)
        )
        #expect(
            KeyboardController.decision(for: escape, session: session, windowModel: windowModel)
                == .forward(.temporaryTextInput)
        )
    }

    @Test(arguments: [false, true])
    func textInputPanelConsumesTabTraversalUnlessComposing(hasMarkedText: Bool) throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        windowModel.showOpenBoardPanel()
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
        if hasMarkedText {
            editor.setMarkedText(
                "変換",
                selectedRange: NSRange(location: 2, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }

        #expect(windowModel.temporaryContext == .openBoard)
        for modifiers: NSEvent.ModifierFlags in [[], [.shift]] {
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: modifiers,
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: "\t",
                    charactersIgnoringModifiers: "\t",
                    isARepeat: false,
                    keyCode: 48
                )
            )
            #expect(KeyEvent(event).hasMarkedText == hasMarkedText)

            // Act
            let decision = KeyboardController.decision(for: event, session: session, windowModel: windowModel)

            // Assert
            #expect(decision == (hasMarkedText ? .forward(.temporaryTextInput) : .consume(.exclusiveContext)))
        }
    }

    @Test func overviewFilterUsesTwoPhaseSelection() throws {
        let first = makeTestBoard("First")
        let second = makeTestBoard("Second")
        let session = try makeKeyboardTestSession(boards: [first, second])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()

        let slash = try keyEvent(
            characters: "/",
            charactersIgnoringModifiers: "/",
            keyCode: 44
        )
        let returnKey = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36
        )

        #expect(KeyboardController.handle(slash, session: session, windowModel: windowModel))
        #expect(windowModel.overview.filterPhase == .filtering)
        windowModel.overview.setQuery("Second")
        #expect(windowModel.overview.selectionBoardID == second.id)

        #expect(KeyboardController.handle(returnKey, session: session, windowModel: windowModel))
        #expect(windowModel.overview.filterPhase == .selecting)
        #expect(windowModel.isOverviewPresented)

        #expect(KeyboardController.handle(returnKey, session: session, windowModel: windowModel))
        #expect(windowModel.overview.filterPhase == .inactive)
        #expect(!windowModel.isOverviewPresented)
        #expect(session.navigation.focusedBoard?.id == second.id)
    }

    @Test func overviewEscapeRequestsBoardDragCancellation() throws {
        let first = makeTestBoard("First")
        let session = try makeKeyboardTestSession(boards: [first])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()
        #expect(windowModel.beginOverviewBoardDrag(first.id))

        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53
        )

        #expect(
            KeyboardController.decision(for: escape, session: session, windowModel: windowModel)
                == .perform(.board(.requestDragCancellation))
        )
        #expect(KeyboardController.handle(escape, session: session, windowModel: windowModel))
        #expect(windowModel.boardDragCancellationRequest == 1)
        #expect(windowModel.isOverviewPresented)
    }

    @Test func zmxSessionsEscapeClosesPanel() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.configuration.preferences.setZmxPath("/missing/zmx")
        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53
        )

        windowModel.showZmxSessions()

        #expect(windowModel.isZmxSessionsPresented)
        #expect(
            KeyboardController.decision(for: escape, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.hide))
        )
        #expect(KeyboardController.handle(escape, session: session, windowModel: windowModel))
        #expect(!windowModel.isZmxSessionsPresented)
    }

    @Test func zmxSessionsArrowSelectionAndActionsUseTheFocusedSession() async throws {
        let session = try makeKeyboardTestSession(
            terminalCommandRunner: ZmxKeyboardCommandRunner(
                responses: [
                    ["list"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "name=den\nname=den-vi\tden.root=den\n"
                    )
                ])
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.configuration.preferences.setZmxPath("/opt/homebrew/bin/zmx")
        windowModel.showZmxSessions()
        await waitForTestZmxSessionLoad(windowModel)

        let down = try arrowEvent(.downArrow, modifiers: [])
        let upArrow = try arrowEvent(.upArrow, modifiers: [])
        let returnKey = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36
        )
        let delete = try keyEvent(
            characters: "\u{8}",
            charactersIgnoringModifiers: "\u{8}",
            keyCode: 51
        )
        let deleteKey = try keyEvent(
            characters: "x",
            charactersIgnoringModifiers: "x",
            keyCode: 7
        )
        let reload = try keyEvent(characters: "r", charactersIgnoringModifiers: "r", keyCode: 15)
        let jKey = try keyEvent(characters: "j", charactersIgnoringModifiers: "j", keyCode: 38)
        let kKey = try keyEvent(characters: "k", charactersIgnoringModifiers: "k", keyCode: 40)
        let space = try keyEvent(characters: " ", charactersIgnoringModifiers: " ", keyCode: 49)
        let selectAll = try keyEvent(
            characters: "a",
            charactersIgnoringModifiers: "a",
            modifiers: [.command],
            keyCode: 0
        )
        let filter = try keyEvent(characters: "/", charactersIgnoringModifiers: "/", keyCode: 44)
        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53
        )

        #expect(windowModel.zmxSessions.selectedSessionName == "den")
        #expect(
            KeyboardController.decision(for: down, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.moveSelection(1)))
        )
        #expect(KeyboardController.handle(down, session: session, windowModel: windowModel))
        #expect(windowModel.zmxSessions.selectedSessionName == "den-vi")
        #expect(KeyboardController.handle(upArrow, session: session, windowModel: windowModel))
        #expect(windowModel.zmxSessions.selectedSessionName == "den")
        #expect(
            KeyboardController.decision(for: jKey, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.moveSelection(1)))
        )
        #expect(KeyboardController.handle(jKey, session: session, windowModel: windowModel))
        #expect(windowModel.zmxSessions.selectedSessionName == "den-vi")
        #expect(KeyboardController.handle(kKey, session: session, windowModel: windowModel))
        #expect(windowModel.zmxSessions.selectedSessionName == "den")
        #expect(KeyboardController.handle(space, session: session, windowModel: windowModel))
        #expect(windowModel.zmxSessions.markedSessionNames == ["den"])
        #expect(
            KeyboardController.decision(for: selectAll, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.selectAll))
        )
        #expect(KeyboardController.handle(selectAll, session: session, windowModel: windowModel))
        #expect(windowModel.zmxSessions.markedSessionNames == ["den", "den-vi"])
        #expect(
            KeyboardController.decision(for: escape, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.clearSelection))
        )
        #expect(KeyboardController.handle(escape, session: session, windowModel: windowModel))
        #expect(windowModel.zmxSessions.markedSessionNames.isEmpty)
        #expect(
            KeyboardController.decision(for: returnKey, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.openSelected))
        )
        #expect(
            KeyboardController.decision(for: filter, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.enterFilter))
        )
        #expect(KeyboardController.handle(filter, session: session, windowModel: windowModel))
        #expect(windowModel.zmxSessions.isFilterInputActive)
        windowModel.zmxSessions.setQuery("vi")
        #expect(
            KeyboardController.decision(for: selectAll, session: session, windowModel: windowModel)
                == .forward(.filterTextInput)
        )
        #expect(
            KeyboardController.decision(for: down, session: session, windowModel: windowModel)
                == .forward(.filterTextInput)
        )
        #expect(
            KeyboardController.decision(for: deleteKey, session: session, windowModel: windowModel)
                == .forward(.filterTextInput)
        )
        #expect(
            KeyboardController.decision(for: returnKey, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.confirmFilterQuery))
        )
        #expect(KeyboardController.handle(returnKey, session: session, windowModel: windowModel))
        #expect(windowModel.zmxSessions.filterPhase == .selecting)
        #expect(
            KeyboardController.decision(for: returnKey, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.openSelected))
        )
        #expect(
            KeyboardController.decision(for: down, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.moveSelection(1)))
        )
        #expect(KeyboardController.handle(escape, session: session, windowModel: windowModel))
        #expect(windowModel.zmxSessions.filterPhase == .inactive)
        #expect(windowModel.zmxSessions.query.isEmpty)
        #expect(
            KeyboardController.decision(for: escape, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.hide))
        )
        #expect(
            KeyboardController.decision(for: delete, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.deleteSelected))
        )
        #expect(
            KeyboardController.decision(for: deleteKey, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.deleteSelected))
        )
        #expect(
            KeyboardController.decision(for: reload, session: session, windowModel: windowModel)
                == .perform(.zmxSessions(.refresh))
        )
        #expect(KeyboardController.handle(delete, session: session, windowModel: windowModel))
        #expect(windowModel.zmxSessions.pendingDeletion == ["den"])
        #expect(
            KeyboardController.decision(for: returnKey, session: session, windowModel: windowModel)
                == .forward(.temporaryTextInput)
        )
    }
}

private struct ZmxKeyboardCommandRunner: TerminalCommandRunning, Sendable {
    let responses: [[String]: TerminalCommandResult]

    func run(
        executablePath: String,
        arguments: [String],
        timeout: Duration
    ) async throws -> TerminalCommandResult {
        guard let response = responses[arguments] else {
            throw TerminalCommandError(message: "Missing stub response for \(arguments)")
        }
        return response
    }
}
