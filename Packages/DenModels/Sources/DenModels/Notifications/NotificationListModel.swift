public import DenApplication
public import DenDomain
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
    private let state: DenStateStore
    private let operations: NotificationOperations
    @ObservationIgnored private let openSource: (BoardID?) -> Void
    public var selectedNotificationID: UUID?
    @ObservationIgnored public var onClose: (() -> Void)?
    @ObservationIgnored public var onRequestClearConfirmation: ((Int) -> Void)?

    public init(
        state: DenStateStore,
        operations: NotificationOperations,
        openSource: @escaping (BoardID?) -> Void
    ) {
        self.state = state
        self.operations = operations
        self.openSource = openSource
    }

    public var items: [NotificationListItem] {
        let snapshot = state.snapshot
        return snapshot.notifications.map { notification in
            let desk = snapshot.den.desks.first { desk in
                desk.boards.contains { $0.id == notification.boardID }
            }
            let board = desk?.boards.first { $0.id == notification.boardID }
            return NotificationListItem(
                notification: notification,
                source: board.flatMap { board in
                    desk.map { NotificationListItem.Source(deskLabel: $0.label, boardLabel: board.label) }
                })
        }
    }

    public var unreadCount: Int { operations.unreadCount() }
    public func unreadCount(for id: BoardID) -> Int { operations.unreadCount(for: id) }

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
        openSource(operations.prepareOpen(notification))
    }

    public func requestClear() {
        let count = state.snapshot.notifications.count
        guard count > 0 else { return }
        onRequestClearConfirmation?(count)
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
