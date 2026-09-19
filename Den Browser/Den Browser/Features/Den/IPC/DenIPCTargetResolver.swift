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
        guard let profileManager else {
            return .failure(.noActiveDesk)
        }

        let scopedProfileID: UUID?
        if let profileIDString = request.profileID {
            guard let profileUUID = UUID(uuidString: profileIDString) else {
                return .failure(.invalidProfileID(profileIDString))
            }
            guard profileManager.profile(id: profileUUID) != nil else {
                return .failure(.profileNotFound(profileIDString))
            }
            guard profileManager.hasWindow(for: profileUUID) else {
                return .failure(.profileHasNoActiveWindow(profileIDString))
            }
            scopedProfileID = profileUUID
        } else {
            scopedProfileID = nil
        }

        let candidateStores: [DenStore] =
            if let scopedProfileID {
                profileManager.stores(for: scopedProfileID)
            } else {
                profileManager.allStores
            }

        // 1. Explicit desk ID (must not fall back if specified)
        if let deskIDString = request.deskID {
            guard let deskUUID = UUID(uuidString: deskIDString) else {
                return .failure(.noActiveDesk)
            }
            for store in candidateStores {
                guard let desk = store.state.desks.first(where: { $0.id == deskUUID }) else { continue }
                let profileID = profileManager.profileID(for: store)
                let targetStore =
                    profileID.flatMap { profileManager.store(for: $0, presentingDeskID: desk.id) } ?? store
                return .success((targetStore, desk))
            }
            return .failure(.noActiveDesk)
        }

        // 2. Caller board ID
        if let callerBoardID = request.callerBoardID, let callerID = UUID(uuidString: callerBoardID) {
            for store in candidateStores {
                guard let indices = store.boardIndices(for: callerID) else { continue }
                let desk = store.state.desks[indices.desk]
                let profileID = profileManager.profileID(for: store)
                let targetStore =
                    profileID.flatMap { profileManager.store(for: $0, presentingDeskID: desk.id) } ?? store
                return .success((targetStore, desk))
            }
        }

        // 3. Fallback to activeStore
        let baseStore: DenStore?
        if let scopedProfileID {
            baseStore = profileManager.store(forProfileID: scopedProfileID)
        } else {
            baseStore = profileManager.activeStore()
        }

        guard let store = baseStore,
            let desk = store.state.desks.first(where: { $0.id == store.presentedDeskID })
                ?? store.state.desks.first
        else {
            return .failure(.noActiveDesk)
        }
        let profileID = profileManager.profileID(for: store)
        let targetStore = profileID.flatMap { profileManager.store(for: $0, presentingDeskID: desk.id) } ?? store
        return .success((targetStore, desk))
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
        guard let profileManager else {
            return .failure(.noTargetBoard(kindLabel))
        }

        // Profile scoping check if specified
        let scopedProfileID: UUID?
        if let profileIDString = request.profileID {
            guard let profileUUID = UUID(uuidString: profileIDString) else {
                return .failure(.invalidProfileID(profileIDString))
            }
            guard profileManager.profile(id: profileUUID) != nil else {
                return .failure(.profileNotFound(profileIDString))
            }
            guard profileManager.hasWindow(for: profileUUID) else {
                return .failure(.profileHasNoActiveWindow(profileIDString))
            }
            scopedProfileID = profileUUID
        } else {
            scopedProfileID = nil
        }

        let candidateStores: [DenStore] =
            if let scopedProfileID {
                profileManager.stores(for: scopedProfileID)
            } else {
                profileManager.allStores
            }

        // 1. Explicit board ID across stores (must not fall back if specified)
        if let idString = request.boardID {
            guard let id = UUID(uuidString: idString) else {
                return .failure(.invalidBoardID(idString))
            }
            for store in candidateStores {
                guard let indices = store.boardIndices(for: id) else { continue }
                let desk = store.state.desks[indices.desk]
                let board = desk.boards[indices.board]
                guard kind.matches(board) else {
                    return .failure(.boardNotMatchingKind(idString, kindLabel))
                }
                let profileID = profileManager.profileID(for: store)
                let targetStore =
                    profileID.flatMap { profileManager.store(for: $0, presentingDeskID: desk.id) } ?? store
                return .success((targetStore, board))
            }
            return .failure(.boardNotFound(idString))
        }

        // 2. Caller board ID
        if let callerString = request.callerBoardID {
            guard let callerID = UUID(uuidString: callerString) else {
                return .failure(.noTargetBoard(kindLabel))
            }
            guard let owningStore = candidateStores.first(where: { $0.boardIndices(for: callerID) != nil }),
                let indices = owningStore.boardIndices(for: callerID)
            else {
                return .failure(.noTargetBoard(kindLabel))
            }

            let callerDesk = owningStore.state.desks[indices.desk]
            let callerIndex = indices.board
            let callerBoard = callerDesk.boards[callerIndex]

            let profileID = profileManager.profileID(for: owningStore)
            let targetStore =
                profileID.flatMap { profileManager.store(for: $0, presentingDeskID: callerDesk.id) } ?? owningStore

            if kind.matches(callerBoard) {
                return .success((targetStore, callerBoard))
            }
            let right = callerDesk.boards.dropFirst(callerIndex + 1).first(where: kind.matches)
            let left = callerDesk.boards.prefix(callerIndex).reversed().first(where: kind.matches)
            guard let target = right ?? left else {
                return .failure(.noTargetBoard(kindLabel))
            }
            return .success((targetStore, target))
        }

        // 3. Fallback to active/presented Desk
        let baseStore: DenStore?
        if let scopedProfileID {
            baseStore = profileManager.store(forProfileID: scopedProfileID)
        } else {
            baseStore = profileManager.activeStore()
        }

        guard let store = baseStore,
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
        let profileID = profileManager.profileID(for: store)
        let targetStore = profileID.flatMap { profileManager.store(for: $0, presentingDeskID: desk.id) } ?? store
        return .success((targetStore, target))
    }
}
