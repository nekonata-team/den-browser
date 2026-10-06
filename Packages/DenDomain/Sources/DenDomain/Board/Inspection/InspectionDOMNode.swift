import Foundation

public struct InspectionDOMNode: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var tag: String
    public var attributes: [InspectionDOMAttribute]
    public var text: String
    public var childCount: Int
}
