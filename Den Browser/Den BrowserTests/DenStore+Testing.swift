import AppKit
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
func makeTestDefaults(suiteName: String = "DenBrowserTests-\(UUID().uuidString)") -> UserDefaults {
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        preconditionFailure("Failed to create isolated test defaults")
    }
    return defaults
}

@MainActor
func makeTestSheetNavigationManager(
    defaults: UserDefaults? = nil,
    scriptSource: String? = nil
) -> SheetNavigationManager {
    SheetNavigationManager(
        defaults: defaults ?? makeTestDefaults(),
        pasteboard: .withUniqueName(),
        scriptSource: scriptSource)
}

@MainActor
private func makeTestDenDependencies() -> (
    navigation: SheetNavigationManager,
    preferences: AppPreferences,
    pasteboard: NSPasteboard
) {
    let defaults = makeTestDefaults()
    let pasteboard = NSPasteboard.withUniqueName()
    return (
        SheetNavigationManager(defaults: defaults, pasteboard: pasteboard, scriptSource: ""),
        AppPreferences(defaults: defaults),
        pasteboard
    )
}

extension DenStore {
    convenience init() {
        self.init(state: .sample)
    }

    convenience init(state: DenState) {
        let dependencies = makeTestDenDependencies()
        self.init(
            state: state,
            websiteDataStore: .nonPersistent(),
            sheetNavigation: dependencies.navigation,
            preferences: dependencies.preferences,
            pasteboard: dependencies.pasteboard)
    }

    convenience init(
        state: DenState,
        sheetNavigation: SheetNavigationManager,
        preferences: AppPreferences? = nil,
        terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner()
    ) {
        self.init(
            state: state,
            websiteDataStore: .nonPersistent(),
            sheetNavigation: sheetNavigation,
            preferences: preferences ?? AppPreferences(defaults: makeTestDefaults()),
            pasteboard: sheetNavigation.pasteboard,
            terminalCommandRunner: terminalCommandRunner)
    }

    convenience init(state: DenState, onSave: @escaping (DenState) -> Void) {
        let dependencies = makeTestDenDependencies()
        self.init(
            state: state,
            websiteDataStore: .nonPersistent(),
            sheetNavigation: dependencies.navigation,
            preferences: dependencies.preferences,
            pasteboard: dependencies.pasteboard,
            onSave: { state in
                onSave(state)
                return true
            })
    }

    convenience init(state: DenState, onSaveReturningBool onSave: @escaping (DenState) -> Bool) {
        let dependencies = makeTestDenDependencies()
        self.init(
            state: state,
            websiteDataStore: .nonPersistent(),
            sheetNavigation: dependencies.navigation,
            preferences: dependencies.preferences,
            pasteboard: dependencies.pasteboard,
            onSave: onSave)
    }

    convenience init(
        state: DenState,
        deskPresets: [PersonalDeskPreset],
        onDeskPresetsSave: (([PersonalDeskPreset]) -> Bool)? = nil
    ) {
        let dependencies = makeTestDenDependencies()
        self.init(
            state: state,
            websiteDataStore: .nonPersistent(),
            sheetNavigation: dependencies.navigation,
            preferences: dependencies.preferences,
            pasteboard: dependencies.pasteboard,
            deskPresets: deskPresets,
            onDeskPresetsSave: onDeskPresetsSave)
    }
}

@MainActor
func withTestStore<T>(
    desks: [DeskState]? = nil,
    boards: [BoardState] = [],
    recentItems: [RecentItem] = [],
    onRecentItemsSave: (([RecentItem]) -> Bool)? = nil,
    onSave: ((DenState) -> Bool)? = nil,
    terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner(),
    body: (DenStore) throws -> T
) rethrows -> T {
    let suiteName = "DenStoreTest-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        preconditionFailure("Failed to create isolated test UserDefaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = AppPreferences(defaults: defaults)
    let pasteboard = NSPasteboard.withUniqueName()
    let storeDesks = desks ?? [DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)]
    let focusedDeskID = storeDesks.first?.id ?? UUID()
    let store = DenStore(
        state: DenState(desks: storeDesks, focusedDeskID: focusedDeskID),
        websiteDataStore: .nonPersistent(),
        sheetNavigation: SheetNavigationManager(defaults: defaults, pasteboard: pasteboard, scriptSource: ""),
        preferences: preferences,
        pasteboard: pasteboard,
        terminalCommandRunner: terminalCommandRunner,
        recentItems: recentItems,
        onSave: onSave,
        onRecentItemsSave: onRecentItemsSave
    )
    return try body(store)
}

@MainActor
func withTestStore<T>(
    desks: [DeskState]? = nil,
    boards: [BoardState] = [],
    recentItems: [RecentItem] = [],
    onRecentItemsSave: (([RecentItem]) -> Bool)? = nil,
    onSave: ((DenState) -> Bool)? = nil,
    terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner(),
    body: (DenStore) async throws -> T
) async rethrows -> T {
    let suiteName = "DenStoreTest-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        preconditionFailure("Failed to create isolated test UserDefaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = AppPreferences(defaults: defaults)
    let pasteboard = NSPasteboard.withUniqueName()
    let storeDesks = desks ?? [DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)]
    let focusedDeskID = storeDesks.first?.id ?? UUID()
    let store = DenStore(
        state: DenState(desks: storeDesks, focusedDeskID: focusedDeskID),
        websiteDataStore: .nonPersistent(),
        sheetNavigation: SheetNavigationManager(defaults: defaults, pasteboard: pasteboard, scriptSource: ""),
        preferences: preferences,
        pasteboard: pasteboard,
        terminalCommandRunner: terminalCommandRunner,
        recentItems: recentItems,
        onSave: onSave,
        onRecentItemsSave: onRecentItemsSave
    )
    return try await body(store)
}

@MainActor
func withStore<T>(
    desks: [DeskState],
    body: (DenStore) throws -> T
) rethrows -> T {
    try withTestStore(desks: desks, body: body)
}

@MainActor
func withStore<T>(
    desks: [DeskState],
    body: (DenStore) async throws -> T
) async rethrows -> T {
    try await withTestStore(desks: desks, body: body)
}
