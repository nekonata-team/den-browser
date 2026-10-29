import DenApplication
import DenDomain
import Foundation
import Testing

nonisolated struct BoardUndoTests {
    private final class State {
        var snapshot: DenSharedState
        var saves = 0
        var reader: DenStateReader { DenStateReader { self.snapshot } }
        var writer: DenStateWriter { DenStateWriter { $0(&self.snapshot) } }
        var movement: BoardMovement { BoardMovement(state: reader, writer: writer) }
        var transfer: DrawerTransfer { DrawerTransfer(store: reader, writer: writer) }
        var removal: BoardRemoval { BoardRemoval(store: reader, writer: writer) }
        var items: DrawerItems { DrawerItems(store: reader, writer: writer) }
        var creation: BoardCreation {
            BoardCreation(
                store: reader, writer: writer, recents: Recents(store: reader, writer: writer),
                directoryExists: { _ in true })
        }
        var placement: DrawerPlacement {
            DrawerPlacement(store: reader, writer: writer, creation: creation, items: items)
        }

        init(_ den: DenState) { snapshot = DenSharedState(den: den) }

        func undo() -> BoardUndo.Result {
            BoardUndo(
                store: reader, writer: writer,
                persist: { _ in
                    self.saves += 1
                    return true
                }
            ).undo(
                presentedDeskID: snapshot.den.focusedDeskID, notifyRemoval: { _ in },
                notifyTransfer: { _ in }, notifyPlacement: { _, _ in }, notifyDrawer: { _ in })
        }
    }

    @Test(arguments: [false, true])
    func mixedOperationsUndoInOrderAndKeepCurrentContent(terminal: Bool) throws {
        // Arrange
        let startURL = try #require(URL(string: "https://example.com/start"))
        let nextURL = try #require(URL(string: "https://example.com/next"))
        let board =
            terminal
            ? BoardState(label: "Work", width: 640, workingDirectory: "/tmp", customLabel: "Task")
            : BoardState(
                label: "Work", width: 640, currentSheetURL: startURL, customLabel: "Task", sheetNavigationPaused: true)
        let neighbor = BoardState(width: 520, workingDirectory: "/tmp")
        let first = DeskState(label: "First", boards: [neighbor, board], focusedBoardID: board.id)
        let second = DeskState(label: "Second", boards: [])
        let state = State(DenState(desks: [first, second], focusedDeskID: first.id))

        // Act: transfer, stash, place, then remove the same Board.
        #expect(state.movement.place(board.id, in: second.id, before: nil))
        let itemID = try #require(state.transfer.move(board.id, notify: { _ in }))
        if terminal {
            state.items.updateTerminal(itemID, workingDirectory: "/var/tmp")
        } else {
            state.items.update(itemID, url: nextURL, title: "Next")
        }
        state.placement.place(
            .init(
                itemID: itemID, width: 520, searchEngine: .google,
                target: .init(presentedDeskID: first.id)), notifyBoard: { _ in }, notifyDrawer: { _ in })
        state.removal.remove(board.id, presentedDeskID: first.id, notify: { _ in })

        // Assert: each Undo reverses one organization operation, without recording itself.
        #expect(state.undo() == .board(board.id))
        #expect(state.snapshot.den.desks[0].boards.map(\.id) == [neighbor.id, board.id])
        #expect(state.snapshot.recentlyRemovedBoards.isEmpty)
        #expect(state.undo() == .drawer(itemID))
        #expect(state.snapshot.den.drawerItems.map(\.id) == [itemID])
        #expect(state.undo() == .board(board.id))
        let restored = try #require(state.snapshot.den.desks[1].boards.first)
        #expect(restored.id == board.id)
        #expect(restored.width == board.width)
        #expect(restored.customLabel == board.customLabel)
        if terminal {
            #expect(restored.terminalWorkingDirectory == "/var/tmp")
        } else {
            #expect(restored.currentSheetURL == nextURL)
            #expect(restored.firstSheetURL == startURL)
            #expect(restored.sheetNavigationPaused)
        }
        #expect(state.undo() == .board(board.id))
        #expect(state.snapshot.den.desks[0].boards.map(\.id) == [neighbor.id, board.id])
        #expect(state.snapshot.den.desks[1].boards.isEmpty)
        #expect(state.undo() == .empty)
        #expect(state.saves == 4)
    }

    @Test func overviewTransferMovesGroupAndSameDeskReorderingDoesNotRecordUndo() {
        // Arrange
        let primary = BoardState(width: 520, workingDirectory: "/tmp")
        let side = BoardState(width: 520, targetBoardID: primary.id)
        let neighbor = BoardState(width: 520, workingDirectory: "/tmp")
        let first = DeskState(label: "First", boards: [primary, side, neighbor])
        let second = DeskState(label: "Second", boards: [])
        let state = State(DenState(desks: [first, second], focusedDeskID: first.id))

        // Act
        state.movement.shiftInOverview(primary.id, by: 1)
        #expect(state.snapshot.boardUndoHistory.isEmpty)
        #expect(state.movement.beginOverviewDrag(side.id))
        state.movement.finishOverviewDrag(side.id, to: second.id, at: .init(rawValue: 0))
        // Looking around does not consume or replace the organization history.
        state.snapshot.den.focusedDeskID = second.id

        // Assert
        #expect(state.snapshot.boardUndoHistory.count == 1)
        #expect(state.undo() == .board(primary.id))
        #expect(state.snapshot.den.desks[0].boards.map(\.id) == [neighbor.id, primary.id, side.id])
        #expect(state.snapshot.den.focusedDeskID == second.id)
        #expect(state.snapshot.den.desks[1].boards.isEmpty)
    }

    @Test func undoPlacementRestoresDrawerPositionWithoutDiscardHistory() throws {
        // Arrange
        let items = (0..<3).map { DrawerItem(terminal: .shell(workingDirectory: "/tmp"), title: "Item \($0)") }
        let desk = DeskState(label: "Desk", boards: [])
        let state = State(DenState(desks: [desk], focusedDeskID: desk.id, drawerItems: items))

        // Act
        state.placement.place(
            .init(
                itemID: items[1].id, width: 520, searchEngine: .google,
                target: .init(presentedDeskID: desk.id)), notifyBoard: { _ in }, notifyDrawer: { _ in })
        let result = state.undo()

        // Assert
        #expect(result == .drawer(items[1].id))
        #expect(state.snapshot.den.drawerItems.map(\.id) == items.map(\.id))
        #expect(state.snapshot.den.desks[0].boards.isEmpty)
        #expect(state.snapshot.recentlyDiscardedDrawerItems.isEmpty)
    }

    @Test func missingDestinationPreservesStateAndHistoryForRetry() {
        // Arrange
        let board = BoardState(width: 520, workingDirectory: "/tmp")
        let older = BoardState(width: 520, workingDirectory: "/tmp")
        let first = DeskState(label: "First", boards: [board])
        let second = DeskState(label: "Second", boards: [older])
        let state = State(DenState(desks: [first, second], focusedDeskID: second.id))
        state.removal.remove(older.id, presentedDeskID: second.id, notify: { _ in })
        #expect(state.movement.place(board.id, in: second.id, before: nil))
        state.snapshot.den.desks.removeFirst()
        let before = state.snapshot

        // Act / Assert
        #expect(state.undo() == .unavailable)
        #expect(state.snapshot == before)
        state.snapshot.den.desks.insert(DeskState(id: first.id, label: "First", boards: []), at: 0)
        #expect(state.undo() == .board(board.id))
        #expect(state.undo() == .board(older.id))
    }

    @Test func draggingBlocksUndoAndResetClearsItsBoundedHistory() {
        // Arrange
        let board = BoardState(width: 520, workingDirectory: "/tmp")
        let first = DeskState(label: "First", boards: [board])
        let second = DeskState(label: "Second", boards: [])
        let state = State(DenState(desks: [first, second], focusedDeskID: first.id))
        for index in 0..<22 {
            #expect(state.movement.place(board.id, in: index.isMultiple(of: 2) ? second.id : first.id, before: nil))
        }

        // Act / Assert
        #expect(state.snapshot.boardUndoHistory.count == 20)
        state.snapshot.activeDrag = .board(board.id)
        #expect(state.undo() == .dragging)
        #expect(state.snapshot.boardUndoHistory.count == 20)
        DenReset(store: state.reader, writer: state.writer).perform(notify: { _ in })
        #expect(state.snapshot.boardUndoHistory.isEmpty)
    }

    @Test func undoRetainsTheLatestTwentyRemovalsIndependentlyOfRestorationHistory() {
        // Arrange
        let boards = (0..<22).map { BoardState(label: "Board \($0)", width: 520, workingDirectory: "/tmp") }
        let desk = DeskState(label: "Desk", boards: boards)
        let state = State(DenState(desks: [desk], focusedDeskID: desk.id))

        // Act
        for board in boards {
            state.removal.remove(board.id, presentedDeskID: desk.id, notify: { _ in })
        }

        // Assert
        for board in boards.suffix(20).reversed() {
            #expect(state.undo() == .board(board.id))
        }
        #expect(state.undo() == .empty)
        #expect(state.snapshot.den.desks[0].boards.map(\.id) == boards.suffix(20).map(\.id))
    }
}
