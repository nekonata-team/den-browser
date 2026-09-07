import Foundation
import WebKit

@MainActor
final class DenIPCService {
    static let shared = DenIPCService()

    private var server: DenSocketServer?
    private weak var profileManager: ProfileManager?

    func start(profileManager: ProfileManager) {
        self.profileManager = profileManager
        let server = DenSocketServer()
        self.server = server

        do {
            try server.start { [weak self] data in
                await self?.handleRawRequest(data) ?? Data()
            }
        } catch {
            print("[DenIPCService] Failed to start server: \(error)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
    }

    private func handleRawRequest(_ data: Data) async -> Data {
        let response: DenIPCResponse
        do {
            let request = try JSONDecoder().decode(DenIPCRequest.self, from: data)
            response = await handleRequest(request)
        } catch {
            response = DenIPCResponse.failure("Invalid JSON request: \(error.localizedDescription)")
        }

        var responseData = (try? JSONEncoder().encode(response)) ?? Data()
        responseData.append(UInt8(ascii: "\n"))
        return responseData
    }

    private func handleRequest(_ request: DenIPCRequest) async -> DenIPCResponse {
        switch request.command.lowercased() {
        case "sheet.open":
            guard let urlString = request.args.first, !urlString.isEmpty else {
                return .failure("Usage: den sheet open <url>")
            }
            guard let (store, board) = resolveTargetWebBoard(request: request) else {
                return .failure("No Web Board found. Use 'den board new <url>' to create a new board.")
            }
            guard let url = URL(string: urlString) ?? URL(string: "https://" + urlString) else {
                return .failure("Invalid URL: \(urlString)")
            }
            let runtime = store.runtime(for: board)
            runtime.load(url)
            return .success("Navigated to \(url.absoluteString)")

        case "sheet.reload":
            guard let (store, board) = resolveTargetWebBoard(request: request) else {
                return .failure("No Web Board found")
            }
            let runtime = store.runtime(for: board)
            runtime.webView.reload()
            return .success("Reloaded")

        case "sheet.url":
            guard let (store, board) = resolveTargetWebBoard(request: request) else {
                return .failure("No Web Board found")
            }
            let runtime = store.runtime(for: board)
            let currentURL = runtime.webView.url?.absoluteString ?? board.currentSheetURL?.absoluteString ?? ""
            return .success(currentURL)

        case "sheet.eval":
            let script = request.args.joined(separator: " ")
            guard !script.isEmpty else {
                return .failure("Usage: den sheet eval <javascript>")
            }
            guard let (store, board) = resolveTargetWebBoard(request: request) else {
                return .failure("No Web Board found")
            }
            let runtime = store.runtime(for: board)
            do {
                let evalResult = try await runtime.webView.evaluateJavaScript(script)
                if let evalResult {
                    return .success("\(evalResult)")
                }
                return .success("undefined")
            } catch {
                return .failure("JavaScript error: \(error.localizedDescription)")
            }

        case "sheet.text":
            guard let (store, board) = resolveTargetWebBoard(request: request) else {
                return .failure("No Web Board found")
            }
            let runtime = store.runtime(for: board)
            do {
                let evalResult = try await runtime.webView.evaluateJavaScript("document.body.innerText")
                return .success("\(evalResult ?? "")")
            } catch {
                return .failure("Failed to get text: \(error.localizedDescription)")
            }

        case "board.list":
            guard let (_, desk) = resolveStoreAndDesk(callerBoardID: request.callerBoardID) else {
                return .failure("No active Desk")
            }
            let list = desk.boards.map { currentBoard in
                "[\(currentBoard.isTerminal ? "terminal" : "web")] \(currentBoard.id.uuidString) - \(currentBoard.label)"
            }.joined(separator: "\n")
            return .success(list)

        case "board.new":
            guard let urlString = request.args.first, !urlString.isEmpty else {
                return .failure("Usage: den board new <url>")
            }
            guard let (store, _) = resolveStoreAndDesk(callerBoardID: request.callerBoardID) else {
                return .failure("No active store found")
            }
            let callerID = request.callerBoardID.flatMap(UUID.init)
            let success = store.openBoard(input: urlString, afterBoardID: callerID ?? store.focusedBoard?.id)
            if success {
                return .success("Opened new Board with \(urlString)")
            }
            return .failure("Failed to open board with \(urlString)")

        case "desk.list":
            guard let (store, _) = resolveStoreAndDesk(callerBoardID: request.callerBoardID) else {
                return .failure("No active store found")
            }
            let presentedID = store.presentedDeskID
            let list = store.state.desks.map { currentDesk in
                let mark = currentDesk.id == presentedID ? "*" : " "
                return
                    "\(mark) \(currentDesk.id.uuidString) - \(currentDesk.label) (\(currentDesk.boards.count) boards)"
            }.joined(separator: "\n")
            return .success(list)

        default:
            return .failure("Unknown command: \(request.command)")
        }
    }

    private func resolveStoreAndDesk(callerBoardID: String?) -> (DenStore, DeskState)? {
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

    private func resolveTargetWebBoard(request: DenIPCRequest) -> (DenStore, BoardState)? {
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
            if let (store, callerDesk) = resolveStoreAndDesk(callerBoardID: callerString),
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
}
