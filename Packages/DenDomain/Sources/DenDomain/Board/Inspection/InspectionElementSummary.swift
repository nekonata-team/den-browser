import Foundation

public struct InspectionElementSummary: Decodable, Equatable, Sendable {
    public var nodeID: String?
    public var selector: String?
    public var tag: String
    public var id: String
    public var className: String
    public var role: String
    public var ariaLabel: String
    public var text: String
    public var attributes: [String]
    public var labels: [String]
    public var capturedAt: String?
}
