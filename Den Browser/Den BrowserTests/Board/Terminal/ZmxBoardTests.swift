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
struct ZmxBoardTests {
    @Test func zmxBoardsOpenNamedSessionAndSessionsList() async throws {
        let source = makeTestDesk("Desk")
        let runner = StubTerminalCommandRunner(responses: [
            ["list"]: TerminalCommandResult(terminationStatus: 0, standardOutput: "")
        ])
        try await withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            ),
            terminalCommandRunner: runner
        ) { session, windowModel in
            session.configuration.preferences.setZmxPath("/opt/homebrew/bin/zmx")

            session.boardOpening.openBoard(input: ":zmx project-a")
            let board = try #require(session.navigation.focusedBoard)
            #expect(board.isTerminal)
            #expect(board.isZmx)
            #expect(board.zmxSessionName == "project-a")
            session.boardOpening.openBoard(input: ":zmx")
            await waitForTestZmxSessionLoad(windowModel)
            #expect(session.navigation.focusedDesk?.boards.count == 1)
            #expect(windowModel.isZmxSessionsPresented)
            #expect(session.resources.recentItems.first == .zmx(sessionName: "project-a"))
            #expect(RecentItem.zmx(sessionName: "").displayText == ":zmx")

            windowModel.hideZmxSessions()
            session.boardOpening.openBoard(recentItem: .zmx(sessionName: ""))
            await waitForTestZmxSessionLoad(windowModel)
            #expect(windowModel.isZmxSessionsPresented)

            windowModel.hideZmxSessions()
            windowModel.showOpenBoardPanel()
            windowModel.openBoard.submit(":zmx", preferredWidth: windowModel.defaultBoardWidth)
            await waitForTestZmxSessionLoad(windowModel)
            windowModel.hideZmxSessions()
            #expect(windowModel.isOpenBoardPanelPresented)
        }
    }

    @Test func zmxSessionsGroupChildrenOpenBoardsAndKillOneSession() async {
        let source = makeTestDesk("Desk")
        let commandRunner = StubTerminalCommandRunner(
            responses: [
                ["list"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: "name=den\nname=den-vi\tden.root=den\nname=old-root-debug\tden.root=old-root\n"
                ),
                ["kill", "den-vi", "--force"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: ""
                ),
            ])
        await withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            ),
            terminalCommandRunner: commandRunner
        ) { session, windowModel in
            session.configuration.preferences.setZmxPath("/opt/homebrew/bin/zmx")

            windowModel.showZmxSessions(selectedSessionName: "den-vi")
            await waitForTestZmxSessionLoad(windowModel)

            #expect(
                windowModel.zmxSessions.groups == [
                    ZmxSessionGroup(
                        rootSessionName: "den",
                        isRootActive: true,
                        childSessionNames: ["den-vi"]
                    ),
                    ZmxSessionGroup(
                        rootSessionName: "old-root",
                        isRootActive: false,
                        childSessionNames: ["old-root-debug"]
                    ),
                ]
            )
            #expect(windowModel.zmxSessions.selectedSessionName == "den-vi")
            windowModel.zmxSessions.setQuery("vi")
            #expect(
                windowModel.zmxSessions.filteredGroups
                    == [
                        ZmxSessionGroup(
                            rootSessionName: "den",
                            isRootActive: true,
                            childSessionNames: ["den-vi"]
                        )
                    ]
            )
            windowModel.clearZmxSessionFilter()

            windowModel.openZmxSession("den-vi")
            #expect(session.navigation.focusedBoard?.zmxSessionName == "den-vi")
            #expect(session.navigation.focusedBoard?.zmxRootSessionName == "den")
            #expect(session.resources.recentItems.first == .zmx(sessionName: "den-vi"))
            #expect(!windowModel.isZmxSessionsPresented)

            windowModel.showZmxSessions()
            await waitForTestZmxSessionLoad(windowModel)
            windowModel.openZmxSession("den-vi")
            #expect(session.navigation.focusedDesk?.boards.count == 1)

            windowModel.showZmxSessions()
            await waitForTestZmxSessionLoad(windowModel)
            windowModel.killZmxSession("den-vi")
            await waitForTestZmxSessionLoad(windowModel)
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
                    standardOutput: "name=den\nname=den-vi\tden.root=den\n"
                )
            ])
        await withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: [existing], focusedBoardID: existing.id)])
                )
            ),
            terminalCommandRunner: commandRunner
        ) { session, windowModel in
            session.configuration.preferences.setZmxPath("/opt/homebrew/bin/zmx")
            windowModel.showZmxSessions(selectedSessionName: "den-vi")
            await waitForTestZmxSessionLoad(windowModel)

            // Act
            windowModel.openZmxSession("den-vi")

            // Assert
            #expect(session.navigation.focusedDesk?.boards.count == 1)
            #expect(session.navigation.focusedBoard?.id == existing.id)
            #expect(session.navigation.focusedBoard?.zmxRootSessionName == "den")
        }
    }

    @Test(arguments: [false, true])
    func zmxBoardDuplicationCreatesRootedIndependentSessions(focusSide: Bool) async throws {
        let sourceBoard = BoardState(
            width: 640,
            zmxSessionName: "den",
            workingDirectory: "/tmp/project"
        )
        var side = BoardState(width: 360, zmxSessionName: "other", workingDirectory: "/tmp/side")
        side.role = .sideBoard(targetBoardID: sourceBoard.id)
        let boards = focusSide ? [sourceBoard, side] : [sourceBoard]
        let source = makeTestDesk("Desk", boards: boards, focusedBoardID: focusSide ? side.id : sourceBoard.id)
        let runner = StubTerminalCommandRunner(
            responses: [
                ["list", "--short"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: ""
                )
            ])
        try await withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            ),
            terminalCommandRunner: runner
        ) { session, windowModel in
            session.configuration.preferences.setZmxPath("/usr/bin/zmx")

            session.zmx.duplicateFocusedBoardFromFirstSheet()
            await session.zmx.waitForZmxCommand()
            let automaticChild = try #require(session.navigation.focusedBoard)
            #expect(session.navigation.focusedDesk?.boards.count == boards.count + 1)
            #expect(!automaticChild.isSideBoard)
            #expect(automaticChild.width == sourceBoard.width)
            #expect(automaticChild.zmxSessionName == "den-2")
            #expect(automaticChild.zmxRootSessionName == "den")
            #expect(automaticChild.terminalWorkingDirectory == "/tmp/project")
            #expect(windowModel.temporaryContext == nil)
            #expect(session.resources.recentItems.isEmpty)

            session.boardNavigation.focusBoard(focusSide ? side.id : sourceBoard.id)
            session.zmx.duplicateFocusedBoard()
            await session.zmx.waitForZmxCommand()
            #expect(windowModel.temporaryContext == .zmxDuplication)
            #expect(session.navigation.focusedDesk?.boards.count == boards.count + 1)

            session.zmx.duplicateFocusedZmxBoard(suffix: "vi")
            await session.zmx.waitForZmxCommand()
            let firstChild = try #require(session.navigation.focusedBoard)
            #expect(!firstChild.isSideBoard)
            #expect(firstChild.width == sourceBoard.width)
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
            workingDirectory: "/tmp/project"
        )
        let source = makeTestDesk("Desk", boards: [sourceBoard], focusedBoardID: sourceBoard.id)
        let commandRunner = StubTerminalCommandRunner(
            responses: [
                ["list", "--short"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: "den-vi\n"
                ),
                ["get", "den-vi", "den.root"]: TerminalCommandResult(
                    terminationStatus: 0,
                    standardOutput: "den\n"
                ),
            ])
        await withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            ),
            terminalCommandRunner: commandRunner
        ) { session, windowModel in
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
            width: 640,
            zmxSessionName: "project-editor",
            workingDirectory: "/tmp/project",
            rootSessionName: "old-root"
        )
        let occupied = BoardState(width: 520, zmxSessionName: "project-3")
        let source = makeTestDesk("Desk", boards: [primary, occupied], focusedBoardID: primary.id)
        let runner = StubTerminalCommandRunner(responses: [
            ["list", "--short"]: TerminalCommandResult(
                terminationStatus: 0,
                standardOutput: "project-editor\nproject-2\n"
            ),
            ["get", "project-editor", "den.root"]: TerminalCommandResult(
                terminationStatus: 0,
                standardOutput: "project\n"
            ),
        ])
        try await withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            ),
            terminalCommandRunner: runner
        ) { session, _ in
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
        let source = makeTestDesk("Desk", boards: [primary], focusedBoardID: primary.id)
        let runner = StubTerminalCommandRunner(responses: [
            ["list", "--short"]: TerminalCommandResult(terminationStatus: 0, standardOutput: "")
        ])
        await withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            ),
            terminalCommandRunner: runner
        ) { session, _ in
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
        let source = makeTestDesk("Desk", boards: [primary], focusedBoardID: primary.id)
        let runner = StubTerminalCommandRunner(responses: [
            ["list", "--short"]: TerminalCommandResult(
                terminationStatus: 1,
                standardOutput: "",
                standardError: "Session lookup failed"
            )
        ])
        await withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            ),
            terminalCommandRunner: runner
        ) { session, _ in
            session.configuration.preferences.setZmxPath("/usr/bin/zmx")

            // Act
            session.sideBoards.createTerminalSideBoard(targetBoardID: primary.id)
            await session.zmx.waitForZmxCommand()

            // Assert
            #expect(session.navigation.focusedDesk?.boards == [primary])
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
