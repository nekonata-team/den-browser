import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

extension DenController {
    func unreadNotificationCount(for boardID: BoardID) -> Int {
        storage.notificationOperations.unreadCount(for: boardID)
    }

    func clearNotifications() {
        storage.notificationOperations.clearAll()
        clearLatestNotificationFeedback()
    }

    func recordNotification(title: String?, body: String, boardID: BoardID) {
        guard let notification = storage.notificationOperations.record(title: title, body: body, boardID: boardID)
        else { return }
        onWindowEffect?(.notificationAdded(notification.id))
        reportFeedback(title: title, body: body, target: .notification(notification.id))
    }

    func openNotificationSource(_ boardID: BoardID?) {
        guard let boardID else {
            reportFeedback("Notification source Board no longer exists.", severity: .warning)
            return
        }
        onWindowEffect?(.dismissTemporaryPresentation)
        onWindowEffect?(.exitDenMode)
        focusBoard(boardID, exitsDenMode: true)
        if focusedDesk?.focusedBoardID == boardID { centerFocusedBoard() }
    }

    func markNotificationRead(_ notificationID: UUID) {
        storage.notificationOperations.markRead(notificationID)
    }

    func markNotificationsRead(for boardID: BoardID) {
        storage.notificationOperations.markAllRead(for: boardID)
    }
}
