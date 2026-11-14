import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import Observation
import Synchronization
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DrawerFilteringTests {
    @Test func drawerModelKeepsLiveInputsObservable() throws {
        let item = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item])
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
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

        session.drawer.keepInDrawer(try #require(URL(string: "https://second.example/")))
        session.configuration.preferences.toggleDrawerStyle()

        #expect(itemChanged.withLock { $0 })
        #expect(styleChanged.withLock { $0 })
    }

    @Test func drawerSelectionWrapsAtBothEnds() throws {
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let last = DrawerItem(url: try #require(URL(string: "https://last.example/")))
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [first, last]
                    )
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.drawer.selectedItemID = last.id

        windowModel.drawer.selectItem(by: 1)
        #expect(windowModel.drawer.selectedItemID == first.id)

        windowModel.drawer.selectItem(by: -1)
        #expect(windowModel.drawer.selectedItemID == last.id)
    }

    @Test func filteringMatchesTitleHostAndURLAndKeepsSelectionInResults() throws {
        let source = makeTestDesk("Desk")
        let items = [
            DrawerItem(
                url: try #require(URL(string: "https://example.com/reference")),
                title: "Swift Guide"
            ),
            DrawerItem(url: try #require(URL(string: "https://news.example.org/releases"))),
        ]
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: items)
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
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
        let source = makeTestDesk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item])
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
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

    @Test func switchingAndCollapsingItemsRetainsOnlyOpenedRuntimes() throws {
        // Arrange
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        let unopened = DrawerItem(url: try #require(URL(string: "https://unopened.example/")))
        withSharedDrawerSessions(items: [first, second, unopened]) { session, _ in
            let composition = DenWindowComposition(session: session)
            composition.connect()
            defer {
                composition.disconnect()
                session.runtimes.releaseRuntimes()
            }
            composition.model.focusDrawerItem(first.id)
            let firstRuntime = session.drawer.drawerRuntime(for: first)

            // Act
            composition.model.drawer.toggleItem(second.id)
            let secondRuntime = session.drawer.drawerRuntime(for: second)
            composition.model.drawer.toggleItem(second.id)

            // Assert
            #expect(session.windowResources.drawerPeek == nil)
            #expect(session.resources.drawerRuntimes.web.count == 2)
            #expect(session.resources.drawerRuntimes.web[unopened.id] == nil)
            #expect(firstRuntime.webView.navigationDelegate === firstRuntime)
            #expect(secondRuntime.webView.navigationDelegate === secondRuntime)
            #expect((firstRuntime.webView as? RuntimeWKWebView)?.isFocusAllowed() == false)
            #expect(session.drawer.drawerRuntime(for: first) === firstRuntime)
        }
    }

    @Test func disconnectedWindowKeepsRuntimeAndBackgroundMetadataUntilAnotherWindowOpensIt() throws {
        // Arrange
        let item = DrawerItem(url: try #require(URL(string: "https://initial.example/")))
        try withSharedDrawerSessions(items: [item]) { first, second in
            defer { second.runtimes.releaseRuntimes() }
            let runtime = first.drawer.drawerRuntime(for: item)
            let nextURL = try #require(URL(string: "https://initial.example/next"))

            // Act
            first.connection.disconnect()
            first.runtimes.releaseWindowResources()
            runtime.handleURLOrTitleChange(url: nextURL, title: "Continued")

            // Assert
            #expect(first.windowResources.drawerPeek == nil)
            #expect(first.resources.drawerRuntimes.web[item.id] === runtime)
            #expect(second.resources.state.drawerItems[0].url == nextURL)
            #expect(second.resources.state.drawerItems[0].title == "Continued")
            #expect(second.drawer.drawerRuntime(for: item) === runtime)
            #expect(runtime.webView.navigationDelegate === runtime)
        }
    }

    @Test func emptyDrawerStaysOmittedFromPersistence() throws {
        let source = makeTestDesk("Desk")
        let state = DenState(desks: [source], focusedDeskID: source.id)
        let encoded = try JSONEncoder().encode(state)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(object["drawerItems"] == nil)
        #expect(object["expandedDrawerItemID"] == nil)
        let decoded = try JSONDecoder().decode(DenState.self, from: encoded)
        #expect(decoded.drawerItems.isEmpty)
    }

    @Test func closingDrawerKeepsExpandedPeekForNextOpen() throws {
        let source = makeTestDesk("Desk")
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://preview.example/")))
        let itemID = try #require(windowModel.drawer.expandedItemID)

        windowModel.drawer.toggleItem(itemID)

        #expect(savedState == session.resources.state)

        windowModel.drawer.toggleItem(itemID)

        #expect(savedState == session.resources.state)
        let item = try #require(windowModel.drawer.selectedItem)
        let runtime = session.drawer.drawerRuntime(for: item)

        windowModel.closeDrawer()

        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == itemID)
        #expect(session.windowResources.drawerPeek === runtime)
        #expect(savedState == session.resources.state)

        windowModel.toggleDrawer()

        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == itemID)
        #expect(session.drawer.drawerRuntime(for: item) === runtime)

        windowModel.drawer.toggleItem(itemID)

        #expect(session.windowResources.drawerPeek == nil)
    }
}
