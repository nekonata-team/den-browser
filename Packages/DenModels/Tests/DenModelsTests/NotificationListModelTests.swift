import DenApplication
import DenDomain
import DenModels
import Foundation
import Observation
import Synchronization
import Testing

@MainActor
private final class NotificationWindowStub {
    var openedSources: [BoardID?] = []
    var confirmationCounts: [Int] = []
    var onOpen: (() -> Void)?

    func openNotificationSource(_ boardID: BoardID?) {
        onOpen?()
        openedSources.append(boardID)
    }

    func requestNotificationClearConfirmation(count: Int) {
        confirmationCounts.append(count)
    }
}

private final class NotificationObservation: Sendable {
    let changed = Mutex(false)
}

@MainActor
struct NotificationListModelTests {
    enum Update: CaseIterable {
        case added, read, sourceTitleChanged, sourceRemoved, cleared
    }

    @Test(arguments: Update.allCases)
    func twoWindowModelsObserveTheSameStore(update: Update) throws {
        // Arrange
        let board = BoardState(label: "Board", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let operations = NotificationOperations(store: shared.store, writer: shared.writer)
        let notification = try #require(operations.record(title: "Build", body: "Finished", boardID: board.id))
        let models = (0..<2).map { _ in
            NotificationListModel(
                state: shared.store, operations: operations, openSource: NotificationWindowStub().openNotificationSource
            )
        }
        let observations = models.map { model in
            let observation = NotificationObservation()
            withObservationTracking {
                _ = model.items
                _ = model.unreadCount
            } onChange: {
                observation.changed.withLock { $0 = true }
            }
            return observation
        }

        // Act
        switch update {
        case .added: operations.record(title: "Another", body: "", boardID: board.id)
        case .read: operations.markRead(notification.id)
        case .sourceTitleChanged: shared.writer.update { $0.den.desks[0].boards[0].label = "Updated" }
        case .sourceRemoved: shared.writer.update { $0.den.desks[0].boards.removeAll() }
        case .cleared: operations.clearAll()
        }

        // Assert
        #expect(observations.allSatisfy { $0.changed.withLock { $0 } })
        for model in models {
            switch update {
            case .added:
                #expect(model.items.count == 2)
                #expect(model.unreadCount == 2)
            case .read:
                #expect(model.items.first?.notification.isRead == true)
                #expect(model.unreadCount == 0)
            case .sourceTitleChanged: #expect(model.items.first?.source?.boardLabel == "Updated")
            case .sourceRemoved: #expect(model.items.first?.source == nil)
            case .cleared:
                #expect(model.items.isEmpty)
                #expect(model.unreadCount == 0)
            }
        }
    }

    @Test(arguments: [false, true])
    func openingUpdatesReadStateBeforeNotifyingOnlyTheInvokingWindow(sourceExists: Bool) throws {
        // Arrange
        let board = BoardState(label: "Board", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: sourceExists ? [board] : [], focusedBoardID: nil)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let operations = NotificationOperations(store: shared.store, writer: shared.writer)
        let notification = try #require(operations.record(title: "Build", body: "Finished", boardID: board.id))
        let first = NotificationWindowStub()
        let second = NotificationWindowStub()
        let model = NotificationListModel(
            state: shared.store, operations: operations, openSource: first.openNotificationSource)
        let other = NotificationListModel(
            state: shared.store, operations: operations, openSource: second.openNotificationSource)
        first.onOpen = { #expect(shared.store.snapshot.notifications.first?.isRead == true) }

        // Act
        model.open(notification)

        // Assert
        #expect(first.openedSources == [sourceExists ? board.id : nil])
        #expect(second.openedSources.isEmpty)
        #expect(other.unreadCount == 0)
    }

    @Test(arguments: [false, true])
    func clearRequestsConfirmationOnlyWhenThereAreMessages(hasMessages: Bool) {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let operations = NotificationOperations(store: shared.store, writer: shared.writer)
        if hasMessages { operations.record(title: "Build", body: "", boardID: BoardID()) }
        let window = NotificationWindowStub()
        let model = NotificationListModel(
            state: shared.store, operations: operations, openSource: window.openNotificationSource)
        model.onRequestClearConfirmation = window.requestNotificationClearConfirmation

        // Act
        model.requestClear()

        // Assert
        #expect(window.confirmationCounts == (hasMessages ? [1] : []))
        #expect(shared.store.snapshot.notifications.count == (hasMessages ? 1 : 0))
    }

    @Test func selectionFollowsHistoryAndOpensTheSelectedMessage() throws {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let operations = NotificationOperations(store: shared.store, writer: shared.writer)
        let first = try #require(operations.record(title: "First", body: "", boardID: BoardID()))
        operations.record(title: "Second", body: "", boardID: BoardID())
        let window = NotificationWindowStub()
        let model = NotificationListModel(
            state: shared.store, operations: operations, openSource: window.openNotificationSource)
        model.selectFirstNotification()

        // Act
        model.moveSelection(by: 1)
        model.openSelectedNotification()

        // Assert
        #expect(model.selectedNotificationID == first.id)
        #expect(window.openedSources.count == 1)
        #expect(shared.store.snapshot.notifications.last?.isRead == true)
    }
}
