import Foundation

public struct ZmxBoardState: Codable, Equatable {
    public var sessionName: String
    public var workingDirectory: String
    public var rootSessionName: String?

    public init(sessionName: String, workingDirectory: String, rootSessionName: String? = nil) {
        self.sessionName = sessionName
        self.workingDirectory = workingDirectory
        self.rootSessionName = rootSessionName
    }
}
