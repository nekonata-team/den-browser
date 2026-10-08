import DenDomain
import DenIPCProtocol
import Foundation

struct ResolvedDeskTarget {
    let store: DenStore
    let desk: DeskState
    let profileID: ProfileID
}

struct ResolvedBoardTarget {
    let store: DenStore
    let desk: DeskState
    let board: BoardState
    let profileID: ProfileID
}

@MainActor
enum DenIPCTargetResolver {
    enum TargetKind {
        case any
        case web
        case terminal
        case inspection

        func matches(_ board: BoardState) -> Bool {
            switch self {
            case .any: !board.isInspection
            case .web: board.isWeb
            case .terminal: board.isTerminal
            case .inspection: board.isInspection
            }
        }

        func matchesExplicit(_ board: BoardState) -> Bool {
            switch self {
            case .any: true
            case .web, .terminal, .inspection: matches(board)
            }
        }

        var label: String {
            switch self {
            case .any: ""
            case .web: "Web"
            case .terminal: "Terminal"
            case .inspection: "Inspection"
            }
        }
    }

    enum TargetResolutionError: Error, LocalizedError, Equatable {
        case profileNotFound(String)
        case profileHasNoActiveWindow(String)
        case boardNotFound(String)
        case boardNotMatchingKind(String, String)
        case noTargetBoard(String)
        case noActiveDesk
        case targetProfileUnavailable

        var errorDescription: String? {
            switch self {
            case .profileNotFound(let id):
                "Profile not found: \(id)"
            case .profileHasNoActiveWindow(let id):
                "Profile '\(id)' has no active window"
            case .boardNotFound(let id):
                "Board not found: \(id)"
            case .boardNotMatchingKind(let id, let kind):
                "Board '\(id)' is not a \(kind) Board"
            case .noTargetBoard(let kind):
                kind.isEmpty ? "No target Board found" : "No target \(kind) Board found"
            case .noActiveDesk:
                "No active Desk found"
            case .targetProfileUnavailable:
                "Target Profile no longer exists"
            }
        }
    }

    private struct StoreScope {
        let stores: [DenStore]
        let profileID: ProfileID?
    }

    static func resolveDesk(
        target: DeskTarget,
        context: DenIPCCallerContext,
        in profileManager: ProfileManager?
    ) -> Result<ResolvedDeskTarget, TargetResolutionError> {
        guard let profileManager else { return .failure(.noActiveDesk) }
        let scope: StoreScope
        switch storeScope(context: context, in: profileManager) {
        case .success(let resolved): scope = resolved
        case .failure(let error): return .failure(error)
        }

        switch target {
        case .explicit(let deskID):
            let deskID = DeskID(deskID)
            for store in scope.stores {
                guard let desk = store.state.desks.first(where: { $0.id == deskID }) else { continue }
                return resolvedDesk(store: store, desk: desk, in: profileManager)
            }
            return .failure(.noActiveDesk)

        case .automatic:
            if let callerBoardID = context.callerBoardID.map(BoardID.init) {
                for store in scope.stores {
                    guard let indices = store.boardIndices(for: callerBoardID) else { continue }
                    let desk = store.state.desks[indices.desk]
                    return resolvedDesk(store: store, desk: desk, in: profileManager)
                }
            }

            let baseStore: DenStore?
            if let profileID = scope.profileID {
                baseStore = profileManager.store(forProfileID: profileID)
            } else {
                baseStore = profileManager.activeStore()
            }
            guard let store = baseStore,
                let desk = store.state.desks.first(where: { $0.id == store.presentedDeskID })
                    ?? store.state.desks.first
            else {
                return .failure(.noActiveDesk)
            }
            return resolvedDesk(store: store, desk: desk, in: profileManager)
        }
    }

