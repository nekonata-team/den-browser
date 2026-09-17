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
        case .profile(let command):
            return handleProfileCommand(command, request: request)
        }
    }

    // MARK: - Sheet Commands

    private func handleSheetCommand(_ command: DenIPCCommand.Sheet, request: DenIPCRequest) async -> DenIPCResponse {
        let store: DenStore
        let board: BoardState
        switch DenIPCTargetResolver.resolveTargetWebBoardResult(request: request, in: profileManager) {
        case .success(let target):
            store = target.0
            board = target.1
        case .failure(let error):
            if command == .open && error == .noTargetBoard("Web") {
                return .failure("No Web Board found. Use 'den board web new <url>' to create a new board.")
            }
            return .failure(error.localizedDescription)
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

            case .interact:
                return await handleSheetInteract(request: request, runtime: runtime)

            case .press:
                guard let key = request.args.first, !key.isEmpty else {
                    return .failure("Usage: den sheet press <key>")
                }
                try await SheetInteraction.press(key: key, in: runtime.webView)
                return .success(message: "Pressed \(key)")

            case .scroll:
                let direction = request.args.first ?? "down"
                let message = try await SheetInteraction.scroll(direction: direction, in: runtime.webView)
                return .success(message: message)

            case .wait:
                let target = firstPositionalArgument(
                    in: request.args,
                    optionsWithValues: ["--url", "--state", "--timeout", "--text", "--load", "--fn"]
                )
                let urlPattern = optionValue("--url", in: request.args)
                let textValue = optionValue("--text", in: request.args)
                let loadValue = optionValue("--load", in: request.args)
                let functionValue = optionValue("--fn", in: request.args)
                let modes = [target, urlPattern, textValue, loadValue, functionValue].compactMap { $0 }.count
                guard modes == 1 else {
                    return .failure("Provide exactly one of a selector/ref, --url, --text, --load, or --fn")
                }
                if target == nil, optionValue("--state", in: request.args) != nil {
                    return .failure("--state requires a selector or element reference")
                }
                if let target, Double(target) != nil {
                    return .failure(
                        "Duration waits are no longer supported; use --state, --url, --text, --load, or --fn")
                }
                let timeout = try timeoutValue(in: request.args)

                if let urlPattern {
                    try await SheetInteraction.waitForURL(
                        pattern: urlPattern,
                        in: runtime.webView,
                        timeout: timeout
                    )
                    return .success(message: "URL matched \(urlPattern)")
                }

                if let textValue {
                    guard !textValue.isEmpty else {
                        return .failure("Text must not be empty")
                    }
                    try await SheetInteraction.waitForText(
                        text: textValue,
                        in: runtime.webView,
                        timeout: timeout
                    )
                    return .success(message: "Text matched: \(textValue)")
                }

                if let loadValue {
                    guard let loadState = SheetLoadState(rawValue: loadValue.lowercased()) else {
                        return .failure("Invalid load state: \(loadValue)")
                    }
                    try await SheetInteraction.waitForLoadState(
                        loadState,
                        in: runtime.webView,
                        timeout: timeout
                    )
                    return .success(message: "Load state reached: \(loadState.rawValue)")
                }

                if let functionValue {
                    guard !functionValue.isEmpty else {
                        return .failure("JavaScript condition must not be empty")
                    }
                    try await SheetInteraction.waitForFunction(
                        expression: functionValue,
                        in: runtime.webView,
                        timeout: timeout
                    )
                    return .success(message: "Condition matched")
                }

                guard let target else {
                    return .failure("Usage: den sheet wait <selector|ref> [--state <state>]")
                }
                let stateValue = optionValue("--state", in: request.args)?.lowercased() ?? "attached"
                guard let state = SheetWaitState(rawValue: stateValue) else {
                    return .failure("Invalid state: \(stateValue)")
                }
                try await SheetInteraction.waitForElement(
                    target: target,
                    state: state,
                    in: runtime.webView,
                    timeout: timeout
                )
                return .success(message: "Waited for \(stateValue): \(target)")

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
                let interactiveOnly = !request.args.contains("--full")
                let within = optionValue("--within", in: request.args)
                let snapshot = try await SheetInteraction.snapshot(
                    in: runtime.webView,
                    interactiveOnly: interactiveOnly,
                    within: within
                )
                return .success(snapshot: snapshot)

            case .query:
                guard
                    let selector = firstPositionalArgument(in: request.args, optionsWithValues: ["--fields"]),
                    !selector.isEmpty
                else {
                    return .failure("Usage: den sheet query <selector>")
                }
                let fields = try SheetInteraction.queryFields(
                    from: optionValue("--fields", in: request.args)
                )
                let elements = try await SheetInteraction.query(
                    selector: selector,
                    visibleOnly: request.args.contains("--visible"),
                    all: request.args.contains("--all"),
                    fields: fields,
                    in: runtime.webView
                )
                return .success(elements: elements)

            case .click:
                let target = firstPositionalArgument(
                    in: request.args,
                    optionsWithValues: ["--role", "--name"]
                )
                let role = optionValue("--role", in: request.args)
                let name = optionValue("--name", in: request.args)
                let exact = request.args.contains("--exact")
                let newBoard = request.args.contains("--new-board")
                let shouldFocus = request.args.contains("--focus")
                if target == nil && (role == nil || name == nil) {
                    return .failure("Usage: den sheet click <@ref|selector> or --role <role> --name <name>")
                }
                if target != nil && (role != nil || name != nil) {
                    return .failure("Provide either a selector/ref or --role and --name, not both")
                }
                let clickResult = try await SheetInteraction.clickResult(
                    target: target,
                    role: role,
                    name: name,
                    exact: exact,
                    newBoard: newBoard,
                    in: runtime.webView
                )
                runtime.triggerActionHighlight(clickResult.rect)
                let description = target ?? "role=\(role ?? ""), name=\(name ?? "")"

                if newBoard {
                    guard let href = clickResult.href, !href.isEmpty else {
                        return .failure("Element is not a link with an href: \(description)")
                    }
                    guard
                        let newBoardID = store.createBoard(
                            urlString: href,
                            afterBoardID: board.id,
                            focus: shouldFocus,
                            origin: .cli
                        ), let newBoard = store.board(for: newBoardID)
                    else {
                        return .failure("Failed to create new Web Board for \(href)")
                    }
                    _ = store.runtime(for: newBoard)
                    return .success(
                        message: "Opened \(description) in new Board",
                        boardId: newBoardID.uuidString,
                        url: href
                    )
                }

                return .success(message: "Clicked \(description)")

            case .fill:
                guard request.args.count >= 2 else {
                    return .failure("Usage: den sheet fill <@ref|selector> <value>")
                }
                let target = request.args[0]
                let value = request.args.dropFirst().joined(separator: " ")
                let rect = try await SheetInteraction.fill(target: target, value: value, in: runtime.webView)
                runtime.triggerActionHighlight(rect)
                return .success(message: "Filled \(target)")

            case .get:
                guard let kind = request.args.first?.lowercased() else {
                    return .failure("Usage: den sheet get <text|value|attr|count> ...")
                }
                switch kind {
                case "text":
                    guard request.args.count == 2, let target = request.args.last, !target.isEmpty else {
                        return .failure("Usage: den sheet get text <@ref|selector>")
                    }
                    let text = try await SheetInteraction.text(target: target, in: runtime.webView)
                    return .success(text: text)

                case "value":
                    guard request.args.count == 2, let target = request.args.last, !target.isEmpty else {
                        return .failure("Usage: den sheet get value <@ref|selector>")
                    }
                    let value = try await SheetInteraction.value(target: target, in: runtime.webView)
                    return .success(value: value)

                case "attr":
                    guard request.args.count == 3 else {
                        return .failure("Usage: den sheet get attr <@ref|selector> <attribute>")
                    }
                    let target = request.args[1]
                    let attribute = request.args[2]
                    guard !target.isEmpty, !attribute.isEmpty else {
                        return .failure("Usage: den sheet get attr <@ref|selector> <attribute>")
                    }
                    let value = try await SheetInteraction.attribute(
                        target: target,
                        name: attribute,
                        in: runtime.webView
                    )
                    return .success(attribute: value)

                case "count":
                    guard request.args.count == 2, let selector = request.args.last, !selector.isEmpty else {
                        return .failure("Usage: den sheet get count <selector>")
                    }
                    let count = try await SheetInteraction.count(selector: selector, in: runtime.webView)
                    return .success(count: count)

                default:
                    return .failure("Unknown get target: \(kind)")
                }

            case .isState:
                guard request.args.count == 2 else {
                    return .failure("Usage: den sheet is <visible|enabled|checked> <@ref|selector>")
                }
                let state = request.args[0].lowercased()
                let target = request.args[1]
                guard !target.isEmpty else {
                    return .failure("Usage: den sheet is <visible|enabled|checked> <@ref|selector>")
                }
                switch state {
                case "visible":
                    let visible = try await SheetInteraction.isVisible(target: target, in: runtime.webView)
                    return .success(visible: visible)
                case "enabled":
                    let enabled = try await SheetInteraction.isEnabled(target: target, in: runtime.webView)
                    return .success(enabled: enabled)
                case "checked":
                    let checked = try await SheetInteraction.isChecked(target: target, in: runtime.webView)
                    return .success(checked: checked)
                default:
                    return .failure("Unknown element state: \(state)")
                }

            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func handleSheetInteract(
        request: DenIPCRequest,
        runtime: BoardRuntime
    ) async -> DenIPCResponse {
        guard
            let stepsJSON = request.args.first(where: { !$0.hasPrefix("-") }),
            let data = stepsJSON.data(using: .utf8),
            let steps = try? JSONDecoder().decode([DenSheetInteractStep].self, from: data),
            !steps.isEmpty
        else {
            return .failure("Usage: den sheet interact <script-or-file>")
        }

        var completedActions = 0
        for (index, step) in steps.enumerated() {
            guard let commandName = step.args.first,
                let sheetCommand = DenIPCCommand.Sheet(rawValue: commandName),
                sheetCommand != .interact
            else {
                let snapshot = try? await SheetInteraction.snapshot(
                    in: runtime.webView,
                    interactiveOnly: !request.args.contains("--full")
                )
                return .failure(
                    "Line \(step.line): Unknown sheet command '\(step.args.first ?? "")'",
                    snapshot: snapshot,
                    completedActions: completedActions,
                    failedActionIndex: index
                )
            }

            let actionArguments = Array(step.args.dropFirst())
            let actionResponse = await handleSheetCommand(
                sheetCommand,
                request: DenIPCRequest(
                    command: .sheet(sheetCommand),
                    args: actionArguments,
                    boardID: request.boardID,
                    deskID: request.deskID,
                    callerBoardID: request.callerBoardID,
                    profileID: request.profileID
                )
            )
            guard actionResponse.isOk else {
                let snapshot = try? await SheetInteraction.snapshot(
                    in: runtime.webView,
                    interactiveOnly: !request.args.contains("--full")
                )
                let reason = actionResponse.error ?? "Interact action failed"
                return .failure(
                    "Line \(step.line) (\(step.text)): \(reason)",
                    snapshot: snapshot,
                    completedActions: completedActions,
                    failedActionIndex: index
                )
            }
            completedActions += 1
        }

        do {
            let snapshot = try await SheetInteraction.snapshot(
                in: runtime.webView,
                interactiveOnly: !request.args.contains("--full")
            )
            return .success(snapshot: snapshot, completedActions: completedActions)
        } catch {
            return .failure(
                error.localizedDescription,
                completedActions: completedActions
            )
        }
    }

    private func firstPositionalArgument(in args: [String], optionsWithValues: Set<String>) -> String? {
        var index = args.startIndex
        while index < args.endIndex {
            let argument = args[index]
            if argument.hasPrefix("--") {
                if argument.contains("=") {
                    index = args.index(after: index)
                } else if optionsWithValues.contains(argument) {
                    index = args.index(index, offsetBy: min(2, args.distance(from: index, to: args.endIndex)))
                } else {
                    index = args.index(after: index)
                }
            } else if argument.hasPrefix("-") {
                index = args.index(after: index)
            } else {
                return argument
            }
        }
        return nil
    }

    private func optionValue(_ option: String, in args: [String]) -> String? {
        if let index = args.firstIndex(of: option), args.index(after: index) < args.endIndex {
            let value = args[args.index(after: index)]
            if !value.hasPrefix("-") {
                return value
            }
        }
        let prefix = option + "="
        return args.first(where: { $0.hasPrefix(prefix) }).map { String($0.dropFirst(prefix.count)) }
    }

    private func timeoutValue(in args: [String]) throws -> TimeInterval {
        guard let rawTimeout = optionValue("--timeout", in: args) else {
            return 10
        }
        guard let timeout = Double(rawTimeout), timeout.isFinite, timeout >= 0 else {
            throw SheetInteractionError.invalidArgument("Timeout must be a finite non-negative number")
        }
        return timeout
    }

    // MARK: - Board Commands

    private func handleBoardCommand(_ command: DenIPCCommand.Board, request: DenIPCRequest) -> DenIPCResponse {
        switch command {
        case .list:
            let desk: DeskState
            switch DenIPCTargetResolver.resolveStoreAndDesk(request: request, in: profileManager) {
            case .success(let target):
                desk = target.1
            case .failure(let error):
                return .failure(error.localizedDescription)
            }
            let boards = desk.boards.map { currentBoard in
                DenBoardInfo(
                    id: currentBoard.id.uuidString,
                    type: currentBoard.isTerminal ? "terminal" : "web",
                    label: currentBoard.displayName,
                    url: currentBoard.currentSheetURL?.absoluteString,
                    sessionName: currentBoard.zellijSessionName ?? currentBoard.zmxSessionName,
                    isFocused: currentBoard.id == desk.focusedBoardID
                )
            }
            return .success(boards: boards)

        case .focused:
            let desk: DeskState
            switch DenIPCTargetResolver.resolveStoreAndDesk(request: request, in: profileManager) {
            case .success(let target):
                desk = target.1
            case .failure(let error):
                return .failure(error.localizedDescription)
            }
            guard let focusedBoard = desk.boards.first(where: { $0.id == desk.focusedBoardID }) else {
                return .failure("No focused Board found")
            }
            let info = DenBoardInfo(
                id: focusedBoard.id.uuidString,
                type: focusedBoard.isTerminal ? "terminal" : "web",
                label: focusedBoard.displayName,
                url: focusedBoard.currentSheetURL?.absoluteString,
                sessionName: focusedBoard.zellijSessionName ?? focusedBoard.zmxSessionName,
                isFocused: true
            )
            return .success(boardId: info.id, board: info)

        case .web(.new):
            guard let urlString = request.args.first(where: { !$0.hasPrefix("-") }), !urlString.isEmpty else {
                return .failure("Usage: den board web new <url> [--focus]")
            }
            let store: DenStore
            switch DenIPCTargetResolver.resolveStoreAndDesk(request: request, in: profileManager) {
            case .success(let target):
                store = target.0
            case .failure(let error):
                return .failure(error.localizedDescription)
            }
            let shouldFocus = request.args.contains("--focus")
            let callerID = request.callerBoardID.flatMap(UUID.init)
            if let boardID = store.createBoard(
                urlString: urlString,
                afterBoardID: callerID ?? store.focusedBoard?.id,
                focus: shouldFocus,
                origin: .cli
            ), let board = store.board(for: boardID) {
                _ = store.runtime(for: board)
                return .success(boardId: boardID.uuidString)
            }
            return .failure("Failed to open board with \(urlString)")

        case .terminal(.new):
            return handleTerminalBoardNew(request: request)

        case .close:
            guard request.args.isEmpty else {
                return .failure("Usage: den board close [--board <id>]")
            }
            let targetResult: Result<(DenStore, BoardState), DenIPCTargetResolver.TargetResolutionError>
            if request.boardID != nil {
                targetResult = DenIPCTargetResolver.resolveTargetAnyBoardResult(request: request, in: profileManager)
            } else {
                targetResult = DenIPCTargetResolver.resolveTargetWebBoardResult(request: request, in: profileManager)
            }
            switch targetResult {
            case .success(let (store, board)):
                store.removeBoard(board.id, origin: .cli)
                return .success(
                    message: "Closed Board \(board.id.uuidString)",
                    closedBoardId: board.id.uuidString
                )
            case .failure(let error):
                return .failure(error.localizedDescription)
            }

        }
    }

    private func handleTerminalBoardNew(request: DenIPCRequest) -> DenIPCResponse {
        let store: DenStore
        switch DenIPCTargetResolver.resolveStoreAndDesk(request: request, in: profileManager) {
        case .success(let target):
            store = target.0
        case .failure(let error):
            return .failure(error.localizedDescription)
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
                focus: shouldFocus,
                origin: .cli
            )
        else {
            return .failure("Failed to create terminal board")
        }

        if let runCommand, let board = store.board(for: boardID) {
            let runtime = store.terminalRuntime(for: board)
            runtime.runCommand(runCommand)
        }

        return .success(boardId: boardID.uuidString)
    }

    // MARK: - Desk Commands

    private func handleDeskCommand(_ command: DenIPCCommand.Desk, request: DenIPCRequest) -> DenIPCResponse {
        switch command {
        case .list:
            let store: DenStore
            switch DenIPCTargetResolver.resolveStoreAndDesk(request: request, in: profileManager) {
            case .success(let target):
                store = target.0
            case .failure(let error):
                return .failure(error.localizedDescription)
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
        let store: DenStore
        switch DenIPCTargetResolver.resolveStoreAndDesk(request: request, in: profileManager) {
        case .success(let target):
            store = target.0
        case .failure(let error):
            return .failure(error.localizedDescription)
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
            if let boardID = store.placeDrawerItemAsBoard(item.id),
                let board = store.board(for: boardID)
            {
                _ = store.runtime(for: board)
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
        let store: DenStore
        let board: BoardState
        switch DenIPCTargetResolver.resolveTargetTerminalBoardResult(request: request, in: profileManager) {
        case .success(let target):
            store = target.0
            board = target.1
        case .failure(let error):
            return .failure(error.localizedDescription)
        }

        switch command {
        case .text:
            let runtime = store.terminalRuntime(for: board)
            guard let text = runtime.readViewportText() else {
                return .failure("Failed to read terminal screen")
            }
            return .success(text: text)

        case .send:
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

        case .run:
            guard let command = request.args.first, !command.isEmpty else {
                return .failure("Usage: den terminal run <command> [--board <id>]")
            }
            let runtime = store.terminalRuntime(for: board)
            runtime.runCommand(command)
            return .success(message: "Ran command in Terminal Board \(board.id.uuidString)")

        case .kill:
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

    // MARK: - Profile Commands

    private func handleProfileCommand(_ command: DenIPCCommand.Profile, request: DenIPCRequest) -> DenIPCResponse {
        guard let profileManager else {
            return .failure("Profile manager unavailable")
        }
        switch command {
        case .list:
            let activeID = profileManager.activeProfileID()
            let profiles = profileManager.profiles.map { profile in
                DenProfileInfo(
                    id: profile.id.uuidString,
                    name: profile.name,
                    isActive: profile.id == activeID,
                    hasWindow: profileManager.hasWindow(for: profile.id)
                )
            }
            return .success(profiles: profiles)

        case .open:
            guard let targetIDString = request.args.first ?? request.profileID, !targetIDString.isEmpty else {
                return .failure("Usage: den profile open <uuid>")
            }
            guard let targetUUID = UUID(uuidString: targetIDString) else {
                return .failure("Invalid profile ID: \(targetIDString)")
            }
            guard let profile = profileManager.profile(id: targetUUID) else {
                return .failure("Profile not found: \(targetIDString)")
            }
            let wasAlreadyOpen = profileManager.hasWindow(for: profile.id)
            guard profileManager.openWindow(for: profile.id) else {
                return .failure("Failed to open window for profile '\(targetIDString)'")
            }
            let message =
                wasAlreadyOpen
                ? "Activated window for profile '\(profile.name)'"
                : "Opened window for profile '\(profile.name)'"
            return .success(message: message)
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
