import AppKit
import Foundation
import Testing
@testable import Den_Browser

@MainActor
struct DenStoreDrawerTests {
    @Test func captureKeepsDeskLayoutAndOpensNewestItem() throws {
        let existingBoard = board("Existing", url: "https://desk.example/")
        let source = desk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { savedState = $0 })
        let url = try #require(URL(string: "https://drawer.example/first"))

        store.captureInDrawer(url)

        #expect(store.focusedDesk == source)
        #expect(store.state.drawerItems.map(\.url) == [url])
        #expect(store.selectedDrawerItemID == store.state.drawerItems[0].id)
        #expect(store.expandedDrawerItemID == store.state.drawerItems[0].id)
        #expect(store.isDrawerOpen)
        #expect(savedState == store.state)
    }

    @Test func duplicateURLsRemainDistinctAndNewestComesFirst() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let url = try #require(URL(string: "https://example.com/"))

        store.captureInDrawer(url)
        let firstID = try #require(store.state.drawerItems.first?.id)
        store.captureInDrawer(url)

        #expect(store.state.drawerItems.count == 2)
        #expect(store.state.drawerItems[0].id != firstID)
        #expect(store.state.drawerItems[1].id == firstID)
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
        store.selectedDrawerItemID = items[1].id

        store.setDrawerQuery("swift")
        #expect(store.filteredDrawerItems.map(\.id) == [items[0].id])
        #expect(store.selectedDrawerItemID == items[0].id)

        store.setDrawerQuery("example.org")
        #expect(store.filteredDrawerItems.map(\.id) == [items[1].id])

        store.setDrawerQuery("releases")
        #expect(store.filteredDrawerItems.map(\.id) == [items[1].id])
    }

    @Test func closingDrawerClearsFilterState() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))
        store.toggleDrawer()
        store.enterDrawerFilterMode()
        store.setDrawerQuery("example")

        store.closeDrawer()

        #expect(!store.isDrawerOpen)
        #expect(!store.isDrawerFilterMode)
        #expect(store.drawerQuery.isEmpty)
    }

    @Test func captureCurrentSheetCopiesWithoutOpeningDrawerOrChangingBoard() {
        let existingBoard = board("Reference", url: "https://example.com/reference")
        let source = desk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        store.captureFocusedSheetInDrawer()

        #expect(store.focusedBoard == existingBoard)
        #expect(store.state.drawerItems.first?.url == existingBoard.currentSheetURL)
        #expect(store.state.drawerItems.first?.title == existingBoard.displayName)
        #expect(!store.isDrawerOpen)
        #expect(store.temporaryContext == nil)
    }

    @Test func placementCreatesFocusedBoardAndRemovesItem() throws {
        let existingBoard = board("Existing", width: 2_480)
        let source = desk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let url = try #require(URL(string: "https://placed.example/"))
        store.captureInDrawer(url)
        let itemID = try #require(store.selectedDrawerItemID)

        store.placeDrawerItemAsBoard(itemID)

        #expect(store.state.drawerItems.isEmpty)
        #expect(store.focusedDesk?.boards.map(\.currentSheetURL) == [existingBoard.currentSheetURL, url])
        #expect(store.focusedBoard?.currentSheetURL == url)
        #expect(store.focusedBoard?.width == existingBoard.width)
        #expect(!store.isDrawerOpen)
    }

    @Test func discardingSelectedItemSelectsItsNeighborAndClosesWhenEmpty() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        store.captureInDrawer(try #require(URL(string: "https://first.example/")))
        store.captureInDrawer(try #require(URL(string: "https://second.example/")))

        store.discardSelectedDrawerItem()

        #expect(store.state.drawerItems.count == 1)
        #expect(store.selectedDrawerItemID == store.state.drawerItems[0].id)
        #expect(store.isDrawerOpen)

        store.discardSelectedDrawerItem()

        #expect(store.state.drawerItems.isEmpty)
        #expect(!store.isDrawerOpen)
        #expect(store.selectedDrawerItemID == nil)
    }

    @Test func discardingExpandedItemDisposesItsPreviewRuntime() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        store.captureInDrawer(try #require(URL(string: "https://preview.example/")))
        let item = try #require(store.selectedDrawerItem)
        let runtime = store.drawerRuntime(for: item)

        store.discardDrawerItem(item.id)

        #expect(store.drawerPreviewRuntime == nil)
        #expect(runtime.webView.navigationDelegate == nil)
        #expect(runtime.webView.uiDelegate == nil)
    }

    @Test func clearingDrawerRequiresConfirmationAndDisposesAllItems() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        store.captureInDrawer(try #require(URL(string: "https://first.example/")))
        store.captureInDrawer(try #require(URL(string: "https://second.example/")))
        _ = store.drawerRuntime(for: try #require(store.selectedDrawerItem))

        store.requestDrawerClearConfirmation()

        #expect(store.state.drawerItems.count == 2)
        #expect(store.drawerPendingDeletionCount == 2)

        store.confirmDrawerClear()

        #expect(store.state.drawerItems.isEmpty)
        #expect(store.drawerPendingDeletionCount == nil)
        #expect(store.selectedDrawerItemID == nil)
        #expect(store.expandedDrawerItemID == nil)
        #expect(store.drawerPreviewRuntime == nil)
        #expect(!store.isDrawerOpen)
    }

    @Test func legacyDenStateLoadsWithEmptyDrawerAndEmptyDrawerStaysOmitted() throws {
        let source = desk("Desk")
        let state = DenState(desks: [source], focusedDeskID: source.id)
        let encoded = try JSONEncoder().encode(state)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(object["drawerItems"] == nil)
        #expect(object["expandedDrawerItemID"] == nil)
        let decoded = try JSONDecoder().decode(DenState.self, from: encoded)
        #expect(decoded.drawerItems.isEmpty)
        #expect(decoded.expandedDrawerItemID == nil)
    }

    @Test func expandedPreviewRestoresWhenDrawerNextOpensWithoutPersistingItsRuntime() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://preview.example/")))
        let state = DenState(
            desks: [source],
            focusedDeskID: source.id,
            drawerItems: [item],
            expandedDrawerItemID: item.id)

        let restoredState = try JSONDecoder().decode(
            DenState.self,
            from: JSONEncoder().encode(state))
        let store = DenStore(state: restoredState)

        #expect(store.state.expandedDrawerItemID == item.id)
        #expect(store.selectedDrawerItemID == item.id)
        #expect(store.expandedDrawerItemID == item.id)
        #expect(!store.isDrawerOpen)
        #expect(store.drawerPreviewRuntime == nil)

        store.toggleDrawer()

        #expect(store.isDrawerOpen)
        #expect(store.expandedDrawerItemID == item.id)
    }

    @Test func missingExpandedDrawerItemIsClearedOnRestore() throws {
        let source = desk("Desk")
        var savedState: DenState?
        let store = DenStore(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                expandedDrawerItemID: UUID()),
            onSave: { savedState = $0 })

        #expect(store.state.expandedDrawerItemID == nil)
        #expect(store.expandedDrawerItemID == nil)
        #expect(!store.isDrawerOpen)
        #expect(savedState == store.state)
    }

    @Test func closingDrawerKeepsExpandedPreviewForNextOpen() throws {
        let source = desk("Desk")
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { savedState = $0 })
        store.captureInDrawer(try #require(URL(string: "https://preview.example/")))
        let itemID = try #require(store.expandedDrawerItemID)

        store.toggleDrawerItem(itemID)

        #expect(store.state.expandedDrawerItemID == nil)
        #expect(savedState == store.state)

        store.toggleDrawerItem(itemID)

        #expect(store.state.expandedDrawerItemID == itemID)
        #expect(savedState == store.state)
        let item = try #require(store.selectedDrawerItem)
        let runtime = store.drawerRuntime(for: item)

        store.closeDrawer()

        #expect(!store.isDrawerOpen)
        #expect(store.expandedDrawerItemID == itemID)
        #expect(store.state.expandedDrawerItemID == itemID)
        #expect(store.drawerPreviewRuntime === runtime)
        #expect(savedState == store.state)

        store.toggleDrawer()

        #expect(store.isDrawerOpen)
        #expect(store.expandedDrawerItemID == itemID)
        #expect(store.drawerRuntime(for: item) === runtime)

        store.toggleDrawerItem(itemID)

        #expect(store.drawerPreviewRuntime == nil)
    }

    @Test func denModeKeyboardControlsOpenDrawer() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        store.captureInDrawer(try #require(URL(string: "https://first.example/")))
        store.captureInDrawer(try #require(URL(string: "https://second.example/")))
        store.isDenMode = true

        #expect(KeyboardController.handle(try keyEvent(.downArrow, keyCode: 125), store: store))
        #expect(store.selectedDrawerItemID == store.state.drawerItems[1].id)
        #expect(store.state.expandedDrawerItemID == store.state.drawerItems[1].id)
        #expect(KeyboardController.handle(try keyEvent(.carriageReturn, keyCode: 36), store: store))
        #expect(store.expandedDrawerItemID == nil)
        #expect(store.state.expandedDrawerItemID == nil)
        #expect(KeyboardController.handle(try keyEvent(.tab, keyCode: 48), store: store))
        #expect(!store.isDrawerOpen)

        store.toggleDrawer()

        #expect(store.isDrawerOpen)
        #expect(store.expandedDrawerItemID == nil)
    }

    @Test func openingDrawerExitsDenModeOnlyForExpandedPreview() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let store = DenStore(
            state: DenState(
                desks: [source],
                focusedDeskID: source.id,
                drawerItems: [item]))

        store.isDenMode = true
        store.openDrawer()
        #expect(store.isDenMode)

        store.closeDrawer()
        store.toggleDrawerItem(item.id)
        store.isDenMode = true
        store.openDrawer()
        #expect(!store.isDenMode)
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
        store.isDenMode = true
        store.toggleDrawer()

        #expect(KeyboardController.handle(try keyEvent("/", keyCode: 44), store: store))
        #expect(store.isDrawerFilterMode)

        store.setDrawerQuery("second")
        #expect(store.selectedDrawerItemID == second.id)
        #expect(KeyboardController.handle(try keyEvent(.carriageReturn, keyCode: 36), store: store))
        #expect(!store.isDrawerFilterMode)
        #expect(store.expandedDrawerItemID == second.id)
        #expect(store.drawerQuery == "second")
        #expect(!store.isDenMode)

        #expect(KeyboardController.handle(try keyEvent("\u{1B}", keyCode: 53), store: store))
        #expect(!store.isDrawerOpen)
        #expect(store.expandedDrawerItemID == second.id)
    }

    @Test func denModeKeyboardControlsDiscardDrawerItemWithXAndD() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        store.captureInDrawer(try #require(URL(string: "https://first.example/")))
        store.captureInDrawer(try #require(URL(string: "https://second.example/")))
        store.isDenMode = true

        #expect(store.isDrawerOpen)
        #expect(store.state.drawerItems.count == 2)
        #expect(KeyboardController.handle(try keyEvent("x", keyCode: 7), store: store))
        #expect(store.state.drawerItems.count == 1)
        #expect(KeyboardController.handle(try keyEvent("d", keyCode: 2), store: store))
        #expect(store.state.drawerItems.isEmpty)
        #expect(!store.isDrawerOpen)
    }

    @Test func sheetInputLeavesVimStyleDrawerKeysUnclaimed() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        store.captureInDrawer(try #require(URL(string: "https://first.example/")))
        store.captureInDrawer(try #require(URL(string: "https://second.example/")))

        #expect(store.state.drawerItems.count == 2)
        #expect(store.isDrawerOpen)
        #expect(!store.isDenMode)

        for (key, keyCode) in [("d", 2), ("x", 7), ("j", 38), ("k", 40), ("p", 35), ("/", 44)] {
            #expect(!KeyboardController.handle(try keyEvent(key, keyCode: UInt16(keyCode)), store: store))
        }
        #expect(!KeyboardController.handle(try keyEvent(.tab, keyCode: 48), store: store))
        #expect(store.state.drawerItems.count == 2)
        #expect(store.isDrawerOpen)
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
}
