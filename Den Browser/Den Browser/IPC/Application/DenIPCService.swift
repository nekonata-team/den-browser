import Darwin
import DenDomain
import DenIPCProtocol
import Foundation
import WebKit

@MainActor
final class DenIPCService {
    static let shared = DenIPCService()

    private struct WebBoardInteractionTarget {
        let profileID: ProfileID
        let store: DenStore
        let board: BoardState
        let runtime: WebBoardRuntime
    }

    private var server: DenSocketServer?
    private weak var profileManager: ProfileManager?

    init(profileManager: ProfileManager? = nil) {
        self.profileManager = profileManager
    }

    func start(profileManager: ProfileManager) {
        self.profileManager = profileManager
        let server = DenSocketServer(socketPath: profileManager.ipcSocketPath)
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
            response = DenIPCResponse(
                result: .failure("Invalid JSON request: \(error.localizedDescription)"),
                target: .none
            )
        }

        var responseData = (try? JSONEncoder().encode(response)) ?? Data()
        responseData.append(UInt8(ascii: "\n"))
        return responseData
    }

    func handleRequest(_ request: DenIPCRequest) async -> DenIPCResponse {
        switch request.operation {
        case .health:
            return DenIPCResponse(result: .success(), target: .none)
        case .sheet(let command, let target):
            return await withWebBoardTarget(target: target, context: request.context, command: command) { resolved in
                await self.performSheetCommand(command, target: resolved)
            }
        case .sheetWithSnapshot(let command, let target, let snapshot):
            return await withWebBoardTarget(target: target, context: request.context, command: command) { resolved in
                let result = await self.performSheetCommand(command, target: resolved)
                return await self.appendRequestedSnapshot(
                    to: result, command: command, snapshot: snapshot, target: resolved)
            }
        case .boardList(let target):
            return withDeskTarget(target, context: request.context) { self.handleBoardList(target: $0) }
        case .boardFocused(let target):
            return withDeskTarget(target, context: request.context) { self.handleBoardFocused(target: $0) }
        case .boardClose(let target):
            let kind: DenIPCTargetResolver.TargetKind = target == .automatic ? .web : .any
            return await withBoardTarget(target, context: request.context, kind: kind) {
                self.handleBoardClose(target: $0)
            }
        case .createWebBoard(let payload, let destination):
            guard !payload.url.isEmpty else {
                return DenIPCResponse(result: .failure("Usage: den board web new <url> [--focus]"), target: .none)
            }
            return withDeskTarget(destination, context: request.context) {
                self.handleWebBoardNew(payload: payload, target: $0, context: request.context)
            }
        case .createTerminalBoard(let payload, let destination):
            return withDeskTarget(destination, context: request.context) {
                self.handleTerminalBoardNew(payload: payload, target: $0, context: request.context)
            }
        case .createInspectionBoard(let targetBoardID, let payload):
            return await withBoardTarget(
                .explicit(targetBoardID), context: request.context, kind: .web
            ) { self.handleInspectionBoardNew(payload: payload, target: $0) }
        case .deskList(let target):
            return withDeskTarget(target, context: request.context) { self.handleDeskList(target: $0) }
        case .drawer(let command, let target):
            return withDeskTarget(target, context: request.context) {
                self.handleDrawerCommand(command, target: $0)
            }
        case .terminal(let command, let target):
            return await withBoardTarget(target, context: request.context, kind: .terminal) {
                await self.handleTerminalCommand(command, target: $0)
            }
        case .readInspection(let boardID):
            return await withBoardTarget(
                .explicit(boardID), context: request.context, kind: .inspection
            ) { await self.handleInspectionRead(target: $0) }
        case .profileList:
            return DenIPCResponse(result: handleProfileList(), target: .none)
        case .openProfile(let profileID):
            guard let profileManager else {
                return DenIPCResponse(result: .failure("Profile manager unavailable"), target: .none)
            }
            guard let profile = profileManager.profile(id: ProfileID(profileID)) else {
                return DenIPCResponse(result: .failure("Profile not found: \(profileID.uuidString)"), target: .none)
            }
            return DenIPCResponse(
                result: handleProfileOpen(profile: profile, in: profileManager),
                target: .profile(profileID: profile.id.rawValue)
            )
        case .inspectDen(let target):
            return withDeskTarget(target, context: request.context) { self.handleInspectDen(target: $0) }
        }
    }

    private func withDeskTarget(
        _ requested: DeskTarget,
        context: DenIPCCallerContext,
        perform: (ResolvedDeskTarget) -> DenIPCOperationResult
    ) -> DenIPCResponse {
        switch DenIPCTargetResolver.resolveDesk(target: requested, context: context, in: profileManager) {
        case .success(let resolved):
            return DenIPCResponse(result: perform(resolved), target: .profile(profileID: resolved.profileID.rawValue))
        case .failure(let error):
            return DenIPCResponse(result: .failure(error.localizedDescription), target: .none)
        }
    }

    private func withBoardTarget(
        _ requested: BoardTarget,
        context: DenIPCCallerContext,
        kind: DenIPCTargetResolver.TargetKind,
        perform: (ResolvedBoardTarget) async -> DenIPCOperationResult
    ) async -> DenIPCResponse {
        switch DenIPCTargetResolver.resolveBoard(
            target: requested, context: context, kind: kind, in: profileManager)
        {
        case .success(let resolved):
            let result = await perform(resolved)
            return DenIPCResponse(
                result: result,
                target: .board(profileID: resolved.profileID.rawValue, boardID: resolved.board.id.rawValue)
            )
        case .failure(let error):
            return DenIPCResponse(result: .failure(error.localizedDescription), target: .none)
        }
    }

    private func withWebBoardTarget(
        target: BoardTarget,
        context: DenIPCCallerContext,
        command: DenIPCCommand.Sheet,
        perform: (WebBoardInteractionTarget) async -> DenIPCOperationResult
    ) async -> DenIPCResponse {
        switch DenIPCTargetResolver.resolveBoard(target: target, context: context, kind: .web, in: profileManager) {
        case .success(let resolved):
            let webBoardTarget = WebBoardInteractionTarget(
                profileID: resolved.profileID,
                store: resolved.store,
                board: resolved.board,
                runtime: resolved.store.webRuntime(for: resolved.board)
            )
            let result = await perform(webBoardTarget)
            return DenIPCResponse(
                result: result,
                target: .board(profileID: resolved.profileID.rawValue, boardID: resolved.board.id.rawValue)
            )
        case .failure(let error):
            if case .navigate = command, error == .noTargetBoard("Web") {
                return DenIPCResponse(
                    result: .failure("No Web Board found. Use 'den board web new <url>' to create a new board."),
                    target: .none
                )
            }
            return DenIPCResponse(result: .failure(error.localizedDescription), target: .none)
        }
    }

    private func handleInspectionRead(target: ResolvedBoardTarget) async -> DenIPCOperationResult {
        let store = target.store
        let inspection = target.board
        guard let targetBoardID = inspection.sideBoardTargetBoardID,
            let targetBoard = store.board(for: targetBoardID), targetBoard.isWeb
        else {
            return .failure("Inspection Board target Web Board is unavailable")
        }
        guard let runtime = store.webRuntimes[targetBoard.id] else {
            return .failure("Inspection collection is unavailable for the target Web Board")
        }
        let generation = runtime.inspectionPageGeneration
        do {
            let page = try await runtime.readInspectionSnapshotForIPC()
            guard let documentID = page.documentID, !documentID.isEmpty else {
                return .failure("Inspection data has no document identity")
            }
            guard generation == runtime.inspectionPageGeneration else {
                return .failure("The target Sheet changed while reading Inspection data")
            }
            let ancestors = page.selectionConnected == true ? Array(page.treePath.dropLast()) : []
            let result = DenInspectionReadInfo(
                boardID: inspection.id.rawValue.uuidString,
                targetBoardID: targetBoard.id.rawValue.uuidString,
                url: runtime.webView.url?.absoluteString,
                pageGeneration: generation,
                documentID: documentID,
                capturedAt: ISO8601DateFormatter().string(from: Date()),
                collectionStartedAt: page.collectionStartedAt,
                selection: page.selection.map {
                    DenInspectionElementInfo(
                        nodeID: $0.nodeID,
                        ref: nil,
                        selector: $0.selector,
                        tag: $0.tag,
                        id: $0.id,
                        className: $0.className,
                        role: $0.role,
                        ariaLabel: $0.ariaLabel,
                        text: $0.text,
                        attributes: $0.attributes,
                        labels: $0.labels,
                        capturedAt: $0.capturedAt,
                        isConnected: page.selectionConnected ?? false)
                },
                ancestors: ancestors.map {
                    DenInspectionNodeInfo(
                        nodeID: $0.id,
                        tag: $0.tag,
                        attributes: $0.attributes.map { DenInspectionAttributeInfo(name: $0.name, value: $0.value) },
                        text: $0.text,
                        childCount: $0.childCount)
                },
                events: page.events.map {
                    DenInspectionEventInfo(
                        id: $0.id,
                        time: $0.timestamp ?? $0.time,
                        level: $0.level,
                        message: $0.message)
                },
                eventsDropped: page.eventsDropped ?? 0)
            return .success(boardId: inspection.id.rawValue.uuidString, inspection: result)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func handleInspectDen(target resolved: ResolvedDeskTarget) -> DenIPCOperationResult {
        guard let profileManager else {
            return .failure("Profile manager unavailable")
        }
        let store = resolved.store
        let desk = resolved.desk
        guard let profile = profileManager.profile(id: resolved.profileID)
        else {
            return .failure("Target Profile no longer exists")
        }
        let activeProfileID = profileManager.activeProfileID()
        let profiles = profileManager.profiles.map {
            DenProfileInfo(
                id: $0.id.rawValue.uuidString,
                name: $0.name,
                isActive: $0.id == activeProfileID,
                hasWindow: profileManager.hasWindow(for: $0.id)
            )
        }
        let desks = store.state.desks.map {
            DenDeskInfo(
                id: $0.id.rawValue.uuidString,
                label: $0.label,
                isActive: $0.id == desk.id,
                boardCount: $0.boards.count
            )
        }
        let boards = desk.boards.map {
            DenBoardInfo(
                id: $0.id.rawValue.uuidString,
                type: $0.isInspection
                    ? "inspection"
                    : ($0.isTutorial ? "tutorial" : ($0.isTerminal ? "terminal" : "web")),
                label: $0.displayName,
                url: $0.currentSheetURL?.absoluteString,
                sessionName: $0.zellijSessionName ?? $0.zmxSessionName,
                targetBoardID: $0.sideBoardTargetBoardID?.rawValue.uuidString,
                isFocused: $0.id == desk.focusedBoardID
            )
        }
        let activeDesk = desks.first { $0.isActive }
        return .success(
            boards: boards,
            desks: desks,
            profiles: profiles,
            profile: DenSelectedProfileInfo(id: profile.id.rawValue.uuidString, name: profile.name),
            profileID: profile.id.rawValue.uuidString,
            activeDesk: activeDesk,
            focusedBoardID: desk.focusedBoardID?.rawValue.uuidString,
            drawerItemCount: store.state.drawerItems.count
        )
    }

    // MARK: - Sheet Commands

    private func appendRequestedSnapshot(
        to result: DenIPCOperationResult,
        command: DenIPCCommand.Sheet,
        snapshot: DenSheetSnapshotPayload,
        target: WebBoardInteractionTarget
    ) async -> DenIPCOperationResult {
        switch command {
        case .inspect, .snapshot:
            return result
        default:
            break
        }

        let isInteract: Bool
        if case .interact = command {
            isInteract = true
        } else {
            isInteract = false
        }
        guard result.isOk || (isInteract && result.completedActions != nil) else { return result }

        func commandSucceededButTargetUnavailable() -> DenIPCOperationResult {
            var result = result
            result.isOk = false
            result.error =
                "Command succeeded, but the target Web Board no longer exists: \(target.board.id.rawValue.uuidString)"
            return result
        }

        func targetUnavailable() -> DenIPCOperationResult {
            .failure(
                "Target Web Board no longer exists: \(target.board.id.rawValue.uuidString)",
                completedActions: result.completedActions,
                failedActionIndex: {
                    guard case .interact(let payload) = command else { return nil }
                    return max(payload.steps.count - 1, 0)
                }()
            )
        }

        guard isWebBoardInteractionTargetAvailable(target) else {
            return isInteract ? (result.isOk ? targetUnavailable() : result) : commandSucceededButTargetUnavailable()
        }

        do {
            let captured = try await SheetInteraction.snapshot(
                in: target.runtime.webView,
                interactiveOnly: !snapshot.full,
                within: snapshot.within
            )
            guard isWebBoardInteractionTargetAvailable(target) else {
                return isInteract
                    ? (result.isOk ? targetUnavailable() : result) : commandSucceededButTargetUnavailable()
            }
            var result = result
            result.snapshot = captured
            return result
        } catch {
            guard isWebBoardInteractionTargetAvailable(target) else {
                return isInteract
                    ? (result.isOk ? targetUnavailable() : result) : commandSucceededButTargetUnavailable()
            }
            guard isInteract else {
                var result = result
                result.isOk = false
                result.error = "Command succeeded, but snapshot failed: \(error.localizedDescription)"
                return result
            }
            guard result.isOk else { return result }
            var result = result
            result.isOk = false
            result.error = error.localizedDescription
            return result
        }
    }

    private func performSheetCommand(
        _ command: DenIPCCommand.Sheet,
        target: WebBoardInteractionTarget
    ) async -> DenIPCOperationResult {
        let store = target.store
        let board = target.board
        let runtime = target.runtime

        do {
            switch command {
            case .navigate(let payload):
                guard !payload.url.isEmpty else {
                    return .failure("Usage: den board web navigate <url>")
                }
                guard
                    let resolved = BoardInputResolver.resolveOpenBoardInput(
                        payload.url,
                        searchEngine: store.preferences.searchEngine),
                    WebURLPolicy.isSupported(resolved.url)
                else {
                    return .failure("Invalid or unsupported URL: \(payload.url)")
                }
                let url = WebURLPolicy.canonicalSheetURL(resolved.url)
                runtime.load(url)
                return .success(message: "Navigated to \(url.absoluteString)", url: url.absoluteString)

            case .inspect(let payload):
                let currentURL = runtime.webView.url?.absoluteString ?? board.currentSheetURL?.absoluteString ?? ""
                let snapshot = try await SheetInteraction.snapshot(
                    in: runtime.webView,
                    interactiveOnly: !payload.full,
                    within: payload.within
                )
                return .success(boardId: board.id.rawValue.uuidString, url: currentURL, snapshot: snapshot)

            case .reload:
                runtime.webView.reload()
                return .success(message: "Reloaded")

            case .url:
                let currentURL = runtime.webView.url?.absoluteString ?? board.currentSheetURL?.absoluteString ?? ""
                return .success(url: currentURL)

            case .eval(let payload):
                guard !payload.script.isEmpty else {
                    return .failure("Usage: den board web eval <javascript>")
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

            case .interact(let payload):
                return await handleSheetInteract(payload: payload, target: target)

            case .press(let payload):
                guard !payload.key.isEmpty else {
                    return .failure("Usage: den board web press <key>")
                }
                let key = payload.key
                try await SheetInteraction.press(key: key, in: runtime.webView)
                return .success(message: "Pressed \(key)")

            case .scroll(let payload):
                let direction = payload.directionOrTarget ?? "down"
                let message = try await SheetInteraction.scroll(direction: direction, in: runtime.webView)
                return .success(message: message)

            case .wait(let payload):
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
                    return .failure("Usage: den board web wait <selector|ref> [--state <state>]")
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

            case .screenshot(let payload):
                let image = try await ScreenshotCapture.visibleCurrentSheet(in: runtime.webView)
                let data = try ScreenshotOutput.pngData(for: image)
                let targetURL: URL = {
                    if let path = payload.outputPath, !path.isEmpty {
                        return URL(fileURLWithPath: path)
                    }
                    let filename = ScreenshotOutput.suggestedFilename(scope: board.label)
                    return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                }()
                try data.write(to: targetURL)
                return .success(screenshotPath: targetURL.path)

            case .snapshot(let payload):
                let interactiveOnly = !payload.full
                let within = payload.within
                let snapshot = try await SheetInteraction.snapshot(
                    in: runtime.webView,
                    interactiveOnly: interactiveOnly,
                    within: within
                )
                return .success(snapshot: snapshot)

            case .query(let payload):
                guard !payload.selector.isEmpty else {
                    return .failure("Usage: den board web query <selector>")
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

            case .click(let payload):
                let target = payload.target
                let role = payload.role
                let name = payload.name
                let exact = payload.exact
                let newBoard = payload.newBoard
                let shouldFocus = payload.focus
                if target == nil && (role == nil || name == nil) {
                    return .failure("Usage: den board web click <@ref|selector> or --role <role> --name <name>")
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
                    _ = store.webRuntime(for: newBoard)
                    return .success(
                        message: "Opened \(description) in new Board",
                        boardId: newBoardID.rawValue.uuidString,
                        url: href
                    )
                }

                return .success(message: "Clicked \(description)")

            case .dblclick(let payload):
                guard !payload.target.isEmpty else {
                    return .failure("Usage: den board web dblclick <@ref|selector>")
                }
                let target = payload.target
                let rect = try await SheetInteraction.dblclick(target: target, in: runtime.webView)
                runtime.triggerActionHighlight(rect)
                return .success(message: "Double-clicked \(target)")

            case .focus(let payload):
                guard !payload.target.isEmpty else {
                    return .failure("Usage: den board web focus <@ref|selector>")
                }
                let target = payload.target
                let rect = try await SheetInteraction.focus(target: target, in: runtime.webView)
                runtime.triggerActionHighlight(rect)
                return .success(message: "Focused \(target)")

            case .fill(let payload):
                guard !payload.target.isEmpty else {
                    return .failure("Usage: den board web fill <@ref|selector> <value>")
                }
                let target = payload.target
                let value = payload.value
                let rect = try await SheetInteraction.fill(target: target, value: value, in: runtime.webView)
                runtime.triggerActionHighlight(rect)
                return .success(message: "Filled \(target)")

            case .type(let payload):
                guard !payload.text.isEmpty else {
                    return .failure("Usage: den board web type [<@ref|selector>] <text>")
                }
                let target = payload.target
                let text = payload.text
                let rect = try await SheetInteraction.type(target: target, text: text, in: runtime.webView)
                runtime.triggerActionHighlight(rect)
                let destination = target ?? "focused element"
                return .success(message: "Typed into \(destination)")

            case .drag(let payload):
                guard !payload.source.isEmpty else {
                    return .failure(
                        "Usage: den board web drag <source> [<target>] [--dx <dx>] [--dy <dy>] [--steps <steps>]")
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

            case .get(let command):
                switch command {
                case .text(let payload):
                    let target = payload.target
                    let text = try await SheetInteraction.text(target: target, in: runtime.webView)
                    return .success(text: text)

                case .value(let payload):
                    let target = payload.target
                    let value = try await SheetInteraction.value(target: target, in: runtime.webView)
                    return .success(value: value)

                case .attribute(let payload):
                    let value = try await SheetInteraction.attribute(
                        target: payload.target,
                        name: payload.attribute,
                        in: runtime.webView
                    )
                    return .success(attribute: value)

                case .count(let payload):
                    let count = try await SheetInteraction.count(
                        selector: payload.target,
                        in: runtime.webView
                    )
                    return .success(count: count)

                case .box(let payload):
                    let rect = try await SheetInteraction.box(target: payload.target, in: runtime.webView)
                    let box = DenBoundingBox(
                        originX: rect.origin.x,
                        originY: rect.origin.y,
                        width: rect.size.width,
                        height: rect.size.height
                    )
                    return .success(box: box)
                }

            case .isState(let state):
                let input =
                    switch state {
                    case .visible(let input), .enabled(let input), .checked(let input): input
                    }
                do {
                    try input.validate()
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
                func buttonCode(_ rawButton: String?) -> Int {
                    switch rawButton?.lowercased() {
                    case "right", "2": return 2
                    case "middle", "1": return 1
                    default: return 0
                    }
                }
                switch action {
                case .move(let payload):
                    guard let coordX = payload.coordX, let coordY = payload.coordY else {
                        return .failure("Usage: den board web mouse move <x> <y>")
                    }
                    try await SheetInteraction.mouseMove(coordX: coordX, coordY: coordY, in: runtime.webView)
                    return .success(message: "Mouse moved to \(coordX), \(coordY)")

                case .down(let payload):
                    let button = buttonCode(payload.button)
                    try await SheetInteraction.mouseDown(button: button, in: runtime.webView)
                    return .success(message: "Mouse button \(button) down")

                case .release(let payload):
                    let button = buttonCode(payload.button)
                    try await SheetInteraction.mouseUp(button: button, in: runtime.webView)
                    return .success(message: "Mouse button \(button) up")

                case .click(let payload):
                    guard let coordX = payload.coordX, let coordY = payload.coordY else {
                        return .failure(
                            "Usage: den board web mouse click <x> <y> [--button <left|right|middle>] [--count <n>]")
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

                case .wheel(let payload):
                    guard let deltaY = payload.deltaY else {
                        return .failure("Usage: den board web mouse wheel <dy> [--dx <dx>]")
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
        payload: DenSheetInteractPayload,
        target: WebBoardInteractionTarget
    ) async -> DenIPCOperationResult {
        guard !payload.steps.isEmpty else {
            return .failure("Usage: den board web interact <script-or-file>")
        }

        var completedActions = 0
        func targetUnavailable(at index: Int) -> DenIPCOperationResult {
            .failure(
                "Target Web Board no longer exists: \(target.board.id.rawValue.uuidString)",
                completedActions: completedActions,
                failedActionIndex: index
            )
        }

        for (index, step) in payload.steps.enumerated() {
            guard isWebBoardInteractionTargetAvailable(target) else {
                return targetUnavailable(at: index)
            }
            if case .interact = step.command {
                return .failure(
                    "Line \(step.line): Nested interact is not supported",
                    completedActions: completedActions,
                    failedActionIndex: index
                )
            }
            let actionResponse = await performSheetCommand(step.command, target: target)
            guard actionResponse.isOk else {
                let reason = actionResponse.error ?? "Interact action failed"
                return .failure(
                    "Line \(step.line) (\(step.text)): \(reason)",
                    completedActions: completedActions,
                    failedActionIndex: index
                )
            }
            guard isWebBoardInteractionTargetAvailable(target) else {
                return targetUnavailable(at: index)
            }
            completedActions += 1
        }

        guard isWebBoardInteractionTargetAvailable(target) else {
            return targetUnavailable(at: payload.steps.count - 1)
        }
        return .success(completedActions: completedActions)
    }

    private func isWebBoardInteractionTargetAvailable(_ target: WebBoardInteractionTarget) -> Bool {
        guard let profileManager,
            profileManager.profile(id: target.profileID) != nil,
            profileManager.hasWindow(for: target.profileID)
        else {
            return false
        }
        return target.store.board(for: target.board.id) != nil
    }

    // MARK: - Board Commands

    private func handleBoardList(target resolved: ResolvedDeskTarget) -> DenIPCOperationResult {
        let boards = resolved.desk.boards.map { boardInfo($0, focusedBoardID: resolved.desk.focusedBoardID) }
        return .success(boards: boards)
    }

    private func handleBoardFocused(target resolved: ResolvedDeskTarget) -> DenIPCOperationResult {
        guard let focusedBoard = resolved.desk.boards.first(where: { $0.id == resolved.desk.focusedBoardID }) else {
            return .failure("No focused Board found")
        }
        let info = boardInfo(focusedBoard, focusedBoardID: focusedBoard.id)
        return .success(boardId: info.id, board: info)
    }

    private func boardInfo(_ board: BoardState, focusedBoardID: BoardID?) -> DenBoardInfo {
        DenBoardInfo(
            id: board.id.rawValue.uuidString,
            type: board.isInspection
                ? "inspection"
                : (board.isTutorial ? "tutorial" : (board.isTerminal ? "terminal" : "web")),
            label: board.displayName,
            url: board.currentSheetURL?.absoluteString,
            sessionName: board.zellijSessionName ?? board.zmxSessionName,
            targetBoardID: board.sideBoardTargetBoardID?.rawValue.uuidString,
            isFocused: board.id == focusedBoardID
        )
    }

    private func handleWebBoardNew(
        payload: DenBoardWebNewPayload,
        target resolved: ResolvedDeskTarget,
        context: DenIPCCallerContext
    ) -> DenIPCOperationResult {
        guard
            let boardID = resolved.store.createBoard(
                urlString: payload.url,
                preferredWidth: payload.width,
                afterBoardID: newBoardInsertionAnchor(context: context, in: resolved.store, deskID: resolved.desk.id),
                focus: payload.focus,
                origin: .cli,
                deskID: resolved.desk.id
            ), let board = resolved.store.board(for: boardID)
        else {
            return .failure("Failed to open board with \(payload.url)")
        }
        _ = resolved.store.webRuntime(for: board)
        return .success(boardId: boardID.rawValue.uuidString)
    }

    private func handleInspectionBoardNew(
        payload: DenBoardInspectionNewPayload,
        target resolved: ResolvedBoardTarget
    ) -> DenIPCOperationResult {
        guard
            let inspectionID = resolved.store.createInspectionBoard(
                targetBoardID: resolved.board.id, focus: payload.focus)
        else {
            return .failure("Could not create an Inspection Board for \(resolved.board.id.rawValue.uuidString)")
        }
        return .success(boardId: inspectionID.rawValue.uuidString)
    }

    private func handleBoardClose(target resolved: ResolvedBoardTarget) -> DenIPCOperationResult {
        resolved.store.removeBoard(resolved.board.id, origin: .cli)
        return .success(
            message: "Closed Board \(resolved.board.id.rawValue.uuidString)",
            closedBoardId: resolved.board.id.rawValue.uuidString
        )
    }

    private func handleTerminalBoardNew(
        payload: DenBoardTerminalNewPayload,
        target resolved: ResolvedDeskTarget,
        context: DenIPCCallerContext
    ) -> DenIPCOperationResult {
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

        guard
            let boardID = resolved.store.createTerminalBoard(
                workingDirectory: resolvedDir,
                preferredWidth: payload.width,
                afterBoardID: newBoardInsertionAnchor(context: context, in: resolved.store, deskID: resolved.desk.id),
                focus: payload.focus,
                origin: .cli,
                deskID: resolved.desk.id
            )
        else {
            return .failure("Failed to create terminal board")
        }

        if let runCommand = payload.runCommand, let board = resolved.store.board(for: boardID) {
            let runtime = resolved.store.terminalRuntime(for: board)
            runtime.runCommand(runCommand)
        }

        return .success(boardId: boardID.rawValue.uuidString)
    }

    private func newBoardInsertionAnchor(
        context: DenIPCCallerContext,
        in store: DenStore,
        deskID: DeskID
    ) -> BoardID? {
        guard let deskIndex = store.state.desks.firstIndex(where: { $0.id == deskID }) else { return nil }
        let callerAnchor = context.callerBoardID.map(BoardID.init).flatMap { boardID -> BoardID? in
            guard store.boardIndices(for: boardID)?.desk == deskIndex else { return nil }
            return boardID
        }
        return callerAnchor ?? store.state.desks[deskIndex].focusedBoardID
    }

    // MARK: - Desk Commands

    private func handleDeskList(target resolved: ResolvedDeskTarget) -> DenIPCOperationResult {
        let desks = resolved.store.state.desks.map { desk in
            DenDeskInfo(
                id: desk.id.rawValue.uuidString,
                label: desk.label,
                isActive: desk.id == resolved.store.presentedDeskID,
                boardCount: desk.boards.count
            )
        }
        return .success(desks: desks)
    }

    // MARK: - Drawer Commands

    private func handleDrawerCommand(
        _ command: DenIPCCommand.Drawer,
        target resolved: ResolvedDeskTarget
    ) -> DenIPCOperationResult {
        let store = resolved.store
        let desk = resolved.desk

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

        case .keep(let payload):
            guard !payload.url.isEmpty else {
                return .failure("Usage: den drawer keep <url> [--title <title>]")
            }
            guard
                let openInput = BoardInputResolver.resolveOpenBoardInput(
                    payload.url,
                    searchEngine: store.preferences.searchEngine),
                case let .url(url) = openInput.item,
                WebURLPolicy.isSupported(url)
            else {
                return .failure("Invalid or unsupported URL: \(payload.url)")
            }
            let canonicalURL = WebURLPolicy.canonicalSheetURL(url)
            if let itemID = store.keepInDrawerInBackground(canonicalURL, title: payload.title) {
                return .success(
                    message: "Kept in Drawer: \(canonicalURL.absoluteString)", drawerItemId: itemID.uuidString
                )
            }
            return .failure("Failed to keep in Drawer: \(canonicalURL.absoluteString)")

        case .place(let idString):
            guard !idString.isEmpty else {
                return .failure("Usage: den drawer place <id>")
            }
            guard let item = findDrawerItem(in: store, matching: idString) else {
                return .failure("Drawer Item not found: \(idString)")
            }
            if let boardID = store.placeDrawerItemAsBoard(item.id, deskID: desk.id),
                let board = store.board(for: boardID)
            {
                _ = store.webRuntime(for: board)
                return .success(
                    message: "Placed Drawer Item as Board", boardId: boardID.rawValue.uuidString
                )
            }
            return .failure("Failed to place Drawer Item as Board: \(idString)")

        case .discard(let idString):
            guard !idString.isEmpty else {
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

    private func handleTerminalCommand(
        _ command: DenIPCCommand.Terminal,
        target resolved: ResolvedBoardTarget
    ) async -> DenIPCOperationResult {
        let store = resolved.store
        let board = resolved.board

        switch command {
        case .text:
            let runtime = store.terminalRuntime(for: board)
            guard let text = runtime.readViewportText() else {
                return .failure("Failed to read terminal screen")
            }
            return .success(text: text)

        case .send(let rawText):
            guard !rawText.isEmpty else {
                return .failure("Usage: den board terminal send <text> [--board <id>]")
            }
            let text =
                rawText
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\r", with: "\r")
                .replacingOccurrences(of: "\\t", with: "\t")
            let runtime = store.terminalRuntime(for: board)
            runtime.sendText(text)
            return .success(message: "Sent text to Terminal Board \(board.id.rawValue.uuidString)")

        case .run(let command):
            guard !command.isEmpty else {
                return .failure("Usage: den board terminal run <command> [--board <id>]")
            }
            let runtime = store.terminalRuntime(for: board)
            runtime.runCommand(command)
            return .success(message: "Ran command in Terminal Board \(board.id.rawValue.uuidString)")

        case .kill(let rawSignal):
            let signal = rawSignal.trimmingCharacters(in: .whitespacesAndNewlines)
            let signalName =
                signal.isEmpty
                ? "TERM"
                : signal
            guard let parsed = Self.parseSignal(signalName) else {
                return .failure("Unknown signal: \(signalName)")
            }
            do {
                let pid = try await store.sendSignal(parsed.number, to: board)
                return .success(
                    message: "Sent \(parsed.name) to process group \(pid) (Board \(board.id.rawValue.uuidString))"
                )
            } catch {
                return .failure(error.localizedDescription)
            }

        }
    }

    // MARK: - Profile Commands

    private func handleProfileList() -> DenIPCOperationResult {
        guard let profileManager else {
            return .failure("Profile manager unavailable")
        }
        let activeID = profileManager.activeProfileID()
        let profiles = profileManager.profiles.map { profile in
            DenProfileInfo(
                id: profile.id.rawValue.uuidString,
                name: profile.name,
                isActive: profile.id == activeID,
                hasWindow: profileManager.hasWindow(for: profile.id)
            )
        }
        return .success(profiles: profiles)
    }

    private func handleProfileOpen(profile: ProfileState, in profileManager: ProfileManager) -> DenIPCOperationResult {
        let wasAlreadyOpen = profileManager.hasWindow(for: profile.id)
        guard profileManager.openWindow(for: profile.id) else {
            return .failure("Failed to open window for profile '\(profile.id.rawValue.uuidString)'")
        }
        let message =
            wasAlreadyOpen
            ? "Activated window for profile '\(profile.name)'"
            : "Opened window for profile '\(profile.name)'"
        return .success(message: message)
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
