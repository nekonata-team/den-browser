import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

@MainActor
final class NotificationDelivery {
    private let context: WindowNativeContext
    private let boardNavigation: BoardNavigation
    private var storage: DenProfileResources { context.storage }
    private var focusedDesk: DeskState? { context.focusedDesk }
    private var notifications: [DenNotification] { context.storage.notifications }
    private var onWindowEffect: ((DenWindowEffect) -> Void)? { context.connection.onWindowEffect }

    init(context: WindowNativeContext, boardNavigation: BoardNavigation) {
        self.context = context
        self.boardNavigation = boardNavigation
    }

    func clearNotifications() {
        storage.notificationOperations.clearAll()
        context.feedback.clearNotification()
    }

    func recordNotification(title: String?, body: String, boardID: BoardID) {
        guard let notification = storage.notificationOperations.record(title: title, body: body, boardID: boardID)
        else { return }
        onWindowEffect?(.notificationAdded(notification.id))
        context.feedback.publish(title: title, body: body, target: .notification(notification.id))
    }

    func openNotificationSource(_ boardID: BoardID?) {
        guard let boardID else {
            context.feedback.publish("Notification source Board no longer exists.", severity: .warning)
            return
        }
        onWindowEffect?(.dismissTemporaryPresentation)
        onWindowEffect?(.exitDenMode)
        boardNavigation.focusBoard(boardID, exitsDenMode: true)
        if focusedDesk?.focusedBoardID == boardID { boardNavigation.centerFocusedBoard() }
    }

    func openFeedbackTarget(_ target: DenFeedback.Target?) {
        guard let target else { return }
        switch target {
        case .board(let boardID):
            guard context.boardIndices(for: boardID) != nil else { return }
            onWindowEffect?(.dismissTemporaryPresentation)
            onWindowEffect?(.exitDenMode)
            boardNavigation.focusBoard(boardID, exitsDenMode: true)
            if focusedDesk?.focusedBoardID == boardID { boardNavigation.centerFocusedBoard() }
        case .drawerItem(let itemID):
            onWindowEffect?(.openDrawerItem(itemID))
        case .notification(let notificationID):
            guard let notification = notifications.first(where: { $0.id == notificationID }) else {
                return
            }
            storage.notificationOperations.markRead(notificationID)
            guard context.boardIndices(for: notification.boardID) != nil else { return }
            onWindowEffect?(.dismissTemporaryPresentation)
            onWindowEffect?(.exitDenMode)
            boardNavigation.focusBoard(notification.boardID, exitsDenMode: true)
            if focusedDesk?.focusedBoardID == notification.boardID { boardNavigation.centerFocusedBoard() }
        }
    }
}
