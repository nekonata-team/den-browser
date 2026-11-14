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
struct DrawerDiscardTests {
    @Test func openingDrawerCleansExpiredItemsAndProtectsVisiblePeeks() async throws {
        // Arrange
        let url = try #require(URL(string: "https://example.com/"))
        var visible = DrawerItem(url: url)
        visible.touchedAt = Date().addingTimeInterval(-13 * 60 * 60)
        var expired = DrawerItem(terminal: .shell(workingDirectory: "/tmp"))
        expired.touchedAt = visible.touchedAt
        let source = makeTestDesk("Desk")
        let resources = DenProfileResources(
            state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: [visible, expired])
        )
        let configuration = makeTestBoardRuntimeConfiguration()
        let session = ProfileWindowSession(resources: resources, configuration: configuration)
        let other = ProfileWindowSession(resources: resources, configuration: configuration)
        let composition = DenWindowComposition(session: session)
        let otherComposition = DenWindowComposition(session: other)
        composition.connect()
        otherComposition.connect()
        defer {
            otherComposition.disconnect()
            composition.disconnect()
        }
        otherComposition.model.focusDrawerItem(visible.id)
        composition.model.drawer.expandedItemID = expired.id

        // Act
        session.configuration.preferences.setDrawerAutoCleanup(true)
        #expect(session.resources.state.drawerItems.count == 2)
        composition.model.openDrawer()
        await Task.yield()

