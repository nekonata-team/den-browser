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
struct ShortcutConfigurationTests {
    @Test func shortcutOverridesPersistClearAndReset() throws {
        let suiteName = "KeyboardShortcutTests-\(UUID())"
        let defaults = makeTestDefaults(suiteName: suiteName)
        let preferences = AppPreferences(defaults: defaults)
        let customToggle = ShortcutBinding(key: .character("."), modifiers: [.control])
        let customDeskNumber = ShortcutBinding(
            key: .character("1"),
            modifiers: [.control, .option]
        )

        #expect(preferences.shortcut(for: .toggleDenMode) == ConfigurableShortcut.toggleDenMode.defaultBinding)
        #expect(
            preferences.deskNumberBinding
                == ShortcutBinding(key: .character("1"), modifiers: [.command, .option])
        )
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
            ]
        )
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
        let preferences = try makeKeyboardTestPreferences()
        let unmodified = ShortcutBinding(key: .character("a"), modifiers: [])

        #expect(preferences.setShortcut(unmodified, for: .toggleDenMode) == .invalid)
        #expect(
            preferences.setShortcut(
                ConfigurableShortcut.focusPreviousBoard.defaultBinding,
                for: .focusNextBoard
            ) == .conflict(.focusPreviousBoard)
        )
        #expect(
            preferences.setShortcut(
                ShortcutBinding(key: .character("1"), modifiers: [.command, .option]),
                for: .focusNextBoard
            ) == .conflictWithDeskNumber
        )
        #expect(
            preferences.setDeskNumberBinding(
                ShortcutBinding(key: .character("1"), modifiers: [.shift, .command, .option])
            ) == nil
        )
        #expect(
            preferences.setDeskNumberBinding(
                ShortcutBinding(key: .character("1"), modifiers: [.shift])
            ) == .invalid
        )
        preferences.clearShortcut(for: .toggleDenMode)
        #expect(preferences.shortcut(for: .toggleDenMode) == ConfigurableShortcut.toggleDenMode.defaultBinding)
    }

    @Test func unreadableAndDuplicateOverridesFallBackSafely() throws {
        let suiteName = "KeyboardShortcutCorruptionTests-\(UUID())"
        let defaults = makeTestDefaults(suiteName: suiteName)
        defaults.set(
            Data("not a property list".utf8),
            forKey: "preferences.shortcuts.actions.toggle-den-mode"
        )

        let duplicate = ShortcutOverride.assigned(
            ShortcutBinding(key: .character("b"), modifiers: [.control])
        )
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
            keyCode: 0
        )
        #expect(
            ShortcutBinding(event: letter)
                == ShortcutBinding(key: .character("a"), modifiers: [.command])
        )

        let shiftedDigit = try keyEvent(
            characters: "!",
            charactersIgnoringModifiers: "!",
            modifiers: [.shift],
            keyCode: 18
        )
        #expect(
            ShortcutBinding(event: shiftedDigit)
                == ShortcutBinding(key: .character("1"), modifiers: [.shift])
        )

        let functionCharacter = String(try #require(UnicodeScalar(NSEvent.SpecialKey.f12.rawValue)))
        let function = try keyEvent(
            characters: functionCharacter,
            charactersIgnoringModifiers: functionCharacter,
            modifiers: [.control],
            keyCode: 111
        )
        #expect(
            ShortcutBinding(event: function)
                == ShortcutBinding(key: .function(12), modifiers: [.control])
        )
        #expect(ConfigurableShortcut.moveFocusedBoardLeft.defaultBinding.displayTokens == ["⌥", "⇧", "⌘", "←"])
    }

    @Test func customBindingsApplyImmediatelyAndCanBeUnassigned() throws {
        let preferences = try makeKeyboardTestPreferences()
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First"), makeTestBoard("Second")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let toggle = try keyEvent(
            characters: ".",
            charactersIgnoringModifiers: ".",
            modifiers: [.control],
            keyCode: 47
        )
        let defaultToggle = try keyEvent(
            characters: ",",
            charactersIgnoringModifiers: ",",
            modifiers: [.control],
            keyCode: 43
        )
        #expect(
            preferences.setShortcut(
                ShortcutBinding(key: .character("."), modifiers: [.control]),
                for: .toggleDenMode
            ) == nil
        )

        #expect(
            !KeyboardController.handle(
                defaultToggle,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(
            KeyboardController.handle(
                toggle,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(windowModel.isDenMode)

        windowModel.exitDenMode()
        preferences.clearShortcut(for: .focusNextBoard)
        let right = try arrowEvent(.rightArrow, modifiers: [.command, .option])
        #expect(
            !KeyboardController.handle(
                right,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(
            session.navigation.focusedDesk?.focusedBoardID == session.navigation.focusedDesk?.boards.first?.id
        )
    }

    @Test func customBindingsAreSuspendedByTemporaryContexts() throws {
        let preferences = try makeKeyboardTestPreferences()
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First"), makeTestBoard("Second")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let next = try arrowEvent(.rightArrow, modifiers: [.command, .option])

        windowModel.showNewDeskPanel()
        #expect(
            !KeyboardController.handle(next, session: session, windowModel: windowModel, preferences: preferences)
        )
        windowModel.hideNewDeskPanel()

        windowModel.showOverview()
        let focusedBoardID = session.navigation.focusedDesk?.focusedBoardID
        #expect(
            KeyboardController.handle(next, session: session, windowModel: windowModel, preferences: preferences)
        )
        #expect(session.navigation.focusedDesk?.focusedBoardID == focusedBoardID)
    }
}
