import Foundation

public struct DenNotification: Equatable, Identifiable {
    public let id: UUID
    public let title: String?
    public let body: String
    public let boardID: BoardID
    public let createdAt: Date
    public var isRead: Bool

    public init(
        id: UUID = UUID(),
        title: String?,
        body: String,
        boardID: BoardID,
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
