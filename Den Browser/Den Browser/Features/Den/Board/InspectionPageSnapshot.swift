import Foundation

struct InspectionPageSnapshot: Decodable, Equatable {
    var isPicking: Bool
    var selection: InspectionElementSummary?
    var events: [InspectionConsoleEvent]

    static let empty = InspectionPageSnapshot(isPicking: false, selection: nil, events: [])
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
    static let startPicking: String = {
        guard
            let url = Bundle.main.url(forResource: "InspectionAgent", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()

    static let readSnapshot = #"""
        window.__denInspection?.readSnapshot()
          ?? JSON.stringify({ isPicking: false, selection: null, events: [] })
        """#

    static let stop = #"window.__denInspection?.stop()"#
}
