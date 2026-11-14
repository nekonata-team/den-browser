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
struct BoardOpeningTests {
    @Test func boardLinkFocusIntentDoesNotConsumeNewerIntent() {
        let firstBoard = BoardState(label: "First", width: 520, currentSheetURL: nil)
        let secondBoard = BoardState(label: "Second", width: 520, currentSheetURL: nil)
        let source = makeTestDesk("Desk", boards: [firstBoard, secondBoard], focusedBoardID: firstBoard.id)
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session, windowModel in
            ({
                session.boardNavigation.prepareBoardLinkFocus(firstBoard.id)
                #expect(windowModel.pendingBoardLinkFocus != nil)
                guard let firstIntent = windowModel.pendingBoardLinkFocus else { return }
                #expect(firstIntent.origin == .interactive)
                session.boardNavigation.prepareBoardLinkFocus(secondBoard.id)
                #expect(windowModel.pendingBoardLinkFocus != nil)
                guard let secondIntent = windowModel.pendingBoardLinkFocus else { return }

                windowModel.consumeBoardLinkFocus(firstIntent)
                #expect(windowModel.pendingBoardLinkFocus == secondIntent)

                windowModel.consumeBoardLinkFocus(secondIntent)
                #expect(windowModel.pendingBoardLinkFocus == nil)
            })()
        }
    }

    @Test func focusedBoardCreationEndsLinkFocusSuppression() throws {
        let source = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let desk = makeTestDesk("Desk", boards: [source], focusedBoardID: source.id)
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))
            )
        ) { session, windowModel in
            session.boardNavigation.prepareBoardLinkFocus(source.id)
            #expect(
                session.boardOpening.createBoard(
                    urlString: "https://focused.example",
                    afterBoardID: source.id
                ) != nil
            )

            #expect(windowModel.pendingBoardLinkFocus == nil)
            #expect(session.navigation.focusedBoard?.currentSheetURL?.host == "focused.example")
        }
    }

    @Test func backgroundBoardFocusSuppressionEndsOnNextFocus() throws {
        let source = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let other = BoardState(label: "Other", width: 520, currentSheetURL: nil)
        let desk = makeTestDesk("Desk", boards: [source, other], focusedBoardID: source.id)
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))
            )
        ) { session, windowModel in
            #expect(
                session.boardOpening.createBoard(
                    urlString: "https://background.example",
                    afterBoardID: source.id,
                    focus: false
                ) != nil
            )
            let intent = try #require(windowModel.pendingBoardLinkFocus)
            #expect(intent.origin == .interactive)
            #expect(session.navigation.focusedBoard?.id == source.id)

            session.boardNavigation.focusBoard(other.id)

            #expect(windowModel.pendingBoardLinkFocus == nil)
            windowModel.consumeBoardLinkFocus(intent)
            #expect(windowModel.pendingBoardLinkFocus == nil)
        }
    }

    @Test func cliBackgroundBoardCarriesCLIInsertionOrigin() throws {
        let source = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let other = BoardState(label: "Other", width: 520, currentSheetURL: nil)
        let desk = makeTestDesk("Desk", boards: [source, other], focusedBoardID: source.id)
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))
            )
        ) { session, windowModel in
            #expect(
                session.boardOpening.createBoard(
                    urlString: "https://cli.example",
                    afterBoardID: source.id,
                    focus: false,
                    origin: .cli
                ) != nil
            )
            let intent = try #require(windowModel.pendingBoardLinkFocus)

            #expect(intent.origin == .cli)
        }
    }

    @Test func cliBackgroundBoardRemovalCarriesCLIOperationOrigin() throws {
        let left = BoardState(label: "Left", width: 520, currentSheetURL: nil)
        let focused = BoardState(label: "Focused", width: 520, currentSheetURL: nil)
        let source = makeTestDesk("Desk", boards: [left, focused], focusedBoardID: focused.id)
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session, windowModel in
            session.boardRemoval.removeBoard(left.id, origin: .cli)

            let intent = try #require(windowModel.pendingBoardRemoval)
            #expect(intent.origin == .cli)
            #expect(session.navigation.focusedBoard?.id == focused.id)
        }
    }

    @Test func terminalLinkCreatesFocusedBoardWithoutDrawer() throws {
        // Arrange
        let terminal = BoardState(width: 520, workingDirectory: "/tmp")
        let source = makeTestDesk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let url = try #require(URL(string: "https://terminal-link.example/path"))
        defer { session.runtimes.releaseRuntimes() }

        // Act
        session.runtimes.terminalRuntime(for: terminal).terminalDidRequestOpenURL(url.absoluteString, kind: .text)

        // Assert
        let createdBoard = try #require(session.navigation.focusedDesk?.boards.last)
        #expect(createdBoard.currentSheetURL == url)
        #expect(session.navigation.focusedDesk?.focusedBoardID == createdBoard.id)
        #expect(session.resources.state.drawerItems.isEmpty)
        #expect(session.resources.recentItems == [.url(url)])
    }

    @Test func searchesUseCurrentEngineAndPreserveQueryAndExplicitURLs() throws {
        try withTestSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState()))
        ) { session in
            let query = "日本語 & C++ # Swift?"
            for engine in SearchEngine.allCases {
                session.configuration.preferences.setSearchEngine(engine)
                session.boardOpening.openBoard(recentItem: .search(query))
                let url = try #require(session.navigation.focusedBoard?.currentSheetURL)
                let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
                #expect(components.host == URL(string: engine.searchURL)?.host)
                #expect(components.path == URL(string: engine.searchURL)?.path)
                let queryParameter = engine == .yahooJapan ? "p" : "q"
                #expect(components.queryItems == [URLQueryItem(name: queryParameter, value: query)])
                #expect(components.fragment == nil)
                #expect(session.resources.recentItems.first == .search(query))
            }
            let existingURL = session.navigation.focusedBoard?.currentSheetURL
            session.configuration.preferences.setSearchEngine(.duckDuckGo)
            #expect(session.navigation.focusedBoard?.currentSheetURL == existingURL)
            #expect(session.boardOpening.navigateFocusedBoard(urlString: "example.com/path?q=literal"))
            #expect(
                session.navigation.focusedBoard?.currentSheetURL
                    == URL(string: "https://example.com/path?q=literal")
            )
            #expect(session.boardOpening.navigateFocusedBoard(urlString: query))
            #expect(session.navigation.focusedBoard?.currentSheetURL?.host == "duckduckgo.com")
        }
    }

    @Test func openBoardAcceptsWebHostsAndRejectsInvalidURLs() throws {
        try withTestSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState()))
        ) { session in
            _ = session.boardOpening.createBoard(urlString: "localhost:3000")
            let localURL = try #require(session.navigation.focusedDesk?.boards.last?.currentSheetURL)
            #expect(localURL.scheme == "https")
            #expect(localURL.host == "localhost")
            #expect(localURL.port == 3000)

            _ = session.boardOpening.createBoard(urlString: "swift: concurrency")
            let searchURL = try #require(
                session.navigation.focusedDesk?.boards.last?.currentSheetURL
                    .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            )
            #expect(searchURL.host == "www.google.com")
            #expect(searchURL.queryItems == [URLQueryItem(name: "q", value: "swift: concurrency")])

            let boardCount = try #require(session.navigation.focusedDesk?.boards.count)
            #expect(session.boardOpening.createBoard(urlString: "https://") == nil)
            #expect(session.boardOpening.createBoard(urlString: "ftp://example.com") == nil)
            #expect(session.navigation.focusedDesk?.boards.count == boardCount)
        }
    }

    @Test func localFileURLParticipatesInBoardRecentDrawerAndPresetWorkflows() throws {
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let fileURL = try #require(URL(string: "file:///tmp/Den%20Browser/index.html#notes"))

        session.boardOpening.openBoard(input: fileURL.absoluteString)

        #expect(session.navigation.focusedBoard?.currentSheetURL == fileURL)
        #expect(session.navigation.focusedBoard?.firstSheetURL == fileURL)
        #expect(session.resources.recentItems.first == .url(fileURL))

        session.drawer.keepInDrawer(fileURL)
        #expect(session.resources.state.drawerItems.first?.url == fileURL)

        #expect(session.presets.saveFocusedDeskAsPreset(label: "Local Files") == .created)
        #expect(session.resources.deskPresets.first?.boards.first?.initialSheetURL == fileURL)
    }

    @Test func editingFocusedBoardLinkReplacesCurrentSheet() throws {
        let board = makeTestBoard("Board", url: "https://before.example/")
        let source = makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)
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

        windowModel.showEditBoardLinkPanel()

        #expect(session.boardOpening.navigateFocusedBoard(urlString: "after.example/path"))
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://after.example/path"))
        #expect(session.navigation.focusedBoard?.firstSheetURL == URL(string: "https://before.example/"))
        #expect(windowModel.temporaryContext == nil)
        #expect(!windowModel.isDenMode)
    }

    @Test func newBoardKeepsFirstSheetWhenCurrentSheetChanges() throws {
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        _ = session.boardOpening.createBoard(urlString: "https://start.example/")
        let firstSheetURL = try #require(session.navigation.focusedBoard?.firstSheetURL)

        #expect(session.boardOpening.navigateFocusedBoard(urlString: "https://later.example/"))
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://later.example/"))
        #expect(session.navigation.focusedBoard?.firstSheetURL == firstSheetURL)
    }

    @Test func openBoardCanInsertAfterSpecifiedBoard() {
        let boards = [makeTestBoard("First"), makeTestBoard("Focused"), makeTestBoard("Last")]
        let source = makeTestDesk("Desk", boards: boards, focusedBoardID: boards[1].id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.boardOpening.openBoard(input: "example.com", afterBoardID: boards.last?.id)

        #expect(session.navigation.focusedDesk?.boards.map(\.label) == ["First", "Focused", "Last", "example.com"])
        #expect(session.navigation.focusedDesk?.focusedBoardID == session.navigation.focusedDesk?.boards.last?.id)
    }

    @Test func newBoardKeepsPreferredWidthBeyondManualResizeLimit() {
        for width in [BoardState.minimumWidth, BoardState.maximumWidth, 2_480] {
            let source = makeTestDesk("Desk")
            let session = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
                ),
                configuration: makeTestBoardRuntimeConfiguration()
            )

            _ = session.boardOpening.createBoard(urlString: "https://example.com", preferredWidth: width)

            #expect(session.navigation.focusedBoard?.width == width)
        }
    }

    @Test func newBoardInheritsFocusedWidthWhenPreferredWidthIsUnset() {
        let source = makeTestBoard("Source", width: 760)
        let focusedDesk = makeTestDesk("Focused", boards: [source], focusedBoardID: source.id)
        let focusedSession = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [focusedDesk], focusedDeskID: focusedDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        _ = focusedSession.boardOpening.createBoard(urlString: "https://example.com")
        #expect(focusedSession.navigation.focusedBoard?.width == 760)
    }

    @Test func newBoardFromTerminalSideBoardUsesPrimaryWidth() {
        // Arrange
        let primary = BoardState(label: "Primary", width: 800, workingDirectory: "/tmp")
        var side = BoardState(label: "Side", width: 360, workingDirectory: "/tmp")
        side.role = .sideBoard(targetBoardID: primary.id)
        let source = makeTestDesk("Desk", boards: [primary, side], focusedBoardID: side.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        // Act
        let inheritedWidth = session.boardOpening.inheritedBoardWidth
        session.boardOpening.handleTerminalURL("https://example.com", boardID: side.id)

        // Assert
        #expect(inheritedWidth == primary.width)
        #expect(session.navigation.focusedBoard?.isWeb == true)
        #expect(session.navigation.focusedBoard?.width == primary.width)
    }

    @Test func emptyDeskUsesTwoBoardFitWidthAsDefault() {
        let emptyDesk = makeTestDesk("Empty")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [emptyDesk]))
            )
        ) { session, windowModel in
            #expect(session.boardOpening.inheritedBoardWidth == BuiltInDeskPreset.boardWidth)

            windowModel.updateBoardLayout(availableWidth: 1376, spacing: 12)
            #expect(windowModel.defaultBoardWidth == 682)

            _ = session.boardOpening.createBoard(
                urlString: "https://example.com",
                preferredWidth: windowModel.defaultBoardWidth
            )
            #expect(session.navigation.focusedBoard?.width == 682)
        }
    }

    @Test func emptyDeskAppliesFitWidthToClipboardAndEssential() {
        let emptyDesk = makeTestDesk("Empty")
        let essential = Essential(name: "Search", key: "s", input: "https://example.com")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [emptyDesk]))
            )
        ) { session, windowModel in
            #expect(session.configuration.preferences.setEssentials([essential]))
            windowModel.updateBoardLayout(availableWidth: 1000, spacing: 12)

            windowModel.launchEssential(id: essential.id)
            #expect(session.navigation.focusedBoard?.width == 494)

            session.resources.state.desks[0].boards.removeAll()
            let pasteboard = NSPasteboard.withUniqueName()
            pasteboard.clearContents()
            pasteboard.setString("https://clipboard.example.com", forType: .string)
            session.input.openBoardFromClipboard(
                pasteboard: pasteboard,
                preferredWidth: windowModel.defaultBoardWidth
            )
            #expect(session.navigation.focusedBoard?.width == 494)
        }
    }

    @Test func emptyDeskReceivesFocusedBoardIDWhenAddingBoardInBackground() {
        let firstDesk = makeTestDesk("First", boards: [makeTestBoard("Main")], focusedBoardID: nil)
        let emptyDesk = makeTestDesk("Empty")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [firstDesk, emptyDesk], focusedDeskID: firstDesk.id)
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        // Open board on emptyDesk without focus
        _ = session.boardOpening.createBoard(
            urlString: "https://example.com",
            focus: false
        )
        #expect(session.resources.state.desks[0].boards.count == 2)

        // Focus empty desk and open in background
        session.boardNavigation.focusDesk(emptyDesk.id)
        #expect(session.resources.state.desks[1].focusedBoardID == nil)
        _ = session.boardOpening.createBoard(
            urlString: "https://example.com",
            focus: false
        )

        #expect(session.resources.state.desks[1].boards.count == 1)
        #expect(session.resources.state.desks[1].focusedBoardID == session.resources.state.desks[1].boards[0].id)
    }

    @Test func updateBoardKeepsCurrentSheetForUnsupportedURL() throws {
        let board = makeTestBoard("Board", url: "https://before.example/")
        let source = makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)
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

        session.runtimes.updateBoard(
            boardID: board.id,
            url: URL(string: "mailto:user@example.com"),
            title: "Updated title"
        )

        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://before.example/"))
        #expect(session.navigation.focusedBoard?.label == "Updated title")
        #expect(savedState == nil)
    }

    @Test func updateBoardDoesNotTriggerSaveWhenOnlyTitleChanges() throws {
        let board = makeTestBoard("Board", url: "https://example.com/")
        let source = makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { _ in saveCount += 1 }
                    callback(state)
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.runtimes.updateBoard(boardID: board.id, url: nil, title: "New Title")
        #expect(session.navigation.focusedBoard?.label == "New Title")
        #expect(saveCount == 0)

        session.runtimes.updateBoard(boardID: board.id, url: URL(string: "https://example.com/updated"), title: nil)
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://example.com/updated"))
        #expect(saveCount == 1)
    }

    @Test func openBoardFromClipboardOpensBoardToRightAndExitsDenMode() {
        let source = makeTestDesk("Desk", boards: [makeTestBoard("First")])
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
        windowModel.isDenMode = true
        #expect(windowModel.isDenMode)
        #expect(session.navigation.focusedDesk?.boards.count == 1)

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/clipboard", forType: .string)

        session.input.openBoardFromClipboard(pasteboard: pasteboard, preferredWidth: windowModel.defaultBoardWidth)

        #expect(session.navigation.focusedDesk?.boards.count == 2)
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://example.com/clipboard"))
        #expect(!windowModel.isDenMode)
        #expect(session.feedback.latest == nil)
    }

    @Test func openBoardFromClipboardShowsWarningFeedbackWhenEmpty() {
        let source = makeTestDesk("Desk", boards: [makeTestBoard("First")])
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
        windowModel.isDenMode = true
        let initialCount = session.navigation.focusedDesk?.boards.count ?? 0

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()

        session.input.openBoardFromClipboard(pasteboard: pasteboard, preferredWidth: windowModel.defaultBoardWidth)

        #expect(session.navigation.focusedDesk?.boards.count == initialCount)
        #expect(session.feedback.latest?.message == "Clipboard is empty.")
    }

    @Test func openBoardFromClipboardReportsConfigurationFailure() {
        // Arrange
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.setString(":zmx test-session", forType: .string)

        // Act
        session.input.openBoardFromClipboard(pasteboard: pasteboard)

        // Assert
        #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
        #expect(session.feedback.latest?.message == "Set an absolute zmx executable path in Settings > Terminal.")
    }

    @Test func openBoardRecentItemDelegatesToOpenBoardInput() {
        let source = makeTestDesk("Desk")
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session in
            session.configuration.preferences.setZmxPath("/usr/bin/zmx")
            session.configuration.preferences.setZellijPath("/usr/bin/zellij")

            session.boardOpening.openBoard(recentItem: .zellij(sessionName: "my-session"))
            #expect(session.navigation.focusedBoard?.zellijSessionName == "my-session")
            #expect(session.resources.recentItems.first == .zellij(sessionName: "my-session"))

            session.boardOpening.openBoard(recentItem: .zmx(sessionName: "zmx-session"))
            #expect(session.navigation.focusedBoard?.zmxSessionName == "zmx-session")
            #expect(session.resources.recentItems.first == .zmx(sessionName: "zmx-session"))
        }
    }
}
