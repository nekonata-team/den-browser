import Foundation

public struct DrawerItem: Codable, Equatable, Identifiable {
    public var id: UUID
    public var url: URL
    public var title: String?

    public init(id: UUID = UUID(), url: URL, title: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
    }

    public var displayName: String {
        title ?? url.host(percentEncoded: false) ?? url.absoluteString
    }
}
