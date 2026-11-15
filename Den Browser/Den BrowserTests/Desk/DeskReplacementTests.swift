import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DeskReplacementTests {
    @Test func backgroundDeskDeletionPreservesDenMode() {
        // Arrange
        let first = makeTestDesk("First")
        let second = makeTestDesk("Second")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, second]))
            )
        ) { session, model in
            model.isDenMode = true

            // Act
            session.desks.confirmDeskDeletion(second.id)

            // Assert
            #expect(session.resources.state.desks.map(\.id) == [first.id])
            #expect(session.navigation.presentedDeskID == first.id)
            #expect(model.isDenMode)
        }
    }

    @Test func replacingPopulatedDeskRequiresConfirmationAndReleasesItsBoards() throws {
        let oldBoards = [makeTestBoard("First"), makeTestBoard("Second")]
        let replacing = makeTestDesk("Research", boards: oldBoards, focusedBoardID: oldBoards[1].id)
        let other = makeTestDesk("Other")
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [replacing, other], focusedDeskID: replacing.id)
                ),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let runtime = session.runtimes.webRuntime(for: oldBoards[0])
        let restorationCandidate = RecentlyRemovedBoard(
            board: makeTestBoard("Removed"),
            sourceDeskID: other.id,
            sourceBoardIndex: BoardIndex(rawValue: 0)
        )
        session.resources.recentlyRemovedBoards = [restorationCandidate]
        windowModel.toggleFocusedBoardMaximized()
        windowModel.showReplaceDeskPanel()

        let result = session.desks.replaceFocusedDesk(label: "  Morning  ", preset: .chatGPT)

        #expect(result == .confirmationPending)
        #expect(session.navigation.focusedDesk == replacing)
        if case let .replaceDesk(replacement)? = windowModel.pendingConfirmation {
            #expect(replacement.presetLabel == BuiltInDeskPreset.chatGPT.label)
        } else {
            Issue.record("Expected a desk replacement confirmation")
        }
        #expect(windowModel.isReplaceDeskPanelPresented)
        #expect(savedState == nil)

        windowModel.confirmDeskReplacement()

        let replaced = try #require(session.navigation.focusedDesk)
        #expect(replaced.id == replacing.id)
        #expect(session.resources.state.desks.map(\.id) == [replacing.id, other.id])
        #expect(replaced.label == "Morning")
        #expect(replaced.boards.count == 3)
        #expect(replaced.boards.allSatisfy { $0.currentSheetURL == URL(string: "https://chatgpt.com/") })
        #expect(Set(replaced.boards.map(\.id)).isDisjoint(with: oldBoards.map(\.id)))
        #expect(replaced.focusedBoardID == replaced.boards.first?.id)
        #expect(session.resources.webRuntimes[oldBoards[0].id] == nil)
        #expect(runtime.webView.navigationDelegate == nil)
        #expect(runtime.webView.uiDelegate == nil)
        #expect(windowModel.maximizedBoardID == nil)
        #expect(session.resources.recentlyRemovedBoards.first?.board.id == restorationCandidate.board.id)
        #expect(!windowModel.isReplaceDeskPanelPresented)
        #expect(!windowModel.isDenMode)
        #expect(savedState == session.resources.state)
    }

    @Test func replacingDeskInvalidatesReferencesToRemovedBoards() {
        // Arrange
        let oldBoards = [makeTestBoard("First"), makeTestBoard("Second")]
        var replacing = makeTestDesk("Research", boards: oldBoards, focusedBoardID: oldBoards[1].id)
        replacing.anchorBoardID = oldBoards[0].id
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [replacing], focusedDeskID: replacing.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.navigation.anchorJumpOriginBoardIDByDesk[replacing.id] = oldBoards[1].id
        _ = session.boardNavigation.prepareBoardLinkFocus(oldBoards[1].id)
        windowModel.overview.selectBoard(oldBoards[1].id)
        windowModel.showReplaceDeskPanel()
        windowModel.openBoard.afterBoardID = oldBoards[0].id
        _ = session.desks.replaceFocusedDesk(label: "Morning", preset: .chatGPT)

        // Act
        windowModel.confirmDeskReplacement()

        // Assert
        #expect(session.navigation.focusedDesk?.anchorBoardID == nil)
        #expect(session.navigation.anchorJumpOriginBoardIDByDesk[replacing.id] == nil)
        #expect(windowModel.openBoard.afterBoardID == nil)
        #expect(windowModel.pendingBoardLinkFocus == nil)
        #expect(windowModel.overview.selectionDeskID == nil)
        #expect(windowModel.overview.selectionBoardID == nil)
    }

    @Test func cancellingDeskReplacementKeepsDeskAndPanel() {
        let existing = makeTestBoard("Existing")
        let original = makeTestDesk("Original", boards: [existing])
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [original]))
            )
        ) { session, windowModel in
            windowModel.showReplaceDeskPanel()
            #expect(session.desks.replaceFocusedDesk(label: "AI", preset: .gemini) == .confirmationPending)

            windowModel.cancelConfirmation()

            #expect(session.navigation.focusedDesk == original)
            #expect(windowModel.pendingConfirmation == nil)
            #expect(windowModel.isReplaceDeskPanelPresented)
        }
    }

    @Test func deletingEmptyDeskFocusesPreviousDeskWhenAvailable() {
        let first = makeTestDesk("First")
        let empty = makeTestDesk("Empty")
        let third = makeTestDesk("Third")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, empty, third]))
            )
        ) { session, windowModel in
            session.boardNavigation.focusDesk(empty.id)
            windowModel.isDenMode = true
            let initialSuppression = windowModel.boardMutationAnimationSuppressionRequest
            session.desks.deleteFocusedDesk()

            #expect(session.resources.state.desks.map(\.id) == [first.id, third.id])
            #expect(session.navigation.focusedDesk?.id == first.id)
            #expect(!windowModel.isDenMode)
            #expect(windowModel.boardMutationAnimationSuppressionRequest == initialSuppression + 1)
        }
    }

    @Test func deletingFirstDeskFocusesNextDeskWhenPreviousDeskIsUnavailable() {
        let first = makeTestDesk("First")
        let second = makeTestDesk("Second")
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, second]))
            )
        ) { session in
            session.desks.deleteFocusedDesk()

            #expect(session.resources.state.desks.map(\.id) == [second.id])
            #expect(session.navigation.focusedDesk?.id == second.id)
        }
    }

    @Test func confirmingDeletionOfUnfocusedDeskClearsPreviousFocusedDeskID() {
        let first = makeTestDesk("First")
        let secondBoard = makeTestBoard("SecondBoard")
        let second = makeTestDesk("Second", boards: [secondBoard])
        let third = makeTestDesk("Third")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, second, third]))
            )
        ) { session, windowModel in
            session.boardNavigation.focusDesk(second.id)
            session.desks.deleteFocusedDesk()
            if case let .deleteDesk(pending)? = windowModel.pendingConfirmation {
                #expect(pending.id == second.id)
            } else {
                Issue.record("Expected a desk deletion confirmation")
            }

            // Switch to third desk, then confirm deletion of second desk
            session.boardNavigation.focusDesk(third.id)
            #expect(session.navigation.previousFocusedDeskID == second.id)

            let initialSuppression = windowModel.boardMutationAnimationSuppressionRequest
            windowModel.confirmDeskDeletion()
            #expect(session.resources.state.desks.map(\.id) == [first.id, third.id])
            #expect(session.navigation.previousFocusedDeskID == nil)
            #expect(windowModel.boardMutationAnimationSuppressionRequest == initialSuppression + 1)
        }
    }

    @Test func cancellingDeskDragPersistsRestoredOrderAfterBoardUpdate() {
        let firstBoard = makeTestBoard("First Board")
        let secondBoard = makeTestBoard("Second Board")
        let first = makeTestDesk("First", boards: [firstBoard], focusedBoardID: firstBoard.id)
        let second = makeTestDesk("Second", boards: [secondBoard], focusedBoardID: secondBoard.id)
        let third = makeTestDesk("Third")
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [first, second, third], focusedDeskID: first.id)
                ),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        #expect(session.resources.deskMovement.beginDrag(second.id))
        session.resources.deskMovement.preview(second.id, to: DeskIndex(rawValue: 2))
        session.runtimes.updateBoard(
            boardID: secondBoard.id,
            url: URL(string: "https://updated.example/"),
            title: "Updated title"
        )
        #expect(savedState == nil)

        session.resources.deskMovement.restoreOrder([first.id, second.id, third.id])
        session.resources.deskMovement.finishDrag()

        #expect(session.resources.state.desks.map(\.id) == [first.id, second.id, third.id])
        #expect(
            session.resources.state.desks[1].boards[0].currentSheetURL == URL(string: "https://updated.example/")
        )
        #expect(session.resources.state.desks[1].boards[0].label == "Updated title")
        #expect(savedState == session.resources.state)
    }

    @Test func deletingDeskWithBoardsRequiresConfirmation() {
        let board = makeTestBoard("Board")
        let populated = makeTestDesk("Populated", boards: [board])
        let empty = makeTestDesk("Empty")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [populated, empty]))
            )
        ) { session, windowModel in
            let runtime = session.runtimes.webRuntime(for: board)
            session.desks.deleteFocusedDesk()

            #expect(session.resources.state.desks.count == 2)
            if case let .deleteDesk(pending)? = windowModel.pendingConfirmation {
                #expect(pending.id == populated.id)
            } else {
                Issue.record("Expected a desk deletion confirmation")
            }

            session.boardNavigation.focusDesk(empty.id)
            windowModel.confirmDeskDeletion()
            #expect(session.resources.state.desks.map(\.id) == [empty.id])
            #expect(session.navigation.focusedDesk?.id == empty.id)
            #expect(windowModel.pendingConfirmation == nil)
            #expect(session.resources.webRuntimes[board.id] == nil)
            #expect(runtime.webView.navigationDelegate == nil)
            #expect(runtime.webView.uiDelegate == nil)
        }
    }

    @Test func confirmingDeskDeletionExitsDenModeAfterSuccessfulDeletion() {
        let populated = makeTestDesk("Populated", boards: [makeTestBoard("Board")])
        let empty = makeTestDesk("Empty")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [populated, empty]))
            )
        ) { session, windowModel in
            windowModel.isDenMode = true
            session.desks.deleteFocusedDesk()

            #expect(windowModel.isDenMode)
            windowModel.confirmDeskDeletion()

            #expect(!windowModel.isDenMode)
        }
    }

    @Test func cancellingDeskDeletionKeepsBoards() {
        let populated = makeTestDesk("Populated", boards: [makeTestBoard("Board")])
        let empty = makeTestDesk("Empty")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [populated, empty]))
            )
        ) { session, windowModel in
            session.desks.deleteFocusedDesk()
            windowModel.cancelConfirmation()

            #expect(session.resources.state.desks.map(\.id) == [populated.id, empty.id])
            #expect(windowModel.pendingConfirmation == nil)
        }
    }

    @Test func lastDeskCannotBeDeleted() {
        let onlyDesk = makeTestDesk("Only")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [onlyDesk]))
            )
        ) { session, windowModel in
            session.desks.deleteFocusedDesk()

            #expect(session.resources.state.desks.count == 1)
            #expect(windowModel.pendingConfirmation == nil)
        }
    }
}
