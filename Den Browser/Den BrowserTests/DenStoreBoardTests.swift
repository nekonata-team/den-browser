import AppKit
import Foundation
import GhosttyTerminal
import Testing
import WebKit

@testable import Den_Browser

@MainActor
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
        let suiteName = "DenStoreZellijTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setZellijPath("/opt/homebrew/bin/zellij")
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences)

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
        #expect(restoredNamed.content == .zellij(ZellijBoardState(sessionName: "project-a")))

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
        #expect(restoredWelcome.content == .zellij(ZellijBoardState(sessionName: nil)))
    }

    @Test func zellijBoardRequiresConfiguredAbsoluteExecutablePath() {
        let source = desk("Desk")
        let suiteName = "DenStoreZellijMissingPathTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences)

        store.openBoard(input: ":zellij")

        #expect(store.focusedBoard?.isZellij != true)
        #expect(store.openBoardPanelMessage?.contains("absolute Zellij executable path") == true)
        #expect(store.recentItems.isEmpty)
    }

    @Test func zmxBoardsPersistNamedSessionAndOpenSessionsList() async throws {
        let source = desk("Desk")
        let suiteName = "DenStoreZmxTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setZmxPath("/opt/homebrew/bin/zmx")
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences,
            terminalCommandRunner: StubTerminalCommandRunner(responses: [
                ["list"]: TerminalCommandResult(terminationStatus: 0, standardOutput: "")
            ]))

        store.openBoard(input: ":zmx project-a")
        let board = try #require(store.focusedBoard)
        #expect(board.isTerminal)
        #expect(board.isZmx)
        #expect(board.zmxSessionName == "project-a")
        #expect(
            ZmxClient(executablePath: "/opt/homebrew/bin/zmx")
                .launchCommand(sessionName: board.zmxSessionName ?? "")
                == "'/opt/homebrew/bin/zmx' attach 'project-a'"
        )
        let restored = try JSONDecoder().decode(
            BoardState.self,
            from: JSONEncoder().encode(board))
        #expect(
            restored.content
                == .zmx(
                    ZmxBoardState(
                        sessionName: "project-a",
                        workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path)))

        store.openBoard(input: ":zmx")
        await waitForZmxSessionLoad(store)
        #expect(store.focusedDesk?.boards.count == 1)
        #expect(store.isZmxSessionsPresented)
        #expect(store.recentItems.first == .zmx(sessionName: ""))
        #expect(RecentItem.zmx(sessionName: "").displayText == ":zmx")

        store.hideZmxSessions()
        store.openBoard(recentItem: .zmx(sessionName: ""))
        await waitForZmxSessionLoad(store)
        #expect(store.isZmxSessionsPresented)

        store.hideZmxSessions()
        store.showOpenBoardPanel()
        store.openBoard(input: ":zmx")
        await waitForZmxSessionLoad(store)
        store.hideZmxSessions()
        #expect(store.isOpenBoardPanelPresented)
    }

    @Test func zmxSessionsGroupChildrenOpenBoardsAndKillOneSession() async {
        let source = desk("Desk")
        let suiteName = "DenStoreZmxSessionsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setZmxPath("/opt/homebrew/bin/zmx")
        let commandRunner = StubTerminalCommandRunner(
            responses: [
                ["list"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: "name=den\nname=den-vi\tden.root=den\nname=old-root-debug\tden.root=old-root\n"),
                ["kill", "den-vi", "--force"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: ""),
            ])
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences,
            terminalCommandRunner: commandRunner)

        store.showZmxSessions(selectedSessionName: "den-vi")
        await waitForZmxSessionLoad(store)

        #expect(
            store.zmxSessionGroups == [
                ZmxSessionGroup(rootSessionName: "den", isRootActive: true, childSessionNames: ["den-vi"]),
                ZmxSessionGroup(
                    rootSessionName: "old-root",
                    isRootActive: false,
                    childSessionNames: ["old-root-debug"]),
            ])
        #expect(store.zmxSessionSelectedName == "den-vi")
        store.setZmxSessionQuery("vi")
        #expect(
            store.filteredZmxSessionGroups
                == [ZmxSessionGroup(rootSessionName: "den", isRootActive: true, childSessionNames: ["den-vi"])]
        )
        store.clearZmxSessionFilter()

        store.openZmxSession("den-vi")
        #expect(store.focusedBoard?.zmxSessionName == "den-vi")
        #expect(!store.isZmxSessionsPresented)

        store.showZmxSessions()
        await waitForZmxSessionLoad(store)
        store.openZmxSession("den-vi")
        #expect(store.focusedDesk?.boards.count == 1)

        store.showZmxSessions()
        await waitForZmxSessionLoad(store)
        store.killZmxSession("den-vi")
        await waitForZmxSessionLoad(store)
        #expect(store.zmxSessionsMessage == nil)
    }

    @Test func changingWebExtensionHostKeepsTerminalRuntimeAlive() {
        let terminal = BoardState(width: 520, zmxSessionName: "project-a", workingDirectory: "/tmp")
        let source = desk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: SheetNavigationManager(),
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

    @Test func zmxBoardDuplicationCreatesRootedIndependentSessions() throws {
        let sourceBoard = BoardState(
            width: 640,
            zmxSessionName: "den",
            workingDirectory: "/tmp/project")
        let source = desk("Desk", boards: [sourceBoard], focusedBoardID: sourceBoard.id)
        let suiteName = "DenStoreZmxDuplicationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setZmxPath("/usr/bin/zmx")
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences,
            terminalCommandRunner: StubTerminalCommandRunner(
                responses: [
                    ["list", "--short"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "")
                ]))

        store.duplicateFocusedBoardFromFirstSheet()
        let automaticChild = try #require(store.focusedBoard)
        #expect(store.focusedDesk?.boards.count == 2)
        #expect(automaticChild.zmxSessionName == "den-2")
        #expect(automaticChild.zmxRootSessionName == "den")
        #expect(automaticChild.terminalWorkingDirectory == "/tmp/project")
        #expect(store.temporaryContext == nil)

        store.focusBoard(sourceBoard.id)
        store.duplicateFocusedBoard()
        #expect(store.temporaryContext == .zmxDuplication)
        #expect(store.focusedDesk?.boards.count == 2)

        #expect(store.duplicateFocusedZmxBoard(suffix: "vi"))
        let firstChild = try #require(store.focusedBoard)
        #expect(firstChild.zmxSessionName == "den-vi")
        #expect(firstChild.zmxRootSessionName == "den")
        #expect(firstChild.terminalWorkingDirectory == "/tmp/project")
        #expect(store.recentItems.first == .zmx(sessionName: "den-vi"))
        let restoredChild = try JSONDecoder().decode(
            BoardState.self,
            from: JSONEncoder().encode(firstChild))
        #expect(
            restoredChild.content
                == .zmx(
                    ZmxBoardState(
                        sessionName: "den-vi",
                        workingDirectory: "/tmp/project",
                        rootSessionName: "den")))

        store.duplicateFocusedBoard()
        #expect(store.duplicateFocusedZmxBoard(suffix: "nvim"))
        #expect(store.focusedBoard?.zmxSessionName == "den-nvim")
        #expect(store.focusedBoard?.zmxRootSessionName == "den")
        #expect(store.recentItems.first == .zmx(sessionName: "den-nvim"))

        store.focusBoard(firstChild.id)
        store.duplicateFocusedBoard()
        #expect(store.duplicateFocusedZmxBoard(suffix: "vi"))
        #expect(store.focusedBoard?.zmxSessionName == "den-vi-2")
        #expect(store.recentItems.first == .zmx(sessionName: "den-vi-2"))
    }

    @Test func zmxBoardDuplicationUsesTheSourceRootLabel() throws {
        let sourceBoard = BoardState(
            width: 640,
            zmxSessionName: "den-vi",
            workingDirectory: "/tmp/project")
        let source = desk("Desk", boards: [sourceBoard], focusedBoardID: sourceBoard.id)
        let suiteName = "DenStoreZmxRootLabelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setZmxPath("/usr/bin/zmx")
        let commandRunner = StubTerminalCommandRunner(
            responses: [
                ["list", "--short"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: "den-vi\n"),
                ["get", "den-vi", "den.root"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: "den\n"),
            ])
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            sheetNavigation: SheetNavigationManager(),
            preferences: preferences,
            terminalCommandRunner: commandRunner)

        store.duplicateFocusedBoard()
        #expect(store.zmxDuplicationRootSessionName == "den")
        #expect(store.duplicateFocusedZmxBoard(suffix: "nvim"))
        #expect(store.focusedBoard?.zmxSessionName == "den-nvim")
        #expect(store.focusedBoard?.zmxRootSessionName == "den")
    }

    @Test func invalidTerminalInputDoesNotCreateRecentItem() {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        store.openBoard(input: ":terminal /missing/den-browser-\(UUID().uuidString)")

        #expect(store.focusedDesk?.boards.isEmpty == true)
        #expect(store.recentItems.isEmpty)
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
        store.isDenMode = true

        store.terminalRuntime(for: terminal).terminalDidChangeFocus(true)

        #expect(store.isDenMode)
        #expect(store.focusedBoard?.id == terminal.id)
    }

    @Test func terminalLinkCreatesBackgroundBoardWithoutDrawer() throws {
        let terminal = BoardState(width: 520, workingDirectory: "/tmp")
        let source = desk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let url = try #require(URL(string: "https://terminal-link.example/path"))
        defer { store.releaseRuntimes() }

        store.terminalRuntime(for: terminal).terminalDidRequestOpenURL(url.absoluteString, kind: .text)

        #expect(store.focusedDesk?.boards.map(\.currentSheetURL) == [nil, url])
        #expect(store.focusedDesk?.focusedBoardID == terminal.id)
        #expect(store.state.drawerItems.isEmpty)

        store.handleExternalURL(url)

        #expect(store.state.drawerItems.isEmpty)
    }

    @Test func openBoardAcceptsWebHostsAndSearchesInvalidURLs() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        store.addBoard(urlString: "localhost:3000")
        let localURL = try #require(store.focusedDesk?.boards.last?.currentSheetURL)
        #expect(localURL.scheme == "https")
        #expect(localURL.host == "localhost")
        #expect(localURL.port == 3000)

        store.addBoard(urlString: "swift: concurrency")
        let searchURL = try #require(
            store.focusedDesk?.boards.last?.currentSheetURL
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(searchURL.host == "www.google.com")
        #expect(searchURL.queryItems == [URLQueryItem(name: "q", value: "swift: concurrency")])

        store.addBoard(urlString: "https://")
        let invalidURLSearch = try #require(
            store.focusedDesk?.boards.last?.currentSheetURL
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(invalidURLSearch.queryItems == [URLQueryItem(name: "q", value: "https://")])
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

        store.showEditBoardLinkPanel()

        #expect(store.navigateFocusedBoard(urlString: "after.example/path"))
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://after.example/path"))
        #expect(store.focusedBoard?.firstSheetURL == URL(string: "https://before.example/"))
        #expect(store.temporaryContext == nil)
        #expect(!store.isDenMode)
    }

    @Test func newBoardKeepsFirstSheetWhenCurrentSheetChanges() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        store.addBoard(urlString: "https://start.example/")
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

            store.addBoard(urlString: "https://example.com", preferredWidth: width)

            #expect(store.focusedBoard?.width == width)
        }
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
        #expect(savedState == store.state)
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
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.moveFocusedBoardLeft()
            store.moveFocusedBoardLeft()

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(store.centerFocusedBoardRequest == 1)
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

    @Test func restorationCreatesANewBoardRuntime() throws {
        let removed = board("Removed")
        try withStore(desks: [desk("Desk", boards: [removed])]) { store in
            let originalRuntime = store.runtime(for: removed)

            store.removeFocusedBoard()
            #expect(store.runtimes[removed.id] == nil)

            store.restoreRecentlyRemovedBoard()
            let restoredBoard = try #require(store.focusedDesk?.boards.first)
            let restoredRuntime = store.runtime(for: restoredBoard)
            #expect(restoredRuntime !== originalRuntime)
        }
    }

    @Test func removingBoardDisposesItsRuntime() {
        let removed = board("Removed")
        withStore(desks: [desk("Desk", boards: [removed])]) { store in
            let runtime = store.runtime(for: removed)

            store.removeFocusedBoard()

            #expect(store.runtimes[removed.id] == nil)
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

    @Test func adjustsEveryBoardInFocusedDeskWithinBounds() {
        let boards = [board("Narrow", width: 280), board("Wide", width: 1_400)]
        let otherBoard = board("Other", width: 760)
        let firstDesk = desk("First", boards: boards, focusedBoardID: boards[0].id)
        let secondDesk = desk("Second", boards: [otherBoard])
        withStore(desks: [firstDesk, secondDesk]) { store in
            store.toggleFocusedBoardMaximized()

            store.adjustFocusedDeskBoardWidths(by: -80)
            #expect(store.focusedDesk?.boards.map(\.width) == [280, 1_320])
            #expect(store.state.desks[1].boards.map(\.width) == [760])
            #expect(store.maximizedBoardID == nil)

            store.adjustFocusedDeskBoardWidths(by: 160)
            #expect(store.focusedDesk?.boards.map(\.width) == [440, 1_400])
        }
    }

    @Test func resizesEveryBoardInFocusedDeskToFitCurrentWindow() {
        let firstBoards = [board("First", width: 440), board("Second", width: 760)]
        let otherBoard = board("Other", width: 980)
        let firstDesk = desk("First", boards: firstBoards, focusedBoardID: firstBoards[0].id)
        let secondDesk = desk("Second", boards: [otherBoard])
        withStore(desks: [firstDesk, secondDesk]) { store in
            store.updateBoardLayout(availableWidth: 1_180, spacing: 10)
            store.toggleFocusedBoardMaximized()
            let centerRequest = store.centerFocusedBoardRequest

            #expect(store.resizeFocusedDeskBoards(toFit: 3))
            #expect(
                store.focusedDesk?.boards.allSatisfy {
                    abs($0.width - 386.666_666_666_666_7) < 0.001
                } == true)
            #expect(store.state.desks[1].boards[0].width == 980)
            #expect(store.maximizedBoardID == nil)
            #expect(store.centerFocusedBoardRequest == centerRequest + 1)
        }
    }

    @Test func rejectsBoardFitCountsOutsideCurrentWidth() {
        let boards = [board("First"), board("Second")]
        withStore(desks: [desk("Desk", boards: boards)]) { store in
            #expect(store.boardLayoutMetrics == nil)
            #expect(store.boardWidth(toFit: 3) == nil)

            store.updateBoardLayout(availableWidth: 1_080, spacing: 10)

            #expect(
                store.boardLayoutMetrics
                    == BoardLayoutMetrics(availableWidth: 1_080, spacing: 10))
            #expect(store.boardWidth(toFit: 3) != nil)
            #expect(store.boardWidth(toFit: 4) == nil)
            #expect(!store.resizeFocusedDeskBoards(toFit: 4))
            #expect(store.focusedDesk?.boards.map(\.width) == [520, 520])
        }
    }

    @Test func oneBoardFitUsesFullWindowBeyondManualResizeLimit() {
        withStore(desks: [desk("Desk", boards: [board("Wide")])]) { store in
            store.updateBoardLayout(availableWidth: 2_480, spacing: 10)

            #expect(store.resizeFocusedDeskBoards(toFit: 1))
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
    private func withStore(desks: [DeskState], body: (DenStore) throws -> Void) rethrows {
        let store = DenStore(state: DenState(desks: desks, focusedDeskID: desks[0].id))
        try body(store)
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

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }

    private func waitForZmxSessionLoad(_ store: DenStore) async {
        await store.zmxSessionRefreshTask?.value
    }
}

private struct StubTerminalCommandRunner: TerminalCommandRunning, Sendable {
    let responses: [[String]: TerminalCommandResult]

    func run(executablePath: String, arguments: [String]) -> TerminalCommandResult? {
        responses[arguments]
    }
}
