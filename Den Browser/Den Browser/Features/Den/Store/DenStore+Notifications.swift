import Foundation

struct DenNotificationSource {
    let deskLabel: String
    let boardLabel: String
}

extension DenStore {
    func requestNotificationClearConfirmation() {
        guard !notifications.isEmpty else { return }
        pendingConfirmation = .clearNotifications(notifications.count)
    }

    func confirmNotificationClear() {
        guard notificationPendingDeletionCount != nil else { return }
        notifications.removeAll()
        if let target = toastMessage?.target, case .notification = target {
            dismissToast()
        }
        closeNotificationList()
        pendingConfirmation = nil
    }

    func cancelNotificationClear() {
        if notificationPendingDeletionCount != nil {
            pendingConfirmation = nil
        }
    }

    func toggleNotificationList() {
        guard temporaryContext == nil else { return }
        if isNotificationListPresented {
            closeNotificationList()
        } else {
            isNotificationListPresented = true
            selectedNotificationID = notifications.first?.id
        }
    }

    func closeNotificationList() {
        isNotificationListPresented = false
        selectedNotificationID = nil
    }

    func recordNotification(title: String?, body: String, boardID: UUID) {
        guard title?.isEmpty == false || !body.isEmpty else { return }
        let notification = DenNotification(title: title, body: body, boardID: boardID)
        notifications.insert(notification, at: 0)
        if notifications.count > Self.maximumNotificationCount {
            notifications.removeLast(notifications.count - Self.maximumNotificationCount)
        }
        if let selectedNotificationID,
            !notifications.contains(where: { $0.id == selectedNotificationID })
        {
            self.selectedNotificationID = notifications.first?.id
        }
        showToast(title: title, body: body, target: .notification(notification.id))
    }

    func moveNotificationSelection(by offset: Int) {
        guard !notifications.isEmpty else { return }
        let currentIndex =
            selectedNotificationID.flatMap { id in
                notifications.firstIndex { $0.id == id }
            } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), notifications.count - 1)
        selectedNotificationID = notifications[nextIndex].id
    }

    func openSelectedNotification() {
        guard
            let selectedNotificationID,
            let notification = notifications.first(where: { $0.id == selectedNotificationID })
        else { return }
        openNotification(notification)
    }

    func openNotification(_ notification: DenNotification) {
        guard boardIndices(for: notification.boardID) != nil else {
            markNotificationRead(notification.id)
            showToast("Notification source Board no longer exists.", style: .warning)
            return
        }
        markNotificationRead(notification.id)
        closeNotificationList()
        setTemporaryContext(nil)
        focusBoard(notification.boardID, exitsDenMode: true)
    }

    func markNotificationRead(_ notificationID: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        notifications[index].isRead = true
    }

    func notificationSource(for notification: DenNotification) -> DenNotificationSource? {
        guard let indices = boardIndices(for: notification.boardID) else { return nil }
        let desk = state.desks[indices.desk]
        let board = desk.boards[indices.board]
        return DenNotificationSource(deskLabel: desk.label, boardLabel: board.label)
    }
}
