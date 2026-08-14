import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct DenStoreRecentTests {
    @Test func openBoardStoresAndReusesRecentItemsInMostRecentOrder() throws {
        let source = desk("Desk")
        var savedItems: [RecentItem] = []
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            recentItems: [],
            onSave: nil,
            onRecentItemsSave: {
                savedItems = $0
                return true
            })

        store.openBoard(input: "example.com")
        store.openBoard(input: "Swift Observation")
        store.openBoard(input: "https://EXAMPLE.com/")

        #expect(
            store.recentItems == [
                .url(try #require(URL(string: "https://EXAMPLE.com/"))),
                .search("Swift Observation"),
            ])
        #expect(savedItems == store.recentItems)
    }

    @Test func recentSearchDeduplicationIgnoresCaseAndRepeatedWhitespace() {
        let source = desk("Desk")
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            recentItems: [],
            onSave: nil,
            onRecentItemsSave: { _ in true })

        store.openBoard(input: "Swift   Observation")
        store.openBoard(input: "swift observation")

        #expect(store.recentItems == [.search("swift observation")])
    }

    @Test func recentKeepsOneHundredItemsAndClearPersists() {
        let source = desk("Desk")
        var savedItems: [RecentItem] = []
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            recentItems: [],
            onSave: nil,
            onRecentItemsSave: {
                savedItems = $0
                return true
            })

        for index in 0...100 {
            store.openBoard(input: "https://example.com/\(index)")
        }

        #expect(store.recentItems.count == 100)
        #expect(store.recentItems.first == .url(URL(string: "https://example.com/100")!))
        #expect(store.recentItems.last == .url(URL(string: "https://example.com/1")!))

        store.clearRecent()

        #expect(store.recentItems.isEmpty)
        #expect(savedItems.isEmpty)
    }

    @Test func failedRecentSaveRestoresItemsWithoutBlockingBoardCreation() {
        let source = desk("Desk")
        let original: [RecentItem] = [.search("existing")]
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            recentItems: original,
            onSave: nil,
            onRecentItemsSave: { _ in false })

        store.openBoard(input: "new search")

        #expect(store.recentItems == original)
        #expect(store.focusedDesk?.boards.count == 1)
    }

    @Test func terminalAndZellijInputsBecomeRecentItems() throws {
        let source = desk("Desk")
        let suiteName = "DenStoreRecentTerminalTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setZellijPath("/opt/homebrew/bin/zellij")
        preferences.setZmxPath("/opt/homebrew/bin/zmx")
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences)
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path

        store.openBoard(input: ":terminal")
        store.openBoard(input: ":terminal ~")
        store.openBoard(input: ":terminal \(directory)")
        store.openBoard(input: ":zellij")
        store.openBoard(input: ":zellij project-a")
        store.openBoard(input: ":zmx project-a")

        #expect(
            store.recentItems == [
                .zmx(sessionName: "project-a"),
                .zellij(sessionName: "project-a"),
                .zellij(sessionName: nil),
                .terminal(workingDirectory: directory),
                .terminal(workingDirectory: home),
            ])
    }

    @Test func openingTerminalRecentRevalidatesDirectoryAndMovesItToTheFront() throws {
        let source = desk("Desk")
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let item = RecentItem.terminal(workingDirectory: directory)
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            recentItems: [.search("existing"), item],
            onSave: nil,
            onRecentItemsSave: { _ in true })

        store.openBoard(recentItem: item)

        #expect(store.focusedBoard?.terminalWorkingDirectory == directory)
        #expect(store.recentItems.first == item)
    }

    @Test func missingTerminalRecentShowsErrorWithoutCreatingBoard() {
        let source = desk("Desk")
        let item = RecentItem.terminal(
            workingDirectory: "/missing/den-browser-\(UUID().uuidString)")
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            recentItems: [item],
            onSave: nil,
            onRecentItemsSave: { _ in true })

        store.openBoard(recentItem: item)

        #expect(store.focusedDesk?.boards.isEmpty == true)
        #expect(store.openBoardPanelMessage?.contains("does not exist") == true)
        #expect(store.recentItems == [item])
    }

    @Test func openingZellijRecentCreatesBoardAndMovesItToTheFront() {
        let source = desk("Desk")
        let suiteName = "DenStoreRecentZellijTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setZellijPath("/opt/homebrew/bin/zellij")
        let item = RecentItem.zellij(sessionName: "project-a")
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences,
            recentItems: [.search("existing"), item],
            onSave: nil,
            onRecentItemsSave: { _ in true })

        store.openBoard(recentItem: item)

        #expect(store.focusedBoard?.isZellij == true)
        #expect(store.focusedBoard?.zellijSessionName == "project-a")
        #expect(store.recentItems.first == item)
    }

    @Test func openingZmxRecentCreatesBoardAndMovesItToTheFront() {
        let source = desk("Desk")
        let suiteName = "DenStoreRecentZmxTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setZmxPath("/opt/homebrew/bin/zmx")
        let item = RecentItem.zmx(sessionName: "project-a")
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences,
            recentItems: [.search("existing"), item],
            onSave: nil,
            onRecentItemsSave: { _ in true })

        store.openBoard(recentItem: item)

        #expect(store.focusedBoard?.isZmx == true)
        #expect(store.focusedBoard?.zmxSessionName == "project-a")
        #expect(store.recentItems.first == item)
    }

    @Test func openingZellijRecentWithoutConfigurationShowsError() {
        let source = desk("Desk")
        let suiteName = "DenStoreRecentMissingZellijTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let item = RecentItem.zellij(sessionName: nil)
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences,
            recentItems: [item],
            onSave: nil,
            onRecentItemsSave: { _ in true })

        store.openBoard(recentItem: item)

        #expect(store.focusedDesk?.boards.isEmpty == true)
        #expect(store.openBoardPanelMessage?.contains("absolute Zellij executable path") == true)
        #expect(store.recentItems == [item])
    }

    @Test func openingZmxRecentWithoutConfigurationShowsError() {
        let source = desk("Desk")
        let suiteName = "DenStoreRecentMissingZmxTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let item = RecentItem.zmx(sessionName: "project-a")
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences,
            recentItems: [item],
            onSave: nil,
            onRecentItemsSave: { _ in true })

        store.openBoard(recentItem: item)

        #expect(store.focusedDesk?.boards.isEmpty == true)
        #expect(store.openBoardPanelMessage?.contains("absolute zmx executable path") == true)
        #expect(store.recentItems == [item])
    }

    private func desk(_ label: String) -> DeskState {
        DeskState(label: label, boards: [])
    }
}
