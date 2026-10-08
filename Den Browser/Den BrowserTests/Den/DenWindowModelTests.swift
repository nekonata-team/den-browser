import DenDomain
import DenPresentation
import Foundation
import Observation
import Synchronization
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenWindowModelTests {
    enum NotificationUpdate: CaseIterable {
        case added, read, sourceTitleChanged, sourceRemoved
    }

    @Test(arguments: NotificationUpdate.allCases)
    func notificationListKeepsLiveDisplayInputsObservable(update: NotificationUpdate) throws {
        // Arrange
        let board = BoardState(label: "Board", width: 520, currentSheetURL: URL(string: "https://board.example/"))
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))
        store.recordNotification(title: "Build", body: "Finished", boardID: board.id)
        let notificationID = try #require(store.notifications.first?.id)
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        let changed = Mutex(false)
        withObservationTracking {
            _ = windowModel.notificationList.items
            _ = windowModel.notificationList.unreadCount
        } onChange: {
            changed.withLock { $0 = true }
        }

        // Act
        switch update {
        case .added:
            store.recordNotification(title: "Another build", body: "Finished", boardID: board.id)
        case .read:
            store.markNotificationRead(notificationID)
        case .sourceTitleChanged:
            store.updateBoard(boardID: board.id, url: nil, title: "Updated title")
        case .sourceRemoved:
            store.removeBoard(board.id)
        }

        // Assert
        #expect(changed.withLock { $0 })
        let items = windowModel.notificationList.items
        switch update {
        case .added:
            #expect(items.count == 2)
            #expect(windowModel.notificationList.unreadCount == 2)
        case .read:
            #expect(items.first?.notification.isRead == true)
            #expect(windowModel.notificationList.unreadCount == 0)
        case .sourceTitleChanged:
            #expect(items.first?.source?.boardLabel == "Updated title")
        case .sourceRemoved:
            #expect(items.first?.source == nil)
        }
    }

    @Test(arguments: [false, true])
    func runtimeFocusSelectsWebBoardButDoesNotStealFocusForTerminal(isTerminal: Bool) {
        // Arrange
        let current = BoardState(label: "Current", width: 520, currentSheetURL: URL(string: "https://current.example/"))
        let target =
            isTerminal
            ? BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
            : BoardState(label: "Web", width: 520, currentSheetURL: URL(string: "https://target.example/"))
        let desk = DeskState(label: "Desk", boards: [current, target], focusedBoardID: current.id)
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let composition = DenWindowComposition(store: store)
        composition.connect()
        defer { composition.disconnect() }

        // Act
        store.onWindowEffect?(.runtimeFocusedBoard(target.id))

        // Assert
        #expect(store.focusedBoard?.id == (isTerminal ? current.id : target.id))
    }

    @Test func deletionInAnotherWindowInvalidatesSelectionAndInsertionReferences() {
        // Arrange
        let board = BoardState(label: "Board", width: 520, currentSheetURL: URL(string: "https://board.example/"))
        let selectedBoard =
            BoardState(label: "Selected", width: 520, currentSheetURL: URL(string: "https://selected.example/"))
        let mainDesk = DeskState(label: "Main", boards: [board], focusedBoardID: board.id)
        let selectedDesk = DeskState(label: "Selected", boards: [selectedBoard], focusedBoardID: selectedBoard.id)
        let otherDesk = DeskState(label: "Other", boards: [])
        let storage = DenProfileResources(
            state: DenState(desks: [mainDesk, selectedDesk, otherDesk], focusedDeskID: mainDesk.id))
        let defaults = makeTestDefaults()
        let pasteboard = NSPasteboard.withUniqueName()
        let sheetNavigation = SheetNavigationManager(
            defaults: defaults, pasteboard: pasteboard, scriptSource: "")
        let preferences = AppPreferences(defaults: defaults)
        func makeStore(presenting deskID: DeskID) -> DenStore {
            DenStore(
                storage: storage,
                presentedDeskID: deskID,
                websiteDataStore: .nonPersistent(),
                sheetNavigation: sheetNavigation,
                preferences: preferences,
                pasteboard: pasteboard,
                canPresentDesk: { _ in true },
                onDeskPresentationRequest: { _ in true },
                onWillResetDen: {})
        }
        let deletingStore = makeStore(presenting: mainDesk.id)
        let otherWindowComposition = DenWindowComposition(store: makeStore(presenting: otherDesk.id))
        let otherWindow = otherWindowComposition.model
        otherWindowComposition.connect()
        defer { otherWindowComposition.disconnect() }
        otherWindow.overview.preparePresentation(deskID: mainDesk.id, boardID: board.id)
        otherWindow.openBoard.preparePresentation(afterBoardID: board.id)

        // Act - another window removes the Board.
        deletingStore.removeBoard(board.id)

        // Assert
        #expect(otherWindow.overview.selectionBoardID == nil)
        #expect(otherWindow.openBoard.afterBoardID == nil)

        // Act - another window removes the Desk currently selected in Overview.
        otherWindow.overview.preparePresentation(deskID: selectedDesk.id, boardID: selectedBoard.id)
        deletingStore.confirmDeskDeletion(selectedDesk.id)

        // Assert
        #expect(otherWindow.overview.selectionDeskID == nil)
        #expect(otherWindow.overview.selectionBoardID == nil)
    }

    @Test func latestFeedbackIsDisplayedAndPreviousTimerCannotDismissReplacement() async {
        // Arrange
        let store = DenStore(state: .sample)
        let composition = DenWindowComposition(store: store, feedbackDuration: .milliseconds(150))
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        // Act
        store.reportFeedback("First")
        try? await Task.sleep(for: .milliseconds(100))
        store.reportFeedback("Latest")
        try? await Task.sleep(for: .milliseconds(70))

        // Assert
        #expect(windowModel.displayedFeedback?.body == "Latest")

        try? await Task.sleep(for: .milliseconds(110))
        #expect(windowModel.displayedFeedback == nil)
    }

    @Test func receivingSameFeedbackAgainDoesNotRedisplayAfterDismissal() {
        // Arrange
        let store = DenStore(state: .sample)
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let feedback = DenFeedback(body: "Saved")

        // Act
        windowModel.receive(.feedback(feedback))
        windowModel.dismissFeedback()
        windowModel.receive(.feedback(feedback))

        // Assert
        #expect(windowModel.displayedFeedback == nil)
    }

    @Test func tappingFeedbackOpensTargetAndDismissesIt() throws {
        // Arrange
        let board = BoardState(label: "Target", width: 520, currentSheetURL: URL(string: "https://example.com/"))
        let first = DeskState(label: "Empty", boards: [])
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let store = DenStore(
            state: DenState(desks: [first, desk], focusedDeskID: first.id))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        store.reportFeedback(title: "Build", body: "Finished", target: .board(board.id))
        let feedback = try #require(windowModel.displayedFeedback)

        // Act
        windowModel.handleTap(on: feedback)

        // Assert
        #expect(store.focusedBoard?.id == board.id)
        #expect(windowModel.temporaryContext == nil)
        #expect(windowModel.displayedFeedback == nil)
    }

    @Test func tappingUntargetedFeedbackDismissesItWithoutChangingState() throws {
        // Arrange
        let store = DenStore(state: .sample)
        let initialState = store.state
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        store.reportFeedback("Saved")
        let feedback = try #require(windowModel.displayedFeedback)

        // Act
        windowModel.handleTap(on: feedback)

        // Assert
        #expect(windowModel.displayedFeedback == nil)
        #expect(store.state == initialState)
    }
}
