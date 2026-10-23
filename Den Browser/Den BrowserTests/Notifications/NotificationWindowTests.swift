import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct NotificationWindowTests {
    @Test func recordingNotificationAddsUnreadHistoryAndTargetedFeedback() {
        // Arrange
        let target = board("Terminal")
        let desk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        var effects: [String] = []
        session.connection.onWindowEffect = { effect in
            switch effect {
            case .notificationAdded(let id):
                #expect(session.resources.notifications.first?.id == id)
                effects.append("notification")
            case .feedback:
                effects.append("feedback")
            default: break
            }
        }
        defer { session.connection.onWindowEffect = nil }

        // Act
        session.notifications.recordNotification(title: "Build", body: "Finished", boardID: target.id)

        // Assert
        #expect(session.resources.notifications.count == 1)
        #expect(session.resources.notifications[0].title == "Build")
        #expect(session.resources.notifications[0].body == "Finished")
        #expect(session.resources.notifications[0].boardID == target.id)
        #expect(session.resources.notificationOperations.unreadCount() == 1)
        #expect(session.feedback.latest?.target == .notification(session.resources.notifications[0].id))
        #expect(effects == ["notification", "feedback"])
    }

    @Test func focusingBoardMarksItsUnreadNotificationsRead() {
        // Arrange
        let currentBoard = board("Current")
        let targetBoard = board("Target")
        let desk = desk("Desk", boards: [currentBoard, targetBoard], focusedBoardID: currentBoard.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        session.notifications.recordNotification(title: "First", body: "Finished", boardID: targetBoard.id)
        session.notifications.recordNotification(title: "Second", body: "Finished", boardID: targetBoard.id)
        session.notifications.recordNotification(title: "Other", body: "Finished", boardID: currentBoard.id)

        // Act
        session.boardNavigation.focusBoard(targetBoard.id)

        // Assert
        #expect(session.navigation.focusedBoard?.id == targetBoard.id)
        #expect(session.resources.notificationOperations.unreadCount(for: targetBoard.id) == 0)
        #expect(session.resources.notificationOperations.unreadCount(for: currentBoard.id) == 1)
        #expect(session.resources.notificationOperations.unreadCount() == 1)
    }

    @Test func focusingDeskMarksItsFocusedBoardNotificationsRead() {
        // Arrange
        let currentBoard = board("Current")
        let targetBoard = board("Target")
        let currentDesk = desk("Current", boards: [currentBoard], focusedBoardID: currentBoard.id)
        let targetDesk = desk("Target", boards: [targetBoard], focusedBoardID: targetBoard.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [currentDesk, targetDesk], focusedDeskID: currentDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        session.notifications.recordNotification(title: "Build", body: "Finished", boardID: targetBoard.id)

        // Act
        session.boardNavigation.focusDesk(targetDesk.id)

        // Assert
        #expect(session.resources.notificationOperations.unreadCount(for: targetBoard.id) == 0)
        #expect(session.resources.notificationOperations.unreadCount() == 0)
    }

    @Test func clearingNotificationsRemovesSessionHistoryAfterConfirmation() {
        // Arrange
        let target = board("Terminal")
        let desk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        session.notifications.recordNotification(title: "Build", body: "Finished", boardID: target.id)
        windowModel.toggleNotificationList()
        var confirmationEffects = 0
        let deliverEffect = session.connection.onWindowEffect
        session.connection.onWindowEffect = { effect in
            if case .requestConfirmation = effect { confirmationEffects += 1 }
            deliverEffect?(effect)
        }
        // Act
        windowModel.notificationList.requestClear()

        let confirmationCount = windowModel.notificationPendingDeletionCount
        windowModel.confirmNotificationClear()

        // Assert
        #expect(confirmationCount == 1)
        #expect(confirmationEffects == 0)
        #expect(session.resources.notifications.isEmpty)
        #expect(session.resources.notificationOperations.unreadCount() == 0)
        #expect(!windowModel.isNotificationListPresented)
        #expect(windowModel.notificationPendingDeletionCount == nil)
        #expect(session.feedback.latest == nil)
    }

    @Test func openingNotificationFocusesItsBoardAcrossDesksAndMarksItRead() {
        // Arrange
        let target = board("Terminal")
        let first = desk("First")
        let second = desk("Second", boards: [target], focusedBoardID: target.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [first, second], focusedDeskID: first.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        session.notifications.recordNotification(title: "Build", body: "Finished", boardID: target.id)
        let notification = session.resources.notifications[0]
        windowModel.toggleNotificationList()

        // Act
        windowModel.notificationList.open(notification)

        // Assert
        #expect(session.navigation.presentedDeskID == second.id)
        #expect(session.navigation.focusedBoard?.id == target.id)
        #expect(session.resources.notifications[0].isRead)
        #expect(session.resources.notificationOperations.unreadCount() == 0)
        #expect(!windowModel.isNotificationListPresented)
    }

    @Test func openingNotificationFeedbackTargetFocusesItsBoardAndMarksItRead() {
        // Arrange
        let target = board("Terminal")
        let first = desk("First")
        let second = desk("Second", boards: [target], focusedBoardID: target.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [first, second], focusedDeskID: first.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        session.notifications.recordNotification(title: "Build", body: "Finished", boardID: target.id)
        windowModel.toggleNotificationList()

        // Act
        session.notifications.openFeedbackTarget(session.feedback.latest?.target)

        // Assert
        #expect(session.navigation.presentedDeskID == second.id)
        #expect(session.navigation.focusedBoard?.id == target.id)
        #expect(session.resources.notifications[0].isRead)
        #expect(!windowModel.isNotificationListPresented)
    }

    @Test(arguments: [false, true])
    func openingNotificationOnlyUpdatesTheInvokingWindow(sourceExists: Bool) throws {
        // Arrange
        let board = board("Source")
        let firstDesk = desk("First")
        let secondDesk = desk("Second", boards: sourceExists ? [board] : [], focusedBoardID: nil)
        let storage = DenProfileResources(
            state: DenState(desks: [firstDesk, secondDesk], focusedDeskID: firstDesk.id))
        let defaults = makeTestDefaults()
        let navigation = makeTestSheetNavigationManager(defaults: defaults, scriptSource: "")
        let preferences = AppPreferences(defaults: defaults)
        func session() -> ProfileWindowSession {
            ProfileWindowSession(
                resources: storage,
                configuration: makeTestBoardRuntimeConfiguration(
                    websiteDataStore: .nonPersistent(), sheetNavigation: navigation, preferences: preferences),
                presentedDeskID: firstDesk.id, canPresentDesk: { _ in true }, onDeskPresentationRequest: { _ in true },
                onWillResetDen: {})
        }
        let first = DenWindowComposition(session: session())
        let second = DenWindowComposition(session: session())
        first.connect()
        second.connect()
        defer {
            first.disconnect()
            second.disconnect()
        }
        first.session.notifications.recordNotification(title: "Build", body: "Finished", boardID: board.id)
        let notification = try #require(storage.notifications.first)
        first.model.isDenMode = true
        second.model.isDenMode = true
        first.model.toggleNotificationList()
        second.model.toggleNotificationList()

        // Act
        first.model.notificationList.open(notification)

        // Assert
        #expect(storage.notifications.first?.isRead == true)
        #expect(second.session.navigation.presentedDeskID == firstDesk.id)
        #expect(second.model.isDenMode)
        #expect(second.model.isNotificationListPresented)
        #expect(second.model.displayedFeedback == nil)
        if sourceExists {
            #expect(first.session.navigation.presentedDeskID == secondDesk.id)
            #expect(first.session.navigation.focusedBoard?.id == board.id)
            #expect(!first.model.isNotificationListPresented)
            #expect(!first.model.isDenMode)
        } else {
            #expect(first.session.navigation.presentedDeskID == firstDesk.id)
            #expect(first.model.displayedFeedback?.body == "Notification source Board no longer exists.")
            #expect(first.model.displayedFeedback?.severity == .warning)
            #expect(first.model.isNotificationListPresented)
        }
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: BoardID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String) -> BoardState {
        BoardState(label: label, width: 520, workingDirectory: "/tmp")
    }
}
