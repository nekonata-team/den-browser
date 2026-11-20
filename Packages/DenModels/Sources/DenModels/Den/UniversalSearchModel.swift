import DenDomain
import Foundation
import Observation

@MainActor
@Observable
public final class UniversalSearchModel {
    public var query = "" {
        didSet {
            let stripped = WebURLPolicy.stripNewlines(query)
            if query != stripped {
                query = stripped
                return
            }
            selectedID = nil
            recomputeResults()
        }
    }
    public var items: [UniversalSearchItem] = [] {
        didSet { recomputeResults() }
    }
    public var recentItems: [RecentItem] = [] {
        didSet { recomputeResults() }
    }
    public var selectedID: UniversalSearchItem.Target?
    public var message: String?
    public private(set) var submissionRequest = 0
    public private(set) var submitsInDrawer = false
    public private(set) var results: [UniversalSearchItem] = []

    public init() {}

    public var commandsOnly: Bool { UniversalSearch.isCommandsOnly(query) }

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

    public func submit(inDrawer: Bool = false) {
        submitsInDrawer = inDrawer
        submissionRequest += 1
    }

    private func recomputeResults() {
        results = UniversalSearch.results(query: query, items: items, recentItems: recentItems)
    }
}
