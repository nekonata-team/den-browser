import Foundation

@MainActor
enum DenIPCTargetResolver {
    static func resolveStoreAndDesk(
        callerBoardID: String?,
        in profileManager: ProfileManager?
    ) -> (DenStore, DeskState)? {
        let allStores = profileManager?.allStores ?? []
        if let callerBoardID, let callerID = UUID(uuidString: callerBoardID) {
            // First look for a store where the caller's desk is actively presented (Desk in New Window)
            for store in allStores {
                if let desk = store.state.desks.first(where: { $0.boards.contains(where: { $0.id == callerID }) }),
                    store.presentedDeskID == desk.id
                {
                    return (store, desk)
                }
            }
            // Fallback: any store whose state contains the caller board
            for store in allStores {
                if let desk = store.state.desks.first(where: { $0.boards.contains(where: { $0.id == callerID }) }) {
                    return (store, desk)
                }
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
        let allStores = profileManager?.allStores ?? []

        // 1. Explicit board ID across all stores
        if let idString = request.boardID, let id = UUID(uuidString: idString) {
            for store in allStores {
                for candidateDesk in store.state.desks {
                    if let board = candidateDesk.boards.first(where: { $0.id == id && !$0.isTerminal }) {
                        if let presenting = allStores.first(where: { $0.presentedDeskID == candidateDesk.id }) {
                            return (presenting, board)
                        }
                        return (store, board)
                    }
                }
            }
        }

        // 2. Ambient resolution relative to callerBoardID (scans the Desk that currently contains callerBoardID)
        if let callerString = request.callerBoardID, let callerID = UUID(uuidString: callerString) {
            if let (store, callerDesk) = resolveStoreAndDesk(callerBoardID: callerString, in: profileManager),
                let callerIndex = callerDesk.boards.firstIndex(where: { $0.id == callerID })
            {
                for candidateIndex in (callerIndex + 1)..<callerDesk.boards.count {
                    let candidateBoard = callerDesk.boards[candidateIndex]
                    if !candidateBoard.isTerminal { return (store, candidateBoard) }
                }
                for candidateIndex in (0..<callerIndex).reversed() {
                    let candidateBoard = callerDesk.boards[candidateIndex]
                    if !candidateBoard.isTerminal { return (store, candidateBoard) }
                }
            }
        }

        // 3. Fallback to active/presented Desk
        guard let store = profileManager?.activeStore(),
            let desk = store.state.desks.first(where: { $0.id == store.presentedDeskID })
        else { return nil }

        if let focusedID = desk.focusedBoardID,
            let board = desk.boards.first(where: { $0.id == focusedID && !$0.isTerminal })
        {
            return (store, board)
        }

        if let board = desk.boards.first(where: { !$0.isTerminal }) {
            return (store, board)
        }

        return nil
    }

    static func resolveTargetTerminalBoard(
        request: DenIPCRequest,
        in profileManager: ProfileManager?
    ) -> (DenStore, BoardState)? {
        let allStores = profileManager?.allStores ?? []

        // 1. Explicit board ID across all stores
        if let idString = request.boardID, let id = UUID(uuidString: idString) {
            for store in allStores {
                for candidateDesk in store.state.desks {
                    if let board = candidateDesk.boards.first(where: { $0.id == id && $0.isTerminal }) {
                        if let presenting = allStores.first(where: { $0.presentedDeskID == candidateDesk.id }) {
                            return (presenting, board)
                        }
                        return (store, board)
                    }
                }
            }
        }

        // 2. Ambient resolution relative to callerBoardID
        if let callerString = request.callerBoardID, let callerID = UUID(uuidString: callerString) {
            if let (store, callerDesk) = resolveStoreAndDesk(callerBoardID: callerString, in: profileManager),
                let callerIndex = callerDesk.boards.firstIndex(where: { $0.id == callerID })
            {
                let callerBoard = callerDesk.boards[callerIndex]
                if callerBoard.isTerminal {
                    return (store, callerBoard)
                }
                for candidateIndex in (callerIndex + 1)..<callerDesk.boards.count {
                    let candidateBoard = callerDesk.boards[candidateIndex]
                    if candidateBoard.isTerminal { return (store, candidateBoard) }
                }
                for candidateIndex in (0..<callerIndex).reversed() {
                    let candidateBoard = callerDesk.boards[candidateIndex]
                    if candidateBoard.isTerminal { return (store, candidateBoard) }
                }
            }
        }

        // 3. Fallback to active/presented Desk
        guard let store = profileManager?.activeStore(),
            let desk = store.state.desks.first(where: { $0.id == store.presentedDeskID })
        else { return nil }

        if let focusedID = desk.focusedBoardID,
            let board = desk.boards.first(where: { $0.id == focusedID && $0.isTerminal })
        {
            return (store, board)
        }

        if let board = desk.boards.first(where: { $0.isTerminal }) {
            return (store, board)
        }

        return nil
    }
}
