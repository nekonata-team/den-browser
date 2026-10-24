public import DenDomain
import Foundation

/// Profile-shared notification operations; no window state or presentation callbacks.
public final class NotificationOperations {
    public static let maximumNotificationCount = 200
    private let store: DenStateReader
    private let writer: DenStateWriter

    public init(store: DenStateReader, writer: DenStateWriter) {
        self.store = store
        self.writer = writer
    }

    public func unreadCount(for boardID: BoardID? = nil) -> Int {
        store.snapshot.notifications.lazy.filter {
            !$0.isRead && (boardID == nil || $0.boardID == boardID)
        }.count
    }

    @discardableResult
    public func record(title: String?, body: String, boardID: BoardID) -> DenNotification? {
        guard title?.isEmpty == false || !body.isEmpty else { return nil }
        let notification = DenNotification(title: title, body: body, boardID: boardID)
        writer.update { state in
            state.notifications.insert(notification, at: 0)
            if state.notifications.count > Self.maximumNotificationCount {
                state.notifications.removeLast(state.notifications.count - Self.maximumNotificationCount)
            }
        }
        return notification
    }

    public func markRead(_ notificationID: UUID) {
        guard store.snapshot.notifications.contains(where: { $0.id == notificationID && !$0.isRead }) else { return }
        writer.update { state in
            guard let index = state.notifications.firstIndex(where: { $0.id == notificationID }) else { return }
            state.notifications[index].isRead = true
        }
    }

    public func markAllRead(for boardID: BoardID) {
        guard store.snapshot.notifications.contains(where: { $0.boardID == boardID && !$0.isRead }) else { return }
        writer.update { state in
            for index in state.notifications.indices where state.notifications[index].boardID == boardID {
                state.notifications[index].isRead = true
            }
        }
    }

    /// Marks the message read before handing its current source to the invoking window.
    public func prepareOpen(_ notification: DenNotification) -> BoardID? {
        let exists = store.snapshot.den.desks.contains { desk in
            desk.boards.contains { $0.id == notification.boardID }
        }
        markRead(notification.id)
        return exists ? notification.boardID : nil
    }

    public func clearAll() {
        guard !store.snapshot.notifications.isEmpty else { return }
        writer.update { $0.notifications.removeAll() }
    }
}
