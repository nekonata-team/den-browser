import Foundation

struct InspectionPageSnapshot: Decodable, Equatable {
    var isPicking: Bool
    var isCollecting: Bool
    var selection: InspectionElementSummary?
    var treePath: [InspectionDOMNode]
    var events: [InspectionConsoleEvent]

    static let empty = InspectionPageSnapshot(
        isPicking: false, isCollecting: false, selection: nil, treePath: [], events: [])
}

struct InspectionDOMNode: Decodable, Equatable, Identifiable {
    var id: String
    var tag: String
    var attributes: [InspectionDOMAttribute]
    var text: String
    var childCount: Int
}

struct InspectionDOMAttribute: Decodable, Equatable, Identifiable {
    var name: String
    var value: String
    var id: String { name }
}

struct InspectionElementSummary: Decodable, Equatable {
    var tag: String
    var id: String
    var className: String
    var role: String
    var ariaLabel: String
    var text: String
    var attributes: [String]
    var labels: [String]
    var ancestors: [String]
}

struct InspectionConsoleEvent: Decodable, Equatable, Identifiable {
    var id: String
    var time: String
    var level: String
    var message: String
}

enum InspectionPageScript {
    static let initialize: String = {
        guard
            let url = Bundle.main.url(forResource: "InspectionAgent", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()

    static let startPicking = #"window.__denInspection?.startPicking()"#

    static let collect = #"window.__denInspection?.startCollection()"#

    static let pauseCollection = #"window.__denInspection?.stopCollection()"#

    static let readSnapshot = #"""
        window.__denInspection?.readSnapshot()
          ?? JSON.stringify({ isPicking: false, isCollecting: false, selection: null, treePath: [], events: [] })
        """#

    static func readChildren(_ id: String) -> String {
        guard id.hasPrefix("n"), let number = Int(id.dropFirst()) else { return "[]" }
        return "window.__denInspection?.readChildren('n\(number)') ?? '[]'"
    }

    static func selectNode(_ id: String) -> String {
        guard id.hasPrefix("n"), let number = Int(id.dropFirst()) else { return "false" }
        return "window.__denInspection?.selectNode('n\(number)') ?? false"
    }

    static func highlightNode(_ id: String?) -> String {
        guard let id, id.hasPrefix("n"), let number = Int(id.dropFirst()) else {
            return "window.__denInspection?.clearHighlight()"
        }
        return "window.__denInspection?.highlightNode('n\(number)')"
    }

    static let stop = #"window.__denInspection?.stop()"#
}
