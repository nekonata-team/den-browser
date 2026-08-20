import AppKit
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
struct KeyboardShortcutTests {
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

    @Test func denModeShiftDigitMovesFocusedBoardToDesk() throws {
        let movedBoard = board("Moved")
        let firstDesk = DeskState(label: "First", boards: [], focusedBoardID: nil)
        let secondDesk = DeskState(
            label: "Second",
            boards: [movedBoard],
            focusedBoardID: movedBoard.id)
        let store = DenStore(
            state: DenState(
                desks: [firstDesk, secondDesk],
                focusedDeskID: secondDesk.id))
        store.isDenMode = true

        let shiftOne = try keyEvent(
            characters: "!",
            charactersIgnoringModifiers: "!",
            modifiers: [.shift],
            keyCode: 18)

        #expect(KeyboardController.handle(shiftOne, store: store))
        #expect(store.state.focusedDeskID == firstDesk.id)
        #expect(store.focusedDesk?.focusedBoardID == movedBoard.id)
        #expect(store.state.desks[0].boards.map(\.id) == [movedBoard.id])
        #expect(!store.isDenMode)
    }

    @Test func denModeEqualsWidensFocusedBoardWithOrWithoutShift() throws {
        for (characters, modifiers) in [("=", NSEvent.ModifierFlags()), ("+", NSEvent.ModifierFlags.shift)] {
            let store = try makeStore(boards: [board("Focused")])
            store.isDenMode = true
            let event = try keyEvent(
                characters: characters,
                charactersIgnoringModifiers: "=",
                modifiers: modifiers,
                keyCode: 24)

            #expect(KeyboardController.handle(event, store: store))
            #expect(store.focusedBoard?.width == 600)
        }
    }

    @Test func sheetInputCommandOptionDigitFocusesDeskAndLeavesCommandZeroAvailable() throws {
        let movedBoard = board("Moved")
        let firstDesk = DeskState(label: "First", boards: [], focusedBoardID: nil)
        let secondDesk = DeskState(
            label: "Second",
            boards: [movedBoard],
            focusedBoardID: movedBoard.id)
        let store = DenStore(
            state: DenState(
                desks: [firstDesk, secondDesk],
                focusedDeskID: secondDesk.id))
        let preferences = try makePreferences()
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

        #expect(KeyboardController.handle(commandOptionOne, store: store, preferences: preferences))
        #expect(store.state.focusedDeskID == firstDesk.id)
        #expect(!store.isDenMode)
        #expect(!KeyboardController.handle(commandZero, store: store, preferences: preferences))
        #expect(store.state.focusedDeskID == firstDesk.id)
    }

