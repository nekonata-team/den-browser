import DenModels
import Observation
import Synchronization
import Testing

@testable import Den_Browser

@MainActor
struct PreferencesPresentationTests {
    @Test func appearanceAndShortcutModelsReadTheExistingObservableOwner() {
        let preferences = AppPreferences(defaults: makeTestDefaults())
        let otherPreferences = AppPreferences(defaults: makeTestDefaults())
        let first = AppearanceModel(preferences: preferences)
        let second = AppearanceModel(preferences: preferences)
        let changed = Mutex(false)
        withObservationTracking {
            _ = second.sheetScale
        } onChange: {
            changed.withLock { $0 = true }
        }

        first.setSheetScale(125)
        #expect(preferences.sheetScale == 125)
        #expect(second.sheetScale == 125)
        #expect(otherPreferences.sheetScale == AppPreferences.defaultSheetScale)
        #expect(changed.withLock { $0 })

        let shortcuts = ShortcutSettingsModel(preferences: preferences)
        let replacement = ShortcutBinding(key: .character("k"), modifiers: [.control, .option])
        #expect(shortcuts.setShortcut(replacement, for: .focusNextBoard) == nil)
        #expect(preferences.shortcut(for: .focusNextBoard) == replacement)
        preferences.resetShortcut(for: .focusNextBoard)
        #expect(shortcuts.shortcut(for: .focusNextBoard) == ConfigurableShortcut.focusNextBoard.defaultBinding)
    }
}
