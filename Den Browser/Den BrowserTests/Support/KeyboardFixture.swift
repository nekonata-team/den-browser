import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
func makeKeyboardTestPreferences() throws -> AppPreferences {
    AppPreferences(defaults: makeTestDefaults(suiteName: "KeyboardShortcutTests-\(UUID())"))
}

@MainActor
func makeKeyboardTestSession(
    desks: [DeskState]? = nil,
    boards: [BoardState] = [],
    terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner()
) throws -> ProfileWindowSession {
    let sessionDesks = desks ?? [DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)]
    let defaults = makeTestDefaults(suiteName: "KeyboardShortcutStore-\(UUID())")
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
