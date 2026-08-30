import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
func withTestStore<T>(
    desks: [DeskState]? = nil,
    boards: [BoardState] = [],
    recentItems: [RecentItem] = [],
    onRecentItemsSave: (([RecentItem]) -> Bool)? = nil,
    onSave: ((DenState) -> Void)? = nil,
    terminalCommandRunner: any TerminalCommandRunning = ProcessTerminalCommandRunner(),
    body: (DenStore) throws -> T
) rethrows -> T {
    let suiteName = "DenStoreTest-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        preconditionFailure("Failed to create isolated test UserDefaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = AppPreferences(defaults: defaults)
    let storeDesks = desks ?? [DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)]
    let focusedDeskID = storeDesks.first?.id ?? UUID()
    let store = DenStore(
        state: DenState(desks: storeDesks, focusedDeskID: focusedDeskID),
        websiteDataStore: .nonPersistent(),
        sheetNavigation: SheetNavigationManager(defaults: defaults, scriptSource: ""),
        preferences: preferences,
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
    onSave: ((DenState) -> Void)? = nil,
    terminalCommandRunner: any TerminalCommandRunning = ProcessTerminalCommandRunner(),
    body: (DenStore) async throws -> T
) async rethrows -> T {
    let suiteName = "DenStoreTest-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        preconditionFailure("Failed to create isolated test UserDefaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = AppPreferences(defaults: defaults)
    let storeDesks = desks ?? [DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)]
    let focusedDeskID = storeDesks.first?.id ?? UUID()
    let store = DenStore(
        state: DenState(desks: storeDesks, focusedDeskID: focusedDeskID),
        websiteDataStore: .nonPersistent(),
        sheetNavigation: SheetNavigationManager(defaults: defaults, scriptSource: ""),
        preferences: preferences,
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
