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
struct DrawerPlacementTests {
    @Test func placingInAChosenDeskPreservesTheLiveRuntime() throws {
        // Arrange
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let source = makeTestDesk("Source")
        let anchor = makeDrawerTestBoard("Anchor")
        let destination = makeTestDesk("Destination", boards: [anchor], focusedBoardID: anchor.id)
        let resources = DenProfileResources(
            state: DenState(desks: [source, destination], focusedDeskID: source.id, drawerItems: [item])
        )
        let session = ProfileWindowSession(resources: resources, configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        let runtime = session.drawer.drawerRuntime(for: item)
        composition.model.openDrawer()
        composition.model.isDenMode = true

        // Act
        composition.model.chooseSelectedDrawerItemPlacementDesk()
        #expect(composition.model.drawer.placementDeskID == source.id)
        composition.model.selectDrawerPlacementDesk(by: 1)
        composition.model.confirmDrawerPlacementDesk()

        // Assert
        #expect(session.navigation.presentedDeskID == destination.id)
        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [anchor.id, BoardID(item.id)])
        #expect(session.navigation.focusedDesk?.focusedBoardID == BoardID(item.id))
        #expect(session.resources.webRuntimes[BoardID(item.id)] === runtime)
        #expect(session.resources.state.drawerItems.isEmpty)
        #expect(!composition.model.isDrawerOpen)
        #expect(!composition.model.isDenMode)
    }

    @Test func choosingAnUnavailableDeskKeepsTheDrawerItem() throws {
        // Arrange
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let source = makeTestDesk("Source")
        let unavailable = makeTestDesk("Unavailable")
        let resources = DenProfileResources(
            state: DenState(desks: [source, unavailable], focusedDeskID: source.id, drawerItems: [item])
        )
        let session = ProfileWindowSession(
            resources: resources,
            configuration: makeTestBoardRuntimeConfiguration(),
            canPresentDesk: { $0 != unavailable.id }
        )
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        composition.model.openDrawer()
        composition.model.chooseSelectedDrawerItemPlacementDesk()

        // Act
        composition.model.selectDrawerPlacementDesk(by: 1)
        #expect(composition.model.drawer.placementDeskID == source.id)
        composition.model.placeDrawerItem(inDeskNumber: 9)
        composition.model.placeDrawerItem(inDeskNumber: 2)

        // Assert
        #expect(session.resources.state.drawerItems.map(\.id) == [item.id])
        #expect(composition.model.drawer.isChoosingPlacementDesk)
        #expect(session.navigation.presentedDeskID == source.id)
    }

    @Test(arguments: [2, 10]) func placingInANumberedDeskCreatesItsFirstBoard(number: Int) throws {
        // Arrange
        let item = DrawerItem(terminal: .shell(workingDirectory: "/tmp"))
        let source = makeTestDesk("Source")
        let destination = makeTestDesk("Empty")
        let intermediate = (2..<number).map { makeTestDesk("Desk \($0)") }
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenState(
                    desks: [source] + intermediate + [destination],
                    focusedDeskID: source.id,
                    drawerItems: [item]
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        composition.model.openDrawer()

        // Act
        composition.model.chooseSelectedDrawerItemPlacementDesk()
        composition.model.placeDrawerItem(inDeskNumber: number)

        // Assert
        #expect(session.navigation.presentedDeskID == destination.id)
        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [BoardID(item.id)])
        #expect(session.navigation.focusedDesk?.focusedBoardID == BoardID(item.id))
        #expect(session.resources.state.drawerItems.isEmpty)
    }

    @Test func keepPreservesDeskLayoutAndOpensNewestItem() throws {
        let existingBoard = makeDrawerTestBoard("Existing", url: "https://desk.example/")
        let source = makeTestDesk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
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
        let url = try #require(URL(string: "https://drawer.example/first"))

        session.drawer.keepInDrawer(url)

        #expect(session.navigation.focusedDesk == source)
        #expect(session.resources.state.drawerItems.map(\.url) == [url])
        #expect(windowModel.drawer.selectedItemID == session.resources.state.drawerItems[0].id)
        #expect(windowModel.drawer.expandedItemID == session.resources.state.drawerItems[0].id)
        #expect(windowModel.isDrawerOpen)
        #expect(savedState == session.resources.state)
    }

    @Test func externalURLCanOpenToRightOfFocusedBoard() throws {
        let first = makeDrawerTestBoard("First", width: 640)
        let focused = makeDrawerTestBoard("Focused", width: 880)
        let source = makeTestDesk("Desk", boards: [first, focused], focusedBoardID: focused.id)
        let suiteName = "ExternalLinkDestinationTests-\(UUID())"
        let defaults = makeTestDefaults(suiteName: suiteName)
        let preferences = AppPreferences(defaults: defaults)
        preferences.setExternalLinkDestination(.focusedBoard)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(
                sheetNavigation: makeTestSheetNavigationManager(),
                preferences: preferences
            )
        )
        let url = try #require(URL(string: "https://external.example/path"))

