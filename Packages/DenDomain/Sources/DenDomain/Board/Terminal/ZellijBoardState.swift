import Foundation

public struct ZellijBoardState: Codable, Equatable {
    public var sessionName: String?

    public init(sessionName: String?) {
        self.sessionName = sessionName
    }
}
