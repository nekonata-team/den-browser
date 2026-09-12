import Foundation

@MainActor
enum DenIPCTargetResolver {
    enum TargetKind {
        case any
        case web
        case terminal

        func matches(_ board: BoardState) -> Bool {
            switch self {
            case .any: return true
            case .web: return !board.isTerminal
            case .terminal: return board.isTerminal
            }
        }

        var label: String {
            switch self {
            case .any: ""
            case .web: "Web"
            case .terminal: "Terminal"
            }
        }
    }

    enum TargetResolutionError: Error, LocalizedError, Equatable {
        case invalidProfileID(String)
        case profileNotFound(String)
        case profileHasNoActiveWindow(String)
        case invalidBoardID(String)
        case boardNotFound(String)
        case boardNotMatchingKind(String, String)
        case noTargetBoard(String)
        case noActiveDesk

        var errorDescription: String? {
            switch self {
            case .invalidProfileID(let id):
                "Invalid profile ID: \(id)"
            case .profileNotFound(let id):
                "Profile not found: \(id)"
            case .profileHasNoActiveWindow(let id):
                "Profile '\(id)' has no active window"
            case .invalidBoardID(let id):
                "Invalid board ID: \(id)"
            case .boardNotFound(let id):
                "Board not found: \(id)"
            case .boardNotMatchingKind(let id, let kind):
                "Board '\(id)' is not a \(kind) Board"
            case .noTargetBoard(let kind):
                kind.isEmpty ? "No target Board found" : "No target \(kind) Board found"
            case .noActiveDesk:
                "No active Desk found"
            }
        }
    }

    static func resolveStoreAndDesk(
        callerBoardID: String?,
        in profileManager: ProfileManager?
    ) -> (DenStore, DeskState)? {
        let request = DenIPCRequest(command: .desk(.list), callerBoardID: callerBoardID)
        return try? resolveStoreAndDesk(request: request, in: profileManager).get()
    }

    static func resolveStoreAndDesk(
        request: DenIPCRequest,
        in profileManager: ProfileManager?
    ) -> Result<(DenStore, DeskState), TargetResolutionError> {
        // 1. Explicit profile ID
        if let profileIDString = request.profileID {
            guard let profileUUID = UUID(uuidString: profileIDString) else {
                return .failure(.invalidProfileID(profileIDString))
            }
            guard profileManager?.profile(id: profileUUID) != nil else {
                return .failure(.profileNotFound(profileIDString))
            }
            guard let store = profileManager?.store(forProfileID: profileUUID) else {
                return .failure(.profileHasNoActiveWindow(profileIDString))
            }
            let targetDesk: DeskState?
            if let deskIDString = request.deskID, let deskUUID = UUID(uuidString: deskIDString) {
                targetDesk = store.state.desks.first(where: { $0.id == deskUUID })
            } else if let callerBoardID = request.callerBoardID,
                let callerID = UUID(uuidString: callerBoardID),
                let indices = store.boardIndices(for: callerID)
            {
                targetDesk = store.state.desks[indices.desk]
            } else {
                targetDesk =
                    store.state.desks.first(where: { $0.id == store.presentedDeskID })
                    ?? store.state.desks.first
            }
            guard let desk = targetDesk else {
                return .failure(.noActiveDesk)
            }
            return .success((store, desk))
        }

        // 2. Caller board ID across all stores
        let allStores = profileManager?.allStores ?? []
        if let callerBoardID = request.callerBoardID, let callerID = UUID(uuidString: callerBoardID) {
            let matches = allStores.compactMap { store -> (DenStore, DeskState)? in
                guard let indices = store.boardIndices(for: callerID) else { return nil }
                return (store, store.state.desks[indices.desk])
            }
            if let presented = matches.first(where: { $0.0.presentedDeskID == $0.1.id }) {
                return .success(presented)
            }
            if let first = matches.first {
                return .success(first)
            }
        }

        // 3. Fallback to activeStore
        guard let store = profileManager?.activeStore(),
            let desk = store.state.desks.first(where: { $0.id == store.presentedDeskID })
                ?? store.state.desks.first
        else {
            return .failure(.noActiveDesk)
        }
        return .success((store, desk))
    }

    static func resolveTargetWebBoard(
        request: DenIPCRequest,
        in profileManager: ProfileManager?
    ) -> (DenStore, BoardState)? {
        try? resolveTargetBoard(request: request, in: profileManager, kind: .web).get()
    }

    static func resolveTargetWebBoardResult(
        request: DenIPCRequest,
        in profileManager: ProfileManager?
    ) -> Result<(DenStore, BoardState), TargetResolutionError> {
        resolveTargetBoard(request: request, in: profileManager, kind: .web)
    }

    static func resolveTargetTerminalBoard(
        request: DenIPCRequest,
        in profileManager: ProfileManager?
    ) -> (DenStore, BoardState)? {
        try? resolveTargetBoard(request: request, in: profileManager, kind: .terminal).get()
    }

