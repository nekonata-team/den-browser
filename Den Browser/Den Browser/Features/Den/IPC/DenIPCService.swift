import Darwin
import Foundation
import WebKit

@MainActor
final class DenIPCService {
    static let shared = DenIPCService()

    private var server: DenSocketServer?
    private weak var profileManager: ProfileManager?

    init(profileManager: ProfileManager? = nil) {
        self.profileManager = profileManager
    }

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

    func handleRequest(_ request: DenIPCRequest) async -> DenIPCResponse {
        switch request.command {
        case .health:
            return .success()
        case .sheet(let command):
            return await handleSheetCommand(command, request: request)
        case .board(let command):
            return handleBoardCommand(command, request: request)
        case .desk(let command):
            return handleDeskCommand(command, request: request)
        case .drawer(let command):
            return handleDrawerCommand(command, request: request)
        case .terminal(let command):
            return handleTerminalCommand(command, request: request)
        }
    }

    // MARK: - Sheet Commands

    private func handleSheetCommand(_ command: DenIPCCommand.Sheet, request: DenIPCRequest) async -> DenIPCResponse {
        guard let (store, board) = DenIPCTargetResolver.resolveTargetWebBoard(request: request, in: profileManager)
        else {
            if command == .open {
                return .failure("No Web Board found. Use 'den board web new <url>' to create a new board.")
            }
            return .failure("No Web Board found")
        }
        let runtime = store.runtime(for: board)

        do {
            switch command {
            case .open:
                guard let urlString = request.args.first, !urlString.isEmpty else {
                    return .failure("Usage: den sheet open <url>")
                }
                guard let url = URL(string: urlString) ?? URL(string: "https://" + urlString) else {
                    return .failure("Invalid URL: \(urlString)")
                }
                runtime.load(url)
                return .success(message: "Navigated to \(url.absoluteString)", url: url.absoluteString)

            case .reload:
                runtime.webView.reload()
                return .success(message: "Reloaded")

            case .url:
                let currentURL = runtime.webView.url?.absoluteString ?? board.currentSheetURL?.absoluteString ?? ""
                return .success(url: currentURL)

            case .eval:
                let script = request.args.joined(separator: " ")
                guard !script.isEmpty else {
                    return .failure("Usage: den sheet eval <javascript>")
                }
                let evalResult = try await runtime.webView.evaluateJavaScript(script)
                if let evalResult {
                    return .success(value: "\(evalResult)")
                }
                return .success(value: "undefined")

            case .text:
                let evalResult = try await runtime.webView.evaluateJavaScript("document.body.innerText")
                return .success(text: "\(evalResult ?? "")")

            case .back:
                guard runtime.webView.canGoBack else {
                    return .failure("Cannot go back: no previous page in history")
                }
                runtime.webView.goBack()
                return .success(message: "Navigated back")

            case .forward:
                guard runtime.webView.canGoForward else {
                    return .failure("Cannot go forward: no forward page in history")
                }
                runtime.webView.goForward()
                return .success(message: "Navigated forward")

            case .press:
                guard let key = request.args.first, !key.isEmpty else {
                    return .failure("Usage: den sheet press <key>")
                }
                try await SheetInteraction.press(key: key, in: runtime.webView)
                return .success(message: "Pressed \(key)")

            case .scroll:
                let direction = request.args.first?.lowercased() ?? "down"
                let message = try await SheetInteraction.scroll(direction: direction, in: runtime.webView)
                return .success(message: message)

            case .wait:
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

            case .screenshot:
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

            case .snapshot:
                let interactiveOnly = request.args.contains("-i") || request.args.contains("--interactive")
                let snapshot = try await SheetInteraction.snapshot(
                    in: runtime.webView,
                    interactiveOnly: interactiveOnly
                )
                return .success(snapshot: snapshot)

            case .click:
                guard let target = request.args.first, !target.isEmpty else {
                    return .failure("Usage: den sheet click <@ref|selector>")
                }
                try await SheetInteraction.click(target: target, in: runtime.webView)
                return .success(message: "Clicked \(target)")

            case .fill:
                guard request.args.count >= 2 else {
                    return .failure("Usage: den sheet fill <@ref|selector> <value>")
                }
                let target = request.args[0]
                let value = request.args.dropFirst().joined(separator: " ")
                try await SheetInteraction.fill(target: target, value: value, in: runtime.webView)
                return .success(message: "Filled \(target)")

            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Board Commands

    private func handleBoardCommand(_ command: DenIPCCommand.Board, request: DenIPCRequest) -> DenIPCResponse {
        switch command {
        case .list:
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

        case .web(.new):
            guard let urlString = request.args.first(where: { !$0.hasPrefix("-") }), !urlString.isEmpty else {
                return .failure("Usage: den board web new <url> [--focus]")
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

        case .terminal(.new):
            return handleTerminalBoardNew(request: request)

        case .close:
            guard request.args.isEmpty else {
                return .failure("Usage: den board close [--board <id>]")
            }
            if let idString = request.boardID {
                guard let targetID = UUID(uuidString: idString) else {
                    return .failure("Invalid board ID: \(idString)")
                }
                let allStores = profileManager?.allStores ?? []
                for candidateStore in allStores where candidateStore.boardIndices(for: targetID) != nil {
                    candidateStore.removeBoard(targetID)
                    return .success(
                        message: "Closed Board \(targetID.uuidString)",
                        closedBoardId: targetID.uuidString
                    )
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

        }
    }

    private func handleTerminalBoardNew(request: DenIPCRequest) -> DenIPCResponse {
        guard
            let (store, _) = DenIPCTargetResolver.resolveStoreAndDesk(
                callerBoardID: request.callerBoardID,
                in: profileManager
            )
        else {
            return .failure("No active store found")
        }

        var workingDir: String?
        var runCommand: String?
        let shouldFocus = request.args.contains("--focus")

        var argIndex = 0
        while argIndex < request.args.count {
            let arg = request.args[argIndex]
            if arg == "--focus" {
                argIndex += 1
            } else if arg == "--run", argIndex + 1 < request.args.count {
                runCommand = request.args[argIndex + 1]
                argIndex += 2
            } else if !arg.hasPrefix("-") && workingDir == nil {
                workingDir = arg
                argIndex += 1
            } else {
                argIndex += 1
            }
        }

        let resolvedDir: String
        if let dir = workingDir {
            switch BoardInputResolver.validateTerminalWorkingDirectory(dir) {
            case .success(let path):
                resolvedDir = path
            case .failure(let error):
                return .failure(error.message)
            }
        } else {
            resolvedDir = FileManager.default.homeDirectoryForCurrentUser.path
        }

        let callerID = request.callerBoardID.flatMap(UUID.init)
        guard
            let boardID = store.createTerminalBoard(
                workingDirectory: resolvedDir,
                afterBoardID: callerID ?? store.focusedBoard?.id,
                focus: shouldFocus
            )
        else {
            return .failure("Failed to create terminal board")
        }

        if let runCommand, let board = store.board(for: boardID) {
            let runtime = store.terminalRuntime(for: board)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                let commandText = runCommand.hasSuffix("\n") ? runCommand : runCommand + "\n"
                runtime.sendText(commandText)
            }
        }

        return .success(boardId: boardID.uuidString)
    }

    // MARK: - Desk Commands

    private func handleDeskCommand(_ command: DenIPCCommand.Desk, request: DenIPCRequest) -> DenIPCResponse {
        switch command {
        case .list:
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

        }
    }

    // MARK: - Drawer Commands

    private func handleDrawerCommand(_ command: DenIPCCommand.Drawer, request: DenIPCRequest) -> DenIPCResponse {
        guard
            let (store, _) = DenIPCTargetResolver.resolveStoreAndDesk(
                callerBoardID: request.callerBoardID,
                in: profileManager
            )
        else {
            return .failure("No active store found")
        }

        switch command {
        case .list:
            let items = store.state.drawerItems.map { item in
                DenDrawerItemInfo(
                    id: item.id.uuidString,
                    url: item.url.absoluteString,
                    title: item.title
                )
            }
            return .success(drawerItems: items)

        case .keep:
            guard let urlString = request.args.first(where: { !$0.hasPrefix("-") }), !urlString.isEmpty else {
                return .failure("Usage: den drawer keep <url> [--title <title>]")
            }
            guard let url = URL(string: urlString), SheetURLPolicy.isSupported(url) else {
                return .failure("Invalid or unsupported URL: \(urlString)")
            }
            var title: String?
            if let titleIndex = request.args.firstIndex(of: "--title"), titleIndex + 1 < request.args.count {
                title = request.args[titleIndex + 1]
            }
            if let itemID = store.keepInDrawerInBackground(url, title: title) {
                return .success(message: "Kept in Drawer: \(urlString)", drawerItemId: itemID.uuidString)
            }
            return .failure("Failed to keep in Drawer: \(urlString)")

        case .place:
            guard let idString = request.args.first(where: { !$0.hasPrefix("-") }), !idString.isEmpty else {
                return .failure("Usage: den drawer place <id>")
            }
            guard let item = findDrawerItem(in: store, matching: idString) else {
                return .failure("Drawer Item not found: \(idString)")
            }
            if let boardID = store.placeDrawerItemAsBoard(item.id) {
                return .success(message: "Placed Drawer Item as Board", boardId: boardID.uuidString)
            }
            return .failure("Failed to place Drawer Item as Board: \(idString)")

        case .discard:
            guard let idString = request.args.first(where: { !$0.hasPrefix("-") }), !idString.isEmpty else {
                return .failure("Usage: den drawer discard <id>")
            }
            guard let item = findDrawerItem(in: store, matching: idString) else {
                return .failure("Drawer Item not found: \(idString)")
            }
            if store.discardDrawerItem(item.id) {
                return .success(message: "Discarded Drawer Item: \(item.displayName)")
            }
            return .failure("Failed to discard Drawer Item: \(idString)")

        }
    }

    private func findDrawerItem(in store: DenStore, matching idString: String) -> DrawerItem? {
        if let exactID = UUID(uuidString: idString) {
            return store.state.drawerItems.first { $0.id == exactID }
        }
        let lower = idString.lowercased()
        let matches = store.state.drawerItems.filter { $0.id.uuidString.lowercased().hasPrefix(lower) }
        return matches.count == 1 ? matches.first : nil
    }

    // MARK: - Terminal Commands

    private func handleTerminalCommand(_ command: DenIPCCommand.Terminal, request: DenIPCRequest) -> DenIPCResponse {
        switch command {
        case .text:
            guard
                let (store, board) = DenIPCTargetResolver.resolveTargetTerminalBoard(
                    request: request,
                    in: profileManager
                )
            else {
                return .failure("No Terminal Board found")
            }
            let runtime = store.terminalRuntime(for: board)
            guard let text = runtime.readViewportText() else {
                return .failure("Failed to read terminal screen")
            }
            return .success(text: text)

        case .send:
            guard
                let (store, board) = DenIPCTargetResolver.resolveTargetTerminalBoard(
                    request: request,
                    in: profileManager
                )
            else {
                return .failure("No Terminal Board found")
            }
            guard let rawText = request.args.first, !rawText.isEmpty else {
                return .failure("Usage: den terminal send <text> [--board <id>]")
            }
            let text =
                rawText
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\r", with: "\r")
                .replacingOccurrences(of: "\\t", with: "\t")
            let runtime = store.terminalRuntime(for: board)
            runtime.sendText(text)
            return .success(message: "Sent text to Terminal Board \(board.id.uuidString)")

        case .kill:
            guard
                let (store, board) = DenIPCTargetResolver.resolveTargetTerminalBoard(
                    request: request,
                    in: profileManager
                )
            else {
                return .failure("No Terminal Board found")
            }
            let rawSignal = request.args.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            let signalName = (rawSignal?.isEmpty == false) ? (rawSignal ?? "TERM") : "TERM"
            guard let parsed = Self.parseSignal(signalName) else {
                return .failure("Unknown signal: \(signalName)")
            }
            do {
                let pid = try store.sendSignal(parsed.number, to: board)
                return .success(message: "Sent \(parsed.name) to process group \(pid) (Board \(board.id.uuidString))")
            } catch {
                return .failure(error.localizedDescription)
            }

        }
    }

    struct ParsedSignal: Equatable {
        let number: Int32
        let name: String
    }

    static func parseSignal(_ raw: String) -> ParsedSignal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let name = trimmed.hasPrefix("SIG") ? String(trimmed.dropFirst(3)) : trimmed
        switch name {
        case "HUP", "1": return ParsedSignal(number: SIGHUP, name: "SIGHUP")
        case "INT", "2": return ParsedSignal(number: SIGINT, name: "SIGINT")
        case "QUIT", "3": return ParsedSignal(number: SIGQUIT, name: "SIGQUIT")
        case "ABRT", "6": return ParsedSignal(number: SIGABRT, name: "SIGABRT")
        case "KILL", "9": return ParsedSignal(number: SIGKILL, name: "SIGKILL")
        case "ALRM", "14": return ParsedSignal(number: SIGALRM, name: "SIGALRM")
        case "TERM", "15": return ParsedSignal(number: SIGTERM, name: "SIGTERM")
        case "STOP", "17": return ParsedSignal(number: SIGSTOP, name: "SIGSTOP")
        case "TSTP", "18": return ParsedSignal(number: SIGTSTP, name: "SIGTSTP")
        case "CONT", "19": return ParsedSignal(number: SIGCONT, name: "SIGCONT")
        case "USR1", "30": return ParsedSignal(number: SIGUSR1, name: "SIGUSR1")
        case "USR2", "31": return ParsedSignal(number: SIGUSR2, name: "SIGUSR2")
        default:
            if let num = Int32(name), num > 0, num < 32 {
                return ParsedSignal(number: num, name: "SIG\(num)")
            }
            return nil
        }
    }
}
