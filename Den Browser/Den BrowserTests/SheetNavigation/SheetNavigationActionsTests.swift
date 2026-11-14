import AppKit
import Combine
import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct SheetNavigationActionsTests {
    @Test func sheetNavigationCanOpenLinkAsAdjacentBoard() {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let source = makeTestBoard("Source", url: "https://source.example/")
        let focused = makeTestBoard("Focused", url: "https://focused.example/")
        let currentDesk = makeTestDesk("Desk", boards: [source, focused], focusedBoardID: focused.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [currentDesk], focusedDeskID: currentDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let sourceWebView = session.runtimes.webRuntime(for: source).webView
        manager.setEnabled(true)

        #expect(
            manager.handleScriptMessage(
                [
                    "action": "openBoard",
                    "url": "https://destination.example/path",
                ],
                from: sourceWebView
            )
        )
        #expect(
            session.navigation.focusedDesk?.boards.map(\.currentSheetURL) == [
                URL(string: "https://source.example/"),
                URL(string: "https://destination.example/path"),
                URL(string: "https://focused.example/"),
            ]
        )
        #expect(session.navigation.focusedDesk?.focusedBoardID == session.navigation.focusedDesk?.boards[1].id)
    }

    @Test func sheetNavigationCanOpenAndKeepLocalFileLinks() throws {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let source = makeTestBoard("Source", url: "https://source.example/")
        let currentDesk = makeTestDesk("Desk", boards: [source], focusedBoardID: source.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [currentDesk], focusedDeskID: currentDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let sourceWebView = session.runtimes.webRuntime(for: source).webView
        let fileURL = try #require(URL(string: "file:///tmp/Den%20Browser/reference.html"))
        manager.setEnabled(true)

        #expect(
            manager.handleScriptMessage(
                ["action": "openBoard", "url": fileURL.absoluteString],
                from: sourceWebView
            )
        )
        #expect(session.navigation.focusedBoard?.currentSheetURL == fileURL)

        #expect(
            manager.handleScriptMessage(
                ["action": "keepInDrawer", "url": fileURL.absoluteString],
                from: sourceWebView
            )
        )
        #expect(session.resources.state.drawerItems.first?.url == fileURL)
    }

    @Test func sheetNavigationShowsFeedbackForCopyAndInvalidPaste() async throws {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let source = makeTestBoard("Source", url: "https://source.example/")
        let currentDesk = makeTestDesk("Desk", boards: [source], focusedBoardID: source.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [currentDesk], focusedDeskID: currentDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let webView = session.runtimes.webRuntime(for: source).webView
        let waiter = WebViewLoadWaiter()

        manager.setEnabled(true)
        await waiter.load("<html>Current Sheet</html>", baseURL: URL(string: "https://source.example/")!, in: webView)
        defer { manager.pasteboard.clearContents() }

        #expect(manager.handleScriptMessage(["action": "copyURL"], from: webView))
        #expect(session.feedback.latest?.message == "Copied Current Sheet URL.")

        #expect(
            manager.handleScriptMessage(
                ["action": "copyMarkdownLink", "title": "Example [Page]\n Title "],
                from: webView
            )
        )
        #expect(session.feedback.latest?.message == "Copied Current Sheet Markdown link.")
        #expect(
            manager.pasteboard.string(forType: .string)
                == "[Example \\[Page\\] Title](https://source.example/)"
        )

        manager.pasteboard.clearContents()
        #expect(
            manager.pasteboard.setString(
                "https://pasted.example/long-\npath",
                forType: .string
            )
        )
        #expect(manager.handleScriptMessage(["action": "pasteURL"], from: webView))
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://pasted.example/long-path"))

        manager.pasteboard.clearContents()
        #expect(
            manager.pasteboard.setString(
                "https://pasted.example/new-\nboard",
                forType: .string
            )
        )
        #expect(manager.handleScriptMessage(["action": "pasteURLInNewBoard"], from: webView))
        #expect(session.navigation.focusedDesk?.boards.count == 2)
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://pasted.example/new-board"))

        manager.pasteboard.clearContents()
        for action in ["pasteURL", "pasteURLInNewBoard"] {
            #expect(!manager.handleScriptMessage(["action": action], from: webView))
            #expect(session.feedback.latest?.message == "Clipboard does not contain a supported URL.")
        }
    }

    @Test func drawerPeekShowsFeedbackForCopyAndInvalidPaste() async throws {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let item = DrawerItem(url: try #require(URL(string: "https://drawer.example/")))
        let desk = DeskState(label: "Desk", boards: [])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [desk],
                        focusedDeskID: desk.id,
                        drawerItems: [item]
                    )
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let runtime = session.drawer.drawerRuntime(for: item)
        let waiter = WebViewLoadWaiter()

        manager.setEnabled(true)
        await waiter.load("<html>Drawer Peek</html>", baseURL: try #require(item.url), in: runtime.webView)
        defer {
            session.runtimes.releaseDrawerPeek()
            manager.pasteboard.clearContents()
        }

        #expect(manager.handleScriptMessage(["action": "copyURL"], from: runtime.webView))
        #expect(session.feedback.latest?.message == "Copied Current Sheet URL.")

        #expect(
            manager.handleScriptMessage(
                ["action": "copyMarkdownLink", "title": "Drawer Peek"],
                from: runtime.webView
            )
        )
        #expect(session.feedback.latest?.message == "Copied Current Sheet Markdown link.")
        #expect(
            manager.pasteboard.string(forType: .string)
                == "[Drawer Peek](https://drawer.example/)"
        )

        manager.pasteboard.clearContents()
        for action in ["pasteURL", "pasteURLInNewBoard"] {
            #expect(!manager.handleScriptMessage(["action": action], from: runtime.webView))
            #expect(session.feedback.latest?.message == "Clipboard does not contain a supported URL.")
        }
    }

    @Test func sheetNavigationReportsCopyFailureWithoutCurrentURL() {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let webView = WKWebView()
        var didReportFailure = false
        manager.didOpen(
            webView,
            actions: .init(onCopyURLFailed: { didReportFailure = true })
        )
        manager.setEnabled(true)

        #expect(!manager.handleScriptMessage(["action": "copyURL"], from: webView))
        #expect(didReportFailure)
    }

    @Test func sheetNavigationReportsCopyMarkdownLinkFailureWithoutCurrentURL() {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let webView = WKWebView()
        var didReportFailure = false
        manager.didOpen(
            webView,
            actions: .init(onCopyMarkdownLinkFailed: { didReportFailure = true })
        )
        manager.setEnabled(true)

        #expect(!manager.handleScriptMessage(["action": "copyMarkdownLink"], from: webView))
        #expect(didReportFailure)
    }

    @Test func markdownLinkFormatsAndEscapesTitleCorrectly() {
        let url = URL(string: "https://example.com/path")!

        #expect(
            SheetNavigationManager.markdownLink(title: "Hello World", url: url)
                == "[Hello World](https://example.com/path)"
        )
        #expect(
            SheetNavigationManager.markdownLink(title: "  Hello \n\t World  ", url: url)
                == "[Hello World](https://example.com/path)"
        )
        #expect(
            SheetNavigationManager.markdownLink(title: "Swift [5.10] Release [Notes]", url: url)
                == "[Swift \\[5.10\\] Release \\[Notes\\]](https://example.com/path)"
        )
        #expect(
            SheetNavigationManager.markdownLink(title: "", url: url)
                == "[https://example.com/path](https://example.com/path)"
        )
        #expect(
            SheetNavigationManager.markdownLink(title: "   \n  ", url: url)
                == "[https://example.com/path](https://example.com/path)"
        )
    }

    @Test func commandClickCanOpenLinkWhenSheetNavigationIsDisabled() {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let source = makeTestBoard("Source", url: "https://source.example/")
        let currentDesk = makeTestDesk("Desk", boards: [source], focusedBoardID: source.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [currentDesk], focusedDeskID: currentDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let sourceWebView = session.runtimes.webRuntime(for: source).webView

        #expect(
            manager.handleScriptMessage(
                [
                    "action": "commandOpenBoard",
                    "url": "https://destination.example/path",
                ],
                from: sourceWebView
            )
        )
        #expect(
            session.navigation.focusedDesk?.boards.map(\.currentSheetURL) == [
                URL(string: "https://source.example/"),
                URL(string: "https://destination.example/path"),
            ]
        )
        #expect(session.navigation.focusedDesk?.focusedBoardID == source.id)

        #expect(
            manager.handleScriptMessage(
                [
                    "action": "commandOpenBoard",
                    "url": "https://focused.example/path",
                    "focused": true,
                ],
                from: sourceWebView
            )
        )
        #expect(
            session.navigation.focusedDesk?.boards.map(\.currentSheetURL) == [
                URL(string: "https://source.example/"),
                URL(string: "https://focused.example/path"),
                URL(string: "https://destination.example/path"),
            ]
        )
        #expect(session.navigation.focusedDesk?.focusedBoardID == session.navigation.focusedDesk?.boards[1].id)
    }

    @Test func optionClickKeepsLinkInDrawerWithoutOpeningIt() {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let source = makeTestBoard("Source", url: "https://source.example/")
        let currentDesk = makeTestDesk("Desk", boards: [source], focusedBoardID: source.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [currentDesk], focusedDeskID: currentDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let sourceWebView = session.runtimes.webRuntime(for: source).webView
        let destination = URL(string: "https://destination.example/path")!

        #expect(
            manager.handleScriptMessage(
                [
                    "action": "keepInDrawer",
                    "url": destination.absoluteString,
                ],
                from: sourceWebView
            )
        )
        #expect(session.resources.state.drawerItems.map(\.url) == [destination])
        #expect(!windowModel.isDrawerOpen)
        #expect(session.navigation.focusedDesk?.focusedBoardID == source.id)
        #expect(session.navigation.focusedBoard?.currentSheetURL == source.currentSheetURL)
    }

    @Test func sheetNavigationRoutesRemoveAndRestoreBoardActions() {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let source = makeTestBoard("First", url: "https://first.example/")
        let second = makeTestBoard("Second", url: "https://second.example/")
        let currentDesk = makeTestDesk("Desk", boards: [source, second], focusedBoardID: source.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [currentDesk], focusedDeskID: currentDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let sourceWebView = session.runtimes.webRuntime(for: source).webView
        let secondWebView = session.runtimes.webRuntime(for: second).webView
        manager.setEnabled(true)

        #expect(session.navigation.focusedDesk?.boards.count == 2)
        #expect(manager.handleScriptMessage(["action": "removeBoard"], from: sourceWebView))
        #expect(session.navigation.focusedDesk?.boards.count == 1)

        #expect(manager.handleScriptMessage(["action": "restoreBoard"], from: secondWebView))
        #expect(session.navigation.focusedDesk?.boards.count == 2)
    }

    @Test func sheetNavigationRejectsUnsupportedMessages() {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let webView = WKWebView()

        #expect(
            !manager.handleScriptMessage(
                ["action": "openBoard", "url": "https://example.com/"],
                from: webView
            )
        )
        manager.setEnabled(true)
        #expect(
            !manager.handleScriptMessage(
                ["action": "openBoard", "url": "mailto:user@example.com"],
                from: webView
            )
        )
        #expect(
            !manager.handleScriptMessage(
                ["action": "unknown", "url": "https://example.com/"],
                from: webView
            )
        )
        #expect(!manager.handleScriptMessage(["action": "openBoard"], from: webView))
    }

    @Test func sheetNavigationRoutesCurrentSheetActionsToDenPanels() async throws {
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        let board = makeTestBoard("Source", url: "https://source.example/")
        let desk = makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let webView = session.runtimes.webRuntime(for: board).webView
        let waiter = WebViewLoadWaiter()
        let url = URL(string: "https://source.example/current")!

        manager.setEnabled(true)
        await waiter.load("<html>Current Sheet</html>", baseURL: url, in: webView)

        #expect(manager.handleScriptMessage(["action": "editCurrentSheet"], from: webView))
        #expect(windowModel.isEditBoardLinkPanelPresented)

        windowModel.hideEditBoardLinkPanel()
        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("Shift", shift: true, in: webView)
        try await dispatchSheetKey("E", shift: true, in: webView)
        #expect(windowModel.isOpenBoardPanelPresented)
        #expect(windowModel.openBoard.initialURL == url)

        windowModel.hideOpenBoardPanel()
        try await dispatchSheetKey("t", in: webView)
        #expect(windowModel.isOpenBoardPanelPresented)

        windowModel.hideOpenBoardPanel()
        try await dispatchSheetKey("T", shift: true, in: webView)
        #expect(windowModel.isOverviewPresented)

        windowModel.hideOverview()
        try await dispatchSheetKey("o", in: webView)
        #expect(windowModel.temporaryContext == .essentialsPrefix)
    }

    @Test func sheetNavigationDispatchesYmToCopyMarkdownLink() async throws {
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        let board = makeTestBoard("Source", url: "https://source.example/")
        let desk = makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let webView = session.runtimes.webRuntime(for: board).webView
        let waiter = WebViewLoadWaiter()

        manager.setEnabled(true)
        await waiter.load(
            "<html><head><title>My Sheet</title></head><body>Hello</body></html>",
            baseURL: URL(string: "https://source.example/sheet")!,
            in: webView
        )
        defer { manager.pasteboard.clearContents() }

        try await dispatchSheetKey("y", in: webView)
        try await dispatchSheetKey("m", in: webView)

        #expect(session.feedback.latest?.message == "Copied Current Sheet Markdown link.")
        #expect(manager.pasteboard.string(forType: .string) == "[My Sheet](https://source.example/sheet)")
    }

    @Test func sheetNavigationDispatchesYbToCopyBoardID() async throws {
        // Arrange
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        let board = makeTestBoard("Source", url: "https://source.example/")
        let desk = makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let webView = session.runtimes.webRuntime(for: board).webView
        let waiter = WebViewLoadWaiter()

        manager.setEnabled(true)
        await waiter.load(
            "<html><body>Current Sheet</body></html>",
            baseURL: URL(string: "https://source.example/sheet")!,
            in: webView
        )
        defer { manager.pasteboard.clearContents() }

        // Act
        try await dispatchSheetKey("y", in: webView)
        try await dispatchSheetKey("b", in: webView)

        // Assert
        #expect(session.feedback.latest?.message == "Copied Board ID.")
        #expect(manager.pasteboard.string(forType: .string) == board.id.rawValue.uuidString.lowercased())
    }

    @Test func sheetNavigationRoutesBoardBoundaryCommands() async throws {
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        let boards = [makeTestBoard("First"), makeTestBoard("Middle"), makeTestBoard("Last")]
        let currentDesk = makeTestDesk("Desk", boards: boards, focusedBoardID: boards[1].id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [currentDesk], focusedDeskID: currentDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let webView = session.runtimes.webRuntime(for: boards[1]).webView
        let waiter = WebViewLoadWaiter()

        manager.setEnabled(true)
        await waiter.load("<html>Current Sheet</html>", baseURL: URL(string: "https://example.com/")!, in: webView)

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("T", shift: true, in: webView)
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("t", in: webView)
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[2].id)

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("0", in: webView)
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("$", shift: true, in: webView)
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[2].id)

        #expect(manager.handleScriptMessage(["action": "goToFirstSheet"], from: webView))
        #expect(manager.handleScriptMessage(["action": "goToLatestSheet"], from: webView))
    }

    @Test func sheetNavigationRemovesBoardAndFocusesNextBoard() async throws {
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        let boards = [makeTestBoard("First"), makeTestBoard("Middle"), makeTestBoard("Last")]
        let currentDesk = makeTestDesk("Desk", boards: boards, focusedBoardID: boards[1].id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [currentDesk], focusedDeskID: currentDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let webView = session.runtimes.webRuntime(for: boards[1]).webView
        let waiter = WebViewLoadWaiter()

        manager.setEnabled(true)
        await waiter.load("<html>Current Sheet</html>", baseURL: URL(string: "https://example.com/")!, in: webView)

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("x", in: webView)

        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [boards[0].id, boards[2].id])
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[2].id)
    }
}
