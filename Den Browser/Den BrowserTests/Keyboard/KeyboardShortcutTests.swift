import AppKit
import DenDomain
import DenPresentationModels
import Foundation
import Testing

@testable import Den_Browser

private final class TestUserDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    init?(suiteName: String) {
        super.init(suiteName: suiteName)
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }

    override func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    override func string(forKey defaultName: String) -> String? {
        values[defaultName] as? String
    }

    override func data(forKey defaultName: String) -> Data? {
        values[defaultName] as? Data
    }

    override func bool(forKey defaultName: String) -> Bool {
        values[defaultName] as? Bool ?? false
    }

    override func removeObject(forKey defaultName: String) {
        values.removeValue(forKey: defaultName)
    }
}

@MainActor
@Suite(.serialized)
struct KeyboardShortcutTests {
    @Test func universalSearchForwardsMarkedTextConfirmationInsteadOfExecuting() throws {
        // Arrange
        let controller = try makeController(boards: [board("Board")])
        let model = DenWindowComposition(controller: controller).model
        model.showUniversalSearch()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        window.contentView?.addSubview(editor)
        #expect(window.makeFirstResponder(editor))
        editor.setMarkedText(
            "検索", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        #expect(KeyEvent(event).hasMarkedText)

        // Act
        let decision = KeyboardController.decision(for: event, controller: controller, windowModel: model)

        // Assert
        #expect(decision == .forward(.temporaryTextInput))
        #expect(model.universalSearch.submissionRequest == 0)
    }

    @Test func universalSearchEntrancesRouteToTheSamePresentation() throws {
        // Arrange
        let controller = try makeController(boards: [board("Board")])
        let composition = DenWindowComposition(controller: controller)
        let model = composition.model
        let search = try keyEvent(characters: "p", charactersIgnoringModifiers: "p", modifiers: [.command], keyCode: 35)
        let commands = try keyEvent(
            characters: "P", charactersIgnoringModifiers: "P", modifiers: [.command, .shift], keyCode: 35)
        let colon = try keyEvent(characters: ":", charactersIgnoringModifiers: ":", modifiers: [.shift], keyCode: 41)

        // Act
        let searchDecision = KeyboardController.decision(for: search, controller: controller, windowModel: model)
        let commandDecision = KeyboardController.decision(for: commands, controller: controller, windowModel: model)
        model.isDenMode = true
        let colonDecision = KeyboardController.decision(for: colon, controller: controller, windowModel: model)

        // Assert
        #expect(searchDecision == .perform(.application(.showUniversalSearch(commandsOnly: false))))
        #expect(commandDecision == .perform(.application(.showUniversalSearch(commandsOnly: true))))
        #expect(colonDecision == searchDecision)
    }

    @Test func universalSearchOwnsInputAndCancelPreservesDenMode() throws {
        // Arrange
        let controller = try makeController(boards: [board("Board")])
        let composition = DenWindowComposition(controller: controller)
        let model = composition.model
        model.isDenMode = true
        model.showUniversalSearch(commandsOnly: true)
        let letter = try keyEvent(characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let enter = try keyEvent(characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let escape = try keyEvent(characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)

        // Act
        let letterDecision = KeyboardController.decision(for: letter, controller: controller, windowModel: model)
        let enterDecision = KeyboardController.decision(for: enter, controller: controller, windowModel: model)
        let escapeDecision = KeyboardController.decision(for: escape, controller: controller, windowModel: model)
        AppActionHandler.perform(.application(.hideUniversalSearch), controller: controller, windowModel: model)

        // Assert
        #expect(model.universalSearch.commandsOnly)
        #expect(letterDecision == .forward(.temporaryTextInput))
        #expect(enterDecision == .perform(.application(.submitSearch)))
        #expect(escapeDecision == .perform(.application(.hideUniversalSearch)))
        #expect(model.temporaryContext == nil)
        #expect(model.isDenMode)
    }

    @Test func keyboardShortcutGuideForwardsTextInputAndKeepsEscapeToClose() throws {
        // Arrange
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showKeyboardShortcuts()
        let letterA = try keyEvent(
            characters: "a", charactersIgnoringModifiers: "a", keyCode: 0)
        let commandA = try keyEvent(
            characters: "a", charactersIgnoringModifiers: "a", modifiers: [.command], keyCode: 0)
        let commandT = try keyEvent(
            characters: "t", charactersIgnoringModifiers: "t", modifiers: [.command], keyCode: 17)
        let questionMark = try keyEvent(
            characters: "?", charactersIgnoringModifiers: "/", modifiers: [.shift], keyCode: 44)
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)

        // Act
        let letterDecision = KeyboardController.decision(for: letterA, controller: controller, windowModel: windowModel)
        let selectAllDecision = KeyboardController.decision(
            for: commandA, controller: controller, windowModel: windowModel)
        let commandTDecision = KeyboardController.decision(
            for: commandT, controller: controller, windowModel: windowModel)
        let questionDecision = KeyboardController.decision(
            for: questionMark, controller: controller, windowModel: windowModel)
        let escapeDecision = KeyboardController.decision(for: escape, controller: controller, windowModel: windowModel)

        // Assert
        #expect(letterDecision == .forward(.filterTextInput))
        #expect(selectAllDecision == .forward(.filterTextInput))
        #expect(commandTDecision == .forward(.filterTextInput))
        #expect(questionDecision == .forward(.filterTextInput))
        #expect(escapeDecision == .perform(.application(.hideKeyboardShortcuts)))
    }

    @Test func shortcutOverridesPersistClearAndReset() throws {
        let suiteName = "KeyboardShortcutTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let customToggle = ShortcutBinding(key: .character("."), modifiers: [.control])
        let customDeskNumber = ShortcutBinding(
            key: .character("1"), modifiers: [.control, .option])

        #expect(preferences.shortcut(for: .toggleDenMode) == ConfigurableShortcut.toggleDenMode.defaultBinding)
        #expect(
            preferences.deskNumberBinding
                == ShortcutBinding(key: .character("1"), modifiers: [.command, .option]))
        #expect(preferences.setShortcut(customToggle, for: .toggleDenMode) == nil)
        #expect(preferences.setDeskNumberBinding(customDeskNumber) == nil)
        preferences.clearShortcut(for: .focusPreviousBoard)

        let restored = AppPreferences(defaults: defaults)
        #expect(
            Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys) == [
                "preferences.schema.version",
                "preferences.shortcuts.actions.toggle-den-mode",
                "preferences.shortcuts.actions.focus-previous-board",
                "preferences.shortcuts.desk-number.binding",
            ])
        #expect(defaults.integer(forKey: "preferences.schema.version") == 1)
        #expect(restored.shortcut(for: .toggleDenMode) == customToggle)
        #expect(restored.shortcut(for: .focusPreviousBoard) == nil)
        #expect(restored.deskNumberBinding == customDeskNumber)

