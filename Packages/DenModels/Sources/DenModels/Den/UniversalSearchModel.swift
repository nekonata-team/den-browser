import DenDomain
import Foundation
import Observation

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

    public var commandsOnly: Bool { UniversalSearch.isCommandsOnly(query) }

    public var results: [UniversalSearchItem] {
        UniversalSearch.results(query: query, items: items, recentItems: recentItems)
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
}
