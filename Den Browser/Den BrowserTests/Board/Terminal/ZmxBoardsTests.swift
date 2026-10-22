import DenApplication
import DenDomain
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct ZmxBoardsTests {
    @Test(arguments: [false, true])
    func closedWindowAndCancelledDuplicationDoNotInsert(cancelled: Bool) async {
        // Arrange
        let source = BoardState(width: 520, zmxSessionName: "root", workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [source], focusedBoardID: source.id)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let creation = BoardCreation(
            store: shared.store, writer: shared.writer,
            recents: Recents(store: shared.store, writer: shared.writer), directoryExists: { _ in true })
        let operations = ZmxBoards(
            state: shared.store, creation: creation,
            removal: BoardRemoval(store: shared.store, writer: shared.writer),
            updates: BoardUpdates(store: shared.store, writer: shared.writer))
        let runner = DuplicationRunner()
        let initial = shared.store.snapshot
        let task = Task { @MainActor in
            if cancelled { withUnsafeCurrentTask { $0?.cancel() } }
            await operations.duplicate(
                .init(
                    source: source, suffix: "", asSideBoard: false, focus: true, width: 520, workingDirectory: "/tmp"),
                client: ZmxClient(executablePath: "/usr/bin/zmx", commandRunner: runner),
                window: { cancelled ? .init(presentedDeskID: desk.id, focusedBoardID: source.id) : nil },
                notify: { _ in Issue.record("Cancelled or closed-window operation must not notify") })
        }
        // Act
        await task.value
        // Assert
        #expect(shared.store.snapshot == initial)
    }
}

private struct DuplicationRunner: TerminalCommandRunning, Sendable {
    func run(executablePath: String, arguments: [String], timeout: Duration) async throws -> TerminalCommandResult {
        TerminalCommandResult(terminationStatus: 0, standardOutput: "")
    }
}
