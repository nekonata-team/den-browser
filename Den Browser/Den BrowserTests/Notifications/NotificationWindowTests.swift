import DenDomain
import DenPresentationModels
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
        let controller = DenController(state: DenState(desks: [desk], focusedDeskID: desk.id))
        var effects: [String] = []
        controller.onWindowEffect = { effect in
            switch effect {
            case .notificationAdded(let id):
                #expect(controller.notifications.first?.id == id)
                effects.append("notification")
            case .feedback:
                effects.append("feedback")
            default: break
            }
        }
        defer { controller.onWindowEffect = nil }

        // Act
        controller.recordNotification(title: "Build", body: "Finished", boardID: target.id)

        // Assert
        #expect(controller.notifications.count == 1)
        #expect(controller.notifications[0].title == "Build")
        #expect(controller.notifications[0].body == "Finished")
        #expect(controller.notifications[0].boardID == target.id)
        #expect(controller.unreadNotificationCount == 1)
        #expect(controller.latestFeedback?.target == .notification(controller.notifications[0].id))
        #expect(effects == ["notification", "feedback"])
    }

    @Test func focusingBoardMarksItsUnreadNotificationsRead() {
        // Arrange
        let currentBoard = board("Current")
        let targetBoard = board("Target")
        let desk = desk("Desk", boards: [currentBoard, targetBoard], focusedBoardID: currentBoard.id)
        let controller = DenController(state: DenState(desks: [desk], focusedDeskID: desk.id))
        controller.recordNotification(title: "First", body: "Finished", boardID: targetBoard.id)
        controller.recordNotification(title: "Second", body: "Finished", boardID: targetBoard.id)
        controller.recordNotification(title: "Other", body: "Finished", boardID: currentBoard.id)

        // Act
        controller.focusBoard(targetBoard.id)

        // Assert
        #expect(controller.focusedBoard?.id == targetBoard.id)
        #expect(controller.unreadNotificationCount(for: targetBoard.id) == 0)
        #expect(controller.unreadNotificationCount(for: currentBoard.id) == 1)
        #expect(controller.unreadNotificationCount == 1)
    }

    @Test func focusingDeskMarksItsFocusedBoardNotificationsRead() {
        // Arrange
        let currentBoard = board("Current")
        let targetBoard = board("Target")
        let currentDesk = desk("Current", boards: [currentBoard], focusedBoardID: currentBoard.id)
        let targetDesk = desk("Target", boards: [targetBoard], focusedBoardID: targetBoard.id)
        let controller = DenController(
            state: DenState(desks: [currentDesk, targetDesk], focusedDeskID: currentDesk.id))
        controller.recordNotification(title: "Build", body: "Finished", boardID: targetBoard.id)

        // Act
        controller.focusDesk(targetDesk.id)

        // Assert
        #expect(controller.unreadNotificationCount(for: targetBoard.id) == 0)
        #expect(controller.unreadNotificationCount == 0)
    }

    @Test func clearingNotificationsRemovesSessionHistoryAfterConfirmation() {
        // Arrange
        let target = board("Terminal")
        let desk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let controller = DenController(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        controller.recordNotification(title: "Build", body: "Finished", boardID: target.id)
        windowModel.toggleNotificationList()
        var confirmationEffects = 0
        let deliverEffect = controller.onWindowEffect
        controller.onWindowEffect = { effect in
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
        #expect(controller.notifications.isEmpty)
        #expect(controller.unreadNotificationCount == 0)
        #expect(!windowModel.isNotificationListPresented)
        #expect(windowModel.notificationPendingDeletionCount == nil)
        #expect(controller.latestFeedback == nil)
    }

    @Test func openingNotificationFocusesItsBoardAcrossDesksAndMarksItRead() {
        // Arrange
        let target = board("Terminal")
        let first = desk("First")
        let second = desk("Second", boards: [target], focusedBoardID: target.id)
        let controller = DenController(state: DenState(desks: [first, second], focusedDeskID: first.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        controller.recordNotification(title: "Build", body: "Finished", boardID: target.id)
        let notification = controller.notifications[0]
        windowModel.toggleNotificationList()

        // Act
        windowModel.notificationList.open(notification)

        // Assert
        #expect(controller.presentedDeskID == second.id)
        #expect(controller.focusedBoard?.id == target.id)
        #expect(controller.notifications[0].isRead)
        #expect(controller.unreadNotificationCount == 0)
        #expect(!windowModel.isNotificationListPresented)
    }

    @Test func openingNotificationFeedbackTargetFocusesItsBoardAndMarksItRead() {
        // Arrange
        let target = board("Terminal")
        let first = desk("First")
        let second = desk("Second", boards: [target], focusedBoardID: target.id)
        let controller = DenController(state: DenState(desks: [first, second], focusedDeskID: first.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        controller.recordNotification(title: "Build", body: "Finished", boardID: target.id)
        windowModel.toggleNotificationList()

        // Act
        controller.openFeedbackTarget(controller.latestFeedback?.target)

        // Assert
        #expect(controller.presentedDeskID == second.id)
        #expect(controller.focusedBoard?.id == target.id)
        #expect(controller.notifications[0].isRead)
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
        func controller() -> DenController {
            DenController(
                storage: storage, presentedDeskID: firstDesk.id, websiteDataStore: .nonPersistent(),
                sheetNavigation: navigation, preferences: preferences,
                canPresentDesk: { _ in true }, onDeskPresentationRequest: { _ in true }, onWillResetDen: {})
        }
        let first = DenWindowComposition(controller: controller())
        let second = DenWindowComposition(controller: controller())
        first.connect()
        second.connect()
        defer {
            first.disconnect()
            second.disconnect()
        }
        first.controller.recordNotification(title: "Build", body: "Finished", boardID: board.id)
        let notification = try #require(storage.notifications.first)
        first.model.isDenMode = true
        second.model.isDenMode = true
        first.model.toggleNotificationList()
        second.model.toggleNotificationList()

        // Act
        first.model.notificationList.open(notification)

        // Assert
        #expect(storage.notifications.first?.isRead == true)
        #expect(second.controller.presentedDeskID == firstDesk.id)
        #expect(second.model.isDenMode)
        #expect(second.model.isNotificationListPresented)
        #expect(second.model.displayedFeedback == nil)
        if sourceExists {
            #expect(first.controller.presentedDeskID == secondDesk.id)
            #expect(first.controller.focusedBoard?.id == board.id)
            #expect(!first.model.isNotificationListPresented)
            #expect(!first.model.isDenMode)
        } else {
            #expect(first.controller.presentedDeskID == firstDesk.id)
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
