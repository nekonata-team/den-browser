import Foundation

struct DenNotification: Equatable, Identifiable {
    let id: UUID
    let title: String?
    let body: String
    let boardID: UUID
    let createdAt: Date
    var isRead: Bool

    init(
        id: UUID = UUID(),
        title: String?,
        body: String,
        boardID: UUID,
        createdAt: Date = .now,
        isRead: Bool = false
    ) {
        self.id = id
        self.title = title?.isEmpty == false ? title : nil
        self.body = body
        self.boardID = boardID
        self.createdAt = createdAt
        self.isRead = isRead
    }
}
