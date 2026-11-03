public import DenDomain

public struct BoardSizing {
    private let reader: DenStateReader
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?
    private let deferredSave: (() -> Void)?

    public init(
        reader: DenStateReader, writer: DenStateWriter,
        persist: ((DenState) -> Bool)? = nil, deferredSave: (() -> Void)? = nil
    ) {
        self.reader = reader
        self.writer = writer
        self.persist = persist
        self.deferredSave = deferredSave
    }

    public func adjustBoard(_ id: BoardID, by delta: Double) {
        guard let indices = indices(id) else { return }
        let board = reader.snapshot.den.desks[indices.desk].boards[indices.board]
        let width = BoardState.constrainedWidth(board.width + delta)
        guard width != board.width else { return }
        writer.update { $0.den.desks[indices.desk].boards[indices.board].width = width }
        save(deferred: true)
    }

    public func adjustDesk(_ id: DeskID, by delta: Double) {
        guard let index = reader.snapshot.den.desks.firstIndex(where: { $0.id == id }) else { return }
        let original = reader.snapshot.den.desks[index].boards
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
        guard let index = reader.snapshot.den.desks.firstIndex(where: { $0.id == id }) else { return false }
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

    public func setBoardWidth(_ id: BoardID, to width: Double, maximumWidth: Double) -> Double? {
        guard width.isFinite, width > 0, maximumWidth.isFinite, maximumWidth >= BoardState.minimumWidth,
            reader.snapshot.activeDrag == nil, let indices = indices(id)
        else { return nil }
        let appliedWidth = min(max(width, BoardState.minimumWidth), maximumWidth)
        writer.update { $0.den.desks[indices.desk].boards[indices.board].width = appliedWidth }
        guard persist?(reader.snapshot.den) ?? true else { return nil }
        return appliedWidth
    }

    public func resizePair(_ id: BoardID, to width: Double) {
        guard let indices = indices(id) else { return }
        let next = indices.board + 1
        let boards = reader.snapshot.den.desks[indices.desk].boards
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
        for (desk, value) in reader.snapshot.den.desks.enumerated() {
            if let board = value.boards.firstIndex(where: { $0.id == id }) { return (desk, board) }
        }
        return nil
    }

    private func save(deferred: Bool = false) {
        guard reader.snapshot.activeDrag == nil else { return }
        if deferred, let deferredSave { deferredSave() } else { _ = persist?(reader.snapshot.den) }
    }
}
