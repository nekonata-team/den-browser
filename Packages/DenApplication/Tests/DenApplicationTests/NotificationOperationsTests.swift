import DenApplication
import DenDomain
import Foundation
import Testing

@MainActor
struct NotificationOperationsTests {
    @Test(arguments: [nil, ""] as [String?])
    func emptyMessagesAreIgnored(title: String?) {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let operations = NotificationOperations(store: shared.store, writer: shared.writer)

        // Act
        let result = operations.record(title: title, body: "", boardID: BoardID())

        // Assert
        #expect(result == nil)
        #expect(shared.store.snapshot.notifications.isEmpty)
    }

    @Test func recordingKeepsNewestMessagesWithinTheLimit() throws {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let operations = NotificationOperations(store: shared.store, writer: shared.writer)
        let boardID = BoardID()
        let initial = (0..<NotificationOperations.maximumNotificationCount).map { index in
            DenNotification(title: nil, body: "Message \(index)", boardID: boardID)
        }
        shared.writer.update { $0.notifications = initial }

        // Act
        let notification = try #require(operations.record(title: "", body: "Body", boardID: boardID))

        // Assert
        #expect(notification.title == nil)
        #expect(!notification.isRead)
        #expect(notification.boardID == boardID)
        #expect(shared.store.snapshot.notifications == [notification] + initial.dropLast())
        #expect(operations.unreadCount() == NotificationOperations.maximumNotificationCount)
    }

    @Test func markReadChangesOnlyTheRequestedMessage() {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let operations = NotificationOperations(store: shared.store, writer: shared.writer)
        let first = DenNotification(title: "First", body: "", boardID: BoardID())
        let second = DenNotification(title: "Second", body: "", boardID: BoardID())
        shared.writer.update { $0.notifications = [first, second] }

        // Act
        operations.markRead(first.id)

        // Assert
        #expect(shared.store.snapshot.notifications.map(\.isRead) == [true, false])
        #expect(operations.unreadCount() == 1)
    }

    @Test func markAllReadIsScopedToTheBoard() {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let operations = NotificationOperations(store: shared.store, writer: shared.writer)
        let boardID = BoardID()
        shared.writer.update {
            $0.notifications = [
                DenNotification(title: "First", body: "", boardID: boardID),
                DenNotification(title: "Second", body: "", boardID: boardID),
                DenNotification(title: "Other", body: "", boardID: BoardID()),
            ]
        }

        // Act
        operations.markAllRead(for: boardID)

        // Assert
        #expect(shared.store.snapshot.notifications.map(\.isRead) == [true, true, false])
        #expect(operations.unreadCount(for: boardID) == 0)
        #expect(operations.unreadCount() == 1)
    }

    @Test(arguments: [false, true])
    func prepareOpenMarksReadAndResolvesTheCurrentSource(sourceExists: Bool) {
        // Arrange
        let board = BoardState(label: "Source", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: sourceExists ? [board] : [], focusedBoardID: nil)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let operations = NotificationOperations(store: shared.store, writer: shared.writer)
        let notification = DenNotification(title: "Message", body: "", boardID: board.id)
        shared.writer.update { $0.notifications = [notification] }

        // Act
        let result = operations.prepareOpen(notification)

        // Assert
        #expect(result == (sourceExists ? board.id : nil))
        #expect(shared.store.snapshot.notifications.first?.isRead == true)
    }

    @Test func clearRemovesReadAndUnreadMessages() {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let operations = NotificationOperations(store: shared.store, writer: shared.writer)
        shared.writer.update {
            $0.notifications = [
                DenNotification(title: "Read", body: "", boardID: BoardID(), isRead: true),
                DenNotification(title: "Unread", body: "", boardID: BoardID()),
            ]
        }

        // Act
        operations.clearAll()

        // Assert
        #expect(shared.store.snapshot.notifications.isEmpty)
        #expect(operations.unreadCount() == 0)
    }
}
