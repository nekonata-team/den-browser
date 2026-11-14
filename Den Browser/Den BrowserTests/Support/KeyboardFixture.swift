import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@testable import Den_Browser

private final class InMemoryUserDefaults: UserDefaults {
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
func makeKeyboardTestPreferences() throws -> AppPreferences {
    let defaults = try #require(InMemoryUserDefaults(suiteName: "KeyboardShortcutTests-\(UUID())"))
    return AppPreferences(defaults: defaults)
}

@MainActor
func makeKeyboardTestSession(
    desks: [DeskState]? = nil,
    boards: [BoardState] = [],
    terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner()
) throws -> ProfileWindowSession {
    let sessionDesks = desks ?? [DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)]
    let defaults = try #require(InMemoryUserDefaults(suiteName: "KeyboardShortcutStore-\(UUID())"))
    let pasteboard = NSPasteboard.withUniqueName()
    return ProfileWindowSession(
        resources: DenProfileResources(
            state: DenStateNormalization.normalize(
                DenState(desks: sessionDesks, focusedDeskID: sessionDesks.first?.id ?? DeskID())
            )
        ),
        configuration: makeTestBoardRuntimeConfiguration(
            websiteDataStore: .nonPersistent(),
            sheetNavigation: SheetNavigationManager(
                defaults: defaults,
                pasteboard: pasteboard,
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: defaults),
            terminalCommandRunner: terminalCommandRunner
        ),
        pasteboard: pasteboard
    )
}