        restored.resetShortcut(for: .toggleDenMode)
        #expect(restored.shortcut(for: .toggleDenMode) == ConfigurableShortcut.toggleDenMode.defaultBinding)
        restored.clearDeskNumberBinding()
        #expect(restored.deskNumberBinding == nil)
        #expect(AppPreferences(defaults: defaults).deskNumberBinding == nil)
        restored.resetDeskNumberBinding()
        restored.resetAllShortcuts()
        #expect(restored.shortcutOverrides.isEmpty)
        #expect(restored.shortcut(for: .focusPreviousBoard) == ConfigurableShortcut.focusPreviousBoard.defaultBinding)
        #expect(restored.deskNumberBinding == AppPreferences.defaultDeskNumberBinding)
    }

    @Test func shortcutValidationRejectsMissingModifierAndDuplicate() throws {
        let preferences = try makePreferences()
        let unmodified = ShortcutBinding(key: .character("a"), modifiers: [])

        #expect(preferences.setShortcut(unmodified, for: .toggleDenMode) == .invalid)
        #expect(
            preferences.setShortcut(
                ConfigurableShortcut.focusPreviousBoard.defaultBinding,
                for: .focusNextBoard) == .conflict(.focusPreviousBoard))
        #expect(
            preferences.setShortcut(
                ShortcutBinding(key: .character("1"), modifiers: [.command, .option]),
                for: .focusNextBoard) == .conflictWithDeskNumber)
        #expect(
            preferences.setDeskNumberBinding(
                ShortcutBinding(key: .character("1"), modifiers: [.shift, .command, .option])) == nil)
        #expect(
            preferences.setDeskNumberBinding(
                ShortcutBinding(key: .character("1"), modifiers: [.shift])) == .invalid)
        preferences.clearShortcut(for: .toggleDenMode)
        #expect(preferences.shortcut(for: .toggleDenMode) == ConfigurableShortcut.toggleDenMode.defaultBinding)
    }

    @Test func unreadableAndDuplicateOverridesFallBackSafely() throws {
        let suiteName = "KeyboardShortcutCorruptionTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            Data("not a property list".utf8),
            forKey: "preferences.shortcuts.actions.toggle-den-mode")

        let duplicate = ShortcutOverride.assigned(
            ShortcutBinding(key: .character("b"), modifiers: [.control]))
        let data = try PropertyListEncoder().encode(duplicate)
        defaults.set(data, forKey: "preferences.shortcuts.actions.focus-previous-board")
        defaults.set(data, forKey: "preferences.shortcuts.actions.focus-next-board")

        let preferences = AppPreferences(defaults: defaults)
        let effective = ConfigurableShortcut.allCases.compactMap(preferences.shortcut)
        #expect(preferences.shortcut(for: .toggleDenMode) == ConfigurableShortcut.toggleDenMode.defaultBinding)
        #expect(Set(effective).count == effective.count)
    }

    @Test func eventsNormalizeLogicalCharactersAndSupportedSpecialKeys() throws {
        let letter = try keyEvent(
            characters: "A",
            charactersIgnoringModifiers: "A",
            modifiers: [.capsLock, .command],
            keyCode: 0)
        #expect(
            ShortcutBinding(event: letter)
                == ShortcutBinding(key: .character("a"), modifiers: [.command]))

        let shiftedDigit = try keyEvent(
            characters: "!",
            charactersIgnoringModifiers: "!",
            modifiers: [.shift],
            keyCode: 18)
        #expect(
            ShortcutBinding(event: shiftedDigit)
                == ShortcutBinding(key: .character("1"), modifiers: [.shift]))

        let functionCharacter = String(try #require(UnicodeScalar(NSEvent.SpecialKey.f12.rawValue)))
        let function = try keyEvent(
            characters: functionCharacter,
            charactersIgnoringModifiers: functionCharacter,
            modifiers: [.control],
            keyCode: 111)
        #expect(
            ShortcutBinding(event: function)
                == ShortcutBinding(key: .function(12), modifiers: [.control]))
        #expect(ConfigurableShortcut.moveFocusedBoardLeft.defaultBinding.displayTokens == ["⌥", "⇧", "⌘", "←"])
    }

    @Test func commandSTogglesBoardRailAndIgnoresKeyRepeat() throws {
        let controller = try makeController(boards: [board("Board")])
        let composition = DenWindowComposition(controller: controller)
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
            KeyboardController.decision(for: toggle, controller: controller, windowModel: windowModel)
                == .perform(.application(.toggleBoardRail))
        )
        #expect(
            KeyboardController.decision(
                for: repeatToggle,
                controller: controller,
                windowModel: windowModel
            ) == .consume(.ignoredRepeat)
        )
    }

    @Test func denModeShiftDigitMovesFocusedBoardToDesk() throws {
        let movedBoard = board("Moved")
        let firstDesk = DeskState(label: "First", boards: [], focusedBoardID: nil)
        let secondDesk = DeskState(
            label: "Second",
            boards: [movedBoard],
            focusedBoardID: movedBoard.id)
        let controller = try makeController(desks: [firstDesk, secondDesk])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.focusDesk(secondDesk.id)
        windowModel.isDenMode = true

        let shiftOne = try keyEvent(
            characters: "!",
            charactersIgnoringModifiers: "!",
            modifiers: [.shift],
            keyCode: 18)

        #expect(KeyboardController.handle(shiftOne, controller: controller, windowModel: windowModel))
        #expect(controller.state.focusedDeskID == firstDesk.id)
        #expect(controller.focusedDesk?.focusedBoardID == movedBoard.id)
        #expect(controller.state.desks[0].boards.map(\.id) == [movedBoard.id])
        #expect(!windowModel.isDenMode)
    }

    @Test func denModeEqualsWidensFocusedBoardWithOrWithoutShift() throws {
        for (characters, modifiers) in [("=", NSEvent.ModifierFlags()), ("+", NSEvent.ModifierFlags.shift)] {
            let controller = try makeController(boards: [board("Focused")])
            let composition = DenWindowComposition(controller: controller)
            let windowModel = composition.model
            composition.connect()
            defer { composition.disconnect() }
            windowModel.isDenMode = true
            let event = try keyEvent(
                characters: characters,
                charactersIgnoringModifiers: "=",
                modifiers: modifiers,
                keyCode: 24)

            #expect(KeyboardController.handle(event, controller: controller, windowModel: windowModel))
            #expect(controller.focusedBoard?.width == 600)
        }
    }

    @Test func denModeAngleBracketsBrowseBoardsWithoutChangingFocus() throws {
        let first = board("First")
        let second = board("Second")
        let controller = try makeController(boards: [first, second])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let right = try keyEvent(
            characters: ">",
            charactersIgnoringModifiers: ".",
            modifiers: [.shift],
            keyCode: 47)

        #expect(KeyboardController.handle(right, controller: controller, windowModel: windowModel))
        #expect(windowModel.revealNextBoardRequest == 1)
        #expect(controller.focusedDesk?.focusedBoardID == first.id)

        let left = try keyEvent(
            characters: "<",
            charactersIgnoringModifiers: ",",
            modifiers: [.shift],
            keyCode: 43)

        #expect(KeyboardController.handle(left, controller: controller, windowModel: windowModel))
        #expect(windowModel.revealPreviousBoardRequest == 1)
        #expect(controller.focusedDesk?.focusedBoardID == first.id)
    }

    @Test func denModeControlSCopiesCurrentSheetScreenshot() throws {
        let controller = try makeController(boards: [board("First"), board("Second")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let controlS = try keyEvent(
            characters: "s",
            charactersIgnoringModifiers: "s",
            modifiers: [.control],
            keyCode: 1)
        #expect(
            KeyboardController.decision(for: controlS, controller: controller, windowModel: windowModel)
                == .perform(.board(.copySheetScreenshot)))
    }

    @Test func denModeYCopiesFocusedBoardLocationAndShiftYCopiesBoardID() throws {
        // Arrange
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let locationEvent = try keyEvent(
            characters: "y",
            charactersIgnoringModifiers: "y",
            keyCode: 16)
        let boardIDEvent = try keyEvent(
            characters: "Y",
            charactersIgnoringModifiers: "y",
            modifiers: [.shift],
            keyCode: 16)

        // Act
        let locationDecision = KeyboardController.decision(
            for: locationEvent, controller: controller, windowModel: windowModel)
        let boardIDDecision = KeyboardController.decision(
            for: boardIDEvent, controller: controller, windowModel: windowModel)

        // Assert
        #expect(
            locationDecision == .perform(.board(.copyLocation)))
        #expect(
            boardIDDecision == .perform(.board(.copyID)))
    }

    @Test func sheetInputCommandOptionDigitFocusesDeskAndLeavesCommandZeroAvailable() throws {
        let movedBoard = board("Moved")
        let firstDesk = DeskState(label: "First", boards: [], focusedBoardID: nil)
        let secondDesk = DeskState(
            label: "Second",
            boards: [movedBoard],
            focusedBoardID: movedBoard.id)
        let controller = try makeController(desks: [firstDesk, secondDesk])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.focusDesk(secondDesk.id)
        let preferences = controller.preferences
        let commandOptionOne = try keyEvent(
            characters: "1",
            charactersIgnoringModifiers: "1",
            modifiers: [.command, .option],
            keyCode: 18)
        let commandZero = try keyEvent(
            characters: "0",
            charactersIgnoringModifiers: "0",
            modifiers: [.command],
            keyCode: 29)

        #expect(
            KeyboardController.handle(
                commandOptionOne, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(controller.state.focusedDeskID == firstDesk.id)
        #expect(!windowModel.isDenMode)
        #expect(
            !KeyboardController.handle(
                commandZero, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(controller.state.focusedDeskID == firstDesk.id)
    }

    @Test func contentSizeShortcutsRouteToTheFocusedBoardInEveryInputMode() throws {
        let controller = try makeController(boards: [board("Focused")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let increase = try keyEvent(
            characters: "=",
            charactersIgnoringModifiers: "=",
            modifiers: [.command],
            keyCode: 24)
        let plus = try keyEvent(
            characters: "+",
            charactersIgnoringModifiers: "=",
            modifiers: [.command, .shift],
            keyCode: 24)
        let decrease = try keyEvent(
            characters: "-",
            charactersIgnoringModifiers: "-",
            modifiers: [.command],
            keyCode: 27)
        let reset = try keyEvent(
            characters: "0",
            charactersIgnoringModifiers: "0",
            modifiers: [.command],
            keyCode: 29)

        #expect(
            KeyboardController.decision(for: increase, controller: controller, windowModel: windowModel)
                == .perform(.board(.increaseSheetSize)))
        #expect(
            KeyboardController.decision(for: plus, controller: controller, windowModel: windowModel)
                == .perform(.board(.increaseSheetSize)))
        #expect(
            KeyboardController.decision(for: decrease, controller: controller, windowModel: windowModel)
                == .perform(.board(.decreaseSheetSize)))
        #expect(
            KeyboardController.decision(for: reset, controller: controller, windowModel: windowModel)
                == .perform(.board(.resetSheetSize)))

        windowModel.isDenMode = true
        #expect(
            KeyboardController.decision(for: decrease, controller: controller, windowModel: windowModel)
                == .perform(.board(.decreaseSheetSize)))
    }

    @Test(arguments: [false, true])
    func commandDCreatesTerminalSideBoardInEveryInputMode(_ isDenMode: Bool) throws {
        // Arrange
        let primary = BoardState(label: "Terminal", width: 520, workingDirectory: "/work")
        let controller = try makeController(boards: [primary])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = isDenMode
        let commandD = try keyEvent(
            characters: "d", charactersIgnoringModifiers: "d", modifiers: [.command], keyCode: 2)

        // Act
        let handled = KeyboardController.handle(commandD, controller: controller, windowModel: windowModel)

        // Assert
        let sideBoard = try #require(controller.focusedBoard)
        #expect(handled)
        #expect(controller.state.desks[0].boards.count == 2)
        #expect(sideBoard.id != primary.id)
        #expect(sideBoard.label == "Terminal Side Board")
        #expect(sideBoard.isTerminal)
        #expect(sideBoard.isSideBoard)
        #expect(sideBoard.sideBoardTargetBoardID == primary.id)
        #expect(sideBoard.terminalWorkingDirectory == "/work")
        #expect(controller.createTerminalSideBoard(targetBoardID: sideBoard.id) == sideBoard.id)
        #expect(controller.state.desks[0].boards.count == 2)
    }

    @Test func commandDIsDisabledForWebBoards() throws {
        // Arrange
        let webBoard = board("Web")
        let controller = try makeController(boards: [webBoard])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let commandD = try keyEvent(
            characters: "d", charactersIgnoringModifiers: "d", modifiers: [.command], keyCode: 2)

        // Act
        let decision = KeyboardController.decision(for: commandD, controller: controller, windowModel: windowModel)
        let handled = KeyboardController.handle(commandD, controller: controller, windowModel: windowModel)

        // Assert
        #expect(decision == .forward(.sheet))
        #expect(!handled)
        #expect(controller.state.desks[0].boards == [webBoard])
    }

    @Test func controlTabDeskShortcutsNavigateAndReturn() throws {
        let firstDesk = DeskState(label: "First", boards: [])
        let secondDesk = DeskState(label: "Second", boards: [])
        let thirdDesk = DeskState(label: "Third", boards: [])
        let controller = try makeController(desks: [firstDesk, secondDesk, thirdDesk])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let preferences = controller.preferences

        let next = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.control],
            keyCode: 48)
        #expect(
            KeyboardController.handle(next, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(controller.focusedDesk?.id == secondDesk.id)

        let previous = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.control, .shift],
            keyCode: 48)
        #expect(
            KeyboardController.handle(
                previous, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(controller.focusedDesk?.id == firstDesk.id)

        let returnToPrevious = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.command, .option],
            keyCode: 48)
        #expect(
            KeyboardController.handle(
                returnToPrevious,
                controller: controller, windowModel: windowModel,
                preferences: preferences))
        #expect(controller.focusedDesk?.id == secondDesk.id)
    }

    @Test func denModeIOpensNotifications() throws {
        let controller = try makeController(boards: [board("Terminal")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let open = try keyEvent(
            characters: "i",
            charactersIgnoringModifiers: "i",
            keyCode: 34)

        #expect(KeyboardController.handle(open, controller: controller, windowModel: windowModel))
        #expect(windowModel.isNotificationListPresented)
        #expect(windowModel.isDenMode)
    }

    @Test func denModeVOpensBoardFromClipboard() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        controller.pasteboard.clearContents()
        controller.pasteboard.setString("https://example.com/test", forType: .string)

        let vKey = try keyEvent(
            characters: "v",
            charactersIgnoringModifiers: "v",
            keyCode: 9)

        #expect(KeyboardController.handle(vKey, controller: controller, windowModel: windowModel))
        #expect(controller.focusedDesk?.boards.count == 2)
        #expect(controller.focusedBoard?.currentSheetURL == URL(string: "https://example.com/test"))
        #expect(!windowModel.isDenMode)
    }

    @Test func denModeBKeyOpensSaveEssentialPanelForFocusedBoard() throws {
        let board = BoardState(
            label: "Niri",
            width: 520,
            currentSheetURL: URL(string: "https://github.com/YaLTeR/niri")
        )
        let desk = DeskState(label: "Dev", boards: [board], focusedBoardID: board.id)
        let controller = DenController(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        let bKey = try keyEvent(
            characters: "b",
            charactersIgnoringModifiers: "b",
            keyCode: 11
        )

        #expect(KeyboardController.handle(bKey, controller: controller, windowModel: windowModel))
        #expect(windowModel.isSaveEssentialPanelPresented)
        #expect(windowModel.saveEssentialDraft?.name == "Niri")
        #expect(windowModel.saveEssentialDraft?.input == "https://github.com/YaLTeR/niri")
    }

    @Test func denModeMKeyTogglesAnchorBoardAndShiftMJumps() throws {
        let first = board("First")
        let second = board("Second")
        let controller = try makeController(boards: [first, second])
        let composition = DenWindowComposition(controller: controller)
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
        #expect(KeyboardController.handle(mKey, controller: controller, windowModel: windowModel))
        #expect(controller.focusedDesk?.anchorBoardID == first.id)
        #expect(controller.latestFeedback?.message == "Set Anchor Board")

        // Move to second board.
        controller.focusBoard(second.id)
        #expect(controller.focusedBoard?.id == second.id)

        // Press 'Shift + m' to jump to anchor first board.
        #expect(KeyboardController.handle(shiftMKey, controller: controller, windowModel: windowModel))
        #expect(controller.focusedBoard?.id == first.id)

        // Press 'Shift + m' again to return to second board (A <-> B toggle).
        #expect(KeyboardController.handle(shiftMKey, controller: controller, windowModel: windowModel))
        #expect(controller.focusedBoard?.id == second.id)

        // Press 'm' on second board to move anchor.
        #expect(KeyboardController.handle(mKey, controller: controller, windowModel: windowModel))
        #expect(controller.focusedDesk?.anchorBoardID == second.id)

        // Press 'm' again on second board to clear anchor.
        #expect(KeyboardController.handle(mKey, controller: controller, windowModel: windowModel))
        #expect(controller.focusedDesk?.anchorBoardID == nil)
        #expect(controller.latestFeedback?.message == "Cleared Anchor Board")

        // Press 'Shift + m' with no anchor shows warning.
        #expect(KeyboardController.handle(shiftMKey, controller: controller, windowModel: windowModel))
        #expect(controller.latestFeedback?.message == "No Anchor Board in Desk")
        #expect(controller.latestFeedback?.severity == .warning)
    }

    @Test func notificationArrowsMoveSelectionAndReturnOpensIt() throws {
        let first = board("First")
        let second = board("Second")
        let controller = try makeController(boards: [first, second])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.recordNotification(title: "First", body: "Done", boardID: first.id)
        controller.recordNotification(title: "Second", body: "Done", boardID: second.id)
        windowModel.isDenMode = true
        let preferences = try makePreferences()

        let open = try keyEvent(
            characters: "i",
            charactersIgnoringModifiers: "i",
            keyCode: 34)
        let down = try keyEvent(
            characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}",
            keyCode: 125)
        let enter = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36)

        #expect(
            KeyboardController.handle(open, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(windowModel.notificationList.selectedNotificationID == controller.notifications[0].id)
        #expect(
            KeyboardController.handle(down, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(windowModel.notificationList.selectedNotificationID == controller.notifications[1].id)
        #expect(
            KeyboardController.handle(enter, controller: controller, windowModel: windowModel, preferences: preferences)
        )
        #expect(controller.focusedBoard?.id == first.id)
        #expect(!windowModel.isNotificationListPresented)
    }

    @Test func customBindingsApplyImmediatelyAndCanBeUnassigned() throws {
        let preferences = try makePreferences()
        let controller = try makeController(boards: [board("First"), board("Second")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let toggle = try keyEvent(
            characters: ".", charactersIgnoringModifiers: ".", modifiers: [.control], keyCode: 47)
        let defaultToggle = try keyEvent(
            characters: ",", charactersIgnoringModifiers: ",", modifiers: [.control], keyCode: 43)
        #expect(
            preferences.setShortcut(
                ShortcutBinding(key: .character("."), modifiers: [.control]),
                for: .toggleDenMode) == nil)

        #expect(
            !KeyboardController.handle(
                defaultToggle, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(
            KeyboardController.handle(
                toggle, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(windowModel.isDenMode)

        windowModel.exitDenMode()
        preferences.clearShortcut(for: .focusNextBoard)
        let right = try arrowEvent(.rightArrow, modifiers: [.command, .option])
        #expect(
            !KeyboardController.handle(
                right, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(controller.focusedDesk?.focusedBoardID == controller.focusedDesk?.boards.first?.id)
    }

    @Test func customBindingsAreSuspendedByTemporaryContexts() throws {
        let preferences = try makePreferences()
        let controller = try makeController(boards: [board("First"), board("Second")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let next = try arrowEvent(.rightArrow, modifiers: [.command, .option])

        windowModel.showNewDeskPanel()
        #expect(
            !KeyboardController.handle(next, controller: controller, windowModel: windowModel, preferences: preferences)
        )
        windowModel.hideNewDeskPanel()

        windowModel.showOverview()
        let focusedBoardID = controller.focusedDesk?.focusedBoardID
        #expect(
            KeyboardController.handle(next, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(controller.focusedDesk?.focusedBoardID == focusedBoardID)
    }

    @Test func shiftEscapeTogglesBoardActivityAcrossInputContexts() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let shiftEscape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            modifiers: [.shift],
            keyCode: 53)

        #expect(KeyboardController.handle(shiftEscape, controller: controller, windowModel: windowModel))
        #expect(windowModel.isBoardActivityPresented)

        #expect(KeyboardController.handle(shiftEscape, controller: controller, windowModel: windowModel))
        #expect(!windowModel.isBoardActivityPresented)

        windowModel.isDenMode = true
        #expect(KeyboardController.handle(shiftEscape, controller: controller, windowModel: windowModel))
        #expect(windowModel.isBoardActivityPresented)

        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53)
        #expect(KeyboardController.handle(escape, controller: controller, windowModel: windowModel))
        #expect(!windowModel.isBoardActivityPresented)
    }

    @Test func denModeToggleRemainsAvailableInDrawer() throws {
        let preferences = try makePreferences()
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.keepInDrawer(try #require(URL(string: "https://example.com/")))
        let peekID = windowModel.drawer.expandedItemID
        let toggle = try keyEvent(
            characters: ",", charactersIgnoringModifiers: ",", modifiers: [.control], keyCode: 43)

        #expect(
            KeyboardController.handle(
                toggle, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(windowModel.isDenMode)
        #expect(windowModel.drawer.expandedItemID == peekID)

        #expect(
            KeyboardController.handle(
                toggle, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(!windowModel.isDenMode)
        #expect(windowModel.drawer.expandedItemID == peekID)
    }

    @Test func drawerCommandWDiscardsSelectedItemWithoutRemovingBoard() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.keepInDrawer(try #require(URL(string: "https://first.example/")))
        controller.keepInDrawer(try #require(URL(string: "https://second.example/")))
        let selectedItemID = try #require(windowModel.drawer.selectedItemID)
        let commandW = try keyEvent(
            characters: "w",
            charactersIgnoringModifiers: "w",
            modifiers: [.command],
            keyCode: 13)

        #expect(
            KeyboardController.decision(for: commandW, controller: controller, windowModel: windowModel)
                == .perform(.drawer(.discardSelectedItem(focusNext: true))))
        #expect(KeyboardController.handle(commandW, controller: controller, windowModel: windowModel))
        #expect(controller.state.drawerItems.count == 1)
        #expect(!controller.state.drawerItems.contains { $0.id == selectedItemID })
        #expect(controller.focusedDesk?.boards.count == 1)
        #expect(windowModel.isDrawerOpen)

        let repeatedCommandW = try keyEvent(
            characters: "w",
            charactersIgnoringModifiers: "w",
            modifiers: [.command],
            isARepeat: true,
            keyCode: 13)
        #expect(
            KeyboardController.decision(for: repeatedCommandW, controller: controller, windowModel: windowModel)
                == .consume(.ignoredRepeat))
        #expect(KeyboardController.handle(repeatedCommandW, controller: controller, windowModel: windowModel))
        #expect(controller.state.drawerItems.count == 1)
    }

    @Test func drawerControlEscapeClosesDrawerWithOrWithoutPeek() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.keepInDrawer(try #require(URL(string: "https://preview.example/")))
        let itemID = try #require(windowModel.drawer.expandedItemID)
        let controlEscape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            modifiers: [.control],
            keyCode: 53)

        #expect(
            KeyboardController.decision(for: controlEscape, controller: controller, windowModel: windowModel)
                == .perform(.drawer(.close)))
        #expect(KeyboardController.handle(controlEscape, controller: controller, windowModel: windowModel))
        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == itemID)

        windowModel.openDrawer()
        windowModel.drawer.toggleItem(itemID)
        windowModel.isDenMode = true

        #expect(KeyboardController.handle(controlEscape, controller: controller, windowModel: windowModel))
        #expect(!windowModel.isDrawerOpen)
        #expect(controller.state.drawerItems.count == 1)
    }

    @Test func drawerConsumesUnmappedKeysWhenPeekIsNotFocused() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.keepInDrawer(try #require(URL(string: "https://example.com/")))
        let itemID = try #require(windowModel.drawer.selectedItemID)
        windowModel.drawer.toggleItem(itemID)
        #expect(!windowModel.isDenMode)
        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == nil)

        let letterA = try keyEvent(
            characters: "a", charactersIgnoringModifiers: "a", keyCode: 0)
        let space = try keyEvent(
            characters: " ", charactersIgnoringModifiers: " ", keyCode: 49)
        let tab = try keyEvent(
            characters: "\t", charactersIgnoringModifiers: "\t", keyCode: 48)

        #expect(
            KeyboardController.decision(for: letterA, controller: controller, windowModel: windowModel)
                == .consume(.exclusiveContext))
        #expect(KeyboardController.handle(letterA, controller: controller, windowModel: windowModel))

        #expect(
            KeyboardController.decision(for: space, controller: controller, windowModel: windowModel)
                == .consume(.exclusiveContext))
        #expect(KeyboardController.handle(space, controller: controller, windowModel: windowModel))

        #expect(
            KeyboardController.decision(for: tab, controller: controller, windowModel: windowModel)
                == .consume(.exclusiveContext))
        #expect(KeyboardController.handle(tab, controller: controller, windowModel: windowModel))

        #expect(windowModel.isDrawerOpen)
        #expect(controller.state.drawerItems.count == 1)
        #expect(controller.focusedDesk?.boards.count == 1)
    }

    @Test func denModeShiftDRequestsDrawerClearConfirmation() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.keepInDrawer(try #require(URL(string: "https://first.example/")))
        controller.keepInDrawer(try #require(URL(string: "https://second.example/")))
        windowModel.isDenMode = true

        let clear = try keyEvent(
            characters: "D",
            charactersIgnoringModifiers: "d",
            modifiers: [.shift],
            keyCode: 2)

        #expect(KeyboardController.handle(clear, controller: controller, windowModel: windowModel))
        #expect(windowModel.drawerPendingDeletionCount == 2)
        #expect(controller.state.drawerItems.count == 2)
    }

    @Test func drawerFKeyTogglesPresentationStyle() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.keepInDrawer(try #require(URL(string: "https://example.com/")))
        windowModel.openDrawer()
        windowModel.isDenMode = true

        #expect(controller.preferences.drawerStyle == .floating)

        let fKey = try keyEvent(
            characters: "f",
            charactersIgnoringModifiers: "f",
            keyCode: 3
        )
        #expect(KeyboardController.handle(fKey, controller: controller, windowModel: windowModel))
        #expect(controller.preferences.drawerStyle == .bottom)

        #expect(KeyboardController.handle(fKey, controller: controller, windowModel: windowModel))
        #expect(controller.preferences.drawerStyle == .floating)
    }

    @Test func denModeShiftDDoesNothingInDrawerFilterModeOrOnRepeat() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.keepInDrawer(try #require(URL(string: "https://example.com/")))
        windowModel.isDenMode = true

        let clear = try keyEvent(
            characters: "D",
            charactersIgnoringModifiers: "d",
            modifiers: [.shift],
            keyCode: 2)
        windowModel.drawer.enterFilterMode()
        #expect(!KeyboardController.handle(clear, controller: controller, windowModel: windowModel))
        #expect(!windowModel.hasPendingConfirmation)

        windowModel.drawer.exitFilterMode()
        let repeatClear = try keyEvent(
            characters: "D",
            charactersIgnoringModifiers: "d",
            modifiers: [.shift],
            isARepeat: true,
            keyCode: 2)
        #expect(KeyboardController.handle(repeatClear, controller: controller, windowModel: windowModel))
        #expect(!windowModel.hasPendingConfirmation)
    }

    @Test func denModeEnterAndShiftEnterUseDistinctDuplicateActions() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let returnKey = try keyEvent(
            characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(
            KeyboardController.decision(for: returnKey, controller: controller, windowModel: windowModel)
                == .perform(.board(.duplicate)))
        #expect(
            KeyboardController.decision(for: shiftReturn, controller: controller, windowModel: windowModel)
                == .perform(.board(.duplicateFirstSheet)))
    }

    @Test func denModeShiftEnterDuplicatesTerminalInItsWorkingDirectory() throws {
        let source = BoardState(
            label: "Terminal",
            width: 520,
            workingDirectory: "/tmp/project",
            customLabel: "Build")
        let controller = try makeController(boards: [source])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(KeyboardController.handle(shiftReturn, controller: controller, windowModel: windowModel))
        #expect(controller.focusedDesk?.boards.count == 2)
        #expect(controller.focusedBoard?.id != source.id)
        #expect(controller.focusedBoard?.isTerminal == true)
        #expect(controller.focusedBoard?.terminalWorkingDirectory == "/tmp/project")
        #expect(controller.focusedBoard?.label == "Terminal")
        #expect(controller.focusedBoard?.width == 520)
        #expect(controller.focusedBoard?.customLabel == "Build")
    }

    @Test func denModeShiftEnterDuplicatesZellijSession() throws {
        let source = BoardState(
            label: "Zellij",
            width: 520,
            zellijSessionName: "dev",
            customLabel: "Build")
        let controller = try makeController(boards: [source])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(KeyboardController.handle(shiftReturn, controller: controller, windowModel: windowModel))
        #expect(controller.focusedDesk?.boards.count == 2)
        let duplicate = try #require(controller.focusedBoard)
        #expect(duplicate.id != source.id)
        #expect(duplicate.isZellij)
        #expect(duplicate.zellijSessionName == "dev")
        #expect(duplicate.label == "Zellij")
        #expect(duplicate.width == 520)
        #expect(duplicate.customLabel == "Build")
    }

    @Test func openProfilePanelForwardsKeyboardNavigationToItsTextField() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
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
            characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)

        #expect(
            KeyboardController.decision(for: down, controller: controller, windowModel: windowModel)
                == .forward(.temporaryTextInput))
        #expect(
            KeyboardController.decision(for: returnKey, controller: controller, windowModel: windowModel)
                == .forward(.temporaryTextInput))
        #expect(
            KeyboardController.decision(for: escape, controller: controller, windowModel: windowModel)
                == .forward(.temporaryTextInput))
    }

    @Test func textInputPanelConsumesTabTraversal() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        windowModel.showOpenBoardPanel()
        let tab = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            keyCode: 48)
        let shiftTab = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.shift],
            keyCode: 48)

        #expect(windowModel.temporaryContext == .openBoard)
        #expect(
            KeyboardController.decision(for: tab, controller: controller, windowModel: windowModel)
                == .consume(.exclusiveContext))
        #expect(
            KeyboardController.decision(for: shiftTab, controller: controller, windowModel: windowModel)
                == .consume(.exclusiveContext))
    }

    @Test func drawerFilterPassesShiftedCharactersToTextInput() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.keepInDrawer(try #require(URL(string: "https://example.com/")))
        windowModel.isDenMode = true
        windowModel.drawer.enterFilterMode()

        let uppercase = try keyEvent(
            characters: "A",
            charactersIgnoringModifiers: "a",
            modifiers: [.shift],
            keyCode: 0)

        #expect(!KeyboardController.handle(uppercase, controller: controller, windowModel: windowModel))
        #expect(windowModel.drawer.isFilterInputActive)
    }

    @Test func drawerFilterPassesModifiedReturnAndControlEscapeClosesDrawer() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.keepInDrawer(try #require(URL(string: "https://example.com/")))
        windowModel.isDenMode = true
        windowModel.drawer.enterFilterMode()

        let modifiedReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)
        let controlEscape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            modifiers: [.control],
            keyCode: 53)

        #expect(!KeyboardController.handle(modifiedReturn, controller: controller, windowModel: windowModel))
        #expect(
            KeyboardController.decision(for: controlEscape, controller: controller, windowModel: windowModel)
                == .perform(.drawer(.close)))
        #expect(KeyboardController.handle(controlEscape, controller: controller, windowModel: windowModel))
        #expect(!windowModel.isDrawerOpen)
    }

    @Test func overviewFilterUsesTwoPhaseSelection() throws {
        let first = board("First")
        let second = board("Second")
        let controller = try makeController(boards: [first, second])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()

        let slash = try keyEvent(
            characters: "/",
            charactersIgnoringModifiers: "/",
            keyCode: 44)
        let returnKey = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36)

        #expect(KeyboardController.handle(slash, controller: controller, windowModel: windowModel))
        #expect(windowModel.overview.filterPhase == .filtering)
        windowModel.overview.setQuery("Second")
        #expect(windowModel.overview.selectionBoardID == second.id)

        #expect(KeyboardController.handle(returnKey, controller: controller, windowModel: windowModel))
        #expect(windowModel.overview.filterPhase == .selecting)
        #expect(windowModel.isOverviewPresented)

        #expect(KeyboardController.handle(returnKey, controller: controller, windowModel: windowModel))
        #expect(windowModel.overview.filterPhase == .inactive)
        #expect(!windowModel.isOverviewPresented)
        #expect(controller.focusedBoard?.id == second.id)
    }

    @Test func overviewEscapeRequestsBoardDragCancellation() throws {
        let first = board("First")
        let controller = try makeController(boards: [first])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()
        #expect(windowModel.beginOverviewBoardDrag(first.id))

        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53)

        #expect(
            KeyboardController.decision(for: escape, controller: controller, windowModel: windowModel)
                == .perform(.board(.requestDragCancellation)))
        #expect(KeyboardController.handle(escape, controller: controller, windowModel: windowModel))
        #expect(windowModel.boardDragCancellationRequest == 1)
        #expect(windowModel.isOverviewPresented)
    }

    @Test func denModeRemoveShortcutsChooseTheirFocusDirection() throws {
        let dBoards = [board("First"), board("Focused"), board("Last")]
        let dController = try makeController(boards: dBoards)
        let dComposition = DenWindowComposition(controller: dController)
        let dWindowModel = dComposition.model
        dComposition.connect()
        defer { dComposition.disconnect() }
        dController.focusBoard(dBoards[1].id)
        dWindowModel.isDenMode = true
        let dEvent = try keyEvent(characters: "d", charactersIgnoringModifiers: "d", keyCode: 2)

        #expect(
            KeyboardController.decision(for: dEvent, controller: dController, windowModel: dWindowModel)
                == .perform(.board(.removeAndFocusNext)))
        #expect(KeyboardController.handle(dEvent, controller: dController, windowModel: dWindowModel))
        #expect(dController.focusedDesk?.boards.map(\.id) == [dBoards[0].id, dBoards[2].id])
        #expect(dController.focusedDesk?.focusedBoardID == dBoards[2].id)

        let xBoards = [board("First"), board("Focused"), board("Last")]
        let xController = try makeController(boards: xBoards)
        let xComposition = DenWindowComposition(controller: xController)
        let xWindowModel = xComposition.model
        xComposition.connect()
        defer { xComposition.disconnect() }
        xController.focusBoard(xBoards[1].id)
        xWindowModel.isDenMode = true
        let xEvent = try keyEvent(characters: "x", charactersIgnoringModifiers: "x", keyCode: 7)

        #expect(
            KeyboardController.decision(for: xEvent, controller: xController, windowModel: xWindowModel)
                == .perform(.board(.remove)))
        #expect(KeyboardController.handle(xEvent, controller: xController, windowModel: xWindowModel))
        #expect(xController.focusedDesk?.boards.map(\.id) == [xBoards[0].id, xBoards[2].id])
        #expect(xController.focusedDesk?.focusedBoardID == xBoards[0].id)
    }

    @Test func nativeCommandShortcutsPassThroughWithoutExecuting() throws {
        let first = board("First")
        let second = board("Second")
        let controller = try makeController(boards: [first, second])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let commands = [
            try keyEvent(
                characters: "w", charactersIgnoringModifiers: "w", modifiers: [.command], keyCode: 13),
            try keyEvent(
                characters: "t", charactersIgnoringModifiers: "t", modifiers: [.command], keyCode: 17),
            try keyEvent(
                characters: "l", charactersIgnoringModifiers: "l", modifiers: [.command], keyCode: 37),
            try keyEvent(
                characters: "r", charactersIgnoringModifiers: "r", modifiers: [.command], keyCode: 15),
        ]
        let closeWindow = try keyEvent(
            characters: "W",
            charactersIgnoringModifiers: "w",
            modifiers: [.command, .shift],
            keyCode: 13)

        for command in commands {
            #expect(!KeyboardController.handle(command, controller: controller, windowModel: windowModel))
        }
        #expect(!KeyboardController.handle(closeWindow, controller: controller, windowModel: windowModel))
        #expect(controller.focusedDesk?.boards.map(\.id) == [first.id, second.id])
        #expect(windowModel.temporaryContext == nil)
    }

    @Test func denModeCommaPerformsSettingsWithoutForwarding() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let comma = try keyEvent(
            characters: ",", charactersIgnoringModifiers: ",", modifiers: [], keyCode: 43)

        #expect(!KeyboardController.handle(comma, controller: controller, windowModel: windowModel))

        windowModel.isDenMode = true
        #expect(
            KeyboardController.decision(for: comma, controller: controller, windowModel: windowModel)
                == .perform(.application(.openSettings)))
        var didOpenSettings = false
        let handled = KeyboardController.handle(
            comma,
            controller: controller, windowModel: windowModel,
            openSettings: { didOpenSettings = true })
        #expect(handled)
        #expect(didOpenSettings)

        windowModel.showOverview()
        #expect(KeyboardController.handle(comma, controller: controller, windowModel: windowModel))
        #expect(
            KeyboardController.decision(for: comma, controller: controller, windowModel: windowModel)
                == .consume(.exclusiveContext))
    }

    @Test func denModeGPrefixLaunchesMatchingEssential() throws {
        let controller = try makeController(boards: [BoardState(label: "First", width: 720, currentSheetURL: nil)])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let essential = Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
        #expect(controller.preferences.setEssentials([essential]))
        windowModel.isDenMode = true

        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let key = try keyEvent(
            characters: "c", charactersIgnoringModifiers: "c", keyCode: 8)

        #expect(
            KeyboardController.decision(for: prefix, controller: controller, windowModel: windowModel)
                == .perform(.essentials(.enterPrefix)))
        #expect(KeyboardController.handle(prefix, controller: controller, windowModel: windowModel))
        #expect(windowModel.temporaryContext == .essentialsPrefix)
        #expect(
            KeyboardController.decision(for: key, controller: controller, windowModel: windowModel)
                == .perform(.essentials(.launch(essential.id))))
        #expect(KeyboardController.handle(key, controller: controller, windowModel: windowModel))
        #expect(windowModel.temporaryContext == nil)
        #expect(!windowModel.isDenMode)
        #expect(controller.focusedBoard?.currentSheetURL == URL(string: "https://chatgpt.com/"))
        #expect(controller.focusedBoard?.width == 720)
    }

    @Test func sheetInputEssentialsPrefixLaunchesWithoutEnteringDenMode() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let essential = Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
        #expect(controller.preferences.setEssentials([essential]))
        windowModel.showEssentialsPrefix()

        let key = try keyEvent(
            characters: "c", charactersIgnoringModifiers: "c", keyCode: 8)

        #expect(
            KeyboardController.decision(for: key, controller: controller, windowModel: windowModel)
                == .perform(.essentials(.launch(essential.id))))
        #expect(KeyboardController.handle(key, controller: controller, windowModel: windowModel))
        #expect(windowModel.temporaryContext == nil)
        #expect(!windowModel.isDenMode)
        #expect(controller.focusedBoard?.currentSheetURL == URL(string: "https://chatgpt.com/"))
    }

    @Test func essentialsPrefixSelectionWrapsBetweenFirstAndLast() throws {
        // Arrange
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let first = Essential(name: "First Essential", key: "a", input: "https://first.example")
        let second = Essential(name: "Second Essential", key: "b", input: "https://second.example")
        #expect(controller.preferences.setEssentials([first, second]))

        // Act
        windowModel.showEssentialsPrefix()
        windowModel.moveEssentialSelection(by: -1)

        // Assert
        #expect(windowModel.selectedEssentialID == second.id)

        // Act
        windowModel.moveEssentialSelection(by: 1)

        // Assert
        #expect(windowModel.selectedEssentialID == first.id)
    }

    @Test func essentialsPrefixOpeningResetsSelectionToFirst() throws {
        // Arrange
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let first = Essential(name: "First Essential", key: "a", input: "https://first.example")
        let second = Essential(name: "Second Essential", key: "b", input: "https://second.example")
        #expect(controller.preferences.setEssentials([first, second]))
        windowModel.showEssentialsPrefix()

        // Act
        windowModel.moveEssentialSelection(by: 1)
        windowModel.exitEssentialsPrefix()
        windowModel.showEssentialsPrefix()

        // Assert
        #expect(windowModel.selectedEssentialID == first.id)
    }

    @Test func essentialsPrefixReturnLaunchesFocusedEssentialAndClosesPrefix() throws {
        // Arrange
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let first = Essential(name: "First Essential", key: "a", input: "https://first.example")
        let second = Essential(name: "Second Essential", key: "b", input: "https://second.example")
        #expect(controller.preferences.setEssentials([first, second]))
        windowModel.showEssentialsPrefix()

        // Act
        windowModel.moveEssentialSelection(by: 1)
        windowModel.launchSelectedEssential()

        // Assert
        #expect(windowModel.temporaryContext == nil)
        #expect(windowModel.selectedEssentialID == nil)
        #expect(controller.focusedBoard?.currentSheetURL == URL(string: "https://second.example/"))
    }

    @Test func essentialsPrefixRoutesArrowsReturnAndConfiguredJkKeys() throws {
        // Arrange
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let jEssential = Essential(name: "J Essential", key: "j", input: "https://j.example")
        let kEssential = Essential(name: "K Essential", key: "k", input: "https://k.example")
        #expect(controller.preferences.setEssentials([jEssential, kEssential]))
        windowModel.showEssentialsPrefix()
        let upArrow = try arrowEvent(.upArrow, modifiers: [])
        let down = try arrowEvent(.downArrow, modifiers: [])
        let returnKey = try keyEvent(
            characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let jKey = try keyEvent(characters: "j", charactersIgnoringModifiers: "j", keyCode: 38)
        let kKey = try keyEvent(characters: "k", charactersIgnoringModifiers: "k", keyCode: 40)

        // Act
        func route(_ event: NSEvent) -> InputDecision {
            KeyboardRouter.route(
                event: KeyEvent(event),
                context: InputContext(controller: controller, windowModel: windowModel, event: event),
                shortcuts: ShortcutConfiguration(preferences: controller.preferences))
        }
        let upDecision = route(upArrow)
        let downDecision = route(down)
        let returnDecision = route(returnKey)
        let jDecision = route(jKey)
        let kDecision = route(kKey)

        // Assert
        #expect(upDecision == .perform(.essentials(.moveSelection(-1))))
        #expect(downDecision == .perform(.essentials(.moveSelection(1))))
        #expect(returnDecision == .perform(.essentials(.launchSelected)))
        #expect(jDecision == .perform(.essentials(.launch(jEssential.id))))
        #expect(kDecision == .perform(.essentials(.launch(kEssential.id))))
    }

    @Test func essentialsPrefixAllowsRepeatedArrowMovementButSuppressesRepeatedLaunch() throws {
        // Arrange
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let essential = Essential(name: "Essential", key: "a", input: "https://essential.example")
        let nextEssential = Essential(name: "Next", key: "b", input: "https://next.example")
        #expect(controller.preferences.setEssentials([essential, nextEssential]))
        windowModel.showEssentialsPrefix()
        let repeatedUp = try arrowEvent(.upArrow, modifiers: [], isARepeat: true)
        let repeatedDown = try arrowEvent(.downArrow, modifiers: [], isARepeat: true)
        let repeatedReturn = try keyEvent(
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: true, keyCode: 36)
        let repeatedKey = try keyEvent(
            characters: "a", charactersIgnoringModifiers: "a", isARepeat: true, keyCode: 0)
        let repeatedEscape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: true, keyCode: 53)
        func route(_ event: NSEvent) -> InputDecision {
            KeyboardRouter.route(
                event: KeyEvent(event),
                context: InputContext(controller: controller, windowModel: windowModel, event: event),
                shortcuts: ShortcutConfiguration(preferences: controller.preferences))
        }

        // Act
        let upDecision = route(repeatedUp)
        let movementDecision = route(repeatedDown)
        let returnDecision = route(repeatedReturn)
        let keyDecision = route(repeatedKey)
        let escapeDecision = route(repeatedEscape)
        #expect(KeyboardController.handle(repeatedDown, controller: controller, windowModel: windowModel))
        #expect(KeyboardController.handle(repeatedReturn, controller: controller, windowModel: windowModel))
        #expect(KeyboardController.handle(repeatedKey, controller: controller, windowModel: windowModel))

        // Assert
        #expect(upDecision == .perform(.essentials(.moveSelection(-1))))
        #expect(movementDecision == .perform(.essentials(.moveSelection(1))))
        #expect(windowModel.selectedEssentialID == nextEssential.id)
        #expect(returnDecision == .consume(.ignoredRepeat))
        #expect(keyDecision == .consume(.ignoredRepeat))
        #expect(escapeDecision == .consume(.ignoredRepeat))
        #expect(controller.focusedDesk?.boards.count == 1)
    }

    @Test func denModeGPrefixShowsFeedbackForUnregisteredKeys() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let essential = Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
        #expect(controller.preferences.setEssentials([essential]))
        windowModel.isDenMode = true
        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let unknown = try keyEvent(
            characters: "x", charactersIgnoringModifiers: "x", keyCode: 7)

        #expect(KeyboardController.handle(prefix, controller: controller, windowModel: windowModel))
        #expect(
            KeyboardController.decision(for: unknown, controller: controller, windowModel: windowModel)
                == .perform(.essentials(.showNotFound("x"))))
        #expect(KeyboardController.handle(unknown, controller: controller, windowModel: windowModel))
        #expect(windowModel.temporaryContext == nil)
        #expect(windowModel.isDenMode)
        #expect(controller.focusedDesk?.boards.count == 1)
        #expect(controller.latestFeedback?.message == "No Essential assigned to 'x'.")
        #expect(controller.latestFeedback?.severity == .warning)
    }

    @Test func denModeGPrefixCancelsQuietlyForEscapeAndModifiedKeys() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        #expect(
            controller.preferences.setEssentials([
                Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
            ]))
        windowModel.isDenMode = true
        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)
        let modified = try keyEvent(
            characters: "x", charactersIgnoringModifiers: "x", modifiers: [.command], keyCode: 7)

        #expect(KeyboardController.handle(prefix, controller: controller, windowModel: windowModel))
        #expect(KeyboardController.handle(escape, controller: controller, windowModel: windowModel))
        #expect(windowModel.temporaryContext == nil)
        #expect(windowModel.isDenMode)

        #expect(KeyboardController.handle(prefix, controller: controller, windowModel: windowModel))
        #expect(KeyboardController.handle(modified, controller: controller, windowModel: windowModel))
        #expect(windowModel.temporaryContext == nil)
        #expect(windowModel.isDenMode)
        #expect(controller.latestFeedback == nil)
    }

    @Test func zmxSessionsEscapeClosesPanel() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.preferences.setZmxPath("/missing/zmx")
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)

        windowModel.showZmxSessions()

        #expect(windowModel.isZmxSessionsPresented)
        #expect(
            KeyboardController.decision(for: escape, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.hide)))
        #expect(KeyboardController.handle(escape, controller: controller, windowModel: windowModel))
        #expect(!windowModel.isZmxSessionsPresented)
    }

    @Test func zmxSessionsArrowSelectionAndActionsUseTheFocusedSession() async throws {
        let controller = try makeController(
            terminalCommandRunner: ZmxKeyboardCommandRunner(
                responses: [
                    ["list"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "name=den\nname=den-vi\tden.root=den\n")
                ]))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.preferences.setZmxPath("/opt/homebrew/bin/zmx")
        windowModel.showZmxSessions()
        await waitForZmxSessionLoad(windowModel)

        let down = try arrowEvent(.downArrow, modifiers: [])
        let upArrow = try arrowEvent(.upArrow, modifiers: [])
        let returnKey = try keyEvent(
            characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let delete = try keyEvent(
            characters: "\u{8}", charactersIgnoringModifiers: "\u{8}", keyCode: 51)
        let deleteKey = try keyEvent(
            characters: "x", charactersIgnoringModifiers: "x", keyCode: 7)
        let reload = try keyEvent(characters: "r", charactersIgnoringModifiers: "r", keyCode: 15)
        let jKey = try keyEvent(characters: "j", charactersIgnoringModifiers: "j", keyCode: 38)
        let kKey = try keyEvent(characters: "k", charactersIgnoringModifiers: "k", keyCode: 40)
        let space = try keyEvent(characters: " ", charactersIgnoringModifiers: " ", keyCode: 49)
        let selectAll = try keyEvent(
            characters: "a", charactersIgnoringModifiers: "a", modifiers: [.command], keyCode: 0)
        let filter = try keyEvent(characters: "/", charactersIgnoringModifiers: "/", keyCode: 44)
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)

        #expect(windowModel.zmxSessions.selectedSessionName == "den")
        #expect(
            KeyboardController.decision(for: down, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.moveSelection(1))))
        #expect(KeyboardController.handle(down, controller: controller, windowModel: windowModel))
        #expect(windowModel.zmxSessions.selectedSessionName == "den-vi")
        #expect(KeyboardController.handle(upArrow, controller: controller, windowModel: windowModel))
        #expect(windowModel.zmxSessions.selectedSessionName == "den")
        #expect(
            KeyboardController.decision(for: jKey, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.moveSelection(1))))
        #expect(KeyboardController.handle(jKey, controller: controller, windowModel: windowModel))
        #expect(windowModel.zmxSessions.selectedSessionName == "den-vi")
        #expect(KeyboardController.handle(kKey, controller: controller, windowModel: windowModel))
        #expect(windowModel.zmxSessions.selectedSessionName == "den")
        #expect(KeyboardController.handle(space, controller: controller, windowModel: windowModel))
        #expect(windowModel.zmxSessions.markedSessionNames == ["den"])
        #expect(
            KeyboardController.decision(for: selectAll, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.selectAll)))
        #expect(KeyboardController.handle(selectAll, controller: controller, windowModel: windowModel))
        #expect(windowModel.zmxSessions.markedSessionNames == ["den", "den-vi"])
        #expect(
            KeyboardController.decision(for: escape, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.clearSelection)))
        #expect(KeyboardController.handle(escape, controller: controller, windowModel: windowModel))
        #expect(windowModel.zmxSessions.markedSessionNames.isEmpty)
        #expect(
            KeyboardController.decision(for: returnKey, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.openSelected)))
        #expect(
            KeyboardController.decision(for: filter, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.enterFilter)))
        #expect(KeyboardController.handle(filter, controller: controller, windowModel: windowModel))
        #expect(windowModel.zmxSessions.isFilterInputActive)
        #expect(
            KeyboardController.decision(for: selectAll, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.selectAll)))
        #expect(
            KeyboardController.decision(for: deleteKey, controller: controller, windowModel: windowModel)
                == .forward(.filterTextInput))
        #expect(
            KeyboardController.decision(for: returnKey, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.openSelected)))
        #expect(KeyboardController.handle(escape, controller: controller, windowModel: windowModel))
        #expect(!windowModel.zmxSessions.isFilterInputActive)
        #expect(windowModel.zmxSessions.query.isEmpty)
        #expect(
            KeyboardController.decision(for: escape, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.hide)))
        #expect(
            KeyboardController.decision(for: delete, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.deleteSelected)))
        #expect(
            KeyboardController.decision(for: deleteKey, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.deleteSelected)))
        #expect(
            KeyboardController.decision(for: reload, controller: controller, windowModel: windowModel)
                == .perform(.zmxSessions(.refresh)))
        #expect(KeyboardController.handle(delete, controller: controller, windowModel: windowModel))
        #expect(windowModel.zmxSessions.pendingDeletion == ["den"])
        #expect(
            KeyboardController.decision(for: returnKey, controller: controller, windowModel: windowModel)
                == .forward(.temporaryTextInput))
    }

    @Test func denModeGPrefixPreservesEssentialKeyCase() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let lowercase = Essential(name: "Lowercase", key: "c", input: "https://example.com/lower")
        let uppercase = Essential(name: "Uppercase", key: "C", input: "https://example.com/upper")
        #expect(controller.preferences.setEssentials([lowercase, uppercase]))
        windowModel.isDenMode = true

        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let lowercaseKey = try keyEvent(
            characters: "c", charactersIgnoringModifiers: "c", keyCode: 8)
        let uppercaseKey = try keyEvent(
            characters: "C", charactersIgnoringModifiers: "c", modifiers: [.shift], keyCode: 8)

        #expect(KeyboardController.handle(prefix, controller: controller, windowModel: windowModel))
        #expect(
            KeyboardController.decision(for: lowercaseKey, controller: controller, windowModel: windowModel)
                == .perform(.essentials(.launch(lowercase.id))))
        #expect(
            KeyboardController.decision(for: uppercaseKey, controller: controller, windowModel: windowModel)
                == .perform(.essentials(.launch(uppercase.id))))
        #expect(KeyboardController.handle(uppercaseKey, controller: controller, windowModel: windowModel))
        #expect(controller.focusedBoard?.currentSheetURL == URL(string: "https://example.com/upper"))
    }

    @Test func denModeGPrefixCanLaunchTerminalEssential() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        #expect(
            controller.preferences.setEssentials([
                Essential(name: "Terminal", key: "t", input: ":terminal \(directory)")
            ]))
        windowModel.isDenMode = true

        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let key = try keyEvent(
            characters: "t", charactersIgnoringModifiers: "t", keyCode: 17)

        #expect(KeyboardController.handle(prefix, controller: controller, windowModel: windowModel))
        #expect(KeyboardController.handle(key, controller: controller, windowModel: windowModel))
        #expect(controller.focusedBoard?.terminalWorkingDirectory == directory)
        #expect(!windowModel.isDenMode)
    }

    @Test func commandShortcutRemainsOutsideEssentialsPrefix() throws {
        let preferences = try makePreferences()
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        #expect(
            controller.preferences.setEssentials([
                Essential(name: "Terminal", key: "t", input: ":terminal")
            ]))
        windowModel.isDenMode = true
        let commandT = try keyEvent(
            characters: "t", charactersIgnoringModifiers: "t", modifiers: [.command], keyCode: 17)

        #expect(
            !KeyboardController.handle(
                commandT, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(windowModel.temporaryContext == nil)
        #expect(windowModel.isDenMode)
    }

    @Test func denModeUnmappedKeyIsConsumedByRouter() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let unmapped = try keyEvent(
            characters: "q", charactersIgnoringModifiers: "q", modifiers: [], keyCode: 12)

        #expect(
            KeyboardController.decision(for: unmapped, controller: controller, windowModel: windowModel)
                == .consume(.denModeUnmapped))
    }

    @Test func hardReloadCurrentSheetShortcutReloadsOnlyFocusedBoard() throws {
        let first = board("First")
        let second = board("Second")
        let controller = try makeController(boards: [first, second])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let reload = try keyEvent(
            characters: "R",
            charactersIgnoringModifiers: "r",
            modifiers: [.command, .shift],
            keyCode: 15)

        #expect(KeyboardController.handle(reload, controller: controller, windowModel: windowModel))
        #expect(Set(controller.webRuntimes.keys) == Set([first.id]))
        #expect(controller.focusedDesk?.focusedBoardID == first.id)
    }

    @Test func reloadFocusedDeskSheetsShortcutReloadsOnlyFocusedDesk() throws {
        let first = board("First")
        let second = board("Second")
        let other = board("Other")
        let firstDesk = DeskState(
            label: "First Desk",
            boards: [first, second],
            focusedBoardID: first.id)
        let secondDesk = DeskState(
            label: "Second Desk",
            boards: [other],
            focusedBoardID: other.id)
        let controller = DenController(
            state: DenState(
                desks: [firstDesk, secondDesk],
                focusedDeskID: firstDesk.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let reload = try keyEvent(
            characters: "R",
            charactersIgnoringModifiers: "r",
            modifiers: [.command, .option, .shift],
            keyCode: 15)

        #expect(KeyboardController.handle(reload, controller: controller, windowModel: windowModel))
        #expect(Set(controller.webRuntimes.keys) == Set([first.id, second.id]))
        #expect(controller.focusedDesk?.id == firstDesk.id)
        #expect(controller.state.desks.map(\.id) == [firstDesk.id, secondDesk.id])
    }

    @Test func denModeEOpensFocusedBoardLinkEditor() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let editLink = try keyEvent(characters: "e", charactersIgnoringModifiers: "e", keyCode: 14)

        #expect(KeyboardController.handle(editLink, controller: controller, windowModel: windowModel))
        #expect(windowModel.isEditBoardLinkPanelPresented)
    }

    @Test func denModeShiftReturnCreatesBoardFromFirstSheet() throws {
        let firstSheetURL = try #require(URL(string: "https://example.com/origin"))
        let currentSheetURL = try #require(URL(string: "https://example.com/current"))
        let source = BoardState(
            label: "First",
            width: 520,
            currentSheetURL: currentSheetURL,
            firstSheetURL: firstSheetURL,
            customLabel: "Pinned")
        let controller = try makeController(boards: [source])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(KeyboardController.handle(shiftReturn, controller: controller, windowModel: windowModel))
        #expect(controller.focusedDesk?.boards.count == 2)
        #expect(controller.focusedBoard?.currentSheetURL == firstSheetURL)
        #expect(controller.focusedBoard?.firstSheetURL == firstSheetURL)
        #expect(controller.focusedBoard?.customLabel == "Pinned")
        #expect(!windowModel.isDenMode)
    }

    @Test func denModeShiftReturnDoesNothingWithoutFirstSheet() throws {
        var source = BoardState(
            label: "Legacy",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/current"),
            firstSheetURL: nil)
        source.firstSheetURL = nil
        let controller = try makeController(boards: [source])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(KeyboardController.handle(shiftReturn, controller: controller, windowModel: windowModel))
        #expect(controller.focusedDesk?.boards.count == 1)
        #expect(windowModel.isDenMode)
    }

    @Test func denModeTTogglesSheetNavigationPauseForFocusedBoard() throws {
        let suiteName = "KeyboardSheetNavigationTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sheetNavigation = SheetNavigationManager(defaults: defaults, scriptSource: "")
        let desk = DeskState(label: "Desk", boards: [board("First")])
        let controller = DenController(
            state: DenState(desks: [desk], focusedDeskID: desk.id),
            sheetNavigation: sheetNavigation)
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let toggle = try keyEvent(characters: "t", charactersIgnoringModifiers: "t", keyCode: 17)
        let repeatedToggle = try keyEvent(
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: true,
            keyCode: 17)
        #expect(controller.focusedBoard?.sheetNavigationPaused == false)
        #expect(KeyboardController.handle(toggle, controller: controller, windowModel: windowModel))
        #expect(controller.focusedBoard?.sheetNavigationPaused == true)
        #expect(KeyboardController.handle(repeatedToggle, controller: controller, windowModel: windowModel))
        #expect(controller.focusedBoard?.sheetNavigationPaused == true)
        #expect(KeyboardController.handle(toggle, controller: controller, windowModel: windowModel))
        #expect(controller.focusedBoard?.sheetNavigationPaused == false)
    }

    @Test func denModeAddsSpaceGuideAndZenViewWithoutPersistedStateChanges() throws {
        let preferences = try makePreferences()
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let state = controller.state

        let zen = try keyEvent(characters: "z", charactersIgnoringModifiers: "z", keyCode: 6)
        #expect(
            KeyboardController.handle(zen, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(windowModel.isZenViewPresented)
        let repeatedZen = try keyEvent(
            characters: "z", charactersIgnoringModifiers: "z", isARepeat: true, keyCode: 6)
        #expect(
            KeyboardController.handle(
                repeatedZen, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(windowModel.isZenViewPresented)

        let question = try keyEvent(
            characters: "?", charactersIgnoringModifiers: "/", modifiers: [.shift], keyCode: 44)
        #expect(
            KeyboardController.handle(
                question, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(windowModel.isKeyboardShortcutsPresented)
        let movement = try keyEvent(characters: "h", charactersIgnoringModifiers: "h", keyCode: 4)
        #expect(
            !KeyboardController.handle(
                movement, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(windowModel.isKeyboardShortcutsPresented)
        #expect(
            !KeyboardController.handle(
                question, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(windowModel.isKeyboardShortcutsPresented)
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)
        #expect(
            KeyboardController.handle(
                escape, controller: controller, windowModel: windowModel, preferences: preferences))
        #expect(!windowModel.isKeyboardShortcutsPresented)

        let space = try keyEvent(characters: " ", charactersIgnoringModifiers: " ", keyCode: 49)
        #expect(
            KeyboardController.handle(space, controller: controller, windowModel: windowModel, preferences: preferences)
        )
        #expect(windowModel.isOpenBoardPanelPresented)
        #expect(controller.state == state)
    }

    @Test func denModeShiftBracketsHandleFirstAndLatestSheet() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let first = try keyEvent(
            characters: "{", charactersIgnoringModifiers: "{", modifiers: [.shift], keyCode: 33)
        let latest = try keyEvent(
            characters: "}", charactersIgnoringModifiers: "}", modifiers: [.shift], keyCode: 30)

        #expect(KeyboardController.handle(first, controller: controller, windowModel: windowModel))
        #expect(KeyboardController.handle(latest, controller: controller, windowModel: windowModel))
        #expect(windowModel.isDenMode)
    }

    @Test func denModePOpensDeskPresetPanelOnlyForDeskWithBoards() throws {
        let save = try keyEvent(characters: "p", charactersIgnoringModifiers: "p", keyCode: 35)
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        #expect(KeyboardController.handle(save, controller: controller, windowModel: windowModel))
        #expect(windowModel.isSaveDeskPresetPanelPresented)

        let empty = try makeController(boards: [])
        let emptyComposition = DenWindowComposition(controller: empty)
        let emptyWindowModel = emptyComposition.model
        emptyComposition.connect()
        defer { emptyComposition.disconnect() }
        emptyWindowModel.isDenMode = true
        #expect(KeyboardController.handle(save, controller: empty, windowModel: emptyWindowModel))
        #expect(!emptyWindowModel.isSaveDeskPresetPanelPresented)
    }

    @Test func denModeShiftPOpensDeskReplacement() throws {
        let replace = try keyEvent(
            characters: "P", charactersIgnoringModifiers: "p", modifiers: [.shift], keyCode: 35)
        let controller = try makeController(boards: [])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        #expect(KeyboardController.handle(replace, controller: controller, windowModel: windowModel))
        #expect(windowModel.isReplaceDeskPanelPresented)
        #expect(windowModel.isNewDeskPanelPresented)
        #expect(!windowModel.isDeskPresetManagementPresented)
    }

    @Test func denModeBHasNoPresetAction() throws {
        let legacy = try keyEvent(characters: "b", charactersIgnoringModifiers: "b", keyCode: 11)
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        #expect(KeyboardController.handle(legacy, controller: controller, windowModel: windowModel))
        #expect(!windowModel.isSaveDeskPresetPanelPresented)
        #expect(!windowModel.isDeskPresetManagementPresented)
    }

    @Test func presetConfirmationsSuspendBoardRemovalShortcuts() throws {
        let commandW = try keyEvent(
            characters: "w", charactersIgnoringModifiers: "w", modifiers: [.command], keyCode: 13)
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        #expect(controller.saveFocusedDeskAsPreset(label: "Routine") == .created)
        #expect(controller.saveFocusedDeskAsPreset(label: "Routine") == .replacementPending)
        #expect(!KeyboardController.handle(commandW, controller: controller, windowModel: windowModel))
        #expect(controller.focusedDesk?.boards.count == 1)

        windowModel.cancelDeskPresetReplacement()
        let presetID = try #require(controller.deskPresets.first?.id)
        controller.requestDeskPresetDeletion(presetID)
        #expect(!KeyboardController.handle(commandW, controller: controller, windowModel: windowModel))
        #expect(controller.focusedDesk?.boards.count == 1)
    }

    @Test func fullscreenBypassesAllShortcutsAndClearsDenMode() throws {
        let controller = try makeController(boards: [board("First")])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        controller.updateFullscreenStatus(boardID: BoardID(), isFullscreen: true)
        #expect(!windowModel.isDenMode)
        #expect(windowModel.isFullscreenActive)

        let commandW = try keyEvent(
            characters: "w", charactersIgnoringModifiers: "w", modifiers: [.command], keyCode: 13)
        #expect(!KeyboardController.handle(commandW, controller: controller, windowModel: windowModel))
    }

    @Test func denModeAKeepsFocusedSheetInDrawer() throws {
        let focused = board("Focused", url: "https://drawer.example/")
        let controller = try makeController(boards: [focused])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        let keep = try keyEvent(
            characters: "a",
            charactersIgnoringModifiers: "a",
            keyCode: 0)

        #expect(KeyboardController.handle(keep, controller: controller, windowModel: windowModel))
        #expect(controller.state.drawerItems.first?.url == URL(string: "https://drawer.example/"))
        #expect(!windowModel.isDrawerOpen)
    }

    private func makePreferences() throws -> AppPreferences {
        let defaults = try #require(TestUserDefaults(suiteName: "KeyboardShortcutTests-\(UUID())"))
        return AppPreferences(defaults: defaults)
    }

    private func makeController(
        desks: [DeskState]? = nil,
        boards: [BoardState] = [],
        terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner()
    ) throws -> DenController {
        let controllerDesks = desks ?? [DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)]
        let defaults = try #require(TestUserDefaults(suiteName: "KeyboardShortcutStore-\(UUID())"))
        let pasteboard = NSPasteboard.withUniqueName()
        return DenController(
            state: DenState(desks: controllerDesks, focusedDeskID: controllerDesks.first?.id ?? DeskID()),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: SheetNavigationManager(
                defaults: defaults,
                pasteboard: pasteboard,
                scriptSource: ""),
            preferences: AppPreferences(defaults: defaults),
            pasteboard: pasteboard,
            terminalCommandRunner: terminalCommandRunner)
    }

    private func keyEvent(
        characters: String,
        charactersIgnoringModifiers: String,
        modifiers: NSEvent.ModifierFlags = [],
        isARepeat: Bool = false,
        keyCode: UInt16
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                isARepeat: isARepeat,
                keyCode: keyCode))
    }

    private func arrowEvent(
        _ specialKey: NSEvent.SpecialKey,
        modifiers: NSEvent.ModifierFlags,
        isARepeat: Bool = false
    ) throws -> NSEvent {
        let (characters, keyCode): (String, UInt16) =
            switch specialKey {
            case .upArrow: ("\u{F700}", 126)
            case .downArrow: ("\u{F701}", 125)
            case .leftArrow: ("\u{F702}", 123)
            case .rightArrow: ("\u{F703}", 124)
            default: ("", 0)
            }
        return try keyEvent(
            characters: characters,
            charactersIgnoringModifiers: characters,
            modifiers: modifiers,
            isARepeat: isARepeat,
            keyCode: keyCode)
    }

    private func board(_ label: String, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: 520, currentSheetURL: URL(string: url))
    }

    private func waitForZmxSessionLoad(_ windowModel: DenWindowModel) async {
        await windowModel.zmxSessions.waitForRefresh()
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