    static func resolveBoard(
        target: BoardTarget,
        context: DenIPCCallerContext,
        kind: TargetKind,
        in profileManager: ProfileManager?
    ) -> Result<ResolvedBoardTarget, TargetResolutionError> {
        guard let profileManager else { return .failure(.noTargetBoard(kind.label)) }
        let scope: StoreScope
        switch storeScope(context: context, in: profileManager) {
        case .success(let resolved): scope = resolved
        case .failure(let error): return .failure(error)
        }

        switch target {
        case .explicit(let boardID):
            let boardID = BoardID(boardID)
            for store in scope.stores {
                guard let indices = store.boardIndices(for: boardID) else { continue }
                let desk = store.state.desks[indices.desk]
                let board = desk.boards[indices.board]
                guard kind.matchesExplicit(board) else {
                    return .failure(.boardNotMatchingKind(boardID.rawValue.uuidString, kind.label))
                }
                return resolvedBoard(store: store, desk: desk, board: board, in: profileManager)
            }
            return .failure(.boardNotFound(boardID.rawValue.uuidString))

        case .automatic:
            if let callerBoardID = context.callerBoardID.map(BoardID.init) {
                guard let owningStore = scope.stores.first(where: { $0.boardIndices(for: callerBoardID) != nil }),
                    let indices = owningStore.boardIndices(for: callerBoardID)
                else {
                    return .failure(.noTargetBoard(kind.label))
                }
                let desk = owningStore.state.desks[indices.desk]
                let callerBoard = desk.boards[indices.board]
                let target: BoardState?
                if kind.matches(callerBoard) {
                    target = callerBoard
                } else {
                    target =
                        desk.boards.dropFirst(indices.board + 1).first(where: kind.matches)
                        ?? desk.boards.prefix(indices.board).reversed().first(where: kind.matches)
                }
                guard let target else { return .failure(.noTargetBoard(kind.label)) }
                return resolvedBoard(store: owningStore, desk: desk, board: target, in: profileManager)
            }

            let baseStore: DenStore?
            if let profileID = scope.profileID {
                baseStore = profileManager.store(forProfileID: profileID)
            } else {
                baseStore = profileManager.activeStore()
            }
            guard let store = baseStore,
                let desk = store.state.desks.first(where: { $0.id == store.presentedDeskID })
                    ?? store.state.desks.first
            else {
                return .failure(.noTargetBoard(kind.label))
            }
            let focused = desk.focusedBoardID.flatMap { id in
                desk.boards.first(where: { $0.id == id && kind.matches($0) })
            }
            guard let board = focused ?? desk.boards.first(where: kind.matches) else {
                return .failure(.noTargetBoard(kind.label))
            }
            return resolvedBoard(store: store, desk: desk, board: board, in: profileManager)
        }
    }

    private static func storeScope(
        context: DenIPCCallerContext,
        in profileManager: ProfileManager
    ) -> Result<StoreScope, TargetResolutionError> {
        guard let rawProfileID = context.profileID else {
            return .success(StoreScope(stores: profileManager.allStores, profileID: nil))
        }
        let profileID = ProfileID(rawProfileID)
        guard profileManager.profile(id: profileID) != nil else {
            return .failure(.profileNotFound(rawProfileID.uuidString))
        }
        guard profileManager.hasWindow(for: profileID) else {
            return .failure(.profileHasNoActiveWindow(rawProfileID.uuidString))
        }
        return .success(StoreScope(stores: profileManager.stores(for: profileID), profileID: profileID))
    }

    private static func resolvedDesk(
        store: DenStore,
        desk: DeskState,
        in profileManager: ProfileManager
    ) -> Result<ResolvedDeskTarget, TargetResolutionError> {
        guard let resolved = resolvedStore(for: store, deskID: desk.id, in: profileManager) else {
            return .failure(.targetProfileUnavailable)
        }
        return .success(ResolvedDeskTarget(store: resolved.store, desk: desk, profileID: resolved.profileID))
    }

    private static func resolvedBoard(
        store: DenStore,
        desk: DeskState,
        board: BoardState,
        in profileManager: ProfileManager
    ) -> Result<ResolvedBoardTarget, TargetResolutionError> {
        guard let resolved = resolvedStore(for: store, deskID: desk.id, in: profileManager) else {
            return .failure(.targetProfileUnavailable)
        }
        return .success(
            ResolvedBoardTarget(store: resolved.store, desk: desk, board: board, profileID: resolved.profileID))
    }

    private static func resolvedStore(
        for store: DenStore,
        deskID: DeskID,
        in profileManager: ProfileManager
    ) -> (store: DenStore, profileID: ProfileID)? {
        guard let profileID = profileManager.profileID(for: store) else { return nil }
        let targetStore = profileManager.store(for: profileID, presentingDeskID: deskID) ?? store
        return (targetStore, profileID)
    }
}
