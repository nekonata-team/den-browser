import Foundation

public struct InspectionPageSnapshot: Decodable, Equatable, Sendable {
    public var documentID: String?
    public var collectionStartedAt: String?
    public var eventsDropped: Int?
    public var isPicking: Bool
    public var isCollecting: Bool
    public var selection: InspectionElementSummary?
    public var selectionConnected: Bool?
    public var treePath: [InspectionDOMNode]
    public var events: [InspectionConsoleEvent]

    public static let empty = InspectionPageSnapshot(
        documentID: nil, collectionStartedAt: nil, eventsDropped: nil,
        isPicking: false, isCollecting: false, selection: nil, selectionConnected: nil, treePath: [], events: [])
}
