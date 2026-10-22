import DenDomain

@MainActor
public struct BoardSizing {
    private let store: DenStateStore
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?
    private let deferredSave: (() -> Void)?

    public init(
        store: DenStateStore, writer: DenStateWriter,
        persist: ((DenState) -> Bool)? = nil, deferredSave: (() -> Void)? = nil
    ) {
        self.store = store
        self.writer = writer
        self.persist = persist
        self.deferredSave = deferredSave
    }

    public func adjustBoard(_ id: BoardID, by delta: Double) {
        guard let indices = indices(id) else { return }
        let board = store.snapshot.den.desks[indices.desk].boards[indices.board]
        let width = BoardState.constrainedWidth(board.width + delta)
        guard width != board.width else { return }
        writer.update { $0.den.desks[indices.desk].boards[indices.board].width = width }
        save(deferred: true)
    }

    public func adjustDesk(_ id: DeskID, by delta: Double) {
        guard let index = store.snapshot.den.desks.firstIndex(where: { $0.id == id }) else { return }
        let original = store.snapshot.den.desks[index].boards
        var boards = original
        for index in boards.indices where !boards[index].isSideBoard {
            boards[index].width = BoardState.constrainedWidth(boards[index].width + delta)
        }
        guard boards != original else { return }
        writer.update { $0.den.desks[index].boards = boards }
        save(deferred: true)
    }

    @discardableResult
    public func resizeDesk(_ id: DeskID, to width: Double) -> Bool {
        guard let index = store.snapshot.den.desks.firstIndex(where: { $0.id == id }) else { return false }
        writer.update {
            for boardIndex in $0.den.desks[index].boards.indices
            where !$0.den.desks[index].boards[boardIndex].isSideBoard {
                $0.den.desks[index].boards[boardIndex].width = width
            }
            if $0.den.desks[index].focusedBoardID != nil { $0.den.desks[index].scrollOffsetX = nil }
        }
        save()
        return true
    }

    public func resizeBoard(_ id: BoardID, to width: Double) {
        guard let indices = indices(id) else { return }
        writer.update { $0.den.desks[indices.desk].boards[indices.board].width = BoardState.constrainedWidth(width) }
    }

    public func resizePair(_ id: BoardID, to width: Double) {
        guard let indices = indices(id) else { return }
        let next = indices.board + 1
        let boards = store.snapshot.den.desks[indices.desk].boards
        guard boards.indices.contains(next) else { return }
        let total = boards[indices.board].width + boards[next].width
        let minimum = max(BoardState.minimumWidth, total - BoardState.maximumWidth)
        let maximum = min(BoardState.maximumWidth, total - BoardState.minimumWidth)
        let resized = min(max(width, minimum), maximum)
        writer.update {
            $0.den.desks[indices.desk].boards[indices.board].width = resized
            $0.den.desks[indices.desk].boards[next].width = total - resized
        }
    }

    public func saveWidths() { save() }

    private func indices(_ id: BoardID) -> (desk: Int, board: Int)? {
        for (desk, value) in store.snapshot.den.desks.enumerated() {
            if let board = value.boards.firstIndex(where: { $0.id == id }) { return (desk, board) }
        }
        return nil
    }

    private func save(deferred: Bool = false) {
        guard store.snapshot.activeDrag == nil else { return }
        if deferred, let deferredSave { deferredSave() } else { _ = persist?(store.snapshot.den) }
    }
}
