import AppKit
import Foundation
import GhosttyTerminal
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenStoreBoardTests {

    @Test func terminalInputResolvesHomeRelativeAndAbsoluteDirectories() throws {
        let home = FileManager.default.temporaryDirectory

        #expect(
            try DenStore.resolveTerminalInput(":terminal", homeDirectory: home)?.get()
                == home.standardizedFileURL.path)
        #expect(
            try DenStore.resolveTerminalInput(":terminal .", homeDirectory: home)?.get()
                == home.standardizedFileURL.path)
        #expect(
            try DenStore.resolveTerminalInput(
                ":terminal \(home.path)", homeDirectory: URL(fileURLWithPath: "/"))?.get()
                == home.standardizedFileURL.path)
        #expect(DenStore.resolveTerminalInput(":terminally", homeDirectory: home) == nil)

        let missing = DenStore.resolveTerminalInput(
            ":terminal missing-\(UUID().uuidString)", homeDirectory: home)
        #expect(throws: TerminalInputError.self) { try missing?.get() }
    }

    @Test func zellijInputResolvesWelcomeAndNamedSessions() {
        #expect(DenStore.resolveZellijInput(":zellij") == .welcome)
        #expect(DenStore.resolveZellijInput(":zellij   ") == .welcome)
        #expect(DenStore.resolveZellijInput(":zellij project-a") == .session("project-a"))
        #expect(DenStore.resolveZellijInput(":zellijly") == nil)
    }

    @Test func zmxInputRequiresAndResolvesNamedSessions() {
        #expect(DenStore.resolveZmxInput(":zmx") == .missingSessionName)
        #expect(DenStore.resolveZmxInput(":zmx   ") == .missingSessionName)
        #expect(DenStore.resolveZmxInput(":zmx project-a") == .session("project-a"))
        #expect(DenStore.resolveZmxInput(":zmxly") == nil)
    }

    @Test func zellijBoardsPersistOptionalSessionNames() throws {
        let source = desk("Desk")
        try withTestStore(desks: [source]) { store in
            store.preferences.setZellijPath("/opt/homebrew/bin/zellij")

            store.openBoard(input: ":zellij project-a")
            let named = try #require(store.focusedBoard)
            #expect(named.isTerminal)
            #expect(named.isZellij)
            #expect(named.zellijSessionName == "project-a")
            #expect(
                ZellijClient(executablePath: "/opt/homebrew/bin/zellij")
                    .launchCommand(sessionName: named.zellijSessionName)
                    == "'/opt/homebrew/bin/zellij' attach --create 'project-a'"
            )
            let restoredNamed = try JSONDecoder().decode(
                BoardState.self,
                from: JSONEncoder().encode(named))
            #expect(
                restoredNamed.kind
                    == .terminal(.zellij(ZellijBoardState(sessionName: "project-a"))))

            store.openBoard(input: ":zellij")
            let welcome = try #require(store.focusedBoard)
            #expect(welcome.isZellij)
            #expect(welcome.zellijSessionName == nil)
            #expect(
                ZellijClient(executablePath: "/opt/homebrew/bin/zellij")
                    .launchCommand(sessionName: welcome.zellijSessionName)
                    == "'/opt/homebrew/bin/zellij' -l welcome"
            )
            let restoredWelcome = try JSONDecoder().decode(
                BoardState.self,
                from: JSONEncoder().encode(welcome))
            #expect(
                restoredWelcome.kind
                    == .terminal(.zellij(ZellijBoardState(sessionName: nil))))
        }
    }

    @Test func zellijBoardRequiresConfiguredAbsoluteExecutablePath() {
        let source = desk("Desk")
        withTestViewModel(desks: [source]) { viewModel in
            let store = viewModel.store
            viewModel.showOpenBoardPanel()
            store.openBoard(input: ":zellij")

            #expect(store.focusedBoard?.isZellij != true)
            #expect(viewModel.openBoard.message?.contains("absolute Zellij executable path") == true)
            #expect(store.recentItems.isEmpty)
        }
    }

    @Test func zmxBoardsPersistNamedSessionAndOpenSessionsList() async throws {
        let source = desk("Desk")
        let runner = StubTerminalCommandRunner(responses: [
            ["list"]: TerminalCommandResult(terminationStatus: 0, standardOutput: "")
        ])
        try await withTestViewModel(desks: [source], terminalCommandRunner: runner) {
            viewModel in
            let store = viewModel.store
            store.preferences.setZmxPath("/opt/homebrew/bin/zmx")

            store.openBoard(input: ":zmx project-a")
            let board = try #require(store.focusedBoard)
            #expect(board.isTerminal)
            #expect(board.isZmx)
            #expect(board.zmxSessionName == "project-a")
            #expect(
                ZmxClient(executablePath: "/opt/homebrew/bin/zmx")
                    .launchCommand(sessionName: board.zmxSessionName ?? "")
                    == "/usr/bin/env -u ZMX_SESSION '/opt/homebrew/bin/zmx' attach 'project-a'"
            )
            let restored = try JSONDecoder().decode(
                BoardState.self,
                from: JSONEncoder().encode(board))
            #expect(
                restored.kind
                    == .terminal(
                        .zmx(
                            ZmxBoardState(
                                sessionName: "project-a",
                                workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path))))

            store.openBoard(input: ":zmx")
            await waitForZmxSessionLoad(viewModel)
            #expect(store.focusedDesk?.boards.count == 1)
            #expect(viewModel.isZmxSessionsPresented)
            #expect(store.recentItems.first == .zmx(sessionName: "project-a"))
            #expect(RecentItem.zmx(sessionName: "").displayText == ":zmx")

            viewModel.hideZmxSessions()
            store.openBoard(recentItem: .zmx(sessionName: ""))
            await waitForZmxSessionLoad(viewModel)
            #expect(viewModel.isZmxSessionsPresented)

            viewModel.hideZmxSessions()
            viewModel.showOpenBoardPanel()
            viewModel.submitOpenBoard(":zmx")
            await waitForZmxSessionLoad(viewModel)
            viewModel.hideZmxSessions()
            #expect(viewModel.isOpenBoardPanelPresented)
        }
    }

    @Test func zmxSessionsGroupChildrenOpenBoardsAndKillOneSession() async {
        let source = desk("Desk")
        let commandRunner = StubTerminalCommandRunner(
            responses: [
                ["list"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: "name=den\nname=den-vi\tden.root=den\nname=old-root-debug\tden.root=old-root\n"),
                ["kill", "den-vi", "--force"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: ""),
            ])
        await withTestViewModel(
            desks: [source], terminalCommandRunner: commandRunner
        ) { viewModel in
            let store = viewModel.store
            store.preferences.setZmxPath("/opt/homebrew/bin/zmx")

            viewModel.showZmxSessions(selectedSessionName: "den-vi")
            await waitForZmxSessionLoad(viewModel)

            #expect(
                viewModel.zmxSessions.groups == [
                    ZmxSessionGroup(rootSessionName: "den", isRootActive: true, childSessionNames: ["den-vi"]),
                    ZmxSessionGroup(
                        rootSessionName: "old-root",
                        isRootActive: false,
                        childSessionNames: ["old-root-debug"]),
                ])
            #expect(viewModel.zmxSessions.selectedSessionName == "den-vi")
            viewModel.zmxSessions.setQuery("vi")
            #expect(
                viewModel.zmxSessions.filteredGroups
                    == [ZmxSessionGroup(rootSessionName: "den", isRootActive: true, childSessionNames: ["den-vi"])]
            )
            viewModel.clearZmxSessionFilter()

            viewModel.openZmxSession("den-vi")
            #expect(store.focusedBoard?.zmxSessionName == "den-vi")
            #expect(store.focusedBoard?.zmxRootSessionName == "den")
            #expect(store.recentItems.first == .zmx(sessionName: "den-vi"))
            #expect(!viewModel.isZmxSessionsPresented)

            viewModel.showZmxSessions()
            await waitForZmxSessionLoad(viewModel)
            viewModel.openZmxSession("den-vi")
            #expect(store.focusedDesk?.boards.count == 1)

            viewModel.showZmxSessions()
            await waitForZmxSessionLoad(viewModel)
            viewModel.killZmxSession("den-vi")
            await waitForZmxSessionLoad(viewModel)
            #expect(viewModel.zmxSessions.message == nil)
        }
    }

    @Test func openingExistingZmxBoardFromSessionsCapturesRoot() async {
        // Arrange
        let existing = BoardState(width: 520, zmxSessionName: "den-vi")
        let commandRunner = StubTerminalCommandRunner(
            responses: [
                ["list"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: "name=den\nname=den-vi\tden.root=den\n")
            ])
        await withTestViewModel(
            desks: [desk("Desk", boards: [existing], focusedBoardID: existing.id)],
            terminalCommandRunner: commandRunner
        ) { viewModel in
            let store = viewModel.store
            store.preferences.setZmxPath("/opt/homebrew/bin/zmx")
            viewModel.showZmxSessions(selectedSessionName: "den-vi")
            await waitForZmxSessionLoad(viewModel)

            // Act
            viewModel.openZmxSession("den-vi")

            // Assert
            #expect(store.focusedDesk?.boards.count == 1)
            #expect(store.focusedBoard?.id == existing.id)
            #expect(store.focusedBoard?.zmxRootSessionName == "den")
        }
    }

    @Test func changingWebExtensionHostKeepsTerminalRuntimeAlive() {
        let terminal = BoardState(width: 520, zmxSessionName: "project-a", workingDirectory: "/tmp")
        let source = desk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: makeTestSheetNavigationManager(),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            onSave: nil)
        let runtime = store.terminalRuntime(for: terminal)
        let host = MV3WebExtensionHost(
            profileID: UUID(),
            websiteDataStore: .nonPersistent(),
            userContentController: WKUserContentController())
        let window = host.window(for: UUID())
        defer {
            store.releaseRuntimes()
            host.dispose()
        }

        store.updateWebExtensionHost(host, window: window)

        #expect(store.terminalRuntimes[terminal.id] === runtime)
    }

    @Test func zmxBoardDuplicationCreatesRootedIndependentSessions() async throws {
        let sourceBoard = BoardState(
            width: 640,
            zmxSessionName: "den",
            workingDirectory: "/tmp/project")
        let source = desk("Desk", boards: [sourceBoard], focusedBoardID: sourceBoard.id)
        let runner = StubTerminalCommandRunner(
            responses: [
                ["list", "--short"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: "")
            ])
        try await withTestViewModel(desks: [source], terminalCommandRunner: runner) {
            viewModel in
            let store = viewModel.store
            store.preferences.setZmxPath("/usr/bin/zmx")

            store.duplicateFocusedBoardFromFirstSheet()
            await store.waitForZmxCommand()
            let automaticChild = try #require(store.focusedBoard)
            #expect(store.focusedDesk?.boards.count == 2)
            #expect(automaticChild.zmxSessionName == "den-2")
            #expect(automaticChild.zmxRootSessionName == "den")
            #expect(automaticChild.terminalWorkingDirectory == "/tmp/project")
            #expect(viewModel.temporaryContext == nil)
            #expect(store.recentItems.isEmpty)

            store.focusBoard(sourceBoard.id)
            store.duplicateFocusedBoard()
            await store.waitForZmxCommand()
            #expect(viewModel.temporaryContext == .zmxDuplication)
            #expect(store.focusedDesk?.boards.count == 2)

            store.duplicateFocusedZmxBoard(suffix: "vi")
            await store.waitForZmxCommand()
            let firstChild = try #require(store.focusedBoard)
            #expect(firstChild.zmxSessionName == "den-vi")
            #expect(firstChild.zmxRootSessionName == "den")
            #expect(firstChild.terminalWorkingDirectory == "/tmp/project")
            let restoredChild = try JSONDecoder().decode(
                BoardState.self,
                from: JSONEncoder().encode(firstChild))
            #expect(
                restoredChild.kind
                    == .terminal(
                        .zmx(
                            ZmxBoardState(
                                sessionName: "den-vi",
                                workingDirectory: "/tmp/project",
                                rootSessionName: "den"))))

            store.duplicateFocusedBoard()
            await store.waitForZmxCommand()
            store.duplicateFocusedZmxBoard(suffix: "nvim")
            await store.waitForZmxCommand()
            #expect(store.focusedBoard?.zmxSessionName == "den-nvim")
            #expect(store.focusedBoard?.zmxRootSessionName == "den")

            store.focusBoard(firstChild.id)
            store.duplicateFocusedBoard()
            await store.waitForZmxCommand()
            store.duplicateFocusedZmxBoard(suffix: "vi")
            await store.waitForZmxCommand()
            #expect(store.focusedBoard?.zmxSessionName == "den-vi-2")
        }
    }

    @Test func zmxBoardDuplicationUsesTheSourceRootLabel() async {
        let sourceBoard = BoardState(
            width: 640,
            zmxSessionName: "den-vi",
            workingDirectory: "/tmp/project")
        let source = desk("Desk", boards: [sourceBoard], focusedBoardID: sourceBoard.id)
        let commandRunner = StubTerminalCommandRunner(
            responses: [
                ["list", "--short"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: "den-vi\n"),
                ["get", "den-vi", "den.root"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: "den\n"),
            ])
        await withTestViewModel(
            desks: [source], terminalCommandRunner: commandRunner
        ) { viewModel in
            let store = viewModel.store
            store.preferences.setZmxPath("/usr/bin/zmx")

            store.duplicateFocusedBoard()
            await store.waitForZmxCommand()
            #expect(viewModel.zmxDuplicationRootSessionName == "den")
            store.duplicateFocusedZmxBoard(suffix: "nvim")
            await store.waitForZmxCommand()
            #expect(store.focusedBoard?.zmxSessionName == "den-nvim")
            #expect(store.focusedBoard?.zmxRootSessionName == "den")
        }
    }

    @Test func invalidTerminalInputDoesNotCreateRecentItem() {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        store.openBoard(input: ":terminal /missing/den-browser-\(UUID().uuidString)")

        #expect(store.focusedDesk?.boards.isEmpty == true)
        #expect(store.recentItems.isEmpty)
    }

    @Test func popupBoardKeepsItsOpenerRequestAndUsesTheProvidedWebView() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let store = popupStore(for: sourceBoard)
        defer { store.releaseRuntimes() }

        let popupURL = try #require(URL(string: "https://login.example/authorize"))
        let backgroundPopup = WebBoardWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // Act
        #expect(
            store.createPopupBoard(
                backgroundPopup,
                requestedURL: popupURL,
                fromBoardID: sourceBoard.id,
                modifierFlags: .command))
        let backgroundBoard = try #require(store.state.desks[0].boards.first { $0.id != sourceBoard.id })

        // Assert
        #expect(store.focusedBoard?.id == sourceBoard.id)
        #expect(backgroundBoard.currentSheetURL == popupURL)
        #expect(backgroundBoard.firstSheetURL == popupURL)
        #expect(store.webRuntimes[backgroundBoard.id]?.webView === backgroundPopup)
        #expect(backgroundPopup.url == nil)
    }

    @Test func commandShiftPopupFocusesItsBoard() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let store = popupStore(for: sourceBoard)
        defer { store.releaseRuntimes() }
        let popup = WebBoardWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // Act
        #expect(
            store.createPopupBoard(
                popup,
                requestedURL: nil,
                fromBoardID: sourceBoard.id,
                modifierFlags: [.command, .shift]))

        // Assert
        let focusedBoard = try #require(store.focusedBoard)
        #expect(focusedBoard.id != sourceBoard.id)
        #expect(focusedBoard.currentSheetURL == nil)
        #expect(store.webRuntimes[focusedBoard.id]?.webView === popup)
        #expect(popup.url == nil)
    }

    @Test func popupBoardFocusesByDefault() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let store = popupStore(for: sourceBoard)
        defer { store.releaseRuntimes() }
        let popup = WebBoardWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // Act
        #expect(
            store.createPopupBoard(
                popup,
                requestedURL: nil,
                fromBoardID: sourceBoard.id,
                modifierFlags: []))

        // Assert
        let focusedBoard = try #require(store.focusedBoard)
        #expect(focusedBoard.id != sourceBoard.id)
        #expect(store.webRuntimes[focusedBoard.id]?.webView === popup)
    }

    @Test func closingPopupWebViewRemovesItsBoard() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let store = popupStore(for: sourceBoard)
        defer { store.releaseRuntimes() }
        let popup = WebBoardWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        #expect(
            store.createPopupBoard(
                popup,
                requestedURL: nil,
                fromBoardID: sourceBoard.id,
                modifierFlags: []))
        let popupBoard = try #require(store.focusedBoard)

        // Act
        store.webRuntimes[popupBoard.id]?.webViewDidClose(popup)

        // Assert
        #expect(store.board(for: popupBoard.id) == nil)
        #expect(store.webRuntimes[popupBoard.id] == nil)
    }

    @Test func windowOpenPopupPreservesOpenerPostMessage() async throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let store = popupStore(for: sourceBoard)
        defer { store.releaseRuntimes() }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store.websiteDataStore
        configuration.userContentController = store.sheetNavigation.userContentController
        let sourceWebView = WebBoardWKWebView(frame: .zero, configuration: configuration)
        let sourceRuntime = store.webRuntime(for: sourceBoard, popupWebView: sourceWebView)
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
            in: sourceRuntime.webView)
        sourceRuntime.webView.navigationDelegate = sourceRuntime

        // Act
        _ = try await sourceRuntime.webView.evaluateJavaScript(
            "window.open('about:blank', '_blank'); true")
        let popupBoard = try #require(store.state.desks[0].boards.first { $0.id != sourceBoard.id })
        let popupRuntime = try #require(store.webRuntimes[popupBoard.id])
        _ = try await popupRuntime.webView.evaluateJavaScript(
            "window.opener.postMessage('popup-message', '*')")
        try await SheetInteraction.waitForFunction(
            expression: "document.title === 'popup-message'",
            in: sourceRuntime.webView,
            timeout: 5)

        // Assert
        #expect(popupRuntime.webView !== sourceRuntime.webView)
        #expect(popupRuntime.webView.uiDelegate === popupRuntime)
        #expect(try await sourceRuntime.webView.evaluateJavaScript("document.title") as? String == "popup-message")
    }

    @Test func timerTriggeredJavaScriptPopupCreatesBoard() async throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let store = popupStore(for: sourceBoard)
        defer { store.releaseRuntimes() }
        let sourceRuntime = store.webRuntime(for: sourceBoard)
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
            in: sourceRuntime.webView)
        sourceRuntime.webView.navigationDelegate = sourceRuntime

        // Act
        try await SheetInteraction.waitForFunction(
            expression: "document.title === 'Opened'",
            in: sourceRuntime.webView,
            timeout: 5)

        // Assert
        #expect(store.state.desks[0].boards.count == 2)
        #expect(store.state.desks[0].boards[1].id != sourceBoard.id)
    }

    @Test func terminalBoardsCreateDuplicateRemoveAndRestoreWithRecentItems() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path

        store.openBoard(input: ":terminal \(directory)", preferredWidth: 640)

        let original = try #require(store.focusedBoard)
        #expect(original.isTerminal)
        #expect(original.terminalWorkingDirectory == directory)
        #expect(original.width == 640)
        #expect(store.recentItems == [.terminal(workingDirectory: directory)])

        store.duplicateFocusedBoard()
        let duplicate = try #require(store.focusedBoard)
        #expect(duplicate.id != original.id)
        #expect(duplicate.terminalWorkingDirectory == directory)

        store.removeFocusedBoard()
        store.restoreRecentlyRemovedBoard()
        #expect(store.focusedBoard?.id == duplicate.id)
        #expect(store.focusedBoard?.terminalWorkingDirectory == directory)
    }

    @Test func terminalFocusNotificationDoesNotExitDenMode() {
        let terminal = BoardState(width: 520, workingDirectory: "/tmp")
        let source = desk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true

        store.terminalRuntime(for: terminal).terminalDidChangeFocus(true)

        #expect(viewModel.isDenMode)
        #expect(store.focusedBoard?.id == terminal.id)
    }

    @Test func boardLinkFocusIntentDoesNotConsumeNewerIntent() {
        let firstBoard = BoardState(label: "First", width: 520, currentSheetURL: nil)
        let secondBoard = BoardState(label: "Second", width: 520, currentSheetURL: nil)
        let source = desk("Desk", boards: [firstBoard, secondBoard], focusedBoardID: firstBoard.id)
        withTestViewModel(desks: [source]) { viewModel in
            let store = viewModel.store
            store.prepareBoardLinkFocus(firstBoard.id)
            #expect(viewModel.pendingBoardLinkFocus != nil)
            guard let firstIntent = viewModel.pendingBoardLinkFocus else { return }
            #expect(firstIntent.origin == .interactive)
            store.prepareBoardLinkFocus(secondBoard.id)
            #expect(viewModel.pendingBoardLinkFocus != nil)
            guard let secondIntent = viewModel.pendingBoardLinkFocus else { return }

            viewModel.consumeBoardLinkFocus(firstIntent)
            #expect(viewModel.pendingBoardLinkFocus == secondIntent)

            viewModel.consumeBoardLinkFocus(secondIntent)
            #expect(viewModel.pendingBoardLinkFocus == nil)
        }
    }

    @Test func focusedBoardCreationEndsLinkFocusSuppression() throws {
        let source = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let desk = desk("Desk", boards: [source], focusedBoardID: source.id)
        withTestViewModel(desks: [desk]) { viewModel in
            let store = viewModel.store
            store.prepareBoardLinkFocus(source.id)
            #expect(store.createBoard(urlString: "https://focused.example", afterBoardID: source.id) != nil)

            #expect(viewModel.pendingBoardLinkFocus == nil)
            #expect(store.focusedBoard?.currentSheetURL?.host == "focused.example")
        }
    }

    @Test func inspectionBoardLinksToWebBoardAndReusesIt() throws {
        let target = BoardState(label: "Target", width: 520, currentSheetURL: URL(string: "https://example.com"))
        let sourceDesk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let store = DenStore(state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))

        let inspectionID = try #require(store.createInspectionBoard(targetBoardID: target.id))
        let inspection = try #require(store.board(for: inspectionID))

        #expect(store.state.desks[0].boards.map(\.id) == [target.id, inspectionID])
        #expect(store.focusedBoard?.id == inspectionID)
        #expect(inspection.isInspection)
        #expect(!inspection.isWeb)
        #expect(!inspection.isTerminal)
        #expect(inspection.isSideBoard)
        #expect(inspection.sideBoardTargetBoardID == target.id)
        #expect(try JSONDecoder().decode(BoardState.self, from: JSONEncoder().encode(inspection)) == inspection)
        #expect(store.createInspectionBoard(targetBoardID: target.id) == inspectionID)
        #expect(store.state.desks[0].boards.count == 2)
    }

    @Test(arguments: [false, true], [false, true])
    func sideBoardCannotBeDuplicated(isInspection: Bool, fromFirstSheet: Bool) {
        // Arrange
        let target = board("Target")
        var side =
            isInspection
            ? BoardState(width: 360, targetBoardID: target.id)
            : board("Side")
        if !isInspection {
            side.firstSheetURL = URL(string: "https://example.com/first")
            side.role = .sideBoard(targetBoardID: target.id)
        }
        let sourceDesk = desk("Desk", boards: [target, side], focusedBoardID: side.id)
        let store = DenStore(state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))

        // Act
        if fromFirstSheet {
            store.duplicateFocusedBoardFromFirstSheet()
        } else {
            store.duplicateFocusedBoard()
        }

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [target.id, side.id])
        #expect(store.focusedBoard?.id == side.id)
    }

    @Test(arguments: [0, 1])
    func focusedBoardCreationKeepsSideBoardGroupAdjacent(focusedIndex: Int) throws {
        // Arrange
        let target = board("Target")
        var side = board("Side")
        side.role = .sideBoard(targetBoardID: target.id)
        let following = board("Following")
        let sourceDesk = desk(
            "Desk",
            boards: [target, side, following],
            focusedBoardID: [target.id, side.id][focusedIndex])
        let store = DenStore(state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))

        // Act
        let insertedID = try #require(store.createBoard(urlString: "https://new.example"))

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [target.id, side.id, insertedID, following.id])
    }

    @Test(arguments: await [BoardState.minimumWidth, BuiltInDeskPreset.boardWidth, BoardState.maximumWidth])
    func inspectionBoardStartsAtCompactWidthRegardlessOfTargetWidth(targetWidth: Double) throws {
        // Arrange
        let target = BoardState(
            label: "Target", width: targetWidth, currentSheetURL: URL(string: "https://example.com"))
        let sourceDesk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let store = DenStore(state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))

        // Act
        let inspectionID = try #require(store.createInspectionBoard(targetBoardID: target.id))
        let inspection = try #require(store.board(for: inspectionID))

        // Assert
        #expect(inspection.width == 360)
    }

    @Test func inspectionBoardRequiresSideBoardRoleToDecode() {
        let boardID = UUID()
        let data = Data(
            """
            {"id":"\(boardID.uuidString)","label":"Inspection Board","width":390,"content":{"kind":"inspection"}}
            """.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BoardState.self, from: data)
        }
    }

    @Test func boardWithoutRoleDecodesAsPrimary() throws {
        let boardID = UUID()
        let data = Data(
            """
            {"id":"\(boardID.uuidString)","label":"Web","width":520,"content":{"kind":"web"}}
            """.utf8)

        let board = try JSONDecoder().decode(BoardState.self, from: data)

        #expect(board.role == .primary)
    }

    @Test func boardGroupKeepsSideRoleSeparateFromBoardContent() throws {
        let target = board("Target")
        var side = BoardState(label: "Side Terminal", width: 390, workingDirectory: "/tmp")
        side.role = .sideBoard(targetBoardID: target.id)

        let group = try #require(BoardGroup.containing(side.id, in: [target, side]))

        #expect(!side.isInspection)
        #expect(group.primaryBoard.id == target.id)
        #expect(group.sideBoard?.id == side.id)
        #expect(group.boards.map(\.id) == [target.id, side.id])
        let encoded = try JSONEncoder().encode(side)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let role = try #require(object["role"] as? [String: Any])
        #expect(role["kind"] as? String == "sideBoard")
        #expect(role["targetBoardID"] as? String == target.id.uuidString)
        #expect(object["sideBoard"] == nil)
        #expect(try JSONDecoder().decode(BoardState.self, from: encoded) == side)
    }

    @Test func backgroundBoardFocusSuppressionEndsOnNextFocus() throws {
        let source = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let other = BoardState(label: "Other", width: 520, currentSheetURL: nil)
        let desk = desk("Desk", boards: [source, other], focusedBoardID: source.id)
        try withTestViewModel(desks: [desk]) { viewModel in
            let store = viewModel.store
            #expect(
                store.createBoard(
                    urlString: "https://background.example",
                    afterBoardID: source.id,
                    focus: false) != nil)
            let intent = try #require(viewModel.pendingBoardLinkFocus)
            #expect(intent.origin == .interactive)
            #expect(store.focusedBoard?.id == source.id)

            store.focusBoard(other.id)

            #expect(viewModel.pendingBoardLinkFocus == nil)
            viewModel.consumeBoardLinkFocus(intent)
            #expect(viewModel.pendingBoardLinkFocus == nil)
        }
    }

    @Test func cliBackgroundBoardCarriesCLIInsertionOrigin() throws {
        let source = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let other = BoardState(label: "Other", width: 520, currentSheetURL: nil)
        let desk = desk("Desk", boards: [source, other], focusedBoardID: source.id)
        try withTestViewModel(desks: [desk]) { viewModel in
            let store = viewModel.store
            #expect(
                store.createBoard(
                    urlString: "https://cli.example",
                    afterBoardID: source.id,
                    focus: false,
                    origin: .cli) != nil)
            let intent = try #require(viewModel.pendingBoardLinkFocus)

            #expect(intent.origin == .cli)
        }
    }

    @Test func cliBackgroundBoardRemovalCarriesCLIOperationOrigin() throws {
        let left = BoardState(label: "Left", width: 520, currentSheetURL: nil)
        let focused = BoardState(label: "Focused", width: 520, currentSheetURL: nil)
        let source = desk("Desk", boards: [left, focused], focusedBoardID: focused.id)
        try withTestViewModel(desks: [source]) { viewModel in
            let store = viewModel.store
            store.removeBoard(left.id, origin: .cli)

            let intent = try #require(viewModel.pendingBoardRemoval)
            #expect(intent.origin == .cli)
            #expect(store.focusedBoard?.id == focused.id)
        }
    }

    @Test func terminalLinkCreatesFocusedBoardWithoutDrawer() throws {
        // Arrange
        let terminal = BoardState(width: 520, workingDirectory: "/tmp")
        let source = desk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let url = try #require(URL(string: "https://terminal-link.example/path"))
        defer { store.releaseRuntimes() }

        // Act
        store.terminalRuntime(for: terminal).terminalDidRequestOpenURL(url.absoluteString, kind: .text)

        // Assert
        let createdBoard = try #require(store.focusedDesk?.boards.last)
        #expect(createdBoard.currentSheetURL == url)
        #expect(store.focusedDesk?.focusedBoardID == createdBoard.id)
        #expect(store.state.drawerItems.isEmpty)
        #expect(store.recentItems == [.url(url)])
    }

    @Test func searchesUseCurrentEngineAndPreserveQueryAndExplicitURLs() throws {
        try withTestStore { store in
            let query = "日本語 & C++ # Swift?"
            for engine in SearchEngine.allCases {
                store.preferences.setSearchEngine(engine)
                store.openBoard(recentItem: .search(query))
                let url = try #require(store.focusedBoard?.currentSheetURL)
                let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
                #expect(components.host == URL(string: engine.searchURL)?.host)
                #expect(components.path == URL(string: engine.searchURL)?.path)
                let queryParameter = engine == .yahooJapan ? "p" : "q"
                #expect(components.queryItems == [URLQueryItem(name: queryParameter, value: query)])
                #expect(components.fragment == nil)
                #expect(store.recentItems.first == .search(query))
            }
            let existingURL = store.focusedBoard?.currentSheetURL
            store.preferences.setSearchEngine(.duckDuckGo)
            #expect(store.focusedBoard?.currentSheetURL == existingURL)
            #expect(store.navigateFocusedBoard(urlString: "example.com/path?q=literal"))
            #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://example.com/path?q=literal"))
            #expect(store.navigateFocusedBoard(urlString: query))
            #expect(store.focusedBoard?.currentSheetURL?.host == "duckduckgo.com")
        }
    }

    @Test func openBoardAcceptsWebHostsAndRejectsInvalidURLs() throws {
        try withTestStore { store in

            _ = store.createBoard(urlString: "localhost:3000")
            let localURL = try #require(store.focusedDesk?.boards.last?.currentSheetURL)
            #expect(localURL.scheme == "https")
            #expect(localURL.host == "localhost")
            #expect(localURL.port == 3000)

            _ = store.createBoard(urlString: "swift: concurrency")
            let searchURL = try #require(
                store.focusedDesk?.boards.last?.currentSheetURL
                    .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
            #expect(searchURL.host == "www.google.com")
            #expect(searchURL.queryItems == [URLQueryItem(name: "q", value: "swift: concurrency")])

            let boardCount = try #require(store.focusedDesk?.boards.count)
            #expect(store.createBoard(urlString: "https://") == nil)
            #expect(store.createBoard(urlString: "ftp://example.com") == nil)
            #expect(store.focusedDesk?.boards.count == boardCount)
        }
    }

    @Test func localFileURLParticipatesInBoardRecentDrawerAndPresetWorkflows() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let fileURL = try #require(URL(string: "file:///tmp/Den%20Browser/index.html#notes"))

        store.openBoard(input: fileURL.absoluteString)

        #expect(store.focusedBoard?.currentSheetURL == fileURL)
        #expect(store.focusedBoard?.firstSheetURL == fileURL)
        #expect(store.recentItems.first == .url(fileURL))

        store.keepFocusedSheetInDrawer()
        #expect(store.state.drawerItems.first?.url == fileURL)

        #expect(store.saveFocusedDeskAsPreset(label: "Local Files") == .created)
        #expect(store.deskPresets.first?.boards.first?.initialSheetURL == fileURL)
    }

    @Test func editingFocusedBoardLinkReplacesCurrentSheet() throws {
        let board = board("Board", url: "https://before.example/")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        viewModel.showEditBoardLinkPanel()

        #expect(store.navigateFocusedBoard(urlString: "after.example/path"))
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://after.example/path"))
        #expect(store.focusedBoard?.firstSheetURL == URL(string: "https://before.example/"))
        #expect(viewModel.temporaryContext == nil)
        #expect(!viewModel.isDenMode)
    }

    @Test func newBoardKeepsFirstSheetWhenCurrentSheetChanges() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        _ = store.createBoard(urlString: "https://start.example/")
        let firstSheetURL = try #require(store.focusedBoard?.firstSheetURL)

        #expect(store.navigateFocusedBoard(urlString: "https://later.example/"))
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://later.example/"))
        #expect(store.focusedBoard?.firstSheetURL == firstSheetURL)
    }

    @Test func openBoardCanInsertAfterSpecifiedBoard() {
        let boards = [board("First"), board("Focused"), board("Last")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[1].id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        store.openBoard(input: "example.com", afterBoardID: boards.last?.id)

        #expect(store.focusedDesk?.boards.map(\.label) == ["First", "Focused", "Last", "example.com"])
        #expect(store.focusedDesk?.focusedBoardID == store.focusedDesk?.boards.last?.id)
    }

    @Test func newBoardKeepsPreferredWidthBeyondManualResizeLimit() {
        for width in [BoardState.minimumWidth, BoardState.maximumWidth, 2_480] {
            let source = desk("Desk")
            let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

            _ = store.createBoard(urlString: "https://example.com", preferredWidth: width)

            #expect(store.focusedBoard?.width == width)
        }
    }

    @Test func newBoardInheritsFocusedWidthWhenPreferredWidthIsUnset() {
        let source = board("Source", width: 760)
        let focusedDesk = desk("Focused", boards: [source], focusedBoardID: source.id)
        let focusedStore = DenStore(state: DenState(desks: [focusedDesk], focusedDeskID: focusedDesk.id))
        _ = focusedStore.createBoard(urlString: "https://example.com")
        #expect(focusedStore.focusedBoard?.width == 760)
    }

    @Test func emptyDeskUsesTwoBoardFitWidthAsDefault() {
        let emptyDesk = desk("Empty")
        withTestViewModel(desks: [emptyDesk]) { viewModel in
            let store = viewModel.store

            #expect(store.inheritedBoardWidth == BuiltInDeskPreset.boardWidth)

            viewModel.updateBoardLayout(availableWidth: 1376, spacing: 12)
            #expect(viewModel.defaultBoardWidth == 682)

            _ = store.createBoard(urlString: "https://example.com", preferredWidth: viewModel.defaultBoardWidth)
            #expect(store.focusedBoard?.width == 682)
        }
    }

    @Test func emptyDeskAppliesFitWidthToClipboardAndEssential() {
        let emptyDesk = desk("Empty")
        let essential = Essential(name: "Search", key: "s", input: "https://example.com")
        withTestViewModel(desks: [emptyDesk]) { viewModel in
            let store = viewModel.store
            #expect(store.preferences.setEssentials([essential]))
            viewModel.updateBoardLayout(availableWidth: 1000, spacing: 12)

            viewModel.launchEssential(id: essential.id)
            #expect(store.focusedBoard?.width == 494)

            store.state.desks[0].boards.removeAll()
            let pasteboard = NSPasteboard.withUniqueName()
            pasteboard.clearContents()
            pasteboard.setString("https://clipboard.example.com", forType: .string)
            viewModel.openBoardFromClipboard(pasteboard: pasteboard)
            #expect(store.focusedBoard?.width == 494)
        }
    }

    @Test func emptyDeskReceivesFocusedBoardIDWhenAddingBoardInBackground() {
        let firstDesk = desk("First", boards: [board("Main")], focusedBoardID: nil)
        let emptyDesk = desk("Empty")
        let store = DenStore(state: DenState(desks: [firstDesk, emptyDesk], focusedDeskID: firstDesk.id))

        // Open board on emptyDesk without focus
        _ = store.createBoard(
            urlString: "https://example.com",
            focus: false)
        #expect(store.state.desks[0].boards.count == 2)

        // Focus empty desk and open in background
        store.focusDesk(emptyDesk.id)
        #expect(store.state.desks[1].focusedBoardID == nil)
        _ = store.createBoard(
            urlString: "https://example.com",
            focus: false)

        #expect(store.state.desks[1].boards.count == 1)
        #expect(store.state.desks[1].focusedBoardID == store.state.desks[1].boards[0].id)
    }

    @Test func updateBoardKeepsCurrentSheetForUnsupportedURL() throws {
        let board = board("Board", url: "https://before.example/")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { savedState = $0 })

        store.updateBoard(
            boardID: board.id,
            url: URL(string: "mailto:user@example.com"),
            title: "Updated title")

        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://before.example/"))
        #expect(store.focusedBoard?.label == "Updated title")
        #expect(savedState == nil)
    }

    @Test func updateBoardDoesNotTriggerSaveWhenOnlyTitleChanges() throws {
        let board = board("Board", url: "https://example.com/")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { _ in saveCount += 1 })

        store.updateBoard(boardID: board.id, url: nil, title: "New Title")
        #expect(store.focusedBoard?.label == "New Title")
        #expect(saveCount == 0)

        store.updateBoard(boardID: board.id, url: URL(string: "https://example.com/updated"), title: nil)
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://example.com/updated"))
        #expect(saveCount == 1)
    }

    @Test func boardFocusMovesAndWrapsAtBothEdges() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            store.focusNextBoard()
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)

            store.focusPreviousBoard()
            store.focusPreviousBoard()
            #expect(store.focusedDesk?.focusedBoardID == boards[2].id)

            store.focusNextBoard()
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test(arguments: [false, true])
    func movingBoardFocusCompletesTutorialNavigationStep(inDenMode: Bool) {
        // Arrange
        let sourceDesk = desk("Desk")
        let store = DenStore(state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))
        withTestViewModel(store: store) { viewModel in

            #expect(store.openTutorialBoard())
            #expect(store.openBoard(input: "https://one.example/"))
            #expect(store.focusedDesk?.boards.count == 2)
            if inDenMode { viewModel.toggleDenMode() }

            // Act
            store.focusNextBoard()

            // Assert
            #expect(
                store.focusedDesk?.boards.contains {
                    $0.tutorialCompletedSteps?.contains(.navigateBoards) == true
                } == true)
        }
    }

    @Test(arguments: [false, true])
    func showingKeyboardShortcutsCompletesOptionalTutorialStepOnlyInDenMode(inDenMode: Bool) {
        let store = DenStore(state: .sample)
        withTestViewModel(store: store) { viewModel in
            #expect(store.openTutorialBoard())
            if inDenMode { viewModel.toggleDenMode() }

            viewModel.showKeyboardShortcuts()

            #expect(viewModel.isKeyboardShortcutsPresented)
            #expect(
                store.state.desks[0].boards.first?.tutorialCompletedSteps?.contains(.keyboardShortcuts)
                    == inDenMode)
        }
    }

    @Test func focusMovesDoNotSaveWhenThereIsOnlyOneTarget() {
        let board = board("Board")
        let onlyDesk = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        withTestStore(
            desks: [onlyDesk],
            onSave: { _ in
                saveCount += 1
                return true
            },
            body: { store in
                store.focusNextDesk()
                store.focusPreviousDesk()
                store.focusNextBoard()
                store.focusPreviousBoard()

                #expect(store.presentedDeskID == onlyDesk.id)
                #expect(store.focusedDesk?.focusedBoardID == board.id)
                #expect(saveCount == 0)
            })
    }

    @Test func reselectingPresentedDeskKeepsTransientEffectsWithoutSaving() {
        let board = board("Board")
        let onlyDesk = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0

        withTestViewModel(
            desks: [onlyDesk],
            onSave: { _ in
                saveCount += 1
                return true
            },
            body: { viewModel in
                let store = viewModel.store
                viewModel.deskFilter.enter()
                viewModel.deskFilter.setQuery("board")
                viewModel.isDenMode = true
                store.recordNotification(title: "Build", body: "Finished", boardID: board.id)

                store.focusDesk(onlyDesk.id)

                #expect(!viewModel.deskFilter.isPresented)
                #expect(viewModel.deskFilter.query.isEmpty)
                #expect(!viewModel.isDenMode)
                #expect(store.unreadNotificationCount == 0)
                #expect(saveCount == 0)
            })
    }

    @Test func boardFocusRecoversWhenNoBoardIsFocused() {
        let boards = [board("A"), board("B"), board("C")]
        let deskState = desk("Desk", boards: boards)
        let store = DenStore(state: DenState(desks: [deskState], focusedDeskID: deskState.id))
        store.state.desks[0].focusedBoardID = nil
        #expect(store.focusedDesk?.focusedBoardID == nil)

        store.focusNextBoard()
        #expect(store.focusedDesk?.focusedBoardID == boards[0].id)

        store.state.desks[0].focusedBoardID = nil
        store.focusPreviousBoard()
        #expect(store.focusedDesk?.focusedBoardID == boards[2].id)
    }

    @Test func boardBoundaryFocusStaysWithinSourceDesk() {
        let boards = [board("A"), board("B"), board("C")]
        let sourceDesk = desk("Source", boards: boards, focusedBoardID: boards[1].id)
        let otherDesk = desk("Other", boards: [board("Other Board")])
        let store = DenStore(
            state: DenState(desks: [sourceDesk, otherDesk], focusedDeskID: sourceDesk.id))

        store.focusFirstBoardInDesk(containing: boards[1].id)
        #expect(store.focusedDesk?.id == sourceDesk.id)
        #expect(store.focusedDesk?.focusedBoardID == boards[0].id)

        store.focusLastBoardInDesk(containing: boards[1].id)
        #expect(store.focusedDesk?.focusedBoardID == boards[2].id)
    }

    @Test func focusingAlreadyFocusedBoardDoesNotSaveAgain() {
        let board = board("Focused")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) { _ in
            saveCount += 1
        }

        store.focusBoard(board.id)

        #expect(saveCount == 0)
    }

    @Test func boardMovementAvailabilityStopsAtDeskEdges() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards)]) { store in
            #expect(!store.canMoveBoard(boards[0].id, by: -1))
            #expect(store.canMoveBoard(boards[0].id, by: 1))
            #expect(store.canMoveBoard(boards[1].id, by: -1))
            #expect(store.canMoveBoard(boards[1].id, by: 1))
            #expect(store.canMoveBoard(boards[2].id, by: -1))
            #expect(!store.canMoveBoard(boards[2].id, by: 1))
        }
    }

    @Test func reorderingBoardKeepsItFocusedAndStopsAtDeskEdge() {
        let boards = [board("A"), board("B"), board("C")]
        withTestViewModel(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { viewModel in
            let store = viewModel.store
            store.moveFocusedBoardLeft()
            store.moveFocusedBoardLeft()

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(viewModel.centerFocusedBoardRequest == 1)
        }
    }

    @Test func sideBoardMovesWithTargetAndIsRestoredWithItAfterRemoval() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let after = board("After")
        withStore(desks: [desk("Desk", boards: [target, side, after], focusedBoardID: target.id)]) { store in
            store.moveFocusedBoardRight()
            #expect(store.focusedDesk?.boards.map(\.id) == [after.id, target.id, side.id])
            #expect(!store.canMoveBoard(side.id, by: 1))

            store.removeBoard(target.id)
            #expect(store.focusedDesk?.boards.map(\.id) == [after.id])
            #expect(store.recentlyRemovedBoards.first?.sideBoard?.id == side.id)

            store.restoreRecentlyRemovedBoard()
            #expect(store.focusedDesk?.boards.map(\.id) == [after.id, target.id, side.id])
            #expect(store.focusedDesk?.focusedBoardID == target.id)
        }
    }

    @Test func removingSideBoardLeavesItsTarget() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        withStore(desks: [desk("Desk", boards: [target, side], focusedBoardID: side.id)]) { store in
            store.removeFocusedBoard()

            #expect(store.focusedDesk?.boards.map(\.id) == [target.id])
            #expect(store.recentlyRemovedBoards.first?.board.id == side.id)
            #expect(store.recentlyRemovedBoards.first?.sideBoard == nil)
        }
    }

    @Test func restoringRemovedSideBoardFollowsTargetToItsCurrentDesk() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let source = desk("Source", boards: [target, side], focusedBoardID: side.id)
        let destination = desk("Destination")
        withStore(desks: [source, destination]) { store in
            store.removeBoard(side.id)
            store.focusBoard(target.id)
            store.moveFocusedBoardToNextDesk()

            store.restoreRecentlyRemovedBoard()

            #expect(store.state.desks[0].boards.isEmpty)
            #expect(store.state.desks[1].boards.map(\.id) == [target.id, side.id])
            #expect(store.focusedDesk?.focusedBoardID == side.id)
        }
    }

    @Test func movingSideBoardGroupAcrossAnotherGroupKeepsBothAdjacent() {
        let firstTarget = board("First")
        let firstSide = BoardState(width: 390, targetBoardID: firstTarget.id)
        let secondTarget = board("Second")
        let secondSide = BoardState(width: 410, targetBoardID: secondTarget.id)
        let boards = [firstTarget, firstSide, secondTarget, secondSide]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: firstTarget.id)]) { store in
            store.moveFocusedBoardRight()

            #expect(
                store.focusedDesk?.boards.map(\.id) == [secondTarget.id, secondSide.id, firstTarget.id, firstSide.id])
            #expect(store.focusedDesk?.boards[1].sideBoardTargetBoardID == secondTarget.id)
            #expect(store.focusedDesk?.boards[3].sideBoardTargetBoardID == firstTarget.id)
        }
    }

    @Test func movingInspectionBoardToDeskCarriesTargetGroup() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let source = desk("Source", boards: [target, side], focusedBoardID: side.id)
        let destinationBoard = board("Destination")
        let destination = desk("Destination", boards: [destinationBoard], focusedBoardID: destinationBoard.id)
        withStore(desks: [source, destination]) { store in
            store.moveFocusedBoardToNextDesk()

            #expect(store.state.desks[0].boards.isEmpty)
            #expect(store.state.desks[1].boards.map(\.id) == [destinationBoard.id, target.id, side.id])
            #expect(store.focusedDesk?.focusedBoardID == side.id)
            #expect(store.focusedBoard?.width == 390)
        }
    }

    @Test func reorderingBoardWithScrollOffsetSavesOnceAndCenters() {
        let boards = [board("A"), board("B")]
        var source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        source.scrollOffsetX = 180
        var saveCount = 0

        withTestViewModel(
            desks: [source],
            onSave: { _ in
                saveCount += 1
                return true
            },
            body: { viewModel in
                let store = viewModel.store
                store.moveFocusedBoardRight()

                #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id])
                #expect(store.state.desks[0].scrollOffsetX == nil)
                #expect(viewModel.centerFocusedBoardRequest == 1)
                #expect(saveCount == 1)
            })
    }

    @Test func rapidBoardReorderingKeepsFocusAndRequestsCentering() {
        let boards = [board("A"), board("B"), board("C"), board("D")]
        withTestViewModel(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { viewModel in
            let store = viewModel.store
            store.moveFocusedBoardRight()
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id, boards[2].id, boards[3].id])
            #expect(viewModel.centerFocusedBoardRequest == 1)

            store.moveFocusedBoardRight()
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id, boards[0].id, boards[3].id])
            #expect(viewModel.centerFocusedBoardRequest == 2)

            store.moveFocusedBoardRight()
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id, boards[3].id, boards[0].id])
            #expect(viewModel.centerFocusedBoardRequest == 3)
        }
    }

    @Test func boardDragPersistsOnlyItsFinalOrder() {
        let boards = [board("A"), board("B"), board("C")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        var savedStates: [DenState] = []
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) {
            savedStates.append($0)
        }

        #expect(store.beginBoardDrag(boards[0].id))
        store.previewBoardMove(boards[0].id, to: 2)
        #expect(savedStates.isEmpty)

        store.finishBoardDrag()
        #expect(savedStates.count == 1)
        #expect(savedStates[0].desks[0].boards.map(\.id) == [boards[1].id, boards[2].id, boards[0].id])
    }

    @Test func boardDragMovesSideBoardGroupAsOneBlock() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let middle = board("Middle")
        let last = board("Last")
        let boards = [target, side, middle, last]
        let source = desk("Desk", boards: boards)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        #expect(store.beginBoardDrag(target.id))
        store.previewBoardMove(target.id, to: 3)

        #expect(store.focusedDesk?.boards.map(\.id) == [middle.id, last.id, target.id, side.id])
        store.finishBoardDrag()
    }

    @Test func boardAndDeskDragAreMutuallyExclusive() {
        let board = board("Board")
        let first = desk("First", boards: [board], focusedBoardID: board.id)
        let second = desk("Second")
        let store = DenStore(
            state: DenState(desks: [first, second], focusedDeskID: first.id))

        #expect(store.beginDeskDrag(second.id))
        #expect(store.activeDrag == .desk(second.id))
        #expect(!store.beginBoardDrag(board.id))
        #expect(!store.isBoardDragging)
        #expect(store.isDeskDragging)

        store.finishDeskDrag()
        #expect(store.beginBoardDrag(board.id))
        #expect(store.activeDrag == .board(board.id))
        #expect(!store.beginDeskDrag(second.id))
        #expect(store.isBoardDragging)
        #expect(!store.isDeskDragging)
    }

    @Test func cancelledBoardDragRestoresAndPersistsOriginalOrder() {
        let boards = [board("A"), board("B"), board("C")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        var persistedState: DenState?
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) {
            persistedState = $0
        }

        #expect(store.beginBoardDrag(boards[0].id))
        store.previewBoardMove(boards[0].id, to: 2)
        store.restoreBoardOrder(boards.map(\.id), in: source.id)
        store.finishBoardDrag()

        #expect(store.focusedDesk?.boards.map(\.id) == boards.map(\.id))
        #expect(persistedState?.desks[0].boards.map(\.id) == boards.map(\.id))
    }

    @Test func movingBoardToDeskPlacesItAfterTargetAndFocusesIt() {
        let moved = board("Moved")
        let targetBoards = [board("Before"), board("Target"), board("After")]
        let source = desk("Source", boards: [moved])
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        withStore(desks: [source, target]) { store in
            store.moveFocusedBoardToNextDesk()

            #expect(store.state.desks[0].boards.isEmpty)
            #expect(store.state.desks[0].focusedBoardID == nil)
            #expect(
                store.state.desks[1].boards.map(\.id) == [
                    targetBoards[0].id, targetBoards[1].id, moved.id, targetBoards[2].id,
                ])
            #expect(store.focusedDesk?.id == target.id)
            #expect(store.focusedDesk?.focusedBoardID == moved.id)
        }
    }

    @Test func removingBoardFocusesPreviousBoard() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.removeFocusedBoard()

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(store.recentlyRemovedBoards.first?.board.id == boards[1].id)
        }
    }

    @Test func removingAndRestoringBoardRestoresSheetNavigationPause() {
        let board = BoardState(
            label: "Paused",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/"),
            sheetNavigationPaused: true)
        let store = DenStore(
            state: DenState(
                desks: [desk("Desk", boards: [board], focusedBoardID: board.id)],
                focusedDeskID: UUID()))
        store.removeFocusedBoard()

        #expect(store.recentlyRemovedBoards.first?.board.sheetNavigationPaused == true)

        store.restoreRecentlyRemovedBoard()

        #expect(store.focusedBoard?.sheetNavigationPaused == true)
    }

    @Test func removingFirstBoardFocusesNextBoard() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            store.removeFocusedBoard()

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
        }
    }

    @Test func removingLastBoardFocusesPreviousBoard() {
        let boards = [board("A"), board("B")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.removeFocusedBoard()

            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test func removingBoardCanPreferNextBoard() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.removeBoard(boards[1].id, focusNext: true)

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[2].id)
        }

        let lastBoards = [board("A"), board("B")]
        withStore(desks: [desk("Desk", boards: lastBoards, focusedBoardID: lastBoards[1].id)]) { store in
            store.removeBoard(lastBoards[1].id, focusNext: true)

            #expect(store.focusedDesk?.focusedBoardID == lastBoards[0].id)
        }
    }

    @Test func removingUnfocusedBoardKeepsFocus() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.removeBoard(boards[0].id)

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
        }
    }

    @Test func removingLastBoardClearsScrollOffsetX() {
        let onlyBoard = board("Only")
        var deskState = desk("Desk", boards: [onlyBoard], focusedBoardID: onlyBoard.id)
        deskState.scrollOffsetX = 250.0
        let store = DenStore(state: DenState(desks: [deskState], focusedDeskID: deskState.id))
        #expect(store.state.desks[0].scrollOffsetX == 250.0)

        store.removeBoard(onlyBoard.id)
        #expect(store.state.desks[0].boards.isEmpty)
        #expect(store.state.desks[0].scrollOffsetX == nil)
    }

    @Test func removingFocusedBoardClearsScrollOffsetX() {
        let boardA = board("A")
        let boardB = board("B")
        var deskState = desk("Desk", boards: [boardA, boardB], focusedBoardID: boardB.id)
        deskState.scrollOffsetX = 350.0
        let store = DenStore(state: DenState(desks: [deskState], focusedDeskID: deskState.id))
        #expect(store.state.desks[0].scrollOffsetX == 350.0)

        store.removeBoard(boardB.id)
        #expect(store.state.desks[0].focusedBoardID == boardA.id)
        #expect(store.state.desks[0].scrollOffsetX == nil)
    }

    @Test func duplicatingFocusedBoardClearsScrollOffsetX() {
        let boardA = board("A")
        let boardB = board("B")
        var deskState = desk("Desk", boards: [boardA, boardB], focusedBoardID: boardB.id)
        deskState.scrollOffsetX = 350.0
        let store = DenStore(state: DenState(desks: [deskState], focusedDeskID: deskState.id))
        #expect(store.state.desks[0].scrollOffsetX == 350.0)

        store.duplicateFocusedBoard()
        #expect(store.state.desks[0].boards.count == 3)
        #expect(store.state.desks[0].scrollOffsetX == nil)
    }

    @Test func insertingFocusedBoardClearsScrollOffsetX() {
        let boardA = board("A")
        var deskState = desk("Desk", boards: [boardA], focusedBoardID: boardA.id)
        deskState.scrollOffsetX = 200.0
        let store = DenStore(state: DenState(desks: [deskState], focusedDeskID: deskState.id))
        #expect(store.state.desks[0].scrollOffsetX == 200.0)

        _ = store.createBoard(urlString: "https://example.com", focus: true)
        #expect(store.state.desks[0].scrollOffsetX == nil)
    }

    @Test func deskStateFocusedBoardIDChangeClearsScrollOffsetX() {
        let boardA = board("A")
        let boardB = board("B")
        var deskState = desk("Desk", boards: [boardA, boardB], focusedBoardID: boardA.id)
        deskState.scrollOffsetX = 150.0

        deskState.focusedBoardID = boardA.id
        #expect(deskState.scrollOffsetX == 150.0)

        deskState.focusedBoardID = boardB.id
        #expect(deskState.scrollOffsetX == nil)

        deskState.scrollOffsetX = 200.0
        deskState.focusedBoardID = nil
        #expect(deskState.scrollOffsetX == nil)
    }

    @Test func removalHistoryKeepsNewestBoardsAndDoesNotPersistThem() throws {
        let boards = [board("First"), board("Second")]
        let source = desk("Source", boards: boards, focusedBoardID: boards[0].id)
        var persistedState: DenState?
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) {
            persistedState = $0
        }

        store.removeFocusedBoard()
        store.removeFocusedBoard()
        let persisted = try #require(persistedState)

        #expect(store.recentlyRemovedBoards.map { $0.board.id } == [boards[1].id, boards[0].id])
        #expect(persisted.desks[0].boards.isEmpty)
        #expect(DenStore(state: persisted).recentlyRemovedBoards.isEmpty)
    }

    @Test func removalHistoryKeepsAtMostTenBoardsAndRestoresNewestFirst() {
        let boards = (0..<12).map { board("Board \($0)") }
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            for _ in 0..<11 {
                store.removeFocusedBoard()
            }

            #expect(store.recentlyRemovedBoards.count == DenStore.maximumRecentlyRemovedBoardCount)
            #expect(
                store.recentlyRemovedBoards.map { $0.board.id }
                    == Array((1...10).reversed()).map { boards[$0].id })

            for _ in 0..<DenStore.maximumRecentlyRemovedBoardCount {
                store.restoreRecentlyRemovedBoard()
            }

            #expect(store.recentlyRemovedBoards.isEmpty)
            #expect(store.focusedDesk?.boards.map(\.id) == Array(1...11).map { boards[$0].id })
        }
    }

    @Test func restorationUsesOriginalDeskIndexAndBoardIdentity() {
        let boards = [board("First"), board("Restored", width: 760), board("Last")]
        let source = desk("Source", boards: boards, focusedBoardID: boards[1].id)
        withStore(desks: [source]) { store in
            store.removeFocusedBoard()
            store.restoreRecentlyRemovedBoard()

            #expect(store.focusedDesk?.boards == boards)
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(store.recentlyRemovedBoards.isEmpty)
        }
    }

    @Test func restorationAtStaleIndexDoesNotSplitExistingSideBoardGroup() throws {
        // Arrange
        let target = board("Target")
        let removed = board("Removed")
        let following = board("Following")
        let source = desk("Desk", boards: [target, removed, following], focusedBoardID: removed.id)
        try withStore(desks: [source]) { store in
            store.removeBoard(removed.id)
            let sideID = try #require(store.createInspectionBoard(targetBoardID: target.id))

            // Act
            store.restoreRecentlyRemovedBoard()

            // Assert
            let boards = try #require(store.focusedDesk?.boards)
            #expect(boards.map(\.id) == [target.id, sideID, removed.id, following.id])
            #expect(BoardGroup.containing(target.id, in: boards)?.boards.map(\.id) == [target.id, sideID])
        }
    }

    @Test func restorationToFallbackDeskDoesNotSplitFocusedSideBoardGroup() throws {
        // Arrange
        let removed = board("Removed")
        let source = desk("Source", boards: [removed], focusedBoardID: removed.id)
        let target = board("Target")
        let side = BoardState(width: 360, targetBoardID: target.id)
        let destination = desk("Destination", boards: [target, side], focusedBoardID: target.id)
        try withStore(desks: [source, destination]) { store in
            store.removeBoard(removed.id)
            store.deleteFocusedDesk()

            // Act
            store.restoreRecentlyRemovedBoard()

            // Assert
            let boards = try #require(store.focusedDesk?.boards)
            #expect(boards.map(\.id) == [target.id, side.id, removed.id])
            #expect(BoardGroup.containing(target.id, in: boards)?.boards.map(\.id) == [target.id, side.id])
        }
    }

    @Test func restorationCreatesANewBoardRuntime() throws {
        let removed = board("Removed")
        try withStore(desks: [desk("Desk", boards: [removed])]) { store in
            let originalRuntime = store.webRuntime(for: removed)

            store.removeFocusedBoard()
            #expect(store.webRuntimes[removed.id] == nil)

            store.restoreRecentlyRemovedBoard()
            let restoredBoard = try #require(store.focusedDesk?.boards.first)
            let restoredRuntime = store.webRuntime(for: restoredBoard)
            #expect(restoredRuntime !== originalRuntime)
        }
    }

    @Test func removingBoardDisposesItsRuntime() {
        let removed = board("Removed")
        withStore(desks: [desk("Desk", boards: [removed])]) { store in
            let runtime = store.webRuntime(for: removed)

            store.removeFocusedBoard()

            #expect(store.webRuntimes[removed.id] == nil)
            #expect(runtime.webView.navigationDelegate == nil)
            #expect(runtime.webView.uiDelegate == nil)
        }
    }

    @Test func restorationFallsBackRightOfFocusedBoardWhenSourceDeskIsGone() {
        let removed = board("Removed")
        let source = desk("Source", boards: [removed])
        let targetBoards = [board("Before"), board("Focused"), board("After")]
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        withStore(desks: [source, target]) { store in
            store.removeFocusedBoard()
            store.deleteFocusedDesk()
            store.restoreRecentlyRemovedBoard()

            #expect(store.focusedDesk?.id == target.id)
            #expect(
                store.focusedDesk?.boards.map(\.id) == [
                    targetBoards[0].id, targetBoards[1].id, removed.id, targetBoards[2].id,
                ])
            #expect(store.focusedDesk?.focusedBoardID == removed.id)
        }
    }

    @Test func mouseResizeChangesTargetBoardWidthWithinBounds() {
        let boards = [board("First"), board("Second")]
        withStore(desks: [desk("Desk", boards: boards)]) { store in
            store.resizeBoard(boards[1].id, to: 760)
            #expect(store.focusedDesk?.boards.map(\.width) == [520, 760])

            store.resizeBoard(boards[1].id, to: 100)
            #expect(store.focusedDesk?.boards[1].width == 280)

            store.resizeBoard(boards[1].id, to: 2_000)
            #expect(store.focusedDesk?.boards[1].width == 1400)
        }
    }

    @Test func pairedMouseResizeKeepsOuterEdgesFixed() {
        let boards = [board("First", width: 520), board("Second", width: 760)]
        withStore(desks: [desk("Desk", boards: boards)]) { store in
            // Arrange
            let totalWidth = boards.map(\.width).reduce(0, +)

            // Act
            store.resizeBoardPair(boards[0].id, to: 700)

            // Assert
            #expect(store.focusedDesk?.boards.map(\.width) == [700, 580])
            #expect(store.focusedDesk?.boards.map(\.width).reduce(0, +) == totalWidth)
        }
    }

    @Test func pairedMouseResizeRespectsBothBoardMinimumWidths() {
        let boards = [board("First", width: 520), board("Second", width: 760)]
        withStore(desks: [desk("Desk", boards: boards)]) { store in
            // Arrange
            let expectedMinimumPairWidth = BoardState.minimumWidth

            // Act
            store.resizeBoardPair(boards[0].id, to: 2_000)

            // Assert
            #expect(store.focusedDesk?.boards.map(\.width) == [1_000, expectedMinimumPairWidth])
        }
    }

    @Test func adjustsEveryBoardInFocusedDeskWithinBounds() {
        let boards = [board("Narrow", width: 280), board("Wide", width: 1_400)]
        let otherBoard = board("Other", width: 760)
        let firstDesk = desk("First", boards: boards, focusedBoardID: boards[0].id)
        let secondDesk = desk("Second", boards: [otherBoard])
        withTestViewModel(desks: [firstDesk, secondDesk]) { viewModel in
            let store = viewModel.store
            viewModel.toggleFocusedBoardMaximized()

            viewModel.adjustFocusedDeskBoardWidths(by: -80)
            #expect(store.focusedDesk?.boards.map(\.width) == [280, 1_320])
            #expect(store.state.desks[1].boards.map(\.width) == [760])
            #expect(viewModel.maximizedBoardID == nil)

            viewModel.adjustFocusedDeskBoardWidths(by: 160)
            #expect(store.focusedDesk?.boards.map(\.width) == [440, 1_400])
        }
    }

    @Test func resizesEveryBoardInFocusedDeskToFitCurrentWindow() {
        let firstBoards = [board("First", width: 440), board("Second", width: 760)]
        let otherBoard = board("Other", width: 980)
        let firstDesk = desk("First", boards: firstBoards, focusedBoardID: firstBoards[0].id)
        let secondDesk = desk("Second", boards: [otherBoard])
        var saveCount = 0
        withTestViewModel(
            desks: [firstDesk, secondDesk],
            onSave: { _ in
                saveCount += 1
                return true
            },
            body: { viewModel in
                let store = viewModel.store
                viewModel.updateBoardLayout(availableWidth: 1_180, spacing: 10)
                viewModel.toggleFocusedBoardMaximized()
                store.state.desks[0].scrollOffsetX = 180
                let centerRequest = viewModel.centerFocusedBoardRequest
                let saveCountBeforeResize = saveCount

                #expect(viewModel.resizeFocusedDeskBoards(toFit: 3))
                #expect(
                    store.focusedDesk?.boards.allSatisfy {
                        abs($0.width - 386.666_666_666_666_7) < 0.001
                    } == true)
                #expect(store.state.desks[1].boards[0].width == 980)
                #expect(store.state.desks[0].scrollOffsetX == nil)
                #expect(viewModel.maximizedBoardID == nil)
                #expect(viewModel.centerFocusedBoardRequest == centerRequest + 1)
                #expect(saveCount == saveCountBeforeResize + 1)
            })
    }

    @Test func rejectsBoardFitCountsOutsideCurrentWidth() {
        let boards = [board("First"), board("Second")]
        withTestViewModel(desks: [desk("Desk", boards: boards)]) { viewModel in
            let store = viewModel.store
            #expect(viewModel.boardLayoutMetrics == nil)
            #expect(viewModel.boardWidth(toFit: 3) == nil)

            viewModel.updateBoardLayout(availableWidth: 1_080, spacing: 10)

            #expect(
                viewModel.boardLayoutMetrics
                    == BoardLayoutMetrics(availableWidth: 1_080, spacing: 10))
            #expect(viewModel.boardWidth(toFit: 3) != nil)
            #expect(viewModel.boardWidth(toFit: 4) == nil)
            #expect(!viewModel.resizeFocusedDeskBoards(toFit: 4))
            #expect(store.focusedDesk?.boards.map(\.width) == [520, 520])
        }
    }

    @Test func oneBoardFitUsesFullWindowBeyondManualResizeLimit() {
        withTestViewModel(desks: [desk("Desk", boards: [board("Wide")])]) { viewModel in
            let store = viewModel.store
            viewModel.updateBoardLayout(availableWidth: 2_480, spacing: 10)

            #expect(viewModel.resizeFocusedDeskBoards(toFit: 1))
            #expect(store.focusedDesk?.boards[0].width == 2_480)
        }
    }

    @Test func reloadingFocusedBoardDoesNotChangeDenState() {
        let current = board("Current", url: "https://example.com/path")
        withStore(desks: [desk("Desk", boards: [current])]) { store in
            let stateBeforeReload = store.state

            store.reloadFocusedBoard()

            #expect(store.state == stateBeforeReload)
        }
    }

    @Test func navigatingAnotherBoardFocusesIt() {
        let first = board("First")
        let second = board("Second")
        withStore(desks: [desk("Desk", boards: [first, second], focusedBoardID: first.id)]) { store in
            store.goBackInBoard(second.id)

            #expect(store.focusedDesk?.focusedBoardID == second.id)
        }
    }

    private func arrowEvent(
        _ specialKey: NSEvent.SpecialKey,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        let (characters, keyCode): (String, UInt16) =
            switch specialKey {
            case .leftArrow: ("\u{F702}", 123)
            case .rightArrow: ("\u{F703}", 124)
            default: ("", 0)
            }
        return try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func popupStore(for sourceBoard: BoardState) -> DenStore {
        let sourceDesk = desk("Desk", boards: [sourceBoard], focusedBoardID: sourceBoard.id)
        return DenStore(
            state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()))
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }

    private func waitForZmxSessionLoad(_ viewModel: DenViewModel) async {
        await viewModel.zmxSessions.waitForRefresh()
    }

    @Test func openBoardFromClipboardOpensBoardToRightAndExitsDenMode() {
        let source = desk("Desk", boards: [board("First")])
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        #expect(viewModel.isDenMode)
        #expect(store.focusedDesk?.boards.count == 1)

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/clipboard", forType: .string)

        viewModel.openBoardFromClipboard(pasteboard: pasteboard)

        #expect(store.focusedDesk?.boards.count == 2)
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://example.com/clipboard"))
        #expect(!viewModel.isDenMode)
        #expect(store.latestFeedback == nil)
    }

    @Test func openBoardFromClipboardShowsWarningFeedbackWhenEmpty() {
        let source = desk("Desk", boards: [board("First")])
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        let initialCount = store.focusedDesk?.boards.count ?? 0

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()

        viewModel.openBoardFromClipboard(pasteboard: pasteboard)

        #expect(store.focusedDesk?.boards.count == initialCount)
        #expect(store.latestFeedback?.message == "Clipboard is empty.")
    }

    @Test func createTerminalBoardAddsBoardToActiveDeskAndFocuses() throws {
        let source = desk("Desk", boards: [board("First")])
        try withTestStore(desks: [source]) { store in
            let dir = FileManager.default.temporaryDirectory.path
            let boardID = try #require(store.createTerminalBoard(workingDirectory: dir, focus: true))

            let createdBoard = try #require(store.board(for: boardID))
            #expect(createdBoard.isTerminal)
            #expect(createdBoard.terminalWorkingDirectory == dir)
            #expect(store.focusedBoard?.id == boardID)
        }
    }

    @Test func terminalTitleChangeDoesNotTriggerSave() throws {
        let dir = FileManager.default.temporaryDirectory.path
        let terminalBoard = BoardState(width: 520, workingDirectory: dir)
        let source = desk("Desk", boards: [terminalBoard], focusedBoardID: terminalBoard.id)
        var saveCount = 0
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { _ in saveCount += 1 })

        let runtime = store.terminalRuntime(for: terminalBoard)
        defer { runtime.dispose() }

        runtime.terminalDidChangeTitle("codex: thinking...")
        #expect(store.focusedBoard?.label == "codex: thinking...")
        #expect(saveCount == 0)

        runtime.terminalDidChangeWorkingDirectory("/tmp/new-working-dir")
        #expect(store.focusedBoard?.terminalWorkingDirectory == "/tmp/new-working-dir")
        #expect(saveCount == 1)
    }

    @Test func copyBoardIDCopiesLowercasedUUIDToPasteboardAndShowsFeedback() {
        let firstBoard = board("First")
        let source = desk("Desk", boards: [firstBoard])
        withTestStore(desks: [source]) { store in
            let pasteboard = NSPasteboard.withUniqueName()
            store.copyBoardID(firstBoard.id, pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == firstBoard.id.uuidString.lowercased())
            #expect(store.latestFeedback?.message == "Copied Board ID.")
            #expect(store.latestFeedback?.severity == .success)
        }
    }

    @Test func copyBoardIDIgnoresUnknownBoardID() {
        let source = desk("Desk", boards: [board("First")])
        withTestStore(desks: [source]) { store in
            let pasteboard = NSPasteboard.withUniqueName()
            store.copyBoardID(UUID(), pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == nil)
            #expect(store.latestFeedback == nil)
        }
    }

    @Test func copyBoardLocationCopiesWebTerminalAndSessionLocations() {
        let cases: [(BoardState, String, String)] = [
            (
                BoardState(label: "Web", width: 520, currentSheetURL: URL(string: "https://example.com/sheet")),
                "https://example.com/sheet",
                "Copied Current Sheet URL."
            ),
            (
                BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp/project"),
                "/tmp/project",
                "Copied Terminal working directory."
            ),
            (
                BoardState(label: "Zellij", width: 520, zellijSessionName: "project-a"),
                "project-a",
                "Copied Zellij session name."
            ),
            (
                BoardState(label: "zmx", width: 520, zmxSessionName: "project-b"),
                "project-b",
                "Copied zmx session name."
            ),
        ]

        for (board, expectedValue, expectedFeedback) in cases {
            // Arrange
            let source = desk("Desk", boards: [board], focusedBoardID: board.id)
            let pasteboard = NSPasteboard.withUniqueName()
            withTestStore(desks: [source]) { store in
                // Act
                store.copyBoardLocation(pasteboard: pasteboard)

                // Assert
                #expect(pasteboard.string(forType: .string) == expectedValue)
                #expect(store.latestFeedback?.message == expectedFeedback)
                #expect(store.latestFeedback?.severity == .success)
            }
        }
    }

    @Test func toggleAnchorBoardSetsAndClearsAnchor() {
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let source = desk("Desk", boards: [firstBoard, secondBoard])
        withTestStore(desks: [source]) { store in
            store.focusBoard(firstBoard.id)

            store.toggleAnchorBoard()
            #expect(store.focusedDesk?.anchorBoardID == firstBoard.id)
            #expect(store.latestFeedback?.message == "Set Anchor Board")

            store.toggleAnchorBoard()
            #expect(store.focusedDesk?.anchorBoardID == nil)
            #expect(store.latestFeedback?.message == "Cleared Anchor Board")

            store.focusBoard(secondBoard.id)
            store.toggleAnchorBoard()
            #expect(store.focusedDesk?.anchorBoardID == secondBoard.id)
            #expect(store.latestFeedback?.message == "Set Anchor Board")
        }
    }

    @Test func toggleAnchorBoardForAnotherDeskKeepsCurrentFocus() {
        let focusedBoard = board("Focused")
        let targetBoard = board("Target")
        let focusedDesk = desk("Current", boards: [focusedBoard], focusedBoardID: focusedBoard.id)
        let targetDesk = desk("Overview", boards: [targetBoard])

        withTestStore(desks: [focusedDesk, targetDesk]) { store in
            store.focusBoard(focusedBoard.id)

            store.toggleAnchorBoard(targetBoard.id, in: targetDesk.id)
            #expect(store.state.desks.first(where: { $0.id == targetDesk.id })?.anchorBoardID == targetBoard.id)
            #expect(store.focusedDesk?.id == focusedDesk.id)
            #expect(store.focusedBoard?.id == focusedBoard.id)

            store.toggleAnchorBoard(targetBoard.id, in: targetDesk.id)
            #expect(store.state.desks.first(where: { $0.id == targetDesk.id })?.anchorBoardID == nil)
            #expect(store.focusedDesk?.id == focusedDesk.id)
            #expect(store.focusedBoard?.id == focusedBoard.id)
        }
    }

    @Test func jumpToAnchorBoardTogglesBetweenAnchorAndOrigin() {
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let source = desk("Desk", boards: [firstBoard, secondBoard])
        withTestStore(desks: [source]) { store in
            store.focusBoard(firstBoard.id)
            store.toggleAnchorBoard()

            store.focusBoard(secondBoard.id)
            #expect(store.focusedBoard?.id == secondBoard.id)

            store.jumpToAnchorBoard()
            #expect(store.focusedBoard?.id == firstBoard.id)

            store.jumpToAnchorBoard()
            #expect(store.focusedBoard?.id == secondBoard.id)
        }
    }

    @Test func jumpToAnchorBoardShowsWarningWhenNoAnchor() {
        let source = desk("Desk", boards: [board("First")])
        withTestStore(desks: [source]) { store in
            store.jumpToAnchorBoard()
            #expect(store.latestFeedback?.message == "No Anchor Board in Desk")
            #expect(store.latestFeedback?.severity == .warning)
        }
    }

    @Test func removingAnchorBoardClearsAnchor() {
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let source = desk("Desk", boards: [firstBoard, secondBoard])
        withTestStore(desks: [source]) { store in
            store.focusBoard(firstBoard.id)
            store.toggleAnchorBoard()
            #expect(store.focusedDesk?.anchorBoardID == firstBoard.id)
            store.focusBoard(secondBoard.id)
            store.jumpToAnchorBoard()
            #expect(store.anchorJumpOriginBoardIDByDesk[source.id] == secondBoard.id)

            store.removeBoard(firstBoard.id)
            #expect(store.focusedDesk?.anchorBoardID == nil)
            #expect(store.anchorJumpOriginBoardIDByDesk[source.id] == nil)
        }
    }

    @Test func duplicateTerminalBoardResetsTemporaryContextAndFollowsInsertionContract() {
        let first = BoardState(width: 400, workingDirectory: "/tmp")
        let second = board("Second")
        let source = desk("Desk", boards: [first, second], focusedBoardID: first.id)
        withTestViewModel(desks: [source]) { viewModel in
            let store = viewModel.store
            viewModel.setTemporaryContext(.openBoard)
            store.duplicateFocusedBoard()

            #expect(viewModel.temporaryContext == nil)
            #expect(viewModel.isDenMode == false)
            let boards = store.focusedDesk?.boards ?? []
            #expect(boards.count == 3)
            #expect(boards[0].id == first.id)
            #expect(boards[1].id != first.id)
            #expect(boards[1].terminalWorkingDirectory == "/tmp")
            #expect(boards[2].id == second.id)
            #expect(store.focusedBoard?.id == boards[1].id)
        }
    }

    @Test func openBoardRecentItemDelegatesToOpenBoardInput() {
        let source = desk("Desk")
        withTestStore(desks: [source]) { store in
            store.preferences.setZmxPath("/usr/bin/zmx")
            store.preferences.setZellijPath("/usr/bin/zellij")

            store.openBoard(recentItem: .zellij(sessionName: "my-session"))
            #expect(store.focusedBoard?.zellijSessionName == "my-session")
            #expect(store.recentItems.first == .zellij(sessionName: "my-session"))

            store.openBoard(recentItem: .zmx(sessionName: "zmx-session"))
            #expect(store.focusedBoard?.zmxSessionName == "zmx-session")
            #expect(store.recentItems.first == .zmx(sessionName: "zmx-session"))
        }
    }
}

private struct StubTerminalCommandRunner: TerminalCommandRunning, Sendable {
    let responses: [[String]: TerminalCommandResult]

    func run(
        executablePath: String,
        arguments: [String],
        timeout: Duration
    ) async throws -> TerminalCommandResult {
        guard let response = responses[arguments] else {
            throw TerminalCommandError(message: "Missing stub response for \(arguments)")
        }
        return response
    }
}
