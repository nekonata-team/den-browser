import DenDomain

@MainActor
public struct BoardMovement {
    private let state: DenStateStore
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?

    public init(state: DenStateStore, writer: DenStateWriter, persist: ((DenState) -> Bool)? = nil) {
        self.state = state
        self.writer = writer
        self.persist = persist
    }

    public func canMove(_ boardID: BoardID, by delta: Int) -> Bool {
        guard delta != 0,
            let desk = state.snapshot.den.desks.first(where: { $0.boards.contains { $0.id == boardID } })
        else { return false }
        let boards = desk.boards
        guard let group = BoardGroup.containing(boardID, in: boards),
            let first = group.boards.first,
            let last = group.boards.last,
            let firstIndex = boards.firstIndex(where: { $0.id == first.id }),
            let lastIndex = boards.firstIndex(where: { $0.id == last.id })
        else { return false }
        return delta < 0 ? firstIndex > 0 : lastIndex < boards.count - 1
    }

    public func transfer(_ boardID: BoardID, from sourceDeskID: DeskID, to targetDeskID: DeskID, at index: BoardIndex) {
        writer.update { snapshot in
            guard let sourceIndex = snapshot.den.desks.firstIndex(where: { $0.id == sourceDeskID }),
                let targetIndex = snapshot.den.desks.firstIndex(where: { $0.id == targetDeskID })
            else { return }
            let sourceBoards = snapshot.den.desks[sourceIndex].boards
            guard let group = BoardGroup.containing(boardID, in: sourceBoards) else { return }
            let groupBoards = group.boards
            let ids = Set(groupBoards.map(\.id))
            let removedIndex = sourceBoards.firstIndex { ids.contains($0.id) } ?? 0
            let sourceWasFocused = snapshot.den.desks[sourceIndex].focusedBoardID.map(ids.contains) ?? false
            snapshot.den.desks[sourceIndex].boards.removeAll { ids.contains($0.id) }
            if sourceWasFocused && sourceIndex != targetIndex {
                let remaining = snapshot.den.desks[sourceIndex].boards
                snapshot.den.desks[sourceIndex].focusedBoardID =
                    remaining.indices.contains(removedIndex)
                    ? remaining[removedIndex].id
                    : remaining.last?.id
            }
            let targetBoards = snapshot.den.desks[targetIndex].boards
            let insertionIndex = BoardInsertion.groupBoundaryOffset(index.rawValue, in: targetBoards)
            snapshot.den.desks[targetIndex].boards.insert(contentsOf: groupBoards, at: insertionIndex)
        }
    }

    public func reorder(_ boardID: BoardID, to targetIndex: BoardIndex, in deskID: DeskID) {
        writer.update { snapshot in
            guard let deskIndex = snapshot.den.desks.firstIndex(where: { $0.id == deskID }) else { return }
            let boards = snapshot.den.desks[deskIndex].boards
            let targetOffset = targetIndex.rawValue
            guard let group = BoardGroup.containing(boardID, in: boards), boards.indices.contains(targetOffset) else {
                return
            }
            let groupIDs = Set(group.boards.map(\.id))
            guard let firstIndex = boards.firstIndex(where: { groupIDs.contains($0.id) }) else { return }
            guard let destinationGroup = BoardGroup.containing(boards[targetOffset].id, in: boards) else { return }
            guard !destinationGroup.boards.contains(where: { groupIDs.contains($0.id) }) else { return }
            var remaining = boards.filter { !groupIDs.contains($0.id) }
            let insertionIndex: Int
            if targetOffset < firstIndex {
                insertionIndex =
                    destinationGroup.boards.first.flatMap { member in
                        remaining.firstIndex(where: { $0.id == member.id })
                    } ?? 0
            } else if let destinationLastID = destinationGroup.boards.last?.id,
                let index = remaining.firstIndex(where: { $0.id == destinationLastID })
            {
                insertionIndex = index + 1
            } else {
                insertionIndex = remaining.endIndex
            }
            remaining.insert(contentsOf: group.boards, at: insertionIndex)
            snapshot.den.desks[deskIndex].boards = remaining
        }
    }

    public func restoreOrder(_ boardIDs: [BoardID], in deskID: DeskID) {
        writer.update { snapshot in
            guard let deskIndex = snapshot.den.desks.firstIndex(where: { $0.id == deskID }) else { return }
            let order = Dictionary(uniqueKeysWithValues: boardIDs.enumerated().map { ($1, $0) })
            snapshot.den.desks[deskIndex].boards.sort {
                (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max)
            }
        }
    }

    public func place(_ boardID: BoardID, in deskID: DeskID, before anchorID: BoardID?) -> Bool {
        guard state.snapshot.activeDrag == nil,
            let source = deskIndex(containing: boardID),
            let target = state.snapshot.den.desks.firstIndex(where: { $0.id == deskID }),
            let group = BoardGroup.containing(boardID, in: state.snapshot.den.desks[source].boards)
        else { return false }
        let ids = Set(group.boards.map(\.id))
        if let anchorID, ids.contains(anchorID) { return true }
        let remaining = state.snapshot.den.desks[target].boards.filter { !ids.contains($0.id) }
        let index: Int
        if let anchorID {
            guard let offset = remaining.firstIndex(where: { $0.id == anchorID }) else { return false }
            index = offset
        } else {
            index = remaining.endIndex
        }
        transfer(boardID, from: state.snapshot.den.desks[source].id, to: deskID, at: .init(rawValue: index))
        focusIfEmpty(boardID, in: target)
        save()
        return true
    }

