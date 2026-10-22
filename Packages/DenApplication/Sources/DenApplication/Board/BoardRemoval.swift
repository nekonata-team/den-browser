import DenDomain

@MainActor
public final class BoardRemoval {
    public static let maximumHistoryCount = 10

    public struct RemovalPlan {
        public let desk: DeskState
        public let removedBoards: [BoardState]
        public let historyEntry: RecentlyRemovedBoard
    }

    public static func planRemoval(
        _ boardID: BoardID,
        from source: DeskState,
        focusNext: Bool = false
    ) -> RemovalPlan? {
        guard let boardOffset = source.boards.firstIndex(where: { $0.id == boardID }) else { return nil }
        let board = source.boards[boardOffset]
        let removedBoards =
            board.isSideBoard
            ? [board]
            : (BoardGroup.containing(board.id, in: source.boards)?.boards ?? [board])
        var desk = source
        for member in removedBoards.reversed() {
            guard let boardOffset = desk.boards.firstIndex(where: { $0.id == member.id }) else { continue }
            desk.boards.remove(at: boardOffset)
            if desk.anchorBoardID == member.id {
                desk.anchorBoardID = nil
            }
            if desk.boards.isEmpty {
                desk.scrollOffsetX = nil
            }
            guard desk.focusedBoardID == member.id else { continue }
            if focusNext && boardOffset < desk.boards.count {
                desk.focusedBoardID = desk.boards[boardOffset].id
            } else if boardOffset > 0 {
                desk.focusedBoardID = desk.boards[boardOffset - 1].id
            } else {
                desk.focusedBoardID = desk.boards.first?.id
            }
        }
        return RemovalPlan(
            desk: desk,
            removedBoards: removedBoards,
            historyEntry: RecentlyRemovedBoard(
                board: board,
                sideBoard: removedBoards.first(where: { $0.id != board.id }),
                sourceDeskID: source.id,
                sourceBoardIndex: BoardIndex(rawValue: boardOffset)))
    }

    public enum Notice {
        case suppressMutationAnimation
        case prepareRemoval(BoardOperationOrigin)
        case removed(source: DeskState, plan: RemovalPlan)
        case restored(board: BoardState, deskID: DeskID, present: Bool)
    }

    public enum RestoreResult {
        case restored(BoardID)
        case existingTutorial(BoardID)
        case rejected(BoardRestoration.Failure)
        case emptyHistory
    }

    private let store: DenStateStore
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?

    public init(store: DenStateStore, writer: DenStateWriter, persist: ((DenState) -> Bool)? = nil) {
        self.store = store
        self.writer = writer
        self.persist = persist
    }

    @discardableResult
    public func remove(
        _ boardID: BoardID, presentedDeskID: DeskID, focusNext: Bool = false,
        origin: BoardOperationOrigin = .interactive, notify: (Notice) -> Void
    ) -> Bool {
        guard let deskIndex = store.snapshot.den.desks.firstIndex(where: { $0.boards.contains { $0.id == boardID } })
        else { return false }
        let source = store.snapshot.den.desks[deskIndex]
        let background = origin == .cli && source.id == presentedDeskID && source.focusedBoardID != boardID
        if background {
            notify(.suppressMutationAnimation)
            notify(.prepareRemoval(origin))
        }
        guard let removal = Self.planRemoval(boardID, from: source, focusNext: focusNext) else { return false }
        writer.update {
            $0.den.desks[deskIndex] = removal.desk
            $0.recentlyRemovedBoards.insert(removal.historyEntry, at: 0)
            if $0.recentlyRemovedBoards.count > Self.maximumHistoryCount { $0.recentlyRemovedBoards.removeLast() }
        }
        notify(.removed(source: source, plan: removal))
        let removedIDs = Set(removal.removedBoards.map(\.id))
        if case .board(let id) = store.snapshot.activeDrag, removedIDs.contains(id) {
            writer.update { $0.activeDrag = nil }
        }
        save()
        return true
    }

    public func restore(presentedDeskID: DeskID, present: Bool = true, notify: (Notice) -> Void) -> RestoreResult {
        guard let history = store.snapshot.recentlyRemovedBoards.first else { return .emptyHistory }
        switch BoardRestoration.restore(history, in: store.snapshot.den.desks, presentedDeskID: presentedDeskID) {
        case .focusExistingTutorial(let id):
            writer.update { $0.recentlyRemovedBoards.removeFirst() }
            return .existingTutorial(id)
        case .rejected(let failure):
            return .rejected(failure)
        case .restored(let deskIndex, let desk):
            writer.update { $0.den.desks[deskIndex.rawValue] = desk }
            notify(.restored(board: history.board, deskID: desk.id, present: present))
            writer.update { $0.recentlyRemovedBoards.removeFirst() }
            save()
            return .restored(history.board.id)
        }
    }

    private func save() {
        guard store.snapshot.activeDrag == nil else { return }
        _ = persist?(store.snapshot.den)
    }
}
