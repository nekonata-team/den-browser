import DenDomain
import Foundation
import Observation

public enum UniversalSearchCommand: String, CaseIterable {
    case newDesk
    case openProfile
    case openSettings
    case toggleZenView
    case toggleFocusMode
    case restoreBoard
}

public struct UniversalSearchItem: Identifiable, Equatable {
    public enum Target: Hashable {
        case board(BoardID)
        case desk(DeskID)
        case profile(ProfileID)
        case essential(UUID)
        case createBoard(String)
        case command(UniversalSearchCommand)

        fileprivate var navigationID: UUID? {
            switch self {
            case .board(let id): id.rawValue
            case .desk(let id): id.rawValue
            case .profile(let id): id.rawValue
            case .essential, .createBoard, .command: nil
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
    public var selectedID: UniversalSearchItem.Target?
    public var message: String?
    public private(set) var submissionRequest = 0

    public init() {}

    public var commandsOnly: Bool { query.trimmingCharacters(in: .whitespaces).hasPrefix(">") }

    public var results: [UniversalSearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let terms = (commandsOnly ? String(trimmed.dropFirst()) : trimmed).split(whereSeparator: \.isWhitespace)
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
        if !commandsOnly, !trimmed.isEmpty {
            results.append(
                UniversalSearchItem(
                    target: .createBoard(trimmed), title: trimmed,
                    detail: "Create Board in the current Desk"))
        }
        return results
    }

    public var selectedItem: UniversalSearchItem? {
        results.first(where: { $0.id == selectedID }) ?? results.first
    }

    public func prepare(commandsOnly: Bool) {
        query = commandsOnly ? "> " : ""
        message = nil
    }

    public func moveSelection(by offset: Int) {
        selectedID = SelectionNavigation.next(selectedItem?.id, among: results.map(\.id), by: offset)
    }

    public func submit() { submissionRequest += 1 }
}
