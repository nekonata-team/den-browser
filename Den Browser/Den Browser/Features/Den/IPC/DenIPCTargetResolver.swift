import Foundation

@MainActor
enum DenIPCTargetResolver {
    enum TargetKind {
        case web
        case terminal

        func matches(_ board: BoardState) -> Bool {
            switch self {
            case .web: return !board.isTerminal
            case .terminal: return board.isTerminal
            }
        }
    }

    static func resolveStoreAndDesk(
        callerBoardID: String?,
        in profileManager: ProfileManager?
    ) -> (DenStore, DeskState)? {
        let allStores = profileManager?.allStores ?? []
        if let callerBoardID, let callerID = UUID(uuidString: callerBoardID) {
            let matches = allStores.compactMap { store -> (DenStore, DeskState)? in
                guard let indices = store.boardIndices(for: callerID) else { return nil }
                return (store, store.state.desks[indices.desk])
            }
            if let presented = matches.first(where: { $0.0.presentedDeskID == $0.1.id }) {
                return presented
            }
            if let first = matches.first {
                return first
            }
        }

        // Default to activeStore
        guard let store = profileManager?.activeStore(),
            let desk = store.state.desks.first(where: { $0.id == store.presentedDeskID })
        else {
            return nil
        }
        return (store, desk)
    }

    static func resolveTargetWebBoard(
        request: DenIPCRequest,
        in profileManager: ProfileManager?
    ) -> (DenStore, BoardState)? {
        resolveTargetBoard(request: request, in: profileManager, kind: .web)
    }

    static func resolveTargetTerminalBoard(
        request: DenIPCRequest,
        in profileManager: ProfileManager?
    ) -> (DenStore, BoardState)? {
        resolveTargetBoard(request: request, in: profileManager, kind: .terminal)
    }

    private static func resolveTargetBoard(
        request: DenIPCRequest,
        in profileManager: ProfileManager?,
        kind: TargetKind
    ) -> (DenStore, BoardState)? {
        let allStores = profileManager?.allStores ?? []

        // 1. Explicit board ID across all stores (must not fall back if specified)
        if let idString = request.boardID {
            guard let id = UUID(uuidString: idString) else { return nil }
            for store in allStores {
                guard let indices = store.boardIndices(for: id) else { continue }
                let desk = store.state.desks[indices.desk]
                let board = desk.boards[indices.board]
                guard kind.matches(board) else { return nil }
                let presenting = allStores.first(where: { $0.presentedDeskID == desk.id }) ?? store
                return (presenting, board)
            }
            return nil
        }

        // 2. Ambient resolution relative to callerBoardID (scans the Desk that currently contains callerBoardID)
        if let callerString = request.callerBoardID {
            guard let callerID = UUID(uuidString: callerString),
                let (store, callerDesk) = resolveStoreAndDesk(callerBoardID: callerString, in: profileManager),
                let callerIndex = callerDesk.boards.firstIndex(where: { $0.id == callerID })
            else {
                return nil
            }
            let callerBoard = callerDesk.boards[callerIndex]
            if kind.matches(callerBoard) {
                return (store, callerBoard)
            }
            let right = callerDesk.boards.dropFirst(callerIndex + 1).first(where: kind.matches)
            let left = callerDesk.boards.prefix(callerIndex).reversed().first(where: kind.matches)
            guard let target = right ?? left else { return nil }
            return (store, target)
        }

        // 3. Fallback to active/presented Desk (only when executed from external shell without callerBoardID)
        guard let store = profileManager?.activeStore(),
            let desk = store.state.desks.first(where: { $0.id == store.presentedDeskID })
        else { return nil }

        let focused = desk.focusedBoardID.flatMap { id in
            desk.boards.first(where: { $0.id == id && kind.matches($0) })
        }
        guard let target = focused ?? desk.boards.first(where: kind.matches) else { return nil }
        return (store, target)
    }
}