    static func resolveTargetTerminalBoardResult(
        request: DenIPCRequest,
        in profileManager: ProfileManager?
    ) -> Result<(DenStore, BoardState), TargetResolutionError> {
        resolveTargetBoard(request: request, in: profileManager, kind: .terminal)
    }

    static func resolveTargetAnyBoardResult(
        request: DenIPCRequest,
        in profileManager: ProfileManager?
    ) -> Result<(DenStore, BoardState), TargetResolutionError> {
        resolveTargetBoard(request: request, in: profileManager, kind: .any)
    }

    private static func resolveTargetBoard(
        request: DenIPCRequest,
        in profileManager: ProfileManager?,
        kind: TargetKind
    ) -> Result<(DenStore, BoardState), TargetResolutionError> {
        let kindLabel = kind.label

        // Explicit profile ID scoping
        if let profileIDString = request.profileID {
            guard let profileUUID = UUID(uuidString: profileIDString) else {
                return .failure(.invalidProfileID(profileIDString))
            }
            guard profileManager?.profile(id: profileUUID) != nil else {
                return .failure(.profileNotFound(profileIDString))
            }
            guard let store = profileManager?.store(forProfileID: profileUUID) else {
                return .failure(.profileHasNoActiveWindow(profileIDString))
            }

            if let idString = request.boardID {
                guard let id = UUID(uuidString: idString) else {
                    return .failure(.invalidBoardID(idString))
                }
                guard let indices = store.boardIndices(for: id) else {
                    return .failure(.boardNotFound(idString))
                }
                let board = store.state.desks[indices.desk].boards[indices.board]
                guard kind.matches(board) else {
                    return .failure(.boardNotMatchingKind(idString, kindLabel))
                }
                return .success((store, board))
            }

            if let callerBoardID = request.callerBoardID,
                let callerID = UUID(uuidString: callerBoardID),
                let indices = store.boardIndices(for: callerID)
            {
                let callerDesk = store.state.desks[indices.desk]
                let callerIndex = indices.board
                let callerBoard = callerDesk.boards[callerIndex]
                if kind.matches(callerBoard) {
                    return .success((store, callerBoard))
                }
                let right = callerDesk.boards.dropFirst(callerIndex + 1).first(where: kind.matches)
                let left = callerDesk.boards.prefix(callerIndex).reversed().first(where: kind.matches)
                if let target = right ?? left {
                    return .success((store, target))
                }
            }

            guard
                let desk = store.state.desks.first(where: { $0.id == store.presentedDeskID })
                    ?? store.state.desks.first
            else {
                return .failure(.noTargetBoard(kindLabel))
            }

            let focused = desk.focusedBoardID.flatMap { id in
                desk.boards.first(where: { $0.id == id && kind.matches($0) })
            }
            guard let target = focused ?? desk.boards.first(where: kind.matches) else {
                return .failure(.noTargetBoard(kindLabel))
            }
            return .success((store, target))
        }

        let allStores = profileManager?.allStores ?? []

        // 1. Explicit board ID across all stores (must not fall back if specified)
        if let idString = request.boardID {
            guard let id = UUID(uuidString: idString) else {
                return .failure(.invalidBoardID(idString))
            }
            for store in allStores {
                guard let indices = store.boardIndices(for: id) else { continue }
                let desk = store.state.desks[indices.desk]
                let board = desk.boards[indices.board]
                guard kind.matches(board) else {
                    return .failure(.boardNotMatchingKind(idString, kindLabel))
                }
                let presenting = allStores.first(where: { $0.presentedDeskID == desk.id }) ?? store
                return .success((presenting, board))
            }
            return .failure(.boardNotFound(idString))
        }

        // 2. Ambient resolution relative to callerBoardID (scans the Desk that currently contains callerBoardID)
        if let callerString = request.callerBoardID {
            guard let callerID = UUID(uuidString: callerString),
                let (store, callerDesk) = resolveStoreAndDesk(callerBoardID: callerString, in: profileManager),
                let callerIndex = callerDesk.boards.firstIndex(where: { $0.id == callerID })
            else {
                return .failure(.noTargetBoard(kindLabel))
            }
            let callerBoard = callerDesk.boards[callerIndex]
            if kind.matches(callerBoard) {
                return .success((store, callerBoard))
            }
            let right = callerDesk.boards.dropFirst(callerIndex + 1).first(where: kind.matches)
            let left = callerDesk.boards.prefix(callerIndex).reversed().first(where: kind.matches)
            guard let target = right ?? left else {
                return .failure(.noTargetBoard(kindLabel))
            }
            return .success((store, target))
        }

        // 3. Fallback to active/presented Desk (only when executed from external shell without callerBoardID)
        guard let store = profileManager?.activeStore(),
            let desk = store.state.desks.first(where: { $0.id == store.presentedDeskID })
                ?? store.state.desks.first
        else {
            return .failure(.noTargetBoard(kindLabel))
        }

        let focused = desk.focusedBoardID.flatMap { id in
            desk.boards.first(where: { $0.id == id && kind.matches($0) })
        }
        guard let target = focused ?? desk.boards.first(where: kind.matches) else {
            return .failure(.noTargetBoard(kindLabel))
        }
        return .success((store, target))
    }
}