        session.input.handleExternalURL(url)

        #expect(session.navigation.focusedDesk?.boards.map(\.label) == ["First", "Focused", "external.example"])
        #expect(session.navigation.focusedDesk?.boards[2].width == focused.width)
        #expect(session.navigation.focusedDesk?.focusedBoardID == session.navigation.focusedDesk?.boards[2].id)
        #expect(session.resources.state.drawerItems.isEmpty)
        #expect(session.resources.recentItems == [.url(url)])
    }

    @Test func duplicateURLsRemainDistinctAndNewestComesFirst() throws {
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let url = try #require(URL(string: "https://example.com/"))

        session.drawer.keepInDrawer(url)
        let firstID = try #require(session.resources.state.drawerItems.first?.id)
        session.drawer.keepInDrawer(url)

        #expect(session.resources.state.drawerItems.count == 2)
        #expect(session.resources.state.drawerItems[0].id != firstID)
        #expect(session.resources.state.drawerItems[1].id == firstID)
    }

    @Test func backgroundKeepPreservesCurrentPeekSelection() throws {
        let source = makeTestDesk("Desk")
        let currentItem = DrawerItem(url: try #require(URL(string: "https://current.example/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [currentItem]
                    )
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.drawer.selectedItemID = currentItem.id
        windowModel.drawer.expandedItemID = currentItem.id
        let runtime = session.drawer.drawerRuntime(for: currentItem)

        let backgroundURL = try #require(URL(string: "https://background.example/"))
        session.drawer.keepInDrawerInBackground(backgroundURL)

        #expect(session.resources.state.drawerItems.map(\.url) == [backgroundURL, currentItem.url])
        #expect(windowModel.drawer.selectedItemID == currentItem.id)
        #expect(windowModel.drawer.expandedItemID == currentItem.id)
        #expect(session.windowResources.drawerPeek === runtime)
    }

    @Test func drawerPeekMovesBetweenWindowsAndKeepsSharedMetadata() throws {
        let item = DrawerItem(url: try #require(URL(string: "https://initial.example/")))
        try withSharedDrawerSessions(items: [item]) { first, second in
            let firstComposition = DenWindowComposition(session: first)
            let firstWindowModel = firstComposition.model
            firstComposition.connect()
            defer { firstComposition.disconnect() }
            let secondComposition = DenWindowComposition(session: second)
            let secondWindowModel = secondComposition.model
            secondComposition.connect()
            defer { secondComposition.disconnect() }
            firstWindowModel.focusDrawerItem(item.id)
            let firstRuntime = first.drawer.drawerRuntime(for: item)

            #expect(firstWindowModel.drawer.expandedItemID == item.id)
            #expect(secondWindowModel.drawer.expandedItemID == nil)

            secondWindowModel.focusDrawerItem(item.id)
            let secondRuntime = second.drawer.drawerRuntime(for: item)
            #expect(secondWindowModel.drawer.expandedItemID == item.id)
            #expect(firstRuntime === secondRuntime)
            #expect(firstWindowModel.drawer.expandedItemID == nil)
            #expect(first.windowResources.drawerPeek == nil)
            #expect(second.windowResources.drawerPeek === firstRuntime)

            let firstURL = try #require(URL(string: "https://first.example/"))
            let secondURL = try #require(URL(string: "https://second.example/"))
            firstRuntime.handleURLOrTitleChange(url: firstURL, title: "First")
            secondRuntime.handleURLOrTitleChange(url: secondURL, title: "Second")

            #expect(first.resources.state.drawerItems[0].url == secondURL)
            #expect(first.resources.state.drawerItems[0].title == "Second")
        }
    }

    @Test func moveBoardRemovesSourceWithoutOpeningDrawer() {
        let existingBoard = makeDrawerTestBoard("Reference", url: "https://example.com/reference")
        let source = makeTestDesk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
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

        session.drawer.moveBoardToDrawer(existingBoard.id)

        #expect(session.navigation.focusedBoard == nil)
        #expect(session.resources.recentlyRemovedBoards.isEmpty)
        #expect(session.resources.state.drawerItems.first?.url == existingBoard.currentSheetURL)
        #expect(session.resources.state.drawerItems.first?.title == existingBoard.displayName)
        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.temporaryContext == nil)
    }

    @Test func placementCreatesFocusedBoardAndRemovesItem() throws {
        let existingBoard = makeDrawerTestBoard("Existing", width: 2_480)
        let source = makeTestDesk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
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
        let url = try #require(URL(string: "https://placed.example/"))
        session.drawer.keepInDrawer(url)
        let itemID = try #require(windowModel.drawer.selectedItemID)

        windowModel.placeDrawerItemAsBoard(itemID)

        #expect(session.resources.state.drawerItems.isEmpty)
        #expect(
            session.navigation.focusedDesk?.boards.map(\.currentSheetURL) == [existingBoard.currentSheetURL, url]
        )
        #expect(session.navigation.focusedBoard?.currentSheetURL == url)
        #expect(session.navigation.focusedBoard?.width == existingBoard.width)
        #expect(session.resources.recentItems == [.url(url)])
        #expect(session.resources.recentlyDiscardedDrawerItems.isEmpty)
        #expect(!windowModel.isDrawerOpen)
    }

    @Test func placementTransfersLiveDocumentWithoutReloading() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "peek.html")
        try "<html><head><title>Live Peek</title></head><body></body></html>".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        let item = DrawerItem(url: url)
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item])
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration(
                sheetNavigation: makeTestSheetNavigationManager(scriptSource: "")
            )
        )
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer {
            composition.disconnect()
            session.runtimes.releaseRuntimes()
        }
        composition.model.focusDrawerItem(item.id)
        let peek = session.drawer.drawerRuntime(for: item)
        for _ in 0..<200 where peek.webView.title != "Live Peek" || peek.webView.isLoading {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(peek.webView.title == "Live Peek")
        let documentToken = try #require(
            try await peek.webView.evaluateJavaScript("window.documentToken = crypto.randomUUID()") as? String
        )

        // Act
        let boardID = try #require(session.drawer.placeDrawerItemAsBoard(item.id))
        let placed = try #require(session.resources.webRuntimes[boardID])
        let transferredToken = try await placed.webView.evaluateJavaScript("window.documentToken") as? String

        // Assert
        #expect(placed === peek)
        #expect(placed.boardID == boardID)
        #expect(placed.webView.navigationDelegate === placed)
        #expect(placed.webView.uiDelegate === placed)
        #expect(transferredToken == documentToken)
        #expect(!placed.webView.isLoading)
        #expect(session.navigation.focusedBoard?.label == "Live Peek")
        #expect(session.windowResources.drawerPeek == nil)
        #expect(session.resources.state.drawerItems.isEmpty)
    }

    @Test func placementPreservesDownloadsAndRoutesSubsequentChangesToBoard() throws {
        // Arrange
        let item = DrawerItem(url: try #require(URL(string: "https://peek.example/")))
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item])
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        defer { session.runtimes.releaseRuntimes() }
        let peek = session.drawer.drawerRuntime(for: item)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let temporaryURL = directory.appending(path: "download.part")
        let destinationURL = directory.appending(path: "download.txt")
        try Data("download contents".utf8).write(to: temporaryURL)
        let download = NSObject()
        let key = ObjectIdentifier(download)
        let downloadID = peek.downloadHandler.registerPendingDownload(
            for: key,
            destinationURL: destinationURL,
            temporaryURL: temporaryURL
        )
        let nextURL = try #require(URL(string: "https://peek.example/next"))

        // Act
        let boardID = try #require(session.drawer.placeDrawerItemAsBoard(item.id))
        session.runtimes.releaseWindowResources()
        peek.handleURLOrTitleChange(url: nextURL, title: "Continued")
        let downloadCompleted = peek.downloadHandler.completeDownload(for: key)

        // Assert
        #expect(session.resources.webRuntimes[boardID] === peek)
        #expect(peek.webView.navigationDelegate === peek)
        #expect(session.navigation.focusedBoard?.currentSheetURL == nextURL)
        #expect(session.navigation.focusedBoard?.label == "Continued")
        #expect(downloadCompleted)
        #expect(try Data(contentsOf: destinationURL) == Data("download contents".utf8))
        #expect(!peek.downloadHandler.activeActivities.contains { $0.id == downloadID })
        #expect(session.resources.state.drawerItems.isEmpty)
    }

    @Test func placementSwitchesPeekActionsAndFocusToBoard() throws {
        // Arrange
        let item = DrawerItem(url: try #require(URL(string: "https://peek.example/")))
        let source = makeTestDesk("Desk")
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        manager.setEnabled(true)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item])
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        defer { session.runtimes.releaseRuntimes() }
        let peek = session.drawer.drawerRuntime(for: item)
        let destination = try #require(URL(string: "https://board.example/"))

        // Act
        let boardID = try #require(session.drawer.placeDrawerItemAsBoard(item.id))
        let handled = peek.handleLinkNavigation(
            destination,
            navigationType: .linkActivated,
            modifierFlags: [.command, .shift],
            button: .primary,
            opensNewContext: false
        )
        let webView = try #require(peek.webView as? RuntimeWKWebView)
        let focusAllowedAfterLeaving = webView.isFocusAllowed()
        session.boardNavigation.focusBoard(boardID)
        let focusAllowedAfterReturning = webView.isFocusAllowed()
        let boardIDCopied = manager.handleScriptMessage(["action": "copyBoardID"], from: webView)

        // Assert
        #expect(handled)
        #expect(session.navigation.focusedDesk?.boards.count == 2)
        #expect(session.navigation.focusedDesk?.boards.last?.currentSheetURL == destination)
        #expect(session.resources.state.drawerItems.isEmpty)
        #expect(!focusAllowedAfterLeaving)
        #expect(focusAllowedAfterReturning)
        #expect(boardIDCopied)
        #expect(session.pasteboard.string(forType: .string) == boardID.rawValue.uuidString.lowercased())
    }

    @Test func failedPlacementKeepsPeekAndDrawerItem() throws {
        // Arrange
        let item = DrawerItem(url: try #require(URL(string: "https://preview.example/")))
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item])
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        defer { session.runtimes.releaseRuntimes() }
        let peek = session.drawer.drawerRuntime(for: item)

        // Act
        let boardID = session.drawer.placeDrawerItemAsBoard(item.id, deskID: DeskID())

        // Assert
        #expect(boardID == nil)
        #expect(session.windowResources.drawerPeek === peek)
        #expect(peek.webView.navigationDelegate === peek)
        #expect(session.resources.state.drawerItems == [item])
        #expect(session.resources.webRuntimes.isEmpty)
    }

    @Test func sharedPlacementTransfersTheSameRuntimeFromAnotherWindow() throws {
        // Arrange
        let item = DrawerItem(url: try #require(URL(string: "https://preview.example/")))
        try withSharedDrawerSessions(items: [item]) { first, second in
            let firstPeek = first.drawer.drawerRuntime(for: item)
            let secondPeek = second.drawer.drawerRuntime(for: item)

            // Act
            let boardID = try #require(first.drawer.placeDrawerItemAsBoard(item.id))

            // Assert
            #expect(first.resources.webRuntimes[boardID] === firstPeek)
            #expect(second.resources.webRuntimes[boardID] === firstPeek)
            #expect(firstPeek.webView.navigationDelegate === firstPeek)
            #expect(secondPeek === firstPeek)
            #expect(secondPeek.webView.navigationDelegate === secondPeek)
            #expect(first.resources.drawerRuntimes.web.isEmpty)
            #expect(first.windowResources.drawerPeek == nil)
            #expect(second.windowResources.drawerPeek == nil)
        }
    }

    @Test func placementTransfersCollapsedRuntime() throws {
        // Arrange
        let item = DrawerItem(url: try #require(URL(string: "https://retained.example/")))
        try withSharedDrawerSessions(items: [item]) { session, _ in
            defer { session.runtimes.releaseRuntimes() }
            let runtime = session.drawer.drawerRuntime(for: item)
            session.runtimes.releaseDrawerPeek()

            // Act
            let boardID = try #require(session.drawer.placeDrawerItemAsBoard(item.id))

            // Assert
            #expect(session.resources.webRuntimes[boardID] === runtime)
            #expect(runtime.boardID == boardID)
            #expect(runtime.webView.navigationDelegate === runtime)
            #expect(session.resources.drawerRuntimes.web.isEmpty)
            #expect(session.resources.state.drawerItems.isEmpty)
        }
    }

    @Test func keepAndPlaceReturnIdentifiersAndDiscardReturnsSuccess() throws {
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let url = try #require(URL(string: "https://drawer.example/item"))

        let itemID = session.drawer.keepInDrawer(url, title: "Test Item")
        #expect(itemID != nil)
        #expect(session.resources.state.drawerItems.first?.id == itemID)

        let placedBoardID = session.drawer.placeDrawerItemAsBoard(try #require(itemID))
        #expect(placedBoardID != nil)
        #expect(session.navigation.focusedBoard?.id == placedBoardID)
        #expect(session.resources.state.drawerItems.isEmpty)

        let secondURL = try #require(URL(string: "https://drawer.example/discard-me"))
        let secondItemID = try #require(session.drawer.keepInDrawer(secondURL))
        #expect(session.drawer.discardDrawerItem(secondItemID))
        #expect(!session.drawer.discardDrawerItem(secondItemID))
    }

    @Test func placementDoesNotAdvanceToAnotherDrawerPeek() throws {
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
        windowModel.placeDrawerItemAsBoard(second.id)

        #expect(session.resources.state.drawerItems.map(\.id) == [first.id])
        #expect(windowModel.drawer.expandedItemID == nil)
        #expect(!windowModel.isDrawerOpen)
    }
}
