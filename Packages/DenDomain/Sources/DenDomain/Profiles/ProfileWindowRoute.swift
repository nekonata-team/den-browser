import Foundation

public struct ProfileWindowRoute: Codable, Hashable {
    public let windowID: UUID
    public let profileID: ProfileID
    public let deskID: DeskID?

    public init(windowID: UUID = UUID(), profileID: ProfileID, deskID: DeskID? = nil) {
        self.windowID = windowID
        self.profileID = profileID
        self.deskID = deskID
    }
}
