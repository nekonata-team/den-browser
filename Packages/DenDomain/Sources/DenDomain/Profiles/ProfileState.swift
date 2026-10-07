import Foundation

public struct ProfileState: Codable, Equatable, Identifiable {
    public var id: ProfileID
    public var name: String
    public var color: ProfileColor
    public var webProfileStore: WebProfileStore

    public init(id: ProfileID, name: String, color: ProfileColor, webProfileStore: WebProfileStore) {
        self.id = id
        self.name = name
        self.color = color
        self.webProfileStore = webProfileStore
    }
}
