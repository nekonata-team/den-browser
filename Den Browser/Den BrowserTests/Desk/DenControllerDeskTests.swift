import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenControllerDeskTests {
    @Test func createsEmptyDeskAfterFocusedDesk() {
        withTestWindowModel(desks: [desk("First"), desk("Second")]) { windowModel, controller in
            windowModel.isDenMode = true
            controller.createDesk(label: "  Writing  ", preset: .empty)

            #expect(controller.state.desks.map(\.label) == ["First", "Writing", "Second"])
            #expect(controller.focusedDesk?.label == "Writing")
            #expect(controller.focusedDesk?.boards.isEmpty == true)
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func creatingDeskCompletesTutorialDeskStep() {
        // Arrange
        let sourceDesk = desk("First")
        let controller = DenController(state: DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))
        #expect(controller.openTutorialBoard())
        #expect(controller.openBoard(input: "https://one.example/"))
        #expect(controller.focusedDesk?.boards.count == 2)
        controller.focusNextBoard()

        // Act
        controller.createDesk(label: "Writing", preset: .empty)

        // Assert
        #expect(controller.focusedDesk?.label == "Writing")
        #expect(
            controller.state.desks.flatMap(\.boards).first(where: \.isTutorial)?.tutorialCompletedSteps?.isSuperset(
                of: [.openBoard, .navigateBoards, .createDesk]) == true)
    }

    @Test func createsChatGPTPresetWithThreeBoards() {
        withController(desks: [desk("First")]) { controller in
            controller.createDesk(label: "AI", preset: .chatGPT)

            #expect(controller.focusedDesk?.boards.count == 3)
            #expect(
                controller.focusedDesk?.boards.allSatisfy {
                    $0.currentSheetURL == URL(string: "https://chatgpt.com/")
                } == true)
            #expect(controller.focusedDesk?.boards.allSatisfy { $0.width == 520 } == true)
            #expect(controller.focusedDesk?.focusedBoardID == controller.focusedDesk?.boards.first?.id)
        }
    }

    @Test func createsGeminiPresetWithThreeBoards() {
        withController(desks: [desk("First")]) { controller in
            controller.createDesk(label: "Gemini", preset: .gemini)

            #expect(controller.focusedDesk?.boards.count == 3)
            #expect(
                controller.focusedDesk?.boards.allSatisfy {
                    $0.currentSheetURL == URL(string: "https://gemini.google.com/") && $0.width == 520
                } == true)
        }
    }

    @Test func deskCreationStopsAtTenDesks() {
        let desks = (1...DenController.maximumDeskCount).map { desk("Desk \($0)") }
        withController(desks: desks) { controller in
            controller.createDesk(label: "Overflow", preset: .empty)

            #expect(controller.state.desks.count == DenController.maximumDeskCount)
            #expect(!controller.canCreateDesk)
        }
    }

    @Test func replacingPopulatedDeskRequiresConfirmationAndReleasesItsBoards() throws {
        let oldBoards = [board("First"), board("Second")]
        let replacing = desk("Research", boards: oldBoards, focusedBoardID: oldBoards[1].id)
        let other = desk("Other")
        var savedState: DenState?
        let controller = DenController(
            state: DenState(desks: [replacing, other], focusedDeskID: replacing.id),
            onSave: { savedState = $0 })
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let runtime = controller.webRuntime(for: oldBoards[0])
        let restorationCandidate = RecentlyRemovedBoard(
            board: board("Removed"),
            sourceDeskID: other.id,
            sourceBoardIndex: BoardIndex(rawValue: 0))
        controller.storage.recentlyRemovedBoards = [restorationCandidate]
        windowModel.toggleFocusedBoardMaximized()
        windowModel.showReplaceDeskPanel()

        let result = controller.replaceFocusedDesk(label: "  Morning  ", preset: .chatGPT)

        #expect(result == .confirmationPending)
        #expect(controller.focusedDesk == replacing)
        if case let .replaceDesk(replacement)? = windowModel.pendingConfirmation {
            #expect(replacement.presetLabel == BuiltInDeskPreset.chatGPT.label)
        } else {
            Issue.record("Expected a desk replacement confirmation")
        }
        #expect(windowModel.isReplaceDeskPanelPresented)
        #expect(savedState == nil)

        windowModel.confirmDeskReplacement()

        let replaced = try #require(controller.focusedDesk)
        #expect(replaced.id == replacing.id)
        #expect(controller.state.desks.map(\.id) == [replacing.id, other.id])
        #expect(replaced.label == "Morning")
        #expect(replaced.boards.count == 3)
        #expect(replaced.boards.allSatisfy { $0.currentSheetURL == URL(string: "https://chatgpt.com/") })
        #expect(Set(replaced.boards.map(\.id)).isDisjoint(with: oldBoards.map(\.id)))
        #expect(replaced.focusedBoardID == replaced.boards.first?.id)
        #expect(controller.webRuntimes[oldBoards[0].id] == nil)
        #expect(runtime.webView.navigationDelegate == nil)
        #expect(runtime.webView.uiDelegate == nil)
        #expect(windowModel.maximizedBoardID == nil)
        #expect(controller.recentlyRemovedBoards.first?.board.id == restorationCandidate.board.id)
        #expect(!windowModel.isReplaceDeskPanelPresented)
        #expect(!windowModel.isDenMode)
        #expect(savedState == controller.state)
    }

    @Test func replacingDeskDiscardsPausedStateWithItsBoards() {
        let oldBoard = BoardState(
            label: "Old",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/"),
            sheetNavigationPaused: true)
        let replacing = desk("Research", boards: [oldBoard], focusedBoardID: oldBoard.id)
        let other = desk("Other")
        let controller = DenController(
            state: DenState(desks: [replacing, other], focusedDeskID: replacing.id))

        let composition = DenWindowComposition(controller: controller)

        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        _ = controller.replaceFocusedDesk(label: "Morning", preset: .chatGPT)
        windowModel.confirmDeskReplacement()

        #expect(!controller.state.desks.flatMap(\.boards).contains { $0.id == oldBoard.id })
    }

    @Test func replacingDeskInvalidatesReferencesToRemovedBoards() {
        // Arrange
        let oldBoards = [board("First"), board("Second")]
        var replacing = desk("Research", boards: oldBoards, focusedBoardID: oldBoards[1].id)
        replacing.anchorBoardID = oldBoards[0].id
        let controller = DenController(state: DenState(desks: [replacing], focusedDeskID: replacing.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        controller.anchorJumpOriginBoardIDByDesk[replacing.id] = oldBoards[1].id
        _ = controller.prepareBoardLinkFocus(oldBoards[1].id)
        windowModel.overview.selectBoard(oldBoards[1].id)
        windowModel.showReplaceDeskPanel()
        windowModel.openBoard.afterBoardID = oldBoards[0].id
        _ = controller.replaceFocusedDesk(label: "Morning", preset: .chatGPT)

        // Act
        windowModel.confirmDeskReplacement()

        // Assert
        #expect(controller.focusedDesk?.anchorBoardID == nil)
        #expect(controller.anchorJumpOriginBoardIDByDesk[replacing.id] == nil)
        #expect(windowModel.openBoard.afterBoardID == nil)
        #expect(windowModel.pendingBoardLinkFocus == nil)
        #expect(windowModel.overview.selectionDeskID == nil)
        #expect(windowModel.overview.selectionBoardID == nil)
    }

    @Test func cancellingDeskReplacementKeepsDeskAndPanel() {
        let existing = board("Existing")
        let original = desk("Original", boards: [existing])
        withTestWindowModel(desks: [original]) { windowModel, controller in
            windowModel.showReplaceDeskPanel()
            #expect(controller.replaceFocusedDesk(label: "AI", preset: .gemini) == .confirmationPending)

            windowModel.cancelConfirmation()

            #expect(controller.focusedDesk == original)
            #expect(windowModel.pendingConfirmation == nil)
            #expect(windowModel.isReplaceDeskPanelPresented)
        }
    }

    @Test func replacingEmptyDeskAppliesImmediatelyAndEmptyPresetIsUnavailable() {
        let empty = desk("Empty")
        withTestWindowModel(desks: [empty]) { windowModel, controller in
            windowModel.showReplaceDeskPanel()

            #expect(controller.replaceFocusedDesk(label: "Still Empty", preset: .empty) == .unavailable)
            #expect(controller.focusedDesk == empty)
            #expect(controller.replaceFocusedDesk(label: "Gemini", preset: .gemini) == .applied)

            #expect(controller.focusedDesk?.id == empty.id)
            #expect(controller.focusedDesk?.label == "Gemini")
            #expect(controller.focusedDesk?.boards.count == 3)
            #expect(!windowModel.isReplaceDeskPanelPresented)
        }
    }

    @Test func deletingEmptyDeskFocusesPreviousDeskWhenAvailable() {
        let first = desk("First")
        let empty = desk("Empty")
        let third = desk("Third")
        withTestWindowModel(desks: [first, empty, third]) { windowModel, controller in
            controller.focusDesk(empty.id)
            windowModel.isDenMode = true
            controller.deleteFocusedDesk()

            #expect(controller.state.desks.map(\.id) == [first.id, third.id])
            #expect(controller.focusedDesk?.id == first.id)
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func deletingFirstDeskFocusesNextDeskWhenPreviousDeskIsUnavailable() {
        let first = desk("First")
        let second = desk("Second")
        withController(desks: [first, second]) { controller in
            controller.deleteFocusedDesk()

            #expect(controller.state.desks.map(\.id) == [second.id])
            #expect(controller.focusedDesk?.id == second.id)
        }
    }

    @Test func confirmingDeletionOfUnfocusedDeskClearsPreviousFocusedDeskID() {
        let first = desk("First")
        let secondBoard = board("SecondBoard")
        let second = desk("Second", boards: [secondBoard])
        let third = desk("Third")
        withTestWindowModel(desks: [first, second, third]) { windowModel, controller in
            controller.focusDesk(second.id)
            controller.deleteFocusedDesk()
            if case let .deleteDesk(pending)? = windowModel.pendingConfirmation {
                #expect(pending.id == second.id)
            } else {
                Issue.record("Expected a desk deletion confirmation")
            }

            // Switch to third desk, then confirm deletion of second desk
            controller.focusDesk(third.id)
            #expect(controller.previousFocusedDeskID == second.id)

            windowModel.confirmDeskDeletion()
            #expect(controller.state.desks.map(\.id) == [first.id, third.id])
            #expect(controller.previousFocusedDeskID == nil)
        }
    }

    @Test func returnToPreviousDeskTogglesBetweenMostRecentDesks() {
        let first = desk("First")
        let second = desk("Second")
        let third = desk("Third")
        let controller = DenController(
            state: DenState(desks: [first, second, third], focusedDeskID: first.id))

        controller.focusDesk(second.id)
        controller.focusDesk(third.id)
        controller.returnToPreviousDesk()
        #expect(controller.focusedDesk?.id == second.id)

        controller.returnToPreviousDesk()
        #expect(controller.focusedDesk?.id == third.id)
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

        let normalized = DenController.normalizedPersistedState(rawState)
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
        let controller = DenController(state: DenState(desks: [first, second], focusedDeskID: first.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.isDenMode = true
        controller.focusDesk(number: 2)
        #expect(controller.focusedDesk?.id == second.id)
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
        let controller = DenController(
            state: DenState(desks: [first, second, third], focusedDeskID: first.id),
            onSave: { savedState = $0 })

        #expect(controller.beginDeskDrag(second.id))
        controller.previewDeskMove(second.id, to: DeskIndex(rawValue: 2))
        controller.updateBoard(
            boardID: secondBoard.id,
            url: URL(string: "https://updated.example/"),
            title: "Updated title")

        #expect(savedState == nil)

        controller.finishDeskDrag()

        #expect(controller.state.desks.map(\.id) == [first.id, third.id, second.id])
        #expect(controller.focusedDesk?.id == first.id)
        #expect(controller.state.desks[2].boards.map(\.id) == [secondBoard.id])
        #expect(controller.state.desks[2].focusedBoardID == secondBoard.id)
        #expect(controller.state.desks[2].boards[0].currentSheetURL == URL(string: "https://updated.example/"))
        #expect(controller.state.desks[2].boards[0].label == "Updated title")
        #expect(savedState == controller.state)

        controller.previewDeskMove(second.id, to: DeskIndex(rawValue: 2))
        #expect(controller.state.desks.map(\.id) == [first.id, third.id, second.id])
    }

    @Test func movingDeskByAccessibilityActionReordersOneStepAndPreservesFocus() {
        let first = desk("First")
        let second = desk("Second")
        let third = desk("Third")
        let controller = DenController(
            state: DenState(desks: [first, second, third], focusedDeskID: second.id))

        controller.moveDesk(first.id, by: 1)

        #expect(controller.state.desks.map(\.id) == [second.id, first.id, third.id])
        #expect(controller.focusedDesk?.id == second.id)

        controller.moveDesk(third.id, by: 1)
        #expect(controller.state.desks.map(\.id) == [second.id, first.id, third.id])

        #expect(controller.beginDeskDrag(first.id))
        controller.moveDesk(third.id, by: -1)
        #expect(controller.state.desks.map(\.id) == [second.id, first.id, third.id])
        controller.finishDeskDrag()
    }

    @Test func cancellingDeskDragPersistsRestoredOrderAfterBoardUpdate() {
        let firstBoard = board("First Board")
        let secondBoard = board("Second Board")
        let first = desk("First", boards: [firstBoard], focusedBoardID: firstBoard.id)
        let second = desk("Second", boards: [secondBoard], focusedBoardID: secondBoard.id)
        let third = desk("Third")
        var savedState: DenState?
        let controller = DenController(
            state: DenState(desks: [first, second, third], focusedDeskID: first.id),
            onSave: { savedState = $0 })

        #expect(controller.beginDeskDrag(second.id))
        controller.previewDeskMove(second.id, to: DeskIndex(rawValue: 2))
        controller.updateBoard(
            boardID: secondBoard.id,
            url: URL(string: "https://updated.example/"),
            title: "Updated title")
        #expect(savedState == nil)

        controller.restoreDeskOrder([first.id, second.id, third.id])
        controller.finishDeskDrag()

        #expect(controller.state.desks.map(\.id) == [first.id, second.id, third.id])
        #expect(controller.state.desks[1].boards[0].currentSheetURL == URL(string: "https://updated.example/"))
        #expect(controller.state.desks[1].boards[0].label == "Updated title")
        #expect(savedState == controller.state)
    }

    @Test func deletingDeskWithBoardsRequiresConfirmation() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        withTestWindowModel(desks: [populated, empty]) { windowModel, controller in
            controller.deleteFocusedDesk()

            #expect(controller.state.desks.count == 2)
            if case let .deleteDesk(pending)? = windowModel.pendingConfirmation {
                #expect(pending.id == populated.id)
            } else {
                Issue.record("Expected a desk deletion confirmation")
            }

            controller.focusDesk(empty.id)
            windowModel.confirmDeskDeletion()
            #expect(controller.state.desks.map(\.id) == [empty.id])
            #expect(controller.focusedDesk?.id == empty.id)
            #expect(windowModel.pendingConfirmation == nil)
        }
    }

    @Test func confirmingDeskDeletionExitsDenModeAfterSuccessfulDeletion() {
        let populated = desk("Populated", boards: [board("Board")])
        let empty = desk("Empty")
        withTestWindowModel(desks: [populated, empty]) { windowModel, controller in
            windowModel.isDenMode = true
            controller.deleteFocusedDesk()

            #expect(windowModel.isDenMode)
            windowModel.confirmDeskDeletion()

            #expect(!windowModel.isDenMode)
        }
    }

    @Test func cancellingDeskDeletionKeepsBoards() {
        let populated = desk("Populated", boards: [board("Board")])
        let empty = desk("Empty")
        withTestWindowModel(desks: [populated, empty]) { windowModel, controller in
            controller.deleteFocusedDesk()
            windowModel.cancelConfirmation()

            #expect(controller.state.desks.map(\.id) == [populated.id, empty.id])
            #expect(windowModel.pendingConfirmation == nil)
        }
    }

    @Test func deletingDeskDisposesItsBoardRuntimes() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        withTestWindowModel(desks: [populated, empty]) { windowModel, controller in
            let runtime = controller.webRuntime(for: board)
            controller.deleteFocusedDesk()

            windowModel.confirmDeskDeletion()

            #expect(controller.webRuntimes[board.id] == nil)
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
        let controller = DenController(
            state: DenState(desks: [populated, empty], focusedDeskID: populated.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        controller.deleteFocusedDesk()
        windowModel.confirmDeskDeletion()

        #expect(!controller.state.desks.flatMap(\.boards).contains { $0.id == removedBoard.id })
    }

    @Test func lastDeskCannotBeDeleted() {
        let onlyDesk = desk("Only")
        withTestWindowModel(desks: [onlyDesk]) { windowModel, controller in
            controller.deleteFocusedDesk()

            #expect(controller.state.desks.count == 1)
            #expect(windowModel.pendingConfirmation == nil)
        }
    }

    @Test func digitDeskMovementFocusesAndMovesToNumberedDesk() {
        let moving = board("Moving")
        let targetBoard = board("Target")
        let source = desk("One", boards: [moving])
        let target = desk("Two", boards: [targetBoard])
        withController(desks: [source, target]) { controller in
            controller.moveFocusedBoard(toDeskNumber: 2)

            #expect(controller.focusedDesk?.id == target.id)
            #expect(controller.state.desks[1].boards.map(\.id) == [targetBoard.id, moving.id])

            controller.focusDesk(number: 1)
            #expect(controller.focusedDesk?.id == source.id)
        }
    }

    @Test func deskRenaming() {
        let firstBoard = board("Google")
        let desk1 = desk("Main", boards: [firstBoard], focusedBoardID: firstBoard.id)

        withTestWindowModel(desks: [desk1]) { windowModel, controller in
            // 1. Enter Den Mode, show rename panel
            windowModel.isDenMode = true
            windowModel.showRenameDeskPanel()
            #expect(windowModel.isRenameDeskPanelPresented)

            // 2. Rename the desk to a custom name
            controller.renameFocusedDesk(to: "Web Search")
            #expect(!windowModel.isRenameDeskPanelPresented)
            #expect(controller.focusedDesk?.label == "Web Search")

            // 3. Rename with empty name should be ignored (keep old name)
            windowModel.showRenameDeskPanel()
            controller.renameFocusedDesk(to: "")
            #expect(!windowModel.isRenameDeskPanelPresented)
            #expect(controller.focusedDesk?.label == "Web Search")
        }
    }

    @Test func savesAndRetrievesDeskScrollOffset() {
        let deskA = desk("Desk A")
        let deskB = desk("Desk B")
        withController(desks: [deskA, deskB]) { controller in
            #expect(controller.deskScrollOffset(for: deskA.id) == nil)

            controller.saveDeskScrollOffset(420.5, for: deskA.id)
            #expect(controller.deskScrollOffset(for: deskA.id) == 420.5)
            #expect(controller.deskScrollOffset(for: deskB.id) == nil)

            controller.saveDeskScrollOffset(120.0, for: deskB.id)
            #expect(controller.deskScrollOffset(for: deskA.id) == 420.5)
            #expect(controller.deskScrollOffset(for: deskB.id) == 120.0)
        }
    }

    @Test func copyDeskIDCopiesLowercasedUUIDToPasteboardAndShowsFeedback() {
        let deskA = desk("Desk A")
        withController(desks: [deskA]) { controller in
            let pasteboard = NSPasteboard.withUniqueName()
            controller.copyDeskID(deskA.id, pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == deskA.id.rawValue.uuidString.lowercased())
            #expect(controller.latestFeedback?.message == "Copied Desk ID.")
            #expect(controller.latestFeedback?.severity == .success)
        }
    }

    @Test func copyDeskIDIgnoresUnknownDeskID() {
        let deskA = desk("Desk A")
        withController(desks: [deskA]) { controller in
            let pasteboard = NSPasteboard.withUniqueName()
            controller.copyDeskID(DeskID(), pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == nil)
            #expect(controller.latestFeedback == nil)
        }
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: BoardID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
