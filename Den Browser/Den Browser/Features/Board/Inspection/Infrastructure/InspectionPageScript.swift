import Foundation

enum InspectionPageScript {
    static let initialize: String = {
        guard
            let url = Bundle.main.url(forResource: "InspectionAgent", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()

    static let startPicking = #"window.__denInspection?.startPicking()"#

    static func setHighlightColor(_ color: ProfileRGB) -> String {
        "window.__denInspection?.setHighlightColor({ red: \(color.red), green: \(color.green), blue: \(color.blue) })"
    }

    static let collect = #"window.__denInspection?.startCollection()"#

    static let readSnapshot = #"""
        window.__denInspection?.readSnapshot()
          ?? JSON.stringify({ documentID: null, collectionStartedAt: null, eventsDropped: 0, isPicking: false, isCollecting: false, selection: null, selectionConnected: false, treePath: [], events: [] })
        """#

    static func readChildren(_ id: String) -> String {
        guard id.hasPrefix("n"), let number = Int(id.dropFirst()) else { return "[]" }
        return "window.__denInspection?.readChildren('n\(number)') ?? '[]'"
    }

    static func readChildren(_ ids: [String]) -> String {
        let entries = ids.compactMap { id -> String? in
            guard id.hasPrefix("n"), let number = Int(id.dropFirst()) else { return nil }
            return "['n\(number)', JSON.parse(\(readChildren(id)))]"
        }
        return "JSON.stringify(Object.fromEntries([\(entries.joined(separator: ","))]))"
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
