import AppKit
import DenApplication
import DenDomain
import DenModels
import DenViews
import Foundation
import GhosttyTerminal
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct WebPopupBoardTests {
    @Test func popupBoardKeepsItsOpenerRequestAndUsesTheProvidedWebView() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let session = makeTestPopupSession(for: sourceBoard)
        defer { session.runtimes.releaseRuntimes() }

        let popupURL = try #require(URL(string: "https://login.example/authorize"))
        let backgroundPopup = RuntimeWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // Act
        #expect(
            session.boardOpening.createPopupBoard(
                backgroundPopup,
                requestedURL: popupURL,
                fromBoardID: sourceBoard.id,
                modifierFlags: .command
            )
        )
        let backgroundBoard = try #require(session.resources.state.desks[0].boards.first { $0.id != sourceBoard.id })

        // Assert
        #expect(session.navigation.focusedBoard?.id == sourceBoard.id)
        #expect(backgroundBoard.currentSheetURL == popupURL)
        #expect(backgroundBoard.firstSheetURL == popupURL)
        #expect(session.resources.webRuntimes[backgroundBoard.id]?.webView === backgroundPopup)
        #expect(backgroundPopup.url == nil)
    }

    @Test func commandShiftPopupFocusesItsBoard() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let session = makeTestPopupSession(for: sourceBoard)
        defer { session.runtimes.releaseRuntimes() }
        let popup = RuntimeWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // Act
        #expect(
            session.boardOpening.createPopupBoard(
                popup,
                requestedURL: nil,
                fromBoardID: sourceBoard.id,
                modifierFlags: [.command, .shift]
            )
        )

        // Assert
        let focusedBoard = try #require(session.navigation.focusedBoard)
        #expect(focusedBoard.id != sourceBoard.id)
        #expect(focusedBoard.currentSheetURL == nil)
        #expect(session.resources.webRuntimes[focusedBoard.id]?.webView === popup)
        #expect(popup.url == nil)
    }

    @Test func popupBoardFocusesByDefault() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let session = makeTestPopupSession(for: sourceBoard)
        defer { session.runtimes.releaseRuntimes() }
        let popup = RuntimeWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // Act
        #expect(
            session.boardOpening.createPopupBoard(
                popup,
                requestedURL: nil,
                fromBoardID: sourceBoard.id,
                modifierFlags: []
            )
        )

        // Assert
        let focusedBoard = try #require(session.navigation.focusedBoard)
        #expect(focusedBoard.id != sourceBoard.id)
        #expect(session.resources.webRuntimes[focusedBoard.id]?.webView === popup)
    }

    @Test func closingPopupWebViewRemovesItsBoard() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let session = makeTestPopupSession(for: sourceBoard)
        defer { session.runtimes.releaseRuntimes() }
        let popup = RuntimeWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        #expect(
            session.boardOpening.createPopupBoard(
                popup,
                requestedURL: nil,
                fromBoardID: sourceBoard.id,
                modifierFlags: []
            )
        )
        let popupBoard = try #require(session.navigation.focusedBoard)

        // Act
        session.resources.webRuntimes[popupBoard.id]?.webViewDidClose(popup)

        // Assert
        #expect(session.resources.state.board(for: popupBoard.id) == nil)
        #expect(session.resources.webRuntimes[popupBoard.id] == nil)
    }

    @Test func windowOpenPopupPreservesOpenerPostMessage() async throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let session = makeTestPopupSession(for: sourceBoard)
        defer { session.runtimes.releaseRuntimes() }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = session.configuration.websiteDataStore
        configuration.userContentController = session.configuration.sheetNavigation.userContentController
        let sourceWebView = RuntimeWKWebView(frame: .zero, configuration: configuration)
        let sourceRuntime = session.runtimes.webRuntime(for: sourceBoard, popupWebView: sourceWebView)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <title>Ready</title>
            <script>
            window.addEventListener('message', event => {
                document.title = event.data;
            });
            </script>
            """,
            baseURL: URL(string: "file:///tmp/window-open-popup-test.html")!,
            in: sourceRuntime.webView
        )
        sourceRuntime.webView.navigationDelegate = sourceRuntime

        // Act
        _ = try await sourceRuntime.webView.evaluateJavaScript(
            "window.open('about:blank', '_blank'); true"
        )
        let popupBoard = try #require(session.resources.state.desks[0].boards.first { $0.id != sourceBoard.id })
        let popupRuntime = try #require(session.resources.webRuntimes[popupBoard.id])
        _ = try await popupRuntime.webView.evaluateJavaScript(
            "window.opener.postMessage('popup-message', '*')"
        )
        try await SheetInteraction.waitForFunction(
            expression: "document.title === 'popup-message'",
            in: sourceRuntime.webView,
            timeout: 5
        )

        // Assert
        #expect(popupRuntime.webView !== sourceRuntime.webView)
        #expect(popupRuntime.webView.uiDelegate === popupRuntime)
        #expect(try await sourceRuntime.webView.evaluateJavaScript("document.title") as? String == "popup-message")
    }

    @Test func timerTriggeredJavaScriptPopupCreatesBoard() async throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let session = makeTestPopupSession(for: sourceBoard)
        defer { session.runtimes.releaseRuntimes() }
        let sourceRuntime = session.runtimes.webRuntime(for: sourceBoard)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <title>Waiting</title>
            <script>
            setTimeout(() => {
                const popup = window.open('about:blank', '_blank');
                document.title = popup === null ? 'Blocked' : 'Opened';
            }, 0);
            </script>
            """,
            baseURL: URL(string: "file:///tmp/timer-popup-test.html")!,
            in: sourceRuntime.webView
        )
        sourceRuntime.webView.navigationDelegate = sourceRuntime

        // Act
        try await SheetInteraction.waitForFunction(
            expression: "document.title === 'Opened'",
            in: sourceRuntime.webView,
            timeout: 5
        )

        // Assert
        #expect(session.resources.state.desks[0].boards.count == 2)
        #expect(session.resources.state.desks[0].boards[1].id != sourceBoard.id)
    }
}
