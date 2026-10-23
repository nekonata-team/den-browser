import Foundation

public struct DownloadActivity: Equatable, Identifiable {
    public let id: UUID
    public let filename: String
    public var fractionCompleted: Double?

    public init(id: UUID = UUID(), filename: String, fractionCompleted: Double? = nil) {
        self.id = id
        self.filename = filename
        self.fractionCompleted = fractionCompleted
    }
}

public enum DownloadActivityEvent: Equatable {
    case started(DownloadActivity)
    case progressed(id: UUID, fractionCompleted: Double?)
    case ended(id: UUID)
}
