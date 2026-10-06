import Foundation

struct DenNotificationSource {
    let deskLabel: String
    let boardLabel: String
}

extension DenStore {
    func unreadNotificationCount(for boardID: UUID) -> Int {
        notifications.lazy.filter { $0.boardID == boardID && !$0.isRead }.count
    }

    func requestNotificationClearConfirmation() {
        guard !notifications.isEmpty else { return }
        onWindowEffect?(.requestConfirmation(.clearNotifications(notifications.count)))
    }

    func clearNotifications() {
        notifications.removeAll()
        clearLatestNotificationFeedback()
    }

    func recordNotification(title: String?, body: String, boardID: UUID) {
        guard title?.isEmpty == false || !body.isEmpty else { return }
        let notification = DenNotification(title: title, body: body, boardID: boardID)
        notifications.insert(notification, at: 0)
        if notifications.count > Self.maximumNotificationCount {
            notifications.removeLast(notifications.count - Self.maximumNotificationCount)
        }
        onWindowEffect?(.notificationAdded(notification.id))
        reportFeedback(title: title, body: body, target: .notification(notification.id))
    }

    func openNotification(_ notification: DenNotification) {
        guard boardIndices(for: notification.boardID) != nil else {
            markNotificationRead(notification.id)
            reportFeedback("Notification source Board no longer exists.", severity: .warning)
            return
        }
        markNotificationRead(notification.id)
        onWindowEffect?(.dismissTemporaryPresentation)
        onWindowEffect?(.exitDenMode)
        focusBoard(notification.boardID, exitsDenMode: true)
    }

    func markNotificationRead(_ notificationID: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        notifications[index].isRead = true
    }

    func markNotificationsRead(for boardID: UUID) {
        for index in notifications.indices {
            guard notifications[index].boardID == boardID, !notifications[index].isRead else { continue }
            notifications[index].isRead = true
        }
    }

    func notificationSource(for notification: DenNotification) -> DenNotificationSource? {
        guard let indices = boardIndices(for: notification.boardID) else { return nil }
        let desk = state.desks[indices.desk]
        let board = desk.boards[indices.board]
        return DenNotificationSource(deskLabel: desk.label, boardLabel: board.label)
    }
}
