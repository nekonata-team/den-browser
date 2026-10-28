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
struct NativeDrawerTests {
    @Test func drawerModelKeepsLiveInputsObservable() throws {
        let item = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))),
            configuration: makeTestBoardRuntimeConfiguration())
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
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [first, last]))), configuration: makeTestBoardRuntimeConfiguration())
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

    @Test func keepPreservesDeskLayoutAndOpensNewestItem() throws {
        let existingBoard = board("Existing", url: "https://desk.example/")
        let source = desk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())
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
        let first = board("First", width: 640)
        let focused = board("Focused", width: 880)
        let source = desk("Desk", boards: [first, focused], focusedBoardID: focused.id)
        let suiteName = "ExternalLinkDestinationTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setExternalLinkDestination(.focusedBoard)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration(
                sheetNavigation: makeTestSheetNavigationManager(), preferences: preferences))
        let url = try #require(URL(string: "https://external.example/path"))

        session.input.handleExternalURL(url)

        #expect(session.navigation.focusedDesk?.boards.map(\.label) == ["First", "Focused", "external.example"])
        #expect(session.navigation.focusedDesk?.boards[2].width == focused.width)
        #expect(session.navigation.focusedDesk?.focusedBoardID == session.navigation.focusedDesk?.boards[2].id)
        #expect(session.resources.state.drawerItems.isEmpty)
        #expect(session.resources.recentItems == [.url(url)])
    }

    @Test func duplicateURLsRemainDistinctAndNewestComesFirst() throws {
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let url = try #require(URL(string: "https://example.com/"))

        session.drawer.keepInDrawer(url)
        let firstID = try #require(session.resources.state.drawerItems.first?.id)
        session.drawer.keepInDrawer(url)

        #expect(session.resources.state.drawerItems.count == 2)
        #expect(session.resources.state.drawerItems[0].id != firstID)
        #expect(session.resources.state.drawerItems[1].id == firstID)
    }

    @Test func backgroundKeepPreservesCurrentPeekSelection() throws {
        let source = desk("Desk")
        let currentItem = DrawerItem(url: try #require(URL(string: "https://current.example/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [currentItem]))), configuration: makeTestBoardRuntimeConfiguration())
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

            #expect(firstWindowModel.drawerPendingDeletionCount == 2)
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

    @Test func filteringMatchesTitleHostAndURLAndKeepsSelectionInResults() throws {
        let source = desk("Desk")
        let items = [
            DrawerItem(
                url: try #require(URL(string: "https://example.com/reference")),
                title: "Swift Guide"),
            DrawerItem(url: try #require(URL(string: "https://news.example.org/releases"))),
        ]
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: items))),
            configuration: makeTestBoardRuntimeConfiguration())
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
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))),
            configuration: makeTestBoardRuntimeConfiguration())
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

    @Test func keepCurrentSheetCopiesWithoutOpeningDrawerOrChangingBoard() {
        let existingBoard = board("Reference", url: "https://example.com/reference")
        let source = desk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        session.drawer.keepFocusedSheetInDrawer()

        #expect(session.navigation.focusedBoard == existingBoard)
        #expect(session.resources.state.drawerItems.first?.url == existingBoard.currentSheetURL)
        #expect(session.resources.state.drawerItems.first?.title == existingBoard.displayName)
        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.temporaryContext == nil)
    }

    @Test func placementCreatesFocusedBoardAndRemovesItem() throws {
        let existingBoard = board("Existing", width: 2_480)
        let source = desk("Desk", boards: [existingBoard], focusedBoardID: existingBoard.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
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
            session.navigation.focusedDesk?.boards.map(\.currentSheetURL) == [existingBoard.currentSheetURL, url])
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
            to: url, atomically: true, encoding: .utf8)
        let item = DrawerItem(url: url)
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))),
            configuration: makeTestBoardRuntimeConfiguration(
                sheetNavigation: makeTestSheetNavigationManager(scriptSource: "")))
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
            try await peek.webView.evaluateJavaScript("window.documentToken = crypto.randomUUID()") as? String)

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
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))),
            configuration: makeTestBoardRuntimeConfiguration())
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
            for: key, destinationURL: destinationURL, temporaryURL: temporaryURL)
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
        let source = desk("Desk")
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        manager.setEnabled(true)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager))
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
            opensNewContext: false)
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
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))),
            configuration: makeTestBoardRuntimeConfiguration())
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

    @Test func keepAndPlaceReturnIdentifiersAndDiscardReturnsSuccess() throws {
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
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

    @Test func discardingSelectedItemSelectsItsNeighborAndClosesWhenEmpty() throws {
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
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
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://discarded.example/")))
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item])),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())

        session.drawer.discardDrawerItem(item.id)

        #expect(session.resources.recentlyDiscardedDrawerItems.map(\.id) == [item.id])
        let restoredSession = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(try #require(savedState))),
            configuration: makeTestBoardRuntimeConfiguration())
        #expect(restoredSession.resources.recentlyDiscardedDrawerItems.isEmpty)

        session.drawer.restoreRecentlyDiscardedDrawerItem()
        session.reset.resetDen()
        #expect(session.resources.recentlyDiscardedDrawerItems.isEmpty)
    }

    @Test func discardHistoryKeepsAtMostTenItemsAndRestoresNewestFirst() throws {
        let source = desk("Desk")
        let items = try (0..<12).map { index in
            DrawerItem(url: try #require(URL(string: "https://drawer-\(index).example/")))
        }
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: items))),
            configuration: makeTestBoardRuntimeConfiguration())

        for item in items.prefix(11) {
            session.drawer.discardDrawerItem(item.id)
        }

        #expect(session.resources.state.drawerItems.map(\.id) == [items[11].id])
        #expect(session.resources.recentlyDiscardedDrawerItems.count == DrawerItems.maximumDiscardHistoryCount)
        #expect(
            session.resources.recentlyDiscardedDrawerItems.map(\.id)
                == Array(items[1...10].reversed()).map(\.id))

        for _ in 0..<DrawerItems.maximumDiscardHistoryCount {
            session.drawer.restoreRecentlyDiscardedDrawerItem()
        }

        #expect(session.resources.recentlyDiscardedDrawerItems.isEmpty)
        #expect(session.resources.state.drawerItems.map(\.id) == Array(items[1...11]).map(\.id))
    }

    @Test func discardingExpandedItemDisposesItsPeekRuntime() throws {
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
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
        let source = desk("Desk")
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        let third = DrawerItem(url: try #require(URL(string: "https://third.example/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [first, second, third]))), configuration: makeTestBoardRuntimeConfiguration())
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
        let source = desk("Desk")
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [first, second]))), configuration: makeTestBoardRuntimeConfiguration())
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

    @Test func placementDoesNotAdvanceToAnotherDrawerPeek() throws {
        let source = desk("Desk")
        let first = DrawerItem(url: try #require(URL(string: "https://first.example/")))
        let second = DrawerItem(url: try #require(URL(string: "https://second.example/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [first, second]))), configuration: makeTestBoardRuntimeConfiguration())
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

    @Test func clearingDrawerRequiresConfirmationAndDisposesAllItems() throws {
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://first.example/")))
        session.drawer.keepInDrawer(try #require(URL(string: "https://second.example/")))
        _ = session.drawer.drawerRuntime(for: try #require(windowModel.drawer.selectedItem))

        session.drawer.requestDrawerClearConfirmation()

        #expect(session.resources.state.drawerItems.count == 2)
        #expect(windowModel.drawerPendingDeletionCount == 2)

        windowModel.confirmDrawerClear()

        #expect(session.resources.state.drawerItems.isEmpty)
        #expect(windowModel.drawerPendingDeletionCount == nil)
        #expect(windowModel.drawer.selectedItemID == nil)
        #expect(windowModel.drawer.expandedItemID == nil)
        #expect(session.windowResources.drawerPeek == nil)
        #expect(session.resources.recentlyDiscardedDrawerItems.count == 2)
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

    @Test func closingDrawerKeepsExpandedPeekForNextOpen() throws {
        let source = desk("Desk")
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())
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

    @Test func denModeKeyboardControlsOpenDrawer() throws {
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://first.example/")))
        session.drawer.keepInDrawer(try #require(URL(string: "https://second.example/")))
        windowModel.isDenMode = true

        #expect(
            KeyboardController.handle(
                try keyEvent(.downArrow, keyCode: 125), session: session, windowModel: windowModel))
        #expect(windowModel.drawer.selectedItemID == session.resources.state.drawerItems[1].id)
        #expect(windowModel.drawer.expandedItemID == session.resources.state.drawerItems[1].id)
        #expect(
            KeyboardController.handle(
                try keyEvent(.carriageReturn, keyCode: 36), session: session, windowModel: windowModel))
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
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [item]))), configuration: makeTestBoardRuntimeConfiguration())
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
        let source = desk("Desk")
        let first = DrawerItem(
            url: try #require(URL(string: "https://first.example/")),
            title: "First")
        let second = DrawerItem(
            url: try #require(URL(string: "https://second.example/")),
            title: "Second")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [first, second]))), configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        windowModel.toggleDrawer()

        #expect(
            KeyboardController.handle(try keyEvent("/", keyCode: 44), session: session, windowModel: windowModel))
        #expect(windowModel.drawer.filterPhase == .filtering)

        windowModel.drawer.setQuery("second")
        #expect(windowModel.drawer.selectedItemID == second.id)
        #expect(
            KeyboardController.handle(
                try keyEvent(.carriageReturn, keyCode: 36), session: session, windowModel: windowModel))
        #expect(windowModel.drawer.filterPhase == .selecting)
        #expect(windowModel.drawer.expandedItemID == nil)

        #expect(
            KeyboardController.handle(
                try keyEvent(.carriageReturn, keyCode: 36), session: session, windowModel: windowModel))
        #expect(windowModel.drawer.filterPhase == .inactive)
        #expect(windowModel.drawer.expandedItemID == second.id)
        #expect(windowModel.drawer.query.isEmpty)
        #expect(!windowModel.isDenMode)

        #expect(
            KeyboardController.handle(
                try keyEvent("\u{1B}", keyCode: 53), session: session, windowModel: windowModel))
        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == second.id)
    }

    @Test func drawerFilterKeepsSelectingPhaseWhenThereAreNoMatches() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [source],
                        focusedDeskID: source.id,
                        drawerItems: [item]))), configuration: makeTestBoardRuntimeConfiguration())
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
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
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
            KeyboardController.handle(try keyEvent("x", keyCode: 7), session: session, windowModel: windowModel))
        #expect(session.resources.state.drawerItems.map(\.id) == [itemIDs[0], itemIDs[1], itemIDs[3]])
        #expect(windowModel.drawer.selectedItemID == itemIDs[1])
        #expect(
            KeyboardController.handle(try keyEvent("d", keyCode: 2), session: session, windowModel: windowModel))
        #expect(session.resources.state.drawerItems.map(\.id) == [itemIDs[0], itemIDs[3]])
        #expect(windowModel.drawer.selectedItemID == itemIDs[3])
        #expect(windowModel.isDrawerOpen)
    }

    @Test func denModeKeyboardRestoresNewestDiscardedDrawerItemWithU() throws {
        let source = desk("Desk")
        let item = DrawerItem(url: try #require(URL(string: "https://restore.example/")))
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [source], focusedDeskID: source.id, drawerItems: [item]))),
            configuration: makeTestBoardRuntimeConfiguration())

        let composition = DenWindowComposition(session: session)

        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.openDrawer()
        windowModel.isDenMode = true
        session.drawer.discardDrawerItem(item.id)
        windowModel.openDrawer()
        windowModel.isDenMode = true

        #expect(
            KeyboardController.handle(try keyEvent("u", keyCode: 32), session: session, windowModel: windowModel))
        #expect(session.resources.state.drawerItems.map(\.id) == [item.id])
        #expect(session.resources.recentlyDiscardedDrawerItems.isEmpty)
        #expect(windowModel.drawer.selectedItemID == item.id)
        #expect(windowModel.drawer.expandedItemID == item.id)
        #expect(windowModel.isDenMode)
    }

    @Test func sheetInputLeavesVimStyleDrawerKeysUnclaimed() throws {
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
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
                    == .consume(.exclusiveContext))
            #expect(KeyboardController.handle(event, session: session, windowModel: windowModel))
        }
        let tab = try keyEvent(.tab, keyCode: 48)
        #expect(
            KeyboardController.decision(for: tab, session: session, windowModel: windowModel)
                == .consume(.exclusiveContext))
        #expect(KeyboardController.handle(tab, session: session, windowModel: windowModel))
        #expect(session.resources.state.drawerItems.count == 2)
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

    private func withSharedDrawerSessions<T>(
        items: [DrawerItem],
        body: (ProfileWindowSession, ProfileWindowSession) throws -> T
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
        let makeSession = { (deskID: DeskID) -> ProfileWindowSession in
            ProfileWindowSession(
                resources: storage,
                configuration: makeTestBoardRuntimeConfiguration(
                    websiteDataStore: websiteDataStore, sheetNavigation: sheetNavigation, preferences: preferences),
                presentedDeskID: deskID, canPresentDesk: { _ in true }, onDeskPresentationRequest: { _ in true },
                onWillResetDen: {})
        }
        return try body(makeSession(desks[0].id), makeSession(desks[1].id))
    }
}
