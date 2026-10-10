import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation
import GhosttyTerminal
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenControllerBoardTests {
    @Test func terminalInputResolvesHomeRelativeAndAbsoluteDirectories() throws {
        let home = FileManager.default.temporaryDirectory

        #expect(
            try DenController.resolveTerminalInput(":terminal", homeDirectory: home)?.get()
                == home.standardizedFileURL.path)
        #expect(
            try DenController.resolveTerminalInput(":terminal .", homeDirectory: home)?.get()
                == home.standardizedFileURL.path)
        #expect(
            try DenController.resolveTerminalInput(
                ":terminal \(home.path)", homeDirectory: URL(fileURLWithPath: "/"))?.get()
                == home.standardizedFileURL.path)
        #expect(DenController.resolveTerminalInput(":terminally", homeDirectory: home) == nil)

        let missing = DenController.resolveTerminalInput(
            ":terminal missing-\(UUID().uuidString)", homeDirectory: home)
        #expect(throws: TerminalInputError.self) { try missing?.get() }
    }

    @Test func zellijBoardsPersistOptionalSessionNames() throws {
        let source = desk("Desk")
        try withTestController(desks: [source]) { controller in
            controller.preferences.setZellijPath("/opt/homebrew/bin/zellij")

            controller.openBoard(input: ":zellij project-a")
            let named = try #require(controller.focusedBoard)
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

            controller.openBoard(input: ":zellij")
            let welcome = try #require(controller.focusedBoard)
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
        withTestWindowModel(desks: [source]) { windowModel, controller in
            windowModel.showOpenBoardPanel()
            controller.openBoard(input: ":zellij")

            #expect(controller.focusedBoard?.isZellij != true)
            #expect(windowModel.openBoard.message?.contains("absolute Zellij executable path") == true)
            #expect(controller.recentItems.isEmpty)
        }
    }

    @Test func zmxBoardsPersistNamedSessionAndOpenSessionsList() async throws {
        let source = desk("Desk")
        let runner = StubTerminalCommandRunner(responses: [
            ["list"]: TerminalCommandResult(terminationStatus: 0, standardOutput: "")
        ])
        try await withTestWindowModel(desks: [source], terminalCommandRunner: runner) {
            windowModel, controller in
            controller.preferences.setZmxPath("/opt/homebrew/bin/zmx")

            controller.openBoard(input: ":zmx project-a")
            let board = try #require(controller.focusedBoard)
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

            controller.openBoard(input: ":zmx")
            await waitForZmxSessionLoad(windowModel)
            #expect(controller.focusedDesk?.boards.count == 1)
            #expect(windowModel.isZmxSessionsPresented)
            #expect(controller.recentItems.first == .zmx(sessionName: "project-a"))
            #expect(RecentItem.zmx(sessionName: "").displayText == ":zmx")

            windowModel.hideZmxSessions()
            controller.openBoard(recentItem: .zmx(sessionName: ""))
            await waitForZmxSessionLoad(windowModel)
            #expect(windowModel.isZmxSessionsPresented)

            windowModel.hideZmxSessions()
            windowModel.showOpenBoardPanel()
            windowModel.openBoard.submit(":zmx", preferredWidth: windowModel.defaultBoardWidth)
            await waitForZmxSessionLoad(windowModel)
            windowModel.hideZmxSessions()
            #expect(windowModel.isOpenBoardPanelPresented)
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
        await withTestWindowModel(
            desks: [source], terminalCommandRunner: commandRunner
        ) { windowModel, controller in
            controller.preferences.setZmxPath("/opt/homebrew/bin/zmx")

            windowModel.showZmxSessions(selectedSessionName: "den-vi")
            await waitForZmxSessionLoad(windowModel)

            #expect(
                windowModel.zmxSessions.groups == [
                    ZmxSessionGroup(rootSessionName: "den", isRootActive: true, childSessionNames: ["den-vi"]),
                    ZmxSessionGroup(
                        rootSessionName: "old-root",
                        isRootActive: false,
                        childSessionNames: ["old-root-debug"]),
                ])
            #expect(windowModel.zmxSessions.selectedSessionName == "den-vi")
            windowModel.zmxSessions.setQuery("vi")
            #expect(
                windowModel.zmxSessions.filteredGroups
                    == [ZmxSessionGroup(rootSessionName: "den", isRootActive: true, childSessionNames: ["den-vi"])]
            )
            windowModel.clearZmxSessionFilter()

            windowModel.openZmxSession("den-vi")
            #expect(controller.focusedBoard?.zmxSessionName == "den-vi")
            #expect(controller.focusedBoard?.zmxRootSessionName == "den")
            #expect(controller.recentItems.first == .zmx(sessionName: "den-vi"))
            #expect(!windowModel.isZmxSessionsPresented)

            windowModel.showZmxSessions()
            await waitForZmxSessionLoad(windowModel)
            windowModel.openZmxSession("den-vi")
            #expect(controller.focusedDesk?.boards.count == 1)

            windowModel.showZmxSessions()
            await waitForZmxSessionLoad(windowModel)
            windowModel.killZmxSession("den-vi")
            await waitForZmxSessionLoad(windowModel)
            #expect(windowModel.zmxSessions.message == nil)
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
        await withTestWindowModel(
            desks: [desk("Desk", boards: [existing], focusedBoardID: existing.id)],
            terminalCommandRunner: commandRunner
        ) { windowModel, controller in
            controller.preferences.setZmxPath("/opt/homebrew/bin/zmx")
            windowModel.showZmxSessions(selectedSessionName: "den-vi")
            await waitForZmxSessionLoad(windowModel)

            // Act
            windowModel.openZmxSession("den-vi")

            // Assert
            #expect(controller.focusedDesk?.boards.count == 1)
            #expect(controller.focusedBoard?.id == existing.id)
            #expect(controller.focusedBoard?.zmxRootSessionName == "den")
        }
    }

    @Test func changingWebExtensionHostKeepsTerminalRuntimeAlive() {
        let terminal = BoardState(width: 520, zmxSessionName: "project-a", workingDirectory: "/tmp")
        let source = desk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let controller = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: makeTestSheetNavigationManager(),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            onSave: nil)
        let runtime = controller.terminalRuntime(for: terminal)
        let host = MV3WebExtensionHost(
            profileID: ProfileID(),
            websiteDataStore: .nonPersistent(),
            userContentController: WKUserContentController())
        let window = host.window(for: UUID())
        defer {
            controller.releaseRuntimes()
            host.dispose()
        }

        controller.updateWebExtensionHost(host, window: window)

        #expect(controller.terminalRuntimes[terminal.id] === runtime)
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
        try await withTestWindowModel(desks: [source], terminalCommandRunner: runner) {
            windowModel, controller in
            controller.preferences.setZmxPath("/usr/bin/zmx")

            controller.duplicateFocusedBoardFromFirstSheet()
            await controller.waitForZmxCommand()
            let automaticChild = try #require(controller.focusedBoard)
            #expect(controller.focusedDesk?.boards.count == 2)
            #expect(automaticChild.zmxSessionName == "den-2")
            #expect(automaticChild.zmxRootSessionName == "den")
            #expect(automaticChild.terminalWorkingDirectory == "/tmp/project")
            #expect(windowModel.temporaryContext == nil)
            #expect(controller.recentItems.isEmpty)

            controller.focusBoard(sourceBoard.id)
            controller.duplicateFocusedBoard()
            await controller.waitForZmxCommand()
            #expect(windowModel.temporaryContext == .zmxDuplication)
            #expect(controller.focusedDesk?.boards.count == 2)

            controller.duplicateFocusedZmxBoard(suffix: "vi")
            await controller.waitForZmxCommand()
            let firstChild = try #require(controller.focusedBoard)
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

            controller.duplicateFocusedBoard()
            await controller.waitForZmxCommand()
            controller.duplicateFocusedZmxBoard(suffix: "nvim")
            await controller.waitForZmxCommand()
            #expect(controller.focusedBoard?.zmxSessionName == "den-nvim")
            #expect(controller.focusedBoard?.zmxRootSessionName == "den")

            controller.focusBoard(firstChild.id)
            controller.duplicateFocusedBoard()
            await controller.waitForZmxCommand()
            controller.duplicateFocusedZmxBoard(suffix: "vi")
            await controller.waitForZmxCommand()
            #expect(controller.focusedBoard?.zmxSessionName == "den-vi-2")
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
        await withTestWindowModel(
            desks: [source], terminalCommandRunner: commandRunner
        ) { windowModel, controller in
            controller.preferences.setZmxPath("/usr/bin/zmx")

            controller.duplicateFocusedBoard()
            await controller.waitForZmxCommand()
            #expect(windowModel.zmxDuplicationRootSessionName == "den")
            controller.duplicateFocusedZmxBoard(suffix: "nvim")
            await controller.waitForZmxCommand()
            #expect(controller.focusedBoard?.zmxSessionName == "den-nvim")
            #expect(controller.focusedBoard?.zmxRootSessionName == "den")
        }
    }

    @Test func invalidTerminalInputDoesNotCreateRecentItem() {
        let source = desk("Desk")
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))

        controller.openBoard(input: ":terminal /missing/den-browser-\(UUID().uuidString)")

        #expect(controller.focusedDesk?.boards.isEmpty == true)
        #expect(controller.recentItems.isEmpty)
    }

    @Test func popupBoardKeepsItsOpenerRequestAndUsesTheProvidedWebView() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let controller = popupController(for: sourceBoard)
        defer { controller.releaseRuntimes() }

        let popupURL = try #require(URL(string: "https://login.example/authorize"))
        let backgroundPopup = RuntimeWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // Act
        #expect(
            controller.createPopupBoard(
                backgroundPopup,
                requestedURL: popupURL,
                fromBoardID: sourceBoard.id,
                modifierFlags: .command))
        let backgroundBoard = try #require(controller.state.desks[0].boards.first { $0.id != sourceBoard.id })

        // Assert
        #expect(controller.focusedBoard?.id == sourceBoard.id)
        #expect(backgroundBoard.currentSheetURL == popupURL)
        #expect(backgroundBoard.firstSheetURL == popupURL)
        #expect(controller.webRuntimes[backgroundBoard.id]?.webView === backgroundPopup)
        #expect(backgroundPopup.url == nil)
    }

    @Test func commandShiftPopupFocusesItsBoard() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let controller = popupController(for: sourceBoard)
        defer { controller.releaseRuntimes() }
        let popup = RuntimeWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // Act
        #expect(
            controller.createPopupBoard(
                popup,
                requestedURL: nil,
                fromBoardID: sourceBoard.id,
                modifierFlags: [.command, .shift]))

        // Assert
        let focusedBoard = try #require(controller.focusedBoard)
        #expect(focusedBoard.id != sourceBoard.id)
        #expect(focusedBoard.currentSheetURL == nil)
        #expect(controller.webRuntimes[focusedBoard.id]?.webView === popup)
        #expect(popup.url == nil)
    }

    @Test func popupBoardFocusesByDefault() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let controller = popupController(for: sourceBoard)
        defer { controller.releaseRuntimes() }
        let popup = RuntimeWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // Act
        #expect(
            controller.createPopupBoard(
                popup,
                requestedURL: nil,
                fromBoardID: sourceBoard.id,
                modifierFlags: []))

        // Assert
        let focusedBoard = try #require(controller.focusedBoard)
        #expect(focusedBoard.id != sourceBoard.id)
        #expect(controller.webRuntimes[focusedBoard.id]?.webView === popup)
    }

    @Test func closingPopupWebViewRemovesItsBoard() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let controller = popupController(for: sourceBoard)
        defer { controller.releaseRuntimes() }
        let popup = RuntimeWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        #expect(
            controller.createPopupBoard(
                popup,
                requestedURL: nil,
                fromBoardID: sourceBoard.id,
                modifierFlags: []))
        let popupBoard = try #require(controller.focusedBoard)

        // Act
        controller.webRuntimes[popupBoard.id]?.webViewDidClose(popup)

        // Assert
        #expect(controller.board(for: popupBoard.id) == nil)
        #expect(controller.webRuntimes[popupBoard.id] == nil)
    }

    @Test func windowOpenPopupPreservesOpenerPostMessage() async throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let controller = popupController(for: sourceBoard)
        defer { controller.releaseRuntimes() }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = controller.websiteDataStore
        configuration.userContentController = controller.sheetNavigation.userContentController
        let sourceWebView = RuntimeWKWebView(frame: .zero, configuration: configuration)
        let sourceRuntime = controller.webRuntime(for: sourceBoard, popupWebView: sourceWebView)
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
        let popupBoard = try #require(controller.state.desks[0].boards.first { $0.id != sourceBoard.id })
        let popupRuntime = try #require(controller.webRuntimes[popupBoard.id])
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
        let controller = popupController(for: sourceBoard)
        defer { controller.releaseRuntimes() }
        let sourceRuntime = controller.webRuntime(for: sourceBoard)
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
        #expect(controller.state.desks[0].boards.count == 2)
        #expect(controller.state.desks[0].boards[1].id != sourceBoard.id)
    }

    @Test func terminalBoardsCreateDuplicateRemoveAndRestoreWithRecentItems() throws {
        let source = desk("Desk")
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path

        controller.openBoard(input: ":terminal \(directory)", preferredWidth: 640)

        let original = try #require(controller.focusedBoard)
        #expect(original.isTerminal)
        #expect(original.terminalWorkingDirectory == directory)
        #expect(original.width == 640)
        #expect(controller.recentItems == [.terminal(workingDirectory: directory)])

        controller.duplicateFocusedBoard()
        let duplicate = try #require(controller.focusedBoard)
        #expect(duplicate.id != original.id)
        #expect(duplicate.terminalWorkingDirectory == directory)

        controller.removeFocusedBoard()
        controller.restoreRecentlyRemovedBoard()
        #expect(controller.focusedBoard?.id == duplicate.id)
        #expect(controller.focusedBoard?.terminalWorkingDirectory == directory)
    }

    @Test func terminalFocusNotificationDoesNotExitDenMode() {
        let terminal = BoardState(width: 520, workingDirectory: "/tmp")
        let source = desk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        controller.terminalRuntime(for: terminal).terminalDidChangeFocus(true)

        #expect(windowModel.isDenMode)
        #expect(controller.focusedBoard?.id == terminal.id)
    }

    @Test func boardLinkFocusIntentDoesNotConsumeNewerIntent() {
        let firstBoard = BoardState(label: "First", width: 520, currentSheetURL: nil)
        let secondBoard = BoardState(label: "Second", width: 520, currentSheetURL: nil)
        let source = desk("Desk", boards: [firstBoard, secondBoard], focusedBoardID: firstBoard.id)
        withTestWindowModel(desks: [source]) { windowModel, controller in
            controller.prepareBoardLinkFocus(firstBoard.id)
            #expect(windowModel.pendingBoardLinkFocus != nil)
            guard let firstIntent = windowModel.pendingBoardLinkFocus else { return }
            #expect(firstIntent.origin == .interactive)
            controller.prepareBoardLinkFocus(secondBoard.id)
            #expect(windowModel.pendingBoardLinkFocus != nil)
            guard let secondIntent = windowModel.pendingBoardLinkFocus else { return }

            windowModel.consumeBoardLinkFocus(firstIntent)
            #expect(windowModel.pendingBoardLinkFocus == secondIntent)

            windowModel.consumeBoardLinkFocus(secondIntent)
            #expect(windowModel.pendingBoardLinkFocus == nil)
        }
    }

    @Test func focusedBoardCreationEndsLinkFocusSuppression() throws {
        let source = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let desk = desk("Desk", boards: [source], focusedBoardID: source.id)
        withTestWindowModel(desks: [desk]) { windowModel, controller in
            controller.prepareBoardLinkFocus(source.id)
            #expect(controller.createBoard(urlString: "https://focused.example", afterBoardID: source.id) != nil)

            #expect(windowModel.pendingBoardLinkFocus == nil)
            #expect(controller.focusedBoard?.currentSheetURL?.host == "focused.example")
        }
    }

    @Test func inspectionBoardLinksToWebBoardAndReusesIt() throws {
        let target = BoardState(label: "Target", width: 520, currentSheetURL: URL(string: "https://example.com"))
        let sourceDesk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let controller = DenController(state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))

        let inspectionID = try #require(controller.createInspectionBoard(targetBoardID: target.id))
        let inspection = try #require(controller.board(for: inspectionID))

        #expect(controller.state.desks[0].boards.map(\.id) == [target.id, inspectionID])
        #expect(controller.focusedBoard?.id == inspectionID)
        #expect(inspection.isInspection)
        #expect(!inspection.isWeb)
        #expect(!inspection.isTerminal)
        #expect(inspection.isSideBoard)
        #expect(inspection.sideBoardTargetBoardID == target.id)
        #expect(try JSONDecoder().decode(BoardState.self, from: JSONEncoder().encode(inspection)) == inspection)
        #expect(controller.createInspectionBoard(targetBoardID: target.id) == inspectionID)
        #expect(controller.state.desks[0].boards.count == 2)
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
        let controller = DenController(state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))

        // Act
        if fromFirstSheet {
            controller.duplicateFocusedBoardFromFirstSheet()
        } else {
            controller.duplicateFocusedBoard()
        }

        // Assert
        #expect(controller.state.desks[0].boards.map(\.id) == [target.id, side.id])
        #expect(controller.focusedBoard?.id == side.id)
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
        let controller = DenController(state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))

        // Act
        let insertedID = try #require(controller.createBoard(urlString: "https://new.example"))

        // Assert
        #expect(controller.state.desks[0].boards.map(\.id) == [target.id, side.id, insertedID, following.id])
    }

    @Test(arguments: await [BoardState.minimumWidth, BuiltInDeskPreset.boardWidth, BoardState.maximumWidth])
    func inspectionBoardStartsAtCompactWidthRegardlessOfTargetWidth(targetWidth: Double) throws {
        // Arrange
        let target = BoardState(
            label: "Target", width: targetWidth, currentSheetURL: URL(string: "https://example.com"))
        let sourceDesk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let controller = DenController(state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))

        // Act
        let inspectionID = try #require(controller.createInspectionBoard(targetBoardID: target.id))
        let inspection = try #require(controller.board(for: inspectionID))

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
        #expect(role["targetBoardID"] as? String == target.id.rawValue.uuidString)
        #expect(object["sideBoard"] == nil)
        #expect(try JSONDecoder().decode(BoardState.self, from: encoded) == side)
    }

    @Test func backgroundBoardFocusSuppressionEndsOnNextFocus() throws {
        let source = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let other = BoardState(label: "Other", width: 520, currentSheetURL: nil)
        let desk = desk("Desk", boards: [source, other], focusedBoardID: source.id)
        try withTestWindowModel(desks: [desk]) { windowModel, controller in
            #expect(
                controller.createBoard(
                    urlString: "https://background.example",
                    afterBoardID: source.id,
                    focus: false) != nil)
            let intent = try #require(windowModel.pendingBoardLinkFocus)
            #expect(intent.origin == .interactive)
            #expect(controller.focusedBoard?.id == source.id)

            controller.focusBoard(other.id)

            #expect(windowModel.pendingBoardLinkFocus == nil)
            windowModel.consumeBoardLinkFocus(intent)
            #expect(windowModel.pendingBoardLinkFocus == nil)
        }
    }

    @Test func cliBackgroundBoardCarriesCLIInsertionOrigin() throws {
        let source = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let other = BoardState(label: "Other", width: 520, currentSheetURL: nil)
        let desk = desk("Desk", boards: [source, other], focusedBoardID: source.id)
        try withTestWindowModel(desks: [desk]) { windowModel, controller in
            #expect(
                controller.createBoard(
                    urlString: "https://cli.example",
                    afterBoardID: source.id,
                    focus: false,
                    origin: .cli) != nil)
            let intent = try #require(windowModel.pendingBoardLinkFocus)

            #expect(intent.origin == .cli)
        }
    }

    @Test func cliBackgroundBoardRemovalCarriesCLIOperationOrigin() throws {
        let left = BoardState(label: "Left", width: 520, currentSheetURL: nil)
        let focused = BoardState(label: "Focused", width: 520, currentSheetURL: nil)
        let source = desk("Desk", boards: [left, focused], focusedBoardID: focused.id)
        try withTestWindowModel(desks: [source]) { windowModel, controller in
            controller.removeBoard(left.id, origin: .cli)

            let intent = try #require(windowModel.pendingBoardRemoval)
            #expect(intent.origin == .cli)
            #expect(controller.focusedBoard?.id == focused.id)
        }
    }

    @Test func terminalLinkCreatesFocusedBoardWithoutDrawer() throws {
        // Arrange
        let terminal = BoardState(width: 520, workingDirectory: "/tmp")
        let source = desk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let url = try #require(URL(string: "https://terminal-link.example/path"))
        defer { controller.releaseRuntimes() }

        // Act
        controller.terminalRuntime(for: terminal).terminalDidRequestOpenURL(url.absoluteString, kind: .text)

        // Assert
        let createdBoard = try #require(controller.focusedDesk?.boards.last)
        #expect(createdBoard.currentSheetURL == url)
        #expect(controller.focusedDesk?.focusedBoardID == createdBoard.id)
        #expect(controller.state.drawerItems.isEmpty)
        #expect(controller.recentItems == [.url(url)])
    }

    @Test func searchesUseCurrentEngineAndPreserveQueryAndExplicitURLs() throws {
        try withTestController { controller in
            let query = "日本語 & C++ # Swift?"
            for engine in SearchEngine.allCases {
                controller.preferences.setSearchEngine(engine)
                controller.openBoard(recentItem: .search(query))
                let url = try #require(controller.focusedBoard?.currentSheetURL)
                let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
                #expect(components.host == URL(string: engine.searchURL)?.host)
                #expect(components.path == URL(string: engine.searchURL)?.path)
                let queryParameter = engine == .yahooJapan ? "p" : "q"
                #expect(components.queryItems == [URLQueryItem(name: queryParameter, value: query)])
                #expect(components.fragment == nil)
                #expect(controller.recentItems.first == .search(query))
            }
            let existingURL = controller.focusedBoard?.currentSheetURL
            controller.preferences.setSearchEngine(.duckDuckGo)
            #expect(controller.focusedBoard?.currentSheetURL == existingURL)
            #expect(controller.navigateFocusedBoard(urlString: "example.com/path?q=literal"))
            #expect(controller.focusedBoard?.currentSheetURL == URL(string: "https://example.com/path?q=literal"))
            #expect(controller.navigateFocusedBoard(urlString: query))
            #expect(controller.focusedBoard?.currentSheetURL?.host == "duckduckgo.com")
        }
    }

    @Test func openBoardAcceptsWebHostsAndRejectsInvalidURLs() throws {
        try withTestController { controller in
            _ = controller.createBoard(urlString: "localhost:3000")
            let localURL = try #require(controller.focusedDesk?.boards.last?.currentSheetURL)
            #expect(localURL.scheme == "https")
            #expect(localURL.host == "localhost")
            #expect(localURL.port == 3000)

            _ = controller.createBoard(urlString: "swift: concurrency")
            let searchURL = try #require(
                controller.focusedDesk?.boards.last?.currentSheetURL
                    .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
            #expect(searchURL.host == "www.google.com")
            #expect(searchURL.queryItems == [URLQueryItem(name: "q", value: "swift: concurrency")])

            let boardCount = try #require(controller.focusedDesk?.boards.count)
            #expect(controller.createBoard(urlString: "https://") == nil)
            #expect(controller.createBoard(urlString: "ftp://example.com") == nil)
            #expect(controller.focusedDesk?.boards.count == boardCount)
        }
    }

    @Test func localFileURLParticipatesInBoardRecentDrawerAndPresetWorkflows() throws {
        let source = desk("Desk")
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let fileURL = try #require(URL(string: "file:///tmp/Den%20Browser/index.html#notes"))

        controller.openBoard(input: fileURL.absoluteString)

        #expect(controller.focusedBoard?.currentSheetURL == fileURL)
        #expect(controller.focusedBoard?.firstSheetURL == fileURL)
        #expect(controller.recentItems.first == .url(fileURL))

        controller.keepFocusedSheetInDrawer()
        #expect(controller.state.drawerItems.first?.url == fileURL)

        #expect(controller.saveFocusedDeskAsPreset(label: "Local Files") == .created)
        #expect(controller.deskPresets.first?.boards.first?.initialSheetURL == fileURL)
    }

    @Test func editingFocusedBoardLinkReplacesCurrentSheet() throws {
        let board = board("Board", url: "https://before.example/")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.showEditBoardLinkPanel()

        #expect(controller.navigateFocusedBoard(urlString: "after.example/path"))
        #expect(controller.focusedBoard?.currentSheetURL == URL(string: "https://after.example/path"))
        #expect(controller.focusedBoard?.firstSheetURL == URL(string: "https://before.example/"))
        #expect(windowModel.temporaryContext == nil)
        #expect(!windowModel.isDenMode)
    }

    @Test func newBoardKeepsFirstSheetWhenCurrentSheetChanges() throws {
        let source = desk("Desk")
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))

        _ = controller.createBoard(urlString: "https://start.example/")
        let firstSheetURL = try #require(controller.focusedBoard?.firstSheetURL)

        #expect(controller.navigateFocusedBoard(urlString: "https://later.example/"))
        #expect(controller.focusedBoard?.currentSheetURL == URL(string: "https://later.example/"))
        #expect(controller.focusedBoard?.firstSheetURL == firstSheetURL)
    }

    @Test func openBoardCanInsertAfterSpecifiedBoard() {
        let boards = [board("First"), board("Focused"), board("Last")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[1].id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))

        controller.openBoard(input: "example.com", afterBoardID: boards.last?.id)

        #expect(controller.focusedDesk?.boards.map(\.label) == ["First", "Focused", "Last", "example.com"])
        #expect(controller.focusedDesk?.focusedBoardID == controller.focusedDesk?.boards.last?.id)
    }

    @Test func newBoardKeepsPreferredWidthBeyondManualResizeLimit() {
        for width in [BoardState.minimumWidth, BoardState.maximumWidth, 2_480] {
            let source = desk("Desk")
            let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))

            _ = controller.createBoard(urlString: "https://example.com", preferredWidth: width)

            #expect(controller.focusedBoard?.width == width)
        }
    }

    @Test func newBoardInheritsFocusedWidthWhenPreferredWidthIsUnset() {
        let source = board("Source", width: 760)
        let focusedDesk = desk("Focused", boards: [source], focusedBoardID: source.id)
        let focusedController = DenController(state: DenState(desks: [focusedDesk], focusedDeskID: focusedDesk.id))
        _ = focusedController.createBoard(urlString: "https://example.com")
        #expect(focusedController.focusedBoard?.width == 760)
    }

    @Test func emptyDeskUsesTwoBoardFitWidthAsDefault() {
        let emptyDesk = desk("Empty")
        withTestWindowModel(desks: [emptyDesk]) { windowModel, controller in
            #expect(controller.inheritedBoardWidth == BuiltInDeskPreset.boardWidth)

            windowModel.updateBoardLayout(availableWidth: 1376, spacing: 12)
            #expect(windowModel.defaultBoardWidth == 682)

            _ = controller.createBoard(urlString: "https://example.com", preferredWidth: windowModel.defaultBoardWidth)
            #expect(controller.focusedBoard?.width == 682)
        }
    }

    @Test func emptyDeskAppliesFitWidthToClipboardAndEssential() {
        let emptyDesk = desk("Empty")
        let essential = Essential(name: "Search", key: "s", input: "https://example.com")
        withTestWindowModel(desks: [emptyDesk]) { windowModel, controller in
            #expect(controller.preferences.setEssentials([essential]))
            windowModel.updateBoardLayout(availableWidth: 1000, spacing: 12)

            windowModel.launchEssential(id: essential.id)
            #expect(controller.focusedBoard?.width == 494)

            controller.storage.state.desks[0].boards.removeAll()
            let pasteboard = NSPasteboard.withUniqueName()
            pasteboard.clearContents()
            pasteboard.setString("https://clipboard.example.com", forType: .string)
            controller.openBoardFromClipboard(pasteboard: pasteboard, preferredWidth: windowModel.defaultBoardWidth)
            #expect(controller.focusedBoard?.width == 494)
        }
    }

    @Test func emptyDeskReceivesFocusedBoardIDWhenAddingBoardInBackground() {
        let firstDesk = desk("First", boards: [board("Main")], focusedBoardID: nil)
        let emptyDesk = desk("Empty")
        let controller = DenController(state: DenState(desks: [firstDesk, emptyDesk], focusedDeskID: firstDesk.id))

        // Open board on emptyDesk without focus
        _ = controller.createBoard(
            urlString: "https://example.com",
            focus: false)
        #expect(controller.state.desks[0].boards.count == 2)

        // Focus empty desk and open in background
        controller.focusDesk(emptyDesk.id)
        #expect(controller.state.desks[1].focusedBoardID == nil)
        _ = controller.createBoard(
            urlString: "https://example.com",
            focus: false)

        #expect(controller.state.desks[1].boards.count == 1)
        #expect(controller.state.desks[1].focusedBoardID == controller.state.desks[1].boards[0].id)
    }

    @Test func updateBoardKeepsCurrentSheetForUnsupportedURL() throws {
        let board = board("Board", url: "https://before.example/")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        var savedState: DenState?
        let controller = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { savedState = $0 })

        controller.updateBoard(
            boardID: board.id,
            url: URL(string: "mailto:user@example.com"),
            title: "Updated title")

        #expect(controller.focusedBoard?.currentSheetURL == URL(string: "https://before.example/"))
        #expect(controller.focusedBoard?.label == "Updated title")
        #expect(savedState == nil)
    }

    @Test func updateBoardDoesNotTriggerSaveWhenOnlyTitleChanges() throws {
        let board = board("Board", url: "https://example.com/")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        let controller = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { _ in saveCount += 1 })

        controller.updateBoard(boardID: board.id, url: nil, title: "New Title")
        #expect(controller.focusedBoard?.label == "New Title")
        #expect(saveCount == 0)

        controller.updateBoard(boardID: board.id, url: URL(string: "https://example.com/updated"), title: nil)
        #expect(controller.focusedBoard?.currentSheetURL == URL(string: "https://example.com/updated"))
        #expect(saveCount == 1)
    }

    @Test func boardFocusMovesAndWrapsAtBothEdges() {
        let boards = [board("A"), board("B"), board("C")]
        withController(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { controller in
            controller.focusNextBoard()
            #expect(controller.focusedDesk?.focusedBoardID == boards[1].id)

            controller.focusPreviousBoard()
            controller.focusPreviousBoard()
            #expect(controller.focusedDesk?.focusedBoardID == boards[2].id)

            controller.focusNextBoard()
            #expect(controller.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test(arguments: [false, true])
    func movingBoardFocusCompletesTutorialNavigationStep(inDenMode: Bool) {
        // Arrange
        let sourceDesk = desk("Desk")
        let controller = DenController(state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))
        withTestWindowModel(controller: controller) { windowModel, _ in
            #expect(controller.openTutorialBoard())
            #expect(controller.openBoard(input: "https://one.example/"))
            #expect(controller.focusedDesk?.boards.count == 2)
            if inDenMode { windowModel.toggleDenMode() }

            // Act
            controller.focusNextBoard()

            // Assert
            #expect(
                controller.focusedDesk?.boards.contains {
                    $0.tutorialCompletedSteps?.contains(.navigateBoards) == true
                } == true)
        }
    }

    @Test(arguments: [false, true])
    func showingKeyboardShortcutsCompletesOptionalTutorialStepOnlyInDenMode(inDenMode: Bool) {
        let controller = DenController(state: .sample)
        withTestWindowModel(controller: controller) { windowModel, _ in
            #expect(controller.openTutorialBoard())
            if inDenMode { windowModel.toggleDenMode() }

            windowModel.showKeyboardShortcuts()

            #expect(windowModel.isKeyboardShortcutsPresented)
            #expect(
                controller.state.desks[0].boards.first?.tutorialCompletedSteps?.contains(.keyboardShortcuts)
                    == inDenMode)
        }
    }

    @Test func focusMovesDoNotSaveWhenThereIsOnlyOneTarget() {
        let board = board("Board")
        let onlyDesk = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        withTestController(
            desks: [onlyDesk],
            onSave: { _ in
                saveCount += 1
                return true
            },
            body: { controller in
                controller.focusNextDesk()
                controller.focusPreviousDesk()
                controller.focusNextBoard()
                controller.focusPreviousBoard()

                #expect(controller.presentedDeskID == onlyDesk.id)
                #expect(controller.focusedDesk?.focusedBoardID == board.id)
                #expect(saveCount == 0)
            })
    }

    @Test func reselectingPresentedDeskKeepsTransientEffectsWithoutSaving() {
        let board = board("Board")
        let onlyDesk = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0

        withTestWindowModel(
            desks: [onlyDesk],
            onSave: { _ in
                saveCount += 1
                return true
            },
            body: { windowModel, controller in
                windowModel.deskFilter.enter()
                windowModel.deskFilter.setQuery("board")
                windowModel.isDenMode = true
                controller.recordNotification(title: "Build", body: "Finished", boardID: board.id)

                controller.focusDesk(onlyDesk.id)

                #expect(!windowModel.deskFilter.isPresented)
                #expect(windowModel.deskFilter.query.isEmpty)
                #expect(!windowModel.isDenMode)
                #expect(controller.unreadNotificationCount == 0)
                #expect(saveCount == 0)
            })
    }

    @Test func boardFocusRecoversWhenNoBoardIsFocused() {
        let boards = [board("A"), board("B"), board("C")]
        let deskState = desk("Desk", boards: boards)
        let controller = DenController(state: DenState(desks: [deskState], focusedDeskID: deskState.id))
        controller.storage.state.desks[0].focusedBoardID = nil
        #expect(controller.focusedDesk?.focusedBoardID == nil)

        controller.focusNextBoard()
        #expect(controller.focusedDesk?.focusedBoardID == boards[0].id)

        controller.storage.state.desks[0].focusedBoardID = nil
        controller.focusPreviousBoard()
        #expect(controller.focusedDesk?.focusedBoardID == boards[2].id)
    }

    @Test func boardBoundaryFocusStaysWithinSourceDesk() {
        let boards = [board("A"), board("B"), board("C")]
        let sourceDesk = desk("Source", boards: boards, focusedBoardID: boards[1].id)
        let otherDesk = desk("Other", boards: [board("Other Board")])
        let controller = DenController(
            state: DenState(desks: [sourceDesk, otherDesk], focusedDeskID: sourceDesk.id))

        controller.focusFirstBoardInDesk(containing: boards[1].id)
        #expect(controller.focusedDesk?.id == sourceDesk.id)
        #expect(controller.focusedDesk?.focusedBoardID == boards[0].id)

        controller.focusLastBoardInDesk(containing: boards[1].id)
        #expect(controller.focusedDesk?.focusedBoardID == boards[2].id)
    }

    @Test func focusingAlreadyFocusedBoardDoesNotSaveAgain() {
        let board = board("Focused")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id)) { _ in
            saveCount += 1
        }

        controller.focusBoard(board.id)

        #expect(saveCount == 0)
    }

    @Test func boardMovementAvailabilityStopsAtDeskEdges() {
        let boards = [board("A"), board("B"), board("C")]
        withController(desks: [desk("Desk", boards: boards)]) { controller in
            #expect(!controller.canMoveBoard(boards[0].id, by: -1))
            #expect(controller.canMoveBoard(boards[0].id, by: 1))
            #expect(controller.canMoveBoard(boards[1].id, by: -1))
            #expect(controller.canMoveBoard(boards[1].id, by: 1))
            #expect(controller.canMoveBoard(boards[2].id, by: -1))
            #expect(!controller.canMoveBoard(boards[2].id, by: 1))
        }
    }

    @Test func reorderingBoardKeepsItFocusedAndStopsAtDeskEdge() {
        let boards = [board("A"), board("B"), board("C")]
        withTestWindowModel(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) {
            windowModel, controller in
            controller.moveFocusedBoardLeft()
            controller.moveFocusedBoardLeft()

            #expect(controller.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id, boards[2].id])
            #expect(controller.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(windowModel.centerFocusedBoardRequest == 1)
        }
    }

    @Test func sideBoardMovesWithTargetAndIsRestoredWithItAfterRemoval() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let after = board("After")
        withController(desks: [desk("Desk", boards: [target, side, after], focusedBoardID: target.id)]) { controller in
            controller.moveFocusedBoardRight()
            #expect(controller.focusedDesk?.boards.map(\.id) == [after.id, target.id, side.id])
            #expect(!controller.canMoveBoard(side.id, by: 1))

            controller.removeBoard(target.id)
            #expect(controller.focusedDesk?.boards.map(\.id) == [after.id])
            #expect(controller.recentlyRemovedBoards.first?.sideBoard?.id == side.id)

            controller.restoreRecentlyRemovedBoard()
            #expect(controller.focusedDesk?.boards.map(\.id) == [after.id, target.id, side.id])
            #expect(controller.focusedDesk?.focusedBoardID == target.id)
        }
    }

    @Test func removingSideBoardLeavesItsTarget() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        withController(desks: [desk("Desk", boards: [target, side], focusedBoardID: side.id)]) { controller in
            controller.removeFocusedBoard()

            #expect(controller.focusedDesk?.boards.map(\.id) == [target.id])
            #expect(controller.recentlyRemovedBoards.first?.board.id == side.id)
            #expect(controller.recentlyRemovedBoards.first?.sideBoard == nil)
        }
    }

    @Test func restoringRemovedSideBoardFollowsTargetToItsCurrentDesk() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let source = desk("Source", boards: [target, side], focusedBoardID: side.id)
        let destination = desk("Destination")
        withController(desks: [source, destination]) { controller in
            controller.removeBoard(side.id)
            controller.focusBoard(target.id)
            controller.moveFocusedBoardToNextDesk()

            controller.restoreRecentlyRemovedBoard()

            #expect(controller.state.desks[0].boards.isEmpty)
            #expect(controller.state.desks[1].boards.map(\.id) == [target.id, side.id])
            #expect(controller.focusedDesk?.focusedBoardID == side.id)
        }
    }

    @Test func movingSideBoardGroupAcrossAnotherGroupKeepsBothAdjacent() {
        let firstTarget = board("First")
        let firstSide = BoardState(width: 390, targetBoardID: firstTarget.id)
        let secondTarget = board("Second")
        let secondSide = BoardState(width: 410, targetBoardID: secondTarget.id)
        let boards = [firstTarget, firstSide, secondTarget, secondSide]
        withController(desks: [desk("Desk", boards: boards, focusedBoardID: firstTarget.id)]) { controller in
            controller.moveFocusedBoardRight()

            #expect(
                controller.focusedDesk?.boards.map(\.id) == [
                    secondTarget.id, secondSide.id, firstTarget.id, firstSide.id,
                ])
            #expect(controller.focusedDesk?.boards[1].sideBoardTargetBoardID == secondTarget.id)
            #expect(controller.focusedDesk?.boards[3].sideBoardTargetBoardID == firstTarget.id)
        }
    }

    @Test func movingInspectionBoardToDeskCarriesTargetGroup() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let source = desk("Source", boards: [target, side], focusedBoardID: side.id)
        let destinationBoard = board("Destination")
        let destination = desk("Destination", boards: [destinationBoard], focusedBoardID: destinationBoard.id)
        withController(desks: [source, destination]) { controller in
            controller.moveFocusedBoardToNextDesk()

            #expect(controller.state.desks[0].boards.isEmpty)
            #expect(controller.state.desks[1].boards.map(\.id) == [destinationBoard.id, target.id, side.id])
            #expect(controller.focusedDesk?.focusedBoardID == side.id)
            #expect(controller.focusedBoard?.width == 390)
        }
    }

    @Test func reorderingBoardWithScrollOffsetSavesOnceAndCenters() {
        let boards = [board("A"), board("B")]
        var source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        source.scrollOffsetX = 180
        var saveCount = 0

        withTestWindowModel(
            desks: [source],
            onSave: { _ in
                saveCount += 1
                return true
            },
            body: { windowModel, controller in
                controller.moveFocusedBoardRight()

                #expect(controller.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id])
                #expect(controller.state.desks[0].scrollOffsetX == nil)
                #expect(windowModel.centerFocusedBoardRequest == 1)
                #expect(saveCount == 1)
            })
    }

    @Test func rapidBoardReorderingKeepsFocusAndRequestsCentering() {
        let boards = [board("A"), board("B"), board("C"), board("D")]
        withTestWindowModel(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) {
            windowModel, controller in
            controller.moveFocusedBoardRight()
            #expect(controller.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(
                controller.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id, boards[2].id, boards[3].id])
            #expect(windowModel.centerFocusedBoardRequest == 1)

            controller.moveFocusedBoardRight()
            #expect(controller.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(
                controller.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id, boards[0].id, boards[3].id])
            #expect(windowModel.centerFocusedBoardRequest == 2)

            controller.moveFocusedBoardRight()
            #expect(controller.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(
                controller.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id, boards[3].id, boards[0].id])
            #expect(windowModel.centerFocusedBoardRequest == 3)
        }
    }

    @Test func boardDragPersistsOnlyItsFinalOrder() {
        let boards = [board("A"), board("B"), board("C")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        var savedStates: [DenState] = []
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id)) {
            savedStates.append($0)
        }

        #expect(controller.beginBoardDrag(boards[0].id))
        controller.previewBoardMove(boards[0].id, to: BoardIndex(rawValue: 2))
        #expect(savedStates.isEmpty)

        controller.finishBoardDrag()
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
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))

        #expect(controller.beginBoardDrag(target.id))
        controller.previewBoardMove(target.id, to: BoardIndex(rawValue: 3))

        #expect(controller.focusedDesk?.boards.map(\.id) == [middle.id, last.id, target.id, side.id])
        controller.finishBoardDrag()
    }

    @Test func boardAndDeskDragAreMutuallyExclusive() {
        let board = board("Board")
        let first = desk("First", boards: [board], focusedBoardID: board.id)
        let second = desk("Second")
        let controller = DenController(
            state: DenState(desks: [first, second], focusedDeskID: first.id))

        #expect(controller.beginDeskDrag(second.id))
        #expect(controller.activeDrag == .desk(second.id))
        #expect(!controller.beginBoardDrag(board.id))
        #expect(!controller.isBoardDragging)
        #expect(controller.isDeskDragging)

        controller.finishDeskDrag()
        #expect(controller.beginBoardDrag(board.id))
        #expect(controller.activeDrag == .board(board.id))
        #expect(!controller.beginDeskDrag(second.id))
        #expect(controller.isBoardDragging)
        #expect(!controller.isDeskDragging)
    }

    @Test func cancelledBoardDragRestoresAndPersistsOriginalOrder() {
        let boards = [board("A"), board("B"), board("C")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        var persistedState: DenState?
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id)) {
            persistedState = $0
        }

        #expect(controller.beginBoardDrag(boards[0].id))
        controller.previewBoardMove(boards[0].id, to: BoardIndex(rawValue: 2))
        controller.restoreBoardOrder(boards.map(\.id), in: source.id)
        controller.finishBoardDrag()

        #expect(controller.focusedDesk?.boards.map(\.id) == boards.map(\.id))
        #expect(persistedState?.desks[0].boards.map(\.id) == boards.map(\.id))
    }

    @Test func movingBoardToDeskPlacesItAfterTargetAndFocusesIt() {
        let moved = board("Moved")
        let targetBoards = [board("Before"), board("Target"), board("After")]
        let source = desk("Source", boards: [moved])
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        withController(desks: [source, target]) { controller in
            controller.moveFocusedBoardToNextDesk()

            #expect(controller.state.desks[0].boards.isEmpty)
            #expect(controller.state.desks[0].focusedBoardID == nil)
            #expect(
                controller.state.desks[1].boards.map(\.id) == [
                    targetBoards[0].id, targetBoards[1].id, moved.id, targetBoards[2].id,
                ])
            #expect(controller.focusedDesk?.id == target.id)
            #expect(controller.focusedDesk?.focusedBoardID == moved.id)
        }
    }

    @Test func removingBoardFocusesPreviousBoard() {
        let boards = [board("A"), board("B"), board("C")]
        withController(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { controller in
            controller.removeFocusedBoard()

            #expect(controller.focusedDesk?.boards.map(\.id) == [boards[0].id, boards[2].id])
            #expect(controller.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(controller.recentlyRemovedBoards.first?.board.id == boards[1].id)
        }
    }

    @Test func removingAndRestoringBoardRestoresSheetNavigationPause() {
        let board = BoardState(
            label: "Paused",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/"),
            sheetNavigationPaused: true)
        let controller = DenController(
            state: DenState(
                desks: [desk("Desk", boards: [board], focusedBoardID: board.id)],
                focusedDeskID: DeskID()))
        controller.removeFocusedBoard()

        #expect(controller.recentlyRemovedBoards.first?.board.sheetNavigationPaused == true)

        controller.restoreRecentlyRemovedBoard()

        #expect(controller.focusedBoard?.sheetNavigationPaused == true)
    }

    @Test func removingFirstBoardFocusesNextBoard() {
        let boards = [board("A"), board("B"), board("C")]
        withController(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { controller in
            controller.removeFocusedBoard()

            #expect(controller.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id])
            #expect(controller.focusedDesk?.focusedBoardID == boards[1].id)
        }
    }

    @Test func removingLastBoardFocusesPreviousBoard() {
        let boards = [board("A"), board("B")]
        withController(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { controller in
            controller.removeFocusedBoard()

            #expect(controller.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test func removingBoardCanPreferNextBoard() {
        let boards = [board("A"), board("B"), board("C")]
        withController(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { controller in
            controller.removeBoard(boards[1].id, focusNext: true)

            #expect(controller.focusedDesk?.boards.map(\.id) == [boards[0].id, boards[2].id])
            #expect(controller.focusedDesk?.focusedBoardID == boards[2].id)
        }

        let lastBoards = [board("A"), board("B")]
        withController(desks: [desk("Desk", boards: lastBoards, focusedBoardID: lastBoards[1].id)]) { controller in
            controller.removeBoard(lastBoards[1].id, focusNext: true)

            #expect(controller.focusedDesk?.focusedBoardID == lastBoards[0].id)
        }
    }

    @Test func removingUnfocusedBoardKeepsFocus() {
        let boards = [board("A"), board("B"), board("C")]
        withController(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { controller in
            controller.removeBoard(boards[0].id)

            #expect(controller.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id])
            #expect(controller.focusedDesk?.focusedBoardID == boards[1].id)
        }
    }

    @Test func removingLastBoardClearsScrollOffsetX() {
        let onlyBoard = board("Only")
        var deskState = desk("Desk", boards: [onlyBoard], focusedBoardID: onlyBoard.id)
        deskState.scrollOffsetX = 250.0
        let controller = DenController(state: DenState(desks: [deskState], focusedDeskID: deskState.id))
        #expect(controller.state.desks[0].scrollOffsetX == 250.0)

        controller.removeBoard(onlyBoard.id)
        #expect(controller.state.desks[0].boards.isEmpty)
        #expect(controller.state.desks[0].scrollOffsetX == nil)
    }

    @Test func removingFocusedBoardClearsScrollOffsetX() {
        let boardA = board("A")
        let boardB = board("B")
        var deskState = desk("Desk", boards: [boardA, boardB], focusedBoardID: boardB.id)
        deskState.scrollOffsetX = 350.0
        let controller = DenController(state: DenState(desks: [deskState], focusedDeskID: deskState.id))
        #expect(controller.state.desks[0].scrollOffsetX == 350.0)

        controller.removeBoard(boardB.id)
        #expect(controller.state.desks[0].focusedBoardID == boardA.id)
        #expect(controller.state.desks[0].scrollOffsetX == nil)
    }

    @Test func duplicatingFocusedBoardClearsScrollOffsetX() {
        let boardA = board("A")
        let boardB = board("B")
        var deskState = desk("Desk", boards: [boardA, boardB], focusedBoardID: boardB.id)
        deskState.scrollOffsetX = 350.0
        let controller = DenController(state: DenState(desks: [deskState], focusedDeskID: deskState.id))
        #expect(controller.state.desks[0].scrollOffsetX == 350.0)

        controller.duplicateFocusedBoard()
        #expect(controller.state.desks[0].boards.count == 3)
        #expect(controller.state.desks[0].scrollOffsetX == nil)
    }

    @Test func insertingFocusedBoardClearsScrollOffsetX() {
        let boardA = board("A")
        var deskState = desk("Desk", boards: [boardA], focusedBoardID: boardA.id)
        deskState.scrollOffsetX = 200.0
        let controller = DenController(state: DenState(desks: [deskState], focusedDeskID: deskState.id))
        #expect(controller.state.desks[0].scrollOffsetX == 200.0)

        _ = controller.createBoard(urlString: "https://example.com", focus: true)
        #expect(controller.state.desks[0].scrollOffsetX == nil)
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
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id)) {
            persistedState = $0
        }

        controller.removeFocusedBoard()
        controller.removeFocusedBoard()
        let persisted = try #require(persistedState)

        #expect(controller.recentlyRemovedBoards.map { $0.board.id } == [boards[1].id, boards[0].id])
        #expect(persisted.desks[0].boards.isEmpty)
        #expect(DenController(state: persisted).recentlyRemovedBoards.isEmpty)
    }

    @Test func removalHistoryKeepsAtMostTenBoardsAndRestoresNewestFirst() {
        let boards = (0..<12).map { board("Board \($0)") }
        withController(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { controller in
            for _ in 0..<11 {
                controller.removeFocusedBoard()
            }

            #expect(controller.recentlyRemovedBoards.count == DenController.maximumRecentlyRemovedBoardCount)
            #expect(
                controller.recentlyRemovedBoards.map { $0.board.id }
                    == Array((1...10).reversed()).map { boards[$0].id })

            for _ in 0..<DenController.maximumRecentlyRemovedBoardCount {
                controller.restoreRecentlyRemovedBoard()
            }

            #expect(controller.recentlyRemovedBoards.isEmpty)
            #expect(controller.focusedDesk?.boards.map(\.id) == Array(1...11).map { boards[$0].id })
        }
    }

    @Test func restorationUsesOriginalDeskIndexAndBoardIdentity() {
        let boards = [board("First"), board("Restored", width: 760), board("Last")]
        let source = desk("Source", boards: boards, focusedBoardID: boards[1].id)
        withController(desks: [source]) { controller in
            controller.removeFocusedBoard()
            controller.restoreRecentlyRemovedBoard()

            #expect(controller.focusedDesk?.boards == boards)
            #expect(controller.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(controller.recentlyRemovedBoards.isEmpty)
        }
    }

    @Test func restorationAtStaleIndexDoesNotSplitExistingSideBoardGroup() throws {
        // Arrange
        let target = board("Target")
        let removed = board("Removed")
        let following = board("Following")
        let source = desk("Desk", boards: [target, removed, following], focusedBoardID: removed.id)
        try withController(desks: [source]) { controller in
            controller.removeBoard(removed.id)
            let sideID = try #require(controller.createInspectionBoard(targetBoardID: target.id))

            // Act
            controller.restoreRecentlyRemovedBoard()

            // Assert
            let boards = try #require(controller.focusedDesk?.boards)
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
        try withController(desks: [source, destination]) { controller in
            controller.removeBoard(removed.id)
            controller.deleteFocusedDesk()

            // Act
            controller.restoreRecentlyRemovedBoard()

            // Assert
            let boards = try #require(controller.focusedDesk?.boards)
            #expect(boards.map(\.id) == [target.id, side.id, removed.id])
            #expect(BoardGroup.containing(target.id, in: boards)?.boards.map(\.id) == [target.id, side.id])
        }
    }

    @Test func restorationCreatesANewBoardRuntime() throws {
        let removed = board("Removed")
        try withController(desks: [desk("Desk", boards: [removed])]) { controller in
            let originalRuntime = controller.webRuntime(for: removed)

            controller.removeFocusedBoard()
            #expect(controller.webRuntimes[removed.id] == nil)

            controller.restoreRecentlyRemovedBoard()
            let restoredBoard = try #require(controller.focusedDesk?.boards.first)
            let restoredRuntime = controller.webRuntime(for: restoredBoard)
            #expect(restoredRuntime !== originalRuntime)
        }
    }

    @Test func removingBoardDisposesItsRuntime() {
        let removed = board("Removed")
        withController(desks: [desk("Desk", boards: [removed])]) { controller in
            let runtime = controller.webRuntime(for: removed)

            controller.removeFocusedBoard()

            #expect(controller.webRuntimes[removed.id] == nil)
            #expect(runtime.webView.navigationDelegate == nil)
            #expect(runtime.webView.uiDelegate == nil)
        }
    }

    @Test func restorationFallsBackRightOfFocusedBoardWhenSourceDeskIsGone() {
        let removed = board("Removed")
        let source = desk("Source", boards: [removed])
        let targetBoards = [board("Before"), board("Focused"), board("After")]
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        withController(desks: [source, target]) { controller in
            controller.removeFocusedBoard()
            controller.deleteFocusedDesk()
            controller.restoreRecentlyRemovedBoard()

            #expect(controller.focusedDesk?.id == target.id)
            #expect(
                controller.focusedDesk?.boards.map(\.id) == [
                    targetBoards[0].id, targetBoards[1].id, removed.id, targetBoards[2].id,
                ])
            #expect(controller.focusedDesk?.focusedBoardID == removed.id)
        }
    }

    @Test func mouseResizeChangesTargetBoardWidthWithinBounds() {
        let boards = [board("First"), board("Second")]
        withController(desks: [desk("Desk", boards: boards)]) { controller in
            controller.resizeBoard(boards[1].id, to: 760)
            #expect(controller.focusedDesk?.boards.map(\.width) == [520, 760])

            controller.resizeBoard(boards[1].id, to: 100)
            #expect(controller.focusedDesk?.boards[1].width == 280)

            controller.resizeBoard(boards[1].id, to: 2_000)
            #expect(controller.focusedDesk?.boards[1].width == 1400)
        }
    }

    @Test func pairedMouseResizeKeepsOuterEdgesFixed() {
        let boards = [board("First", width: 520), board("Second", width: 760)]
        withController(desks: [desk("Desk", boards: boards)]) { controller in
            // Arrange
            let totalWidth = boards.map(\.width).reduce(0, +)

            // Act
            controller.resizeBoardPair(boards[0].id, to: 700)

            // Assert
            #expect(controller.focusedDesk?.boards.map(\.width) == [700, 580])
            #expect(controller.focusedDesk?.boards.map(\.width).reduce(0, +) == totalWidth)
        }
    }

    @Test func pairedMouseResizeRespectsBothBoardMinimumWidths() {
        let boards = [board("First", width: 520), board("Second", width: 760)]
        withController(desks: [desk("Desk", boards: boards)]) { controller in
            // Arrange
            let expectedMinimumPairWidth = BoardState.minimumWidth

            // Act
            controller.resizeBoardPair(boards[0].id, to: 2_000)

            // Assert
            #expect(controller.focusedDesk?.boards.map(\.width) == [1_000, expectedMinimumPairWidth])
        }
    }

    @Test func adjustsEveryBoardInFocusedDeskWithinBounds() {
        let boards = [board("Narrow", width: 280), board("Wide", width: 1_400)]
        let otherBoard = board("Other", width: 760)
        let firstDesk = desk("First", boards: boards, focusedBoardID: boards[0].id)
        let secondDesk = desk("Second", boards: [otherBoard])
        withTestWindowModel(desks: [firstDesk, secondDesk]) { windowModel, controller in
            windowModel.toggleFocusedBoardMaximized()

            windowModel.adjustFocusedDeskBoardWidths(by: -80)
            #expect(controller.focusedDesk?.boards.map(\.width) == [280, 1_320])
            #expect(controller.state.desks[1].boards.map(\.width) == [760])
            #expect(windowModel.maximizedBoardID == nil)

            windowModel.adjustFocusedDeskBoardWidths(by: 160)
            #expect(controller.focusedDesk?.boards.map(\.width) == [440, 1_400])
        }
    }

    @Test func resizesEveryBoardInFocusedDeskToFitCurrentWindow() {
        let firstBoards = [board("First", width: 440), board("Second", width: 760)]
        let otherBoard = board("Other", width: 980)
        let firstDesk = desk("First", boards: firstBoards, focusedBoardID: firstBoards[0].id)
        let secondDesk = desk("Second", boards: [otherBoard])
        var saveCount = 0
        withTestWindowModel(
            desks: [firstDesk, secondDesk],
            onSave: { _ in
                saveCount += 1
                return true
            },
            body: { windowModel, controller in
                windowModel.updateBoardLayout(availableWidth: 1_180, spacing: 10)
                windowModel.toggleFocusedBoardMaximized()
                controller.storage.state.desks[0].scrollOffsetX = 180
                let centerRequest = windowModel.centerFocusedBoardRequest
                let saveCountBeforeResize = saveCount

                #expect(windowModel.resizeFocusedDeskBoards(toFit: 3))
                #expect(
                    controller.focusedDesk?.boards.allSatisfy {
                        abs($0.width - 386.666_666_666_666_7) < 0.001
                    } == true)
                #expect(controller.state.desks[1].boards[0].width == 980)
                #expect(controller.state.desks[0].scrollOffsetX == nil)
                #expect(windowModel.maximizedBoardID == nil)
                #expect(windowModel.centerFocusedBoardRequest == centerRequest + 1)
                #expect(saveCount == saveCountBeforeResize + 1)
            })
    }

    @Test func rejectsBoardFitCountsOutsideCurrentWidth() {
        let boards = [board("First"), board("Second")]
        withTestWindowModel(desks: [desk("Desk", boards: boards)]) { windowModel, controller in
            #expect(windowModel.boardLayoutMetrics == nil)
            #expect(windowModel.boardWidth(toFit: 3) == nil)

            windowModel.updateBoardLayout(availableWidth: 1_080, spacing: 10)

            #expect(
                windowModel.boardLayoutMetrics
                    == BoardLayoutMetrics(availableWidth: 1_080, spacing: 10))
            #expect(windowModel.boardWidth(toFit: 3) != nil)
            #expect(windowModel.boardWidth(toFit: 4) == nil)
            #expect(!windowModel.resizeFocusedDeskBoards(toFit: 4))
            #expect(controller.focusedDesk?.boards.map(\.width) == [520, 520])
        }
    }

    @Test func oneBoardFitUsesFullWindowBeyondManualResizeLimit() {
        withTestWindowModel(desks: [desk("Desk", boards: [board("Wide")])]) { windowModel, controller in
            windowModel.updateBoardLayout(availableWidth: 2_480, spacing: 10)

            #expect(windowModel.resizeFocusedDeskBoards(toFit: 1))
            #expect(controller.focusedDesk?.boards[0].width == 2_480)
        }
    }

    @Test func reloadingFocusedBoardDoesNotChangeDenState() {
        let current = board("Current", url: "https://example.com/path")
        withController(desks: [desk("Desk", boards: [current])]) { controller in
            let stateBeforeReload = controller.state

            controller.reloadFocusedBoard()

            #expect(controller.state == stateBeforeReload)
        }
    }

    @Test func navigatingAnotherBoardFocusesIt() {
        let first = board("First")
        let second = board("Second")
        withController(desks: [desk("Desk", boards: [first, second], focusedBoardID: first.id)]) { controller in
            controller.goBackInBoard(second.id)

            #expect(controller.focusedDesk?.focusedBoardID == second.id)
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

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: BoardID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func popupController(for sourceBoard: BoardState) -> DenController {
        let sourceDesk = desk("Desk", boards: [sourceBoard], focusedBoardID: sourceBoard.id)
        return DenController(
            state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()))
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }

    private func waitForZmxSessionLoad(_ windowModel: DenWindowModel) async {
        await windowModel.zmxSessions.waitForRefresh()
    }

    @Test func openBoardFromClipboardOpensBoardToRightAndExitsDenMode() {
        let source = desk("Desk", boards: [board("First")])
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        #expect(windowModel.isDenMode)
        #expect(controller.focusedDesk?.boards.count == 1)

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/clipboard", forType: .string)

        controller.openBoardFromClipboard(pasteboard: pasteboard, preferredWidth: windowModel.defaultBoardWidth)

        #expect(controller.focusedDesk?.boards.count == 2)
        #expect(controller.focusedBoard?.currentSheetURL == URL(string: "https://example.com/clipboard"))
        #expect(!windowModel.isDenMode)
        #expect(controller.latestFeedback == nil)
    }

    @Test func openBoardFromClipboardShowsWarningFeedbackWhenEmpty() {
        let source = desk("Desk", boards: [board("First")])
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        let initialCount = controller.focusedDesk?.boards.count ?? 0

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()

        controller.openBoardFromClipboard(pasteboard: pasteboard, preferredWidth: windowModel.defaultBoardWidth)

        #expect(controller.focusedDesk?.boards.count == initialCount)
        #expect(controller.latestFeedback?.message == "Clipboard is empty.")
    }

    @Test func openBoardFromClipboardReportsConfigurationFailure() {
        // Arrange
        let source = desk("Desk")
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.setString(":zmx test-session", forType: .string)

        // Act
        controller.openBoardFromClipboard(pasteboard: pasteboard)

        // Assert
        #expect(controller.focusedDesk?.boards.isEmpty == true)
        #expect(controller.latestFeedback?.message == "Set an absolute zmx executable path in Settings > Terminal.")
    }

    @Test func createTerminalBoardAddsBoardToActiveDeskAndFocuses() throws {
        let source = desk("Desk", boards: [board("First")])
        try withTestController(desks: [source]) { controller in
            let dir = FileManager.default.temporaryDirectory.path
            let boardID = try #require(controller.createTerminalBoard(workingDirectory: dir, focus: true))

            let createdBoard = try #require(controller.board(for: boardID))
            #expect(createdBoard.isTerminal)
            #expect(createdBoard.terminalWorkingDirectory == dir)
            #expect(controller.focusedBoard?.id == boardID)
        }
    }

    @Test func terminalTitleChangeDoesNotTriggerSave() throws {
        let dir = FileManager.default.temporaryDirectory.path
        let terminalBoard = BoardState(width: 520, workingDirectory: dir)
        let source = desk("Desk", boards: [terminalBoard], focusedBoardID: terminalBoard.id)
        var saveCount = 0
        let controller = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { _ in saveCount += 1 })

        let runtime = controller.terminalRuntime(for: terminalBoard)
        defer { runtime.dispose() }

        runtime.terminalDidChangeTitle("codex: thinking...")
        #expect(controller.focusedBoard?.label == "codex: thinking...")
        #expect(saveCount == 0)

        runtime.terminalDidChangeWorkingDirectory("/tmp/new-working-dir")
        #expect(controller.focusedBoard?.terminalWorkingDirectory == "/tmp/new-working-dir")
        #expect(saveCount == 1)
    }

    @Test func copyBoardIDCopiesLowercasedUUIDToPasteboardAndShowsFeedback() {
        let firstBoard = board("First")
        let source = desk("Desk", boards: [firstBoard])
        withTestController(desks: [source]) { controller in
            let pasteboard = NSPasteboard.withUniqueName()
            controller.copyBoardID(firstBoard.id, pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == firstBoard.id.rawValue.uuidString.lowercased())
            #expect(controller.latestFeedback?.message == "Copied Board ID.")
            #expect(controller.latestFeedback?.severity == .success)
        }
    }

    @Test func copyBoardIDIgnoresUnknownBoardID() {
        let source = desk("Desk", boards: [board("First")])
        withTestController(desks: [source]) { controller in
            let pasteboard = NSPasteboard.withUniqueName()
            controller.copyBoardID(BoardID(), pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == nil)
            #expect(controller.latestFeedback == nil)
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
            withTestController(desks: [source]) { controller in
                // Act
                controller.copyBoardLocation(pasteboard: pasteboard)

                // Assert
                #expect(pasteboard.string(forType: .string) == expectedValue)
                #expect(controller.latestFeedback?.message == expectedFeedback)
                #expect(controller.latestFeedback?.severity == .success)
            }
        }
    }

    @Test func toggleAnchorBoardSetsAndClearsAnchor() {
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let source = desk("Desk", boards: [firstBoard, secondBoard])
        withTestController(desks: [source]) { controller in
            controller.focusBoard(firstBoard.id)

            controller.toggleAnchorBoard()
            #expect(controller.focusedDesk?.anchorBoardID == firstBoard.id)
            #expect(controller.latestFeedback?.message == "Set Anchor Board")

            controller.toggleAnchorBoard()
            #expect(controller.focusedDesk?.anchorBoardID == nil)
            #expect(controller.latestFeedback?.message == "Cleared Anchor Board")

            controller.focusBoard(secondBoard.id)
            controller.toggleAnchorBoard()
            #expect(controller.focusedDesk?.anchorBoardID == secondBoard.id)
            #expect(controller.latestFeedback?.message == "Set Anchor Board")
        }
    }

    @Test func toggleAnchorBoardForAnotherDeskKeepsCurrentFocus() {
        let focusedBoard = board("Focused")
        let targetBoard = board("Target")
        let focusedDesk = desk("Current", boards: [focusedBoard], focusedBoardID: focusedBoard.id)
        let targetDesk = desk("Overview", boards: [targetBoard])

        withTestController(desks: [focusedDesk, targetDesk]) { controller in
            controller.focusBoard(focusedBoard.id)

            controller.toggleAnchorBoard(targetBoard.id, in: targetDesk.id)
            #expect(controller.state.desks.first(where: { $0.id == targetDesk.id })?.anchorBoardID == targetBoard.id)
            #expect(controller.focusedDesk?.id == focusedDesk.id)
            #expect(controller.focusedBoard?.id == focusedBoard.id)

            controller.toggleAnchorBoard(targetBoard.id, in: targetDesk.id)
            #expect(controller.state.desks.first(where: { $0.id == targetDesk.id })?.anchorBoardID == nil)
            #expect(controller.focusedDesk?.id == focusedDesk.id)
            #expect(controller.focusedBoard?.id == focusedBoard.id)
        }
    }

    @Test func jumpToAnchorBoardTogglesBetweenAnchorAndOrigin() {
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let source = desk("Desk", boards: [firstBoard, secondBoard])
        withTestController(desks: [source]) { controller in
            controller.focusBoard(firstBoard.id)
            controller.toggleAnchorBoard()

            controller.focusBoard(secondBoard.id)
            #expect(controller.focusedBoard?.id == secondBoard.id)

            controller.jumpToAnchorBoard()
            #expect(controller.focusedBoard?.id == firstBoard.id)

            controller.jumpToAnchorBoard()
            #expect(controller.focusedBoard?.id == secondBoard.id)
        }
    }

    @Test func jumpToAnchorBoardShowsWarningWhenNoAnchor() {
        let source = desk("Desk", boards: [board("First")])
        withTestController(desks: [source]) { controller in
            controller.jumpToAnchorBoard()
            #expect(controller.latestFeedback?.message == "No Anchor Board in Desk")
            #expect(controller.latestFeedback?.severity == .warning)
        }
    }

    @Test func removingAnchorBoardClearsAnchor() {
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let source = desk("Desk", boards: [firstBoard, secondBoard])
        withTestController(desks: [source]) { controller in
            controller.focusBoard(firstBoard.id)
            controller.toggleAnchorBoard()
            #expect(controller.focusedDesk?.anchorBoardID == firstBoard.id)
            controller.focusBoard(secondBoard.id)
            controller.jumpToAnchorBoard()
            #expect(controller.anchorJumpOriginBoardIDByDesk[source.id] == secondBoard.id)

            controller.removeBoard(firstBoard.id)
            #expect(controller.focusedDesk?.anchorBoardID == nil)
            #expect(controller.anchorJumpOriginBoardIDByDesk[source.id] == nil)
        }
    }

    @Test func duplicateTerminalBoardResetsTemporaryContextAndFollowsInsertionContract() {
        let first = BoardState(width: 400, workingDirectory: "/tmp")
        let second = board("Second")
        let source = desk("Desk", boards: [first, second], focusedBoardID: first.id)
        withTestWindowModel(desks: [source]) { windowModel, controller in
            windowModel.setTemporaryContext(.openBoard)
            controller.duplicateFocusedBoard()

            #expect(windowModel.temporaryContext == nil)
            #expect(windowModel.isDenMode == false)
            let boards = controller.focusedDesk?.boards ?? []
            #expect(boards.count == 3)
            #expect(boards[0].id == first.id)
            #expect(boards[1].id != first.id)
            #expect(boards[1].terminalWorkingDirectory == "/tmp")
            #expect(boards[2].id == second.id)
            #expect(controller.focusedBoard?.id == boards[1].id)
        }
    }

    @Test func openBoardRecentItemDelegatesToOpenBoardInput() {
        let source = desk("Desk")
        withTestController(desks: [source]) { controller in
            controller.preferences.setZmxPath("/usr/bin/zmx")
            controller.preferences.setZellijPath("/usr/bin/zellij")

            controller.openBoard(recentItem: .zellij(sessionName: "my-session"))
            #expect(controller.focusedBoard?.zellijSessionName == "my-session")
            #expect(controller.recentItems.first == .zellij(sessionName: "my-session"))

            controller.openBoard(recentItem: .zmx(sessionName: "zmx-session"))
            #expect(controller.focusedBoard?.zmxSessionName == "zmx-session")
            #expect(controller.recentItems.first == .zmx(sessionName: "zmx-session"))
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
