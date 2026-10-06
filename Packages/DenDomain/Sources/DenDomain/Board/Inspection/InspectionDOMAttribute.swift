import Foundation

public struct InspectionDOMAttribute: Decodable, Equatable, Identifiable, Sendable {
    public var name: String
    public var value: String
    public var id: String { name }
}
