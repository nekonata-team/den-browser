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
        let controller = DenController(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let runtime = controller.terminalRuntime(for: board)
        weak let receiver = controller.storage.boardRuntimes.receivers[board.id]

        // Act
        controller.removeBoard(board.id)
        runtime.terminalDidChangeTitle("Late title")
        runtime.terminalDidRequestDesktopNotification(title: "Late notification", body: "Ignored")

        // Assert
        #expect(receiver == nil)
        #expect(controller.storage.boardRuntimes.receivers.isEmpty)
        #expect(controller.storage.notifications.isEmpty)
        #expect(controller.focusedDesk?.boards.isEmpty == true)
    }

    @Test func backgroundRuntimeExitAfterWindowDisconnectRemovesBoardWithoutChangingOtherWindowFocus() {
        // Arrange
        let terminal = BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
        let remaining = BoardState(label: "Remaining", width: 520, workingDirectory: "/tmp")
        let backgroundDesk = DeskState(label: "Background", boards: [terminal], focusedBoardID: terminal.id)
        let presentedDesk = DeskState(label: "Presented", boards: [remaining], focusedBoardID: remaining.id)
        let controller = DenController(
            state: DenState(desks: [backgroundDesk, presentedDesk], focusedDeskID: presentedDesk.id))
        let receiver = BoardRuntimeReceiver(storage: controller.storage, boardID: terminal.id)
        let disconnected = RuntimeWindowConnection()
        let events = receiver.terminalEvents(for: terminal, connection: disconnected)

        // Act
        events.onClose()

        // Assert
        #expect(controller.state.desks[0].boards.isEmpty)
        #expect(controller.presentedDeskID == presentedDesk.id)
        #expect(controller.focusedDesk?.focusedBoardID == remaining.id)
        #expect(controller.storage.recentlyRemovedBoards.first?.board.id == terminal.id)
    }
    @Test func denResetKeepsTheOpenWindowConnectedToNewRuntimeEvents() {
        // Arrange
        let controller = DenController()
        controller.resetDen()
        let board = BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        controller.storage.state = DenState(desks: [desk], focusedDeskID: desk.id)
        controller.focusDesk(desk.id)
        let runtime = controller.terminalRuntime(for: board)
        var focused: [BoardID] = []
        controller.onWindowEffect = { if case .runtimeFocusedBoard(let id) = $0 { focused.append(id) } }

        // Act
        runtime.terminalDidChangeFocus(true)

        // Assert
        #expect(focused == [board.id])
        #expect(controller.runtimeConnection.controller === controller)
    }
}
