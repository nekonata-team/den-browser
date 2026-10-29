public import DenDomain
import Foundation

public struct DrawerTransfer {
    public enum Notice {
        case willMove(BoardState, DrawerItem)
        case didMove(source: DeskState, plan: BoardRemovalPlan, item: DrawerItem)
    }

    private let store: DenStateReader
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?

    public init(store: DenStateReader, writer: DenStateWriter, persist: ((DenState) -> Bool)? = nil) {
        self.store = store
        self.writer = writer
        self.persist = persist
    }

    public static func canMove(_ board: BoardState, among boards: [BoardState]) -> Bool {
        guard !board.isSideBoard, !boards.contains(where: { $0.sideBoardTargetBoardID == board.id }) else {
            return false
        }
        if board.isTerminal { return true }
        return board.currentSheetURL.map(WebURLPolicy.isSupported) == true
    }

    /// Move atomically without recording a removed Board or restarting its runtime.
    @discardableResult
    public func move(_ boardID: BoardID, recordsUndo: Bool = true, notify: (Notice) -> Void) -> UUID? {
        guard store.snapshot.activeDrag == nil,
            let deskIndex = store.snapshot.den.desks.firstIndex(where: { $0.boards.contains { $0.id == boardID } })
        else { return nil }
        let source = store.snapshot.den.desks[deskIndex]
        guard let board = source.boards.first(where: { $0.id == boardID }),
            Self.canMove(board, among: source.boards),
            !store.snapshot.den.drawerItems.contains(where: { $0.id == boardID.rawValue }),
            let removal = BoardRemovalPlan.make(boardID, from: source)
        else { return nil }
        let item: DrawerItem
        switch board.kind {
        case .web(let web):
            guard let url = web.currentSheetURL else { return nil }
            item = DrawerItem(id: boardID.rawValue, url: url, title: board.displayName)
        case .terminal(let session):
            item = DrawerItem(id: boardID.rawValue, terminal: session, title: board.displayName)
        case .inspection, .tutorial: return nil
        }
        notify(.willMove(board, item))
        writer.update {
            $0.den.desks[deskIndex] = removal.desk
            $0.den.drawerItems.insert(item, at: 0)
            if recordsUndo { $0.rememberBoardOperation(.movedToDrawer(removal.historyEntry)) }
        }
        notify(.didMove(source: source, plan: removal, item: item))
        _ = persist?(store.snapshot.den)
        return item.id
    }
}
