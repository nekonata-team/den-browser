import DenApplication
import DenDomain
import DenIPCProtocol
import Foundation

@MainActor
final class DenMCPActions {
    enum Operation {
        case show, move, create, remove
        case close(sideBoardID: BoardID?)
        case place(DenBoardMoveDestination, deskID: DeskID)
        case confirmRemoval([BoardID])
    }

    struct Entry {
        let profileID: ProfileID
        let deskID: DeskID
        let target: UniversalSearchItem.Target
        let operation: Operation
        let input: String?
        let url: URL?
    }

    private var entries: [UUID: Entry] = [:]
    private var order: [UUID] = []

    subscript(ref: UUID) -> Entry? { entries[ref] }

    func issue(_ entry: Entry, effect: String) -> DenMCPResult.Action {
        let ref = UUID()
        if order.count == 2_048 {
            for expired in order.prefix(1_024) { entries.removeValue(forKey: expired) }
            order.removeFirst(1_024)
        }
        entries[ref] = entry
        order.append(ref)
        return .init(effect: effect, ref: ref)
    }

    func reset() {
        entries.removeAll()
        order.removeAll()
    }
}

extension DenIPCService {
    func handleMCP(_ command: DenMCPCommand, profileID: UUID?) async -> DenIPCResponse {
        let context = DenIPCCallerContext(profileID: profileID)
        switch command {
        case .search(let query, let limit, let kinds):
            return withDeskTarget(.automatic, context: context) {
                search(query: query, limit: limit, kinds: kinds, at: $0)
            }
        case .act(let ref, let name, let deleteBoards):
            guard let entry = mcpActions[ref], profileID == nil || profileID == entry.profileID.rawValue else {
                return .init(result: staleSearchResult, target: .none)
            }
            return .init(
                result: act(entry, name: name, deleteBoards: deleteBoards),
                target: .profile(profileID: entry.profileID.rawValue)
            )
        case .openPages(let pages, let desk, let newDesk):
            return withDeskTarget(.automatic, context: context) {
                openPages(pages, destination: desk, newDesk: newDesk, at: $0)
            }
        case .readPage(let boardID, let url):
            return await readPage(boardID: boardID, url: url, context: context)
        case .readSelection(let boardID):
            return await readSelection(boardID: boardID, context: context)
        }
    }

    private var staleSearchResult: DenIPCOperationResult {
        .failure("This action or its target is no longer available. Run search_den again.")
    }

