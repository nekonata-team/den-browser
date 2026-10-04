import Foundation

struct InspectionPageSnapshot: Decodable, Equatable, Sendable {
    var documentID: String?
    var collectionStartedAt: String?
    var eventsDropped: Int?
    var isPicking: Bool
    var isCollecting: Bool
    var selection: InspectionElementSummary?
    var selectionConnected: Bool?
    var treePath: [InspectionDOMNode]
    var events: [InspectionConsoleEvent]

    static let empty = InspectionPageSnapshot(
        documentID: nil, collectionStartedAt: nil, eventsDropped: nil,
        isPicking: false, isCollecting: false, selection: nil, selectionConnected: nil, treePath: [], events: [])
}

struct InspectionDOMNode: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var tag: String
    var attributes: [InspectionDOMAttribute]
    var text: String
    var childCount: Int
}

struct InspectionDOMAttribute: Decodable, Equatable, Identifiable, Sendable {
    var name: String
    var value: String
    var id: String { name }
}

struct InspectionElementSummary: Decodable, Equatable, Sendable {
    var nodeID: String?
    var selector: String?
    var tag: String
    var id: String
    var className: String
    var role: String
    var ariaLabel: String
    var text: String
    var attributes: [String]
    var labels: [String]
    var capturedAt: String?
}

struct InspectionConsoleEvent: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var time: String
    var timestamp: String?
    var level: String
    var message: String
}
