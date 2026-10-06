import Foundation

public struct InspectionConsoleEvent: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var time: String
    public var timestamp: String?
    public var level: String
    public var message: String
}
