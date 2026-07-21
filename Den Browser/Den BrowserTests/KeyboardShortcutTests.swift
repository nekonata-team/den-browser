import AppKit
import Foundation
import Testing
@testable import Den_Browser

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

        #expect(preferences.shortcut(for: .toggleDenMode) == ShortcutAction.toggleDenMode.defaultBinding)
        #expect(preferences.deskNumberBinding == AppPreferences.defaultDeskNumberBinding)
        #expect(preferences.setShortcut(customToggle, for: .toggleDenMode) == nil)
        #expect(preferences.setDeskNumberBinding(customDeskNumber) == nil)
        preferences.clearShortcut(for: .focusPreviousBoard)

        let restored = AppPreferences(defaults: defaults)
        #expect(defaults.integer(forKey: "preferences.schemaVersion") == 1)
        #expect(restored.shortcut(for: .toggleDenMode) == customToggle)
        #expect(restored.shortcut(for: .focusPreviousBoard) == nil)
        #expect(restored.deskNumberBinding == customDeskNumber)

        restored.resetShortcut(for: .toggleDenMode)
        #expect(restored.shortcut(for: .toggleDenMode) == ShortcutAction.toggleDenMode.defaultBinding)
        restored.clearDeskNumberBinding()
        #expect(restored.deskNumberBinding == nil)
        #expect(AppPreferences(defaults: defaults).deskNumberBinding == nil)
        restored.resetDeskNumberBinding()
        restored.resetAllShortcuts()
        #expect(restored.shortcutOverrides.isEmpty)
        #expect(restored.shortcut(for: .focusPreviousBoard) == ShortcutAction.focusPreviousBoard.defaultBinding)
        #expect(restored.deskNumberBinding == AppPreferences.defaultDeskNumberBinding)
    }

    @Test func shortcutValidationRejectsMissingModifierAndDuplicate() throws {
        let preferences = try makePreferences()
        let unmodified = ShortcutBinding(key: .character("a"), modifiers: [])

        #expect(preferences.setShortcut(unmodified, for: .toggleDenMode) == .invalid)
        #expect(
            preferences.setShortcut(
                ShortcutAction.focusPreviousBoard.defaultBinding,
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
        #expect(preferences.shortcut(for: .toggleDenMode) == ShortcutAction.toggleDenMode.defaultBinding)
    }

    @Test func unreadableAndDuplicateOverridesFallBackSafely() throws {
        let suiteName = "KeyboardShortcutCorruptionTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not a property list".utf8), forKey: "shortcuts.toggle-den-mode")

        let duplicate = ShortcutOverride.assigned(
            ShortcutBinding(key: .character("b"), modifiers: [.control]))
        let data = try PropertyListEncoder().encode(duplicate)
        defaults.set(data, forKey: "shortcuts.focus-previous-board")
        defaults.set(data, forKey: "shortcuts.focus-next-board")

        let preferences = AppPreferences(defaults: defaults)
        let effective = ShortcutAction.allCases.compactMap(preferences.shortcut)
        #expect(preferences.shortcut(for: .toggleDenMode) == ShortcutAction.toggleDenMode.defaultBinding)
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
        #expect(ShortcutAction.moveFocusedBoardLeft.defaultBinding.displayTokens == ["⌥", "⇧", "⌘", "←"])
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
        #expect(store.isDenMode)
    }

    @Test func sheetInputCommandOptionDigitFocusesDesk() throws {
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

        #expect(KeyboardController.handle(commandOptionOne, store: store, preferences: preferences))
        #expect(store.state.focusedDeskID == firstDesk.id)
        #expect(!store.isDenMode)
    }

    @Test func customBindingsApplyImmediatelyAndCanBeUnassigned() throws {
        let preferences = try makePreferences()
        let store = makeStore(boards: [board("First"), board("Second")])
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
        let store = makeStore(boards: [board("First"), board("Second")])
        let next = try arrowEvent(.rightArrow, modifiers: [.command, .option])

        store.showNewDeskPanel()
        #expect(!KeyboardController.handle(next, store: store, preferences: preferences))
        store.hideNewDeskPanel()

        store.showOverview()
        let focusedBoardID = store.focusedDesk?.focusedBoardID
        #expect(KeyboardController.handle(next, store: store, preferences: preferences))
        #expect(store.focusedDesk?.focusedBoardID == focusedBoardID)
    }

    @Test func commandWRemovesFocusedBoardAndShiftCommandWPassesToWindow() throws {
        let first = board("First")
        let second = board("Second")
        let store = makeStore(boards: [first, second])
        let closeBoard = try keyEvent(
            characters: "w", charactersIgnoringModifiers: "w", modifiers: [.command], keyCode: 13)
        let closeWindow = try keyEvent(
            characters: "W",
            charactersIgnoringModifiers: "w",
            modifiers: [.command, .shift],
            keyCode: 13)

        #expect(KeyboardController.handle(closeBoard, store: store))
        #expect(store.focusedDesk?.boards.map(\.id) == [second.id])
        #expect(!KeyboardController.handle(closeWindow, store: store))
        #expect(store.focusedDesk?.boards.map(\.id) == [second.id])
    }

    @Test func commandLOpensFocusedBoardLinkEditor() throws {
        let store = makeStore(boards: [board("First")])
        let editLink = try keyEvent(
            characters: "l", charactersIgnoringModifiers: "l", modifiers: [.command], keyCode: 37)

        #expect(KeyboardController.handle(editLink, store: store))
        #expect(store.isEditBoardLinkPanelPresented)
    }

    @Test func denModeEOpensFocusedBoardLinkEditor() throws {
        let store = makeStore(boards: [board("First")])
        store.isDenMode = true
        let editLink = try keyEvent(characters: "e", charactersIgnoringModifiers: "e", keyCode: 14)

        #expect(KeyboardController.handle(editLink, store: store))
        #expect(store.isEditBoardLinkPanelPresented)
    }

    @Test func denModeAddsSpaceGuideAndZenViewWithoutPersistedStateChanges() throws {
        let preferences = try makePreferences()
        let store = makeStore(boards: [board("First")])
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

    @Test func denModePOpensDeskPresetPanelOnlyForDeskWithBoards() throws {
        let save = try keyEvent(characters: "p", charactersIgnoringModifiers: "p", keyCode: 35)
        let store = makeStore(boards: [board("First")])
        store.isDenMode = true

        #expect(KeyboardController.handle(save, store: store))
        #expect(store.isSaveDeskPresetPanelPresented)

        let empty = makeStore(boards: [])
        empty.isDenMode = true
        #expect(KeyboardController.handle(save, store: empty))
        #expect(!empty.isSaveDeskPresetPanelPresented)
    }

    @Test func denModeShiftPOpensDeskPresetManagement() throws {
        let manage = try keyEvent(
            characters: "P", charactersIgnoringModifiers: "p", modifiers: [.shift], keyCode: 35)
        let store = makeStore(boards: [])
        store.isDenMode = true

        #expect(KeyboardController.handle(manage, store: store))
        #expect(store.isDeskPresetManagementPresented)
        #expect(store.isNewDeskPanelPresented)
    }

    @Test func denModeBHasNoPresetAction() throws {
        let legacy = try keyEvent(characters: "b", charactersIgnoringModifiers: "b", keyCode: 11)
        let store = makeStore(boards: [board("First")])
        store.isDenMode = true

        #expect(KeyboardController.handle(legacy, store: store))
        #expect(!store.isSaveDeskPresetPanelPresented)
        #expect(!store.isDeskPresetManagementPresented)
    }

    @Test func presetConfirmationsSuspendBoardRemovalShortcuts() throws {
        let commandW = try keyEvent(
            characters: "w", charactersIgnoringModifiers: "w", modifiers: [.command], keyCode: 13)
        let store = makeStore(boards: [board("First")])

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
        let store = makeStore(boards: [board("First")])
        store.isDenMode = true

        store.updateFullscreenStatus(boardID: UUID(), isFullscreen: true)
        #expect(!store.isDenMode)
        #expect(store.isFullscreenActive)

        let commandW = try keyEvent(
            characters: "w", charactersIgnoringModifiers: "w", modifiers: [.command], keyCode: 13)
        #expect(!KeyboardController.handle(commandW, store: store))
    }

    private func makePreferences() throws -> AppPreferences {
        let defaults = try #require(UserDefaults(suiteName: "KeyboardShortcutTests-\(UUID())"))
        return AppPreferences(defaults: defaults)
    }

    private func makeStore(boards: [BoardState]) -> DenStore {
        let desk = DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)
        return DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))
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

    private func board(_ label: String) -> BoardState {
        BoardState(label: label, width: 520, currentSheetURL: URL(string: "https://example.com/"))
    }
}
