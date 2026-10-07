import Foundation

public struct ProfileWindowRoute: Codable, Hashable {
    public let windowID: UUID
    public let profileID: UUID
    public let deskID: DeskID?

    public init(windowID: UUID = UUID(), profileID: UUID, deskID: DeskID? = nil) {
        self.windowID = windowID
        self.profileID = profileID
        self.deskID = deskID
    }
}
