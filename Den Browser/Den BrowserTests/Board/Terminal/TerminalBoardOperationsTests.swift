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
struct TerminalBoardOperationsTests {
    @Test func zellijBoardsOpenOptionalSessions() throws {
        let source = makeTestDesk("Desk")
        try withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session in
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
        let source = makeTestDesk("Desk")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session, windowModel in
            windowModel.showOpenBoardPanel()
            session.boardOpening.openBoard(input: ":zellij")

            #expect(session.navigation.focusedBoard?.isZellij != true)
            #expect(windowModel.openBoard.message?.contains("absolute Zellij executable path") == true)
            #expect(session.resources.recentItems.isEmpty)
        }
    }

    @Test func changingWebExtensionHostKeepsTerminalRuntimeAlive() {
        let terminal = BoardState(width: 520, zmxSessionName: "project-a", workingDirectory: "/tmp")
        let source = makeTestDesk("Desk", boards: [terminal], focusedBoardID: terminal.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: nil
            ),
            configuration: makeTestBoardRuntimeConfiguration(
                websiteDataStore: .nonPersistent(),
                sheetNavigation: makeTestSheetNavigationManager(),
                preferences: AppPreferences(defaults: makeTestDefaults())
            )
        )
        let runtime = session.runtimes.terminalRuntime(for: terminal)
        let host = MV3WebExtensionHost(
            profileID: ProfileID(),
            websiteDataStore: .nonPersistent(),
            userContentController: WKUserContentController()
        )
        let window = host.window(for: UUID())
        defer {
            session.runtimes.releaseRuntimes()
            host.dispose()
        }

        session.runtimes.updateWebExtensionHost(host, window: window)

        #expect(session.resources.terminalRuntimes[terminal.id] === runtime)
    }

    @Test func invalidTerminalInputDoesNotCreateRecentItem() {
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.boardOpening.openBoard(input: ":terminal /missing/den-browser-\(UUID().uuidString)")

        #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
        #expect(session.resources.recentItems.isEmpty)
    }

    @Test func terminalBoardsCreateDuplicateRemoveAndRestoreWithRecentItems() throws {
        let source = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
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
        let source = makeTestDesk("Desk", boards: [terminal], focusedBoardID: terminal.id)
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

        session.runtimes.terminalRuntime(for: terminal).terminalDidChangeFocus(true)

        #expect(windowModel.isDenMode)
        #expect(session.navigation.focusedBoard?.id == terminal.id)
    }

    @Test func createTerminalBoardAddsBoardToActiveDeskAndFocuses() throws {
        let source = makeTestDesk("Desk", boards: [makeTestBoard("First")])
        try withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session in
            let dir = FileManager.default.temporaryDirectory.path
            let boardID = try #require(
                session.boardOpening.createTerminalBoard(workingDirectory: dir, focus: true)
            )

            let createdBoard = try #require(session.resources.state.board(for: boardID))
            #expect(createdBoard.isTerminal)
            #expect(createdBoard.terminalWorkingDirectory == dir)
            #expect(session.navigation.focusedBoard?.id == boardID)
        }
    }

    @Test func terminalTitleChangeDoesNotTriggerSave() throws {
        let dir = FileManager.default.temporaryDirectory.path
        let terminalBoard = BoardState(width: 520, workingDirectory: dir)
        let source = makeTestDesk("Desk", boards: [terminalBoard], focusedBoardID: terminalBoard.id)
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

        let runtime = session.runtimes.terminalRuntime(for: terminalBoard)
        defer { runtime.dispose() }

        runtime.terminalDidChangeTitle("codex: thinking...")
        #expect(session.navigation.focusedBoard?.label == "codex: thinking...")
        #expect(saveCount == 0)

        runtime.terminalDidChangeWorkingDirectory("/tmp/new-working-dir")
        #expect(session.navigation.focusedBoard?.terminalWorkingDirectory == "/tmp/new-working-dir")
        #expect(saveCount == 1)
    }

    @Test func duplicateTerminalBoardResetsTemporaryContextAndFollowsInsertionContract() {
        let first = BoardState(width: 400, workingDirectory: "/tmp")
        let second = makeTestBoard("Second")
        let source = makeTestDesk("Desk", boards: [first, second], focusedBoardID: first.id)
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session, windowModel in
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
}
