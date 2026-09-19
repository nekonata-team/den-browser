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
                guard case .sheet(.open(let payload)) = request.payload, !payload.url.isEmpty else {
                    return .failure("Usage: den sheet open <url>")
                }
                let urlString = payload.url
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
                guard case .sheet(.eval(let payload)) = request.payload, !payload.script.isEmpty else {
                    return .failure("Usage: den sheet eval <javascript>")
                }
                let script = payload.script
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
                guard case .sheet(.press(let payload)) = request.payload, !payload.key.isEmpty else {
                    return .failure("Usage: den sheet press <key>")
                }
                let key = payload.key
                try await SheetInteraction.press(key: key, in: runtime.webView)
                return .success(message: "Pressed \(key)")

            case .scroll:
                guard case .sheet(.scroll(let payload)) = request.payload else {
                    return .failure("Usage: den sheet scroll [<direction|amount|target>]")
                }
                let direction = payload.directionOrTarget ?? "down"
                let message = try await SheetInteraction.scroll(direction: direction, in: runtime.webView)
                return .success(message: message)

            case .wait:
                guard case .sheet(.wait(let payload)) = request.payload else {
                    return .failure("Usage: den sheet wait <selector|ref> [--state <state>]")
                }
                let target = payload.target
                let urlPattern = payload.url
                let textValue = payload.text
                let loadValue = payload.loadState
                let functionValue = payload.function
                let modes = [target, urlPattern, textValue, loadValue, functionValue].compactMap { $0 }.count
                guard modes == 1 else {
                    return .failure("Provide exactly one of a selector/ref, --url, --text, --load, or --fn")
                }
                if target == nil, payload.state != nil {
                    return .failure("--state requires a selector or element reference")
                }
                if let target, Double(target) != nil {
                    return .failure(
                        "Duration waits are no longer supported; use --state, --url, --text, --load, or --fn")
                }
                guard payload.timeout.isFinite, payload.timeout >= 0 else {
                    return .failure("Timeout must be a finite non-negative number")
                }
                let timeout = payload.timeout

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
                let stateValue = payload.state?.lowercased() ?? "attached"
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
                guard case .sheet(.screenshot(let payload)) = request.payload else {
                    return .failure("Usage: den sheet screenshot [<output-path>]")
                }
                let image = try await ScreenshotCapture.visibleCurrentSheet(in: runtime.webView)
                let data = try ScreenshotCapture.pngData(for: image)
                let targetURL: URL = {
                    if let path = payload.outputPath, !path.isEmpty {
                        return URL(fileURLWithPath: path)
                    }
                    let filename = ScreenshotCapture.suggestedFilename(scope: board.label)
                    return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                }()
                try data.write(to: targetURL)
                return .success(screenshotPath: targetURL.path)

            case .snapshot:
                guard case .sheet(.snapshot(let payload)) = request.payload else {
                    return .failure("Usage: den sheet snapshot [--interactive|--full] [--within <selector|ref>]")
                }
                let interactiveOnly = !payload.full
                let within = payload.within
                let snapshot = try await SheetInteraction.snapshot(
                    in: runtime.webView,
                    interactiveOnly: interactiveOnly,
                    within: within
                )
                return .success(snapshot: snapshot)

            case .query:
                guard case .sheet(.query(let payload)) = request.payload, !payload.selector.isEmpty else {
                    return .failure("Usage: den sheet query <selector>")
                }
                let fields = try SheetInteraction.queryFields(
                    from: payload.fields
                )
                let elements = try await SheetInteraction.query(
                    selector: payload.selector,
                    visibleOnly: payload.visible,
                    all: payload.all,
                    fields: fields,
                    in: runtime.webView
                )
                return .success(elements: elements)

            case .click:
                guard case .sheet(.click(let payload)) = request.payload else {
                    return .failure("Usage: den sheet click <@ref|selector> or --role <role> --name <name>")
                }
                let target = payload.target
                let role = payload.role
                let name = payload.name
                let exact = payload.exact
                let newBoard = payload.newBoard
                let shouldFocus = payload.focus
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

            case .dblclick:
                guard case .sheet(.dblclick(let payload)) = request.payload, !payload.target.isEmpty else {
                    return .failure("Usage: den sheet dblclick <@ref|selector>")
                }
                let target = payload.target
                let rect = try await SheetInteraction.dblclick(target: target, in: runtime.webView)
                runtime.triggerActionHighlight(rect)
                return .success(message: "Double-clicked \(target)")

            case .focus:
                guard case .sheet(.focus(let payload)) = request.payload, !payload.target.isEmpty else {
                    return .failure("Usage: den sheet focus <@ref|selector>")
                }
                let target = payload.target
                let rect = try await SheetInteraction.focus(target: target, in: runtime.webView)
                runtime.triggerActionHighlight(rect)
                return .success(message: "Focused \(target)")

            case .fill:
                guard case .sheet(.fill(let payload)) = request.payload,
                    !payload.target.isEmpty
                else {
                    return .failure("Usage: den sheet fill <@ref|selector> <value>")
                }
                let target = payload.target
                let value = payload.value
                let rect = try await SheetInteraction.fill(target: target, value: value, in: runtime.webView)
                runtime.triggerActionHighlight(rect)
                return .success(message: "Filled \(target)")

            case .type:
                guard case .sheet(.type(let payload)) = request.payload, !payload.text.isEmpty else {
                    return .failure("Usage: den sheet type [<@ref|selector>] <text>")
                }
                let target = payload.target
                let text = payload.text
                let rect = try await SheetInteraction.type(target: target, text: text, in: runtime.webView)
                runtime.triggerActionHighlight(rect)
                let destination = target ?? "focused element"
                return .success(message: "Typed into \(destination)")

            case .drag:
                guard case .sheet(.drag(let payload)) = request.payload, !payload.source.isEmpty else {
                    return .failure(
                        "Usage: den sheet drag <source> [<target>] [--dx <dx>] [--dy <dy>] [--steps <steps>]")
                }
                let source = payload.source
                let target = payload.destination
                let deltaX = payload.deltaX
                let deltaY = payload.deltaY
                let steps = payload.steps

                guard target != nil || deltaX != nil || deltaY != nil else {
                    return .failure("Drag requires a target element or at least one of --dx / --dy")
                }

                let rect = try await SheetInteraction.drag(
                    source: source,
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    steps: steps,
                    in: runtime.webView
                )
                runtime.triggerActionHighlight(rect)
                let destination = target ?? "dx=\(deltaX ?? 0), dy=\(deltaY ?? 0)"
                return .success(message: "Dragged \(source) to \(destination)")

            case .get(let kind):
                let input: DenSheetGetPayload
                do {
                    guard case .sheet(.get(let payload)) = request.payload else {
                        return .failure("Invalid payload for den sheet get")
                    }
                    try payload.validate(attributeRequired: kind == .attribute)
                    input = payload
                } catch {
                    return .failure(error.localizedDescription)
                }
                switch kind {
                case .text:
                    let target = input.target
                    let text = try await SheetInteraction.text(target: target, in: runtime.webView)
                    return .success(text: text)

                case .value:
                    let target = input.target
                    let value = try await SheetInteraction.value(target: target, in: runtime.webView)
                    return .success(value: value)

                case .attribute:
                    guard let attribute = input.attribute else {
                        return .failure("Invalid payload for den sheet get")
                    }
                    let value = try await SheetInteraction.attribute(
                        target: input.target,
                        name: attribute,
                        in: runtime.webView
                    )
                    return .success(attribute: value)

                case .count:
                    let count = try await SheetInteraction.count(
                        selector: input.target,
                        in: runtime.webView
                    )
                    return .success(count: count)

                case .box:
                    let rect = try await SheetInteraction.box(target: input.target, in: runtime.webView)
                    let box = DenBoundingBox(
                        originX: rect.origin.x,
                        originY: rect.origin.y,
                        width: rect.size.width,
                        height: rect.size.height
                    )
                    return .success(box: box)
                }

            case .isState(let state):
                let input: DenSheetStatePayload
                do {
                    guard case .sheet(.isState(let payload)) = request.payload else {
                        return .failure("Invalid payload for den sheet is")
                    }
                    try payload.validate()
                    input = payload
                } catch {
                    return .failure(error.localizedDescription)
                }
                switch state {
                case .visible:
                    let target = input.target
                    let visible = try await SheetInteraction.isVisible(target: target, in: runtime.webView)
                    return .success(visible: visible)
                case .enabled:
                    let target = input.target
                    let enabled = try await SheetInteraction.isEnabled(target: target, in: runtime.webView)
                    return .success(enabled: enabled)
                case .checked:
                    let target = input.target
                    let checked = try await SheetInteraction.isChecked(target: target, in: runtime.webView)
                    return .success(checked: checked)
                }

            case .mouse(let action):
                guard case .sheet(.mouse(let payload)) = request.payload else {
                    return .failure("Usage: den sheet mouse <move|down|up|click|wheel> ...")
                }
                func buttonCode(_ rawButton: String?) -> Int {
                    switch rawButton?.lowercased() {
                    case "right", "2": return 2
                    case "middle", "1": return 1
                    default: return 0
                    }
                }
                switch action {
                case .move:
                    guard let coordX = payload.coordX, let coordY = payload.coordY else {
                        return .failure("Usage: den sheet mouse move <x> <y>")
                    }
                    try await SheetInteraction.mouseMove(coordX: coordX, coordY: coordY, in: runtime.webView)
                    return .success(message: "Mouse moved to \(coordX), \(coordY)")

                case .down:
                    let button = buttonCode(payload.button)
                    try await SheetInteraction.mouseDown(button: button, in: runtime.webView)
                    return .success(message: "Mouse button \(button) down")

                case .release:
                    let button = buttonCode(payload.button)
                    try await SheetInteraction.mouseUp(button: button, in: runtime.webView)
                    return .success(message: "Mouse button \(button) up")

                case .click:
                    guard let coordX = payload.coordX, let coordY = payload.coordY else {
                        return .failure(
                            "Usage: den sheet mouse click <x> <y> [--button <left|right|middle>] [--count <n>]")
                    }
                    let button = buttonCode(payload.button)
                    let count = payload.count ?? 1
                    let rect = try await SheetInteraction.mouseClick(
                        coordX: coordX,
                        coordY: coordY,
                        button: button,
                        count: count,
                        in: runtime.webView
                    )
                    runtime.triggerActionHighlight(rect)
                    return .success(message: "Mouse clicked at \(coordX), \(coordY)")

                case .wheel:
                    guard let deltaY = payload.deltaY else {
                        return .failure("Usage: den sheet mouse wheel <dy> [--dx <dx>]")
                    }
                    let deltaX = payload.deltaX ?? 0
                    try await SheetInteraction.mouseWheel(deltaX: deltaX, deltaY: deltaY, in: runtime.webView)
                    return .success(message: "Mouse wheel scrolled dx: \(deltaX), dy: \(deltaY)")
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
        guard case .sheet(.interact(let payload)) = request.payload, !payload.steps.isEmpty else {
            return .failure("Usage: den sheet interact <script-or-file>")
        }

        var completedActions = 0
        for (index, step) in payload.steps.enumerated() {
            guard step.command != .interact else {
                let snapshot = try? await SheetInteraction.snapshot(
                    in: runtime.webView,
                    interactiveOnly: !payload.full
                )
                return .failure(
                    "Line \(step.line): Nested interact is not supported",
                    snapshot: snapshot,
                    completedActions: completedActions,
                    failedActionIndex: index
                )
            }
            let actionResponse = await handleSheetCommand(
                step.command,
                request: DenIPCRequest(
                    command: .sheet(step.command),
                    payload: step.payload.map(DenIPCRequestPayload.sheet),
                    boardID: request.boardID,
                    deskID: request.deskID,
                    callerBoardID: request.callerBoardID,
                    profileID: request.profileID
                )
            )
            guard actionResponse.isOk else {
                let snapshot = try? await SheetInteraction.snapshot(
                    in: runtime.webView,
                    interactiveOnly: !payload.full
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
                interactiveOnly: !payload.full
            )
            return .success(snapshot: snapshot, completedActions: completedActions)
        } catch {
            return .failure(
                error.localizedDescription,
                completedActions: completedActions
            )
        }
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
            guard
                let requestPayload = request.payload,
                case .board(.webNew(let payload)) = requestPayload,
                !payload.url.isEmpty
            else {
                return .failure("Usage: den board web new <url> [--focus]")
            }
            let urlString = payload.url
            let store: DenStore
            switch DenIPCTargetResolver.resolveStoreAndDesk(request: request, in: profileManager) {
            case .success(let target):
                store = target.0
            case .failure(let error):
                return .failure(error.localizedDescription)
            }
            let callerID = request.callerBoardID.flatMap(UUID.init)
            if let boardID = store.createBoard(
                urlString: urlString,
                afterBoardID: callerID ?? store.focusedBoard?.id,
                focus: payload.focus,
                origin: .cli
            ), let board = store.board(for: boardID) {
                _ = store.runtime(for: board)
                return .success(boardId: boardID.uuidString)
            }
            return .failure("Failed to open board with \(urlString)")

        case .terminal(.new):
            guard
                let requestPayload = request.payload,
                case .board(.terminalNew(let payload)) = requestPayload
            else {
                return .failure("Usage: den board terminal new [<path>] [--run <cmd>] [--focus]")
            }
            return handleTerminalBoardNew(payload: payload, request: request)

        case .close:
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

    private func handleTerminalBoardNew(
        payload: DenBoardTerminalNewPayload,
        request: DenIPCRequest
    ) -> DenIPCResponse {
        let store: DenStore
        switch DenIPCTargetResolver.resolveStoreAndDesk(request: request, in: profileManager) {
        case .success(let target):
            store = target.0
        case .failure(let error):
            return .failure(error.localizedDescription)
        }

        let resolvedDir: String
        if let dir = payload.path {
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
                focus: payload.focus,
                origin: .cli
            )
        else {
            return .failure("Failed to create terminal board")
        }

        if let runCommand = payload.runCommand, let board = store.board(for: boardID) {
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
            guard
                let requestPayload = request.payload,
                case .drawer(.keep(let payload)) = requestPayload,
                !payload.url.isEmpty
            else {
                return .failure("Usage: den drawer keep <url> [--title <title>]")
            }
            let urlString = payload.url
            guard let url = URL(string: urlString), SheetURLPolicy.isSupported(url) else {
                return .failure("Invalid or unsupported URL: \(urlString)")
            }
            if let itemID = store.keepInDrawerInBackground(url, title: payload.title) {
                return .success(message: "Kept in Drawer: \(urlString)", drawerItemId: itemID.uuidString)
            }
            return .failure("Failed to keep in Drawer: \(urlString)")

        case .place:
            guard
                let requestPayload = request.payload,
                case .drawer(.place(let idString)) = requestPayload,
                !idString.isEmpty
            else {
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
            guard
                let requestPayload = request.payload,
                case .drawer(.discard(let idString)) = requestPayload,
                !idString.isEmpty
            else {
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
            guard
                let requestPayload = request.payload,
                case .terminal(.send(let rawText)) = requestPayload,
                !rawText.isEmpty
            else {
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
            guard
                let requestPayload = request.payload,
                case .terminal(.run(let command)) = requestPayload,
                !command.isEmpty
            else {
                return .failure("Usage: den terminal run <command> [--board <id>]")
            }
            let runtime = store.terminalRuntime(for: board)
            runtime.runCommand(command)
            return .success(message: "Ran command in Terminal Board \(board.id.uuidString)")

        case .kill:
            guard
                let requestPayload = request.payload,
                case .terminal(.kill(let rawSignal)) = requestPayload
            else {
                return .failure("Usage: den terminal kill [-s <signal>] [--board <id>]")
            }
            let signal = rawSignal.trimmingCharacters(in: .whitespacesAndNewlines)
            let signalName =
                signal.isEmpty
                ? "TERM"
                : signal
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
            guard
                let requestPayload = request.payload,
                case .profile(.open(let profileID)) = requestPayload,
                let targetIDString = profileID ?? request.profileID,
                !targetIDString.isEmpty
            else {
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
