import Foundation

struct DrawerItem: Codable, Equatable, Identifiable {
    var id: UUID
    var url: URL
    var title: String?

    init(id: UUID = UUID(), url: URL, title: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
    }

    var displayName: String {
        title ?? url.host(percentEncoded: false) ?? url.absoluteString
    }
}
