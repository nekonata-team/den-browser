import DenDomain
import DenIPCProtocol
import Foundation

struct ResolvedDeskTarget {
    let controller: DenController
    let desk: DeskState
    let profileID: ProfileID
}

struct ResolvedBoardTarget {
    let controller: DenController
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

    private struct ControllerScope {
        let controllers: [DenController]
        let profileID: ProfileID?
    }

    static func resolveDesk(
        target: DeskTarget,
        context: DenIPCCallerContext,
        in profileManager: ProfileManager?
    ) -> Result<ResolvedDeskTarget, TargetResolutionError> {
        guard let profileManager else { return .failure(.noActiveDesk) }
        let scope: ControllerScope
        switch controllerScope(context: context, in: profileManager) {
        case .success(let resolved): scope = resolved
        case .failure(let error): return .failure(error)
        }

        switch target {
        case .explicit(let deskID):
            let deskID = DeskID(deskID)
            for controller in scope.controllers {
                guard let desk = controller.state.desks.first(where: { $0.id == deskID }) else { continue }
                return resolvedDesk(controller: controller, desk: desk, in: profileManager)
            }
            return .failure(.noActiveDesk)

        case .automatic:
            if let callerBoardID = context.callerBoardID.map(BoardID.init) {
                for controller in scope.controllers {
                    guard let indices = controller.boardIndices(for: callerBoardID) else { continue }
                    let desk = controller.state.desks[indices.deskOffset]
                    return resolvedDesk(controller: controller, desk: desk, in: profileManager)
                }
            }

            let baseController: DenController?
            if let profileID = scope.profileID {
                baseController = profileManager.controller(forProfileID: profileID)
            } else {
                baseController = profileManager.activeController()
            }
            guard let controller = baseController,
                let desk = controller.state.desks.first(where: { $0.id == controller.presentedDeskID })
                    ?? controller.state.desks.first
            else {
                return .failure(.noActiveDesk)
            }
            return resolvedDesk(controller: controller, desk: desk, in: profileManager)
        }
    }

    static func resolveBoard(
        target: BoardTarget,
        context: DenIPCCallerContext,
        kind: TargetKind,
        in profileManager: ProfileManager?
    ) -> Result<ResolvedBoardTarget, TargetResolutionError> {
        guard let profileManager else { return .failure(.noTargetBoard(kind.label)) }
        let scope: ControllerScope
        switch controllerScope(context: context, in: profileManager) {
        case .success(let resolved): scope = resolved
        case .failure(let error): return .failure(error)
        }

        switch target {
        case .explicit(let boardID):
            let boardID = BoardID(boardID)
            for controller in scope.controllers {
                guard let indices = controller.boardIndices(for: boardID) else { continue }
                let desk = controller.state.desks[indices.deskOffset]
                let board = desk.boards[indices.boardOffset]
                guard kind.matchesExplicit(board) else {
                    return .failure(.boardNotMatchingKind(boardID.rawValue.uuidString, kind.label))
                }
                return resolvedBoard(controller: controller, desk: desk, board: board, in: profileManager)
            }
            return .failure(.boardNotFound(boardID.rawValue.uuidString))

        case .automatic:
            if let callerBoardID = context.callerBoardID.map(BoardID.init) {
                guard
                    let owningController = scope.controllers.first(where: { $0.boardIndices(for: callerBoardID) != nil }
                    ),
                    let indices = owningController.boardIndices(for: callerBoardID)
                else {
                    return .failure(.noTargetBoard(kind.label))
                }
                let desk = owningController.state.desks[indices.deskOffset]
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
                return resolvedBoard(controller: owningController, desk: desk, board: target, in: profileManager)
            }

            let baseController: DenController?
            if let profileID = scope.profileID {
                baseController = profileManager.controller(forProfileID: profileID)
            } else {
                baseController = profileManager.activeController()
            }
            guard let controller = baseController,
                let desk = controller.state.desks.first(where: { $0.id == controller.presentedDeskID })
                    ?? controller.state.desks.first
            else {
                return .failure(.noTargetBoard(kind.label))
            }
            let focused = desk.focusedBoardID.flatMap { id in
                desk.boards.first(where: { $0.id == id && kind.matches($0) })
            }
            guard let board = focused ?? desk.boards.first(where: kind.matches) else {
                return .failure(.noTargetBoard(kind.label))
            }
            return resolvedBoard(controller: controller, desk: desk, board: board, in: profileManager)
        }
    }

    private static func controllerScope(
        context: DenIPCCallerContext,
        in profileManager: ProfileManager
    ) -> Result<ControllerScope, TargetResolutionError> {
        guard let rawProfileID = context.profileID else {
            return .success(ControllerScope(controllers: profileManager.allControllers, profileID: nil))
        }
        let profileID = ProfileID(rawProfileID)
        guard profileManager.profile(id: profileID) != nil else {
            return .failure(.profileNotFound(rawProfileID.uuidString))
        }
        guard profileManager.hasWindow(for: profileID) else {
            return .failure(.profileHasNoActiveWindow(rawProfileID.uuidString))
        }
        return .success(ControllerScope(controllers: profileManager.controllers(for: profileID), profileID: profileID))
    }

    private static func resolvedDesk(
        controller: DenController,
        desk: DeskState,
        in profileManager: ProfileManager
    ) -> Result<ResolvedDeskTarget, TargetResolutionError> {
        guard let resolved = resolvedController(for: controller, deskID: desk.id, in: profileManager) else {
            return .failure(.targetProfileUnavailable)
        }
        return .success(ResolvedDeskTarget(controller: resolved.controller, desk: desk, profileID: resolved.profileID))
    }

    private static func resolvedBoard(
        controller: DenController,
        desk: DeskState,
        board: BoardState,
        in profileManager: ProfileManager
    ) -> Result<ResolvedBoardTarget, TargetResolutionError> {
        guard let resolved = resolvedController(for: controller, deskID: desk.id, in: profileManager) else {
            return .failure(.targetProfileUnavailable)
        }
        return .success(
            ResolvedBoardTarget(controller: resolved.controller, board: board, profileID: resolved.profileID))
    }

    private static func resolvedController(
        for controller: DenController,
        deskID: DeskID,
        in profileManager: ProfileManager
    ) -> (controller: DenController, profileID: ProfileID)? {
        guard let profileID = profileManager.profileID(for: controller) else { return nil }
        let targetController = profileManager.controller(for: profileID, presentingDeskID: deskID) ?? controller
        return (targetController, profileID)
    }
}
