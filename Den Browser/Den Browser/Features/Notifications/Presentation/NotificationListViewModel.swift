import DenDomain
import Foundation
import Observation

struct NotificationListItem: Identifiable {
    let notification: DenNotification
    let source: DenNotificationSource?

    var id: UUID { notification.id }
}

@MainActor
@Observable
final class NotificationListViewModel {
    private let store: DenStore
    var selectedNotificationID: UUID?
    @ObservationIgnored var onClose: (() -> Void)?

    init(store: DenStore) {
        self.store = store
    }

    var items: [NotificationListItem] {
        store.notifications.map { notification in
            NotificationListItem(
                notification: notification,
                source: store.notificationSource(for: notification))
        }
    }

    var unreadCount: Int { store.unreadNotificationCount }

    func selectFirstNotification() {
        selectedNotificationID = store.notifications.first?.id
    }

    func clearSelection() {
        selectedNotificationID = nil
    }

    func moveSelection(by offset: Int) {
        selectedNotificationID = DenSelectionNavigation.next(
            selectedNotificationID,
            among: store.notifications.map(\.id),
            by: offset)
    }

    func openSelectedNotification() {
        guard
            let selectedNotificationID,
            let notification = store.notifications.first(where: { $0.id == selectedNotificationID })
        else { return }
        open(notification)
    }

    func open(_ notification: DenNotification) {
        store.openNotification(notification)
    }

    func requestClear() {
        store.requestNotificationClearConfirmation()
    }

    func close() {
        onClose?()
    }

    func notificationWasAdded(_ notificationID: UUID) {
        if let selectedNotificationID,
            !store.notifications.contains(where: { $0.id == selectedNotificationID })
        {
            self.selectedNotificationID = notificationID
        }
    }
}
