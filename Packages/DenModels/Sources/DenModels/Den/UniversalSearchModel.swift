import DenDomain
import Foundation
import Observation

public enum UniversalSearchCommand: String, CaseIterable {
    case newDesk
    case openProfile
    case openSettings
    case toggleZenView
    case toggleFocusMode
    case undoBoardOperation
}

public struct UniversalSearchItem: Identifiable, Equatable {
    public enum Target: Hashable {
        case board(BoardID)
        case desk(DeskID)
        case profile(ProfileID)
        case essential(UUID)
        case recent(RecentItem)
        case createBoard(String)
        case command(UniversalSearchCommand)

        fileprivate var navigationID: UUID? {
            switch self {
            case .board(let id): id.rawValue
            case .desk(let id): id.rawValue
            case .profile(let id): id.rawValue
            case .essential, .recent, .createBoard, .command: nil
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

@MainActor
@Observable
public final class UniversalSearchModel {
    public var query = "" {
        didSet {
            let stripped = WebURLPolicy.stripNewlines(query)
            if query != stripped { query = stripped }
            selectedID = nil
        }
    }
    public var items: [UniversalSearchItem] = []
    public var recentItems: [RecentItem] = []
    public var selectedID: UniversalSearchItem.Target?
    public var message: String?
    public private(set) var submissionRequest = 0
    public private(set) var submitsInDrawer = false

    public init() {}

    public var commandsOnly: Bool { query.trimmingCharacters(in: .whitespaces).hasPrefix(">") }

    public var results: [UniversalSearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let terms = (commandsOnly ? String(trimmed.dropFirst()) : trimmed).split(whereSeparator: \.isWhitespace)
        let recentResults = commandsOnly ? [] : recentResults(query: trimmed)
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
                    target: .createBoard(trimmed), title: trimmed,
                    detail: "Create Board in the current Desk"))
        }
        return results
    }

    private func recentResults(query: String) -> [UniversalSearchItem] {
        let matches = matchingRecentItems(query: query)
        return matches.prefix(5).map {
            UniversalSearchItem(
                target: .recent($0), title: $0.title ?? $0.displayText,
                detail: "Create Board from Recent · \($0.displayText)")
        }
    }

    public var selectedItem: UniversalSearchItem? {
        let results = results
        return results.first(where: { $0.id == selectedID }) ?? results.first
    }

    public func prepare(commandsOnly: Bool) {
        query = commandsOnly ? "> " : ""
        message = nil
    }

    public func moveSelection(by offset: Int) {
        selectedID = SelectionNavigation.next(selectedItem?.id, among: results.map(\.id), by: offset)
    }

    public func submit(inDrawer: Bool = false) {
        submitsInDrawer = inDrawer
        submissionRequest += 1
    }

    private func matchingRecentItems(query: String) -> [RecentItem] {
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
