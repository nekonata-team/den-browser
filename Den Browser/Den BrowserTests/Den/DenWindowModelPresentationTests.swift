import AppKit
import DenApplication
import DenDomain
import DenPresentation
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenWindowModelPresentationTests {

    @Test func resetDenClearsRuntimePresentationAndPersistsFreshState() {
        // Arrange
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        var savedState: DenState?
        let controller = DenController(
            state: DenState(desks: [populated, empty], focusedDeskID: populated.id),
            onSave: { savedState = $0 })
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let runtime = controller.webRuntime(for: board)
        controller.deleteFocusedDesk()
        windowModel.maximizedBoardID = board.id
        windowModel.isBoardRailPresented = true
        #expect(controller.beginBoardDrag(board.id))
        controller.storage.recentlyRemovedBoards = [
            RecentlyRemovedBoard(board: board, sourceDeskID: populated.id, sourceBoardIndex: 0)
        ]
        controller.storage.recentlyDiscardedDrawerItems = [
            DrawerItem(url: URL(string: "https://discarded.example/")!)
        ]
        windowModel.setTemporaryContext(.zmxSessions)
        windowModel.openBoard.input = "unfinished search"
        windowModel.openBoard.afterBoardID = board.id
        controller.previousFocusedDeskID = empty.id
        controller.anchorJumpOriginBoardIDByDesk[populated.id] = board.id

        // Act
        controller.resetDen()

        // Assert
        #expect(controller.state.desks.count == 1)
        #expect(windowModel.pendingConfirmation == nil)
        #expect(windowModel.maximizedBoardID == nil)
        #expect(!windowModel.isFocusModePresented)
        #expect(!windowModel.isBoardRailPresented)
        #expect(!controller.isBoardDragging)
        #expect(windowModel.temporaryContext == nil)
        #expect(savedState == controller.state)
        #expect(controller.latestFeedback?.message == "Reset Den completed.")
        #expect(controller.latestFeedback?.severity == .success)
        #expect(controller.webRuntimes.isEmpty)
        #expect(controller.recentlyRemovedBoards.isEmpty)
        #expect(controller.recentlyDiscardedDrawerItems.isEmpty)
        #expect(controller.notifications.isEmpty)
        #expect(windowModel.openBoard.input.isEmpty)
        #expect(windowModel.openBoard.afterBoardID == nil)
        #expect(controller.previousFocusedDeskID == nil)
        #expect(controller.anchorJumpOriginBoardIDByDesk.isEmpty)
        #expect(runtime.webView.navigationDelegate == nil)
        #expect(runtime.webView.uiDelegate == nil)
    }

    @Test func boardRailStaysOpenWhenFocusChangesAndPanelOpens() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let focusedDesk = desk("Desk", boards: [first, second], focusedBoardID: first.id)
        let controller = DenController(
            state: DenState(desks: [focusedDesk], focusedDeskID: focusedDesk.id)
        )
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        // Act
        windowModel.toggleBoardRail()
        controller.focusBoard(second.id)
        windowModel.showOpenBoardPanel()

        // Assert
        #expect(controller.focusedBoard?.id == second.id)
        #expect(windowModel.isOpenBoardPanelPresented)
        #expect(windowModel.isBoardRailPresented)
    }

    @Test func restoreRecentlyRemovedBoardReportsFeedbackWhenNoneExists() {
        let controller = DenController(state: .sample)
        controller.restoreRecentlyRemovedBoard()
        #expect(controller.latestFeedback?.message == "No removed board to restore.")
        #expect(controller.latestFeedback?.severity == .warning)
    }

    @Test func invalidDeskNumberReportsFeedback() {
        let controller = DenController(state: .sample)
        controller.focusDesk(number: 5)
        #expect(controller.latestFeedback?.message == "Desk 5 does not exist.")
        #expect(controller.latestFeedback?.severity == .warning)
    }

    @Test func reportFeedbackSetsLatestFeedbackWithSeverity() {
        let controller = DenController(state: .sample)
        #expect(controller.latestFeedback == nil)

        controller.reportFeedback("Test Toast", severity: .warning)

        #expect(controller.latestFeedback?.message == "Test Toast")
        #expect(controller.latestFeedback?.severity == .warning)
    }

    @Test func reportFeedbackPreservesTitleAndBody() {
        let controller = DenController(state: .sample)

        controller.reportFeedback(title: "Build", body: "Finished")

        #expect(controller.latestFeedback?.title == "Build")
        #expect(controller.latestFeedback?.body == "Finished")
        #expect(controller.latestFeedback?.message == "Build: Finished")
    }

    @Test func openBoardPanelRetainsDraftAndClearsOneShotStateAcrossTransitions() throws {
        let board = board("Insert After")
        let focusedDesk = desk("Desk", boards: [board], focusedBoardID: board.id)
        let controller = DenController(
            state: DenState(
                desks: [focusedDesk],
                focusedDeskID: focusedDesk.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let url = try #require(URL(string: "https://example.com/current"))

        windowModel.showOpenBoardPanel()
        windowModel.openBoard.input = "unfinished search"
        windowModel.hideOpenBoardPanel()

        #expect(windowModel.openBoard.input == "unfinished search")
        #expect(windowModel.openBoard.afterBoardID == nil)

        windowModel.showOpenBoardPanel(initialURL: url, afterBoardID: board.id)
        windowModel.openBoard.message = "Try another input."

        #expect(windowModel.openBoard.input == url.absoluteString)
        #expect(windowModel.openBoard.afterBoardID == board.id)

        windowModel.showKeyboardShortcuts()

        #expect(windowModel.openBoard.input == url.absoluteString)
        #expect(windowModel.openBoard.initialURL == nil)
        #expect(windowModel.openBoard.afterBoardID == nil)
        #expect(windowModel.openBoard.message == nil)

        windowModel.hideKeyboardShortcuts()
        windowModel.showOpenBoardPanel()

        #expect(windowModel.openBoard.input == url.absoluteString)
        #expect(windowModel.openBoard.afterBoardID == nil)
    }

    @Test func openBoardPanelKeepsDraftAndShowsConfigurationFailure() {
        // Arrange
        let source = desk("Desk")
        withTestWindowModel(desks: [source]) { windowModel in
            windowModel.showOpenBoardPanel()
            windowModel.openBoard.input = ":zmx project"

            // Act
            windowModel.openBoard.submit(preferredWidth: windowModel.defaultBoardWidth)

            // Assert
            #expect(windowModel.isOpenBoardPanelPresented)
            #expect(windowModel.openBoard.input == ":zmx project")
            #expect(windowModel.openBoard.message == "Set an absolute zmx executable path in Settings > Terminal.")
            #expect(windowModel.controller.focusedDesk?.boards.isEmpty == true)
        }
    }

    @Test func openBoardPanelOpensRecentItemAtRequestedPositionAndWidth() throws {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let source = desk("Desk", boards: [first, second], focusedBoardID: second.id)
        try withTestWindowModel(desks: [source]) { windowModel in
            let item = RecentItem.url(URL(string: "https://example.com/recent")!)
            windowModel.showOpenBoardPanel(afterBoardID: first.id)

            // Act
            windowModel.openBoard.submit(item.displayText, preferredWidth: 640)

            // Assert
            let opened = try #require(windowModel.controller.focusedBoard)
            #expect(opened.currentSheetURL == URL(string: item.displayText))
            #expect(opened.width == 640)
            #expect(windowModel.controller.focusedDesk?.boards.map(\.id) == [first.id, opened.id, second.id])
            #expect(windowModel.controller.recentItems.first == item)
            #expect(!windowModel.isOpenBoardPanelPresented)
            #expect(windowModel.openBoard.message == nil)
        }
    }

    @Test func recordingNotificationAddsUnreadHistoryAndTargetedFeedback() {
        let target = board("Terminal")
        let desk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let controller = DenController(state: DenState(desks: [desk], focusedDeskID: desk.id))

        controller.recordNotification(title: "Build", body: "Finished", boardID: target.id)

        #expect(controller.notifications.count == 1)
        #expect(controller.notifications[0].title == "Build")
        #expect(controller.notifications[0].body == "Finished")
        #expect(controller.notifications[0].boardID == target.id)
        #expect(controller.unreadNotificationCount == 1)
        #expect(controller.latestFeedback?.target == .notification(controller.notifications[0].id))
    }

    @Test func unreadNotificationCountIsScopedToBoard() {
        // Arrange
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let desk = desk("Desk", boards: [firstBoard, secondBoard], focusedBoardID: firstBoard.id)
        let controller = DenController(state: DenState(desks: [desk], focusedDeskID: desk.id))

        controller.recordNotification(title: "First build", body: "Finished", boardID: firstBoard.id)
        let readNotificationID = controller.notifications[0].id
        controller.recordNotification(title: "Second build", body: "Finished", boardID: firstBoard.id)
        controller.recordNotification(title: "Other build", body: "Finished", boardID: secondBoard.id)
        controller.markNotificationRead(readNotificationID)

        // Act
        let firstCount = controller.unreadNotificationCount(for: firstBoard.id)
        let secondCount = controller.unreadNotificationCount(for: secondBoard.id)

        // Assert
        #expect(firstCount == 1)
        #expect(secondCount == 1)
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
        let target = board("Terminal")
        let desk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let controller = DenController(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        controller.recordNotification(title: "Build", body: "Finished", boardID: target.id)
        windowModel.toggleNotificationList()
        controller.requestNotificationClearConfirmation()

        #expect(windowModel.notificationPendingDeletionCount == 1)
        windowModel.confirmNotificationClear()

        #expect(controller.notifications.isEmpty)
        #expect(controller.unreadNotificationCount == 0)
        #expect(!windowModel.isNotificationListPresented)
        #expect(windowModel.notificationPendingDeletionCount == nil)
        #expect(controller.latestFeedback == nil)
    }

    @Test func openingNotificationFocusesItsBoardAcrossDesksAndMarksItRead() {
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
        controller.openNotification(notification)

        #expect(controller.presentedDeskID == second.id)
        #expect(controller.focusedBoard?.id == target.id)
        #expect(controller.notifications[0].isRead)
        #expect(controller.unreadNotificationCount == 0)
        #expect(!windowModel.isNotificationListPresented)
    }

    @Test func openingNotificationFeedbackTargetFocusesItsBoardAndMarksItRead() {
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
        controller.openFeedbackTarget(controller.latestFeedback?.target)

        #expect(controller.presentedDeskID == second.id)
        #expect(controller.focusedBoard?.id == target.id)
        #expect(controller.notifications[0].isRead)
        #expect(!windowModel.isNotificationListPresented)
    }

    @Test func openingBoardFeedbackTargetFocusesItsBoard() {
        let target = board("Target")
        let first = desk("First")
        let second = desk("Second", boards: [target])
        let controller = DenController(
            state: DenState(desks: [first, second], focusedDeskID: first.id)
        )
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.setTemporaryContext(.drawer)
        controller.reportFeedback(title: "Build", body: "Finished", target: .board(target.id))
        controller.openFeedbackTarget(controller.latestFeedback?.target)

        #expect(controller.presentedDeskID == second.id)
        #expect(controller.focusedBoard?.id == target.id)
        #expect(windowModel.temporaryContext == nil)
    }

    @Test func openingDrawerFeedbackTargetOpensAndExpandsItem() throws {
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let drawerDesk = desk("Desk")
        let controller = DenController(
            state: DenState(
                desks: [drawerDesk],
                focusedDeskID: drawerDesk.id,
                drawerItems: [item])
        )
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        controller.reportFeedback(
            title: nil,
            body: "Open item",
            target: DenFeedback.Target.drawerItem(item.id))
        controller.openFeedbackTarget(controller.latestFeedback?.target)

        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.selectedItemID == item.id)
        #expect(windowModel.drawer.expandedItemID == item.id)
    }

    @Test func resetDenRequiresConfirmationBeforeChangingState() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        var savedState: DenState?
        let controller = DenController(
            state: DenState(desks: [populated], focusedDeskID: populated.id),
            onSave: { savedState = $0 })
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let originalState = controller.state

        windowModel.requestResetDenConfirmation()

        #expect(windowModel.isResetDenPending)
        #expect(controller.state == originalState)
        #expect(savedState == nil)

        windowModel.cancelResetDen()

        #expect(!windowModel.isResetDenPending)
        #expect(controller.state == originalState)
        #expect(savedState == nil)
    }

    @Test func latestConfirmationReplacesEarlierRequestAndCanBeCancelled() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        let controller = DenController(
            state: DenState(desks: [populated, empty], focusedDeskID: populated.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        controller.deleteFocusedDesk()
        if case let .deleteDesk(pending)? = windowModel.pendingConfirmation {
            #expect(pending.id == populated.id)
        } else {
            Issue.record("Expected a desk deletion confirmation")
        }

        windowModel.requestResetDenConfirmation()
        #expect(windowModel.isResetDenPending)

        windowModel.cancelResetDen()
        #expect(!windowModel.hasPendingConfirmation)
    }

    @Test func confirmingResetDenUsesExistingResetBehavior() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        var savedState: DenState?
        let controller = DenController(
            state: DenState(desks: [populated], focusedDeskID: populated.id),
            onSave: { savedState = $0 })
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.requestResetDenConfirmation()
        windowModel.confirmResetDen()

        #expect(!windowModel.isResetDenPending)
        #expect(controller.state.desks.count == 1)
        #expect(controller.state.desks.first?.label == "Main")
        #expect(controller.state.desks.first?.boards.isEmpty == true)
        #expect(controller.state.focusedDeskID == controller.state.desks.first?.id)
        #expect(savedState == controller.state)
    }

    @Test func escapePassesThroughToSheetInput() throws {
        try withTestWindowModel(desks: [desk("Desk")]) { windowModel in
            let controller = windowModel.controller
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "\u{1B}",
                    charactersIgnoringModifiers: "\u{1B}",
                    isARepeat: false,
                    keyCode: 53
                ))

            #expect(!KeyboardController.handle(event, controller: controller, windowModel: windowModel))
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func escapeExitsDenMode() throws {
        try withTestWindowModel(desks: [desk("Desk")]) { windowModel in
            let controller = windowModel.controller
            windowModel.isDenMode = true
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "\u{1B}",
                    charactersIgnoringModifiers: "\u{1B}",
                    isARepeat: false,
                    keyCode: 53
                ))

            #expect(KeyboardController.handle(event, controller: controller, windowModel: windowModel))
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func directDeskSelectionExitsButRelativeNavigationKeepsDenMode() {
        let first = desk("First")
        let second = desk("Second")
        let third = desk("Third")
        withTestWindowModel(desks: [first, second, third]) { windowModel in
            let controller = windowModel.controller
            // 1. focusDesk(number:) exits DenMode on actual switch
            windowModel.isDenMode = true
            controller.focusDesk(number: 2)
            #expect(!windowModel.isDenMode)
            #expect(controller.focusedDesk?.id == second.id)

            // focusDesk(number:) exits even when the target is already focused
            windowModel.isDenMode = true
            controller.focusDesk(number: 2)
            #expect(!windowModel.isDenMode)

            // 2. focusDesk(_:) is direct selection
            controller.focusDesk(third.id)
            #expect(!windowModel.isDenMode)
            #expect(controller.focusedDesk?.id == third.id)

            // focusDesk(_:) exits even when the target is already focused
            windowModel.isDenMode = true
            controller.focusDesk(third.id)
            #expect(!windowModel.isDenMode)

            // 3. Relative Desk Navigation keeps Den Mode active
            windowModel.isDenMode = true
            controller.focusPreviousDesk()
            #expect(windowModel.isDenMode)
            #expect(controller.focusedDesk?.id == second.id)

            windowModel.isDenMode = true
            controller.focusNextDesk()
            #expect(windowModel.isDenMode)
            #expect(controller.focusedDesk?.id == third.id)

            // 4. Overview confirmation exits even on the same Desk
            windowModel.showOverview()
            windowModel.isDenMode = true
            windowModel.overview.selectDesk(first.id)
            windowModel.overview.enterSelection()
            #expect(!windowModel.isDenMode)
            #expect(controller.focusedDesk?.id == first.id)

            // Entering the selected Desk exits even when the target is already focused.
            windowModel.showOverview()
            windowModel.isDenMode = true
            windowModel.overview.selectDesk(first.id)
            windowModel.overview.enterSelection()
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func boardRenamingAndCustomLabelStickiness() {
        let googleBoard = board("Google", url: "https://google.com")
        withTestWindowModel(desks: [desk("Main", boards: [googleBoard])]) { windowModel in
            let controller = windowModel.controller
            // 1. Initially, customLabel is nil, displayName returns page title
            let boardID = googleBoard.id
            guard
                let deskIndex = controller.focusedDeskIndex,
                let boardIndex = controller.focusedBoardIndex(in: deskIndex)
            else {
                Issue.record("Failed to find focused board indices")
                return
            }
            #expect(controller.state.desks[deskIndex].boards[boardIndex].customLabel == nil)
            #expect(controller.state.desks[deskIndex].boards[boardIndex].displayName == "Google")

            // 2. Rename the board to a custom name
            controller.renameFocusedBoard(to: "Search Tasks")
            #expect(controller.state.desks[deskIndex].boards[boardIndex].customLabel == "Search Tasks")
            #expect(controller.state.desks[deskIndex].boards[boardIndex].displayName == "Search Tasks")
            #expect(!windowModel.isDenMode)

            // 3. Navigation doesn't overwrite customLabel, but updates label
            controller.updateBoard(
                boardID: boardID,
                url: URL(string: "https://google.com/search"),
                title: "Google Search Result"
            )
            // Original label is updated in the background
            #expect(controller.state.desks[deskIndex].boards[boardIndex].label == "Google Search Result")
            // customLabel is untouched
            #expect(controller.state.desks[deskIndex].boards[boardIndex].customLabel == "Search Tasks")
            // displayName still shows custom label
            #expect(controller.state.desks[deskIndex].boards[boardIndex].displayName == "Search Tasks")

            // 4. Duplicate the board (duplicate should copy customLabel)
            controller.toggleBoardSheetNavigationPause(boardID)
            windowModel.isDenMode = true
            controller.duplicateFocusedBoard()
            let boards = controller.focusedDesk?.boards ?? []
            #expect(boards.count == 2)
            #expect(boards[1].customLabel == "Search Tasks")
            #expect(boards[1].displayName == "Search Tasks")
            #expect(boards[0].sheetNavigationPaused)
            #expect(boards[1].sheetNavigationPaused)

            // 5. Focus original board and clear the label
            controller.focusBoard(boardID)
            controller.renameFocusedBoard(to: "")
            controller.toggleBoardSheetNavigationPause(boardID)
            #expect(controller.state.desks[deskIndex].boards[boardIndex].customLabel == nil)
            #expect(controller.state.desks[deskIndex].boards[boardIndex].displayName == "Google Search Result")
            #expect(!controller.state.desks[deskIndex].boards[boardIndex].sheetNavigationPaused)
        }
    }

    @Test func controlCommaTogglesDenMode() throws {
        try withTestWindowModel(desks: [desk("Desk")]) { windowModel in
            let controller = windowModel.controller
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .control,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: ",",
                    charactersIgnoringModifiers: ",",
                    isARepeat: false,
                    keyCode: 43
                ))

            #expect(KeyboardController.handle(event, controller: controller, windowModel: windowModel))
            #expect(windowModel.isDenMode)
            #expect(KeyboardController.handle(event, controller: controller, windowModel: windowModel))
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func controlPeriodPassesThroughToSheetInput() throws {
        try withTestWindowModel(desks: [desk("Desk")]) { windowModel in
            let controller = windowModel.controller
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .control,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: ".",
                    charactersIgnoringModifiers: ".",
                    isARepeat: false,
                    keyCode: 47
                ))

            #expect(!KeyboardController.handle(event, controller: controller, windowModel: windowModel))
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func commandOptionArrowsNavigateBoardsWithoutEnteringDenMode() throws {
        let boards = [board("First"), board("Second")]
        try withTestWindowModel(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { windowModel in
            let controller = windowModel.controller
            let right = try arrowEvent(.rightArrow, modifiers: [.command, .option])
            let left = try arrowEvent(.leftArrow, modifiers: [.command, .option])

            #expect(KeyboardController.handle(right, controller: controller, windowModel: windowModel))
            #expect(controller.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(!windowModel.isDenMode)

            #expect(KeyboardController.handle(left, controller: controller, windowModel: windowModel))
            #expect(controller.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func shiftCommandOptionArrowsMoveFocusedBoardWithoutEnteringDenMode() throws {
        let boards = [board("First"), board("Second")]
        try withTestWindowModel(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { windowModel in
            let controller = windowModel.controller
            let right = try arrowEvent(.rightArrow, modifiers: [.command, .option, .shift])
            let left = try arrowEvent(.leftArrow, modifiers: [.command, .option, .shift])

            #expect(KeyboardController.handle(right, controller: controller, windowModel: windowModel))
            #expect(controller.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id])
            #expect(!windowModel.isDenMode)

            #expect(KeyboardController.handle(left, controller: controller, windowModel: windowModel))
            #expect(controller.focusedDesk?.boards.map(\.id) == boards.map(\.id))
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func commandQPassesThroughFromDenMode() throws {
        try withTestWindowModel(desks: [desk("Desk")]) { windowModel in
            let controller = windowModel.controller
            windowModel.isDenMode = true
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .command,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "q",
                    charactersIgnoringModifiers: "q",
                    isARepeat: false,
                    keyCode: 12
                ))

            #expect(!KeyboardController.handle(event, controller: controller, windowModel: windowModel))
            #expect(windowModel.isDenMode)
        }
    }

    @Test func denModeMaximizesAndCentersFocusedBoardWithoutChangingDenState() throws {
        let current = board("Current", width: 520)
        try withTestWindowModel(desks: [desk("Desk", boards: [current])]) { windowModel in
            let controller = windowModel.controller
            windowModel.isDenMode = true
            let stateBeforeCommands = controller.state
            let maximize = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "f",
                    charactersIgnoringModifiers: "f",
                    isARepeat: false,
                    keyCode: 3
                ))
            let center = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "c",
                    charactersIgnoringModifiers: "c",
                    isARepeat: false,
                    keyCode: 8
                ))

            #expect(KeyboardController.handle(maximize, controller: controller, windowModel: windowModel))
            #expect(windowModel.maximizedBoardID == current.id)
            let requestAfterMaximize = windowModel.centerFocusedBoardRequest
            #expect(KeyboardController.handle(center, controller: controller, windowModel: windowModel))
            #expect(windowModel.centerFocusedBoardRequest == requestAfterMaximize + 1)
            #expect(KeyboardController.handle(maximize, controller: controller, windowModel: windowModel))
            #expect(windowModel.maximizedBoardID == nil)
            #expect(controller.state == stateBeforeCommands)
        }
    }

    @Test func focusModeIsRuntimeOnlyAndIgnoresKeyRepeat() throws {
        let first = board("First")
        let second = board("Second")
        let deskState = desk("Desk", boards: [first, second], focusedBoardID: first.id)
        var savedState: DenState?
        let controller = DenController(
            state: DenState(desks: [deskState], focusedDeskID: deskState.id),
            onSave: { savedState = $0 })
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let stateBeforeToggle = controller.state
        windowModel.isDenMode = true

        let toggle = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "F",
                charactersIgnoringModifiers: "f",
                isARepeat: false,
                keyCode: 3))
        let repeatedToggle = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "F",
                charactersIgnoringModifiers: "f",
                isARepeat: true,
                keyCode: 3))

        #expect(KeyboardController.handle(toggle, controller: controller, windowModel: windowModel))
        #expect(windowModel.isFocusModePresented)
        #expect(controller.state == stateBeforeToggle)
        #expect(savedState == nil)
        #expect(KeyboardController.handle(repeatedToggle, controller: controller, windowModel: windowModel))
        #expect(windowModel.isFocusModePresented)

        windowModel.exitDenMode()

        #expect(windowModel.isFocusModePresented)
        #expect(controller.state == stateBeforeToggle)
        #expect(savedState == nil)
    }

    @Test func denModeBoardWidthPanelAdjustsAllBoardsAndAcceptsFitSelectionKeys() throws {
        let boards = [board("First"), board("Second")]
        try withTestWindowModel(desks: [desk("Desk", boards: boards)]) { windowModel in
            let controller = windowModel.controller
            windowModel.isDenMode = true
            windowModel.updateBoardLayout(availableWidth: 1_180, spacing: 10)
            let open = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "w",
                    charactersIgnoringModifiers: "w",
                    isARepeat: false,
                    keyCode: 13
                ))
            let ignoredMovement = try arrowEvent(.rightArrow, modifiers: [])
            let narrow = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "-",
                    charactersIgnoringModifiers: "-",
                    isARepeat: false,
                    keyCode: 27
                ))
            let widen = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "=",
                    charactersIgnoringModifiers: "=",
                    isARepeat: false,
                    keyCode: 24
                ))
            let select = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "3",
                    charactersIgnoringModifiers: "3",
                    isARepeat: false,
                    keyCode: 20
                ))

            #expect(KeyboardController.handle(open, controller: controller, windowModel: windowModel))
            #expect(windowModel.isBoardWidthPanelPresented)
            #expect(KeyboardController.handle(ignoredMovement, controller: controller, windowModel: windowModel))
            #expect(controller.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(KeyboardController.handle(narrow, controller: controller, windowModel: windowModel))
            #expect(controller.focusedDesk?.boards.map(\.width) == [440, 440])
            #expect(windowModel.isBoardWidthPanelPresented)
            #expect(KeyboardController.handle(widen, controller: controller, windowModel: windowModel))
            #expect(controller.focusedDesk?.boards.map(\.width) == [520, 520])
            #expect(windowModel.isBoardWidthPanelPresented)
            #expect(KeyboardController.handle(select, controller: controller, windowModel: windowModel))
            #expect(!windowModel.isBoardWidthPanelPresented)
            #expect(windowModel.isDenMode)
            #expect(
                controller.focusedDesk?.boards.allSatisfy {
                    abs($0.width - 386.666_666_666_666_7) < 0.001
                } == true)
        }
    }

    @Test func showSaveEssentialPanelForBoardPopulatesDraftAndSetsContext() {
        let board = BoardState(
            label: "Example Docs",
            width: 520,
            currentSheetURL: URL(string: "https://docs.example.com/api")
        )
        let desk = DeskState(label: "Work", boards: [board], focusedBoardID: board.id)
        let controller = DenController(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.showSaveEssentialPanel(for: board)

        #expect(windowModel.isSaveEssentialPanelPresented)
        #expect(
            windowModel.saveEssentialDraft
                == SaveEssentialDraft(
                    name: "Example Docs",
                    key: "",
                    input: "https://docs.example.com/api"
                ))

        windowModel.hideSaveEssentialPanel()
        #expect(!windowModel.isSaveEssentialPanelPresented)
        #expect(windowModel.saveEssentialDraft == nil)
    }

    @Test func showSaveEssentialPanelForTerminalBoardPopulatesDraft() {
        let terminalBoard = BoardState(
            label: "Project Shell",
            width: 520,
            workingDirectory: "/Users/test/projects/demo"
        )
        let desk = DeskState(label: "Terminal", boards: [terminalBoard], focusedBoardID: terminalBoard.id)
        let controller = DenController(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.showSaveEssentialPanel(for: terminalBoard)

        #expect(windowModel.isSaveEssentialPanelPresented)
        #expect(windowModel.saveEssentialDraft?.name == "Project Shell")
        #expect(windowModel.saveEssentialDraft?.input == ":terminal /Users/test/projects/demo")
    }

    @Test func showSaveEssentialPanelForRecentItemPopulatesDraft() {
        let controller = DenController(state: .sample)
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let recent = RecentItem.url(URL(string: "https://github.com/apple/swift")!)

        windowModel.showSaveEssentialPanel(for: recent)

        #expect(windowModel.isSaveEssentialPanelPresented)
        #expect(windowModel.saveEssentialDraft?.name == "github.com")
        #expect(windowModel.saveEssentialDraft?.input == "https://github.com/apple/swift")
    }

    @Test func saveEssentialValidatesInputAndUpdatesPreferences() {
        withTestController { controller in
            withTestWindowModel(controller: controller) { windowModel in
                windowModel.showSaveEssentialPanel(name: "Test", key: "", input: "https://test.com")
                #expect(windowModel.isSaveEssentialPanelPresented)

                // Invalid: empty key
                #expect(!windowModel.saveEssential(name: "Test", key: "", input: "https://test.com"))
                #expect(windowModel.isSaveEssentialPanelPresented)

                // Invalid: multi-char key
                #expect(!windowModel.saveEssential(name: "Test", key: "ab", input: "https://test.com"))

                // Valid save
                #expect(windowModel.saveEssential(name: "Test", key: "t", input: "https://test.com"))
                #expect(!windowModel.isSaveEssentialPanelPresented)
                #expect(controller.essentials.contains { $0.key == "t" && $0.name == "Test" })
                #expect(controller.latestFeedback?.message == "Saved Essential 'Test'.")
                #expect(controller.latestFeedback?.severity == .success)

                // Duplicate key conflict rejected
                windowModel.showSaveEssentialPanel(name: "Another", key: "t", input: "https://another.com")
                #expect(!windowModel.saveEssential(name: "Another", key: "t", input: "https://another.com"))
                #expect(windowModel.isSaveEssentialPanelPresented)
            }
        }
    }

    @Test func saveFocusedBoardAsEssentialShowsToastWhenNoBoardFocused() {
        withTestWindowModel(desks: [desk("Empty")]) { windowModel in
            let controller = windowModel.controller
            windowModel.saveFocusedBoardAsEssential()
            #expect(!windowModel.isSaveEssentialPanelPresented)
            #expect(controller.latestFeedback?.message == "No focused board.")
            #expect(controller.latestFeedback?.severity == .warning)
        }
    }

    private func arrowEvent(
        _ specialKey: NSEvent.SpecialKey,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        let (characters, keyCode): (String, UInt16) =
            switch specialKey {
            case .leftArrow: ("\u{F702}", 123)
            case .rightArrow: ("\u{F703}", 124)
            default: ("", 0)
            }
        return try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: BoardID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