    @Test func controlTabDeskShortcutsNavigateAndReturn() throws {
        let firstDesk = DeskState(label: "First", boards: [])
        let secondDesk = DeskState(label: "Second", boards: [])
        let thirdDesk = DeskState(label: "Third", boards: [])
        let store = DenStore(
            state: DenState(
                desks: [firstDesk, secondDesk, thirdDesk],
                focusedDeskID: firstDesk.id))
        let preferences = try makePreferences()

        let next = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.control],
            keyCode: 48)
        #expect(KeyboardController.handle(next, store: store, preferences: preferences))
        #expect(store.focusedDesk?.id == secondDesk.id)

        let previous = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.control, .shift],
            keyCode: 48)
        #expect(KeyboardController.handle(previous, store: store, preferences: preferences))
        #expect(store.focusedDesk?.id == firstDesk.id)

        let returnToPrevious = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            modifiers: [.command, .option],
            keyCode: 48)
        #expect(
            KeyboardController.handle(
                returnToPrevious,
                store: store,
                preferences: preferences))
        #expect(store.focusedDesk?.id == secondDesk.id)
    }

    @Test func denModeIOpensNotifications() throws {
        let store = try makeStore(boards: [board("Terminal")])
        store.isDenMode = true
        let open = try keyEvent(
            characters: "i",
            charactersIgnoringModifiers: "i",
            keyCode: 34)

        #expect(KeyboardController.handle(open, store: store))
        #expect(store.isNotificationListPresented)
        #expect(store.isDenMode)
    }

    @Test func notificationArrowsMoveSelectionAndReturnOpensIt() throws {
        let first = board("First")
        let second = board("Second")
        let store = try makeStore(boards: [first, second])
        store.recordNotification(title: "First", body: "Done", boardID: first.id)
        store.recordNotification(title: "Second", body: "Done", boardID: second.id)
        store.isDenMode = true
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

        #expect(KeyboardController.handle(open, store: store, preferences: preferences))
        #expect(store.selectedNotificationID == store.notifications[0].id)
        #expect(KeyboardController.handle(down, store: store, preferences: preferences))
        #expect(store.selectedNotificationID == store.notifications[1].id)
        #expect(KeyboardController.handle(enter, store: store, preferences: preferences))
        #expect(store.focusedBoard?.id == first.id)
        #expect(!store.isNotificationListPresented)
    }

    @Test func customBindingsApplyImmediatelyAndCanBeUnassigned() throws {
        let preferences = try makePreferences()
        let store = try makeStore(boards: [board("First"), board("Second")])
        let toggle = try keyEvent(
            characters: ".", charactersIgnoringModifiers: ".", modifiers: [.control], keyCode: 47)
        let defaultToggle = try keyEvent(
            characters: ",", charactersIgnoringModifiers: ",", modifiers: [.control], keyCode: 43)
        #expect(
            preferences.setShortcut(
                ShortcutBinding(key: .character("."), modifiers: [.control]),
                for: .toggleDenMode) == nil)

        #expect(!KeyboardController.handle(defaultToggle, store: store, preferences: preferences))
        #expect(KeyboardController.handle(toggle, store: store, preferences: preferences))
        #expect(store.isDenMode)

        store.exitDenMode()
        preferences.clearShortcut(for: .focusNextBoard)
        let right = try arrowEvent(.rightArrow, modifiers: [.command, .option])
        #expect(!KeyboardController.handle(right, store: store, preferences: preferences))
        #expect(store.focusedDesk?.focusedBoardID == store.focusedDesk?.boards.first?.id)
    }

    @Test func customBindingsAreSuspendedByTemporaryContexts() throws {
        let preferences = try makePreferences()
        let store = try makeStore(boards: [board("First"), board("Second")])
        let next = try arrowEvent(.rightArrow, modifiers: [.command, .option])

        store.showNewDeskPanel()
        #expect(!KeyboardController.handle(next, store: store, preferences: preferences))
        store.hideNewDeskPanel()

        store.showOverview()
        let focusedBoardID = store.focusedDesk?.focusedBoardID
        #expect(KeyboardController.handle(next, store: store, preferences: preferences))
        #expect(store.focusedDesk?.focusedBoardID == focusedBoardID)
    }

    @Test func denModeToggleRemainsAvailableInDrawer() throws {
        let preferences = try makePreferences()
        let store = try makeStore(boards: [board("First")])
        store.keepInDrawer(try #require(URL(string: "https://example.com/")))
        let previewID = store.expandedDrawerItemID
        let toggle = try keyEvent(
            characters: ",", charactersIgnoringModifiers: ",", modifiers: [.control], keyCode: 43)

        #expect(KeyboardController.handle(toggle, store: store, preferences: preferences))
        #expect(store.isDenMode)
        #expect(store.expandedDrawerItemID == previewID)

        #expect(KeyboardController.handle(toggle, store: store, preferences: preferences))
        #expect(!store.isDenMode)
        #expect(store.expandedDrawerItemID == previewID)
    }

    @Test func denModeShiftDRequestsDrawerClearConfirmation() throws {
        let store = try makeStore(boards: [board("First")])
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))
        store.isDenMode = true

        let clear = try keyEvent(
            characters: "D",
            charactersIgnoringModifiers: "d",
            modifiers: [.shift],
            keyCode: 2)

        #expect(KeyboardController.handle(clear, store: store))
        #expect(store.drawerPendingDeletionCount == 2)
        #expect(store.state.drawerItems.count == 2)
    }

    @Test func denModeShiftDDoesNothingInDrawerFilterModeOrOnRepeat() throws {
        let store = try makeStore(boards: [board("First")])
        store.keepInDrawer(try #require(URL(string: "https://example.com/")))
        store.isDenMode = true

        let clear = try keyEvent(
            characters: "D",
            charactersIgnoringModifiers: "d",
            modifiers: [.shift],
            keyCode: 2)
        store.enterDrawerFilterMode()
        #expect(!KeyboardController.handle(clear, store: store))
        #expect(!store.hasPendingConfirmation)

        store.exitDrawerFilterMode()
        let repeatClear = try keyEvent(
            characters: "D",
            charactersIgnoringModifiers: "d",
            modifiers: [.shift],
            isARepeat: true,
            keyCode: 2)
        #expect(KeyboardController.handle(repeatClear, store: store))
        #expect(!store.hasPendingConfirmation)
    }

    @Test func denModeEnterAndShiftEnterUseDistinctDuplicateActions() throws {
        let store = try makeStore(boards: [board("First")])
        store.isDenMode = true
        let returnKey = try keyEvent(
            characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(
            KeyboardController.decision(for: returnKey, store: store)
                == .perform(.duplicateBoard))
        #expect(
            KeyboardController.decision(for: shiftReturn, store: store)
                == .perform(.duplicateFirstSheet))
    }

    @Test func drawerFilterPassesShiftedCharactersToTextInput() throws {
        let store = try makeStore(boards: [board("First")])
        store.keepInDrawer(try #require(URL(string: "https://example.com/")))
        store.isDenMode = true
        store.enterDrawerFilterMode()

        let uppercase = try keyEvent(
            characters: "A",
            charactersIgnoringModifiers: "a",
            modifiers: [.shift],
            keyCode: 0)

        #expect(!KeyboardController.handle(uppercase, store: store))
        #expect(store.isDrawerFilterInputActive)
    }

    @Test func drawerFilterPassesModifiedReturnAndEscapeToTextInput() throws {
        let store = try makeStore(boards: [board("First")])
        store.keepInDrawer(try #require(URL(string: "https://example.com/")))
        store.isDenMode = true
        store.enterDrawerFilterMode()

        let modifiedReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)
        let modifiedEscape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            modifiers: [.command],
            keyCode: 53)

        #expect(!KeyboardController.handle(modifiedReturn, store: store))
        #expect(!KeyboardController.handle(modifiedEscape, store: store))
        #expect(store.isDrawerFilterInputActive)
    }

    @Test func overviewFilterUsesTwoPhaseSelection() throws {
        let first = board("First")
        let second = board("Second")
        let store = try makeStore(boards: [first, second])
        store.showOverview()

        let slash = try keyEvent(
            characters: "/",
            charactersIgnoringModifiers: "/",
            keyCode: 44)
        let returnKey = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36)

        #expect(KeyboardController.handle(slash, store: store))
        #expect(store.overviewFilterPhase == .filtering)
        store.setOverviewQuery("Second")
        #expect(store.overviewSelectionBoardID == second.id)

        #expect(KeyboardController.handle(returnKey, store: store))
        #expect(store.overviewFilterPhase == .selecting)
        #expect(store.isOverviewPresented)

        #expect(KeyboardController.handle(returnKey, store: store))
        #expect(store.overviewFilterPhase == .inactive)
        #expect(!store.isOverviewPresented)
        #expect(store.focusedBoard?.id == second.id)
    }

    @Test func overviewEscapeRequestsBoardDragCancellation() throws {
        let first = board("First")
        let store = try makeStore(boards: [first])
        store.showOverview()
        #expect(store.beginOverviewBoardDrag(first.id))

        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53)

        #expect(
            KeyboardController.decision(for: escape, store: store)
                == .perform(.requestBoardDragCancellation))
        #expect(KeyboardController.handle(escape, store: store))
        #expect(store.boardDragCancellationRequest == 1)
        #expect(store.isOverviewPresented)
    }

    @Test func denModeRemoveShortcutsChooseTheirFocusDirection() throws {
        let dBoards = [board("First"), board("Focused"), board("Last")]
        let dStore = try makeStore(boards: dBoards)
        dStore.focusBoard(dBoards[1].id)
        dStore.isDenMode = true
        let dEvent = try keyEvent(characters: "d", charactersIgnoringModifiers: "d", keyCode: 2)

        #expect(
            KeyboardController.decision(for: dEvent, store: dStore)
                == .perform(.removeBoardAndFocusNext))
        #expect(KeyboardController.handle(dEvent, store: dStore))
        #expect(dStore.focusedDesk?.boards.map(\.id) == [dBoards[0].id, dBoards[2].id])
        #expect(dStore.focusedDesk?.focusedBoardID == dBoards[2].id)

        let xBoards = [board("First"), board("Focused"), board("Last")]
        let xStore = try makeStore(boards: xBoards)
        xStore.focusBoard(xBoards[1].id)
        xStore.isDenMode = true
        let xEvent = try keyEvent(characters: "x", charactersIgnoringModifiers: "x", keyCode: 7)

        #expect(
            KeyboardController.decision(for: xEvent, store: xStore)
                == .perform(.removeBoard))
        #expect(KeyboardController.handle(xEvent, store: xStore))
        #expect(xStore.focusedDesk?.boards.map(\.id) == [xBoards[0].id, xBoards[2].id])
        #expect(xStore.focusedDesk?.focusedBoardID == xBoards[0].id)
    }

    @Test func nativeCommandShortcutsPassThroughWithoutExecuting() throws {
        let first = board("First")
        let second = board("Second")
        let store = try makeStore(boards: [first, second])
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
            #expect(!KeyboardController.handle(command, store: store))
        }
        #expect(!KeyboardController.handle(closeWindow, store: store))
        #expect(store.focusedDesk?.boards.map(\.id) == [first.id, second.id])
        #expect(store.temporaryContext == nil)
    }

    @Test func denModeCommaPerformsSettingsWithoutForwarding() throws {
        let store = try makeStore(boards: [board("First")])
        let comma = try keyEvent(
            characters: ",", charactersIgnoringModifiers: ",", modifiers: [], keyCode: 43)

        #expect(!KeyboardController.handle(comma, store: store))

        store.isDenMode = true
        #expect(KeyboardController.decision(for: comma, store: store) == .perform(.openSettings))
        var didOpenSettings = false
        let handled = KeyboardController.handle(
            comma,
            store: store,
            openSettings: { didOpenSettings = true })
        #expect(handled)
        #expect(didOpenSettings)

        store.showOverview()
        #expect(KeyboardController.handle(comma, store: store))
        #expect(KeyboardController.decision(for: comma, store: store) == .consume(.exclusiveContext))
    }

    @Test func denModeGPrefixLaunchesMatchingEssential() throws {
        let store = try makeStore(boards: [BoardState(label: "First", width: 720, currentSheetURL: nil)])
        let essential = Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
        #expect(store.preferences.setEssentials([essential]))
        store.isDenMode = true

        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let key = try keyEvent(
            characters: "c", charactersIgnoringModifiers: "c", keyCode: 8)

        #expect(
            KeyboardController.decision(for: prefix, store: store)
                == .perform(.enterEssentialsPrefix))
        #expect(KeyboardController.handle(prefix, store: store))
        #expect(store.temporaryContext == .essentialsPrefix)
        #expect(
            KeyboardController.decision(for: key, store: store)
                == .perform(.launchEssential(essential.id)))
        #expect(KeyboardController.handle(key, store: store))
        #expect(store.temporaryContext == nil)
        #expect(!store.isDenMode)
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://chatgpt.com/"))
        #expect(store.focusedBoard?.width == 720)
    }

    @Test func sheetInputEssentialsPrefixLaunchesWithoutEnteringDenMode() throws {
        let store = try makeStore(boards: [board("First")])
        let essential = Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
        #expect(store.preferences.setEssentials([essential]))
        store.showEssentialsPrefix()

        let key = try keyEvent(
            characters: "c", charactersIgnoringModifiers: "c", keyCode: 8)

        #expect(
            KeyboardController.decision(for: key, store: store)
                == .perform(.launchEssential(essential.id)))
        #expect(KeyboardController.handle(key, store: store))
        #expect(store.temporaryContext == nil)
        #expect(!store.isDenMode)
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://chatgpt.com/"))
    }

    @Test func denModeGPrefixShowsToastForUnregisteredKeys() throws {
        let store = try makeStore(boards: [board("First")])
        #expect(
            store.preferences.setEssentials([
                Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
            ]))
        store.isDenMode = true
        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let unknown = try keyEvent(
            characters: "x", charactersIgnoringModifiers: "x", keyCode: 7)

        #expect(KeyboardController.handle(prefix, store: store))
        #expect(
            KeyboardController.decision(for: unknown, store: store)
                == .perform(.showEssentialNotFound("x")))
        #expect(KeyboardController.handle(unknown, store: store))
        #expect(store.temporaryContext == nil)
        #expect(store.isDenMode)
        #expect(store.focusedDesk?.boards.count == 1)
        #expect(store.toastMessage?.message == "No Essential assigned to 'x'.")
        #expect(store.toastMessage?.style == .warning)

        let returnKey = try keyEvent(
            characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        #expect(KeyboardController.handle(prefix, store: store))
        #expect(KeyboardController.handle(returnKey, store: store))
        #expect(store.toastMessage?.message == "No Essential assigned to 'Return'.")
    }

    @Test func denModeGPrefixCancelsQuietlyForEscapeAndModifiedKeys() throws {
        let store = try makeStore(boards: [board("First")])
        #expect(
            store.preferences.setEssentials([
                Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
            ]))
        store.isDenMode = true
        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)
        let modified = try keyEvent(
            characters: "x", charactersIgnoringModifiers: "x", modifiers: [.command], keyCode: 7)

        #expect(KeyboardController.handle(prefix, store: store))
        #expect(KeyboardController.handle(escape, store: store))
        #expect(store.temporaryContext == nil)
        #expect(store.isDenMode)

        #expect(KeyboardController.handle(prefix, store: store))
        #expect(KeyboardController.handle(modified, store: store))
        #expect(store.temporaryContext == nil)
        #expect(store.isDenMode)
        #expect(store.toastMessage == nil)
    }

    @Test func zmxSessionsEscapeClosesPanel() throws {
        let initialBoard = board("First")
        let desk = DeskState(label: "Desk", boards: [initialBoard], focusedBoardID: initialBoard.id)
        let preferences = try makePreferences()
        preferences.setZmxPath("/missing/zmx")
        let store = DenStore(
            state: DenState(desks: [desk], focusedDeskID: desk.id),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences)
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)

        store.showZmxSessions()

        #expect(store.isZmxSessionsPresented)
        #expect(KeyboardController.decision(for: escape, store: store) == .perform(.hideZmxSessions))
        #expect(KeyboardController.handle(escape, store: store))
        #expect(!store.isZmxSessionsPresented)
    }

    @Test func zmxSessionsArrowSelectionAndActionsUseTheFocusedSession() async throws {
        let desk = DeskState(label: "Desk", boards: [], focusedBoardID: nil)
        let preferences = try makePreferences()
        preferences.setZmxPath("/opt/homebrew/bin/zmx")
        let store = DenStore(
            state: DenState(desks: [desk], focusedDeskID: desk.id),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences,
            terminalCommandRunner: ZmxKeyboardCommandRunner(
                responses: [
                    ["list"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "name=den\nname=den-vi\tden.root=den\n")
                ]))
        store.showZmxSessions()
        await waitForZmxSessionLoad(store)

        let down = try arrowEvent(.downArrow, modifiers: [])
        let upArrow = try arrowEvent(.upArrow, modifiers: [])
        let returnKey = try keyEvent(
            characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let delete = try keyEvent(
            characters: "\u{8}", charactersIgnoringModifiers: "\u{8}", keyCode: 51)
        let deleteKey = try keyEvent(
            characters: "x", charactersIgnoringModifiers: "x", keyCode: 7)
        let reload = try keyEvent(characters: "r", charactersIgnoringModifiers: "r", keyCode: 15)
        let filter = try keyEvent(characters: "/", charactersIgnoringModifiers: "/", keyCode: 44)
        let escape = try keyEvent(
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)

        #expect(store.zmxSessionSelectedName == "den")
        #expect(
            KeyboardController.decision(for: down, store: store)
                == .perform(.moveZmxSessionSelection(1)))
        #expect(KeyboardController.handle(down, store: store))
        #expect(store.zmxSessionSelectedName == "den-vi")
        #expect(KeyboardController.handle(upArrow, store: store))
        #expect(store.zmxSessionSelectedName == "den")
        #expect(
            KeyboardController.decision(for: returnKey, store: store)
                == .perform(.openSelectedZmxSession))
        #expect(
            KeyboardController.decision(for: filter, store: store)
                == .perform(.enterZmxSessionFilter))
        #expect(KeyboardController.handle(filter, store: store))
        #expect(store.isZmxSessionFilterInputActive)
        #expect(
            KeyboardController.decision(for: deleteKey, store: store)
                == .forward(.filterTextInput))
        #expect(KeyboardController.handle(escape, store: store))
        #expect(!store.isZmxSessionFilterInputActive)
        #expect(store.zmxSessionQuery.isEmpty)
        #expect(
            KeyboardController.decision(for: escape, store: store)
                == .perform(.hideZmxSessions))
        #expect(
            KeyboardController.decision(for: delete, store: store)
                == .perform(.deleteSelectedZmxSession))
        #expect(
            KeyboardController.decision(for: deleteKey, store: store)
                == .perform(.deleteSelectedZmxSession))
        #expect(
            KeyboardController.decision(for: reload, store: store)
                == .perform(.refreshZmxSessions))
        #expect(KeyboardController.handle(delete, store: store))
        #expect(store.zmxSessionPendingDeletion == "den")
        #expect(
            KeyboardController.decision(for: returnKey, store: store)
                == .forward(.temporaryTextInput))
    }

    @Test func denModeGPrefixPreservesEssentialKeyCase() throws {
        let store = try makeStore(boards: [board("First")])
        let lowercase = Essential(name: "Lowercase", key: "c", input: "https://example.com/lower")
        let uppercase = Essential(name: "Uppercase", key: "C", input: "https://example.com/upper")
        #expect(store.preferences.setEssentials([lowercase, uppercase]))
        store.isDenMode = true

        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let lowercaseKey = try keyEvent(
            characters: "c", charactersIgnoringModifiers: "c", keyCode: 8)
        let uppercaseKey = try keyEvent(
            characters: "C", charactersIgnoringModifiers: "c", modifiers: [.shift], keyCode: 8)

        #expect(KeyboardController.handle(prefix, store: store))
        #expect(
            KeyboardController.decision(for: lowercaseKey, store: store)
                == .perform(.launchEssential(lowercase.id)))
        #expect(
            KeyboardController.decision(for: uppercaseKey, store: store)
                == .perform(.launchEssential(uppercase.id)))
        #expect(KeyboardController.handle(uppercaseKey, store: store))
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://example.com/upper"))
    }

    @Test func denModeGPrefixCanLaunchTerminalEssential() throws {
        let store = try makeStore(boards: [board("First")])
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        #expect(
            store.preferences.setEssentials([
                Essential(name: "Terminal", key: "t", input: ":terminal \(directory)")
            ]))
        store.isDenMode = true

        let prefix = try keyEvent(
            characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        let key = try keyEvent(
            characters: "t", charactersIgnoringModifiers: "t", keyCode: 17)

        #expect(KeyboardController.handle(prefix, store: store))
        #expect(KeyboardController.handle(key, store: store))
        #expect(store.focusedBoard?.terminalWorkingDirectory == directory)
        #expect(!store.isDenMode)
    }

    @Test func commandShortcutRemainsOutsideEssentialsPrefix() throws {
        let preferences = try makePreferences()
        let store = try makeStore(boards: [board("First")])
        #expect(
            store.preferences.setEssentials([
                Essential(name: "Terminal", key: "t", input: ":terminal")
            ]))
        store.isDenMode = true
        let commandT = try keyEvent(
            characters: "t", charactersIgnoringModifiers: "t", modifiers: [.command], keyCode: 17)

        #expect(!KeyboardController.handle(commandT, store: store, preferences: preferences))
        #expect(store.temporaryContext == nil)
        #expect(store.isDenMode)
    }

    @Test func denModeUnmappedKeyIsConsumedByRouter() throws {
        let store = try makeStore(boards: [board("First")])
        store.isDenMode = true
        let unmapped = try keyEvent(
            characters: "v", charactersIgnoringModifiers: "v", modifiers: [], keyCode: 9)

        #expect(
            KeyboardController.decision(for: unmapped, store: store)
                == .consume(.denModeUnmapped))
    }

    @Test func hardReloadCurrentSheetShortcutReloadsOnlyFocusedBoard() throws {
        let first = board("First")
        let second = board("Second")
        let store = try makeStore(boards: [first, second])
        let reload = try keyEvent(
            characters: "R",
            charactersIgnoringModifiers: "r",
            modifiers: [.command, .shift],
            keyCode: 15)

        #expect(KeyboardController.handle(reload, store: store))
        #expect(Set(store.runtimes.keys) == Set([first.id]))
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
        let reload = try keyEvent(
            characters: "R",
            charactersIgnoringModifiers: "r",
            modifiers: [.command, .option, .shift],
            keyCode: 15)

        #expect(KeyboardController.handle(reload, store: store))
        #expect(Set(store.runtimes.keys) == Set([first.id, second.id]))
        #expect(store.focusedDesk?.id == firstDesk.id)
        #expect(store.state.desks.map(\.id) == [firstDesk.id, secondDesk.id])
    }

    @Test func denModeEOpensFocusedBoardLinkEditor() throws {
        let store = try makeStore(boards: [board("First")])
        store.isDenMode = true
        let editLink = try keyEvent(characters: "e", charactersIgnoringModifiers: "e", keyCode: 14)

        #expect(KeyboardController.handle(editLink, store: store))
        #expect(store.isEditBoardLinkPanelPresented)
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
        store.isDenMode = true
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(KeyboardController.handle(shiftReturn, store: store))
        #expect(store.focusedDesk?.boards.count == 2)
        #expect(store.focusedBoard?.currentSheetURL == firstSheetURL)
        #expect(store.focusedBoard?.firstSheetURL == firstSheetURL)
        #expect(store.focusedBoard?.customLabel == "Pinned")
        #expect(!store.isDenMode)
    }

    @Test func denModeShiftReturnDoesNothingWithoutFirstSheet() throws {
        var source = BoardState(
            label: "Legacy",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/current"),
            firstSheetURL: nil)
        source.firstSheetURL = nil
        let store = try makeStore(boards: [source])
        store.isDenMode = true
        let shiftReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36)

        #expect(KeyboardController.handle(shiftReturn, store: store))
        #expect(store.focusedDesk?.boards.count == 1)
        #expect(store.isDenMode)
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
        store.isDenMode = true
        let toggle = try keyEvent(characters: "t", charactersIgnoringModifiers: "t", keyCode: 17)
        let repeatedToggle = try keyEvent(
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: true,
            keyCode: 17)
        #expect(store.focusedBoard?.sheetNavigationPaused == false)
        #expect(KeyboardController.handle(toggle, store: store))
        #expect(store.focusedBoard?.sheetNavigationPaused == true)
        #expect(KeyboardController.handle(repeatedToggle, store: store))
        #expect(store.focusedBoard?.sheetNavigationPaused == true)
        #expect(KeyboardController.handle(toggle, store: store))
        #expect(store.focusedBoard?.sheetNavigationPaused == false)
    }

    @Test func denModeAddsSpaceGuideAndZenViewWithoutPersistedStateChanges() throws {
        let preferences = try makePreferences()
        let store = try makeStore(boards: [board("First")])
        store.isDenMode = true
        let state = store.state

        let zen = try keyEvent(characters: "z", charactersIgnoringModifiers: "z", keyCode: 6)
        #expect(KeyboardController.handle(zen, store: store, preferences: preferences))
        #expect(store.isZenViewPresented)
        let repeatedZen = try keyEvent(
            characters: "z", charactersIgnoringModifiers: "z", isARepeat: true, keyCode: 6)
        #expect(KeyboardController.handle(repeatedZen, store: store, preferences: preferences))
        #expect(store.isZenViewPresented)

        let question = try keyEvent(
            characters: "?", charactersIgnoringModifiers: "/", modifiers: [.shift], keyCode: 44)
        #expect(KeyboardController.handle(question, store: store, preferences: preferences))
        #expect(store.isKeyboardShortcutsPresented)
        let movement = try keyEvent(characters: "h", charactersIgnoringModifiers: "h", keyCode: 4)
        #expect(KeyboardController.handle(movement, store: store, preferences: preferences))
        #expect(store.isKeyboardShortcutsPresented)
        #expect(KeyboardController.handle(question, store: store, preferences: preferences))
        #expect(!store.isKeyboardShortcutsPresented)

        let space = try keyEvent(characters: " ", charactersIgnoringModifiers: " ", keyCode: 49)
        #expect(KeyboardController.handle(space, store: store, preferences: preferences))
        #expect(store.isOpenBoardPanelPresented)
        #expect(store.state == state)
    }

    @Test func denModeShiftBracketsHandleFirstAndLatestSheet() throws {
        let store = try makeStore(boards: [board("First")])
        store.isDenMode = true
        let first = try keyEvent(
            characters: "{", charactersIgnoringModifiers: "{", modifiers: [.shift], keyCode: 33)
        let latest = try keyEvent(
            characters: "}", charactersIgnoringModifiers: "}", modifiers: [.shift], keyCode: 30)

        #expect(KeyboardController.handle(first, store: store))
        #expect(KeyboardController.handle(latest, store: store))
        #expect(store.isDenMode)
    }

    @Test func denModePOpensDeskPresetPanelOnlyForDeskWithBoards() throws {
        let save = try keyEvent(characters: "p", charactersIgnoringModifiers: "p", keyCode: 35)
        let store = try makeStore(boards: [board("First")])
        store.isDenMode = true

        #expect(KeyboardController.handle(save, store: store))
        #expect(store.isSaveDeskPresetPanelPresented)

        let empty = try makeStore(boards: [])
        empty.isDenMode = true
        #expect(KeyboardController.handle(save, store: empty))
        #expect(!empty.isSaveDeskPresetPanelPresented)
    }

    @Test func denModeShiftPOpensDeskReplacement() throws {
        let replace = try keyEvent(
            characters: "P", charactersIgnoringModifiers: "p", modifiers: [.shift], keyCode: 35)
        let store = try makeStore(boards: [])
        store.isDenMode = true

        #expect(KeyboardController.handle(replace, store: store))
        #expect(store.isReplaceDeskPanelPresented)
        #expect(store.isNewDeskPanelPresented)
        #expect(!store.isDeskPresetManagementPresented)
    }

    @Test func denModeBHasNoPresetAction() throws {
        let legacy = try keyEvent(characters: "b", charactersIgnoringModifiers: "b", keyCode: 11)
        let store = try makeStore(boards: [board("First")])
        store.isDenMode = true

        #expect(KeyboardController.handle(legacy, store: store))
        #expect(!store.isSaveDeskPresetPanelPresented)
        #expect(!store.isDeskPresetManagementPresented)
    }

    @Test func presetConfirmationsSuspendBoardRemovalShortcuts() throws {
        let commandW = try keyEvent(
            characters: "w", charactersIgnoringModifiers: "w", modifiers: [.command], keyCode: 13)
        let store = try makeStore(boards: [board("First")])

        #expect(store.saveFocusedDeskAsPreset(label: "Routine") == .created)
        #expect(store.saveFocusedDeskAsPreset(label: "Routine") == .replacementPending)
        #expect(!KeyboardController.handle(commandW, store: store))
        #expect(store.focusedDesk?.boards.count == 1)

        store.cancelDeskPresetReplacement()
        let presetID = try #require(store.deskPresets.first?.id)
        store.requestDeskPresetDeletion(presetID)
        #expect(!KeyboardController.handle(commandW, store: store))
        #expect(store.focusedDesk?.boards.count == 1)
    }

    @Test func fullscreenBypassesAllShortcutsAndClearsDenMode() throws {
        let store = try makeStore(boards: [board("First")])
        store.isDenMode = true

        store.updateFullscreenStatus(boardID: UUID(), isFullscreen: true)
        #expect(!store.isDenMode)
        #expect(store.isFullscreenActive)

        let commandW = try keyEvent(
            characters: "w", charactersIgnoringModifiers: "w", modifiers: [.command], keyCode: 13)
        #expect(!KeyboardController.handle(commandW, store: store))
    }

    @Test func denModeAKeepsFocusedSheetInDrawer() throws {
        let focused = board("Focused", url: "https://drawer.example/")
        let store = try makeStore(boards: [focused])
        store.isDenMode = true

        let keep = try keyEvent(
            characters: "a",
            charactersIgnoringModifiers: "a",
            keyCode: 0)

        #expect(KeyboardController.handle(keep, store: store))
        #expect(store.state.drawerItems.first?.url == URL(string: "https://drawer.example/"))
        #expect(!store.isDrawerOpen)
    }

    private func makePreferences() throws -> AppPreferences {
        let defaults = try #require(TestUserDefaults(suiteName: "KeyboardShortcutTests-\(UUID())"))
        return AppPreferences(defaults: defaults)
    }

    private func makeStore(boards: [BoardState]) throws -> DenStore {
        let desk = DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)
        let defaults = try #require(TestUserDefaults(suiteName: "KeyboardShortcutStore-\(UUID())"))
        return DenStore(
            state: DenState(desks: [desk], focusedDeskID: desk.id),
            sheetNavigation: SheetNavigationManager(),
            preferences: AppPreferences(defaults: defaults))
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
        modifiers: NSEvent.ModifierFlags
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
            keyCode: keyCode)
    }

    private func board(_ label: String, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: 520, currentSheetURL: URL(string: url))
    }

    private func waitForZmxSessionLoad(_ store: DenStore) async {
        await store.zmxSessionRefreshTask?.value
    }
}

private struct ZmxKeyboardCommandRunner: TerminalCommandRunning, Sendable {
    let responses: [[String]: TerminalCommandResult]

    func run(executablePath: String, arguments: [String]) -> TerminalCommandResult? {
        responses[arguments]
    }
}
