import AppKit
import DenDomain
import DenPresentation
import Foundation
import Observation
import Synchronization
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenControllerDrawerTests {
    @Test func drawerModelKeepsLiveInputsObservable() throws {
        let item = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let source = desk("Desk")
        let store = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        let itemChanged = Mutex(false)
        let styleChanged = Mutex(false)

        withObservationTracking {
            _ = windowModel.drawer.filteredItems
        } onChange: {
            itemChanged.withLock { $0 = true }
        }
        withObservationTracking {
            _ = windowModel.drawer.isBottomStyle
        } onChange: {
            styleChanged.withLock { $0 = true }
        }

        store.keepInDrawer(try #require(URL(string: "https://second.example/")))
        store.preferences.toggleDrawerStyle()

        #expect(itemChanged.withLock { $0 })
        #expect(styleChanged.withLock { $0 })
    }

    @Test func drawerSelectionWrapsAtBothEnds() throws {
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let last = DrawerItem(url: try #require(URL(string: "https://last.example/")))
        let source = desk("Desk")
        let store = DenController(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [first, last]))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.drawer.selectedItemID = last.id

        windowModel.drawer.selectItem(by: 1)
        #expect(windowModel.drawer.selectedItemID == first.id)

        windowModel.drawer.selectItem(by: -1)
        #expect(windowModel.drawer.selectedItemID == last.id)
    }

    @Test func keepPreservesDeskLayoutAndOpensNewestItem() throws {
        let existingBoard = board("Existing", url: "https://desk.example/")
        let source = desk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
        var savedState: DenState?
        let store = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { savedState = $0 })
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let url = try #require(URL(string: "https://drawer.example/first"))

        store.keepInDrawer(url)

        #expect(store.focusedDesk == source)
        #expect(store.state.drawerItems.map(\.url) == [url])
        #expect(windowModel.drawer.selectedItemID == store.state.drawerItems[0].id)
        #expect(windowModel.drawer.expandedItemID == store.state.drawerItems[0].id)
        #expect(windowModel.isDrawerOpen)
        #expect(savedState == store.state)
    }

    @Test func externalURLCanOpenToRightOfFocusedBoard() throws {
        let first = board("First", width: 640)
        let focused = board("Focused", width: 880)
        let source = desk("Desk", boards: [first, focused], focusedBoardID: focused.id)
        let suiteName = "ExternalLinkDestinationTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setExternalLinkDestination(.focusedBoard)
        let store = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id),
            sheetNavigation: makeTestSheetNavigationManager(),
            preferences: preferences)
        let url = try #require(URL(string: "https://external.example/path"))

        store.handleExternalURL(url)

        #expect(store.focusedDesk?.boards.map(\.label) == ["First", "Focused", "external.example"])
        #expect(store.focusedDesk?.boards[2].width == focused.width)
        #expect(store.focusedDesk?.focusedBoardID == store.focusedDesk?.boards[2].id)
        #expect(store.state.drawerItems.isEmpty)
        #expect(store.recentItems == [.url(url)])
    }

    @Test func duplicateURLsRemainDistinctAndNewestComesFirst() throws {
        let source = desk("Desk")
        let store = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let url = try #require(URL(string: "https://example.com/"))

        store.keepInDrawer(url)
        let firstID = try #require(store.state.drawerItems.first?.id)
        store.keepInDrawer(url)

        #expect(store.state.drawerItems.count == 2)
        #expect(store.state.drawerItems[0].id != firstID)
        #expect(store.state.drawerItems[1].id == firstID)
    }

    @Test func backgroundKeepPreservesCurrentPreviewSelection() throws {
        let source = desk("Desk")
        let currentItem = DrawerItem(url: try #require(URL(string: "https://current.example/")))
        let store = DenController(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [currentItem]))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.drawer.selectedItemID = currentItem.id
        windowModel.drawer.expandedItemID = currentItem.id
        let runtime = store.drawerRuntime(for: currentItem)

        let backgroundURL = try #require(URL(string: "https://background.example/"))
        store.keepInDrawerInBackground(backgroundURL)

        #expect(store.state.drawerItems.map(\.url) == [backgroundURL, currentItem.url])
        #expect(windowModel.drawer.selectedItemID == currentItem.id)
        #expect(windowModel.drawer.expandedItemID == currentItem.id)
        #expect(store.drawerPreviewRuntime === runtime)
    }

    @Test func drawerPreviewPresentationIsWindowLocalAndSharedMetadataUsesLatestUpdate() throws {
        let item = DrawerItem(url: try #require(URL(string: "https://initial.example/")))
        try withSharedDrawerStores(items: [item]) { first, second in
            let firstComposition = DenWindowComposition(store: first)
            let firstWindowModel = firstComposition.model
            firstComposition.connect()
            defer { firstComposition.disconnect() }
            let secondComposition = DenWindowComposition(store: second)
            let secondWindowModel = secondComposition.model
            secondComposition.connect()
            defer { secondComposition.disconnect() }
            firstWindowModel.focusDrawerItem(item.id)
            let firstRuntime = first.drawerRuntime(for: item)

            #expect(firstWindowModel.drawer.expandedItemID == item.id)
            #expect(secondWindowModel.drawer.expandedItemID == nil)

            secondWindowModel.focusDrawerItem(item.id)
            let secondRuntime = second.drawerRuntime(for: item)
            #expect(secondWindowModel.drawer.expandedItemID == item.id)
            #expect(firstRuntime !== secondRuntime)

            let firstURL = try #require(URL(string: "https://first.example/"))
            let secondURL = try #require(URL(string: "https://second.example/"))
            firstRuntime.handleURLOrTitleChange(url: firstURL, title: "First")
            secondRuntime.handleURLOrTitleChange(url: secondURL, title: "Second")

            #expect(first.state.drawerItems[0].url == secondURL)
            #expect(first.state.drawerItems[0].title == "Second")
        }
    }

    @Test func discardingSharedItemRepairsEveryWindowPresentation() throws {
        let firstItem = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let secondItem = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        withSharedDrawerStores(items: [firstItem, secondItem]) { first, second in
            let firstComposition = DenWindowComposition(store: first)
            let firstWindowModel = firstComposition.model
            firstComposition.connect()
            defer { firstComposition.disconnect() }
            let secondComposition = DenWindowComposition(store: second)
            let secondWindowModel = secondComposition.model
            secondComposition.connect()
            defer { secondComposition.disconnect() }
            firstWindowModel.focusDrawerItem(firstItem.id)
            secondWindowModel.focusDrawerItem(firstItem.id)
            let firstRuntime = first.drawerRuntime(for: firstItem)
            let secondRuntime = second.drawerRuntime(for: firstItem)

            first.discardDrawerItem(firstItem.id)

            #expect(first.state.drawerItems.map(\.id) == [secondItem.id])
            #expect(firstWindowModel.drawer.selectedItemID == secondItem.id)
            #expect(secondWindowModel.drawer.selectedItemID == secondItem.id)
            #expect(firstWindowModel.drawer.expandedItemID == secondItem.id)
            #expect(secondWindowModel.drawer.expandedItemID == secondItem.id)
            #expect(first.drawerPreviewRuntime == nil)
            #expect(second.drawerPreviewRuntime == nil)
            #expect(firstRuntime.webView.navigationDelegate == nil)
            #expect(secondRuntime.webView.navigationDelegate == nil)
        }
    }

    @Test func clearingSharedDrawerClearsEveryWindowPresentation() throws {
        let firstItem = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let secondItem = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        withSharedDrawerStores(items: [firstItem, secondItem]) { first, second in
            let firstComposition = DenWindowComposition(store: first)
            let firstWindowModel = firstComposition.model
            firstComposition.connect()
            defer { firstComposition.disconnect() }
            let secondComposition = DenWindowComposition(store: second)
            let secondWindowModel = secondComposition.model
            secondComposition.connect()
            defer { secondComposition.disconnect() }
            firstWindowModel.focusDrawerItem(firstItem.id)
            secondWindowModel.focusDrawerItem(secondItem.id)
            _ = first.drawerRuntime(for: firstItem)
            _ = second.drawerRuntime(for: secondItem)
            first.requestDrawerClearConfirmation()

            #expect(firstWindowModel.drawerPendingDeletionCount == 2)
            firstWindowModel.confirmDrawerClear()

            #expect(first.state.drawerItems.isEmpty)
            #expect(firstWindowModel.drawer.selectedItemID == nil)
            #expect(secondWindowModel.drawer.selectedItemID == nil)
            #expect(firstWindowModel.drawer.expandedItemID == nil)
            #expect(secondWindowModel.drawer.expandedItemID == nil)
            #expect(first.drawerPreviewRuntime == nil)
            #expect(second.drawerPreviewRuntime == nil)
            #expect(!firstWindowModel.isDrawerOpen)
            #expect(!secondWindowModel.isDrawerOpen)
        }
    }

    @Test func filteringMatchesTitleHostAndURLAndKeepsSelectionInResults() throws {
        let source = desk("Desk")
        let items = [
            DrawerItem(
                url: try #require(URL(string: "https://example.com/reference")),
                title: "Swift Guide"),
            DrawerItem(url: try #require(URL(string: "https://news.example.org/releases"))),
        ]
        let store = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: items))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.drawer.selectedItemID = items[1].id

        windowModel.drawer.setQuery("swift")
        #expect(windowModel.drawer.filteredItems.map(\.id) == [items[0].id])
        #expect(windowModel.drawer.selectedItemID == items[0].id)

        windowModel.drawer.setQuery("example.org")
        #expect(windowModel.drawer.filteredItems.map(\.id) == [items[1].id])

        windowModel.drawer.setQuery("releases")
        #expect(windowModel.drawer.filteredItems.map(\.id) == [items[1].id])
    }

    @Test func closingDrawerClearsFilterState() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let store = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.toggleDrawer()
        windowModel.drawer.enterFilterMode()
        windowModel.drawer.setQuery("example")

        windowModel.closeDrawer()

        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.drawer.filterPhase == .inactive)
        #expect(windowModel.drawer.query.isEmpty)
    }

    @Test func keepCurrentSheetCopiesWithoutOpeningDrawerOrChangingBoard() {
        let existingBoard = board("Reference", url: "https://example.com/reference")
        let source = desk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
        let store = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        store.keepFocusedSheetInDrawer()

        #expect(store.focusedBoard == existingBoard)
        #expect(store.state.drawerItems.first?.url == existingBoard.currentSheetURL)
        #expect(store.state.drawerItems.first?.title == existingBoard.displayName)
        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.temporaryContext == nil)
    }

    @Test func placementCreatesFocusedBoardAndRemovesItem() throws {
        let existingBoard = board("Existing", width: 2_480)
        let source = desk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
        let store = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let url = try #require(URL(string: "https://placed.example/"))
        store.keepInDrawer(url)
        let itemID = try #require(windowModel.drawer.selectedItemID)

        windowModel.placeDrawerItemAsBoard(itemID)

        #expect(store.state.drawerItems.isEmpty)
        #expect(store.focusedDesk?.boards.map(\.currentSheetURL) == [existingBoard.currentSheetURL, url])
        #expect(store.focusedBoard?.currentSheetURL == url)
        #expect(store.focusedBoard?.width == existingBoard.width)
        #expect(store.recentItems == [.url(url)])
        #expect(store.recentlyDiscardedDrawerItems.isEmpty)
        #expect(!windowModel.isDrawerOpen)
    }

    @Test func keepAndPlaceReturnIdentifiersAndDiscardReturnsSuccess() throws {
        let source = desk("Desk")
        let store = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let url = try #require(URL(string: "https://drawer.example/item"))

        let itemID = store.keepInDrawer(url, title: "Test Item")
        #expect(itemID != nil)
        #expect(store.state.drawerItems.first?.id == itemID)

        let placedBoardID = store.placeDrawerItemAsBoard(try #require(itemID))
        #expect(placedBoardID != nil)
        #expect(store.focusedBoard?.id == placedBoardID)
        #expect(store.state.drawerItems.isEmpty)

        let secondURL = try #require(URL(string: "https://drawer.example/discard-me"))
        let secondItemID = try #require(store.keepInDrawer(secondURL))
        #expect(store.discardDrawerItem(secondItemID))
        #expect(!store.discardDrawerItem(secondItemID))
    }

    @Test func discardingSelectedItemSelectsItsNeighborAndClosesWhenEmpty() throws {
        let source = desk("Desk")
        let store = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))

        windowModel.drawer.discardSelectedItem()

        #expect(store.state.drawerItems.count == 1)
        #expect(windowModel.drawer.selectedItemID == store.state.drawerItems[0].id)
        #expect(windowModel.isDrawerOpen)

        windowModel.drawer.discardSelectedItem()

        #expect(store.state.drawerItems.isEmpty)
        #expect(store.recentlyDiscardedDrawerItems.count == 2)
        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.drawer.selectedItemID == nil)
    }

    @Test func discardHistoryIsTransientAndResetClearsIt() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://discarded.example/")))
        var savedState: DenState?
        let store = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]),
            onSave: { savedState = $0 })

        store.discardDrawerItem(item.id)

        #expect(store.recentlyDiscardedDrawerItems.map(\.id) == [item.id])
        let restoredStore = DenController(state: try #require(savedState))
        #expect(restoredStore.recentlyDiscardedDrawerItems.isEmpty)

        store.restoreRecentlyDiscardedDrawerItem()
        store.resetDen()
        #expect(store.recentlyDiscardedDrawerItems.isEmpty)
    }

    @Test func discardHistoryKeepsAtMostTenItemsAndRestoresNewestFirst() throws {
        let source = desk("Desk")
        let items = try (0..<12).map { index in
            DrawerItem(url: try #require(URL(string: "https://drawer-\(index).example/")))
        }
        let store = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: items))

        for item in items.prefix(11) {
            store.discardDrawerItem(item.id)
        }

        #expect(store.state.drawerItems.map(\.id) == [items[11].id])
        #expect(store.recentlyDiscardedDrawerItems.count == DenController.maximumRecentlyDiscardedDrawerItemCount)
        #expect(
            store.recentlyDiscardedDrawerItems.map(\.id)
                == Array(items[1...10].reversed()).map(\.id))

        for _ in 0..<DenController.maximumRecentlyDiscardedDrawerItemCount {
            store.restoreRecentlyDiscardedDrawerItem()
        }

        #expect(store.recentlyDiscardedDrawerItems.isEmpty)
        #expect(store.state.drawerItems.map(\.id) == Array(items[1...11]).map(\.id))
    }

    @Test func discardingExpandedItemDisposesItsPreviewRuntime() throws {
        let source = desk("Desk")
        let store = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://preview.example/")))
        let item = try #require(windowModel.drawer.selectedItem)
        let runtime = store.drawerRuntime(for: item)

        store.discardDrawerItem(item.id)

        #expect(store.drawerPreviewRuntime == nil)
        #expect(runtime.webView.navigationDelegate == nil)
        #expect(runtime.webView.uiDelegate == nil)
    }

    @Test func discardingExpandedItemOpensFollowingPreview() throws {
        let source = desk("Desk")
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        let third = DrawerItem(url: try #require(URL(string: "https://third.example/")))
        let store = DenController(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [first, second, third]))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.toggleDrawer()
        windowModel.drawer.toggleItem(second.id)
        store.discardDrawerItem(second.id)

        #expect(store.state.drawerItems.map(\.id) == [first.id, third.id])
        #expect(windowModel.drawer.selectedItemID == third.id)
        #expect(windowModel.drawer.expandedItemID == third.id)
        #expect(windowModel.isDrawerOpen)
    }

    @Test func discardingLastExpandedItemOpensPreviousPreview() throws {
        let source = desk("Desk")
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        let store = DenController(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [first, second]))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.toggleDrawer()
        windowModel.drawer.toggleItem(second.id)
        store.discardDrawerItem(second.id)

        #expect(store.state.drawerItems.map(\.id) == [first.id])
        #expect(windowModel.drawer.selectedItemID == first.id)
        #expect(windowModel.drawer.expandedItemID == first.id)
    }

    @Test func placementDoesNotAdvanceToAnotherDrawerPreview() throws {
        let source = desk("Desk")
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        let store = DenController(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [first, second]))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.toggleDrawer()
        windowModel.drawer.toggleItem(second.id)
        windowModel.placeDrawerItemAsBoard(second.id)

        #expect(store.state.drawerItems.map(\.id) == [first.id])
        #expect(windowModel.drawer.expandedItemID == nil)
        #expect(!windowModel.isDrawerOpen)
    }

    @Test func clearingDrawerRequiresConfirmationAndDisposesAllItems() throws {
        let source = desk("Desk")
        let store = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))
        _ = store.drawerRuntime(for: try #require(windowModel.drawer.selectedItem))

        store.requestDrawerClearConfirmation()

        #expect(store.state.drawerItems.count == 2)
        #expect(windowModel.drawerPendingDeletionCount == 2)

        windowModel.confirmDrawerClear()

        #expect(store.state.drawerItems.isEmpty)
        #expect(windowModel.drawerPendingDeletionCount == nil)
        #expect(windowModel.drawer.selectedItemID == nil)
        #expect(windowModel.drawer.expandedItemID == nil)
        #expect(store.drawerPreviewRuntime == nil)
        #expect(store.recentlyDiscardedDrawerItems.count == 2)
        #expect(!windowModel.isDrawerOpen)
    }

    @Test func emptyDrawerStaysOmittedFromPersistence() throws {
        let source = desk("Desk")
        let state = DenState(desks: [source], focusedDeskID: source.id)
        let encoded = try JSONEncoder().encode(state)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(object["drawerItems"] == nil)
        #expect(object["expandedDrawerItemID"] == nil)
        let decoded = try JSONDecoder().decode(DenState.self, from: encoded)
        #expect(decoded.drawerItems.isEmpty)
    }

    @Test func closingDrawerKeepsExpandedPreviewForNextOpen() throws {
        let source = desk("Desk")
        var savedState: DenState?
        let store = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { savedState = $0 })
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://preview.example/")))
        let itemID = try #require(windowModel.drawer.expandedItemID)

        windowModel.drawer.toggleItem(itemID)

        #expect(savedState == store.state)

        windowModel.drawer.toggleItem(itemID)

        #expect(savedState == store.state)
        let item = try #require(windowModel.drawer.selectedItem)
        let runtime = store.drawerRuntime(for: item)

        windowModel.closeDrawer()

        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == itemID)
        #expect(store.drawerPreviewRuntime === runtime)
        #expect(savedState == store.state)

        windowModel.toggleDrawer()

        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == itemID)
        #expect(store.drawerRuntime(for: item) === runtime)

        windowModel.drawer.toggleItem(itemID)

        #expect(store.drawerPreviewRuntime == nil)
    }

    @Test func denModeKeyboardControlsOpenDrawer() throws {
        let source = desk("Desk")
        let store = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))
        windowModel.isDenMode = true

        #expect(
            KeyboardController.handle(try keyEvent(.downArrow, keyCode: 125), store: store, windowModel: windowModel))
        #expect(windowModel.drawer.selectedItemID == store.state.drawerItems[1].id)
        #expect(windowModel.drawer.expandedItemID == store.state.drawerItems[1].id)
        #expect(
            KeyboardController.handle(
                try keyEvent(.carriageReturn, keyCode: 36), store: store, windowModel: windowModel))
        #expect(windowModel.drawer.expandedItemID == nil)
        #expect(KeyboardController.handle(try keyEvent(.tab, keyCode: 48), store: store, windowModel: windowModel))
        #expect(!windowModel.isDrawerOpen)

        windowModel.toggleDrawer()

        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == nil)
    }

    @Test func openingDrawerExitsDenModeOnlyForExpandedPreview() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let store = DenController(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [item]))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.isDenMode = true
        windowModel.openDrawer()
        #expect(windowModel.isDenMode)

        windowModel.closeDrawer()
        windowModel.drawer.toggleItem(item.id)
        windowModel.isDenMode = true
        windowModel.openDrawer()
        #expect(!windowModel.isDenMode)
    }

    @Test func slashSearchAndReturnToggleFilteredSelectionPreview() throws {
        let source = desk("Desk")
        let first = DrawerItem(
            url: try #require(URL(string: "https://first.example/")),
            title: "First")
        let second = DrawerItem(
            url: try #require(URL(string: "https://second.example/")),
            title: "Second")
        let store = DenController(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [first, second]))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        windowModel.toggleDrawer()

        #expect(KeyboardController.handle(try keyEvent("/", keyCode: 44), store: store, windowModel: windowModel))
        #expect(windowModel.drawer.filterPhase == .filtering)

        windowModel.drawer.setQuery("second")
        #expect(windowModel.drawer.selectedItemID == second.id)
        #expect(
            KeyboardController.handle(
                try keyEvent(.carriageReturn, keyCode: 36), store: store, windowModel: windowModel))
        #expect(windowModel.drawer.filterPhase == .selecting)
        #expect(windowModel.drawer.expandedItemID == nil)

        #expect(
            KeyboardController.handle(
                try keyEvent(.carriageReturn, keyCode: 36), store: store, windowModel: windowModel))
        #expect(windowModel.drawer.filterPhase == .inactive)
        #expect(windowModel.drawer.expandedItemID == second.id)
        #expect(windowModel.drawer.query.isEmpty)
        #expect(!windowModel.isDenMode)

        #expect(KeyboardController.handle(try keyEvent("\u{1B}", keyCode: 53), store: store, windowModel: windowModel))
        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == second.id)
    }

    @Test func drawerFilterKeepsSelectingPhaseWhenThereAreNoMatches() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let store = DenController(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [item]))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        windowModel.toggleDrawer()
        windowModel.drawer.enterFilterMode()
        windowModel.drawer.setQuery("missing")
        windowModel.drawer.confirmFilterQuery()

        #expect(windowModel.drawer.filterPhase == .selecting)
        #expect(windowModel.drawer.selectedItemID == nil)
        windowModel.drawer.confirmFilterSelection()
        #expect(windowModel.drawer.filterPhase == .selecting)
        #expect(windowModel.drawer.query == "missing")

        windowModel.drawer.exitFilterMode()
        #expect(windowModel.drawer.filterPhase == .inactive)
        #expect(windowModel.drawer.query.isEmpty)
    }

    @Test func denModeKeyboardControlsDiscardDrawerItemWithXAndD() throws {
        let source = desk("Desk")
        let store = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))
        store.keepInDrawer(try #require(URL(string: "https://third.example/")))
        store.keepInDrawer(try #require(URL(string: "https://fourth.example/")))
        windowModel.isDenMode = true
        let itemIDs = store.state.drawerItems.map(\.id)
        windowModel.drawer.selectItem(by: 2)

        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.selectedItemID == itemIDs[2])
        #expect(KeyboardController.handle(try keyEvent("x", keyCode: 7), store: store, windowModel: windowModel))
        #expect(store.state.drawerItems.map(\.id) == [itemIDs[0], itemIDs[1], itemIDs[3]])
        #expect(windowModel.drawer.selectedItemID == itemIDs[1])
        #expect(KeyboardController.handle(try keyEvent("d", keyCode: 2), store: store, windowModel: windowModel))
        #expect(store.state.drawerItems.map(\.id) == [itemIDs[0], itemIDs[3]])
        #expect(windowModel.drawer.selectedItemID == itemIDs[3])
        #expect(windowModel.isDrawerOpen)
    }

    @Test func denModeKeyboardRestoresNewestDiscardedDrawerItemWithU() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://restore.example/")))
        let store = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))

        let composition = DenWindowComposition(store: store)

        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.openDrawer()
        windowModel.isDenMode = true
        store.discardDrawerItem(item.id)
        windowModel.openDrawer()
        windowModel.isDenMode = true

        #expect(KeyboardController.handle(try keyEvent("u", keyCode: 32), store: store, windowModel: windowModel))
        #expect(store.state.drawerItems.map(\.id) == [item.id])
        #expect(store.recentlyDiscardedDrawerItems.isEmpty)
        #expect(windowModel.drawer.selectedItemID == item.id)
        #expect(windowModel.drawer.expandedItemID == item.id)
        #expect(windowModel.isDenMode)
    }

    @Test func sheetInputLeavesVimStyleDrawerKeysUnclaimed() throws {
        let source = desk("Desk")
        let store = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))

        #expect(store.state.drawerItems.count == 2)
        #expect(windowModel.isDrawerOpen)
        #expect(!windowModel.isDenMode)

        for (key, keyCode) in [("d", 2), ("x", 7), ("j", 38), ("k", 40), ("p", 35), ("/", 44)] {
            let event = try keyEvent(key, keyCode: UInt16(keyCode))
            #expect(
                KeyboardController.decision(for: event, store: store, windowModel: windowModel)
                    == .consume(.exclusiveContext))
            #expect(KeyboardController.handle(event, store: store, windowModel: windowModel))
        }
        let tab = try keyEvent(.tab, keyCode: 48)
        #expect(
            KeyboardController.decision(for: tab, store: store, windowModel: windowModel)
                == .consume(.exclusiveContext))
        #expect(KeyboardController.handle(tab, store: store, windowModel: windowModel))
        #expect(store.state.drawerItems.count == 2)
        #expect(windowModel.isDrawerOpen)
    }

    private func keyEvent(_ specialKey: NSEvent.SpecialKey, keyCode: UInt16) throws -> NSEvent {
        let scalar = try #require(UnicodeScalar(specialKey.rawValue))
        return try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: String(scalar),
                charactersIgnoringModifiers: String(scalar),
                isARepeat: false,
                keyCode: keyCode
            ))
    }

    private func keyEvent(_ character: String, keyCode: UInt16) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: keyCode
            ))
    }

    private func board(_ label: String, width: Double = 520, url: String? = nil) -> BoardState {
        BoardState(
            label: label,
            width: width,
            currentSheetURL: url.flatMap(URL.init(string:)))
    }

    private func desk(
        _ label: String,
        boards: [BoardState] = [],
        focusedBoardID: BoardID? = nil
    ) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func withSharedDrawerStores<T>(
        items: [DrawerItem],
        body: (DenController, DenController) throws -> T
    ) rethrows -> T {
        let suiteName = "SharedDrawerStoreTests-\(UUID())"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Failed to create isolated test UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let desks = [desk("First"), desk("Second")]
        let storage = DenProfileResources(
            state: DenState(
                desks: desks,
                focusedDeskID: desks[0].id,
                drawerItems: items))
        let websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let sheetNavigation = SheetNavigationManager(defaults: defaults, scriptSource: "")
        let preferences = AppPreferences(defaults: defaults)
        let makeStore = { (deskID: DeskID) -> DenController in
            DenController(
                storage: storage,
                presentedDeskID: deskID,
                websiteDataStore: websiteDataStore,
                sheetNavigation: sheetNavigation,
                preferences: preferences,
                canPresentDesk: { _ in true },
                onDeskPresentationRequest: { _ in true },
                onWillResetDen: {})
        }
        return try body(makeStore(desks[0].id), makeStore(desks[1].id))
    }
}
