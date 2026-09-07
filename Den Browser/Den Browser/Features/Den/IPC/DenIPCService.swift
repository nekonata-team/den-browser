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
        let command = request.command.lowercased()
        if command.hasPrefix("sheet.") {
            return await handleSheetCommand(command, request: request)
        } else if command.hasPrefix("board.") {
            return handleBoardCommand(command, request: request)
        } else if command.hasPrefix("desk.") {
            return handleDeskCommand(command, request: request)
        }
        return .failure("Unknown command: \(request.command)")
    }

    // MARK: - Sheet Commands

    private func handleSheetCommand(_ command: String, request: DenIPCRequest) async -> DenIPCResponse {
        guard let (store, board) = DenIPCTargetResolver.resolveTargetWebBoard(request: request, in: profileManager)
        else {
            if command == "sheet.open" {
                return .failure("No Web Board found. Use 'den board new <url>' to create a new board.")
            }
            return .failure("No Web Board found")
        }
        let runtime = store.runtime(for: board)

        do {
            switch command {
            case "sheet.open":
                guard let urlString = request.args.first, !urlString.isEmpty else {
                    return .failure("Usage: den sheet open <url>")
                }
                guard let url = URL(string: urlString) ?? URL(string: "https://" + urlString) else {
                    return .failure("Invalid URL: \(urlString)")
                }
                runtime.load(url)
                return .success(message: "Navigated to \(url.absoluteString)", url: url.absoluteString)

            case "sheet.reload":
                runtime.webView.reload()
                return .success(message: "Reloaded")

            case "sheet.url":
                let currentURL = runtime.webView.url?.absoluteString ?? board.currentSheetURL?.absoluteString ?? ""
                return .success(url: currentURL)

            case "sheet.eval":
                let script = request.args.joined(separator: " ")
                guard !script.isEmpty else {
                    return .failure("Usage: den sheet eval <javascript>")
                }
                let evalResult = try await runtime.webView.evaluateJavaScript(script)
                if let evalResult {
                    return .success(value: "\(evalResult)")
                }
                return .success(value: "undefined")

            case "sheet.text":
                let evalResult = try await runtime.webView.evaluateJavaScript("document.body.innerText")
                return .success(text: "\(evalResult ?? "")")

            case "sheet.back":
                guard runtime.webView.canGoBack else {
                    return .failure("Cannot go back: no previous page in history")
                }
                runtime.webView.goBack()
                return .success(message: "Navigated back")

            case "sheet.forward":
                guard runtime.webView.canGoForward else {
                    return .failure("Cannot go forward: no forward page in history")
                }
                runtime.webView.goForward()
                return .success(message: "Navigated forward")

            case "sheet.press":
                guard let key = request.args.first, !key.isEmpty else {
                    return .failure("Usage: den sheet press <key>")
                }
                try await SheetInteraction.press(key: key, in: runtime.webView)
                return .success(message: "Pressed \(key)")

            case "sheet.scroll":
                let direction = request.args.first?.lowercased() ?? "down"
                let message = try await SheetInteraction.scroll(direction: direction, in: runtime.webView)
                return .success(message: message)

            case "sheet.wait":
                guard let target = request.args.first, !target.isEmpty else {
                    return .failure("Usage: den sheet wait <duration-or-selector>")
                }
                if let seconds = Double(target), seconds >= 0 {
                    let milliseconds = Int(seconds * 1000)
                    try? await Task.sleep(for: .milliseconds(milliseconds))
                    return .success(message: "Waited \(seconds)s")
                }
                try await SheetInteraction.waitForElement(target: target, in: runtime.webView)
                return .success(message: "Element appeared: \(target)")

            case "sheet.screenshot":
                let image = try await ScreenshotCapture.visibleCurrentSheet(in: runtime.webView)
                let data = try ScreenshotCapture.pngData(for: image)
                let targetURL: URL = {
                    if let path = request.args.first, !path.isEmpty {
                        return URL(fileURLWithPath: path)
                    }
                    let filename = ScreenshotCapture.suggestedFilename(scope: board.label)
                    return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                }()
                try data.write(to: targetURL)
                return .success(screenshotPath: targetURL.path)

            case "sheet.snapshot":
                let interactiveOnly = request.args.contains("-i") || request.args.contains("--interactive")
                let snapshot = try await SheetInteraction.snapshot(
                    in: runtime.webView,
                    interactiveOnly: interactiveOnly
                )
                return .success(snapshot: snapshot)

            case "sheet.click":
                guard let target = request.args.first, !target.isEmpty else {
                    return .failure("Usage: den sheet click <@ref|selector>")
                }
                try await SheetInteraction.click(target: target, in: runtime.webView)
                return .success(message: "Clicked \(target)")

            case "sheet.fill":
                guard request.args.count >= 2 else {
                    return .failure("Usage: den sheet fill <@ref|selector> <value>")
                }
                let target = request.args[0]
                let value = request.args.dropFirst().joined(separator: " ")
                try await SheetInteraction.fill(target: target, value: value, in: runtime.webView)
                return .success(message: "Filled \(target)")

            default:
                return .failure("Unknown sheet command: \(command)")
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Board Commands

    private func handleBoardCommand(_ command: String, request: DenIPCRequest) -> DenIPCResponse {
        switch command {
        case "board.list":
            guard
                let (_, desk) = DenIPCTargetResolver.resolveStoreAndDesk(
                    callerBoardID: request.callerBoardID,
                    in: profileManager
                )
            else {
                return .failure("No active Desk")
            }
            let boards = desk.boards.map { currentBoard in
                DenBoardInfo(
                    id: currentBoard.id.uuidString,
                    type: currentBoard.isTerminal ? "terminal" : "web",
                    label: currentBoard.label,
                    url: currentBoard.currentSheetURL?.absoluteString
                )
            }
            return .success(boards: boards)

        case "board.new":
            guard let urlString = request.args.first(where: { !$0.hasPrefix("-") }), !urlString.isEmpty else {
                return .failure("Usage: den board new <url> [--focus]")
            }
            guard
                let (store, _) = DenIPCTargetResolver.resolveStoreAndDesk(
                    callerBoardID: request.callerBoardID,
                    in: profileManager
                )
            else {
                return .failure("No active store found")
            }
            let shouldFocus = request.args.contains("--focus")
            let callerID = request.callerBoardID.flatMap(UUID.init)
            if let boardID = store.createBoard(
                urlString: urlString,
                afterBoardID: callerID ?? store.focusedBoard?.id,
                focus: shouldFocus
            ) {
                return .success(boardId: boardID.uuidString)
            }
            return .failure("Failed to open board with \(urlString)")

        case "board.close":
            if let idString = request.args.first ?? request.boardID, let targetID = UUID(uuidString: idString) {
                let allStores = profileManager?.allStores ?? []
                for candidateStore in allStores {
                    for desk in candidateStore.state.desks where desk.boards.contains(where: { $0.id == targetID }) {
                        candidateStore.removeBoard(targetID)
                        return .success(
                            message: "Closed Board \(targetID.uuidString)",
                            closedBoardId: targetID.uuidString
                        )
                    }
                }
                return .failure("Board not found: \(idString)")
            }
            guard
                let (store, board) = DenIPCTargetResolver.resolveTargetWebBoard(
                    request: request,
                    in: profileManager
                )
            else {
                return .failure("No target Board to close")
            }
            store.removeBoard(board.id)
            return .success(
                message: "Closed Board \(board.id.uuidString)",
                closedBoardId: board.id.uuidString
            )

        default:
            return .failure("Unknown board command: \(command)")
        }
    }

    // MARK: - Desk Commands

    private func handleDeskCommand(_ command: String, request: DenIPCRequest) -> DenIPCResponse {
        switch command {
        case "desk.list":
            guard
                let (store, _) = DenIPCTargetResolver.resolveStoreAndDesk(
                    callerBoardID: request.callerBoardID,
                    in: profileManager
                )
            else {
                return .failure("No active store found")
            }
            let presentedID = store.presentedDeskID
            let desks = store.state.desks.map { currentDesk in
                DenDeskInfo(
                    id: currentDesk.id.uuidString,
                    label: currentDesk.label,
                    isActive: currentDesk.id == presentedID,
                    boardCount: currentDesk.boards.count
                )
            }
            return .success(desks: desks)

        default:
            return .failure("Unknown desk command: \(command)")
        }
    }
}
