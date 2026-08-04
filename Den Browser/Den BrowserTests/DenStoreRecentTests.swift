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

    private func desk(_ label: String) -> DeskState {
        DeskState(label: label, boards: [])
    }
}
