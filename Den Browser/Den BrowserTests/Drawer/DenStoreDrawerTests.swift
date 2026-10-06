import AppKit
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenStoreDrawerTests {
    @Test func drawerSelectionWrapsAtBothEnds() throws {
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let last = DrawerItem(url: try #require(URL(string: "https://last.example/")))
        let source = desk("Desk")
        let store = DenStore(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [first, last]))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.drawer.selectedItemID = last.id

        viewModel.drawer.selectItem(by: 1)
        #expect(viewModel.drawer.selectedItemID == first.id)

        viewModel.drawer.selectItem(by: -1)
        #expect(viewModel.drawer.selectedItemID == last.id)
    }

    @Test func keepPreservesDeskLayoutAndOpensNewestItem() throws {
        let existingBoard = board("Existing", url: "https://desk.example/")
        let source = desk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { savedState = $0 })
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let url = try #require(URL(string: "https://drawer.example/first"))

        store.keepInDrawer(url)

        #expect(store.focusedDesk == source)
        #expect(store.state.drawerItems.map(\.url) == [url])
        #expect(viewModel.drawer.selectedItemID == store.state.drawerItems[0].id)
        #expect(viewModel.drawer.expandedItemID == store.state.drawerItems[0].id)
        #expect(viewModel.isDrawerOpen)
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
        let store = DenStore(
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
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
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
        let store = DenStore(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [currentItem]))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.drawer.selectedItemID = currentItem.id
        viewModel.drawer.expandedItemID = currentItem.id
        let runtime = store.drawerRuntime(for: currentItem)

        let backgroundURL = try #require(URL(string: "https://background.example/"))
        store.keepInDrawerInBackground(backgroundURL)

        #expect(store.state.drawerItems.map(\.url) == [backgroundURL, currentItem.url])
        #expect(viewModel.drawer.selectedItemID == currentItem.id)
        #expect(viewModel.drawer.expandedItemID == currentItem.id)
        #expect(store.drawerPreviewRuntime === runtime)
    }

    @Test func drawerPreviewPresentationIsWindowLocalAndSharedMetadataUsesLatestUpdate() throws {
        let item = DrawerItem(url: try #require(URL(string: "https://initial.example/")))
        try withSharedDrawerStores(items: [item]) { first, second in
            let firstViewModel = DenViewModel(store: first)
            firstViewModel.connect()
            defer { firstViewModel.disconnect() }
            let secondViewModel = DenViewModel(store: second)
            secondViewModel.connect()
            defer { secondViewModel.disconnect() }
            firstViewModel.focusDrawerItem(item.id)
            let firstRuntime = first.drawerRuntime(for: item)

            #expect(firstViewModel.drawer.expandedItemID == item.id)
            #expect(secondViewModel.drawer.expandedItemID == nil)

            secondViewModel.focusDrawerItem(item.id)
            let secondRuntime = second.drawerRuntime(for: item)
            #expect(secondViewModel.drawer.expandedItemID == item.id)
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
            let firstViewModel = DenViewModel(store: first)
            firstViewModel.connect()
            defer { firstViewModel.disconnect() }
            let secondViewModel = DenViewModel(store: second)
            secondViewModel.connect()
            defer { secondViewModel.disconnect() }
            firstViewModel.focusDrawerItem(firstItem.id)
            secondViewModel.focusDrawerItem(firstItem.id)
            let firstRuntime = first.drawerRuntime(for: firstItem)
            let secondRuntime = second.drawerRuntime(for: firstItem)

            first.discardDrawerItem(firstItem.id)

            #expect(first.state.drawerItems.map(\.id) == [secondItem.id])
            #expect(firstViewModel.drawer.selectedItemID == secondItem.id)
            #expect(secondViewModel.drawer.selectedItemID == secondItem.id)
            #expect(firstViewModel.drawer.expandedItemID == secondItem.id)
            #expect(secondViewModel.drawer.expandedItemID == secondItem.id)
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
            let firstViewModel = DenViewModel(store: first)
            firstViewModel.connect()
            defer { firstViewModel.disconnect() }
            let secondViewModel = DenViewModel(store: second)
            secondViewModel.connect()
            defer { secondViewModel.disconnect() }
            firstViewModel.focusDrawerItem(firstItem.id)
            secondViewModel.focusDrawerItem(secondItem.id)
            _ = first.drawerRuntime(for: firstItem)
            _ = second.drawerRuntime(for: secondItem)
            first.requestDrawerClearConfirmation()

            #expect(firstViewModel.drawerPendingDeletionCount == 2)
            firstViewModel.confirmDrawerClear()

            #expect(first.state.drawerItems.isEmpty)
            #expect(firstViewModel.drawer.selectedItemID == nil)
            #expect(secondViewModel.drawer.selectedItemID == nil)
            #expect(firstViewModel.drawer.expandedItemID == nil)
            #expect(secondViewModel.drawer.expandedItemID == nil)
            #expect(first.drawerPreviewRuntime == nil)
            #expect(second.drawerPreviewRuntime == nil)
            #expect(!firstViewModel.isDrawerOpen)
            #expect(!secondViewModel.isDrawerOpen)
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
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: items))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.drawer.selectedItemID = items[1].id

        viewModel.drawer.setQuery("swift")
        #expect(viewModel.drawer.filteredItems.map(\.id) == [items[0].id])
        #expect(viewModel.drawer.selectedItemID == items[0].id)

        viewModel.drawer.setQuery("example.org")
        #expect(viewModel.drawer.filteredItems.map(\.id) == [items[1].id])

        viewModel.drawer.setQuery("releases")
        #expect(viewModel.drawer.filteredItems.map(\.id) == [items[1].id])
    }

    @Test func closingDrawerClearsFilterState() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.toggleDrawer()
        viewModel.drawer.enterFilterMode()
        viewModel.drawer.setQuery("example")

        viewModel.closeDrawer()

        #expect(!viewModel.isDrawerOpen)
        #expect(viewModel.drawer.filterPhase == .inactive)
        #expect(viewModel.drawer.query.isEmpty)
    }

    @Test func keepCurrentSheetCopiesWithoutOpeningDrawerOrChangingBoard() {
        let existingBoard = board("Reference", url: "https://example.com/reference")
        let source = desk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        store.keepFocusedSheetInDrawer()

        #expect(store.focusedBoard == existingBoard)
        #expect(store.state.drawerItems.first?.url == existingBoard.currentSheetURL)
        #expect(store.state.drawerItems.first?.title == existingBoard.displayName)
        #expect(!viewModel.isDrawerOpen)
        #expect(viewModel.temporaryContext == nil)
    }

    @Test func placementCreatesFocusedBoardAndRemovesItem() throws {
        let existingBoard = board("Existing", width: 2_480)
        let source = desk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let url = try #require(URL(string: "https://placed.example/"))
        store.keepInDrawer(url)
        let itemID = try #require(viewModel.drawer.selectedItemID)

        viewModel.placeDrawerItemAsBoard(itemID)

        #expect(store.state.drawerItems.isEmpty)
        #expect(store.focusedDesk?.boards.map(\.currentSheetURL) == [existingBoard.currentSheetURL, url])
        #expect(store.focusedBoard?.currentSheetURL == url)
        #expect(store.focusedBoard?.width == existingBoard.width)
        #expect(store.recentItems == [.url(url)])
        #expect(store.recentlyDiscardedDrawerItems.isEmpty)
        #expect(!viewModel.isDrawerOpen)
    }

    @Test func keepAndPlaceReturnIdentifiersAndDiscardReturnsSuccess() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
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
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))

        viewModel.drawer.discardSelectedItem()

        #expect(store.state.drawerItems.count == 1)
        #expect(viewModel.drawer.selectedItemID == store.state.drawerItems[0].id)
        #expect(viewModel.isDrawerOpen)

        viewModel.drawer.discardSelectedItem()

        #expect(store.state.drawerItems.isEmpty)
        #expect(store.recentlyDiscardedDrawerItems.count == 2)
        #expect(!viewModel.isDrawerOpen)
        #expect(viewModel.drawer.selectedItemID == nil)
    }

    @Test func discardHistoryIsTransientAndResetClearsIt() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://discarded.example/")))
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]),
            onSave: { savedState = $0 })

        store.discardDrawerItem(item.id)

        #expect(store.recentlyDiscardedDrawerItems.map(\.id) == [item.id])
        let restoredStore = DenStore(state: try #require(savedState))
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
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: items))

        for item in items.prefix(11) {
            store.discardDrawerItem(item.id)
        }

        #expect(store.state.drawerItems.map(\.id) == [items[11].id])
        #expect(store.recentlyDiscardedDrawerItems.count == DenStore.maximumRecentlyDiscardedDrawerItemCount)
        #expect(
            store.recentlyDiscardedDrawerItems.map(\.id)
                == Array(items[1...10].reversed()).map(\.id))

        for _ in 0..<DenStore.maximumRecentlyDiscardedDrawerItemCount {
            store.restoreRecentlyDiscardedDrawerItem()
        }

        #expect(store.recentlyDiscardedDrawerItems.isEmpty)
        #expect(store.state.drawerItems.map(\.id) == Array(items[1...11]).map(\.id))
    }

    @Test func discardingExpandedItemDisposesItsPreviewRuntime() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://preview.example/")))
        let item = try #require(viewModel.drawer.selectedItem)
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
        let store = DenStore(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [first, second, third]))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        viewModel.toggleDrawer()
        viewModel.drawer.toggleItem(second.id)
        store.discardDrawerItem(second.id)

        #expect(store.state.drawerItems.map(\.id) == [first.id, third.id])
        #expect(viewModel.drawer.selectedItemID == third.id)
        #expect(viewModel.drawer.expandedItemID == third.id)
        #expect(viewModel.isDrawerOpen)
    }

    @Test func discardingLastExpandedItemOpensPreviousPreview() throws {
        let source = desk("Desk")
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        let store = DenStore(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [first, second]))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        viewModel.toggleDrawer()
        viewModel.drawer.toggleItem(second.id)
        store.discardDrawerItem(second.id)

        #expect(store.state.drawerItems.map(\.id) == [first.id])
        #expect(viewModel.drawer.selectedItemID == first.id)
        #expect(viewModel.drawer.expandedItemID == first.id)
    }

    @Test func placementDoesNotAdvanceToAnotherDrawerPreview() throws {
        let source = desk("Desk")
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        let store = DenStore(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [first, second]))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        viewModel.toggleDrawer()
        viewModel.drawer.toggleItem(second.id)
        viewModel.placeDrawerItemAsBoard(second.id)

        #expect(store.state.drawerItems.map(\.id) == [first.id])
        #expect(viewModel.drawer.expandedItemID == nil)
        #expect(!viewModel.isDrawerOpen)
    }

    @Test func clearingDrawerRequiresConfirmationAndDisposesAllItems() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))
        _ = store.drawerRuntime(for: try #require(viewModel.drawer.selectedItem))

        store.requestDrawerClearConfirmation()

        #expect(store.state.drawerItems.count == 2)
        #expect(viewModel.drawerPendingDeletionCount == 2)

        viewModel.confirmDrawerClear()

        #expect(store.state.drawerItems.isEmpty)
        #expect(viewModel.drawerPendingDeletionCount == nil)
        #expect(viewModel.drawer.selectedItemID == nil)
        #expect(viewModel.drawer.expandedItemID == nil)
        #expect(store.drawerPreviewRuntime == nil)
        #expect(store.recentlyDiscardedDrawerItems.count == 2)
        #expect(!viewModel.isDrawerOpen)
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
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { savedState = $0 })
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://preview.example/")))
        let itemID = try #require(viewModel.drawer.expandedItemID)

        viewModel.drawer.toggleItem(itemID)

        #expect(savedState == store.state)

        viewModel.drawer.toggleItem(itemID)

        #expect(savedState == store.state)
        let item = try #require(viewModel.drawer.selectedItem)
        let runtime = store.drawerRuntime(for: item)

        viewModel.closeDrawer()

        #expect(!viewModel.isDrawerOpen)
        #expect(viewModel.drawer.expandedItemID == itemID)
        #expect(store.drawerPreviewRuntime === runtime)
        #expect(savedState == store.state)

        viewModel.toggleDrawer()

        #expect(viewModel.isDrawerOpen)
        #expect(viewModel.drawer.expandedItemID == itemID)
        #expect(store.drawerRuntime(for: item) === runtime)

        viewModel.drawer.toggleItem(itemID)

        #expect(store.drawerPreviewRuntime == nil)
    }

    @Test func denModeKeyboardControlsOpenDrawer() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))
        viewModel.isDenMode = true

        #expect(KeyboardController.handle(try keyEvent(.downArrow, keyCode: 125), store: store, viewModel: viewModel))
        #expect(viewModel.drawer.selectedItemID == store.state.drawerItems[1].id)
        #expect(viewModel.drawer.expandedItemID == store.state.drawerItems[1].id)
        #expect(
            KeyboardController.handle(try keyEvent(.carriageReturn, keyCode: 36), store: store, viewModel: viewModel))
        #expect(viewModel.drawer.expandedItemID == nil)
        #expect(KeyboardController.handle(try keyEvent(.tab, keyCode: 48), store: store, viewModel: viewModel))
        #expect(!viewModel.isDrawerOpen)

        viewModel.toggleDrawer()

        #expect(viewModel.isDrawerOpen)
        #expect(viewModel.drawer.expandedItemID == nil)
    }

    @Test func openingDrawerExitsDenModeOnlyForExpandedPreview() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let store = DenStore(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [item]))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        viewModel.isDenMode = true
        viewModel.openDrawer()
        #expect(viewModel.isDenMode)

        viewModel.closeDrawer()
        viewModel.drawer.toggleItem(item.id)
        viewModel.isDenMode = true
        viewModel.openDrawer()
        #expect(!viewModel.isDenMode)
    }

    @Test func slashSearchAndReturnToggleFilteredSelectionPreview() throws {
        let source = desk("Desk")
        let first = DrawerItem(
            url: try #require(URL(string: "https://first.example/")),
            title: "First")
        let second = DrawerItem(
            url: try #require(URL(string: "https://second.example/")),
            title: "Second")
        let store = DenStore(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [first, second]))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        viewModel.toggleDrawer()

        #expect(KeyboardController.handle(try keyEvent("/", keyCode: 44), store: store, viewModel: viewModel))
        #expect(viewModel.drawer.filterPhase == .filtering)

        viewModel.drawer.setQuery("second")
        #expect(viewModel.drawer.selectedItemID == second.id)
        #expect(
            KeyboardController.handle(try keyEvent(.carriageReturn, keyCode: 36), store: store, viewModel: viewModel))
        #expect(viewModel.drawer.filterPhase == .selecting)
        #expect(viewModel.drawer.expandedItemID == nil)

        #expect(
            KeyboardController.handle(try keyEvent(.carriageReturn, keyCode: 36), store: store, viewModel: viewModel))
        #expect(viewModel.drawer.filterPhase == .inactive)
        #expect(viewModel.drawer.expandedItemID == second.id)
        #expect(viewModel.drawer.query.isEmpty)
        #expect(!viewModel.isDenMode)

        #expect(KeyboardController.handle(try keyEvent("\u{1B}", keyCode: 53), store: store, viewModel: viewModel))
        #expect(!viewModel.isDrawerOpen)
        #expect(viewModel.drawer.expandedItemID == second.id)
    }

    @Test func drawerFilterKeepsSelectingPhaseWhenThereAreNoMatches() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let store = DenStore(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [item]))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        viewModel.toggleDrawer()
        viewModel.drawer.enterFilterMode()
        viewModel.drawer.setQuery("missing")
        viewModel.drawer.confirmFilterQuery()

        #expect(viewModel.drawer.filterPhase == .selecting)
        #expect(viewModel.drawer.selectedItemID == nil)
        viewModel.drawer.confirmFilterSelection()
        #expect(viewModel.drawer.filterPhase == .selecting)
        #expect(viewModel.drawer.query == "missing")

        viewModel.drawer.exitFilterMode()
        #expect(viewModel.drawer.filterPhase == .inactive)
        #expect(viewModel.drawer.query.isEmpty)
    }

    @Test func denModeKeyboardControlsDiscardDrawerItemWithXAndD() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))
        store.keepInDrawer(try #require(URL(string: "https://third.example/")))
        store.keepInDrawer(try #require(URL(string: "https://fourth.example/")))
        viewModel.isDenMode = true
        let itemIDs = store.state.drawerItems.map(\.id)
        viewModel.drawer.selectItem(by: 2)

        #expect(viewModel.isDrawerOpen)
        #expect(viewModel.drawer.selectedItemID == itemIDs[2])
        #expect(KeyboardController.handle(try keyEvent("x", keyCode: 7), store: store, viewModel: viewModel))
        #expect(store.state.drawerItems.map(\.id) == [itemIDs[0], itemIDs[1], itemIDs[3]])
        #expect(viewModel.drawer.selectedItemID == itemIDs[1])
        #expect(KeyboardController.handle(try keyEvent("d", keyCode: 2), store: store, viewModel: viewModel))
        #expect(store.state.drawerItems.map(\.id) == [itemIDs[0], itemIDs[3]])
        #expect(viewModel.drawer.selectedItemID == itemIDs[3])
        #expect(viewModel.isDrawerOpen)
    }

    @Test func denModeKeyboardRestoresNewestDiscardedDrawerItemWithU() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://restore.example/")))
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))

        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.openDrawer()
        viewModel.isDenMode = true
        store.discardDrawerItem(item.id)
        viewModel.openDrawer()
        viewModel.isDenMode = true

        #expect(KeyboardController.handle(try keyEvent("u", keyCode: 32), store: store, viewModel: viewModel))
        #expect(store.state.drawerItems.map(\.id) == [item.id])
        #expect(store.recentlyDiscardedDrawerItems.isEmpty)
        #expect(viewModel.drawer.selectedItemID == item.id)
        #expect(viewModel.drawer.expandedItemID == item.id)
        #expect(viewModel.isDenMode)
    }

    @Test func sheetInputLeavesVimStyleDrawerKeysUnclaimed() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.keepInDrawer(try #require(URL(string: "https://first.example/")))
        store.keepInDrawer(try #require(URL(string: "https://second.example/")))

        #expect(store.state.drawerItems.count == 2)
        #expect(viewModel.isDrawerOpen)
        #expect(!viewModel.isDenMode)

        for (key, keyCode) in [("d", 2), ("x", 7), ("j", 38), ("k", 40), ("p", 35), ("/", 44)] {
            let event = try keyEvent(key, keyCode: UInt16(keyCode))
            #expect(
                KeyboardController.decision(for: event, store: store, viewModel: viewModel)
                    == .consume(.exclusiveContext))
            #expect(KeyboardController.handle(event, store: store, viewModel: viewModel))
        }
        let tab = try keyEvent(.tab, keyCode: 48)
        #expect(
            KeyboardController.decision(for: tab, store: store, viewModel: viewModel)
                == .consume(.exclusiveContext))
        #expect(KeyboardController.handle(tab, store: store, viewModel: viewModel))
        #expect(store.state.drawerItems.count == 2)
        #expect(viewModel.isDrawerOpen)
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
        focusedBoardID: UUID? = nil
    ) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func withSharedDrawerStores<T>(
        items: [DrawerItem],
        body: (DenStore, DenStore) throws -> T
    ) rethrows -> T {
        let suiteName = "SharedDrawerStoreTests-\(UUID())"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Failed to create isolated test UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let desks = [desk("First"), desk("Second")]
        let storage = DenStorage(
            state: DenState(
                desks: desks,
                focusedDeskID: desks[0].id,
                drawerItems: items))
        let websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let sheetNavigation = SheetNavigationManager(defaults: defaults, scriptSource: "")
        let preferences = AppPreferences(defaults: defaults)
        let makeStore = { (deskID: UUID) -> DenStore in
            DenStore(
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
