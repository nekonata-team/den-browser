import AppKit
import DenApplication
import DenDomain
import DenPresentation
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenStoreDeskTests {

    @Test func createsEmptyDeskAfterFocusedDesk() {
        withTestWindowModel(desks: [desk("First"), desk("Second")]) { windowModel in
            let store = windowModel.store
            windowModel.isDenMode = true
            store.createDesk(label: "  Writing  ", preset: .empty)

            #expect(store.state.desks.map(\.label) == ["First", "Writing", "Second"])
            #expect(store.focusedDesk?.label == "Writing")
            #expect(store.focusedDesk?.boards.isEmpty == true)
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func creatingDeskCompletesTutorialDeskStep() {
        // Arrange
        let sourceDesk = desk("First")
        let store = DenStore(state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))
        #expect(store.openTutorialBoard())
        #expect(store.openBoard(input: "https://one.example/"))
        #expect(store.focusedDesk?.boards.count == 2)
        store.focusNextBoard()

        // Act
        store.createDesk(label: "Writing", preset: .empty)

        // Assert
        #expect(store.focusedDesk?.label == "Writing")
        #expect(
            store.state.desks.flatMap(\.boards).first(where: \.isTutorial)?.tutorialCompletedSteps?.isSuperset(
                of: [.openBoard, .navigateBoards, .createDesk]) == true)
    }

    @Test func createsChatGPTPresetWithThreeBoards() {
        withStore(desks: [desk("First")]) { store in
            store.createDesk(label: "AI", preset: .chatGPT)

            #expect(store.focusedDesk?.boards.count == 3)
            #expect(
                store.focusedDesk?.boards.allSatisfy {
                    $0.currentSheetURL == URL(string: "https://chatgpt.com/")
                } == true)
            #expect(store.focusedDesk?.boards.allSatisfy { $0.width == 520 } == true)
            #expect(store.focusedDesk?.focusedBoardID == store.focusedDesk?.boards.first?.id)
        }
    }

    @Test func createsGeminiPresetWithThreeBoards() {
        withStore(desks: [desk("First")]) { store in
            store.createDesk(label: "Gemini", preset: .gemini)

            #expect(store.focusedDesk?.boards.count == 3)
            #expect(
                store.focusedDesk?.boards.allSatisfy {
                    $0.currentSheetURL == URL(string: "https://gemini.google.com/") && $0.width == 520
                } == true)
        }
    }

    @Test func deskCreationStopsAtTenDesks() {
        let desks = (1...DenStore.maximumDeskCount).map { desk("Desk \($0)") }
        withStore(desks: desks) { store in
            store.createDesk(label: "Overflow", preset: .empty)

            #expect(store.state.desks.count == DenStore.maximumDeskCount)
            #expect(!store.canCreateDesk)
        }
    }

    @Test func replacingPopulatedDeskRequiresConfirmationAndReleasesItsBoards() throws {
        let oldBoards = [board("First"), board("Second")]
        let replacing = desk("Research", boards: oldBoards, focusedBoardID: oldBoards[1].id)
        let other = desk("Other")
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [replacing, other], focusedDeskID: replacing.id),
            onSave: { savedState = $0 })
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let runtime = store.webRuntime(for: oldBoards[0])
        let restorationCandidate = RecentlyRemovedBoard(
            board: board("Removed"),
            sourceDeskID: other.id,
            sourceBoardIndex: 0)
        store.storage.recentlyRemovedBoards = [restorationCandidate]
        windowModel.toggleFocusedBoardMaximized()
        windowModel.showReplaceDeskPanel()

        let result = store.replaceFocusedDesk(label: "  Morning  ", preset: .chatGPT)

        #expect(result == .confirmationPending)
        #expect(store.focusedDesk == replacing)
        if case let .replaceDesk(replacement)? = windowModel.pendingConfirmation {
            #expect(replacement.presetLabel == BuiltInDeskPreset.chatGPT.label)
        } else {
            Issue.record("Expected a desk replacement confirmation")
        }
        #expect(windowModel.isReplaceDeskPanelPresented)
        #expect(savedState == nil)

        windowModel.confirmDeskReplacement()

        let replaced = try #require(store.focusedDesk)
        #expect(replaced.id == replacing.id)
        #expect(store.state.desks.map(\.id) == [replacing.id, other.id])
        #expect(replaced.label == "Morning")
        #expect(replaced.boards.count == 3)
        #expect(replaced.boards.allSatisfy { $0.currentSheetURL == URL(string: "https://chatgpt.com/") })
        #expect(Set(replaced.boards.map(\.id)).isDisjoint(with: oldBoards.map(\.id)))
        #expect(replaced.focusedBoardID == replaced.boards.first?.id)
        #expect(store.webRuntimes[oldBoards[0].id] == nil)
        #expect(runtime.webView.navigationDelegate == nil)
        #expect(runtime.webView.uiDelegate == nil)
        #expect(windowModel.maximizedBoardID == nil)
        #expect(store.recentlyRemovedBoards.first?.board.id == restorationCandidate.board.id)
        #expect(!windowModel.isReplaceDeskPanelPresented)
        #expect(!windowModel.isDenMode)
        #expect(savedState == store.state)
    }

    @Test func replacingDeskDiscardsPausedStateWithItsBoards() {
        let oldBoard = BoardState(
            label: "Old",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/"),
            sheetNavigationPaused: true)
        let replacing = desk("Research", boards: [oldBoard], focusedBoardID: oldBoard.id)
        let other = desk("Other")
        let store = DenStore(
            state: DenState(desks: [replacing, other], focusedDeskID: replacing.id))

        let composition = DenWindowComposition(store: store)

        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        _ = store.replaceFocusedDesk(label: "Morning", preset: .chatGPT)
        windowModel.confirmDeskReplacement()

        #expect(!store.state.desks.flatMap(\.boards).contains { $0.id == oldBoard.id })
    }

    @Test func replacingDeskInvalidatesReferencesToRemovedBoards() {
        // Arrange
        let oldBoards = [board("First"), board("Second")]
        var replacing = desk("Research", boards: oldBoards, focusedBoardID: oldBoards[1].id)
        replacing.anchorBoardID = oldBoards[0].id
        let store = DenStore(state: DenState(desks: [replacing], focusedDeskID: replacing.id))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        store.anchorJumpOriginBoardIDByDesk[replacing.id] = oldBoards[1].id
        _ = store.prepareBoardLinkFocus(oldBoards[1].id)
        windowModel.overview.selectBoard(oldBoards[1].id)
        windowModel.showReplaceDeskPanel()
        windowModel.openBoard.afterBoardID = oldBoards[0].id
        _ = store.replaceFocusedDesk(label: "Morning", preset: .chatGPT)

        // Act
        windowModel.confirmDeskReplacement()

        // Assert
        #expect(store.focusedDesk?.anchorBoardID == nil)
        #expect(store.anchorJumpOriginBoardIDByDesk[replacing.id] == nil)
        #expect(windowModel.openBoard.afterBoardID == nil)
        #expect(windowModel.pendingBoardLinkFocus == nil)
        #expect(windowModel.overview.selectionDeskID == nil)
        #expect(windowModel.overview.selectionBoardID == nil)
    }

    @Test func cancellingDeskReplacementKeepsDeskAndPanel() {
        let existing = board("Existing")
        let original = desk("Original", boards: [existing])
        withTestWindowModel(desks: [original]) { windowModel in
            let store = windowModel.store
            windowModel.showReplaceDeskPanel()
            #expect(store.replaceFocusedDesk(label: "AI", preset: .gemini) == .confirmationPending)

            windowModel.cancelConfirmation()

            #expect(store.focusedDesk == original)
            #expect(windowModel.pendingConfirmation == nil)
            #expect(windowModel.isReplaceDeskPanelPresented)
        }
    }

    @Test func replacingEmptyDeskAppliesImmediatelyAndEmptyPresetIsUnavailable() {
        let empty = desk("Empty")
        withTestWindowModel(desks: [empty]) { windowModel in
            let store = windowModel.store
            windowModel.showReplaceDeskPanel()

            #expect(store.replaceFocusedDesk(label: "Still Empty", preset: .empty) == .unavailable)
            #expect(store.focusedDesk == empty)
            #expect(store.replaceFocusedDesk(label: "Gemini", preset: .gemini) == .applied)

            #expect(store.focusedDesk?.id == empty.id)
            #expect(store.focusedDesk?.label == "Gemini")
            #expect(store.focusedDesk?.boards.count == 3)
            #expect(!windowModel.isReplaceDeskPanelPresented)
        }
    }

    @Test func deletingEmptyDeskFocusesPreviousDeskWhenAvailable() {
        let first = desk("First")
        let empty = desk("Empty")
        let third = desk("Third")
        withTestWindowModel(desks: [first, empty, third]) { windowModel in
            let store = windowModel.store
            store.focusDesk(empty.id)
            windowModel.isDenMode = true
            store.deleteFocusedDesk()

            #expect(store.state.desks.map(\.id) == [first.id, third.id])
            #expect(store.focusedDesk?.id == first.id)
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func deletingFirstDeskFocusesNextDeskWhenPreviousDeskIsUnavailable() {
        let first = desk("First")
        let second = desk("Second")
        withStore(desks: [first, second]) { store in
            store.deleteFocusedDesk()

            #expect(store.state.desks.map(\.id) == [second.id])
            #expect(store.focusedDesk?.id == second.id)
        }
    }

    @Test func confirmingDeletionOfUnfocusedDeskClearsPreviousFocusedDeskID() {
        let first = desk("First")
        let secondBoard = board("SecondBoard")
        let second = desk("Second", boards: [secondBoard])
        let third = desk("Third")
        withTestWindowModel(desks: [first, second, third]) { windowModel in
            let store = windowModel.store
            store.focusDesk(second.id)
            store.deleteFocusedDesk()
            if case let .deleteDesk(pending)? = windowModel.pendingConfirmation {
                #expect(pending.id == second.id)
            } else {
                Issue.record("Expected a desk deletion confirmation")
            }

            // Switch to third desk, then confirm deletion of second desk
            store.focusDesk(third.id)
            #expect(store.previousFocusedDeskID == second.id)

            windowModel.confirmDeskDeletion()
            #expect(store.state.desks.map(\.id) == [first.id, third.id])
            #expect(store.previousFocusedDeskID == nil)
        }
    }

    @Test func returnToPreviousDeskTogglesBetweenMostRecentDesks() {
        let first = desk("First")
        let second = desk("Second")
        let third = desk("Third")
        let store = DenStore(
            state: DenState(desks: [first, second, third], focusedDeskID: first.id))

        store.focusDesk(second.id)
        store.focusDesk(third.id)
        store.returnToPreviousDesk()
        #expect(store.focusedDesk?.id == second.id)

        store.returnToPreviousDesk()
        #expect(store.focusedDesk?.id == third.id)
    }

    @Test func normalizedPersistedStateEnsuresFocusedObjects() {
        let boardItem = board("Board")
        let tutorialBoard = BoardState(
            label: "Tutorial",
            width: 520,
            tutorial: TutorialBoardState())
        var first = desk(
            "First",
            boards: [tutorialBoard, boardItem],
            focusedBoardID: tutorialBoard.id)
        first.anchorBoardID = tutorialBoard.id
        first.scrollOffsetX = 80
        let second = desk("Second")
        let tutorialOnlyBoard = BoardState(
            label: "Tutorial",
            width: 520,
            tutorial: TutorialBoardState())
        let tutorialOnlyDesk = desk(
            "Tutorial only",
            boards: [tutorialOnlyBoard],
            focusedBoardID: tutorialOnlyBoard.id)
        let rawState = DenState(desks: [second, first, tutorialOnlyDesk], focusedDeskID: DeskID())

        let normalized = DenStore.normalizedPersistedState(rawState)
        #expect(normalized.focusedDeskID == second.id)
        #expect(normalized.desks[1].focusedBoardID == boardItem.id)
        #expect(normalized.desks[1].boards.map(\.id) == [boardItem.id])
        #expect(normalized.desks[1].anchorBoardID == nil)
        #expect(normalized.desks[1].scrollOffsetX == nil)
        #expect(normalized.desks[2].boards.isEmpty)
        #expect(normalized.desks[2].focusedBoardID == nil)
    }

    @Test func focusDeskByNumberDelegatesToFocusDesk() {
        let first = desk("First")
        let second = desk("Second")
        let store = DenStore(state: DenState(desks: [first, second], focusedDeskID: first.id))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.isDenMode = true
        store.focusDesk(number: 2)
        #expect(store.focusedDesk?.id == second.id)
        #expect(!windowModel.isDenMode)
    }

    @Test func deskLinkExportPreservesBoardOrderAndSkipsEmptyBoards() throws {
        let first = BoardState(
            label: "First [Reference]",
            width: 520,
            currentSheetURL: URL(string: "https://first.example/"))
        let empty = BoardState(label: "Empty", width: 520, currentSheetURL: nil)
        let second = BoardState(
            label: "Second",
            width: 520,
            currentSheetURL: URL(string: "https://second.example/path"))
        let desk = DeskState(label: "Research", boards: [first, empty, second])

        let expected = [
            "# Research",
            "",
            "- [First \\[Reference\\]](<https://first.example/>)",
            "- [Second](<https://second.example/path>)",
            "",
        ].joined(separator: "\n")
        #expect(DeskLinkExport.markdown(for: desk) == expected)
    }

    @Test func deskDragReordersPersistedDesksWithoutChangingTheirContents() {
        let firstBoard = board("First Board")
        let secondBoard = board("Second Board")
        let first = desk("First", boards: [firstBoard], focusedBoardID: firstBoard.id)
        let second = desk("Second", boards: [secondBoard], focusedBoardID: secondBoard.id)
        let third = desk("Third")
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [first, second, third], focusedDeskID: first.id),
            onSave: { savedState = $0 })

        #expect(store.beginDeskDrag(second.id))
        store.previewDeskMove(second.id, to: 2)
        store.updateBoard(
            boardID: secondBoard.id,
            url: URL(string: "https://updated.example/"),
            title: "Updated title")

        #expect(savedState == nil)

        store.finishDeskDrag()

        #expect(store.state.desks.map(\.id) == [first.id, third.id, second.id])
        #expect(store.focusedDesk?.id == first.id)
        #expect(store.state.desks[2].boards.map(\.id) == [secondBoard.id])
        #expect(store.state.desks[2].focusedBoardID == secondBoard.id)
        #expect(store.state.desks[2].boards[0].currentSheetURL == URL(string: "https://updated.example/"))
        #expect(store.state.desks[2].boards[0].label == "Updated title")
        #expect(savedState == store.state)

        store.previewDeskMove(second.id, to: 2)
        #expect(store.state.desks.map(\.id) == [first.id, third.id, second.id])
    }

    @Test func movingDeskByAccessibilityActionReordersOneStepAndPreservesFocus() {
        let first = desk("First")
        let second = desk("Second")
        let third = desk("Third")
        let store = DenStore(
            state: DenState(desks: [first, second, third], focusedDeskID: second.id))

        store.moveDesk(first.id, by: 1)

        #expect(store.state.desks.map(\.id) == [second.id, first.id, third.id])
        #expect(store.focusedDesk?.id == second.id)

        store.moveDesk(third.id, by: 1)
        #expect(store.state.desks.map(\.id) == [second.id, first.id, third.id])

        #expect(store.beginDeskDrag(first.id))
        store.moveDesk(third.id, by: -1)
        #expect(store.state.desks.map(\.id) == [second.id, first.id, third.id])
        store.finishDeskDrag()
    }

    @Test func cancellingDeskDragPersistsRestoredOrderAfterBoardUpdate() {
        let firstBoard = board("First Board")
        let secondBoard = board("Second Board")
        let first = desk("First", boards: [firstBoard], focusedBoardID: firstBoard.id)
        let second = desk("Second", boards: [secondBoard], focusedBoardID: secondBoard.id)
        let third = desk("Third")
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [first, second, third], focusedDeskID: first.id),
            onSave: { savedState = $0 })

        #expect(store.beginDeskDrag(second.id))
        store.previewDeskMove(second.id, to: 2)
        store.updateBoard(
            boardID: secondBoard.id,
            url: URL(string: "https://updated.example/"),
            title: "Updated title")
        #expect(savedState == nil)

        store.restoreDeskOrder([first.id, second.id, third.id])
        store.finishDeskDrag()

        #expect(store.state.desks.map(\.id) == [first.id, second.id, third.id])
        #expect(store.state.desks[1].boards[0].currentSheetURL == URL(string: "https://updated.example/"))
        #expect(store.state.desks[1].boards[0].label == "Updated title")
        #expect(savedState == store.state)
    }

    @Test func deletingDeskWithBoardsRequiresConfirmation() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        withTestWindowModel(desks: [populated, empty]) { windowModel in
            let store = windowModel.store
            store.deleteFocusedDesk()

            #expect(store.state.desks.count == 2)
            if case let .deleteDesk(pending)? = windowModel.pendingConfirmation {
                #expect(pending.id == populated.id)
            } else {
                Issue.record("Expected a desk deletion confirmation")
            }

            store.focusDesk(empty.id)
            windowModel.confirmDeskDeletion()
            #expect(store.state.desks.map(\.id) == [empty.id])
            #expect(store.focusedDesk?.id == empty.id)
            #expect(windowModel.pendingConfirmation == nil)
        }
    }

    @Test func confirmingDeskDeletionExitsDenModeAfterSuccessfulDeletion() {
        let populated = desk("Populated", boards: [board("Board")])
        let empty = desk("Empty")
        withTestWindowModel(desks: [populated, empty]) { windowModel in
            let store = windowModel.store
            windowModel.isDenMode = true
            store.deleteFocusedDesk()

            #expect(windowModel.isDenMode)
            windowModel.confirmDeskDeletion()

            #expect(!windowModel.isDenMode)
        }
    }

    @Test func cancellingDeskDeletionKeepsBoards() {
        let populated = desk("Populated", boards: [board("Board")])
        let empty = desk("Empty")
        withTestWindowModel(desks: [populated, empty]) { windowModel in
            let store = windowModel.store
            store.deleteFocusedDesk()
            windowModel.cancelConfirmation()

            #expect(store.state.desks.map(\.id) == [populated.id, empty.id])
            #expect(windowModel.pendingConfirmation == nil)
        }
    }

    @Test func deletingDeskDisposesItsBoardRuntimes() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        withTestWindowModel(desks: [populated, empty]) { windowModel in
            let store = windowModel.store
            let runtime = store.webRuntime(for: board)
            store.deleteFocusedDesk()

            windowModel.confirmDeskDeletion()

            #expect(store.webRuntimes[board.id] == nil)
            #expect(runtime.webView.navigationDelegate == nil)
            #expect(runtime.webView.uiDelegate == nil)
        }
    }

    @Test func deletingDeskDiscardsItsPausedBoardState() {
        let removedBoard = BoardState(
            label: "Removed",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/"),
            sheetNavigationPaused: true)
        let populated = desk("Populated", boards: [removedBoard], focusedBoardID: removedBoard.id)
        let empty = desk("Empty")
        let store = DenStore(
            state: DenState(desks: [populated, empty], focusedDeskID: populated.id))
        let composition = DenWindowComposition(store: store)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        store.deleteFocusedDesk()
        windowModel.confirmDeskDeletion()

        #expect(!store.state.desks.flatMap(\.boards).contains { $0.id == removedBoard.id })
    }

    @Test func lastDeskCannotBeDeleted() {
        let onlyDesk = desk("Only")
        withTestWindowModel(desks: [onlyDesk]) { windowModel in
            let store = windowModel.store
            store.deleteFocusedDesk()

            #expect(store.state.desks.count == 1)
            #expect(windowModel.pendingConfirmation == nil)
        }
    }

    @Test func digitDeskMovementFocusesAndMovesToNumberedDesk() {
        let moving = board("Moving")
        let targetBoard = board("Target")
        let source = desk("One", boards: [moving])
        let target = desk("Two", boards: [targetBoard])
        withStore(desks: [source, target]) { store in
            store.moveFocusedBoard(toDeskNumber: 2)

            #expect(store.focusedDesk?.id == target.id)
            #expect(store.state.desks[1].boards.map(\.id) == [targetBoard.id, moving.id])

            store.focusDesk(number: 1)
            #expect(store.focusedDesk?.id == source.id)
        }
    }

    @Test func deskRenaming() {
        let firstBoard = board("Google")
        let desk1 = desk("Main", boards: [firstBoard], focusedBoardID: firstBoard.id)

        withTestWindowModel(desks: [desk1]) { windowModel in
            let store = windowModel.store
            // 1. Enter Den Mode, show rename panel
            windowModel.isDenMode = true
            windowModel.showRenameDeskPanel()
            #expect(windowModel.isRenameDeskPanelPresented)

            // 2. Rename the desk to a custom name
            store.renameFocusedDesk(to: "Web Search")
            #expect(!windowModel.isRenameDeskPanelPresented)
            #expect(store.focusedDesk?.label == "Web Search")

            // 3. Rename with empty name should be ignored (keep old name)
            windowModel.showRenameDeskPanel()
            store.renameFocusedDesk(to: "")
            #expect(!windowModel.isRenameDeskPanelPresented)
            #expect(store.focusedDesk?.label == "Web Search")
        }
    }

    @Test func savesAndRetrievesDeskScrollOffset() {
        let deskA = desk("Desk A")
        let deskB = desk("Desk B")
        withStore(desks: [deskA, deskB]) { store in
            #expect(store.deskScrollOffset(for: deskA.id) == nil)

            store.saveDeskScrollOffset(420.5, for: deskA.id)
            #expect(store.deskScrollOffset(for: deskA.id) == 420.5)
            #expect(store.deskScrollOffset(for: deskB.id) == nil)

            store.saveDeskScrollOffset(120.0, for: deskB.id)
            #expect(store.deskScrollOffset(for: deskA.id) == 420.5)
            #expect(store.deskScrollOffset(for: deskB.id) == 120.0)
        }
    }

    @Test func copyDeskIDCopiesLowercasedUUIDToPasteboardAndShowsFeedback() {
        let deskA = desk("Desk A")
        withStore(desks: [deskA]) { store in
            let pasteboard = NSPasteboard.withUniqueName()
            store.copyDeskID(deskA.id, pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == deskA.id.rawValue.uuidString.lowercased())
            #expect(store.latestFeedback?.message == "Copied Desk ID.")
            #expect(store.latestFeedback?.severity == .success)
        }
    }

    @Test func copyDeskIDIgnoresUnknownDeskID() {
        let deskA = desk("Desk A")
        withStore(desks: [deskA]) { store in
            let pasteboard = NSPasteboard.withUniqueName()
            store.copyDeskID(DeskID(), pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == nil)
            #expect(store.latestFeedback == nil)
        }
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: BoardID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
