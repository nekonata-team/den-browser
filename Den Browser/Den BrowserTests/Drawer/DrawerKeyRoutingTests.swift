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
struct DrawerKeyRoutingTests {
    @Test func denModeKeyboardControlsOpenDrawer() throws {
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
        windowModel.isDenMode = true

        #expect(
            KeyboardController.handle(
                try keyEvent(.downArrow, keyCode: 125),
                session: session,
                windowModel: windowModel
            )
        )
        #expect(windowModel.drawer.selectedItemID == session.resources.state.drawerItems[1].id)
        #expect(windowModel.drawer.expandedItemID == session.resources.state.drawerItems[1].id)
        #expect(
            KeyboardController.handle(
                try keyEvent(.carriageReturn, keyCode: 36),
                session: session,
                windowModel: windowModel
            )
        )
        #expect(windowModel.drawer.expandedItemID == nil)
        #expect(
            KeyboardController.handle(try keyEvent(.tab, keyCode: 48), session: session, windowModel: windowModel)
        )
        #expect(!windowModel.isDrawerOpen)

        windowModel.toggleDrawer()

        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == nil)
    }

    @Test func openingDrawerExitsDenModeOnlyForExpandedPeek() throws {
        let source = makeTestDesk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [item]
                    )
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
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

    @Test func slashSearchAndReturnToggleFilteredSelectionPeek() throws {
        let source = makeTestDesk("Desk")
        let first = DrawerItem(
            url: try #require(URL(string: "https://first.example/")),
            title: "First"
        )
        let second = DrawerItem(
            url: try #require(URL(string: "https://second.example/")),
            title: "Second"
        )
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
        windowModel.isDenMode = true
        windowModel.toggleDrawer()

        #expect(
            KeyboardController.handle(try keyEvent("/", keyCode: 44), session: session, windowModel: windowModel)
        )
        #expect(windowModel.drawer.filterPhase == .filtering)

        windowModel.drawer.setQuery("second")
        #expect(windowModel.drawer.selectedItemID == second.id)
        #expect(
            KeyboardController.handle(
                try keyEvent(.carriageReturn, keyCode: 36),
                session: session,
                windowModel: windowModel
            )
        )
        #expect(windowModel.drawer.filterPhase == .selecting)
        #expect(windowModel.drawer.expandedItemID == nil)

        #expect(
            KeyboardController.handle(
                try keyEvent(.carriageReturn, keyCode: 36),
                session: session,
                windowModel: windowModel
            )
        )
        #expect(windowModel.drawer.filterPhase == .inactive)
        #expect(windowModel.drawer.expandedItemID == second.id)
        #expect(windowModel.drawer.query.isEmpty)
        #expect(!windowModel.isDenMode)

        #expect(
            KeyboardController.handle(
                try keyEvent("\u{1B}", keyCode: 53),
                session: session,
                windowModel: windowModel
            )
        )
        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == second.id)
    }

    @Test func drawerFilterKeepsSelectingPhaseWhenThereAreNoMatches() throws {
        let source = makeTestDesk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [item]
                    )
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
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
        session.drawer.keepInDrawer(try #require(URL(string: "https://third.example/")))
        session.drawer.keepInDrawer(try #require(URL(string: "https://fourth.example/")))
        windowModel.isDenMode = true
        let itemIDs = session.resources.state.drawerItems.map(\.id)
        windowModel.drawer.selectItem(by: 2)

        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.selectedItemID == itemIDs[2])
        #expect(
            KeyboardController.handle(try keyEvent("x", keyCode: 7), session: session, windowModel: windowModel)
        )
        #expect(session.resources.state.drawerItems.map(\.id) == [itemIDs[0], itemIDs[1], itemIDs[3]])
        #expect(windowModel.drawer.selectedItemID == itemIDs[1])
        #expect(
            KeyboardController.handle(try keyEvent("d", keyCode: 2), session: session, windowModel: windowModel)
        )
        #expect(session.resources.state.drawerItems.map(\.id) == [itemIDs[0], itemIDs[3]])
        #expect(windowModel.drawer.selectedItemID == itemIDs[3])
        #expect(windowModel.isDrawerOpen)
    }

    @Test func restorationActionRestoresNewestDiscardedDrawerItemAndPreservesDenMode() throws {
        let source = makeTestDesk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://restore.example/")))
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
        windowModel.openDrawer()
        windowModel.isDenMode = true
        session.drawer.discardDrawerItem(item.id)
        windowModel.openDrawer()
        windowModel.isDenMode = true

        AppActionHandler.perform(
            .drawer(.restoreDiscardedItem),
            session: session,
            windowModel: windowModel,
            openSettings: {}
        )
        #expect(session.resources.state.drawerItems.map(\.id) == [item.id])
        #expect(session.resources.recentlyDiscardedDrawerItems.isEmpty)
        #expect(windowModel.drawer.selectedItemID == item.id)
        #expect(windowModel.drawer.expandedItemID == item.id)
        #expect(windowModel.isDenMode)
    }

    @Test func sheetInputLeavesVimStyleDrawerKeysUnclaimed() throws {
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

        #expect(session.resources.state.drawerItems.count == 2)
        #expect(windowModel.isDrawerOpen)
        #expect(!windowModel.isDenMode)

        for (key, keyCode) in [("d", 2), ("x", 7), ("j", 38), ("k", 40), ("p", 35), ("/", 44)] {
            let event = try keyEvent(key, keyCode: UInt16(keyCode))
            #expect(
                KeyboardController.decision(for: event, session: session, windowModel: windowModel)
                    == .consume(.exclusiveContext)
            )
            #expect(KeyboardController.handle(event, session: session, windowModel: windowModel))
        }
        let tab = try keyEvent(.tab, keyCode: 48)
        #expect(
            KeyboardController.decision(for: tab, session: session, windowModel: windowModel)
                == .consume(.exclusiveContext)
        )
        #expect(KeyboardController.handle(tab, session: session, windowModel: windowModel))
        #expect(session.resources.state.drawerItems.count == 2)
        #expect(windowModel.isDrawerOpen)
    }
}
