import Foundation

public enum UniversalSearchCommand: String, CaseIterable, Sendable {
    case newDesk
    case openProfile
    case openSettings
    case toggleZenView
    case toggleFocusMode
    case undoBoardOperation
}

public struct UniversalSearchItem: Identifiable, Equatable, Sendable {
    public enum Target: Hashable, Sendable {
        case board(BoardID)
        case desk(DeskID)
        case profile(ProfileID)
        case builtInDeskPreset(BuiltInDeskPreset)
        case personalDeskPreset(UUID)
        case essential(UUID)
        case recent(RecentItem)
        case createBoard(String)
        case command(UniversalSearchCommand)

        public func creationInput(essentials: [Essential], recents: [RecentItem]) -> String? {
            switch self {
            case .essential(let id): essentials.first { $0.id == id }?.input
            case .recent(let item): recents.contains(item) ? item.displayText : nil
            case .createBoard(let input): input
            default: nil
            }
        }

        public func boardDesk(in state: DenState) -> DeskState? {
            guard case .board(let id) = self, let index = state.boardIndices(for: id) else { return nil }
            return state.desks[index.deskOffset]
        }

        public func desk(in state: DenState) -> DeskState? {
            guard case .desk(let id) = self else { return nil }
            return state.desks.first { $0.id == id }
        }

        fileprivate var navigationID: UUID? {
            switch self {
            case .board(let id): id.rawValue
            case .desk(let id): id.rawValue
            case .profile(let id): id.rawValue
            case .essential, .recent, .createBoard, .command, .builtInDeskPreset, .personalDeskPreset: nil
            }
        }
    }

    public let target: Target
    public let title: String
    public let detail: String
    public let keywords: String
    public var id: Target { target }

    public init(target: Target, title: String, detail: String, keywords: String = "") {
        self.target = target
        self.title = title
        self.detail = detail
        self.keywords = keywords
    }
}

public enum UniversalSearch {
    public static func isCommandsOnly(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    public static func sourceItems(
        state: DenState,
        essentials: [Essential],
        hasBoardUndoHistory: Bool,
        profiles: [ProfileState],
        profileName: String,
        deskPresets: [PersonalDeskPreset] = []
    ) -> [UniversalSearchItem] {
        var items: [UniversalSearchItem] = []
        for desk in state.desks {
            for board in desk.boards {
                items.append(
                    UniversalSearchItem(
                        target: .board(board.id),
                        title: board.displayName,
                        detail: "Switch to Board · \(profileName) / \(desk.label)",
                        keywords: [
                            board.currentSheetURL?.absoluteString, board.terminalWorkingDirectory,
                            board.zellijSessionName, board.zmxSessionName,
                        ].compactMap { $0 }.joined(separator: " ")
                    )
                )
            }
        }
        items += essentials.map {
            UniversalSearchItem(
                target: .essential($0.id),
                title: $0.name,
                detail: "Create Board from Essential · \($0.displayKey)",
                keywords: $0.input
            )
        }
        items += state.desks.map {
            UniversalSearchItem(target: .desk($0.id), title: $0.label, detail: "Switch to Desk · \(profileName)")
        }
        items += BuiltInDeskPreset.allCases.map { preset in
            let count = preset.boards.count
            let suffix = count == 1 ? "1 Board" : "\(count) Boards"
            return UniversalSearchItem(
                target: .builtInDeskPreset(preset),
                title: preset.label,
                detail: "Create Desk from Preset · \(suffix)",
                keywords: preset.boards.compactMap { $0.initialSheetURL?.absoluteString }.joined(separator: " ")
            )
        }
        items += deskPresets.map { preset in
            let count = preset.boards.count
            let suffix = count == 1 ? "1 Board" : "\(count) Boards"
            let keywords = preset.boards.flatMap { [$0.label, $0.initialSheetURL?.absoluteString] }
                .compactMap { $0 }
                .joined(separator: " ")
            return UniversalSearchItem(
                target: .personalDeskPreset(preset.id),
                title: preset.label,
                detail: "Create Desk from Preset · \(suffix)",
                keywords: keywords
            )
        }
        items += profiles.map {
            UniversalSearchItem(target: .profile($0.id), title: $0.name, detail: "Switch to Profile")
        }
        for command in UniversalSearchCommand.allCases {
            if command == .undoBoardOperation, !hasBoardUndoHistory { continue }
            let title: String
            switch command {
            case .newDesk: title = "New Desk…"
            case .openProfile: title = "Open Profile…"
            case .openSettings: title = "Open Settings"
            case .toggleZenView: title = "Toggle Zen View"
            case .toggleFocusMode: title = "Toggle Focus Mode"
            case .undoBoardOperation: title = "Undo Board Operation"
            }
            items.append(UniversalSearchItem(target: .command(command), title: title, detail: "Command"))
        }
        return items
    }

    public static func results(query: String, items: [UniversalSearchItem], recentItems: [RecentItem])
        -> [UniversalSearchItem]
    {
        let trimmed = WebURLPolicy.stripNewlines(query).trimmingCharacters(in: .whitespaces)
        let commandsOnly = isCommandsOnly(trimmed)
        let terms = (commandsOnly ? String(trimmed.dropFirst()) : trimmed).split(whereSeparator: \.isWhitespace)
        let recentResults = commandsOnly ? [] : recentResults(query: trimmed, recentItems: recentItems)
        if trimmed.isEmpty {
            let essentials = items.filter { if case .essential = $0.target { true } else { false } }
            let otherItems = items.filter { if case .essential = $0.target { false } else { true } }
            return recentResults + essentials + otherItems
        }
        let queryID = UUID(uuidString: trimmed)
        let idMatches = items.filter { queryID != nil && $0.target.navigationID == queryID }
        var results =
            idMatches
            + items.filter { item in
                if let queryID, item.target.navigationID == queryID { return false }
                if commandsOnly {
                    guard case .command = item.target else { return false }
                }
                let searchable = "\(item.title) \(item.detail) \(item.keywords)"
                return terms.allSatisfy { searchable.localizedCaseInsensitiveContains(String($0)) }
            }
        results += recentResults
        if !commandsOnly, !trimmed.isEmpty {
            results.append(
                UniversalSearchItem(
                    target: .createBoard(trimmed),
                    title: trimmed,
                    detail: "Create Board in the current Desk"
                )
            )
        }
        return results
    }

    private static func recentResults(query: String, recentItems: [RecentItem]) -> [UniversalSearchItem] {
        let matches = matchingRecentItems(query: query, recentItems: recentItems)
        return matches.prefix(5).map {
            UniversalSearchItem(
                target: .recent($0),
                title: $0.title ?? $0.displayText,
                detail: "Create Board from Recent · \($0.displayText)"
            )
        }
    }

    private static func matchingRecentItems(query: String, recentItems: [RecentItem]) -> [RecentItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return recentItems }
        let terms = query.split(whereSeparator: \.isWhitespace)
        var exact: [RecentItem] = []
        var partial: [RecentItem] = []
        for item in recentItems {
            let input = item.displayText
            let searchable = "\(item.title ?? "") \(input)"
            guard terms.allSatisfy({ searchable.localizedCaseInsensitiveContains(String($0)) }) else { continue }
            if input.localizedCaseInsensitiveCompare(query) == .orderedSame
                || item.title?.localizedCaseInsensitiveCompare(query) == .orderedSame
            {
                exact.append(item)
            } else {
                partial.append(item)
            }
        }
        return exact + partial
    }
}
