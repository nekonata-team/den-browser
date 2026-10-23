import DenApplication
import DenDomain
import DenPresentationModels
import Testing

@testable import Den_Browser

@MainActor
struct BoardRuntimeReceiverTests {
    @Test func disposedBoardReleasesReceiverDespiteExternalRuntimeReference() throws {
        // Arrange
        let board = BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let runtime = session.runtimes.terminalRuntime(for: board)
        weak let receiver = session.resources.boardRuntimes.receivers[board.id]

        // Act
        session.boardRemoval.removeBoard(board.id)
        runtime.terminalDidChangeTitle("Late title")
        runtime.terminalDidRequestDesktopNotification(title: "Late notification", body: "Ignored")

        // Assert
        #expect(receiver == nil)
        #expect(session.resources.boardRuntimes.receivers.isEmpty)
        #expect(session.resources.notifications.isEmpty)
        #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
    }

    @Test func backgroundRuntimeExitAfterWindowDisconnectRemovesBoardWithoutChangingOtherWindowFocus() {
        // Arrange
        let terminal = BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
        let remaining = BoardState(label: "Remaining", width: 520, workingDirectory: "/tmp")
        let backgroundDesk = DeskState(label: "Background", boards: [terminal], focusedBoardID: terminal.id)
        let presentedDesk = DeskState(label: "Presented", boards: [remaining], focusedBoardID: remaining.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [backgroundDesk, presentedDesk], focusedDeskID: presentedDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let receiver = BoardRuntimeReceiver(storage: session.resources, boardID: terminal.id)
        let disconnected = RuntimeWindowConnection()
        let events = receiver.terminalEvents(for: terminal, connection: disconnected)

        // Act
        events.onClose()

        // Assert
        #expect(session.resources.state.desks[0].boards.isEmpty)
        #expect(session.navigation.presentedDeskID == presentedDesk.id)
        #expect(session.navigation.focusedDesk?.focusedBoardID == remaining.id)
        #expect(session.resources.recentlyRemovedBoards.first?.board.id == terminal.id)
    }
    @Test func denResetKeepsTheOpenWindowConnectedToNewRuntimeEvents() {
        // Arrange
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration())
        session.reset.resetDen()
        let board = BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        session.resources.state = DenState(desks: [desk], focusedDeskID: desk.id)
        session.boardNavigation.focusDesk(desk.id)
        let runtime = session.runtimes.terminalRuntime(for: board)
        var focused: [BoardID] = []
        session.connection.onWindowEffect = { if case .runtimeFocusedBoard(let id) = $0 { focused.append(id) } }

        // Act
        runtime.terminalDidChangeFocus(true)

        // Assert
        #expect(focused == [board.id])
        #expect(session.connection.runtimes === session.runtimes)
    }
}
