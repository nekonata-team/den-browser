import DenDomain

@MainActor
public struct BoardMovement {
    private let state: DenStateStore
    private let writer: DenStateWriter

    public init(state: DenStateStore, writer: DenStateWriter) {
        self.state = state
        self.writer = writer
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
            if sourceWasFocused {
                let remaining = snapshot.den.desks[sourceIndex].boards
                snapshot.den.desks[sourceIndex].focusedBoardID =
                    remaining.indices.contains(removedIndex)
                    ? remaining[removedIndex].id
                    : remaining.last?.id
            }
            let targetBoards = snapshot.den.desks[targetIndex].boards
            var insertionIndex = min(max(index.rawValue, 0), targetBoards.count)
            if insertionIndex > 0, insertionIndex < targetBoards.count {
                let precedingGroup = BoardGroup.containing(targetBoards[insertionIndex - 1].id, in: targetBoards)
                let precedingIDs = Set(precedingGroup?.boards.map(\.id) ?? [])
                if let lastMemberIndex = targetBoards.lastIndex(where: { precedingIDs.contains($0.id) }),
                    insertionIndex <= lastMemberIndex
                {
                    insertionIndex = lastMemberIndex + 1
                }
            }
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
}
