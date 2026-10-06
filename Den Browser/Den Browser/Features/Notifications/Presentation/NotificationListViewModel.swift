import DenDomain
import Foundation
import Observation

@MainActor
@Observable
final class NotificationListViewModel {
    private let store: DenStore
    var selectedNotificationID: UUID?

    init(store: DenStore) {
        self.store = store
    }

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
        store.openNotification(notification)
    }

    func notificationWasAdded(_ notificationID: UUID) {
        if let selectedNotificationID,
            !store.notifications.contains(where: { $0.id == selectedNotificationID })
        {
            self.selectedNotificationID = notificationID
        }
    }
}
