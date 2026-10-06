import Foundation

public struct ProfileWindowRoute: Codable, Hashable {
    public let windowID: UUID
    public let profileID: UUID
    public let deskID: UUID?

    public init(windowID: UUID = UUID(), profileID: UUID, deskID: UUID? = nil) {
        self.windowID = windowID
        self.profileID = profileID
        self.deskID = deskID
    }
}
