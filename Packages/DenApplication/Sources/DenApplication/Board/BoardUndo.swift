public import DenDomain
import Foundation

public enum BoardUndoEntry: Equatable {
    case movedToDesk(boardID: BoardID, sourceDeskID: DeskID, sourceIndex: BoardIndex)
    case movedToDrawer(RecentlyRemovedBoard)
    case placedFromDrawer(itemID: UUID, sourceIndex: Int)
    case removed(RecentlyRemovedBoard)
}

/// Reverses Board organization without rewinding live Sheet content.
public struct BoardUndo {
    public static let maximumHistoryCount = 20

    public enum Result: Equatable {
        case board(BoardID)
        case drawer(UUID)
        case empty
        case unavailable
        case dragging
    }

    private let store: DenStateReader
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?

    public init(store: DenStateReader, writer: DenStateWriter, persist: ((DenState) -> Bool)? = nil) {
        self.store = store
        self.writer = writer
        self.persist = persist
    }

    public func undo(
        presentedDeskID: DeskID,
        notifyRemoval: (BoardRemoval.Notice) -> Void,
        notifyTransfer: (DrawerTransfer.Notice) -> Void,
        notifyPlacement: (UUID, BoardCreation.Notice) -> Void,
        notifyDrawer: (DrawerItems.Notice) -> Void
    ) -> Result {
        guard store.snapshot.activeDrag == nil else { return .dragging }
        guard let entry = store.snapshot.boardUndoHistory.first else { return .empty }
        let result: Result
        switch entry {
        case .movedToDesk(let boardID, let deskID, let index):
            result = undoDeskMove(boardID, to: deskID, at: index)
        case .movedToDrawer(let source):
            result = undoDrawerMove(source, notify: notifyPlacement, notifyDrawer: notifyDrawer)
        case .placedFromDrawer(let itemID, let index):
            let transfer = DrawerTransfer(store: store, writer: writer)
            if let id = transfer.move(BoardID(itemID), recordsUndo: false, notify: notifyTransfer) {
                writer.update {
                    let item = $0.den.drawerItems.removeFirst()
                    $0.den.drawerItems.insert(item, at: min(index, $0.den.drawerItems.endIndex))
                }
                result = .drawer(id)
            } else {
                result = .unavailable
            }
        case .removed(let source):
            // Undo returns to the original Desk; it does not choose a different destination.
            if store.snapshot.den.desks.contains(where: { $0.id == source.sourceDeskID }),
                !store.snapshot.den.desks.contains(where: { $0.boards.contains { $0.id == source.board.id } }),
                !source.board.isTutorial
                    || !store.snapshot.den.desks.contains(where: { $0.boards.contains(where: \.isTutorial) }),
                !store.snapshot.den.drawerItems.contains(where: { $0.id == source.board.id.rawValue })
            {
                let removal = BoardRemoval(store: store, writer: writer)
                switch removal.restore(source, presentedDeskID: presentedDeskID, present: false, notify: notifyRemoval)
                {
                case .restored(let id): result = .board(id)
                case .existingTutorial, .rejected, .emptyHistory: result = .unavailable
                }
            } else {
                result = .unavailable
            }
        }
        guard result != .unavailable else { return result }
        writer.update {
            if $0.boardUndoHistory.first == entry { $0.boardUndoHistory.removeFirst() }
        }
        _ = persist?(store.snapshot.den)
        return result
    }

    private func undoDeskMove(_ boardID: BoardID, to deskID: DeskID, at index: BoardIndex) -> Result {
        guard let source = store.snapshot.den.desks.first(where: { $0.boards.contains { $0.id == boardID } }),
            store.snapshot.den.desks.contains(where: { $0.id == deskID })
        else { return .unavailable }
        BoardMovement(state: store, writer: writer).transfer(
            boardID, from: source.id, to: deskID, at: index, recordsUndo: false)
        writer.update {
            guard let target = $0.den.desks.firstIndex(where: { $0.id == deskID }) else { return }
            $0.den.desks[target].focusedBoardID = boardID
        }
        return .board(boardID)
    }

    private func undoDrawerMove(
        _ source: RecentlyRemovedBoard,
        notify: (UUID, BoardCreation.Notice) -> Void,
        notifyDrawer: (DrawerItems.Notice) -> Void
    ) -> Result {
        let id = source.board.id.rawValue
        guard let item = store.snapshot.den.drawerItems.first(where: { $0.id == id }),
            let desk = store.snapshot.den.desks.first(where: { $0.id == source.sourceDeskID }),
            !store.snapshot.den.desks.contains(where: { $0.boards.contains { $0.id == source.board.id } })
        else { return .unavailable }
        var board = source.board
        switch item.content {
        case .web(let url): board.currentSheetURL = url
        case .terminal(let session): board.kind = .terminal(session)
        }
        if let title = item.title { board.label = title }
        let offset = BoardInsertion.groupBoundaryOffset(source.sourceBoardIndex.rawValue, in: desk.boards)
        let before = desk.boards.indices.contains(offset) ? desk.boards[offset].id : nil
        let creation = BoardCreation(
            store: store, writer: writer, recents: Recents(store: store, writer: writer), directoryExists: { _ in true }
        )
        guard
            creation.insert(
                board,
                target: .init(
                    presentedDeskID: desk.id, deskID: desk.id,
                    afterBoardID: before == nil ? desk.boards.last?.id : nil, beforeBoardID: before, focus: false),
                notify: { notify(id, $0) }) != nil
        else { return .unavailable }
        DrawerItems(store: store, writer: writer).consume(id, notify: notifyDrawer)
        writer.update {
            guard let target = $0.den.desks.firstIndex(where: { $0.id == desk.id }) else { return }
            $0.den.desks[target].focusedBoardID = board.id
        }
        return .board(board.id)
    }
}
