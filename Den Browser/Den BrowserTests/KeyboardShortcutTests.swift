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

        #expect(preferences.shortcut(for: .toggleDenMode) == ShortcutAction.toggleDenMode.defaultBinding)
        #expect(preferences.setShortcut(customToggle, for: .toggleDenMode) == nil)
        preferences.clearShortcut(for: .focusPreviousBoard)

        let restored = AppPreferences(defaults: defaults)
        #expect(defaults.integer(forKey: "preferences.schemaVersion") == 1)
        #expect(restored.shortcut(for: .toggleDenMode) == customToggle)
        #expect(restored.shortcut(for: .focusPreviousBoard) == nil)

        restored.resetShortcut(for: .toggleDenMode)
        #expect(restored.shortcut(for: .toggleDenMode) == ShortcutAction.toggleDenMode.defaultBinding)
        restored.resetAllShortcuts()
        #expect(restored.shortcutOverrides.isEmpty)
        #expect(restored.shortcut(for: .focusPreviousBoard) == ShortcutAction.focusPreviousBoard.defaultBinding)
    }

    @Test func shortcutValidationRejectsMissingModifierAndDuplicate() throws {
        let preferences = try makePreferences()
        let unmodified = ShortcutBinding(key: .character("a"), modifiers: [])

        #expect(preferences.setShortcut(unmodified, for: .toggleDenMode) == .invalid)
        #expect(
            preferences.setShortcut(
                ShortcutAction.focusPreviousBoard.defaultBinding,
                for: .focusNextBoard) == .conflict(.focusPreviousBoard))
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

    private func makePreferences() throws -> AppPreferences {
        let defaults = try #require(UserDefaults(suiteName: "KeyboardShortcutTests-\(UUID())"))
        return AppPreferences(defaults: defaults)
    }

    private func makeStore(boards: [BoardState]) -> DenStore {
        let desk = DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "keyboard-shortcut-tests-\(UUID())", directoryHint: .isDirectory)
            .appending(path: "den-state.json")
        return DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id), persistenceURL: url)
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
        BoardState(label: label, width: 520, currentURLString: "https://example.com/")
    }
}