    private func search(query: String, limit: Int, kinds: [String]?, at resolved: ResolvedDeskTarget)
        -> DenIPCOperationResult
    {
        guard (1...20).contains(limit), query.utf8.count <= 8_192 else {
            return .failure("Use a shorter query and a limit between 1 and 20")
        }
        let validKinds: Set<String> = ["board", "desk", "recent", "essential", "command", "input"]
        let allowedKinds = kinds.map(Set.init)
        if let allowedKinds, allowedKinds.isEmpty || !allowedKinds.isSubset(of: validKinds) {
            return .failure("kinds must be a non-empty subset of board, desk, recent, essential, command, input")
        }
        let snapshot = resolved.window.resources.snapshot
        let essentials = resolved.window.essentials()
        let profileName = profileManager?.profile(id: resolved.profileID)?.name ?? ""
        let items = UniversalSearch.sourceItems(
            state: snapshot.den,
            essentials: essentials,
            hasBoardUndoHistory: !snapshot.boardUndoHistory.isEmpty,
            profiles: profileManager?.profiles ?? [],
            profileName: profileName
        )
        var matches: [DenMCPResult.Match] = []
        for item in UniversalSearch.results(query: query, items: items, recentItems: snapshot.recentItems) {
            let target = item.target
            let kind: String
            switch target {
            case .board: kind = "board"
            case .desk: kind = "desk"
            case .command(.newDesk): kind = "command"
            case .recent: kind = "recent"
            case .essential: kind = "essential"
            case .createBoard: kind = "input"
            default: continue
            }
            if let allowedKinds, !allowedKinds.contains(kind) { continue }
            let input = target.creationInput(essentials: essentials, recents: snapshot.recentItems)
            let web = input.flatMap { webInput($0, window: resolved.window) }
            let desk = target.boardDesk(in: snapshot.den) ?? target.desk(in: snapshot.den) ?? resolved.desk
            func action(_ operation: DenMCPActions.Operation, _ effect: String) -> DenMCPResult.Action {
                mcpActions.issue(
                    .init(
                        profileID: resolved.profileID,
                        deskID: desk.id,
                        target: target,
                        operation: operation,
                        input: input,
                        url: web?.url
                    ),
                    effect: effect
                )
            }

            let actions: [DenMCPResult.Action]
            let detail: String?
            let id: UUID?
            switch target {
            case .board(let boardID):
                guard let board = snapshot.den.board(for: boardID) else { continue }
                id = boardID.rawValue
                detail =
                    board.currentSheetURL?.absoluteString ?? board.zmxSessionName ?? board.zellijSessionName
                    ?? board.terminalWorkingDirectory
                let sideBoardID = desk.boards.first { $0.sideBoardTargetBoardID == boardID }?.id
                let close =
                    sideBoardID != nil
                    ? "Close Board and its Side Board, ending their live activity"
                    : "Close Board and end its live activity"
                actions = [
                    action(.show, "Show existing Board"),
                    action(.move, "Choose where to move or reorder the Board Group"),
                    action(.close(sideBoardID: sideBoardID), close),
                ]
            case .desk(let deskID):
                id = deskID.rawValue
                detail = nil
                actions = [action(.show, "Show Desk"), action(.remove, "Preview Desk removal")]
            case .command(.newDesk):
                id = nil
                detail = nil
                actions = [action(.create, "Create an empty Desk with a name")]
            case .recent, .essential, .createBoard:
                guard let input, web != nil else { continue }
                id = nil
                detail = input == item.title ? nil : input
                actions = [action(.create, "Create and show a new Web Board")]
            default: continue
            }
            matches.append(
                .init(
                    kind: kind,
                    id: id,
                    name: item.title,
                    location: "\(profileName) / \(desk.label)",
                    detail: detail,
                    actions: actions
                )
            )
            if matches.count == limit { break }
        }
        return .success(.mcp(.init(matches: matches)))
    }

