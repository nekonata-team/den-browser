import DenDomain
import Foundation
import Observation

public struct NotificationListItem: Identifiable {
    public let notification: DenNotification
    public struct Source {
        public let deskLabel: String
        public let boardLabel: String

        public init(deskLabel: String, boardLabel: String) {
            self.deskLabel = deskLabel
            self.boardLabel = boardLabel
        }
    }

    public let source: Source?

    public init(notification: DenNotification, source: Source?) {
        self.notification = notification
        self.source = source
    }

    public var id: UUID { notification.id }
}

@MainActor
@Observable
public final class NotificationListModel {
    @ObservationIgnored private let itemProvider: () -> [NotificationListItem]
    @ObservationIgnored private let openNotification: (DenNotification) -> Void
    @ObservationIgnored private let requestClearConfirmation: () -> Void
    public var selectedNotificationID: UUID?
    @ObservationIgnored public var onClose: (() -> Void)?

    public init(
        items: @escaping () -> [NotificationListItem],
        openNotification: @escaping (DenNotification) -> Void,
        requestClearConfirmation: @escaping () -> Void
    ) {
        itemProvider = items
        self.openNotification = openNotification
        self.requestClearConfirmation = requestClearConfirmation
    }

    public var items: [NotificationListItem] {
        itemProvider()
    }

    public var unreadCount: Int { items.lazy.filter { !$0.notification.isRead }.count }

    public func selectFirstNotification() {
        selectedNotificationID = items.first?.id
    }

    public func clearSelection() {
        selectedNotificationID = nil
    }

    public func moveSelection(by offset: Int) {
        selectedNotificationID = SelectionNavigation.next(
            selectedNotificationID,
            among: items.map(\.id),
            by: offset)
    }

    public func openSelectedNotification() {
        guard
            let selectedNotificationID,
            let notification = items.first(where: { $0.id == selectedNotificationID })?.notification
        else { return }
        open(notification)
    }

    public func open(_ notification: DenNotification) {
        openNotification(notification)
    }

    public func requestClear() {
        requestClearConfirmation()
    }

    public func close() {
        onClose?()
    }

    public func notificationWasAdded(_ notificationID: UUID) {
        if let selectedNotificationID,
            !items.contains(where: { $0.id == selectedNotificationID })
        {
            self.selectedNotificationID = notificationID
        }
    }
}
