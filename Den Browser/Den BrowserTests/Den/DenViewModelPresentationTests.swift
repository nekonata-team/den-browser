import AppKit
import DenDomain
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenViewModelPresentationTests {

    @Test func resetDenClearsRuntimePresentationAndPersistsFreshState() {
        // Arrange
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [populated, empty], focusedDeskID: populated.id),
            onSave: { savedState = $0 })
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let runtime = store.webRuntime(for: board)
        store.deleteFocusedDesk()
        viewModel.maximizedBoardID = board.id
        viewModel.isBoardRailPresented = true
        #expect(store.beginBoardDrag(board.id))
        store.recentlyRemovedBoards = [
            RecentlyRemovedBoard(board: board, sourceDeskID: populated.id, sourceBoardIndex: 0)
        ]
        store.recentlyDiscardedDrawerItems = [
            DrawerItem(url: URL(string: "https://discarded.example/")!)
        ]
        viewModel.setTemporaryContext(.zmxSessions)
        viewModel.openBoard.input = "unfinished search"
        viewModel.openBoard.afterBoardID = board.id
        store.previousFocusedDeskID = empty.id
        store.anchorJumpOriginBoardIDByDesk[populated.id] = board.id

        // Act
        store.resetDen()

        // Assert
        #expect(store.state.desks.count == 1)
        #expect(viewModel.pendingConfirmation == nil)
        #expect(viewModel.maximizedBoardID == nil)
        #expect(!viewModel.isFocusModePresented)
        #expect(!viewModel.isBoardRailPresented)
        #expect(!store.isBoardDragging)
        #expect(viewModel.temporaryContext == nil)
        #expect(savedState == store.state)
        #expect(store.latestFeedback?.message == "Reset Den completed.")
        #expect(store.latestFeedback?.severity == .success)
        #expect(store.webRuntimes.isEmpty)
        #expect(store.recentlyRemovedBoards.isEmpty)
        #expect(store.recentlyDiscardedDrawerItems.isEmpty)
        #expect(store.notifications.isEmpty)
        #expect(viewModel.openBoard.input.isEmpty)
        #expect(viewModel.openBoard.afterBoardID == nil)
        #expect(store.previousFocusedDeskID == nil)
        #expect(store.anchorJumpOriginBoardIDByDesk.isEmpty)
        #expect(runtime.webView.navigationDelegate == nil)
        #expect(runtime.webView.uiDelegate == nil)
    }

    @Test func boardRailStaysOpenWhenFocusChangesAndPanelOpens() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let focusedDesk = desk("Desk", boards: [first, second], focusedBoardID: first.id)
        let store = DenStore(
            state: DenState(desks: [focusedDesk], focusedDeskID: focusedDesk.id)
        )
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        // Act
        viewModel.toggleBoardRail()
        store.focusBoard(second.id)
        viewModel.showOpenBoardPanel()

        // Assert
        #expect(store.focusedBoard?.id == second.id)
        #expect(viewModel.isOpenBoardPanelPresented)
        #expect(viewModel.isBoardRailPresented)
    }

    @Test func restoreRecentlyRemovedBoardReportsFeedbackWhenNoneExists() {
        let store = DenStore(state: .sample)
        store.restoreRecentlyRemovedBoard()
        #expect(store.latestFeedback?.message == "No removed board to restore.")
        #expect(store.latestFeedback?.severity == .warning)
    }

    @Test func invalidDeskNumberReportsFeedback() {
        let store = DenStore(state: .sample)
        store.focusDesk(number: 5)
        #expect(store.latestFeedback?.message == "Desk 5 does not exist.")
        #expect(store.latestFeedback?.severity == .warning)
    }

    @Test func reportFeedbackSetsLatestFeedbackWithSeverity() {
        let store = DenStore(state: .sample)
        #expect(store.latestFeedback == nil)

        store.reportFeedback("Test Toast", severity: .warning)

        #expect(store.latestFeedback?.message == "Test Toast")
        #expect(store.latestFeedback?.severity == .warning)
    }

    @Test func reportFeedbackPreservesTitleAndBody() {
        let store = DenStore(state: .sample)

        store.reportFeedback(title: "Build", body: "Finished")

        #expect(store.latestFeedback?.title == "Build")
        #expect(store.latestFeedback?.body == "Finished")
        #expect(store.latestFeedback?.message == "Build: Finished")
    }

    @Test func openBoardPanelRetainsDraftAndClearsOneShotStateAcrossTransitions() throws {
        let board = board("Insert After")
        let focusedDesk = desk("Desk", boards: [board], focusedBoardID: board.id)
        let store = DenStore(
            state: DenState(
                desks: [focusedDesk],
                focusedDeskID: focusedDesk.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let url = try #require(URL(string: "https://example.com/current"))

        viewModel.showOpenBoardPanel()
        viewModel.openBoard.input = "unfinished search"
        viewModel.hideOpenBoardPanel()

        #expect(viewModel.openBoard.input == "unfinished search")
        #expect(viewModel.openBoard.afterBoardID == nil)

        viewModel.showOpenBoardPanel(initialURL: url, afterBoardID: board.id)
        viewModel.openBoard.message = "Try another input."

        #expect(viewModel.openBoard.input == url.absoluteString)
        #expect(viewModel.openBoard.afterBoardID == board.id)

        viewModel.showKeyboardShortcuts()

        #expect(viewModel.openBoard.input == url.absoluteString)
        #expect(viewModel.openBoard.initialURL == nil)
        #expect(viewModel.openBoard.afterBoardID == nil)
        #expect(viewModel.openBoard.message == nil)

        viewModel.hideKeyboardShortcuts()
        viewModel.showOpenBoardPanel()

        #expect(viewModel.openBoard.input == url.absoluteString)
        #expect(viewModel.openBoard.afterBoardID == nil)
    }

    @Test func recordingNotificationAddsUnreadHistoryAndTargetedFeedback() {
        let target = board("Terminal")
        let desk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))

        store.recordNotification(title: "Build", body: "Finished", boardID: target.id)

        #expect(store.notifications.count == 1)
        #expect(store.notifications[0].title == "Build")
        #expect(store.notifications[0].body == "Finished")
        #expect(store.notifications[0].boardID == target.id)
        #expect(store.unreadNotificationCount == 1)
        #expect(store.latestFeedback?.target == .notification(store.notifications[0].id))
    }

    @Test func unreadNotificationCountIsScopedToBoard() {
        // Arrange
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let desk = desk("Desk", boards: [firstBoard, secondBoard], focusedBoardID: firstBoard.id)
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))

        store.recordNotification(title: "First build", body: "Finished", boardID: firstBoard.id)
        let readNotificationID = store.notifications[0].id
        store.recordNotification(title: "Second build", body: "Finished", boardID: firstBoard.id)
        store.recordNotification(title: "Other build", body: "Finished", boardID: secondBoard.id)
        store.markNotificationRead(readNotificationID)

        // Act
        let firstCount = store.unreadNotificationCount(for: firstBoard.id)
        let secondCount = store.unreadNotificationCount(for: secondBoard.id)

        // Assert
        #expect(firstCount == 1)
        #expect(secondCount == 1)
    }

    @Test func focusingBoardMarksItsUnreadNotificationsRead() {
        // Arrange
        let currentBoard = board("Current")
        let targetBoard = board("Target")
        let desk = desk("Desk", boards: [currentBoard, targetBoard], focusedBoardID: currentBoard.id)
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))
        store.recordNotification(title: "First", body: "Finished", boardID: targetBoard.id)
        store.recordNotification(title: "Second", body: "Finished", boardID: targetBoard.id)
        store.recordNotification(title: "Other", body: "Finished", boardID: currentBoard.id)

        // Act
        store.focusBoard(targetBoard.id)

        // Assert
        #expect(store.focusedBoard?.id == targetBoard.id)
        #expect(store.unreadNotificationCount(for: targetBoard.id) == 0)
        #expect(store.unreadNotificationCount(for: currentBoard.id) == 1)
        #expect(store.unreadNotificationCount == 1)
    }

    @Test func focusingDeskMarksItsFocusedBoardNotificationsRead() {
        // Arrange
        let currentBoard = board("Current")
        let targetBoard = board("Target")
        let currentDesk = desk("Current", boards: [currentBoard], focusedBoardID: currentBoard.id)
        let targetDesk = desk("Target", boards: [targetBoard], focusedBoardID: targetBoard.id)
        let store = DenStore(
            state: DenState(desks: [currentDesk, targetDesk], focusedDeskID: currentDesk.id))
        store.recordNotification(title: "Build", body: "Finished", boardID: targetBoard.id)

        // Act
        store.focusDesk(targetDesk.id)

        // Assert
        #expect(store.unreadNotificationCount(for: targetBoard.id) == 0)
        #expect(store.unreadNotificationCount == 0)
    }

    @Test func clearingNotificationsRemovesSessionHistoryAfterConfirmation() {
        let target = board("Terminal")
        let desk = desk("Desk", boards: [target], focusedBoardID: target.id)
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        store.recordNotification(title: "Build", body: "Finished", boardID: target.id)
        viewModel.toggleNotificationList()
        store.requestNotificationClearConfirmation()

        #expect(viewModel.notificationPendingDeletionCount == 1)
        viewModel.confirmNotificationClear()

        #expect(store.notifications.isEmpty)
        #expect(store.unreadNotificationCount == 0)
        #expect(!viewModel.isNotificationListPresented)
        #expect(viewModel.notificationPendingDeletionCount == nil)
        #expect(store.latestFeedback == nil)
    }

    @Test func openingNotificationFocusesItsBoardAcrossDesksAndMarksItRead() {
        let target = board("Terminal")
        let first = desk("First")
        let second = desk("Second", boards: [target], focusedBoardID: target.id)
        let store = DenStore(state: DenState(desks: [first, second], focusedDeskID: first.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        store.recordNotification(title: "Build", body: "Finished", boardID: target.id)
        let notification = store.notifications[0]
        viewModel.toggleNotificationList()
        store.openNotification(notification)

        #expect(store.presentedDeskID == second.id)
        #expect(store.focusedBoard?.id == target.id)
        #expect(store.notifications[0].isRead)
        #expect(store.unreadNotificationCount == 0)
        #expect(!viewModel.isNotificationListPresented)
    }

    @Test func openingNotificationFeedbackTargetFocusesItsBoardAndMarksItRead() {
        let target = board("Terminal")
        let first = desk("First")
        let second = desk("Second", boards: [target], focusedBoardID: target.id)
        let store = DenStore(state: DenState(desks: [first, second], focusedDeskID: first.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        store.recordNotification(title: "Build", body: "Finished", boardID: target.id)
        viewModel.toggleNotificationList()
        store.openFeedbackTarget(store.latestFeedback?.target)

        #expect(store.presentedDeskID == second.id)
        #expect(store.focusedBoard?.id == target.id)
        #expect(store.notifications[0].isRead)
        #expect(!viewModel.isNotificationListPresented)
    }

    @Test func openingBoardFeedbackTargetFocusesItsBoard() {
        let target = board("Target")
        let first = desk("First")
        let second = desk("Second", boards: [target])
        let store = DenStore(
            state: DenState(desks: [first, second], focusedDeskID: first.id)
        )
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        viewModel.setTemporaryContext(.drawer)
        store.reportFeedback(title: "Build", body: "Finished", target: .board(target.id))
        store.openFeedbackTarget(store.latestFeedback?.target)

        #expect(store.presentedDeskID == second.id)
        #expect(store.focusedBoard?.id == target.id)
        #expect(viewModel.temporaryContext == nil)
    }

    @Test func openingDrawerFeedbackTargetOpensAndExpandsItem() throws {
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let drawerDesk = desk("Desk")
        let store = DenStore(
            state: DenState(
                desks: [drawerDesk],
                focusedDeskID: drawerDesk.id,
                drawerItems: [item])
        )
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        store.reportFeedback(
            title: nil,
            body: "Open item",
            target: DenFeedback.Target.drawerItem(item.id))
        store.openFeedbackTarget(store.latestFeedback?.target)

        #expect(viewModel.isDrawerOpen)
        #expect(viewModel.drawer.selectedItemID == item.id)
        #expect(viewModel.drawer.expandedItemID == item.id)
    }

    @Test func resetDenRequiresConfirmationBeforeChangingState() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [populated], focusedDeskID: populated.id),
            onSave: { savedState = $0 })
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let originalState = store.state

        viewModel.requestResetDenConfirmation()

        #expect(viewModel.isResetDenPending)
        #expect(store.state == originalState)
        #expect(savedState == nil)

        viewModel.cancelResetDen()

        #expect(!viewModel.isResetDenPending)
        #expect(store.state == originalState)
        #expect(savedState == nil)
    }

    @Test func latestConfirmationReplacesEarlierRequestAndCanBeCancelled() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        let store = DenStore(
            state: DenState(desks: [populated, empty], focusedDeskID: populated.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        store.deleteFocusedDesk()
        if case let .deleteDesk(pending)? = viewModel.pendingConfirmation {
            #expect(pending.id == populated.id)
        } else {
            Issue.record("Expected a desk deletion confirmation")
        }

        viewModel.requestResetDenConfirmation()
        #expect(viewModel.isResetDenPending)

        viewModel.cancelResetDen()
        #expect(!viewModel.hasPendingConfirmation)
    }

    @Test func confirmingResetDenUsesExistingResetBehavior() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [populated], focusedDeskID: populated.id),
            onSave: { savedState = $0 })
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        viewModel.requestResetDenConfirmation()
        viewModel.confirmResetDen()

        #expect(!viewModel.isResetDenPending)
        #expect(store.state.desks.count == 1)
        #expect(store.state.desks.first?.label == "Main")
        #expect(store.state.desks.first?.boards.isEmpty == true)
        #expect(store.state.focusedDeskID == store.state.desks.first?.id)
        #expect(savedState == store.state)
    }

    @Test func escapePassesThroughToSheetInput() throws {
        try withTestViewModel(desks: [desk("Desk")]) { viewModel in
            let store = viewModel.store
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

            #expect(!KeyboardController.handle(event, store: store, viewModel: viewModel))
            #expect(!viewModel.isDenMode)
        }
    }

    @Test func escapeExitsDenMode() throws {
        try withTestViewModel(desks: [desk("Desk")]) { viewModel in
            let store = viewModel.store
            viewModel.isDenMode = true
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

            #expect(KeyboardController.handle(event, store: store, viewModel: viewModel))
            #expect(!viewModel.isDenMode)
        }
    }

    @Test func directDeskSelectionExitsButRelativeNavigationKeepsDenMode() {
        let first = desk("First")
        let second = desk("Second")
        let third = desk("Third")
        withTestViewModel(desks: [first, second, third]) { viewModel in
            let store = viewModel.store
            // 1. focusDesk(number:) exits DenMode on actual switch
            viewModel.isDenMode = true
            store.focusDesk(number: 2)
            #expect(!viewModel.isDenMode)
            #expect(store.focusedDesk?.id == second.id)

            // focusDesk(number:) exits even when the target is already focused
            viewModel.isDenMode = true
            store.focusDesk(number: 2)
            #expect(!viewModel.isDenMode)

            // 2. focusDesk(_:) is direct selection
            store.focusDesk(third.id)
            #expect(!viewModel.isDenMode)
            #expect(store.focusedDesk?.id == third.id)

            // focusDesk(_:) exits even when the target is already focused
            viewModel.isDenMode = true
            store.focusDesk(third.id)
            #expect(!viewModel.isDenMode)

            // 3. Relative Desk Navigation keeps Den Mode active
            viewModel.isDenMode = true
            store.focusPreviousDesk()
            #expect(viewModel.isDenMode)
            #expect(store.focusedDesk?.id == second.id)

            viewModel.isDenMode = true
            store.focusNextDesk()
            #expect(viewModel.isDenMode)
            #expect(store.focusedDesk?.id == third.id)

            // 4. Overview confirmation exits even on the same Desk
            viewModel.showOverview()
            viewModel.isDenMode = true
            viewModel.overview.selectDesk(first.id)
            viewModel.overview.enterSelection()
            #expect(!viewModel.isDenMode)
            #expect(store.focusedDesk?.id == first.id)

            // Entering the selected Desk exits even when the target is already focused.
            viewModel.showOverview()
            viewModel.isDenMode = true
            viewModel.overview.selectDesk(first.id)
            viewModel.overview.enterSelection()
            #expect(!viewModel.isDenMode)
        }
    }

    @Test func boardRenamingAndCustomLabelStickiness() {
        let googleBoard = board("Google", url: "https://google.com")
        withTestViewModel(desks: [desk("Main", boards: [googleBoard])]) { viewModel in
            let store = viewModel.store
            // 1. Initially, customLabel is nil, displayName returns page title
            let boardID = googleBoard.id
            guard
                let deskIndex = store.focusedDeskIndex,
                let boardIndex = store.focusedBoardIndex(in: deskIndex)
            else {
                Issue.record("Failed to find focused board indices")
                return
            }
            #expect(store.state.desks[deskIndex].boards[boardIndex].customLabel == nil)
            #expect(store.state.desks[deskIndex].boards[boardIndex].displayName == "Google")

            // 2. Rename the board to a custom name
            store.renameFocusedBoard(to: "Search Tasks")
            #expect(store.state.desks[deskIndex].boards[boardIndex].customLabel == "Search Tasks")
            #expect(store.state.desks[deskIndex].boards[boardIndex].displayName == "Search Tasks")
            #expect(!viewModel.isDenMode)

            // 3. Navigation doesn't overwrite customLabel, but updates label
            store.updateBoard(
                boardID: boardID,
                url: URL(string: "https://google.com/search"),
                title: "Google Search Result"
            )
            // Original label is updated in the background
            #expect(store.state.desks[deskIndex].boards[boardIndex].label == "Google Search Result")
            // customLabel is untouched
            #expect(store.state.desks[deskIndex].boards[boardIndex].customLabel == "Search Tasks")
            // displayName still shows custom label
            #expect(store.state.desks[deskIndex].boards[boardIndex].displayName == "Search Tasks")

            // 4. Duplicate the board (duplicate should copy customLabel)
            store.toggleBoardSheetNavigationPause(boardID)
            viewModel.isDenMode = true
            store.duplicateFocusedBoard()
            let boards = store.focusedDesk?.boards ?? []
            #expect(boards.count == 2)
            #expect(boards[1].customLabel == "Search Tasks")
            #expect(boards[1].displayName == "Search Tasks")
            #expect(boards[0].sheetNavigationPaused)
            #expect(boards[1].sheetNavigationPaused)

            // 5. Focus original board and clear the label
            store.focusBoard(boardID)
            store.renameFocusedBoard(to: "")
            store.toggleBoardSheetNavigationPause(boardID)
            #expect(store.state.desks[deskIndex].boards[boardIndex].customLabel == nil)
            #expect(store.state.desks[deskIndex].boards[boardIndex].displayName == "Google Search Result")
            #expect(!store.state.desks[deskIndex].boards[boardIndex].sheetNavigationPaused)
        }
    }

    @Test func controlCommaTogglesDenMode() throws {
        try withTestViewModel(desks: [desk("Desk")]) { viewModel in
            let store = viewModel.store
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

            #expect(KeyboardController.handle(event, store: store, viewModel: viewModel))
            #expect(viewModel.isDenMode)
            #expect(KeyboardController.handle(event, store: store, viewModel: viewModel))
            #expect(!viewModel.isDenMode)
        }
    }

    @Test func controlPeriodPassesThroughToSheetInput() throws {
        try withTestViewModel(desks: [desk("Desk")]) { viewModel in
            let store = viewModel.store
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

            #expect(!KeyboardController.handle(event, store: store, viewModel: viewModel))
            #expect(!viewModel.isDenMode)
        }
    }

    @Test func commandOptionArrowsNavigateBoardsWithoutEnteringDenMode() throws {
        let boards = [board("First"), board("Second")]
        try withTestViewModel(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { viewModel in
            let store = viewModel.store
            let right = try arrowEvent(.rightArrow, modifiers: [.command, .option])
            let left = try arrowEvent(.leftArrow, modifiers: [.command, .option])

            #expect(KeyboardController.handle(right, store: store, viewModel: viewModel))
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(!viewModel.isDenMode)

            #expect(KeyboardController.handle(left, store: store, viewModel: viewModel))
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(!viewModel.isDenMode)
        }
    }

    @Test func shiftCommandOptionArrowsMoveFocusedBoardWithoutEnteringDenMode() throws {
        let boards = [board("First"), board("Second")]
        try withTestViewModel(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { viewModel in
            let store = viewModel.store
            let right = try arrowEvent(.rightArrow, modifiers: [.command, .option, .shift])
            let left = try arrowEvent(.leftArrow, modifiers: [.command, .option, .shift])

            #expect(KeyboardController.handle(right, store: store, viewModel: viewModel))
            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id])
            #expect(!viewModel.isDenMode)

            #expect(KeyboardController.handle(left, store: store, viewModel: viewModel))
            #expect(store.focusedDesk?.boards.map(\.id) == boards.map(\.id))
            #expect(!viewModel.isDenMode)
        }
    }

    @Test func commandQPassesThroughFromDenMode() throws {
        try withTestViewModel(desks: [desk("Desk")]) { viewModel in
            let store = viewModel.store
            viewModel.isDenMode = true
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

            #expect(!KeyboardController.handle(event, store: store, viewModel: viewModel))
            #expect(viewModel.isDenMode)
        }
    }

    @Test func denModeMaximizesAndCentersFocusedBoardWithoutChangingDenState() throws {
        let current = board("Current", width: 520)
        try withTestViewModel(desks: [desk("Desk", boards: [current])]) { viewModel in
            let store = viewModel.store
            viewModel.isDenMode = true
            let stateBeforeCommands = store.state
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

            #expect(KeyboardController.handle(maximize, store: store, viewModel: viewModel))
            #expect(viewModel.maximizedBoardID == current.id)
            let requestAfterMaximize = viewModel.centerFocusedBoardRequest
            #expect(KeyboardController.handle(center, store: store, viewModel: viewModel))
            #expect(viewModel.centerFocusedBoardRequest == requestAfterMaximize + 1)
            #expect(KeyboardController.handle(maximize, store: store, viewModel: viewModel))
            #expect(viewModel.maximizedBoardID == nil)
            #expect(store.state == stateBeforeCommands)
        }
    }

    @Test func focusModeIsRuntimeOnlyAndIgnoresKeyRepeat() throws {
        let first = board("First")
        let second = board("Second")
        let deskState = desk("Desk", boards: [first, second], focusedBoardID: first.id)
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [deskState], focusedDeskID: deskState.id),
            onSave: { savedState = $0 })
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let stateBeforeToggle = store.state
        viewModel.isDenMode = true

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

        #expect(KeyboardController.handle(toggle, store: store, viewModel: viewModel))
        #expect(viewModel.isFocusModePresented)
        #expect(store.state == stateBeforeToggle)
        #expect(savedState == nil)
        #expect(KeyboardController.handle(repeatedToggle, store: store, viewModel: viewModel))
        #expect(viewModel.isFocusModePresented)

        viewModel.exitDenMode()

        #expect(viewModel.isFocusModePresented)
        #expect(store.state == stateBeforeToggle)
        #expect(savedState == nil)
    }

    @Test func denModeBoardWidthPanelAdjustsAllBoardsAndAcceptsFitSelectionKeys() throws {
        let boards = [board("First"), board("Second")]
        try withTestViewModel(desks: [desk("Desk", boards: boards)]) { viewModel in
            let store = viewModel.store
            viewModel.isDenMode = true
            viewModel.updateBoardLayout(availableWidth: 1_180, spacing: 10)
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

            #expect(KeyboardController.handle(open, store: store, viewModel: viewModel))
            #expect(viewModel.isBoardWidthPanelPresented)
            #expect(KeyboardController.handle(ignoredMovement, store: store, viewModel: viewModel))
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(KeyboardController.handle(narrow, store: store, viewModel: viewModel))
            #expect(store.focusedDesk?.boards.map(\.width) == [440, 440])
            #expect(viewModel.isBoardWidthPanelPresented)
            #expect(KeyboardController.handle(widen, store: store, viewModel: viewModel))
            #expect(store.focusedDesk?.boards.map(\.width) == [520, 520])
            #expect(viewModel.isBoardWidthPanelPresented)
            #expect(KeyboardController.handle(select, store: store, viewModel: viewModel))
            #expect(!viewModel.isBoardWidthPanelPresented)
            #expect(viewModel.isDenMode)
            #expect(
                store.focusedDesk?.boards.allSatisfy {
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
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        viewModel.showSaveEssentialPanel(for: board)

        #expect(viewModel.isSaveEssentialPanelPresented)
        #expect(
            viewModel.saveEssentialDraft
                == SaveEssentialDraft(
                    name: "Example Docs",
                    key: "",
                    input: "https://docs.example.com/api"
                ))

        viewModel.hideSaveEssentialPanel()
        #expect(!viewModel.isSaveEssentialPanelPresented)
        #expect(viewModel.saveEssentialDraft == nil)
    }

    @Test func showSaveEssentialPanelForTerminalBoardPopulatesDraft() {
        let terminalBoard = BoardState(
            label: "Project Shell",
            width: 520,
            workingDirectory: "/Users/test/projects/demo"
        )
        let desk = DeskState(label: "Terminal", boards: [terminalBoard], focusedBoardID: terminalBoard.id)
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        viewModel.showSaveEssentialPanel(for: terminalBoard)

        #expect(viewModel.isSaveEssentialPanelPresented)
        #expect(viewModel.saveEssentialDraft?.name == "Project Shell")
        #expect(viewModel.saveEssentialDraft?.input == ":terminal /Users/test/projects/demo")
    }

    @Test func showSaveEssentialPanelForRecentItemPopulatesDraft() {
        let store = DenStore(state: .sample)
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let recent = RecentItem.url(URL(string: "https://github.com/apple/swift")!)

        viewModel.showSaveEssentialPanel(for: recent)

        #expect(viewModel.isSaveEssentialPanelPresented)
        #expect(viewModel.saveEssentialDraft?.name == "github.com")
        #expect(viewModel.saveEssentialDraft?.input == "https://github.com/apple/swift")
    }

    @Test func saveEssentialValidatesInputAndUpdatesPreferences() {
        withTestStore { store in
            withTestViewModel(store: store) { viewModel in
                viewModel.showSaveEssentialPanel(name: "Test", key: "", input: "https://test.com")
                #expect(viewModel.isSaveEssentialPanelPresented)

                // Invalid: empty key
                #expect(!viewModel.saveEssential(name: "Test", key: "", input: "https://test.com"))
                #expect(viewModel.isSaveEssentialPanelPresented)

                // Invalid: multi-char key
                #expect(!viewModel.saveEssential(name: "Test", key: "ab", input: "https://test.com"))

                // Valid save
                #expect(viewModel.saveEssential(name: "Test", key: "t", input: "https://test.com"))
                #expect(!viewModel.isSaveEssentialPanelPresented)
                #expect(store.essentials.contains { $0.key == "t" && $0.name == "Test" })
                #expect(store.latestFeedback?.message == "Saved Essential 'Test'.")
                #expect(store.latestFeedback?.severity == .success)

                // Duplicate key conflict rejected
                viewModel.showSaveEssentialPanel(name: "Another", key: "t", input: "https://another.com")
                #expect(!viewModel.saveEssential(name: "Another", key: "t", input: "https://another.com"))
                #expect(viewModel.isSaveEssentialPanelPresented)
            }
        }
    }

    @Test func saveFocusedBoardAsEssentialShowsToastWhenNoBoardFocused() {
        withTestViewModel(desks: [desk("Empty")]) { viewModel in
            let store = viewModel.store
            viewModel.saveFocusedBoardAsEssential()
            #expect(!viewModel.isSaveEssentialPanelPresented)
            #expect(store.latestFeedback?.message == "No focused board.")
            #expect(store.latestFeedback?.severity == .warning)
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
