import AppKit
import DenDomain
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
    @Test func keyboardShortcutGuideForwardsTextInputAndKeepsEscapeToClose() throws {
        // Arrange
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showKeyboardShortcuts()
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
        let letterDecision = KeyboardController.decision(for: letterA, store: store, viewModel: viewModel)
        let selectAllDecision = KeyboardController.decision(for: commandA, store: store, viewModel: viewModel)
        let commandTDecision = KeyboardController.decision(for: commandT, store: store, viewModel: viewModel)
        let questionDecision = KeyboardController.decision(for: questionMark, store: store, viewModel: viewModel)
        let escapeDecision = KeyboardController.decision(for: escape, store: store, viewModel: viewModel)

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
        let store = try makeStore(boards: [board("Board")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
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
            KeyboardController.decision(for: toggle, store: store, viewModel: viewModel)
                == .perform(.application(.toggleBoardRail))
        )
        #expect(
            KeyboardController.decision(
                for: repeatToggle,
                store: store,
                viewModel: viewModel
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
        let store = try makeStore(desks: [firstDesk, secondDesk])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.focusDesk(secondDesk.id)
        viewModel.isDenMode = true

        let shiftOne = try keyEvent(
            characters: "!",
            charactersIgnoringModifiers: "!",
            modifiers: [.shift],
            keyCode: 18)

        #expect(KeyboardController.handle(shiftOne, store: store, viewModel: viewModel))
        #expect(store.state.focusedDeskID == firstDesk.id)
        #expect(store.focusedDesk?.focusedBoardID == movedBoard.id)
        #expect(store.state.desks[0].boards.map(\.id) == [movedBoard.id])
        #expect(!viewModel.isDenMode)
    }

    @Test func denModeEqualsWidensFocusedBoardWithOrWithoutShift() throws {
        for (characters, modifiers) in [("=", NSEvent.ModifierFlags()), ("+", NSEvent.ModifierFlags.shift)] {
            let store = try makeStore(boards: [board("Focused")])
            let viewModel = DenViewModel(store: store)
            viewModel.connect()
            defer { viewModel.disconnect() }
            viewModel.isDenMode = true
            let event = try keyEvent(
                characters: characters,
                charactersIgnoringModifiers: "=",
                modifiers: modifiers,
                keyCode: 24)

            #expect(KeyboardController.handle(event, store: store, viewModel: viewModel))
            #expect(store.focusedBoard?.width == 600)
        }
    }

    @Test func denModeAngleBracketsBrowseBoardsWithoutChangingFocus() throws {
        let first = board("First")
        let second = board("Second")
        let store = try makeStore(boards: [first, second])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let right = try keyEvent(
            characters: ">",
            charactersIgnoringModifiers: ".",
            modifiers: [.shift],
            keyCode: 47)

        #expect(KeyboardController.handle(right, store: store, viewModel: viewModel))
        #expect(viewModel.revealNextBoardRequest == 1)
        #expect(store.focusedDesk?.focusedBoardID == first.id)

        let left = try keyEvent(
            characters: "<",
            charactersIgnoringModifiers: ",",
            modifiers: [.shift],
            keyCode: 43)

        #expect(KeyboardController.handle(left, store: store, viewModel: viewModel))
        #expect(viewModel.revealPreviousBoardRequest == 1)
        #expect(store.focusedDesk?.focusedBoardID == first.id)
    }

    @Test func denModeControlSCopiesCurrentSheetScreenshot() throws {
        let store = try makeStore(boards: [board("First"), board("Second")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let controlS = try keyEvent(
            characters: "s",
            charactersIgnoringModifiers: "s",
            modifiers: [.control],
            keyCode: 1)
        #expect(
            KeyboardController.decision(for: controlS, store: store, viewModel: viewModel)
                == .perform(.board(.copySheetScreenshot)))
    }

    @Test func denModeYCopiesFocusedBoardLocationAndShiftYCopiesBoardID() throws {
        // Arrange
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
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
        let locationDecision = KeyboardController.decision(for: locationEvent, store: store, viewModel: viewModel)
        let boardIDDecision = KeyboardController.decision(for: boardIDEvent, store: store, viewModel: viewModel)

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
        let store = try makeStore(desks: [firstDesk, secondDesk])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.focusDesk(secondDesk.id)
        let preferences = store.preferences
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
            KeyboardController.handle(commandOptionOne, store: store, viewModel: viewModel, preferences: preferences))
        #expect(store.state.focusedDeskID == firstDesk.id)
        #expect(!viewModel.isDenMode)
        #expect(!KeyboardController.handle(commandZero, store: store, viewModel: viewModel, preferences: preferences))
        #expect(store.state.focusedDeskID == firstDesk.id)
    }

    @Test func contentSizeShortcutsRouteToTheFocusedBoardInEveryInputMode() throws {
        let store = try makeStore(boards: [board("Focused")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
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
            KeyboardController.decision(for: increase, store: store, viewModel: viewModel)
                == .perform(.board(.increaseSheetSize)))
        #expect(
            KeyboardController.decision(for: plus, store: store, viewModel: viewModel)
                == .perform(.board(.increaseSheetSize)))
        #expect(
            KeyboardController.decision(for: decrease, store: store, viewModel: viewModel)
                == .perform(.board(.decreaseSheetSize)))
        #expect(
            KeyboardController.decision(for: reset, store: store, viewModel: viewModel)
                == .perform(.board(.resetSheetSize)))

        viewModel.isDenMode = true
        #expect(
            KeyboardController.decision(for: decrease, store: store, viewModel: viewModel)
                == .perform(.board(.decreaseSheetSize)))
    }

    @Test func controlTabDeskShortcutsNavigateAndReturn() throws {
        let firstDesk = DeskState(label: "First", boards: [])
        let secondDesk = DeskState(label: "Second", boards: [])
        let thirdDesk = DeskState(label: "Third", boards: [])
        let store = try makeStore(desks: [firstDesk, secondDesk, thirdDesk])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let preferences = store.preferences

        let next = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.control],
            keyCode: 48)
        #expect(KeyboardController.handle(next, store: store, viewModel: viewModel, preferences: preferences))
        #expect(store.focusedDesk?.id == secondDesk.id)

        let previous = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.control, .shift],
            keyCode: 48)
        #expect(KeyboardController.handle(previous, store: store, viewModel: viewModel, preferences: preferences))
        #expect(store.focusedDesk?.id == firstDesk.id)

        let returnToPrevious = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.command, .option],
            keyCode: 48)
        #expect(
            KeyboardController.handle(
                returnToPrevious,
                store: store, viewModel: viewModel,
                preferences: preferences))
        #expect(store.focusedDesk?.id == secondDesk.id)
    }

    @Test func denModeIOpensNotifications() throws {
        let store = try makeStore(boards: [board("Terminal")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let open = try keyEvent(
            characters: "i",
            charactersIgnoringModifiers: "i",
            keyCode: 34)

        #expect(KeyboardController.handle(open, store: store, viewModel: viewModel))
        #expect(viewModel.isNotificationListPresented)
        #expect(viewModel.isDenMode)
    }

    @Test func denModeVOpensBoardFromClipboard() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        store.pasteboard.clearContents()
        store.pasteboard.setString("https://example.com/test", forType: .string)

        let vKey = try keyEvent(
            characters: "v",
            charactersIgnoringModifiers: "v",
            keyCode: 9)

        #expect(KeyboardController.handle(vKey, store: store, viewModel: viewModel))
        #expect(store.focusedDesk?.boards.count == 2)
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://example.com/test"))
        #expect(!viewModel.isDenMode)
    }

    @Test func denModeBKeyOpensSaveEssentialPanelForFocusedBoard() throws {
        let board = BoardState(
            label: "Niri",
            width: 520,
            currentSheetURL: URL(string: "https://github.com/YaLTeR/niri")
        )
        let desk = DeskState(label: "Dev", boards: [board], focusedBoardID: board.id)
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true

        let bKey = try keyEvent(
            characters: "b",
            charactersIgnoringModifiers: "b",
            keyCode: 11
        )

        #expect(KeyboardController.handle(bKey, store: store, viewModel: viewModel))
        #expect(viewModel.isSaveEssentialPanelPresented)
        #expect(viewModel.saveEssentialDraft?.name == "Niri")
        #expect(viewModel.saveEssentialDraft?.input == "https://github.com/YaLTeR/niri")
    }

    @Test func denModeMKeyTogglesAnchorBoardAndShiftMJumps() throws {
        let first = board("First")
        let second = board("Second")
        let store = try makeStore(boards: [first, second])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true

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
        #expect(KeyboardController.handle(mKey, store: store, viewModel: viewModel))
        #expect(store.focusedDesk?.anchorBoardID == first.id)
        #expect(store.latestFeedback?.message == "Set Anchor Board")

        // Move to second board.
        store.focusBoard(second.id)
        #expect(store.focusedBoard?.id == second.id)

        // Press 'Shift + m' to jump to anchor first board.
        #expect(KeyboardController.handle(shiftMKey, store: store, viewModel: viewModel))
        #expect(store.focusedBoard?.id == first.id)

        // Press 'Shift + m' again to return to second board (A <-> B toggle).
        #expect(KeyboardController.handle(shiftMKey, store: store, viewModel: viewModel))
        #expect(store.focusedBoard?.id == second.id)

        // Press 'm' on second board to move anchor.
        #expect(KeyboardController.handle(mKey, store: store, viewModel: viewModel))
        #expect(store.focusedDesk?.anchorBoardID == second.id)

        // Press 'm' again on second board to clear anchor.
        #expect(KeyboardController.handle(mKey, store: store, viewModel: viewModel))
        #expect(store.focusedDesk?.anchorBoardID == nil)
        #expect(store.latestFeedback?.message == "Cleared Anchor Board")

        // Press 'Shift + m' with no anchor shows warning.
        #expect(KeyboardController.handle(shiftMKey, store: store, viewModel: viewModel))
        #expect(store.latestFeedback?.message == "No Anchor Board in Desk")
        #expect(store.latestFeedback?.severity == .warning)
    }

    @Test func notificationArrowsMoveSelectionAndReturnOpensIt() throws {
        let first = board("First")
        let second = board("Second")
        let store = try makeStore(boards: [first, second])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.recordNotification(title: "First", body: "Done", boardID: first.id)
        store.recordNotification(title: "Second", body: "Done", boardID: second.id)
        viewModel.isDenMode = true
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

        #expect(KeyboardController.handle(open, store: store, viewModel: viewModel, preferences: preferences))
        #expect(viewModel.notificationList.selectedNotificationID == store.notifications[0].id)
        #expect(KeyboardController.handle(down, store: store, viewModel: viewModel, preferences: preferences))
        #expect(viewModel.notificationList.selectedNotificationID == store.notifications[1].id)
        #expect(KeyboardController.handle(enter, store: store, viewModel: viewModel, preferences: preferences))
        #expect(store.focusedBoard?.id == first.id)
        #expect(!viewModel.isNotificationListPresented)
    }

    @Test func customBindingsApplyImmediatelyAndCanBeUnassigned() throws {
        let preferences = try makePreferences()
        let store = try makeStore(boards: [board("First"), board("Second")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let toggle = try keyEvent(
            characters: ".", charactersIgnoringModifiers: ".", modifiers: [.control], keyCode: 47)
        let defaultToggle = try keyEvent(
            characters: ",", charactersIgnoringModifiers: ",", modifiers: [.control], keyCode: 43)
        #expect(
            preferences.setShortcut(
                ShortcutBinding(key: .character("."), modifiers: [.control]),
                for: .toggleDenMode) == nil)

        #expect(!KeyboardController.handle(defaultToggle, store: store, viewModel: viewModel, preferences: preferences))
        #expect(KeyboardController.handle(toggle, store: store, viewModel: viewModel, preferences: preferences))
        #expect(viewModel.isDenMode)

        viewModel.exitDenMode()
        preferences.clearShortcut(for: .focusNextBoard)
        let right = try arrowEvent(.rightArrow, modifiers: [.command, .option])
        #expect(!KeyboardController.handle(right, store: store, viewModel: viewModel, preferences: preferences))
        #expect(store.focusedDesk?.focusedBoardID == store.focusedDesk?.boards.first?.id)
    }

    @Test func customBindingsAreSuspendedByTemporaryContexts() throws {
        let preferences = try makePreferences()
        let store = try makeStore(boards: [board("First"), board("Second")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let next = try arrowEvent(.rightArrow, modifiers: [.command, .option])

        viewModel.showNewDeskPanel()
        #expect(!KeyboardController.handle(next, store: store, viewModel: viewModel, preferences: preferences))
        viewModel.hideNewDeskPanel()

        viewModel.showOverview()
        let focusedBoardID = store.focusedDesk?.focusedBoardID
        #expect(KeyboardController.handle(next, store: store, viewModel: viewModel, preferences: preferences))
        #expect(store.focusedDesk?.focusedBoardID == focusedBoardID)
    }

    @Test func shiftEscapeTogglesBoardActivityAcrossInputContexts() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let shiftEscape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            modifiers: [.shift],
            keyCode: 53)

        #expect(KeyboardController.handle(shiftEscape, store: store, viewModel: viewModel))
        #expect(viewModel.isBoardActivityPresented)

        #expect(KeyboardController.handle(shiftEscape, store: store, viewModel: viewModel))
        #expect(!viewModel.isBoardActivityPresented)

        viewModel.isDenMode = true
        #expect(KeyboardController.handle(shiftEscape, store: store, viewModel: viewModel))
        #expect(viewModel.isBoardActivityPresented)

        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53)
        #expect(KeyboardController.handle(escape, store: store, viewModel: viewModel))
        #expect(!viewModel.isBoardActivityPresented)
    }

    @Test func denModeToggleRemainsAvailableInDrawer() throws {
        let preferences = try makePreferences()
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://example.com/")))
        let previewID = viewModel.drawer.expandedItemID
        let toggle = try keyEvent(
            characters: ",", charactersIgnoringModifiers: ",", modifiers: [.control], keyCode: 43)

        #expect(KeyboardController.handle(toggle, store: store, viewModel: viewModel, preferences: preferences))
        #expect(viewModel.isDenMode)
        #expect(viewModel.drawer.expandedItemID == previewID)

        #expect(KeyboardController.handle(toggle, store: store, viewModel: viewModel, preferences: preferences))
        #expect(!viewModel.isDenMode)
        #expect(viewModel.drawer.expandedItemID == previewID)
    }

    @Test func drawerCommandWDiscardsSelectedItemWithoutRemovingBoard() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))
        let selectedItemID = try #require(viewModel.drawer.selectedItemID)
        let commandW = try keyEvent(
            characters: "w",
            charactersIgnoringModifiers: "w",
            modifiers: [.command],
            keyCode: 13)

        #expect(
            KeyboardController.decision(for: commandW, store: store, viewModel: viewModel)
                == .perform(.drawer(.discardSelectedItem(focusNext: true))))
        #expect(KeyboardController.handle(commandW, store: store, viewModel: viewModel))
        #expect(store.state.drawerItems.count == 1)
        #expect(!store.state.drawerItems.contains { $0.id == selectedItemID })
        #expect(store.focusedDesk?.boards.count == 1)
        #expect(viewModel.isDrawerOpen)

        let repeatedCommandW = try keyEvent(
            characters: "w",
            charactersIgnoringModifiers: "w",
            modifiers: [.command],
            isARepeat: true,
            keyCode: 13)
        #expect(
            KeyboardController.decision(for: repeatedCommandW, store: store, viewModel: viewModel)
                == .consume(.ignoredRepeat))
        #expect(KeyboardController.handle(repeatedCommandW, store: store, viewModel: viewModel))
        #expect(store.state.drawerItems.count == 1)
    }

    @Test func drawerControlEscapeClosesDrawerWithOrWithoutPreview() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://preview.example/")))
        let itemID = try #require(viewModel.drawer.expandedItemID)
        let controlEscape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            modifiers: [.control],
            keyCode: 53)

        #expect(
            KeyboardController.decision(for: controlEscape, store: store, viewModel: viewModel)
                == .perform(.drawer(.close)))
        #expect(KeyboardController.handle(controlEscape, store: store, viewModel: viewModel))
        #expect(!viewModel.isDrawerOpen)
        #expect(viewModel.drawer.expandedItemID == itemID)

        viewModel.openDrawer()
        viewModel.drawer.toggleItem(itemID)
        viewModel.isDenMode = true

        #expect(KeyboardController.handle(controlEscape, store: store, viewModel: viewModel))
        #expect(!viewModel.isDrawerOpen)
        #expect(store.state.drawerItems.count == 1)
    }

    @Test func drawerConsumesUnmappedKeysWhenPreviewIsNotFocused() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://example.com/")))
        let itemID = try #require(viewModel.drawer.selectedItemID)
        viewModel.drawer.toggleItem(itemID)
        #expect(!viewModel.isDenMode)
        #expect(viewModel.isDrawerOpen)
        #expect(viewModel.drawer.expandedItemID == nil)

        let letterA = try keyEvent(
            characters: "a", charactersIgnoringModifiers: "a", keyCode: 0)
        let space = try keyEvent(
            characters: " ", charactersIgnoringModifiers: " ", keyCode: 49)
        let tab = try keyEvent(
            characters: "\t", charactersIgnoringModifiers: "\t", keyCode: 48)

        #expect(
            KeyboardController.decision(for: letterA, store: store, viewModel: viewModel)
                == .consume(.exclusiveContext))
        #expect(KeyboardController.handle(letterA, store: store, viewModel: viewModel))

        #expect(
            KeyboardController.decision(for: space, store: store, viewModel: viewModel)
                == .consume(.exclusiveContext))
        #expect(KeyboardController.handle(space, store: store, viewModel: viewModel))

        #expect(
            KeyboardController.decision(for: tab, store: store, viewModel: viewModel)
                == .consume(.exclusiveContext))
        #expect(KeyboardController.handle(tab, store: store, viewModel: viewModel))

        #expect(viewModel.isDrawerOpen)
        #expect(store.state.drawerItems.count == 1)
        #expect(store.focusedDesk?.boards.count == 1)
    }

    @Test func denModeShiftDRequestsDrawerClearConfirmation() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))
        viewModel.isDenMode = true

        let clear = try keyEvent(
            characters: "D",
            charactersIgnoringModifiers: "d",
            modifiers: [.shift],
            keyCode: 2)

        #expect(KeyboardController.handle(clear, store: store, viewModel: viewModel))
        #expect(viewModel.drawerPendingDeletionCount == 2)
        #expect(store.state.drawerItems.count == 2)
    }

    @Test func drawerFKeyTogglesPresentationStyle() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://example.com/")))
        viewModel.openDrawer()
        viewModel.isDenMode = true

        #expect(store.preferences.drawerStyle == .floating)

        let fKey = try keyEvent(
            characters: "f",
            charactersIgnoringModifiers: "f",
            keyCode: 3
        )
        #expect(KeyboardController.handle(fKey, store: store, viewModel: viewModel))
        #expect(store.preferences.drawerStyle == .bottom)

        #expect(KeyboardController.handle(fKey, store: store, viewModel: viewModel))
        #expect(store.preferences.drawerStyle == .floating)
    }

    @Test func denModeShiftDDoesNothingInDrawerFilterModeOrOnRepeat() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://example.com/")))
        viewModel.isDenMode = true

        let clear = try keyEvent(
            characters: "D",
            charactersIgnoringModifiers: "d",
            modifiers: [.shift],
            keyCode: 2)
        viewModel.drawer.enterFilterMode()
        #expect(!KeyboardController.handle(clear, store: store, viewModel: viewModel))
        #expect(!viewModel.hasPendingConfirmation)

        viewModel.drawer.exitFilterMode()
        let repeatClear = try keyEvent(
            characters: "D",
            charactersIgnoringModifiers: "d",
            modifiers: [.shift],
            isARepeat: true,
            keyCode: 2)
        #expect(KeyboardController.handle(repeatClear, store: store, viewModel: viewModel))
        #expect(!viewModel.hasPendingConfirmation)
    }

    @Test func denModeEnterAndShiftEnterUseDistinctDuplicateActions() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let returnKey = try keyEvent(
            characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(
            KeyboardController.decision(for: returnKey, store: store, viewModel: viewModel)
                == .perform(.board(.duplicate)))
        #expect(
            KeyboardController.decision(for: shiftReturn, store: store, viewModel: viewModel)
                == .perform(.board(.duplicateFirstSheet)))
    }

    @Test func denModeShiftEnterDuplicatesTerminalInItsWorkingDirectory() throws {
        let source = BoardState(
            label: "Terminal",
            width: 520,
            workingDirectory: "/tmp/project",
            customLabel: "Build")
        let store = try makeStore(boards: [source])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(KeyboardController.handle(shiftReturn, store: store, viewModel: viewModel))
        #expect(store.focusedDesk?.boards.count == 2)
        #expect(store.focusedBoard?.id != source.id)
        #expect(store.focusedBoard?.isTerminal == true)
        #expect(store.focusedBoard?.terminalWorkingDirectory == "/tmp/project")
        #expect(store.focusedBoard?.label == "Terminal")
        #expect(store.focusedBoard?.width == 520)
        #expect(store.focusedBoard?.customLabel == "Build")
    }

    @Test func denModeShiftEnterDuplicatesZellijSession() throws {
        let source = BoardState(
            label: "Zellij",
            width: 520,
            zellijSessionName: "dev",
            customLabel: "Build")
        let store = try makeStore(boards: [source])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(KeyboardController.handle(shiftReturn, store: store, viewModel: viewModel))
        #expect(store.focusedDesk?.boards.count == 2)
        let duplicate = try #require(store.focusedBoard)
        #expect(duplicate.id != source.id)
        #expect(duplicate.isZellij)
        #expect(duplicate.zellijSessionName == "dev")
        #expect(duplicate.label == "Zellij")
        #expect(duplicate.width == 520)
        #expect(duplicate.customLabel == "Build")
    }

    @Test func openProfilePanelForwardsKeyboardNavigationToItsTextField() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        viewModel.deskFilter.enter()
        viewModel.isNotificationListPresented = true
        viewModel.setTemporaryContext(.profilePicker)
        #expect(viewModel.temporaryContext == .profilePicker)
        #expect(viewModel.deskFilter.phase == .inactive)
        #expect(!viewModel.isNotificationListPresented)
        let down = try arrowEvent(.downArrow, modifiers: [])
        let returnKey = try keyEvent(
            characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)

        #expect(
            KeyboardController.decision(for: down, store: store, viewModel: viewModel) == .forward(.temporaryTextInput))
        #expect(
            KeyboardController.decision(for: returnKey, store: store, viewModel: viewModel)
                == .forward(.temporaryTextInput))
        #expect(
            KeyboardController.decision(for: escape, store: store, viewModel: viewModel)
                == .forward(.temporaryTextInput))
    }

    @Test func textInputPanelConsumesTabTraversal() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.showOpenBoardPanel()
        let tab = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            keyCode: 48)
        let shiftTab = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.shift],
            keyCode: 48)

        #expect(viewModel.temporaryContext == .openBoard)
        #expect(
            KeyboardController.decision(for: tab, store: store, viewModel: viewModel)
                == .consume(.exclusiveContext))
        #expect(
            KeyboardController.decision(for: shiftTab, store: store, viewModel: viewModel)
                == .consume(.exclusiveContext))
    }

    @Test func drawerFilterPassesShiftedCharactersToTextInput() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://example.com/")))
        viewModel.isDenMode = true
        viewModel.drawer.enterFilterMode()

        let uppercase = try keyEvent(
            characters: "A",
            charactersIgnoringModifiers: "a",
            modifiers: [.shift],
            keyCode: 0)

        #expect(!KeyboardController.handle(uppercase, store: store, viewModel: viewModel))
        #expect(viewModel.drawer.isFilterInputActive)
    }

    @Test func drawerFilterPassesModifiedReturnAndControlEscapeClosesDrawer() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://example.com/")))
        viewModel.isDenMode = true
        viewModel.drawer.enterFilterMode()

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

        #expect(!KeyboardController.handle(modifiedReturn, store: store, viewModel: viewModel))
        #expect(
            KeyboardController.decision(for: controlEscape, store: store, viewModel: viewModel)
                == .perform(.drawer(.close)))
        #expect(KeyboardController.handle(controlEscape, store: store, viewModel: viewModel))
        #expect(!viewModel.isDrawerOpen)
    }

    @Test func overviewFilterUsesTwoPhaseSelection() throws {
        let first = board("First")
        let second = board("Second")
        let store = try makeStore(boards: [first, second])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()

        let slash = try keyEvent(
            characters: "/",
            charactersIgnoringModifiers: "/",
            keyCode: 44)
        let returnKey = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36)

        #expect(KeyboardController.handle(slash, store: store, viewModel: viewModel))
        #expect(viewModel.overview.filterPhase == .filtering)
        viewModel.overview.setQuery("Second")
        #expect(viewModel.overview.selectionBoardID == second.id)

        #expect(KeyboardController.handle(returnKey, store: store, viewModel: viewModel))
        #expect(viewModel.overview.filterPhase == .selecting)
        #expect(viewModel.isOverviewPresented)

        #expect(KeyboardController.handle(returnKey, store: store, viewModel: viewModel))
        #expect(viewModel.overview.filterPhase == .inactive)
        #expect(!viewModel.isOverviewPresented)
        #expect(store.focusedBoard?.id == second.id)
    }

    @Test func overviewEscapeRequestsBoardDragCancellation() throws {
        let first = board("First")
        let store = try makeStore(boards: [first])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()
        #expect(viewModel.beginOverviewBoardDrag(first.id))

        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53)

        #expect(
            KeyboardController.decision(for: escape, store: store, viewModel: viewModel)
                == .perform(.board(.requestDragCancellation)))
        #expect(KeyboardController.handle(escape, store: store, viewModel: viewModel))
        #expect(viewModel.boardDragCancellationRequest == 1)
        #expect(viewModel.isOverviewPresented)
    }

    @Test func denModeRemoveShortcutsChooseTheirFocusDirection() throws {
        let dBoards = [board("First"), board("Focused"), board("Last")]
        let dStore = try makeStore(boards: dBoards)
        let dViewModel = DenViewModel(store: dStore)
        dViewModel.connect()
        defer { dViewModel.disconnect() }
        dStore.focusBoard(dBoards[1].id)
        dViewModel.isDenMode = true
        let dEvent = try keyEvent(characters: "d", charactersIgnoringModifiers: "d", keyCode: 2)

        #expect(
            KeyboardController.decision(for: dEvent, store: dStore, viewModel: dViewModel)
                == .perform(.board(.removeAndFocusNext)))
        #expect(KeyboardController.handle(dEvent, store: dStore, viewModel: dViewModel))
        #expect(dStore.focusedDesk?.boards.map(\.id) == [dBoards[0].id, dBoards[2].id])
        #expect(dStore.focusedDesk?.focusedBoardID == dBoards[2].id)

        let xBoards = [board("First"), board("Focused"), board("Last")]
        let xStore = try makeStore(boards: xBoards)
        let xViewModel = DenViewModel(store: xStore)
        xViewModel.connect()
        defer { xViewModel.disconnect() }
        xStore.focusBoard(xBoards[1].id)
        xViewModel.isDenMode = true
        let xEvent = try keyEvent(characters: "x", charactersIgnoringModifiers: "x", keyCode: 7)

        #expect(
            KeyboardController.decision(for: xEvent, store: xStore, viewModel: xViewModel)
                == .perform(.board(.remove)))
        #expect(KeyboardController.handle(xEvent, store: xStore, viewModel: xViewModel))
        #expect(xStore.focusedDesk?.boards.map(\.id) == [xBoards[0].id, xBoards[2].id])
        #expect(xStore.focusedDesk?.focusedBoardID == xBoards[0].id)
    }

    @Test func nativeCommandShortcutsPassThroughWithoutExecuting() throws {
        let first = board("First")
        let second = board("Second")
        let store = try makeStore(boards: [first, second])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
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
            #expect(!KeyboardController.handle(command, store: store, viewModel: viewModel))
        }
        #expect(!KeyboardController.handle(closeWindow, store: store, viewModel: viewModel))
        #expect(store.focusedDesk?.boards.map(\.id) == [first.id, second.id])
        #expect(viewModel.temporaryContext == nil)
    }

    @Test func denModeCommaPerformsSettingsWithoutForwarding() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let comma = try keyEvent(
            characters: ",", charactersIgnoringModifiers: ",", modifiers: [], keyCode: 43)

        #expect(!KeyboardController.handle(comma, store: store, viewModel: viewModel))

        viewModel.isDenMode = true
        #expect(
            KeyboardController.decision(for: comma, store: store, viewModel: viewModel)
                == .perform(.application(.openSettings)))
        var didOpenSettings = false
        let handled = KeyboardController.handle(
            comma,
            store: store, viewModel: viewModel,
            openSettings: { didOpenSettings = true })
        #expect(handled)
        #expect(didOpenSettings)

        viewModel.showOverview()
        #expect(KeyboardController.handle(comma, store: store, viewModel: viewModel))
        #expect(
            KeyboardController.decision(for: comma, store: store, viewModel: viewModel) == .consume(.exclusiveContext))
    }

    @Test func denModeGPrefixLaunchesMatchingEssential() throws {
        let store = try makeStore(boards: [BoardState(label: "First", width: 720, currentSheetURL: nil)])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let essential = Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
        #expect(store.preferences.setEssentials([essential]))
        viewModel.isDenMode = true

        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let key = try keyEvent(
            characters: "c", charactersIgnoringModifiers: "c", keyCode: 8)

        #expect(
            KeyboardController.decision(for: prefix, store: store, viewModel: viewModel)
                == .perform(.essentials(.enterPrefix)))
        #expect(KeyboardController.handle(prefix, store: store, viewModel: viewModel))
        #expect(viewModel.temporaryContext == .essentialsPrefix)
        #expect(
            KeyboardController.decision(for: key, store: store, viewModel: viewModel)
                == .perform(.essentials(.launch(essential.id))))
        #expect(KeyboardController.handle(key, store: store, viewModel: viewModel))
        #expect(viewModel.temporaryContext == nil)
        #expect(!viewModel.isDenMode)
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://chatgpt.com/"))
        #expect(store.focusedBoard?.width == 720)
    }

    @Test func sheetInputEssentialsPrefixLaunchesWithoutEnteringDenMode() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let essential = Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
        #expect(store.preferences.setEssentials([essential]))
        viewModel.showEssentialsPrefix()

        let key = try keyEvent(
            characters: "c", charactersIgnoringModifiers: "c", keyCode: 8)

        #expect(
            KeyboardController.decision(for: key, store: store, viewModel: viewModel)
                == .perform(.essentials(.launch(essential.id))))
        #expect(KeyboardController.handle(key, store: store, viewModel: viewModel))
        #expect(viewModel.temporaryContext == nil)
        #expect(!viewModel.isDenMode)
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://chatgpt.com/"))
    }

    @Test func essentialsPrefixSelectionWrapsBetweenFirstAndLast() throws {
        // Arrange
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let first = Essential(name: "First Essential", key: "a", input: "https://first.example")
        let second = Essential(name: "Second Essential", key: "b", input: "https://second.example")
        #expect(store.preferences.setEssentials([first, second]))

        // Act
        viewModel.showEssentialsPrefix()
        viewModel.moveEssentialSelection(by: -1)

        // Assert
        #expect(viewModel.selectedEssentialID == second.id)

        // Act
        viewModel.moveEssentialSelection(by: 1)

        // Assert
        #expect(viewModel.selectedEssentialID == first.id)
    }

    @Test func essentialsPrefixOpeningResetsSelectionToFirst() throws {
        // Arrange
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let first = Essential(name: "First Essential", key: "a", input: "https://first.example")
        let second = Essential(name: "Second Essential", key: "b", input: "https://second.example")
        #expect(store.preferences.setEssentials([first, second]))
        viewModel.showEssentialsPrefix()

        // Act
        viewModel.moveEssentialSelection(by: 1)
        viewModel.exitEssentialsPrefix()
        viewModel.showEssentialsPrefix()

        // Assert
        #expect(viewModel.selectedEssentialID == first.id)
    }

    @Test func essentialsPrefixReturnLaunchesFocusedEssentialAndClosesPrefix() throws {
        // Arrange
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let first = Essential(name: "First Essential", key: "a", input: "https://first.example")
        let second = Essential(name: "Second Essential", key: "b", input: "https://second.example")
        #expect(store.preferences.setEssentials([first, second]))
        viewModel.showEssentialsPrefix()

        // Act
        viewModel.moveEssentialSelection(by: 1)
        viewModel.launchSelectedEssential()

        // Assert
        #expect(viewModel.temporaryContext == nil)
        #expect(viewModel.selectedEssentialID == nil)
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://second.example/"))
    }

    @Test func essentialsPrefixRoutesArrowsReturnAndConfiguredJkKeys() throws {
        // Arrange
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let jEssential = Essential(name: "J Essential", key: "j", input: "https://j.example")
        let kEssential = Essential(name: "K Essential", key: "k", input: "https://k.example")
        #expect(store.preferences.setEssentials([jEssential, kEssential]))
        viewModel.showEssentialsPrefix()
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
                context: InputContext(store: store, viewModel: viewModel, event: event),
                shortcuts: ShortcutConfiguration(preferences: store.preferences))
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
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let essential = Essential(name: "Essential", key: "a", input: "https://essential.example")
        let nextEssential = Essential(name: "Next", key: "b", input: "https://next.example")
        #expect(store.preferences.setEssentials([essential, nextEssential]))
        viewModel.showEssentialsPrefix()
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
                context: InputContext(store: store, viewModel: viewModel, event: event),
                shortcuts: ShortcutConfiguration(preferences: store.preferences))
        }

        // Act
        let upDecision = route(repeatedUp)
        let movementDecision = route(repeatedDown)
        let returnDecision = route(repeatedReturn)
        let keyDecision = route(repeatedKey)
        let escapeDecision = route(repeatedEscape)
        #expect(KeyboardController.handle(repeatedDown, store: store, viewModel: viewModel))
        #expect(KeyboardController.handle(repeatedReturn, store: store, viewModel: viewModel))
        #expect(KeyboardController.handle(repeatedKey, store: store, viewModel: viewModel))

        // Assert
        #expect(upDecision == .perform(.essentials(.moveSelection(-1))))
        #expect(movementDecision == .perform(.essentials(.moveSelection(1))))
        #expect(viewModel.selectedEssentialID == nextEssential.id)
        #expect(returnDecision == .consume(.ignoredRepeat))
        #expect(keyDecision == .consume(.ignoredRepeat))
        #expect(escapeDecision == .consume(.ignoredRepeat))
        #expect(store.focusedDesk?.boards.count == 1)
    }

    @Test func denModeGPrefixShowsFeedbackForUnregisteredKeys() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let essential = Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
        #expect(store.preferences.setEssentials([essential]))
        viewModel.isDenMode = true
        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let unknown = try keyEvent(
            characters: "x", charactersIgnoringModifiers: "x", keyCode: 7)

        #expect(KeyboardController.handle(prefix, store: store, viewModel: viewModel))
        #expect(
            KeyboardController.decision(for: unknown, store: store, viewModel: viewModel)
                == .perform(.essentials(.showNotFound("x"))))
        #expect(KeyboardController.handle(unknown, store: store, viewModel: viewModel))
        #expect(viewModel.temporaryContext == nil)
        #expect(viewModel.isDenMode)
        #expect(store.focusedDesk?.boards.count == 1)
        #expect(store.latestFeedback?.message == "No Essential assigned to 'x'.")
        #expect(store.latestFeedback?.severity == .warning)

    }

    @Test func denModeGPrefixCancelsQuietlyForEscapeAndModifiedKeys() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        #expect(
            store.preferences.setEssentials([
                Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
            ]))
        viewModel.isDenMode = true
        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)
        let modified = try keyEvent(
            characters: "x", charactersIgnoringModifiers: "x", modifiers: [.command], keyCode: 7)

        #expect(KeyboardController.handle(prefix, store: store, viewModel: viewModel))
        #expect(KeyboardController.handle(escape, store: store, viewModel: viewModel))
        #expect(viewModel.temporaryContext == nil)
        #expect(viewModel.isDenMode)

        #expect(KeyboardController.handle(prefix, store: store, viewModel: viewModel))
        #expect(KeyboardController.handle(modified, store: store, viewModel: viewModel))
        #expect(viewModel.temporaryContext == nil)
        #expect(viewModel.isDenMode)
        #expect(store.latestFeedback == nil)
    }

    @Test func zmxSessionsEscapeClosesPanel() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.preferences.setZmxPath("/missing/zmx")
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)

        viewModel.showZmxSessions()

        #expect(viewModel.isZmxSessionsPresented)
        #expect(
            KeyboardController.decision(for: escape, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.hide)))
        #expect(KeyboardController.handle(escape, store: store, viewModel: viewModel))
        #expect(!viewModel.isZmxSessionsPresented)
    }

    @Test func zmxSessionsArrowSelectionAndActionsUseTheFocusedSession() async throws {
        let store = try makeStore(
            terminalCommandRunner: ZmxKeyboardCommandRunner(
                responses: [
                    ["list"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "name=den\nname=den-vi\tden.root=den\n")
                ]))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.preferences.setZmxPath("/opt/homebrew/bin/zmx")
        viewModel.showZmxSessions()
        await waitForZmxSessionLoad(viewModel)

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

        #expect(viewModel.zmxSessions.selectedSessionName == "den")
        #expect(
            KeyboardController.decision(for: down, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.moveSelection(1))))
        #expect(KeyboardController.handle(down, store: store, viewModel: viewModel))
        #expect(viewModel.zmxSessions.selectedSessionName == "den-vi")
        #expect(KeyboardController.handle(upArrow, store: store, viewModel: viewModel))
        #expect(viewModel.zmxSessions.selectedSessionName == "den")
        #expect(
            KeyboardController.decision(for: jKey, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.moveSelection(1))))
        #expect(KeyboardController.handle(jKey, store: store, viewModel: viewModel))
        #expect(viewModel.zmxSessions.selectedSessionName == "den-vi")
        #expect(KeyboardController.handle(kKey, store: store, viewModel: viewModel))
        #expect(viewModel.zmxSessions.selectedSessionName == "den")
        #expect(KeyboardController.handle(space, store: store, viewModel: viewModel))
        #expect(viewModel.zmxSessions.markedSessionNames == ["den"])
        #expect(
            KeyboardController.decision(for: selectAll, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.selectAll)))
        #expect(KeyboardController.handle(selectAll, store: store, viewModel: viewModel))
        #expect(viewModel.zmxSessions.markedSessionNames == ["den", "den-vi"])
        #expect(
            KeyboardController.decision(for: escape, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.clearSelection)))
        #expect(KeyboardController.handle(escape, store: store, viewModel: viewModel))
        #expect(viewModel.zmxSessions.markedSessionNames.isEmpty)
        #expect(
            KeyboardController.decision(for: returnKey, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.openSelected)))
        #expect(
            KeyboardController.decision(for: filter, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.enterFilter)))
        #expect(KeyboardController.handle(filter, store: store, viewModel: viewModel))
        #expect(viewModel.zmxSessions.isFilterInputActive)
        #expect(
            KeyboardController.decision(for: selectAll, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.selectAll)))
        #expect(
            KeyboardController.decision(for: deleteKey, store: store, viewModel: viewModel)
                == .forward(.filterTextInput))
        #expect(
            KeyboardController.decision(for: returnKey, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.openSelected)))
        #expect(KeyboardController.handle(escape, store: store, viewModel: viewModel))
        #expect(!viewModel.zmxSessions.isFilterInputActive)
        #expect(viewModel.zmxSessions.query.isEmpty)
        #expect(
            KeyboardController.decision(for: escape, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.hide)))
        #expect(
            KeyboardController.decision(for: delete, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.deleteSelected)))
        #expect(
            KeyboardController.decision(for: deleteKey, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.deleteSelected)))
        #expect(
            KeyboardController.decision(for: reload, store: store, viewModel: viewModel)
                == .perform(.zmxSessions(.refresh)))
        #expect(KeyboardController.handle(delete, store: store, viewModel: viewModel))
        #expect(viewModel.zmxSessions.pendingDeletion == ["den"])
        #expect(
            KeyboardController.decision(for: returnKey, store: store, viewModel: viewModel)
                == .forward(.temporaryTextInput))
    }

    @Test func denModeGPrefixPreservesEssentialKeyCase() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let lowercase = Essential(name: "Lowercase", key: "c", input: "https://example.com/lower")
        let uppercase = Essential(name: "Uppercase", key: "C", input: "https://example.com/upper")
        #expect(store.preferences.setEssentials([lowercase, uppercase]))
        viewModel.isDenMode = true

        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let lowercaseKey = try keyEvent(
            characters: "c", charactersIgnoringModifiers: "c", keyCode: 8)
        let uppercaseKey = try keyEvent(
            characters: "C", charactersIgnoringModifiers: "c", modifiers: [.shift], keyCode: 8)

        #expect(KeyboardController.handle(prefix, store: store, viewModel: viewModel))
        #expect(
            KeyboardController.decision(for: lowercaseKey, store: store, viewModel: viewModel)
                == .perform(.essentials(.launch(lowercase.id))))
        #expect(
            KeyboardController.decision(for: uppercaseKey, store: store, viewModel: viewModel)
                == .perform(.essentials(.launch(uppercase.id))))
        #expect(KeyboardController.handle(uppercaseKey, store: store, viewModel: viewModel))
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://example.com/upper"))
    }

    @Test func denModeGPrefixCanLaunchTerminalEssential() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        #expect(
            store.preferences.setEssentials([
                Essential(name: "Terminal", key: "t", input: ":terminal \(directory)")
            ]))
        viewModel.isDenMode = true

        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let key = try keyEvent(
            characters: "t", charactersIgnoringModifiers: "t", keyCode: 17)

        #expect(KeyboardController.handle(prefix, store: store, viewModel: viewModel))
        #expect(KeyboardController.handle(key, store: store, viewModel: viewModel))
        #expect(store.focusedBoard?.terminalWorkingDirectory == directory)
        #expect(!viewModel.isDenMode)
    }

    @Test func commandShortcutRemainsOutsideEssentialsPrefix() throws {
        let preferences = try makePreferences()
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        #expect(
            store.preferences.setEssentials([
                Essential(name: "Terminal", key: "t", input: ":terminal")
            ]))
        viewModel.isDenMode = true
        let commandT = try keyEvent(
            characters: "t", charactersIgnoringModifiers: "t", modifiers: [.command], keyCode: 17)

        #expect(!KeyboardController.handle(commandT, store: store, viewModel: viewModel, preferences: preferences))
        #expect(viewModel.temporaryContext == nil)
        #expect(viewModel.isDenMode)
    }

    @Test func denModeUnmappedKeyIsConsumedByRouter() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let unmapped = try keyEvent(
            characters: "q", charactersIgnoringModifiers: "q", modifiers: [], keyCode: 12)

        #expect(
            KeyboardController.decision(for: unmapped, store: store, viewModel: viewModel)
                == .consume(.denModeUnmapped))
    }

    @Test func hardReloadCurrentSheetShortcutReloadsOnlyFocusedBoard() throws {
        let first = board("First")
        let second = board("Second")
        let store = try makeStore(boards: [first, second])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let reload = try keyEvent(
            characters: "R",
            charactersIgnoringModifiers: "r",
            modifiers: [.command, .shift],
            keyCode: 15)

        #expect(KeyboardController.handle(reload, store: store, viewModel: viewModel))
        #expect(Set(store.webRuntimes.keys) == Set([first.id]))
        #expect(store.focusedDesk?.focusedBoardID == first.id)
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
        let store = DenStore(
            state: DenState(
                desks: [firstDesk, secondDesk],
                focusedDeskID: firstDesk.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let reload = try keyEvent(
            characters: "R",
            charactersIgnoringModifiers: "r",
            modifiers: [.command, .option, .shift],
            keyCode: 15)

        #expect(KeyboardController.handle(reload, store: store, viewModel: viewModel))
        #expect(Set(store.webRuntimes.keys) == Set([first.id, second.id]))
        #expect(store.focusedDesk?.id == firstDesk.id)
        #expect(store.state.desks.map(\.id) == [firstDesk.id, secondDesk.id])
    }

    @Test func denModeEOpensFocusedBoardLinkEditor() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let editLink = try keyEvent(characters: "e", charactersIgnoringModifiers: "e", keyCode: 14)

        #expect(KeyboardController.handle(editLink, store: store, viewModel: viewModel))
        #expect(viewModel.isEditBoardLinkPanelPresented)
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
        let store = try makeStore(boards: [source])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(KeyboardController.handle(shiftReturn, store: store, viewModel: viewModel))
        #expect(store.focusedDesk?.boards.count == 2)
        #expect(store.focusedBoard?.currentSheetURL == firstSheetURL)
        #expect(store.focusedBoard?.firstSheetURL == firstSheetURL)
        #expect(store.focusedBoard?.customLabel == "Pinned")
        #expect(!viewModel.isDenMode)
    }

    @Test func denModeShiftReturnDoesNothingWithoutFirstSheet() throws {
        var source = BoardState(
            label: "Legacy",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/current"),
            firstSheetURL: nil)
        source.firstSheetURL = nil
        let store = try makeStore(boards: [source])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(KeyboardController.handle(shiftReturn, store: store, viewModel: viewModel))
        #expect(store.focusedDesk?.boards.count == 1)
        #expect(viewModel.isDenMode)
    }

    @Test func denModeTTogglesSheetNavigationPauseForFocusedBoard() throws {
        let suiteName = "KeyboardSheetNavigationTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sheetNavigation = SheetNavigationManager(defaults: defaults, scriptSource: "")
        let desk = DeskState(label: "Desk", boards: [board("First")])
        let store = DenStore(
            state: DenState(desks: [desk], focusedDeskID: desk.id),
            sheetNavigation: sheetNavigation)
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let toggle = try keyEvent(characters: "t", charactersIgnoringModifiers: "t", keyCode: 17)
        let repeatedToggle = try keyEvent(
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: true,
            keyCode: 17)
        #expect(store.focusedBoard?.sheetNavigationPaused == false)
        #expect(KeyboardController.handle(toggle, store: store, viewModel: viewModel))
        #expect(store.focusedBoard?.sheetNavigationPaused == true)
        #expect(KeyboardController.handle(repeatedToggle, store: store, viewModel: viewModel))
        #expect(store.focusedBoard?.sheetNavigationPaused == true)
        #expect(KeyboardController.handle(toggle, store: store, viewModel: viewModel))
        #expect(store.focusedBoard?.sheetNavigationPaused == false)
    }

    @Test func denModeAddsSpaceGuideAndZenViewWithoutPersistedStateChanges() throws {
        let preferences = try makePreferences()
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let state = store.state

        let zen = try keyEvent(characters: "z", charactersIgnoringModifiers: "z", keyCode: 6)
        #expect(KeyboardController.handle(zen, store: store, viewModel: viewModel, preferences: preferences))
        #expect(viewModel.isZenViewPresented)
        let repeatedZen = try keyEvent(
            characters: "z", charactersIgnoringModifiers: "z", isARepeat: true, keyCode: 6)
        #expect(KeyboardController.handle(repeatedZen, store: store, viewModel: viewModel, preferences: preferences))
        #expect(viewModel.isZenViewPresented)

        let question = try keyEvent(
            characters: "?", charactersIgnoringModifiers: "/", modifiers: [.shift], keyCode: 44)
        #expect(KeyboardController.handle(question, store: store, viewModel: viewModel, preferences: preferences))
        #expect(viewModel.isKeyboardShortcutsPresented)
        let movement = try keyEvent(characters: "h", charactersIgnoringModifiers: "h", keyCode: 4)
        #expect(!KeyboardController.handle(movement, store: store, viewModel: viewModel, preferences: preferences))
        #expect(viewModel.isKeyboardShortcutsPresented)
        #expect(!KeyboardController.handle(question, store: store, viewModel: viewModel, preferences: preferences))
        #expect(viewModel.isKeyboardShortcutsPresented)
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)
        #expect(KeyboardController.handle(escape, store: store, viewModel: viewModel, preferences: preferences))
        #expect(!viewModel.isKeyboardShortcutsPresented)

        let space = try keyEvent(characters: " ", charactersIgnoringModifiers: " ", keyCode: 49)
        #expect(KeyboardController.handle(space, store: store, viewModel: viewModel, preferences: preferences))
        #expect(viewModel.isOpenBoardPanelPresented)
        #expect(store.state == state)
    }

    @Test func denModeShiftBracketsHandleFirstAndLatestSheet() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let first = try keyEvent(
            characters: "{", charactersIgnoringModifiers: "{", modifiers: [.shift], keyCode: 33)
        let latest = try keyEvent(
            characters: "}", charactersIgnoringModifiers: "}", modifiers: [.shift], keyCode: 30)

        #expect(KeyboardController.handle(first, store: store, viewModel: viewModel))
        #expect(KeyboardController.handle(latest, store: store, viewModel: viewModel))
        #expect(viewModel.isDenMode)
    }

    @Test func denModePOpensDeskPresetPanelOnlyForDeskWithBoards() throws {
        let save = try keyEvent(characters: "p", charactersIgnoringModifiers: "p", keyCode: 35)
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true

        #expect(KeyboardController.handle(save, store: store, viewModel: viewModel))
        #expect(viewModel.isSaveDeskPresetPanelPresented)

        let empty = try makeStore(boards: [])
        let emptyViewModel = DenViewModel(store: empty)
        emptyViewModel.connect()
        defer { emptyViewModel.disconnect() }
        emptyViewModel.isDenMode = true
        #expect(KeyboardController.handle(save, store: empty, viewModel: emptyViewModel))
        #expect(!emptyViewModel.isSaveDeskPresetPanelPresented)
    }

    @Test func denModeShiftPOpensDeskReplacement() throws {
        let replace = try keyEvent(
            characters: "P", charactersIgnoringModifiers: "p", modifiers: [.shift], keyCode: 35)
        let store = try makeStore(boards: [])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true

        #expect(KeyboardController.handle(replace, store: store, viewModel: viewModel))
        #expect(viewModel.isReplaceDeskPanelPresented)
        #expect(viewModel.isNewDeskPanelPresented)
        #expect(!viewModel.isDeskPresetManagementPresented)
    }

    @Test func denModeBHasNoPresetAction() throws {
        let legacy = try keyEvent(characters: "b", charactersIgnoringModifiers: "b", keyCode: 11)
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true

        #expect(KeyboardController.handle(legacy, store: store, viewModel: viewModel))
        #expect(!viewModel.isSaveDeskPresetPanelPresented)
        #expect(!viewModel.isDeskPresetManagementPresented)
    }

    @Test func presetConfirmationsSuspendBoardRemovalShortcuts() throws {
        let commandW = try keyEvent(
            characters: "w", charactersIgnoringModifiers: "w", modifiers: [.command], keyCode: 13)
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        #expect(store.saveFocusedDeskAsPreset(label: "Routine") == .created)
        #expect(store.saveFocusedDeskAsPreset(label: "Routine") == .replacementPending)
        #expect(!KeyboardController.handle(commandW, store: store, viewModel: viewModel))
        #expect(store.focusedDesk?.boards.count == 1)

        viewModel.cancelDeskPresetReplacement()
        let presetID = try #require(store.deskPresets.first?.id)
        store.requestDeskPresetDeletion(presetID)
        #expect(!KeyboardController.handle(commandW, store: store, viewModel: viewModel))
        #expect(store.focusedDesk?.boards.count == 1)
    }

    @Test func fullscreenBypassesAllShortcutsAndClearsDenMode() throws {
        let store = try makeStore(boards: [board("First")])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true

        store.updateFullscreenStatus(boardID: BoardID(), isFullscreen: true)
        #expect(!viewModel.isDenMode)
        #expect(viewModel.isFullscreenActive)

        let commandW = try keyEvent(
            characters: "w", charactersIgnoringModifiers: "w", modifiers: [.command], keyCode: 13)
        #expect(!KeyboardController.handle(commandW, store: store, viewModel: viewModel))
    }

    @Test func denModeAKeepsFocusedSheetInDrawer() throws {
        let focused = board("Focused", url: "https://drawer.example/")
        let store = try makeStore(boards: [focused])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true

        let keep = try keyEvent(
            characters: "a",
            charactersIgnoringModifiers: "a",
            keyCode: 0)

        #expect(KeyboardController.handle(keep, store: store, viewModel: viewModel))
        #expect(store.state.drawerItems.first?.url == URL(string: "https://drawer.example/"))
        #expect(!viewModel.isDrawerOpen)
    }

    private func makePreferences() throws -> AppPreferences {
        let defaults = try #require(TestUserDefaults(suiteName: "KeyboardShortcutTests-\(UUID())"))
        return AppPreferences(defaults: defaults)
    }

    private func makeStore(
        desks: [DeskState]? = nil,
        boards: [BoardState] = [],
        terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner()
    ) throws -> DenStore {
        let storeDesks = desks ?? [DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)]
        let defaults = try #require(TestUserDefaults(suiteName: "KeyboardShortcutStore-\(UUID())"))
        let pasteboard = NSPasteboard.withUniqueName()
        return DenStore(
            state: DenState(desks: storeDesks, focusedDeskID: storeDesks.first?.id ?? DeskID()),
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

    private func waitForZmxSessionLoad(_ viewModel: DenViewModel) async {
        await viewModel.zmxSessions.waitForRefresh()
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
