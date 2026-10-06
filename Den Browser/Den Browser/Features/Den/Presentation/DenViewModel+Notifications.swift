import Foundation

@MainActor
extension DenViewModel {
    var notificationPendingDeletionCount: Int? {
        guard case .clearNotifications(let count)? = pendingConfirmation else { return nil }
        return count
    }

    func toggleNotificationList() {
        guard temporaryContext == nil else { return }
        if isNotificationListPresented {
            closeNotificationList()
        } else {
            deskFilter.dismiss()
            isNotificationListPresented = true
            notificationList.selectFirstNotification()
        }
    }

    func closeNotificationList() {
        isNotificationListPresented = false
        notificationList.clearSelection()
    }

    func cancelNotificationClear() {
        if case .clearNotifications? = pendingConfirmation {
            pendingConfirmation = nil
        }
    }

    func confirmNotificationClear() {
        guard notificationPendingDeletionCount != nil else { return }
        store.clearNotifications()
        closeNotificationList()
        pendingConfirmation = nil
    }
}
