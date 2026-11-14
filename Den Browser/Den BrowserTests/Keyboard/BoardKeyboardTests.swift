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
struct BoardKeyboardTests {
    @Test func denModeQQuitsBoardAndIgnoresRepeats() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("Board")])
        let model = DenWindowComposition(session: session).model
        model.isDenMode = true
        let quit = try keyEvent(characters: "q", charactersIgnoringModifiers: "q", keyCode: 12)
        let repeated = try keyEvent(characters: "q", charactersIgnoringModifiers: "q", isARepeat: true, keyCode: 12)

        // Act
        let decision = KeyboardController.decision(for: quit, session: session, windowModel: model)
        let repeatedDecision = KeyboardController.decision(for: repeated, session: session, windowModel: model)

        // Assert
        #expect(decision == .perform(.board(.quit)))
        #expect(repeatedDecision == .consume(.ignoredRepeat))
    }

    @Test(arguments: ["https://clipboard.example/", "Swift concurrency"])
    func denModeOptionVOpensClipboardInDrawer(input: String) throws {
        // Arrange
        let original = makeTestBoard("First")
        let session = try makeKeyboardTestSession(boards: [original])
        let composition = DenWindowComposition(session: session)
        let model = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.pasteboard.setString(input, forType: .string)
        model.isDenMode = true
        let event = try keyEvent(
            characters: "√",
            charactersIgnoringModifiers: "v",
            modifiers: [.option],
            keyCode: 9
        )
        let repeated = try keyEvent(
            characters: "√",
            charactersIgnoringModifiers: "v",
            modifiers: [.option],
            isARepeat: true,
            keyCode: 9
        )

        // Act
        let decision = KeyboardController.decision(for: event, session: session, windowModel: model)
        let repeatedDecision = KeyboardController.decision(for: repeated, session: session, windowModel: model)
        let handled = KeyboardController.handle(event, session: session, windowModel: model)

        // Assert
        #expect(decision == .perform(.board(.openClipboardInDrawer)))
        #expect(handled)
        let item = try #require(session.resources.state.drawerItems.first)
        #expect(
            item.url
                == BoardInputResolver.normalizedURL(
                    from: input,
                    searchEngine: session.configuration.preferences.searchEngine
                )
        )
        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [original.id])
        #expect(model.drawer.expandedItemID == item.id)
        #expect(repeatedDecision == .consume(.ignoredRepeat))
    }

    @Test func commandSTogglesBoardRailAndIgnoresKeyRepeat() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("Board")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let toggle = try keyEvent(
            characters: "s",
            charactersIgnoringModifiers: "s",
            modifiers: [.command],
            keyCode: 1
        )
        let repeatToggle = try keyEvent(
            characters: "s",
            charactersIgnoringModifiers: "s",
            modifiers: [.command],
            isARepeat: true,
            keyCode: 1
        )

        #expect(
            KeyboardController.decision(for: toggle, session: session, windowModel: windowModel)
                == .perform(.application(.toggleBoardRail))
        )
        #expect(
            KeyboardController.decision(
                for: repeatToggle,
                session: session,
                windowModel: windowModel
            ) == .consume(.ignoredRepeat)
        )
    }

    @Test func denModeEqualsWidensFocusedBoardWithOrWithoutShift() throws {
        for (characters, modifiers) in [("=", NSEvent.ModifierFlags()), ("+", NSEvent.ModifierFlags.shift)] {
            let session = try makeKeyboardTestSession(boards: [makeTestBoard("Focused")])
            let composition = DenWindowComposition(session: session)
            let windowModel = composition.model
            composition.connect()
            defer { composition.disconnect() }
            windowModel.isDenMode = true
            let event = try keyEvent(
                characters: characters,
                charactersIgnoringModifiers: "=",
                modifiers: modifiers,
                keyCode: 24
            )

            #expect(KeyboardController.handle(event, session: session, windowModel: windowModel))
            #expect(session.navigation.focusedBoard?.width == 600)
        }
    }

    @Test func denModeAngleBracketsBrowseBoardsWithoutChangingFocus() throws {
        let first = makeTestBoard("First")
        let second = makeTestBoard("Second")
        let session = try makeKeyboardTestSession(boards: [first, second])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let right = try keyEvent(
            characters: ">",
            charactersIgnoringModifiers: ".",
            modifiers: [.shift],
            keyCode: 47
        )

        #expect(KeyboardController.handle(right, session: session, windowModel: windowModel))
        #expect(windowModel.revealNextBoardRequest == 1)
        #expect(session.navigation.focusedDesk?.focusedBoardID == first.id)

        let left = try keyEvent(
            characters: "<",
            charactersIgnoringModifiers: ",",
            modifiers: [.shift],
            keyCode: 43
        )

        #expect(KeyboardController.handle(left, session: session, windowModel: windowModel))
        #expect(windowModel.revealPreviousBoardRequest == 1)
        #expect(session.navigation.focusedDesk?.focusedBoardID == first.id)
    }

    @Test func denModeControlSCopiesCurrentSheetScreenshot() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First"), makeTestBoard("Second")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let controlS = try keyEvent(
            characters: "s",
            charactersIgnoringModifiers: "s",
            modifiers: [.control],
            keyCode: 1
        )
        #expect(
            KeyboardController.decision(for: controlS, session: session, windowModel: windowModel)
                == .perform(.board(.copySheetScreenshot))
        )
    }

    @Test func denModeYCopiesFocusedBoardLocationAndShiftYCopiesBoardID() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let locationEvent = try keyEvent(
            characters: "y",
            charactersIgnoringModifiers: "y",
            keyCode: 16
        )
        let boardIDEvent = try keyEvent(
            characters: "Y",
            charactersIgnoringModifiers: "y",
            modifiers: [.shift],
            keyCode: 16
        )

        // Act
        let locationDecision = KeyboardController.decision(
            for: locationEvent,
            session: session,
            windowModel: windowModel
        )
        let boardIDDecision = KeyboardController.decision(
            for: boardIDEvent,
            session: session,
            windowModel: windowModel
        )

        // Assert
        #expect(
            locationDecision == .perform(.board(.copyLocation))
        )
        #expect(
            boardIDDecision == .perform(.board(.copyID))
        )
    }

    @Test func contentSizeShortcutsRouteToTheFocusedBoardInEveryInputMode() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("Focused")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let increase = try keyEvent(
            characters: "=",
            charactersIgnoringModifiers: "=",
            modifiers: [.command],
            keyCode: 24
        )
        let plus = try keyEvent(
            characters: "+",
            charactersIgnoringModifiers: "=",
            modifiers: [.command, .shift],
            keyCode: 24
        )
        let decrease = try keyEvent(
            characters: "-",
            charactersIgnoringModifiers: "-",
            modifiers: [.command],
            keyCode: 27
        )
        let reset = try keyEvent(
            characters: "0",
            charactersIgnoringModifiers: "0",
            modifiers: [.command],
            keyCode: 29
        )

        #expect(
            KeyboardController.decision(for: increase, session: session, windowModel: windowModel)
                == .perform(.board(.increaseSheetSize))
        )
        #expect(
            KeyboardController.decision(for: plus, session: session, windowModel: windowModel)
                == .perform(.board(.increaseSheetSize))
        )
        #expect(
            KeyboardController.decision(for: decrease, session: session, windowModel: windowModel)
                == .perform(.board(.decreaseSheetSize))
        )
        #expect(
            KeyboardController.decision(for: reset, session: session, windowModel: windowModel)
                == .perform(.board(.resetSheetSize))
        )

        windowModel.isDenMode = true
        #expect(
            KeyboardController.decision(for: decrease, session: session, windowModel: windowModel)
                == .perform(.board(.decreaseSheetSize))
        )
    }

    @Test(arguments: [false, true])
    func commandDCreatesTerminalSideBoardInEveryInputMode(_ isDenMode: Bool) throws {
        // Arrange
        let primary = BoardState(label: "Terminal", width: 520, workingDirectory: "/work")
        let session = try makeKeyboardTestSession(boards: [primary])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = isDenMode
        let commandD = try keyEvent(
            characters: "d",
            charactersIgnoringModifiers: "d",
            modifiers: [.command],
            keyCode: 2
        )

        // Act
        let handled = KeyboardController.handle(commandD, session: session, windowModel: windowModel)

        // Assert
        let sideBoard = try #require(session.navigation.focusedBoard)
        #expect(handled)
        #expect(session.resources.state.desks[0].boards.count == 2)
        #expect(sideBoard.id != primary.id)
        #expect(sideBoard.label == "Terminal Side Board")
        #expect(sideBoard.isTerminal)
        #expect(sideBoard.isSideBoard)
        #expect(sideBoard.sideBoardTargetBoardID == primary.id)
        #expect(sideBoard.terminalWorkingDirectory == "/work")
        #expect(session.sideBoards.createTerminalSideBoard(targetBoardID: sideBoard.id) == sideBoard.id)
        #expect(session.resources.state.desks[0].boards.count == 2)
    }

    @Test func commandDIsDisabledForWebBoards() throws {
        // Arrange
        let webBoard = makeTestBoard("Web")
        let session = try makeKeyboardTestSession(boards: [webBoard])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let commandD = try keyEvent(
            characters: "d",
            charactersIgnoringModifiers: "d",
            modifiers: [.command],
            keyCode: 2
        )

        // Act
        let decision = KeyboardController.decision(for: commandD, session: session, windowModel: windowModel)
        let handled = KeyboardController.handle(commandD, session: session, windowModel: windowModel)

        // Assert
        #expect(decision == .forward(.sheet))
        #expect(!handled)
        #expect(session.resources.state.desks[0].boards == [webBoard])
    }

    @Test func denModeVOpensBoardFromClipboard() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        session.pasteboard.clearContents()
        session.pasteboard.setString("https://example.com/test", forType: .string)

        let vKey = try keyEvent(
            characters: "v",
            charactersIgnoringModifiers: "v",
            keyCode: 9
        )

        #expect(KeyboardController.handle(vKey, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedDesk?.boards.count == 2)
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://example.com/test"))
        #expect(!windowModel.isDenMode)
    }

    @Test func denModeBKeyOpensSaveEssentialPanelForFocusedBoard() throws {
        let board = BoardState(
            label: "Niri",
            width: 520,
            currentSheetURL: URL(string: "https://github.com/YaLTeR/niri")
        )
        let desk = DeskState(label: "Dev", boards: [board], focusedBoardID: board.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        let bKey = try keyEvent(
            characters: "b",
            charactersIgnoringModifiers: "b",
            keyCode: 11
        )

        #expect(KeyboardController.handle(bKey, session: session, windowModel: windowModel))
        #expect(windowModel.isSaveEssentialPanelPresented)
        #expect(windowModel.saveEssentialDraft?.name == "Niri")
        #expect(windowModel.saveEssentialDraft?.input == "https://github.com/YaLTeR/niri")
    }

    @Test func denModeMKeyTogglesAnchorBoardAndShiftMJumps() throws {
        let first = makeTestBoard("First")
        let second = makeTestBoard("Second")
        let session = try makeKeyboardTestSession(boards: [first, second])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        let mKey = try keyEvent(
            characters: "m",
            charactersIgnoringModifiers: "m",
            keyCode: 46
        )
        let shiftMKey = try keyEvent(
            characters: "M",
            charactersIgnoringModifiers: "m",
            modifiers: [.shift],
            keyCode: 46
        )

        // Focus is on first board. Press 'm' to set anchor.
        #expect(KeyboardController.handle(mKey, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedDesk?.anchorBoardID == first.id)
        #expect(session.feedback.latest?.message == "Set Anchor Board")

        // Move to second board.
        session.boardNavigation.focusBoard(second.id)
        #expect(session.navigation.focusedBoard?.id == second.id)

        // Press 'Shift + m' to jump to anchor first board.
        #expect(KeyboardController.handle(shiftMKey, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedBoard?.id == first.id)

        // Press 'Shift + m' again to return to second board (A <-> B toggle).
        #expect(KeyboardController.handle(shiftMKey, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedBoard?.id == second.id)

        // Press 'm' on second board to move anchor.
        #expect(KeyboardController.handle(mKey, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedDesk?.anchorBoardID == second.id)

        // Press 'm' again on second board to clear anchor.
        #expect(KeyboardController.handle(mKey, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedDesk?.anchorBoardID == nil)
        #expect(session.feedback.latest?.message == "Cleared Anchor Board")

        // Press 'Shift + m' with no anchor shows warning.
        #expect(KeyboardController.handle(shiftMKey, session: session, windowModel: windowModel))
        #expect(session.feedback.latest?.message == "No Anchor Board in Desk")
        #expect(session.feedback.latest?.severity == .warning)
    }

    @Test func shiftEscapeTogglesBoardActivityAcrossInputContexts() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let shiftEscape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            modifiers: [.shift],
            keyCode: 53
        )

        #expect(KeyboardController.handle(shiftEscape, session: session, windowModel: windowModel))
        #expect(windowModel.isBoardActivityPresented)

        #expect(KeyboardController.handle(shiftEscape, session: session, windowModel: windowModel))
        #expect(!windowModel.isBoardActivityPresented)

        windowModel.isDenMode = true
        #expect(KeyboardController.handle(shiftEscape, session: session, windowModel: windowModel))
        #expect(windowModel.isBoardActivityPresented)

        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53
        )
        #expect(KeyboardController.handle(escape, session: session, windowModel: windowModel))
        #expect(!windowModel.isBoardActivityPresented)
    }

    @Test func denModeEnterAndShiftEnterUseDistinctDuplicateActions() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let returnKey = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36
        )
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36
        )

        #expect(
            KeyboardController.decision(for: returnKey, session: session, windowModel: windowModel)
                == .perform(.board(.duplicate))
        )
        #expect(
            KeyboardController.decision(for: shiftReturn, session: session, windowModel: windowModel)
                == .perform(.board(.duplicateFirstSheet))
        )
    }

    @Test(arguments: ["d", "x"])
    func denModeRemoveShortcutsChooseTheirFocusDirection(key: String) throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("Focused")])
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        composition.model.isDenMode = true
        let event = try keyEvent(
            characters: key,
            charactersIgnoringModifiers: key,
            keyCode: key == "d" ? 2 : 7
        )

        // Act
        let decision = KeyboardController.decision(for: event, session: session, windowModel: composition.model)

        // Assert
        #expect(decision == .perform(.board(key == "d" ? .removeAndFocusNext : .remove)))
    }

    @Test func hardReloadCurrentSheetShortcutReloadsOnlyFocusedBoard() throws {
        let first = makeTestBoard("First")
        let second = makeTestBoard("Second")
        let session = try makeKeyboardTestSession(boards: [first, second])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let reload = try keyEvent(
            characters: "R",
            charactersIgnoringModifiers: "r",
            modifiers: [.command, .shift],
            keyCode: 15
        )

        #expect(KeyboardController.handle(reload, session: session, windowModel: windowModel))
        #expect(Set(session.resources.webRuntimes.keys) == Set([first.id]))
        #expect(session.navigation.focusedDesk?.focusedBoardID == first.id)
    }

    @Test func reloadFocusedDeskSheetsShortcutReloadsOnlyFocusedDesk() throws {
        let first = makeTestBoard("First")
        let second = makeTestBoard("Second")
        let other = makeTestBoard("Other")
        let firstDesk = DeskState(
            label: "First Desk",
            boards: [first, second],
            focusedBoardID: first.id
        )
        let secondDesk = DeskState(
            label: "Second Desk",
            boards: [other],
            focusedBoardID: other.id
        )
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [firstDesk, secondDesk],
                        focusedDeskID: firstDesk.id
                    )
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let reload = try keyEvent(
            characters: "R",
            charactersIgnoringModifiers: "r",
            modifiers: [.command, .option, .shift],
            keyCode: 15
        )

        #expect(KeyboardController.handle(reload, session: session, windowModel: windowModel))
        #expect(Set(session.resources.webRuntimes.keys) == Set([first.id, second.id]))
        #expect(session.navigation.focusedDesk?.id == firstDesk.id)
        #expect(session.resources.state.desks.map(\.id) == [firstDesk.id, secondDesk.id])
    }

    @Test func denModeEOpensFocusedBoardLinkEditor() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let editLink = try keyEvent(characters: "e", charactersIgnoringModifiers: "e", keyCode: 14)

        #expect(KeyboardController.handle(editLink, session: session, windowModel: windowModel))
        #expect(windowModel.isEditBoardLinkPanelPresented)
    }

    @Test func denModeShiftReturnCreatesBoardFromFirstSheet() throws {
        let firstSheetURL = try #require(URL(string: "https://example.com/origin"))
        let currentSheetURL = try #require(URL(string: "https://example.com/current"))
        let source = BoardState(
            label: "First",
            width: 520,
            currentSheetURL: currentSheetURL,
            firstSheetURL: firstSheetURL
        )
        let session = try makeKeyboardTestSession(boards: [source])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36
        )

        #expect(KeyboardController.handle(shiftReturn, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedDesk?.boards.count == 2)
        #expect(session.navigation.focusedBoard?.currentSheetURL == firstSheetURL)
        #expect(!windowModel.isDenMode)
    }

    @Test func denModeShiftReturnDoesNothingWithoutFirstSheet() throws {
        var source = BoardState(
            label: "Legacy",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/current"),
            firstSheetURL: nil
        )
        source.firstSheetURL = nil
        let session = try makeKeyboardTestSession(boards: [source])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36
        )

        #expect(KeyboardController.handle(shiftReturn, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedDesk?.boards.count == 1)
        #expect(windowModel.isDenMode)
    }

    @Test func denModeTTogglesSheetNavigationPauseForFocusedBoard() throws {
        let suiteName = "KeyboardSheetNavigationTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sheetNavigation = SheetNavigationManager(defaults: defaults, scriptSource: "")
        let desk = DeskState(label: "Desk", boards: [makeTestBoard("First")])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: sheetNavigation)
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let toggle = try keyEvent(characters: "t", charactersIgnoringModifiers: "t", keyCode: 17)
        let repeatedToggle = try keyEvent(
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: true,
            keyCode: 17
        )
        #expect(session.navigation.focusedBoard?.sheetNavigationPaused == false)
        #expect(KeyboardController.handle(toggle, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedBoard?.sheetNavigationPaused == true)
        #expect(KeyboardController.handle(repeatedToggle, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedBoard?.sheetNavigationPaused == true)
        #expect(KeyboardController.handle(toggle, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedBoard?.sheetNavigationPaused == false)
    }

    @Test func denModeShiftBracketsHandleFirstAndLatestSheet() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let first = try keyEvent(
            characters: "{",
            charactersIgnoringModifiers: "{",
            modifiers: [.shift],
            keyCode: 33
        )
        let latest = try keyEvent(
            characters: "}",
            charactersIgnoringModifiers: "}",
            modifiers: [.shift],
            keyCode: 30
        )

        #expect(KeyboardController.handle(first, session: session, windowModel: windowModel))
        #expect(KeyboardController.handle(latest, session: session, windowModel: windowModel))
        #expect(windowModel.isDenMode)
    }
}
