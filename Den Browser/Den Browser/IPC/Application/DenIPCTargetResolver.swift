import DenApplication
import DenDomain
import DenIPCProtocol
import Foundation

struct ResolvedDeskTarget {
    let window: IPCWindowBindings
    let desk: DeskState
    let profileID: ProfileID
}

struct ResolvedBoardTarget {
    let window: IPCWindowBindings
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

    private struct WindowScope {
        let windows: [IPCWindowBindings]
        let profileID: ProfileID?
    }

    static func resolveDesk(
        target: DeskTarget,
        context: DenIPCCallerContext,
        in profileManager: ProfileManager?
    ) -> Result<ResolvedDeskTarget, TargetResolutionError> {
        guard let profileManager else { return .failure(.noActiveDesk) }
        let scope: WindowScope
        switch windowScope(context: context, in: profileManager) {
        case .success(let resolved): scope = resolved
        case .failure(let error): return .failure(error)
        }

        switch target {
        case .explicit(let deskID):
            let deskID = DeskID(deskID)
            for window in scope.windows {
                guard let desk = window.resources.snapshot.den.desks.first(where: { $0.id == deskID }) else {
                    continue
                }
                return resolvedDesk(window: window, desk: desk, in: profileManager)
            }
            return .failure(.noActiveDesk)

        case .automatic:
            if let callerBoardID = context.callerBoardID.map(BoardID.init) {
                for window in scope.windows {
                    guard let indices = window.resources.snapshot.den.boardIndices(for: callerBoardID) else {
                        continue
                    }
                    let desk = window.resources.snapshot.den.desks[indices.deskOffset]
                    return resolvedDesk(window: window, desk: desk, in: profileManager)
                }
            }

            guard let window = profileManager.activeIPCWindow(profileID: scope.profileID),
                let desk = window.resources.snapshot.den.desks.first(where: { $0.id == window.presentedDeskID() })
                    ?? window.resources.snapshot.den.desks.first
            else {
                return .failure(.noActiveDesk)
            }
            return resolvedDesk(window: window, desk: desk, in: profileManager)
        }
    }

    static func resolveBoard(
        target: BoardTarget,
        context: DenIPCCallerContext,
        kind: TargetKind,
        in profileManager: ProfileManager?
    ) -> Result<ResolvedBoardTarget, TargetResolutionError> {
        guard let profileManager else { return .failure(.noTargetBoard(kind.label)) }
        let scope: WindowScope
        switch windowScope(context: context, in: profileManager) {
        case .success(let resolved): scope = resolved
        case .failure(let error): return .failure(error)
        }

        switch target {
        case .explicit(let boardID):
            let boardID = BoardID(boardID)
            for window in scope.windows {
                guard let indices = window.resources.snapshot.den.boardIndices(for: boardID) else { continue }
                let desk = window.resources.snapshot.den.desks[indices.deskOffset]
                let board = desk.boards[indices.boardOffset]
                guard kind.matchesExplicit(board) else {
                    return .failure(.boardNotMatchingKind(boardID.rawValue.uuidString, kind.label))
                }
                return resolvedBoard(window: window, desk: desk, board: board, in: profileManager)
            }
            return .failure(.boardNotFound(boardID.rawValue.uuidString))

        case .automatic:
            if let callerBoardID = context.callerBoardID.map(BoardID.init) {
                guard
                    let owningWindow = scope.windows.first(where: {
                        $0.resources.snapshot.den.boardIndices(for: callerBoardID) != nil
                    }
                    ),
                    let indices = owningWindow.resources.snapshot.den.boardIndices(for: callerBoardID)
                else {
                    return .failure(.noTargetBoard(kind.label))
                }
                let desk = owningWindow.resources.snapshot.den.desks[indices.deskOffset]
                let callerBoard = desk.boards[indices.boardOffset]
                let target: BoardState?
                if kind.matches(callerBoard) {
                    target = callerBoard
                } else {
                    target =
                        desk.boards.dropFirst(indices.boardOffset + 1).first(where: kind.matches)
                        ?? desk.boards.prefix(indices.boardOffset).reversed().first(where: kind.matches)
                }
                guard let target else { return .failure(.noTargetBoard(kind.label)) }
                return resolvedBoard(window: owningWindow, desk: desk, board: target, in: profileManager)
            }

            guard let window = profileManager.activeIPCWindow(profileID: scope.profileID),
                let desk = window.resources.snapshot.den.desks.first(where: { $0.id == window.presentedDeskID() })
                    ?? window.resources.snapshot.den.desks.first
            else {
                return .failure(.noTargetBoard(kind.label))
            }
            let focused = desk.focusedBoardID.flatMap { id in
                desk.boards.first(where: { $0.id == id && kind.matches($0) })
            }
            guard let board = focused ?? desk.boards.first(where: kind.matches) else {
                return .failure(.noTargetBoard(kind.label))
            }
            return resolvedBoard(window: window, desk: desk, board: board, in: profileManager)
        }
    }

    private static func windowScope(
        context: DenIPCCallerContext,
        in profileManager: ProfileManager
    ) -> Result<WindowScope, TargetResolutionError> {
        guard let rawProfileID = context.profileID else {
            return .success(WindowScope(windows: profileManager.ipcWindows, profileID: nil))
        }
        let profileID = ProfileID(rawProfileID)
        guard profileManager.profile(id: profileID) != nil else {
            return .failure(.profileNotFound(rawProfileID.uuidString))
        }
        guard profileManager.hasWindow(for: profileID) else {
            return .failure(.profileHasNoActiveWindow(rawProfileID.uuidString))
        }
        return .success(
            WindowScope(windows: profileManager.ipcWindows.filter { $0.profileID == profileID }, profileID: profileID))
    }

    private static func resolvedDesk(
        window: IPCWindowBindings,
        desk: DeskState,
        in profileManager: ProfileManager
    ) -> Result<ResolvedDeskTarget, TargetResolutionError> {
        guard let resolved = resolvedWindow(for: window, deskID: desk.id, in: profileManager) else {
            return .failure(.targetProfileUnavailable)
        }
        return .success(ResolvedDeskTarget(window: resolved.window, desk: desk, profileID: resolved.profileID))
    }

    private static func resolvedBoard(
        window: IPCWindowBindings,
        desk: DeskState,
        board: BoardState,
        in profileManager: ProfileManager
    ) -> Result<ResolvedBoardTarget, TargetResolutionError> {
        guard let resolved = resolvedWindow(for: window, deskID: desk.id, in: profileManager) else {
            return .failure(.targetProfileUnavailable)
        }
        return .success(
            ResolvedBoardTarget(window: resolved.window, board: board, profileID: resolved.profileID))
    }

    private static func resolvedWindow(
        for window: IPCWindowBindings,
        deskID: DeskID,
        in profileManager: ProfileManager
    ) -> (window: IPCWindowBindings, profileID: ProfileID)? {
        guard profileManager.profile(id: window.profileID) != nil else { return nil }
        let targetWindow =
            profileManager.ipcWindows.first {
                $0.profileID == window.profileID && $0.presentedDeskID() == deskID
            } ?? profileManager.activeIPCWindow(profileID: window.profileID) ?? window
        return (targetWindow, window.profileID)
    }
}