    public func shiftAndCenter(_ boardID: BoardID, by delta: Int, center: () -> Void) {
        guard let destination = adjacentPosition(boardID, by: delta) else { return }
        reorder(boardID, to: .init(rawValue: destination.board), in: state.snapshot.den.desks[destination.desk].id)
        writer.update { $0.den.desks[destination.desk].scrollOffsetX = nil }
        center()
        save()
    }

    public func shiftInOverview(_ boardID: BoardID, by delta: Int) {
        guard state.snapshot.activeDrag == nil, let destination = adjacentPosition(boardID, by: delta) else { return }
        reorder(boardID, to: .init(rawValue: destination.board), in: state.snapshot.den.desks[destination.desk].id)
        save()
    }

    public func transferAndPresent(_ boardID: BoardID, to deskID: DeskID, present: (DeskID) -> Void) {
        guard let source = deskIndex(containing: boardID),
            let target = state.snapshot.den.desks.firstIndex(where: { $0.id == deskID }), source != target
        else { return }
        transfer(boardID, from: state.snapshot.den.desks[source].id, to: deskID, at: insertionAfterFocus(in: target))
        writer.update { $0.den.desks[target].focusedBoardID = boardID }
        present(deskID)
        save()
    }

    public func transferInOverview(_ boardID: BoardID, by delta: Int) {
        let count = state.snapshot.den.desks.count
        guard state.snapshot.activeDrag == nil, count > 1, let source = deskIndex(containing: boardID) else { return }
        let target = ((source + delta) % count + count) % count
        transfer(
            boardID, from: state.snapshot.den.desks[source].id, to: state.snapshot.den.desks[target].id,
            at: insertionAfterFocus(in: target))
        focusIfEmpty(boardID, in: target)
        save()
    }

    public func beginOverviewDrag(_ boardID: BoardID) -> Bool {
        guard state.snapshot.activeDrag == nil, deskIndex(containing: boardID) != nil else { return false }
        writer.update { $0.activeDrag = .board(boardID) }
        return true
    }

    public func finishOverviewDrag(_ boardID: BoardID, to deskID: DeskID, at index: BoardIndex) {
        guard case .board(let activeID)? = state.snapshot.activeDrag, activeID == boardID,
            let source = deskIndex(containing: boardID),
            let target = state.snapshot.den.desks.firstIndex(where: { $0.id == deskID })
        else { return }
        let keepsFocus = source == target && state.snapshot.den.desks[source].focusedBoardID == boardID
        if source == target {
            reorder(boardID, to: index, in: deskID)
        } else {
            transfer(boardID, from: state.snapshot.den.desks[source].id, to: deskID, at: index)
        }
        if keepsFocus { writer.update { $0.den.desks[target].focusedBoardID = boardID } }
        focusIfEmpty(boardID, in: target)
        writer.update { $0.activeDrag = nil }
        save()
    }

    public func cancelOverviewDrag() {
        guard case .board? = state.snapshot.activeDrag else { return }
        writer.update { $0.activeDrag = nil }
    }

    public func beginDrag(_ boardID: BoardID, in deskID: DeskID, prepare: () -> Void) -> Bool {
        guard state.snapshot.activeDrag == nil,
            let source = deskIndex(containing: boardID), state.snapshot.den.desks[source].id == deskID
        else { return false }
        writer.update { $0.den.desks[source].focusedBoardID = boardID }
        NotificationOperations(store: state, writer: writer).markAllRead(for: boardID)
        prepare()
        writer.update { $0.activeDrag = .board(boardID) }
        save()
        return true
    }

    public func preview(_ boardID: BoardID, to index: BoardIndex, in deskID: DeskID) {
        guard let desk = state.snapshot.den.desks.firstIndex(where: { $0.id == deskID }),
            state.snapshot.den.desks[desk].boards.indices.contains(index.rawValue)
        else { return }
        reorder(boardID, to: index, in: deskID)
        writer.update { $0.den.desks[desk].focusedBoardID = boardID }
    }

    public func finishDrag() {
        guard case .board? = state.snapshot.activeDrag else { return }
        writer.update { $0.activeDrag = nil }
        save()
    }

    private func deskIndex(containing id: BoardID) -> Int? {
        state.snapshot.den.desks.firstIndex { $0.boards.contains { $0.id == id } }
    }

    private func adjacentPosition(_ id: BoardID, by delta: Int) -> (desk: Int, board: Int)? {
        guard let desk = deskIndex(containing: id) else { return nil }
        let boards = state.snapshot.den.desks[desk].boards
        guard let group = BoardGroup.containing(id, in: boards),
            let first = group.boards.first, let last = group.boards.last,
            let start = boards.firstIndex(where: { $0.id == first.id }),
            let end = boards.firstIndex(where: { $0.id == last.id })
        else { return nil }
        let destination = delta < 0 ? start - 1 : end + 1
        return boards.indices.contains(destination) ? (desk, destination) : nil
    }

    private func insertionAfterFocus(in index: Int) -> BoardIndex {
        let desk = state.snapshot.den.desks[index]
        let focused = desk.focusedBoardID.flatMap { id in desk.boards.firstIndex { $0.id == id } }
        return .init(rawValue: focused.map { $0 + 1 } ?? desk.boards.endIndex)
    }

    private func focusIfEmpty(_ boardID: BoardID, in index: Int) {
        if state.snapshot.den.desks[index].focusedBoardID == nil {
            writer.update { $0.den.desks[index].focusedBoardID = boardID }
        }
    }

    private func save() {
        guard state.snapshot.activeDrag == nil else { return }
        _ = persist?(state.snapshot.den)
    }
}