        // Assert
        #expect(session.resources.state.drawerItems.map(\.id) == [visible.id])
        #expect(composition.model.drawer.expandedItemID == nil)
        #expect(session.feedback.latest?.message == "Automatically discarded 1 Drawer Item.")
    }

    @Test func openingTheDrawerAddPanelAlsoRunsCleanup() async throws {
        // Arrange
        var expired = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        expired.touchedAt = Date().addingTimeInterval(-13 * 60 * 60)
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: [expired])
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        session.configuration.preferences.setDrawerAutoCleanup(true)
        composition.model.showOpenBoardPanel()

        // Act
        composition.model.showOpenBoardPanel(inDrawer: true)
        await Task.yield()

        // Assert
        #expect(session.resources.state.drawerItems.isEmpty)
        #expect(composition.model.isAddingToDrawer)
        #expect(session.feedback.latest?.message == "Automatically discarded 1 Drawer Item.")
    }

    @Test func cleanupToastSurvivesFeedbackFromKeepingAnItem() async throws {
        // Arrange
        var expired = DrawerItem(url: try #require(URL(string: "https://example.com/old")))
        expired.touchedAt = Date().addingTimeInterval(-13 * 60 * 60)
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenState(desks: [source], focusedDeskID: source.id, drawerItems: [expired])
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        session.configuration.preferences.setDrawerAutoCleanup(true)

        // Act
        session.drawer.keepInDrawer(try #require(URL(string: "https://example.com/new")))
        await Task.yield()

        // Assert
        #expect(session.resources.state.drawerItems.map(\.url) == [URL(string: "https://example.com/new")])
        #expect(session.feedback.latest?.message == "Automatically discarded 1 Drawer Item.")
    }

    @Test func discardingSharedItemRepairsEveryWindowPresentation() throws {
        let firstItem = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let secondItem = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        withSharedDrawerSessions(items: [firstItem, secondItem]) { first, second in
            let firstComposition = DenWindowComposition(session: first)
            let firstWindowModel = firstComposition.model
            firstComposition.connect()
            defer { firstComposition.disconnect() }
            let secondComposition = DenWindowComposition(session: second)
            let secondWindowModel = secondComposition.model
            secondComposition.connect()
            defer { secondComposition.disconnect() }
            firstWindowModel.focusDrawerItem(firstItem.id)
            secondWindowModel.focusDrawerItem(firstItem.id)
            let firstRuntime = first.drawer.drawerRuntime(for: firstItem)
            let secondRuntime = second.drawer.drawerRuntime(for: firstItem)

            first.drawer.discardDrawerItem(firstItem.id)

            #expect(first.resources.state.drawerItems.map(\.id) == [secondItem.id])
            #expect(firstWindowModel.drawer.selectedItemID == secondItem.id)
            #expect(secondWindowModel.drawer.selectedItemID == secondItem.id)
            #expect(firstWindowModel.drawer.expandedItemID == nil)
            #expect(secondWindowModel.drawer.expandedItemID == secondItem.id)
            #expect(first.windowResources.drawerPeek == nil)
            #expect(second.windowResources.drawerPeek == nil)
            #expect(firstRuntime.webView.navigationDelegate == nil)
            #expect(secondRuntime.webView.navigationDelegate == nil)
        }
    }

    @Test func clearingSharedDrawerClearsEveryWindowPresentation() throws {
        let firstItem = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let secondItem = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        withSharedDrawerSessions(items: [firstItem, secondItem]) { first, second in
            let firstComposition = DenWindowComposition(session: first)
            let firstWindowModel = firstComposition.model
            firstComposition.connect()
            defer { firstComposition.disconnect() }
            let secondComposition = DenWindowComposition(session: second)
            let secondWindowModel = secondComposition.model
            secondComposition.connect()
            defer { secondComposition.disconnect() }
            firstWindowModel.focusDrawerItem(firstItem.id)
            secondWindowModel.focusDrawerItem(secondItem.id)
            _ = first.drawer.drawerRuntime(for: firstItem)
            _ = second.drawer.drawerRuntime(for: secondItem)
            first.drawer.requestDrawerClearConfirmation()

            #expect(firstWindowModel.drawerPendingDiscardCount == 2)
            firstWindowModel.confirmDrawerClear()

            #expect(first.resources.state.drawerItems.isEmpty)
            #expect(firstWindowModel.drawer.selectedItemID == nil)
            #expect(secondWindowModel.drawer.selectedItemID == nil)
            #expect(firstWindowModel.drawer.expandedItemID == nil)
            #expect(secondWindowModel.drawer.expandedItemID == nil)
            #expect(first.windowResources.drawerPeek == nil)
            #expect(second.windowResources.drawerPeek == nil)
            #expect(!firstWindowModel.isDrawerOpen)
            #expect(!secondWindowModel.isDrawerOpen)
        }
    }

    @Test func discardingCollapsedItemDisposesItsRetainedRuntime() throws {
        // Arrange
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        withSharedDrawerSessions(items: [first, second]) { session, _ in
            defer { session.runtimes.releaseRuntimes() }
            let discarded = session.drawer.drawerRuntime(for: first)
            let retained = session.drawer.drawerRuntime(for: second)

            // Act
            session.drawer.discardDrawerItem(first.id)

            // Assert
            #expect(session.resources.drawerRuntimes.web[first.id] == nil)
            #expect(discarded.webView.navigationDelegate == nil)
            #expect(session.windowResources.drawerPeek === retained)
            #expect(retained.webView.navigationDelegate === retained)
        }
    }

    @Test func releasingProfileRuntimesDisposesEveryRetainedItem() throws {
        // Arrange
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        withSharedDrawerSessions(items: [first, second]) { session, other in
            let firstRuntime = session.drawer.drawerRuntime(for: first)
            let secondRuntime = other.drawer.drawerRuntime(for: second)

            // Act
            session.runtimes.releaseRuntimes()

            // Assert
            #expect(session.resources.drawerRuntimes.web.isEmpty)
            #expect(session.windowResources.drawerPeek == nil)
            #expect(other.windowResources.drawerPeek == nil)
            #expect(firstRuntime.webView.navigationDelegate == nil)
            #expect(secondRuntime.webView.navigationDelegate == nil)
        }
    }

    @Test func discardingSelectedItemSelectsItsNeighborAndClosesWhenEmpty() throws {
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://first.example/")))
        session.drawer.keepInDrawer(try #require(URL(string: "https://second.example/")))

        windowModel.drawer.discardSelectedItem()

        #expect(session.resources.state.drawerItems.count == 1)
        #expect(windowModel.drawer.selectedItemID == session.resources.state.drawerItems[0].id)
        #expect(windowModel.isDrawerOpen)

        windowModel.drawer.discardSelectedItem()

        #expect(session.resources.state.drawerItems.isEmpty)
        #expect(session.resources.recentlyDiscardedDrawerItems.count == 2)
        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.drawer.selectedItemID == nil)
    }

    @Test func discardHistoryIsTransientAndResetClearsIt() throws {
        let source = makeTestDesk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://discarded.example/")))
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item])
                ),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.drawer.discardDrawerItem(item.id)

        #expect(session.resources.recentlyDiscardedDrawerItems.map(\.id) == [item.id])
        let restoredSession = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(try #require(savedState))),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        #expect(restoredSession.resources.recentlyDiscardedDrawerItems.isEmpty)

        session.drawer.restoreRecentlyDiscardedDrawerItem()
        session.reset.resetDen()
        #expect(session.resources.recentlyDiscardedDrawerItems.isEmpty)
    }

    @Test func discardHistoryKeepsAtMostTenItemsAndRestoresNewestFirst() throws {
        let source = makeTestDesk("Desk")
        let items = try (0..<12).map { index in
            DrawerItem(url: try #require(URL(string: "https://drawer-\(index).example/")))
        }
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: items)
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        for item in items.prefix(11) {
            session.drawer.discardDrawerItem(item.id)
        }

        #expect(session.resources.state.drawerItems.map(\.id) == [items[11].id])
        #expect(session.resources.recentlyDiscardedDrawerItems.count == DrawerItems.maximumDiscardHistoryCount)
        #expect(
            session.resources.recentlyDiscardedDrawerItems.map(\.id)
                == Array(items[1...10].reversed()).map(\.id)
        )

        for _ in 0..<DrawerItems.maximumDiscardHistoryCount {
            session.drawer.restoreRecentlyDiscardedDrawerItem()
        }

        #expect(session.resources.recentlyDiscardedDrawerItems.isEmpty)
        #expect(session.resources.state.drawerItems.map(\.id) == Array(items[1...11]).map(\.id))
    }

    @Test func discardingExpandedItemDisposesItsPeekRuntime() throws {
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://preview.example/")))
        let item = try #require(windowModel.drawer.selectedItem)
        let runtime = session.drawer.drawerRuntime(for: item)

        session.drawer.discardDrawerItem(item.id)

        #expect(session.windowResources.drawerPeek == nil)
        #expect(runtime.webView.navigationDelegate == nil)
        #expect(runtime.webView.uiDelegate == nil)
    }

    @Test func discardingExpandedItemOpensFollowingPeek() throws {
        let source = makeTestDesk("Desk")
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        let third = DrawerItem(url: try #require(URL(string: "https://third.example/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [first, second, third]
                    )
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.toggleDrawer()
        windowModel.drawer.toggleItem(second.id)
        session.drawer.discardDrawerItem(second.id)

        #expect(session.resources.state.drawerItems.map(\.id) == [first.id, third.id])
        #expect(windowModel.drawer.selectedItemID == third.id)
        #expect(windowModel.drawer.expandedItemID == third.id)
        #expect(windowModel.isDrawerOpen)
    }

    @Test func discardingLastExpandedItemOpensPreviousPeek() throws {
        let source = makeTestDesk("Desk")
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [first, second]
                    )
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.toggleDrawer()
        windowModel.drawer.toggleItem(second.id)
        session.drawer.discardDrawerItem(second.id)

        #expect(session.resources.state.drawerItems.map(\.id) == [first.id])
        #expect(windowModel.drawer.selectedItemID == first.id)
        #expect(windowModel.drawer.expandedItemID == first.id)
    }

    @Test func clearingDrawerRequiresConfirmationAndDisposesAllItems() throws {
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://first.example/")))
        session.drawer.keepInDrawer(try #require(URL(string: "https://second.example/")))
        _ = session.drawer.drawerRuntime(for: try #require(windowModel.drawer.selectedItem))

        session.drawer.requestDrawerClearConfirmation()

        #expect(session.resources.state.drawerItems.count == 2)
        #expect(windowModel.drawerPendingDiscardCount == 2)

        windowModel.confirmDrawerClear()

        #expect(session.resources.state.drawerItems.isEmpty)
        #expect(windowModel.drawerPendingDiscardCount == nil)
        #expect(windowModel.drawer.selectedItemID == nil)
        #expect(windowModel.drawer.expandedItemID == nil)
        #expect(session.windowResources.drawerPeek == nil)
        #expect(session.resources.recentlyDiscardedDrawerItems.count == 2)
        #expect(!windowModel.isDrawerOpen)
    }
}
