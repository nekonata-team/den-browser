import DenApplication
import DenDomain
import DenModels
import Foundation

/// Async zmx inspection and shared Board operations; task ownership stays with the invoking window.
@MainActor
struct ZmxBoards {
    struct Window {
        let presentedDeskID: DeskID
        let focusedBoardID: BoardID?
    }

    struct Duplication {
        let source: BoardState
        let suffix: String
        let asSideBoard: Bool
        let focus: Bool
        let width: Double
        let workingDirectory: String
    }

    enum Notice {
        case creation(BoardCreation.Notice)
        case removal(BoardRemoval.Notice)
        case duplicationPanel(String)
        case warning(String)
        case error(String)
        case focusExisting(BoardID)
        case openFailure(String)
    }

    let state: DenStateStore
    let creation: BoardCreation
    let removal: BoardRemoval
    let updates: BoardUpdates

    func open(
        _ sessionName: String, request: InputOpening.Context,
        rootSessionName: (String) -> String?, notify: (Notice) -> Void
    ) -> ZmxSessionOpenResult {
        if let board = state.snapshot.den.desks.lazy.flatMap(\.boards).first(where: { $0.zmxSessionName == sessionName }
        ) {
            updates.recordZmxRoot(rootSessionName(sessionName), for: board.id)
            notify(.focusExisting(board.id))
            return .focusedExistingBoard
        }
        let trimmed = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected }
        let result = creation.open(
            .init(
                input: ":zmx \(trimmed)", width: request.width, target: request.target,
                configuration: request.configuration, zmxRootSessionName: rootSessionName(trimmed)),
            notify: { notify(.creation($0)) })
        switch result {
        case .accepted: return .openedBoard
        case .rejected(let message):
            if let message { notify(.openFailure(message)) }
            return .rejected
        }
    }

    func prepareDuplication(
        _ source: BoardState, client: ZmxClient, window: () -> Window?, notify: (Notice) -> Void
    ) async {
        guard let name = source.zmxSessionName else { return }
        do {
            let root = try await client.resolvedRootSessionName(
                for: name, savedRootSessionName: source.zmxRootSessionName)
            guard !Task.isCancelled, window()?.focusedBoardID == source.id else { return }
            notify(.duplicationPanel(root))
        } catch { return }
    }

    func duplicate(
        _ request: Duplication, client: ZmxClient, window: () -> Window?, notify: (Notice) -> Void
    ) async {
        let source = request.source
        guard let name = source.zmxSessionName else { return }
        do {
            let context = try await client.duplicationContext(
                for: name, savedRootSessionName: source.zmxRootSessionName)
            guard !Task.isCancelled, let current = window() else { return }
            if request.asSideBoard {
                guard
                    let desk = state.snapshot.den.desks.first(where: {
                        $0.boards.contains(where: { $0.id == source.id })
                    }),
                    !desk.boards.contains(where: { $0.sideBoardTargetBoardID == source.id })
                else { return }
            } else {
                guard current.focusedBoardID == source.id else { return }
            }
            let names = state.snapshot.den.desks.flatMap { $0.boards.compactMap(\.zmxSessionName) }
            let session = ZmxSessionNameGenerator.nextName(
                rootSessionName: context.rootSessionName, suffix: request.suffix,
                occupiedNames: context.activeSessionNames.union(names))
            var board = BoardState(
                label: request.asSideBoard ? "Terminal Side Board" : source.label, width: request.width,
                zmxSessionName: session, workingDirectory: request.workingDirectory,
                rootSessionName: context.rootSessionName, customLabel: request.asSideBoard ? nil : source.customLabel)
            if request.asSideBoard { board.role = .sideBoard(targetBoardID: source.id) }
            creation.insert(
                board,
                target: .init(
                    presentedDeskID: current.presentedDeskID, afterBoardID: source.id,
                    focus: request.focus, origin: request.focus ? .interactive : .cli),
                notify: { notify(.creation($0)) })
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, let current = window(),
                request.asSideBoard
                    ? state.snapshot.den.desks.contains(where: { $0.boards.contains(where: { $0.id == source.id }) })
                    : current.focusedBoardID == source.id
            else { return }
            notify(.warning("Could not inspect active zmx sessions: \(error.localizedDescription)"))
        }
    }

    func end(_ name: String, client: ZmxClient, window: () -> Window?, notify: (Notice) -> Void) async {
        do {
            try await client.killSession(name)
            guard !Task.isCancelled, let current = window() else { return }
            let ids = state.snapshot.den.desks.flatMap(\.boards).filter { $0.zmxSessionName == name }.map(\.id)
            for id in ids {
                removal.remove(id, presentedDeskID: current.presentedDeskID, notify: { notify(.removal($0)) })
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, window() != nil else { return }
            notify(.error("Could not end zmx Session '\(name)': \(error.localizedDescription)"))
        }
    }
}
