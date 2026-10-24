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
struct NativeBoardTests {
    @Test func terminalInputResolvesHomeRelativeAndAbsoluteDirectories() throws {
        let home = FileManager.default.temporaryDirectory

        #expect(
            try BoardInputResolver.resolveTerminalInput(
                ":terminal", homeDirectory: home, directoryExists: TerminalWorkingDirectory.exists)?.get()
                == home.standardizedFileURL.path)
        #expect(
            try BoardInputResolver.resolveTerminalInput(
                ":terminal .", homeDirectory: home, directoryExists: TerminalWorkingDirectory.exists)?.get()
                == home.standardizedFileURL.path)
        #expect(
            try BoardInputResolver.resolveTerminalInput(
                ":terminal \(home.path)", homeDirectory: URL(fileURLWithPath: "/"),
                directoryExists: TerminalWorkingDirectory.exists)?.get()
                == home.standardizedFileURL.path)
        #expect(
            BoardInputResolver.resolveTerminalInput(
                ":terminally", homeDirectory: home, directoryExists: TerminalWorkingDirectory.exists) == nil)

        let missing = BoardInputResolver.resolveTerminalInput(
            ":terminal missing-\(UUID().uuidString)", homeDirectory: home,
            directoryExists: TerminalWorkingDirectory.exists)
        #expect(throws: TerminalInputError.self) { try missing?.get() }
    }

    @Test func zellijBoardsOpenOptionalSessions() throws {
        let source = desk("Desk")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.configuration.preferences.setZellijPath("/opt/homebrew/bin/zellij")

            session.boardOpening.openBoard(input: ":zellij project-a")
            let named = try #require(session.navigation.focusedBoard)
            #expect(named.isTerminal)
            #expect(named.isZellij)
            #expect(named.zellijSessionName == "project-a")
            session.boardOpening.openBoard(input: ":zellij")
            let welcome = try #require(session.navigation.focusedBoard)
            #expect(welcome.isZellij)
            #expect(welcome.zellijSessionName == nil)
        }
    }

    @Test func zellijBoardRequiresConfiguredAbsoluteExecutablePath() {
        let source = desk("Desk")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.showOpenBoardPanel()
            session.boardOpening.openBoard(input: ":zellij")

            #expect(session.navigation.focusedBoard?.isZellij != true)
            #expect(windowModel.openBoard.message?.contains("absolute Zellij executable path") == true)
            #expect(session.resources.recentItems.isEmpty)
        }
    }

    @Test func zmxBoardsOpenNamedSessionAndSessionsList() async throws {
        let source = desk("Desk")
        let runner = StubTerminalCommandRunner(responses: [
            ["list"]: TerminalCommandResult(terminationStatus: 0, standardOutput: "")
        ])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(
                    defaults: denFixtureDefaults, terminalCommandRunner: runner))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.configuration.preferences.setZmxPath("/opt/homebrew/bin/zmx")

            session.boardOpening.openBoard(input: ":zmx project-a")
            let board = try #require(session.navigation.focusedBoard)
            #expect(board.isTerminal)
            #expect(board.isZmx)
            #expect(board.zmxSessionName == "project-a")
            session.boardOpening.openBoard(input: ":zmx")
            await waitForZmxSessionLoad(windowModel)
            #expect(session.navigation.focusedDesk?.boards.count == 1)
            #expect(windowModel.isZmxSessionsPresented)
            #expect(session.resources.recentItems.first == .zmx(sessionName: "project-a"))
            #expect(RecentItem.zmx(sessionName: "").displayText == ":zmx")

            windowModel.hideZmxSessions()
            session.boardOpening.openBoard(recentItem: .zmx(sessionName: ""))
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
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(
                    defaults: denFixtureDefaults, terminalCommandRunner: commandRunner))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.configuration.preferences.setZmxPath("/opt/homebrew/bin/zmx")

            windowModel.showZmxSessions(selectedSessionName: "den-vi")
            await waitForZmxSessionLoad(windowModel)

            #expect(
                windowModel.zmxSessions.groups == [
                    ZmxSessionGroup(
                        rootSessionName: "den", isRootActive: true, childSessionNames: ["den-vi"]),
                    ZmxSessionGroup(
                        rootSessionName: "old-root",
                        isRootActive: false,
                        childSessionNames: ["old-root-debug"]),
                ])
            #expect(windowModel.zmxSessions.selectedSessionName == "den-vi")
            windowModel.zmxSessions.setQuery("vi")
            #expect(
                windowModel.zmxSessions.filteredGroups
                    == [
                        ZmxSessionGroup(
                            rootSessionName: "den", isRootActive: true, childSessionNames: ["den-vi"])
                    ]
            )
            windowModel.clearZmxSessionFilter()

            windowModel.openZmxSession("den-vi")
            #expect(session.navigation.focusedBoard?.zmxSessionName == "den-vi")
            #expect(session.navigation.focusedBoard?.zmxRootSessionName == "den")
            #expect(session.resources.recentItems.first == .zmx(sessionName: "den-vi"))
            #expect(!windowModel.isZmxSessionsPresented)

            windowModel.showZmxSessions()
            await waitForZmxSessionLoad(windowModel)
            windowModel.openZmxSession("den-vi")
            #expect(session.navigation.focusedDesk?.boards.count == 1)

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
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: [existing], focusedBoardID: existing.id)]))
                ),
                configuration: makeTestBoardRuntimeConfiguration(
                    defaults: denFixtureDefaults, terminalCommandRunner: commandRunner))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.configuration.preferences.setZmxPath("/opt/homebrew/bin/zmx")
            windowModel.showZmxSessions(selectedSessionName: "den-vi")
            await waitForZmxSessionLoad(windowModel)

            // Act
            windowModel.openZmxSession("den-vi")

            // Assert
            #expect(session.navigation.focusedDesk?.boards.count == 1)
            #expect(session.navigation.focusedBoard?.id == existing.id)
            #expect(session.navigation.focusedBoard?.zmxRootSessionName == "den")
        }
    }

    @Test func changingWebExtensionHostKeepsTerminalRuntimeAlive() {
        let terminal = BoardState(width: 520, zmxSessionName: "project-a", workingDirectory: "/tmp")
        let source = desk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)), onSave: nil
            ),
            configuration: makeTestBoardRuntimeConfiguration(
                websiteDataStore: .nonPersistent(), sheetNavigation: makeTestSheetNavigationManager(),
                preferences: AppPreferences(defaults: makeTestDefaults())))
        let runtime = session.runtimes.terminalRuntime(for: terminal)
        let host = MV3WebExtensionHost(
            profileID: ProfileID(),
            websiteDataStore: .nonPersistent(),
            userContentController: WKUserContentController())
        let window = host.window(for: UUID())
        defer {
            session.runtimes.releaseRuntimes()
            host.dispose()
        }

        session.runtimes.updateWebExtensionHost(host, window: window)

        #expect(session.resources.terminalRuntimes[terminal.id] === runtime)
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
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(
                    defaults: denFixtureDefaults, terminalCommandRunner: runner))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.configuration.preferences.setZmxPath("/usr/bin/zmx")

            session.zmx.duplicateFocusedBoardFromFirstSheet()
            await session.zmx.waitForZmxCommand()
            let automaticChild = try #require(session.navigation.focusedBoard)
            #expect(session.navigation.focusedDesk?.boards.count == 2)
            #expect(automaticChild.zmxSessionName == "den-2")
            #expect(automaticChild.zmxRootSessionName == "den")
            #expect(automaticChild.terminalWorkingDirectory == "/tmp/project")
            #expect(windowModel.temporaryContext == nil)
            #expect(session.resources.recentItems.isEmpty)

            session.boardNavigation.focusBoard(sourceBoard.id)
            session.zmx.duplicateFocusedBoard()
            await session.zmx.waitForZmxCommand()
            #expect(windowModel.temporaryContext == .zmxDuplication)
            #expect(session.navigation.focusedDesk?.boards.count == 2)

            session.zmx.duplicateFocusedZmxBoard(suffix: "vi")
            await session.zmx.waitForZmxCommand()
            let firstChild = try #require(session.navigation.focusedBoard)
            #expect(firstChild.zmxSessionName == "den-vi")
            #expect(firstChild.zmxRootSessionName == "den")
            #expect(firstChild.terminalWorkingDirectory == "/tmp/project")

            session.zmx.duplicateFocusedBoard()
            await session.zmx.waitForZmxCommand()
            session.zmx.duplicateFocusedZmxBoard(suffix: "nvim")
            await session.zmx.waitForZmxCommand()
            #expect(session.navigation.focusedBoard?.zmxSessionName == "den-nvim")
            #expect(session.navigation.focusedBoard?.zmxRootSessionName == "den")

            session.boardNavigation.focusBoard(firstChild.id)
            session.zmx.duplicateFocusedBoard()
            await session.zmx.waitForZmxCommand()
            session.zmx.duplicateFocusedZmxBoard(suffix: "vi")
            await session.zmx.waitForZmxCommand()
            #expect(session.navigation.focusedBoard?.zmxSessionName == "den-vi-2")
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
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(
                    defaults: denFixtureDefaults, terminalCommandRunner: commandRunner))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.configuration.preferences.setZmxPath("/usr/bin/zmx")

            session.zmx.duplicateFocusedBoard()
            await session.zmx.waitForZmxCommand()
            #expect(windowModel.zmxDuplicationRootSessionName == "den")
            session.zmx.duplicateFocusedZmxBoard(suffix: "nvim")
            await session.zmx.waitForZmxCommand()
            #expect(session.navigation.focusedBoard?.zmxSessionName == "den-nvim")
            #expect(session.navigation.focusedBoard?.zmxRootSessionName == "den")
        }
    }

    @Test(arguments: [false, true])
    func zmxSideBoardCreatesIndependentSessionInTheSameRoot(_ focus: Bool) async throws {
        // Arrange
        let primary = BoardState(
            width: 640, zmxSessionName: "project-editor", workingDirectory: "/tmp/project",
            rootSessionName: "old-root")
        let occupied = BoardState(width: 520, zmxSessionName: "project-3")
        let source = desk("Desk", boards: [primary, occupied], focusedBoardID: primary.id)
        let runner = StubTerminalCommandRunner(responses: [
            ["list", "--short"]: TerminalCommandResult(
                terminationStatus: 0, standardOutput: "project-editor\nproject-2\n"),
            ["get", "project-editor", "den.root"]: TerminalCommandResult(
                terminationStatus: 0, standardOutput: "project\n"),
        ])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(
                    defaults: denFixtureDefaults, terminalCommandRunner: runner))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let session = denWindowSession

            session.configuration.preferences.setZmxPath("/usr/bin/zmx")

            // Act
            session.sideBoards.createTerminalSideBoard(targetBoardID: primary.id, focus: focus)
            await session.zmx.waitForZmxCommand()

            // Assert
            let boards = try #require(session.navigation.focusedDesk?.boards)
            let side = try #require(boards.first { $0.sideBoardTargetBoardID == primary.id })
            let sessionName = try #require(side.zmxSessionName)
            #expect(boards.count == 3)
            #expect(boards[1].id == side.id)
            #expect(sessionName.hasPrefix("project-"))
            #expect(!["project-editor", "project-2", "project-3"].contains(sessionName))
            #expect(side.zmxRootSessionName == "project")
            #expect(side.terminalWorkingDirectory == "/tmp/project")
            #expect(session.navigation.focusedBoard?.id == (focus ? side.id : primary.id))
            #expect(session.resources.recentItems.isEmpty)
        }
    }

    @Test func zmxSideBoardDoesNotCreateBoardAfterItsTargetIsRemoved() async {
        // Arrange
        let primary = BoardState(width: 640, zmxSessionName: "project")
        let source = desk("Desk", boards: [primary], focusedBoardID: primary.id)
        let runner = StubTerminalCommandRunner(responses: [
            ["list", "--short"]: TerminalCommandResult(terminationStatus: 0, standardOutput: "")
        ])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(
                    defaults: denFixtureDefaults, terminalCommandRunner: runner))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let session = denWindowSession

            session.configuration.preferences.setZmxPath("/usr/bin/zmx")

            // Act
            session.sideBoards.createTerminalSideBoard(targetBoardID: primary.id)
            session.boardRemoval.removeFocusedBoard()
            await session.zmx.waitForZmxCommand()

            // Assert
            #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
        }
    }

    @Test func zmxSideBoardDoesNotCreateShellWhenSessionLookupFails() async {
        // Arrange
        let primary = BoardState(width: 640, zmxSessionName: "project")
        let source = desk("Desk", boards: [primary], focusedBoardID: primary.id)
        let runner = StubTerminalCommandRunner(responses: [
            ["list", "--short"]: TerminalCommandResult(
                terminationStatus: 1, standardOutput: "", standardError: "Session lookup failed")
        ])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(
                    defaults: denFixtureDefaults, terminalCommandRunner: runner))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let session = denWindowSession

            session.configuration.preferences.setZmxPath("/usr/bin/zmx")

            // Act
            session.sideBoards.createTerminalSideBoard(targetBoardID: primary.id)
            await session.zmx.waitForZmxCommand()

            // Assert
            #expect(session.navigation.focusedDesk?.boards == [primary])
        }
    }

    @Test func invalidTerminalInputDoesNotCreateRecentItem() {
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        session.boardOpening.openBoard(input: ":terminal /missing/den-browser-\(UUID().uuidString)")

        #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
        #expect(session.resources.recentItems.isEmpty)
    }

    @Test func popupBoardKeepsItsOpenerRequestAndUsesTheProvidedWebView() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let session = popupSession(for: sourceBoard)
        defer { session.runtimes.releaseRuntimes() }

        let popupURL = try #require(URL(string: "https://login.example/authorize"))
        let backgroundPopup = RuntimeWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // Act
        #expect(
            session.boardOpening.createPopupBoard(
                backgroundPopup,
                requestedURL: popupURL,
                fromBoardID: sourceBoard.id,
                modifierFlags: .command))
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
        let session = popupSession(for: sourceBoard)
        defer { session.runtimes.releaseRuntimes() }
        let popup = RuntimeWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // Act
        #expect(
            session.boardOpening.createPopupBoard(
                popup,
                requestedURL: nil,
                fromBoardID: sourceBoard.id,
                modifierFlags: [.command, .shift]))

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
        let session = popupSession(for: sourceBoard)
        defer { session.runtimes.releaseRuntimes() }
        let popup = RuntimeWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // Act
        #expect(
            session.boardOpening.createPopupBoard(
                popup,
                requestedURL: nil,
                fromBoardID: sourceBoard.id,
                modifierFlags: []))

        // Assert
        let focusedBoard = try #require(session.navigation.focusedBoard)
        #expect(focusedBoard.id != sourceBoard.id)
        #expect(session.resources.webRuntimes[focusedBoard.id]?.webView === popup)
    }

    @Test func closingPopupWebViewRemovesItsBoard() throws {
        // Arrange
        let sourceBoard = BoardState(label: "Source", width: 520, currentSheetURL: nil)
        let session = popupSession(for: sourceBoard)
        defer { session.runtimes.releaseRuntimes() }
        let popup = RuntimeWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        #expect(
            session.boardOpening.createPopupBoard(
                popup,
                requestedURL: nil,
                fromBoardID: sourceBoard.id,
                modifierFlags: []))
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
        let session = popupSession(for: sourceBoard)
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
            in: sourceRuntime.webView)
        sourceRuntime.webView.navigationDelegate = sourceRuntime

        // Act
        _ = try await sourceRuntime.webView.evaluateJavaScript(
            "window.open('about:blank', '_blank'); true")
        let popupBoard = try #require(session.resources.state.desks[0].boards.first { $0.id != sourceBoard.id })
        let popupRuntime = try #require(session.resources.webRuntimes[popupBoard.id])
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
        let session = popupSession(for: sourceBoard)
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
            in: sourceRuntime.webView)
        sourceRuntime.webView.navigationDelegate = sourceRuntime

        // Act
        try await SheetInteraction.waitForFunction(
            expression: "document.title === 'Opened'",
            in: sourceRuntime.webView,
            timeout: 5)

        // Assert
        #expect(session.resources.state.desks[0].boards.count == 2)
        #expect(session.resources.state.desks[0].boards[1].id != sourceBoard.id)
    }

    @Test func terminalBoardsCreateDuplicateRemoveAndRestoreWithRecentItems() throws {
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path

        session.boardOpening.openBoard(input: ":terminal \(directory)", preferredWidth: 640)

        let original = try #require(session.navigation.focusedBoard)
        #expect(original.isTerminal)
        #expect(original.terminalWorkingDirectory == directory)
        #expect(original.width == 640)
        #expect(session.resources.recentItems == [.terminal(workingDirectory: directory)])

        session.zmx.duplicateFocusedBoard()
        let duplicate = try #require(session.navigation.focusedBoard)
        #expect(duplicate.id != original.id)
        #expect(duplicate.terminalWorkingDirectory == directory)

        session.boardRemoval.removeFocusedBoard()
        session.boardRemoval.restoreRecentlyRemovedBoard()
        #expect(session.navigation.focusedBoard?.id == duplicate.id)
        #expect(session.navigation.focusedBoard?.terminalWorkingDirectory == directory)
    }

    @Test func terminalFocusNotificationDoesNotExitDenMode() {
        let terminal = BoardState(width: 520, workingDirectory: "/tmp")
        let source = desk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        session.runtimes.terminalRuntime(for: terminal).terminalDidChangeFocus(true)

        #expect(windowModel.isDenMode)
        #expect(session.navigation.focusedBoard?.id == terminal.id)
    }

    @Test func boardLinkFocusIntentDoesNotConsumeNewerIntent() {
        let firstBoard = BoardState(label: "First", width: 520, currentSheetURL: nil)
        let secondBoard = BoardState(label: "Second", width: 520, currentSheetURL: nil)
        let source = desk("Desk", boards: [firstBoard, secondBoard], focusedBoardID: firstBoard.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

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
        let desk = desk("Desk", boards: [source], focusedBoardID: source.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.boardNavigation.prepareBoardLinkFocus(source.id)
            #expect(
                session.boardOpening.createBoard(
                    urlString: "https://focused.example", afterBoardID: source.id) != nil)

            #expect(windowModel.pendingBoardLinkFocus == nil)
            #expect(session.navigation.focusedBoard?.currentSheetURL?.host == "focused.example")
        }
    }

    @Test func inspectionBoardLinksToWebBoardAndReusesIt() throws {
        let target = BoardState(label: "Target", width: 520, currentSheetURL: URL(string: "https://example.com"))
        let sourceDesk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        let inspectionID = try #require(session.sideBoards.createInspectionBoard(targetBoardID: target.id))
        let inspection = try #require(session.resources.state.board(for: inspectionID))

        #expect(session.resources.state.desks[0].boards.map(\.id) == [target.id, inspectionID])
        #expect(session.navigation.focusedBoard?.id == inspectionID)
        #expect(inspection.isInspection)
        #expect(!inspection.isWeb)
        #expect(!inspection.isTerminal)
        #expect(inspection.isSideBoard)
        #expect(inspection.sideBoardTargetBoardID == target.id)
        #expect(try JSONDecoder().decode(BoardState.self, from: JSONEncoder().encode(inspection)) == inspection)
        #expect(session.sideBoards.createInspectionBoard(targetBoardID: target.id) == inspectionID)
        #expect(session.resources.state.desks[0].boards.count == 2)
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
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        // Act
        if fromFirstSheet {
            session.zmx.duplicateFocusedBoardFromFirstSheet()
        } else {
            session.zmx.duplicateFocusedBoard()
        }

        // Assert
        #expect(session.resources.state.desks[0].boards.map(\.id) == [target.id, side.id])
        #expect(session.navigation.focusedBoard?.id == side.id)
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
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        // Act
        let insertedID = try #require(session.boardOpening.createBoard(urlString: "https://new.example"))

        // Assert
        #expect(session.resources.state.desks[0].boards.map(\.id) == [target.id, side.id, insertedID, following.id])
    }

    @Test(arguments: [BoardState.minimumWidth, BuiltInDeskPreset.boardWidth, BoardState.maximumWidth])
    func inspectionBoardStartsAtCompactWidthRegardlessOfTargetWidth(targetWidth: Double) throws {
        // Arrange
        let target = BoardState(
            label: "Target", width: targetWidth, currentSheetURL: URL(string: "https://example.com"))
        let sourceDesk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        // Act
        let inspectionID = try #require(session.sideBoards.createInspectionBoard(targetBoardID: target.id))
        let inspection = try #require(session.resources.state.board(for: inspectionID))

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
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            #expect(
                session.boardOpening.createBoard(
                    urlString: "https://background.example",
                    afterBoardID: source.id,
                    focus: false) != nil)
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
        let desk = desk("Desk", boards: [source, other], focusedBoardID: source.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            #expect(
                session.boardOpening.createBoard(
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
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.boardRemoval.removeBoard(left.id, origin: .cli)

            let intent = try #require(windowModel.pendingBoardRemoval)
            #expect(intent.origin == .cli)
            #expect(session.navigation.focusedBoard?.id == focused.id)
        }
    }

    @Test func terminalLinkCreatesFocusedBoardWithoutDrawer() throws {
        // Arrange
        let terminal = BoardState(width: 520, workingDirectory: "/tmp")
        let source = desk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
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
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState())),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

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
                    == URL(string: "https://example.com/path?q=literal"))
            #expect(session.boardOpening.navigateFocusedBoard(urlString: query))
            #expect(session.navigation.focusedBoard?.currentSheetURL?.host == "duckduckgo.com")
        }
    }

    @Test func openBoardAcceptsWebHostsAndRejectsInvalidURLs() throws {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState())),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            _ = session.boardOpening.createBoard(urlString: "localhost:3000")
            let localURL = try #require(session.navigation.focusedDesk?.boards.last?.currentSheetURL)
            #expect(localURL.scheme == "https")
            #expect(localURL.host == "localhost")
            #expect(localURL.port == 3000)

            _ = session.boardOpening.createBoard(urlString: "swift: concurrency")
            let searchURL = try #require(
                session.navigation.focusedDesk?.boards.last?.currentSheetURL
                    .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
            #expect(searchURL.host == "www.google.com")
            #expect(searchURL.queryItems == [URLQueryItem(name: "q", value: "swift: concurrency")])

            let boardCount = try #require(session.navigation.focusedDesk?.boards.count)
            #expect(session.boardOpening.createBoard(urlString: "https://") == nil)
            #expect(session.boardOpening.createBoard(urlString: "ftp://example.com") == nil)
            #expect(session.navigation.focusedDesk?.boards.count == boardCount)
        }
    }

    @Test func localFileURLParticipatesInBoardRecentDrawerAndPresetWorkflows() throws {
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let fileURL = try #require(URL(string: "file:///tmp/Den%20Browser/index.html#notes"))

        session.boardOpening.openBoard(input: fileURL.absoluteString)

        #expect(session.navigation.focusedBoard?.currentSheetURL == fileURL)
        #expect(session.navigation.focusedBoard?.firstSheetURL == fileURL)
        #expect(session.resources.recentItems.first == .url(fileURL))

        session.drawer.keepFocusedSheetInDrawer()
        #expect(session.resources.state.drawerItems.first?.url == fileURL)

        #expect(session.presets.saveFocusedDeskAsPreset(label: "Local Files") == .created)
        #expect(session.resources.deskPresets.first?.boards.first?.initialSheetURL == fileURL)
    }

    @Test func editingFocusedBoardLinkReplacesCurrentSheet() throws {
        let board = board("Board", url: "https://before.example/")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
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
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        _ = session.boardOpening.createBoard(urlString: "https://start.example/")
        let firstSheetURL = try #require(session.navigation.focusedBoard?.firstSheetURL)

        #expect(session.boardOpening.navigateFocusedBoard(urlString: "https://later.example/"))
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://later.example/"))
        #expect(session.navigation.focusedBoard?.firstSheetURL == firstSheetURL)
    }

    @Test func openBoardCanInsertAfterSpecifiedBoard() {
        let boards = [board("First"), board("Focused"), board("Last")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[1].id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        session.boardOpening.openBoard(input: "example.com", afterBoardID: boards.last?.id)

        #expect(session.navigation.focusedDesk?.boards.map(\.label) == ["First", "Focused", "Last", "example.com"])
        #expect(session.navigation.focusedDesk?.focusedBoardID == session.navigation.focusedDesk?.boards.last?.id)
    }

    @Test func newBoardKeepsPreferredWidthBeyondManualResizeLimit() {
        for width in [BoardState.minimumWidth, BoardState.maximumWidth, 2_480] {
            let source = desk("Desk")
            let session = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
                configuration: makeTestBoardRuntimeConfiguration())

            _ = session.boardOpening.createBoard(urlString: "https://example.com", preferredWidth: width)

            #expect(session.navigation.focusedBoard?.width == width)
        }
    }

    @Test func newBoardInheritsFocusedWidthWhenPreferredWidthIsUnset() {
        let source = board("Source", width: 760)
        let focusedDesk = desk("Focused", boards: [source], focusedBoardID: source.id)
        let focusedSession = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [focusedDesk], focusedDeskID: focusedDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        _ = focusedSession.boardOpening.createBoard(urlString: "https://example.com")
        #expect(focusedSession.navigation.focusedBoard?.width == 760)
    }

    @Test func emptyDeskUsesTwoBoardFitWidthAsDefault() {
        let emptyDesk = desk("Empty")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [emptyDesk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            #expect(session.boardOpening.inheritedBoardWidth == BuiltInDeskPreset.boardWidth)

            windowModel.updateBoardLayout(availableWidth: 1376, spacing: 12)
            #expect(windowModel.defaultBoardWidth == 682)

            _ = session.boardOpening.createBoard(
                urlString: "https://example.com", preferredWidth: windowModel.defaultBoardWidth)
            #expect(session.navigation.focusedBoard?.width == 682)
        }
    }

    @Test func emptyDeskAppliesFitWidthToClipboardAndEssential() {
        let emptyDesk = desk("Empty")
        let essential = Essential(name: "Search", key: "s", input: "https://example.com")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [emptyDesk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            #expect(session.configuration.preferences.setEssentials([essential]))
            windowModel.updateBoardLayout(availableWidth: 1000, spacing: 12)

            windowModel.launchEssential(id: essential.id)
            #expect(session.navigation.focusedBoard?.width == 494)

            session.resources.state.desks[0].boards.removeAll()
            let pasteboard = NSPasteboard.withUniqueName()
            pasteboard.clearContents()
            pasteboard.setString("https://clipboard.example.com", forType: .string)
            session.input.openBoardFromClipboard(
                pasteboard: pasteboard, preferredWidth: windowModel.defaultBoardWidth)
            #expect(session.navigation.focusedBoard?.width == 494)
        }
    }

    @Test func emptyDeskReceivesFocusedBoardIDWhenAddingBoardInBackground() {
        let firstDesk = desk("First", boards: [board("Main")], focusedBoardID: nil)
        let emptyDesk = desk("Empty")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [firstDesk, emptyDesk], focusedDeskID: firstDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        // Open board on emptyDesk without focus
        _ = session.boardOpening.createBoard(
            urlString: "https://example.com",
            focus: false)
        #expect(session.resources.state.desks[0].boards.count == 2)

        // Focus empty desk and open in background
        session.boardNavigation.focusDesk(emptyDesk.id)
        #expect(session.resources.state.desks[1].focusedBoardID == nil)
        _ = session.boardOpening.createBoard(
            urlString: "https://example.com",
            focus: false)

        #expect(session.resources.state.desks[1].boards.count == 1)
        #expect(session.resources.state.desks[1].focusedBoardID == session.resources.state.desks[1].boards[0].id)
    }

    @Test func updateBoardKeepsCurrentSheetForUnsupportedURL() throws {
        let board = board("Board", url: "https://before.example/")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())

        session.runtimes.updateBoard(
            boardID: board.id,
            url: URL(string: "mailto:user@example.com"),
            title: "Updated title")

        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://before.example/"))
        #expect(session.navigation.focusedBoard?.label == "Updated title")
        #expect(savedState == nil)
    }

    @Test func updateBoardDoesNotTriggerSaveWhenOnlyTitleChanges() throws {
        let board = board("Board", url: "https://example.com/")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { _ in saveCount += 1 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())

        session.runtimes.updateBoard(boardID: board.id, url: nil, title: "New Title")
        #expect(session.navigation.focusedBoard?.label == "New Title")
        #expect(saveCount == 0)

        session.runtimes.updateBoard(boardID: board.id, url: URL(string: "https://example.com/updated"), title: nil)
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://example.com/updated"))
        #expect(saveCount == 1)
    }

    @Test func boardFocusMovesAndWrapsAtBothEdges() {
        let boards = [board("A"), board("B"), board("C")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardNavigation.focusNextBoard()
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[1].id)

            session.boardNavigation.focusPreviousBoard()
            session.boardNavigation.focusPreviousBoard()
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[2].id)

            session.boardNavigation.focusNextBoard()
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test(arguments: [false, true])
    func movingBoardFocusCompletesTutorialNavigationStep(inDenMode: Bool) {
        // Arrange
        let sourceDesk = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        do {
            let denWindowSession = session
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model

            #expect(session.boardOpening.openTutorialBoard())
            #expect(session.boardOpening.openBoard(input: "https://one.example/"))
            #expect(session.navigation.focusedDesk?.boards.count == 2)
            if inDenMode { windowModel.toggleDenMode() }

            // Act
            session.boardNavigation.focusNextBoard()

            // Assert
            #expect(
                session.navigation.focusedDesk?.boards.contains {
                    $0.tutorialCompletedSteps?.contains(.navigateBoards) == true
                } == true)
        }
    }

    @Test(arguments: [false, true])
    func showingKeyboardShortcutsCompletesOptionalTutorialStepOnlyInDenMode(inDenMode: Bool) {
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration())
        do {
            let denWindowSession = session
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model

            #expect(session.boardOpening.openTutorialBoard())
            if inDenMode { windowModel.toggleDenMode() }

            windowModel.showKeyboardShortcuts()

            #expect(windowModel.isKeyboardShortcutsPresented)
            #expect(
                session.resources.state.desks[0].boards.first?.tutorialCompletedSteps?.contains(
                    .keyboardShortcuts)
                    == inDenMode)
        }
    }

    @Test func focusMovesDoNotSaveWhenThereIsOnlyOneTarget() {
        let board = board("Board")
        let onlyDesk = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [onlyDesk])),
                    onSave: { _ in
                        saveCount += 1
                        return true
                    }), configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardNavigation.focusNextDesk()
            session.boardNavigation.focusPreviousDesk()
            session.boardNavigation.focusNextBoard()
            session.boardNavigation.focusPreviousBoard()

            #expect(session.navigation.presentedDeskID == onlyDesk.id)
            #expect(session.navigation.focusedDesk?.focusedBoardID == board.id)
            #expect(saveCount == 0)
        }
    }

    @Test func reselectingPresentedDeskKeepsTransientEffectsWithoutSaving() {
        let board = board("Board")
        let onlyDesk = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0

        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [onlyDesk])),
                    onSave: { _ in
                        saveCount += 1
                        return true
                    }), configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.deskFilter.enter()
            windowModel.deskFilter.setQuery("board")
            windowModel.isDenMode = true
            session.notifications.recordNotification(title: "Build", body: "Finished", boardID: board.id)

            session.boardNavigation.focusDesk(onlyDesk.id)

            #expect(!windowModel.deskFilter.isPresented)
            #expect(windowModel.deskFilter.query.isEmpty)
            #expect(!windowModel.isDenMode)
            #expect(session.resources.notificationOperations.unreadCount() == 0)
            #expect(saveCount == 0)
        }
    }

    @Test func boardFocusRecoversWhenNoBoardIsFocused() {
        let boards = [board("A"), board("B"), board("C")]
        let deskState = desk("Desk", boards: boards)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        session.resources.state.desks[0].focusedBoardID = nil
        #expect(session.navigation.focusedDesk?.focusedBoardID == nil)

        session.boardNavigation.focusNextBoard()
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)

        session.resources.state.desks[0].focusedBoardID = nil
        session.boardNavigation.focusPreviousBoard()
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[2].id)
    }

    @Test func boardBoundaryFocusStaysWithinSourceDesk() {
        let boards = [board("A"), board("B"), board("C")]
        let sourceDesk = desk("Source", boards: boards, focusedBoardID: boards[1].id)
        let otherDesk = desk("Other", boards: [board("Other Board")])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [sourceDesk, otherDesk], focusedDeskID: sourceDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        session.boardNavigation.focusFirstBoardInDesk(containing: boards[1].id)
        #expect(session.navigation.focusedDesk?.id == sourceDesk.id)
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)

        session.boardNavigation.focusLastBoardInDesk(containing: boards[1].id)
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[2].id)
    }

    @Test func focusingAlreadyFocusedBoardDoesNotSaveAgain() {
        let board = board("Focused")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: { _ in
                    saveCount += 1
                    return true
                }),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.boardNavigation.focusBoard(board.id)

        #expect(saveCount == 0)
    }

    @Test func boardMovementAvailabilityStopsAtDeskEdges() {
        let boards = [board("A"), board("B"), board("C")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk("Desk", boards: boards)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            #expect(!session.resources.boardMovement.canMove(boards[0].id, by: -1))
            #expect(session.resources.boardMovement.canMove(boards[0].id, by: 1))
            #expect(session.resources.boardMovement.canMove(boards[1].id, by: -1))
            #expect(session.resources.boardMovement.canMove(boards[1].id, by: 1))
            #expect(session.resources.boardMovement.canMove(boards[2].id, by: -1))
            #expect(!session.resources.boardMovement.canMove(boards[2].id, by: 1))
        }
    }

    @Test func reorderingBoardKeepsItFocusedAndStopsAtDeskEdge() {
        let boards = [board("A"), board("B"), board("C")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.boardNavigation.moveFocusedBoardLeft()
            session.boardNavigation.moveFocusedBoardLeft()

            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [
                    boards[1].id, boards[0].id, boards[2].id,
                ])
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(windowModel.centerFocusedBoardRequest == 1)
        }
    }

    @Test func reorderingBoardToTargetIndexUpdatesAndPersistsOrder() {
        let boards = [board("A"), board("B"), board("C")]
        var persistedState: DenState?
        let deskState = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id)),
                onSave: {
                    persistedState = $0
                    return true
                }),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.resources.boardMovement.preview(
            boards[0].id, to: BoardIndex(rawValue: 2), in: session.navigation.presentedDeskID)
        session.resources.save()

        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id, boards[0].id])
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
        #expect(persistedState?.desks[0].boards.map(\.id) == [boards[1].id, boards[2].id, boards[0].id])
    }

    @Test func sideBoardMovesWithTargetAndIsRestoredWithItAfterRemoval() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let after = board("After")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [
                            desk("Desk", boards: [target, side, after], focusedBoardID: target.id)
                        ]))), configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardNavigation.moveFocusedBoardRight()
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [after.id, target.id, side.id])
            #expect(!session.resources.boardMovement.canMove(side.id, by: 1))

            session.boardRemoval.removeBoard(target.id)
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [after.id])
            #expect(session.resources.recentlyRemovedBoards.first?.sideBoard?.id == side.id)

            session.boardRemoval.restoreRecentlyRemovedBoard()
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [after.id, target.id, side.id])
            #expect(session.navigation.focusedDesk?.focusedBoardID == target.id)
        }
    }

    @Test func removingSideBoardLeavesItsTarget() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: [target, side], focusedBoardID: side.id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardRemoval.removeFocusedBoard()

            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [target.id])
            #expect(session.resources.recentlyRemovedBoards.first?.board.id == side.id)
            #expect(session.resources.recentlyRemovedBoards.first?.sideBoard == nil)
        }
    }

    @Test func restoringRemovedSideBoardFollowsTargetToItsCurrentDesk() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let source = desk("Source", boards: [target, side], focusedBoardID: side.id)
        let destination = desk("Destination")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, destination]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardRemoval.removeBoard(side.id)
            session.boardNavigation.focusBoard(target.id)
            session.boardNavigation.moveFocusedBoardToNextDesk()

            session.boardRemoval.restoreRecentlyRemovedBoard()

            #expect(session.resources.state.desks[0].boards.isEmpty)
            #expect(session.resources.state.desks[1].boards.map(\.id) == [target.id, side.id])
            #expect(session.navigation.focusedDesk?.focusedBoardID == side.id)
        }
    }

    @Test func movingSideBoardGroupAcrossAnotherGroupKeepsBothAdjacent() {
        let firstTarget = board("First")
        let firstSide = BoardState(width: 390, targetBoardID: firstTarget.id)
        let secondTarget = board("Second")
        let secondSide = BoardState(width: 410, targetBoardID: secondTarget.id)
        let boards = [firstTarget, firstSide, secondTarget, secondSide]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards, focusedBoardID: firstTarget.id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardNavigation.moveFocusedBoardRight()

            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [
                    secondTarget.id, secondSide.id, firstTarget.id, firstSide.id,
                ])
            #expect(session.navigation.focusedDesk?.boards[1].sideBoardTargetBoardID == secondTarget.id)
            #expect(session.navigation.focusedDesk?.boards[3].sideBoardTargetBoardID == firstTarget.id)
        }
    }

    @Test func movingInspectionBoardToDeskCarriesTargetGroup() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let source = desk("Source", boards: [target, side], focusedBoardID: side.id)
        let destinationBoard = board("Destination")
        let destination = desk("Destination", boards: [destinationBoard], focusedBoardID: destinationBoard.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, destination]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardNavigation.moveFocusedBoardToNextDesk()

            #expect(session.resources.state.desks[0].boards.isEmpty)
            #expect(
                session.resources.state.desks[1].boards.map(\.id) == [
                    destinationBoard.id, target.id, side.id,
                ])
            #expect(session.navigation.focusedDesk?.focusedBoardID == side.id)
            #expect(session.navigation.focusedBoard?.width == 390)
        }
    }

    @Test func reorderingBoardWithScrollOffsetSavesOnceAndCenters() {
        let boards = [board("A"), board("B")]
        var source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        source.scrollOffsetX = 180
        var saveCount = 0

        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source])),
                    onSave: { _ in
                        saveCount += 1
                        return true
                    }), configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.boardNavigation.moveFocusedBoardRight()

            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id])
            #expect(session.resources.state.desks[0].scrollOffsetX == nil)
            #expect(windowModel.centerFocusedBoardRequest == 1)
            #expect(saveCount == 1)
        }
    }

    @Test func rapidBoardReorderingKeepsFocusAndRequestsCentering() {
        let boards = [board("A"), board("B"), board("C"), board("D")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.boardNavigation.moveFocusedBoardRight()
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [
                    boards[1].id, boards[0].id, boards[2].id, boards[3].id,
                ])
            #expect(windowModel.centerFocusedBoardRequest == 1)

            session.boardNavigation.moveFocusedBoardRight()
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [
                    boards[1].id, boards[2].id, boards[0].id, boards[3].id,
                ])
            #expect(windowModel.centerFocusedBoardRequest == 2)

            session.boardNavigation.moveFocusedBoardRight()
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [
                    boards[1].id, boards[2].id, boards[3].id, boards[0].id,
                ])
            #expect(windowModel.centerFocusedBoardRequest == 3)
        }
    }

    @Test func boardDragPersistsOnlyItsFinalOrder() {
        let boards = [board("A"), board("B"), board("C")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        var savedStates: [DenState] = []
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: {
                    savedStates.append($0)
                    return true
                }),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        #expect(session.boardNavigation.beginBoardDrag(boards[0].id))
        session.resources.boardMovement.preview(
            boards[0].id, to: BoardIndex(rawValue: 2), in: session.navigation.presentedDeskID)
        #expect(savedStates.isEmpty)

        session.resources.boardMovement.finishDrag()
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
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        #expect(session.boardNavigation.beginBoardDrag(target.id))
        session.resources.boardMovement.preview(
            target.id, to: BoardIndex(rawValue: 3), in: session.navigation.presentedDeskID)

        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [middle.id, last.id, target.id, side.id])
        session.resources.boardMovement.finishDrag()
    }

    @Test func boardAndDeskDragAreMutuallyExclusive() {
        let board = board("Board")
        let first = desk("First", boards: [board], focusedBoardID: board.id)
        let second = desk("Second")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [first, second], focusedDeskID: first.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        #expect(session.resources.deskMovement.beginDrag(second.id))
        #expect(session.resources.activeDrag == .desk(second.id))
        #expect(!session.boardNavigation.beginBoardDrag(board.id))
        #expect(!session.context.isBoardDragging)
        #expect(session.context.isDeskDragging)

        session.resources.deskMovement.finishDrag()
        #expect(session.boardNavigation.beginBoardDrag(board.id))
        #expect(session.resources.activeDrag == .board(board.id))
        #expect(!session.resources.deskMovement.beginDrag(second.id))
        #expect(session.context.isBoardDragging)
        #expect(!session.context.isDeskDragging)
    }

    @Test func cancelledBoardDragRestoresAndPersistsOriginalOrder() {
        let boards = [board("A"), board("B"), board("C")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        var persistedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: {
                    persistedState = $0
                    return true
                }),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        #expect(session.boardNavigation.beginBoardDrag(boards[0].id))
        session.resources.boardMovement.preview(
            boards[0].id, to: BoardIndex(rawValue: 2), in: session.navigation.presentedDeskID)
        session.resources.boardMovement.restoreOrder(boards.map(\.id), in: source.id)
        session.resources.boardMovement.finishDrag()

        #expect(session.navigation.focusedDesk?.boards.map(\.id) == boards.map(\.id))
        #expect(persistedState?.desks[0].boards.map(\.id) == boards.map(\.id))
    }

    @Test func movingBoardToDeskPlacesItAfterTargetAndFocusesIt() {
        let moved = board("Moved")
        let targetBoards = [board("Before"), board("Target"), board("After")]
        let source = desk("Source", boards: [moved])
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, target]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardNavigation.moveFocusedBoardToNextDesk()

            #expect(session.resources.state.desks[0].boards.isEmpty)
            #expect(session.resources.state.desks[0].focusedBoardID == nil)
            #expect(
                session.resources.state.desks[1].boards.map(\.id) == [
                    targetBoards[0].id, targetBoards[1].id, moved.id, targetBoards[2].id,
                ])
            #expect(session.navigation.focusedDesk?.id == target.id)
            #expect(session.navigation.focusedDesk?.focusedBoardID == moved.id)
        }
    }

    @Test func removingBoardFocusesPreviousBoard() {
        let boards = [board("A"), board("B"), board("C")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardRemoval.removeFocusedBoard()

            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [boards[0].id, boards[2].id])
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(session.resources.recentlyRemovedBoards.first?.board.id == boards[1].id)
        }
    }

    @Test func removingAndRestoringBoardRestoresSheetNavigationPause() {
        let board = BoardState(
            label: "Paused",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/"),
            sheetNavigationPaused: true)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [desk("Desk", boards: [board], focusedBoardID: board.id)],
                        focusedDeskID: DeskID()))), configuration: makeTestBoardRuntimeConfiguration())
        session.boardRemoval.removeFocusedBoard()

        #expect(session.resources.recentlyRemovedBoards.first?.board.sheetNavigationPaused == true)

        session.boardRemoval.restoreRecentlyRemovedBoard()

        #expect(session.navigation.focusedBoard?.sheetNavigationPaused == true)
    }

    @Test func removingFirstBoardFocusesNextBoard() {
        let boards = [board("A"), board("B"), board("C")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardRemoval.removeFocusedBoard()

            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id])
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[1].id)
        }
    }

    @Test func removingLastBoardFocusesPreviousBoard() {
        let boards = [board("A"), board("B")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardRemoval.removeFocusedBoard()

            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test func removingBoardCanPreferNextBoard() {
        let boards = [board("A"), board("B"), board("C")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardRemoval.removeBoard(boards[1].id, focusNext: true)

            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [boards[0].id, boards[2].id])
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[2].id)
        }

        let lastBoards = [board("A"), board("B")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: lastBoards, focusedBoardID: lastBoards[1].id)])
                    )), configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardRemoval.removeBoard(lastBoards[1].id, focusNext: true)

            #expect(session.navigation.focusedDesk?.focusedBoardID == lastBoards[0].id)
        }
    }

    @Test func removingUnfocusedBoardKeepsFocus() {
        let boards = [board("A"), board("B"), board("C")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardRemoval.removeBoard(boards[0].id)

            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id])
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[1].id)
        }
    }

    @Test func removingLastBoardClearsScrollOffsetX() {
        let onlyBoard = board("Only")
        var deskState = desk("Desk", boards: [onlyBoard], focusedBoardID: onlyBoard.id)
        deskState.scrollOffsetX = 250.0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        #expect(session.resources.state.desks[0].scrollOffsetX == 250.0)

        session.boardRemoval.removeBoard(onlyBoard.id)
        #expect(session.resources.state.desks[0].boards.isEmpty)
        #expect(session.resources.state.desks[0].scrollOffsetX == nil)
    }

    @Test func removingFocusedBoardClearsScrollOffsetX() {
        let boardA = board("A")
        let boardB = board("B")
        var deskState = desk("Desk", boards: [boardA, boardB], focusedBoardID: boardB.id)
        deskState.scrollOffsetX = 350.0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        #expect(session.resources.state.desks[0].scrollOffsetX == 350.0)

        session.boardRemoval.removeBoard(boardB.id)
        #expect(session.resources.state.desks[0].focusedBoardID == boardA.id)
        #expect(session.resources.state.desks[0].scrollOffsetX == nil)
    }

    @Test func duplicatingFocusedBoardClearsScrollOffsetX() {
        let boardA = board("A")
        let boardB = board("B")
        var deskState = desk("Desk", boards: [boardA, boardB], focusedBoardID: boardB.id)
        deskState.scrollOffsetX = 350.0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        #expect(session.resources.state.desks[0].scrollOffsetX == 350.0)

        session.zmx.duplicateFocusedBoard()
        #expect(session.resources.state.desks[0].boards.count == 3)
        #expect(session.resources.state.desks[0].scrollOffsetX == nil)
    }

    @Test func insertingFocusedBoardClearsScrollOffsetX() {
        let boardA = board("A")
        var deskState = desk("Desk", boards: [boardA], focusedBoardID: boardA.id)
        deskState.scrollOffsetX = 200.0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        #expect(session.resources.state.desks[0].scrollOffsetX == 200.0)

        _ = session.boardOpening.createBoard(urlString: "https://example.com", focus: true)
        #expect(session.resources.state.desks[0].scrollOffsetX == nil)
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
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: {
                    persistedState = $0
                    return true
                }),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.boardRemoval.removeFocusedBoard()
        session.boardRemoval.removeFocusedBoard()
        let persisted = try #require(persistedState)

        #expect(session.resources.recentlyRemovedBoards.map { $0.board.id } == [boards[1].id, boards[0].id])
        #expect(persisted.desks[0].boards.isEmpty)
        #expect(
            DenProfileResources(state: DenStateNormalization.normalize(persisted)).recentlyRemovedBoards.isEmpty)
    }

    @Test func removalHistoryKeepsAtMostTenBoardsAndRestoresNewestFirst() {
        let boards = (0..<12).map { board("Board \($0)") }
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            for _ in 0..<11 {
                session.boardRemoval.removeFocusedBoard()
            }

            #expect(session.resources.recentlyRemovedBoards.count == BoardRemoval.maximumHistoryCount)
            #expect(
                session.resources.recentlyRemovedBoards.map { $0.board.id }
                    == Array((1...10).reversed()).map { boards[$0].id })

            for _ in 0..<BoardRemoval.maximumHistoryCount {
                session.boardRemoval.restoreRecentlyRemovedBoard()
            }

            #expect(session.resources.recentlyRemovedBoards.isEmpty)
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == Array(1...11).map { boards[$0].id })
        }
    }

    @Test func restorationUsesOriginalDeskIndexAndBoardIdentity() {
        let boards = [board("First"), board("Restored", width: 760), board("Last")]
        let source = desk("Source", boards: boards, focusedBoardID: boards[1].id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardRemoval.removeFocusedBoard()
            session.boardRemoval.restoreRecentlyRemovedBoard()

            #expect(session.navigation.focusedDesk?.boards == boards)
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(session.resources.recentlyRemovedBoards.isEmpty)
        }
    }

    @Test func restorationAtStaleIndexDoesNotSplitExistingSideBoardGroup() throws {
        // Arrange
        let target = board("Target")
        let removed = board("Removed")
        let following = board("Following")
        let source = desk("Desk", boards: [target, removed, following], focusedBoardID: removed.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardRemoval.removeBoard(removed.id)
            let sideID = try #require(session.sideBoards.createInspectionBoard(targetBoardID: target.id))

            // Act
            session.boardRemoval.restoreRecentlyRemovedBoard()

            // Assert
            let boards = try #require(session.navigation.focusedDesk?.boards)
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
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, destination]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardRemoval.removeBoard(removed.id)
            session.desks.deleteFocusedDesk()

            // Act
            session.boardRemoval.restoreRecentlyRemovedBoard()

            // Assert
            let boards = try #require(session.navigation.focusedDesk?.boards)
            #expect(boards.map(\.id) == [target.id, side.id, removed.id])
            #expect(BoardGroup.containing(target.id, in: boards)?.boards.map(\.id) == [target.id, side.id])
        }
    }

    @Test func restorationCreatesANewBoardRuntime() throws {
        let removed = board("Removed")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: [removed])]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            let originalRuntime = session.runtimes.webRuntime(for: removed)

            session.boardRemoval.removeFocusedBoard()
            #expect(session.resources.webRuntimes[removed.id] == nil)

            session.boardRemoval.restoreRecentlyRemovedBoard()
            let restoredBoard = try #require(session.navigation.focusedDesk?.boards.first)
            let restoredRuntime = session.runtimes.webRuntime(for: restoredBoard)
            #expect(restoredRuntime !== originalRuntime)
        }
    }

    @Test func removingBoardDisposesItsRuntime() {
        let removed = board("Removed")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: [removed])]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            let runtime = session.runtimes.webRuntime(for: removed)

            session.boardRemoval.removeFocusedBoard()

            #expect(session.resources.webRuntimes[removed.id] == nil)
            #expect(runtime.webView.navigationDelegate == nil)
            #expect(runtime.webView.uiDelegate == nil)
        }
    }

    @Test func restorationFallsBackRightOfFocusedBoardWhenSourceDeskIsGone() {
        let removed = board("Removed")
        let source = desk("Source", boards: [removed])
        let targetBoards = [board("Before"), board("Focused"), board("After")]
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, target]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardRemoval.removeFocusedBoard()
            session.desks.deleteFocusedDesk()
            session.boardRemoval.restoreRecentlyRemovedBoard()

            #expect(session.navigation.focusedDesk?.id == target.id)
            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [
                    targetBoards[0].id, targetBoards[1].id, removed.id, targetBoards[2].id,
                ])
            #expect(session.navigation.focusedDesk?.focusedBoardID == removed.id)
        }
    }

    @Test func adjustsEveryBoardInFocusedDeskWithinBounds() {
        let primary = board("Narrow", width: 280)
        let side = BoardState(label: "Inspection Board", width: 360, targetBoardID: primary.id)
        let boards = [primary, side, board("Wide", width: 1_400)]
        let otherBoard = board("Other", width: 760)
        let firstDesk = desk("First", boards: boards, focusedBoardID: boards[0].id)
        let secondDesk = desk("Second", boards: [otherBoard])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [firstDesk, secondDesk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.toggleFocusedBoardMaximized()

            windowModel.adjustFocusedDeskBoardWidths(by: -80)
            #expect(session.navigation.focusedDesk?.boards.map(\.width) == [280, 360, 1_320])
            #expect(session.resources.state.desks[1].boards.map(\.width) == [760])
            #expect(windowModel.maximizedBoardID == nil)

            windowModel.adjustFocusedDeskBoardWidths(by: 160)
            #expect(session.navigation.focusedDesk?.boards.map(\.width) == [440, 360, 1_400])
        }
    }

    @Test func resizesEveryBoardInFocusedDeskToFitCurrentWindow() {
        let first = board("First", width: 440)
        let side = BoardState(label: "Inspection Board", width: 360, targetBoardID: first.id)
        let firstBoards = [first, side, board("Second", width: 760)]
        let otherBoard = board("Other", width: 980)
        let firstDesk = desk("First", boards: firstBoards, focusedBoardID: firstBoards[0].id)
        let secondDesk = desk("Second", boards: [otherBoard])
        var saveCount = 0
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [firstDesk, secondDesk])),
                    onSave: { _ in
                        saveCount += 1
                        return true
                    }), configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.updateBoardLayout(availableWidth: 1_180, spacing: 10)
            windowModel.toggleFocusedBoardMaximized()
            session.resources.state.desks[0].scrollOffsetX = 180
            let centerRequest = windowModel.centerFocusedBoardRequest
            let saveCountBeforeResize = saveCount

            #expect(windowModel.resizeFocusedDeskBoards(toFit: 3))
            #expect(
                session.navigation.focusedDesk?.boards.filter { !$0.isSideBoard }.allSatisfy {
                    abs($0.width - 386.666_666_666_666_7) < 0.001
                } == true)
            #expect(session.navigation.focusedDesk?.boards[1].width == 360)
            #expect(session.resources.state.desks[1].boards[0].width == 980)
            #expect(session.resources.state.desks[0].scrollOffsetX == nil)
            #expect(windowModel.maximizedBoardID == nil)
            #expect(windowModel.centerFocusedBoardRequest == centerRequest + 1)
            #expect(saveCount == saveCountBeforeResize + 1)
        }
    }

    @Test func rejectsBoardFitCountsOutsideCurrentWidth() {
        let boards = [board("First"), board("Second")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk("Desk", boards: boards)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            #expect(windowModel.boardLayoutMetrics == nil)
            #expect(windowModel.boardWidth(toFit: 3) == nil)

            windowModel.updateBoardLayout(availableWidth: 1_080, spacing: 10)

            #expect(
                windowModel.boardLayoutMetrics
                    == BoardLayoutMetrics(availableWidth: 1_080, spacing: 10))
            #expect(windowModel.boardWidth(toFit: 3) != nil)
            #expect(windowModel.boardWidth(toFit: 4) == nil)
            #expect(!windowModel.resizeFocusedDeskBoards(toFit: 4))
            #expect(session.navigation.focusedDesk?.boards.map(\.width) == [520, 520])
        }
    }

    @Test func oneBoardFitUsesFullWindowBeyondManualResizeLimit() {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: [board("Wide")])]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.updateBoardLayout(availableWidth: 2_480, spacing: 10)

            #expect(windowModel.resizeFocusedDeskBoards(toFit: 1))
            #expect(session.navigation.focusedDesk?.boards[0].width == 2_480)
        }
    }

    @Test func reloadingFocusedBoardDoesNotChangeDenState() {
        let current = board("Current", url: "https://example.com/path")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: [current])]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            let stateBeforeReload = session.resources.state

            session.boardOpening.reloadFocusedBoard()

            #expect(session.resources.state == stateBeforeReload)
        }
    }

    @Test func navigatingAnotherBoardFocusesIt() {
        let first = board("First")
        let second = board("Second")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: [first, second], focusedBoardID: first.id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardOpening.goBackInBoard(second.id)

            #expect(session.navigation.focusedDesk?.focusedBoardID == second.id)
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

    private func popupSession(for sourceBoard: BoardState) -> ProfileWindowSession {
        let sourceDesk = desk("Desk", boards: [sourceBoard], focusedBoardID: sourceBoard.id)
        return ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration(
                websiteDataStore: .nonPersistent(), sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
                preferences: AppPreferences(defaults: makeTestDefaults())))
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }

    private func waitForZmxSessionLoad(_ windowModel: DenWindowModel) async {
        await windowModel.zmxSessions.waitForRefresh()
    }

    @Test func openBoardFromClipboardOpensBoardToRightAndExitsDenMode() {
        let source = desk("Desk", boards: [board("First")])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
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
        let source = desk("Desk", boards: [board("First")])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
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
        let source = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.setString(":zmx test-session", forType: .string)

        // Act
        session.input.openBoardFromClipboard(pasteboard: pasteboard)

        // Assert
        #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
        #expect(session.feedback.latest?.message == "Set an absolute zmx executable path in Settings > Terminal.")
    }

    @Test func createTerminalBoardAddsBoardToActiveDeskAndFocuses() throws {
        let source = desk("Desk", boards: [board("First")])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            let dir = FileManager.default.temporaryDirectory.path
            let boardID = try #require(
                session.boardOpening.createTerminalBoard(workingDirectory: dir, focus: true))

            let createdBoard = try #require(session.resources.state.board(for: boardID))
            #expect(createdBoard.isTerminal)
            #expect(createdBoard.terminalWorkingDirectory == dir)
            #expect(session.navigation.focusedBoard?.id == boardID)
        }
    }

    @Test func terminalTitleChangeDoesNotTriggerSave() throws {
        let dir = FileManager.default.temporaryDirectory.path
        let terminalBoard = BoardState(width: 520, workingDirectory: dir)
        let source = desk("Desk", boards: [terminalBoard], focusedBoardID: terminalBoard.id)
        var saveCount = 0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { _ in saveCount += 1 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())

        let runtime = session.runtimes.terminalRuntime(for: terminalBoard)
        defer { runtime.dispose() }

        runtime.terminalDidChangeTitle("codex: thinking...")
        #expect(session.navigation.focusedBoard?.label == "codex: thinking...")
        #expect(saveCount == 0)

        runtime.terminalDidChangeWorkingDirectory("/tmp/new-working-dir")
        #expect(session.navigation.focusedBoard?.terminalWorkingDirectory == "/tmp/new-working-dir")
        #expect(saveCount == 1)
    }

    @Test func copyBoardIDCopiesLowercasedUUIDToPasteboardAndShowsFeedback() {
        let firstBoard = board("First")
        let source = desk("Desk", boards: [firstBoard])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            let pasteboard = NSPasteboard.withUniqueName()
            session.boardNavigation.copyBoardID(firstBoard.id, pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == firstBoard.id.rawValue.uuidString.lowercased())
            #expect(session.feedback.latest?.message == "Copied Board ID.")
            #expect(session.feedback.latest?.severity == .success)
        }
    }

    @Test func copyBoardIDIgnoresUnknownBoardID() {
        let source = desk("Desk", boards: [board("First")])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            let pasteboard = NSPasteboard.withUniqueName()
            session.boardNavigation.copyBoardID(BoardID(), pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == nil)
            #expect(session.feedback.latest == nil)
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
            do {
                let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
                let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
                defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
                let denWindowSession = ProfileWindowSession(
                    resources: DenProfileResources(
                        state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                    configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
                let session = denWindowSession

                // Act
                session.boardNavigation.copyBoardLocation(pasteboard: pasteboard)

                // Assert
                #expect(pasteboard.string(forType: .string) == expectedValue)
                #expect(session.feedback.latest?.message == expectedFeedback)
                #expect(session.feedback.latest?.severity == .success)
            }
        }
    }

    @Test func toggleAnchorBoardSetsAndClearsAnchor() {
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let source = desk("Desk", boards: [firstBoard, secondBoard])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardNavigation.focusBoard(firstBoard.id)

            session.boardNavigation.toggleAnchorBoard()
            #expect(session.navigation.focusedDesk?.anchorBoardID == firstBoard.id)
            #expect(session.feedback.latest?.message == "Set Anchor Board")

            session.boardNavigation.toggleAnchorBoard()
            #expect(session.navigation.focusedDesk?.anchorBoardID == nil)
            #expect(session.feedback.latest?.message == "Cleared Anchor Board")

            session.boardNavigation.focusBoard(secondBoard.id)
            session.boardNavigation.toggleAnchorBoard()
            #expect(session.navigation.focusedDesk?.anchorBoardID == secondBoard.id)
            #expect(session.feedback.latest?.message == "Set Anchor Board")
        }
    }

    @Test func toggleAnchorBoardForAnotherDeskKeepsCurrentFocus() {
        let focusedBoard = board("Focused")
        let targetBoard = board("Target")
        let focusedDesk = desk("Current", boards: [focusedBoard], focusedBoardID: focusedBoard.id)
        let targetDesk = desk("Overview", boards: [targetBoard])

        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [focusedDesk, targetDesk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardNavigation.focusBoard(focusedBoard.id)

            session.boardNavigation.toggleAnchorBoard(targetBoard.id, in: targetDesk.id)
            #expect(
                session.resources.state.desks.first(where: { $0.id == targetDesk.id })?.anchorBoardID
                    == targetBoard.id)
            #expect(session.navigation.focusedDesk?.id == focusedDesk.id)
            #expect(session.navigation.focusedBoard?.id == focusedBoard.id)

            session.boardNavigation.toggleAnchorBoard(targetBoard.id, in: targetDesk.id)
            #expect(
                session.resources.state.desks.first(where: { $0.id == targetDesk.id })?.anchorBoardID == nil)
            #expect(session.navigation.focusedDesk?.id == focusedDesk.id)
            #expect(session.navigation.focusedBoard?.id == focusedBoard.id)
        }
    }

    @Test func jumpToAnchorBoardTogglesBetweenAnchorAndOrigin() {
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let source = desk("Desk", boards: [firstBoard, secondBoard])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardNavigation.focusBoard(firstBoard.id)
            session.boardNavigation.toggleAnchorBoard()

            session.boardNavigation.focusBoard(secondBoard.id)
            #expect(session.navigation.focusedBoard?.id == secondBoard.id)

            session.boardNavigation.jumpToAnchorBoard()
            #expect(session.navigation.focusedBoard?.id == firstBoard.id)

            session.boardNavigation.jumpToAnchorBoard()
            #expect(session.navigation.focusedBoard?.id == secondBoard.id)
        }
    }

    @Test func jumpToAnchorBoardShowsWarningWhenNoAnchor() {
        let source = desk("Desk", boards: [board("First")])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardNavigation.jumpToAnchorBoard()
            #expect(session.feedback.latest?.message == "No Anchor Board in Desk")
            #expect(session.feedback.latest?.severity == .warning)
        }
    }

    @Test func removingAnchorBoardClearsAnchor() {
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let source = desk("Desk", boards: [firstBoard, secondBoard])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardNavigation.focusBoard(firstBoard.id)
            session.boardNavigation.toggleAnchorBoard()
            #expect(session.navigation.focusedDesk?.anchorBoardID == firstBoard.id)
            session.boardNavigation.focusBoard(secondBoard.id)
            session.boardNavigation.jumpToAnchorBoard()
            #expect(session.navigation.anchorJumpOriginBoardIDByDesk[source.id] == secondBoard.id)

            session.boardRemoval.removeBoard(firstBoard.id)
            #expect(session.navigation.focusedDesk?.anchorBoardID == nil)
            #expect(session.navigation.anchorJumpOriginBoardIDByDesk[source.id] == nil)
        }
    }

    @Test func duplicateTerminalBoardResetsTemporaryContextAndFollowsInsertionContract() {
        let first = BoardState(width: 400, workingDirectory: "/tmp")
        let second = board("Second")
        let source = desk("Desk", boards: [first, second], focusedBoardID: first.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.setTemporaryContext(.openBoard)
            session.zmx.duplicateFocusedBoard()

            #expect(windowModel.temporaryContext == nil)
            #expect(windowModel.isDenMode == false)
            let boards = session.navigation.focusedDesk?.boards ?? []
            #expect(boards.count == 3)
            #expect(boards[0].id == first.id)
            #expect(boards[1].id != first.id)
            #expect(boards[1].terminalWorkingDirectory == "/tmp")
            #expect(boards[2].id == second.id)
            #expect(session.navigation.focusedBoard?.id == boards[1].id)
        }
    }

    @Test func openBoardRecentItemDelegatesToOpenBoardInput() {
        let source = desk("Desk")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

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