    private func act(_ entry: DenMCPActions.Entry, name: String?, deleteBoards: Bool) -> DenIPCOperationResult {
        let context = DenIPCCallerContext(profileID: entry.profileID.rawValue)
        let anchor: DeskTarget = .explicit(entry.deskID.rawValue)
        switch entry.target {
        case .board(let id):
            guard
                case .success(let resolved) = DenIPCTargetResolver.resolveBoard(
                    target: .explicit(id.rawValue),
                    context: context,
                    kind: .any,
                    in: profileManager
                ), let desk = entry.target.boardDesk(in: resolved.window.resources.state)
            else { return staleSearchResult }
            return actOnBoard(entry, at: resolved, desk: desk)
        default:
            guard
                case .success(let resolved) = DenIPCTargetResolver.resolveDesk(
                    target: anchor,
                    context: context,
                    in: profileManager
                )
            else { return staleSearchResult }
            switch entry.target {
            case .desk:
                return actOnDesk(entry, at: resolved, deleteBoards: deleteBoards)
            case .command(.newDesk):
                guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return .success(.mcp(.init(required: ["name"], message: "Provide a label for the new empty Desk.")))
                }
                return handleDeskNew(label: name, focus: true, target: resolved)
            case .recent, .essential, .createBoard:
                let input = entry.target.creationInput(
                    essentials: resolved.window.essentials(),
                    recents: resolved.window.resources.recentItems
                )
                guard let input, input == entry.input, let url = entry.url,
                    let web = webInput(input, window: resolved.window), web.url == url
                else {
                    return staleSearchResult
                }
                guard let board = createPage(web.url, at: resolved, focus: true, recent: web.item) else {
                    return .failure("Could not create Web Board")
                }
                return .success(
                    .createdBoard(id: board.id.rawValue.uuidString, message: nil, url: web.url.absoluteString)
                )
            default:
                return staleSearchResult
            }
        }
    }

    private func actOnBoard(_ entry: DenMCPActions.Entry, at resolved: ResolvedBoardTarget, desk: DeskState)
        -> DenIPCOperationResult
    {
        let board = resolved.board
        let resources = resolved.window.resources
        switch entry.operation {
        case .show:
            resolved.window.board.focus(board.id)
            guard resolved.window.presentedDeskID() == desk.id,
                resources.state.desks.first(where: { $0.id == desk.id })?.focusedBoardID == board.id
            else { return .failure("Could not show Board") }
            return .success(.board(boardInfo(board, focusedBoardID: board.id)))
        case .close(let expectedSideBoardID):
            let sideBoardID = desk.boards.first { $0.sideBoardTargetBoardID == board.id }?.id
            guard sideBoardID == expectedSideBoardID else { return staleSearchResult }
            guard resources.activeDrag == nil else { return .failure("Finish the active drag and retry") }
            let result = handleBoardClose(target: resolved)
            return resources.state.board(for: board.id) == nil ? result : .failure("Could not close Board")
        case .move:
            guard let group = BoardGroup.containing(board.id, in: desk.boards) else { return staleSearchResult }
            let primary = group.primaryBoard.id
            var destinations: [DenMCPResult.Action] = []
            for destination in resources.state.desks {
                func choice(_ target: DenBoardMoveDestination, _ effect: String) -> DenMCPResult.Action {
                    mcpActions.issue(
                        .init(
                            profileID: entry.profileID,
                            deskID: desk.id,
                            target: entry.target,
                            operation: .place(target, deskID: destination.id),
                            input: nil,
                            url: nil
                        ),
                        effect: effect
                    )
                }

                let location = "\(destination.label) [\(destination.id.rawValue)]"
                destinations.append(choice(.endOfDesk(destination.id.rawValue), "Place at end of \(location)"))
                for neighbor in destination.boards where !neighbor.isSideBoard && neighbor.id != primary {
                    let label = "\(neighbor.displayName) [\(neighbor.id.rawValue)] on \(location)"
                    destinations.append(choice(.leftOf(neighbor.id.rawValue), "Place left of \(label)"))
                    destinations.append(choice(.rightOf(neighbor.id.rawValue), "Place right of \(label)"))
                }
            }
            return .success(
                .mcp(.init(destinations: destinations, message: "Call act_on_result with one destination ref."))
            )
        case .place(let destination, let deskID):
            guard let destinationDesk = resources.state.desks.first(where: { $0.id == deskID }) else {
                return staleSearchResult
            }
            if case .leftOf(let id) = destination, !destinationDesk.boards.contains(where: { $0.id.rawValue == id }) {
                return staleSearchResult
            }
            if case .rightOf(let id) = destination, !destinationDesk.boards.contains(where: { $0.id.rawValue == id }) {
                return staleSearchResult
            }
            return handleBoardMove(destination: destination, target: resolved)
        default:
            return staleSearchResult
        }
    }

    private func actOnDesk(_ entry: DenMCPActions.Entry, at resolved: ResolvedDeskTarget, deleteBoards: Bool)
        -> DenIPCOperationResult
    {
        let desk = resolved.desk
        let window = resolved.window
        switch entry.operation {
        case .show:
            window.desk.focus(desk.id)
            guard window.presentedDeskID() == desk.id else { return .failure("Could not show Desk") }
            return .success(.mcp(.init(desk: deskInfo(desk, in: window))))
        case .remove, .confirmRemoval:
            guard window.resources.state.desks.count > 1 else { return .failure("The last Desk cannot be removed") }
            let boardIDs = desk.boards.map(\.id)
            if case .confirmRemoval(let expected) = entry.operation {
                guard expected == boardIDs else {
                    return removalPreview(
                        entry,
                        at: resolved,
                        message: "Desk contents changed. Review the new removal impact."
                    )
                }
                if boardIDs.isEmpty || deleteBoards {
                    guard window.resources.activeDrag == nil else {
                        return .failure("Finish the active drag and retry")
                    }
                    return handleDeskRemove(force: deleteBoards, target: resolved)
                }
            }
            return removalPreview(entry, at: resolved)
        default:
            return staleSearchResult
        }
    }

    private func removalPreview(_ entry: DenMCPActions.Entry, at resolved: ResolvedDeskTarget, message: String? = nil)
        -> DenIPCOperationResult
    {
        let desk = resolved.desk
        let confirmation = mcpActions.issue(
            .init(
                profileID: entry.profileID,
                deskID: desk.id,
                target: entry.target,
                operation: .confirmRemoval(desk.boards.map(\.id)),
                input: nil,
                url: nil
            ),
            effect: desk.boards.isEmpty
                ? "Remove empty Desk" : "Remove Desk and all listed Boards, ending their live activity"
        )
        return .success(
            .mcp(
                .init(
                    desk: deskInfo(desk, in: resolved.window, includeBoards: true),
                    required: desk.boards.isEmpty ? nil : ["delete_boards"],
                    message: [message, "Removing a presented Desk switches its window to a replacement Desk."]
                        .compactMap { $0 }.joined(separator: " "),
                    confirmation: confirmation
                )
            )
        )
    }

    private func openPages(_ pages: [String], destination: String?, newDesk: String?, at source: ResolvedDeskTarget)
        -> DenIPCOperationResult
    {
        guard (1...20).contains(pages.count) else { return .failure("Provide between 1 and 20 pages") }
        guard destination == nil || newDesk == nil else { return .failure("Supply only one of desk and new_desk") }
        let window = source.window
        let resources = window.resources
        guard resources.activeDrag == nil else { return .failure("Finish the active drag and retry") }
        let focused = currentWebBoard(in: source)
        let currentURL = focused.flatMap { resources.webRuntimes[$0.id]?.webView.url ?? $0.currentSheetURL }
        let urls = pages.map { input in
            input == "current" ? currentURL.flatMap { explicitURL($0.absoluteString) } : explicitURL(input)
        }

        let desk: DeskState
        if let destination {
            let matches = resources.state.desks.filter {
                if let id = UUID(uuidString: destination) { return $0.id.rawValue == id }
                return $0.label.localizedCaseInsensitiveCompare(destination) == .orderedSame
            }
            guard let match = matches.first else { return .failure("Desk not found. Use overview_den to find it.") }
            guard matches.count == 1 else {
                return .success(
                    .mcp(
                        .init(
                            choices: matches.map { deskInfo($0, in: window) },
                            message: "More than one Desk matches. Call open_pages again with a Desk ID."
                        )
                    )
                )
            }
            desk = match
        } else if let newDesk {
            guard urls.contains(where: { $0 != nil }) else {
                return .failure(
                    "Provide at least one valid URL or an available current page before creating a Desk",
                    payload: .mcp(.init(pages: pages.enumerated().map { pageError(at: $0.offset, input: $0.element) }))
                )
            }
            let created = handleDeskNew(label: newDesk, focus: false, target: source)
            guard case .createdDesk(let id) = created.payload,
                let match = resources.state.desks.first(where: { $0.id.rawValue.uuidString == id })
            else { return created }
            desk = match
        } else {
            desk = source.desk
        }

        let target = ResolvedDeskTarget(window: window, desk: desk, profileID: source.profileID)
        let results: [DenMCPPage] = pages.enumerated().map { index, input in
            guard let url = urls[index] else { return pageError(at: index, input: input) }
            guard let board = createPage(url, at: target, focus: false) else {
                return .init(index: index, input: input, url: url.absoluteString, error: "Could not create Web Board")
            }
            return .init(index: index, input: input, url: url.absoluteString, boardID: board.id.rawValue.uuidString)
        }
        let updated = resources.state.desks.first { $0.id == desk.id } ?? desk
        let payload = DenIPCResultPayload.mcp(.init(desk: deskInfo(updated, in: window), pages: results))
        return results.contains { $0.boardID != nil }
            ? .success(payload) : .failure("No pages opened", payload: payload)
    }

    private func pageError(at index: Int, input: String) -> DenMCPPage {
        .init(
            index: index,
            input: input,
            error: input == "current" ? "No current Web page" : "Invalid or unsupported absolute URL"
        )
    }

    private func explicitURL(_ input: String) -> URL? {
        guard !input.contains(where: \.isWhitespace), let url = URL(string: input), WebURLPolicy.isSupported(url) else {
            return nil
        }
        return WebURLPolicy.canonicalSheetURL(url)
    }

    private func webInput(_ input: String, window: IPCWindowBindings) -> (url: URL, item: RecentItem)? {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(":"),
            let resolved = BoardInputResolver.resolveOpenBoardInput(input, searchEngine: window.searchEngine())
        else { return nil }
        return (WebURLPolicy.canonicalSheetURL(resolved.url), resolved.item)
    }

    private func createPage(_ url: URL, at resolved: ResolvedDeskTarget, focus: Bool, recent: RecentItem? = nil)
        -> BoardState?
    {
        let window = resolved.window
        let resources = window.resources
        guard resources.activeDrag == nil,
            let desk = resources.state.desks.first(where: { $0.id == resolved.desk.id })
        else { return nil }
        let target = BoardCreation.Target(
            presentedDeskID: window.presentedDeskID(),
            deskID: desk.id,
            afterBoardID: focus ? nil : desk.boards.last?.id,
            focus: focus,
            origin: .cli
        )
        let retainedRecent = recent.flatMap {
            $0.displayText.count <= BoardOpening.maximumPersistedRecentInputLength ? $0 : nil
        }
        guard
            let id = resources.boardCreation.createWeb(
                urlString: url.absoluteString,
                width: window.inheritedBoardWidth(),
                searchEngine: window.searchEngine(),
                target: target,
                recentItem: retainedRecent,
                notify: { notice in
                    if case .prepareLinkFocus = notice { return }
                    window.board.creationNotice(notice)
                }
            ), let board = resources.state.board(for: id)
        else { return nil }
        _ = window.board.webRuntime(board)
        return board
    }

    private func currentWebBoard(in source: ResolvedDeskTarget) -> BoardState? {
        source.desk.boards.first { $0.id == source.desk.focusedBoardID && $0.isWeb }
    }

    private func readPage(boardID: UUID?, url: String?, context: DenIPCCallerContext) async -> DenIPCResponse {
        let resolved: ResolvedBoardTarget
        if let boardID {
            guard url == nil else {
                return .init(result: .failure("Supply only one of board_id and url"), target: .none)
            }
            switch DenIPCTargetResolver.resolveBoard(
                target: .explicit(boardID),
                context: context,
                kind: .web,
                in: profileManager
            ) {
            case .success(let board): resolved = board
            case .failure(let error): return .init(result: .failure(error.localizedDescription), target: .none)
            }
        } else {
            switch DenIPCTargetResolver.resolveDesk(target: .automatic, context: context, in: profileManager) {
            case .failure(let error): return .init(result: .failure(error.localizedDescription), target: .none)
            case .success(let desk):
                let board: BoardState?
                if let url {
                    guard let parsed = explicitURL(url) else {
                        return .init(result: .failure("Invalid or unsupported absolute URL"), target: .none)
                    }
                    board = createPage(parsed, at: desk, focus: false)
                } else {
                    board = currentWebBoard(in: desk)
                }
                guard let board else {
                    let message =
                        url == nil ? "No focused Web Board. Provide board_id or url." : "Could not create Web Board"
                    return .init(result: .failure(message), target: .profile(profileID: desk.profileID.rawValue))
                }
                resolved = .init(window: desk.window, board: board, profileID: desk.profileID)
            }
        }

        let board = resolved.board
        let runtime = resolved.window.resources.webRuntimes[board.id] ?? resolved.window.board.webRuntime(board)
        let target = DenIPCTargetContext.board(profileID: resolved.profileID.rawValue, boardID: board.id.rawValue)
        do {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(10)
            while runtime.webView.isLoading || runtime.webView.url == nil {
                guard clock.now < deadline else {
                    return .init(
                        result: .failure("Page did not finish loading. Retry with the returned board_id."),
                        target: target
                    )
                }
                try await clock.sleep(for: .milliseconds(50))
            }
            let pageURL = runtime.webView.url
            let generation = runtime.inspectionPageGeneration
            let payload = try await SheetReading.read(in: runtime.webView, within: nil)
            guard generation == runtime.inspectionPageGeneration,
                pageURL == runtime.webView.url, !runtime.webView.isLoading,
                resolved.window.resources.webRuntimes[board.id] === runtime,
                resolved.window.resources.state.board(for: board.id) != nil
            else {
                return .init(
                    result: .failure("The Web Board or its Current Sheet changed while reading"),
                    target: target
                )
            }
            return .init(result: .success(payload), target: target)
        } catch {
            return .init(result: .failure(error.localizedDescription), target: target)
        }
    }

    private func readSelection(boardID: UUID?, context: DenIPCCallerContext) async -> DenIPCResponse {
        let id: UUID
        if let boardID {
            id = boardID
        } else {
            let source: ResolvedDeskTarget
            switch DenIPCTargetResolver.resolveDesk(target: .automatic, context: context, in: profileManager) {
            case .failure(let error): return .init(result: .failure(error.localizedDescription), target: .none)
            case .success(let desk): source = desk
            }
            let desks = source.window.resources.state.desks
            let inspections = desks.flatMap(\.boards).filter(\.isInspection)
            if let focused = source.desk.focusedBoardID,
                let inspection = inspections.first(where: { $0.id == focused || $0.sideBoardTargetBoardID == focused })
            {
                id = inspection.id.rawValue
            } else if inspections.count == 1, let inspection = inspections.first {
                id = inspection.id.rawValue
            } else if inspections.isEmpty {
                return .init(result: .failure("No Inspection Board is available"), target: .none)
            } else {
                let choices = desks.flatMap { desk in
                    desk.boards.filter(\.isInspection).map { inspection in
                        let page = desk.boards.first { $0.id == inspection.sideBoardTargetBoardID }
                        return DenMCPResult.InspectionChoice(
                            id: inspection.id.rawValue,
                            name: page?.displayName ?? inspection.displayName,
                            location: desk.label,
                            url: page?.currentSheetURL?.absoluteString
                        )
                    }
                }
                return .init(
                    result: .success(
                        .mcp(
                            .init(
                                message: "Choose an Inspection Board ID and call read_selection again.",
                                inspections: choices
                            )
                        )
                    ),
                    target: .profile(profileID: source.profileID.rawValue)
                )
            }
        }
        switch DenIPCTargetResolver.resolveBoard(
            target: .explicit(id),
            context: context,
            kind: .inspection,
            in: profileManager
        ) {
        case .failure(let error): return .init(result: .failure(error.localizedDescription), target: .none)
        case .success(let target):
            let result = await handleInspectionRead(target: target, includeEvents: false)
            return .init(result: result, target: .board(profileID: target.profileID.rawValue, boardID: id))
        }
    }

    private func deskInfo(_ desk: DeskState, in window: IPCWindowBindings, includeBoards: Bool = false) -> DenDeskInfo {
        .init(
            id: desk.id.rawValue.uuidString,
            label: desk.label,
            isActive: window.presentedDeskID() == desk.id,
            boardCount: desk.boards.count,
            boards: includeBoards ? desk.boards.map { boardInfo($0, focusedBoardID: desk.focusedBoardID) } : nil
        )
    }
}
