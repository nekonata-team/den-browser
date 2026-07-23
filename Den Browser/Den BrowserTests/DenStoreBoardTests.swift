import AppKit
import Foundation
import Testing
@testable import Den_Browser

@MainActor
struct DenStoreBoardTests {

    @Test func openBoardAcceptsWebHostsAndSearchesInvalidURLs() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        store.addBoard(urlString: "localhost:3000")
        let localURL = try #require(store.focusedDesk?.boards.last?.currentSheetURL)
        #expect(localURL.scheme == "https")
        #expect(localURL.host == "localhost")
        #expect(localURL.port == 3000)

        store.addBoard(urlString: "swift: concurrency")
        let searchURL = try #require(
            store.focusedDesk?.boards.last?.currentSheetURL
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(searchURL.host == "www.google.com")
        #expect(searchURL.queryItems == [URLQueryItem(name: "q", value: "swift: concurrency")])

        store.addBoard(urlString: "https://")
        let invalidURLSearch = try #require(
            store.focusedDesk?.boards.last?.currentSheetURL
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(invalidURLSearch.queryItems == [URLQueryItem(name: "q", value: "https://")])
    }

    @Test func editingFocusedBoardLinkReplacesCurrentSheet() throws {
        let board = board("Board", url: "https://before.example/")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        store.showEditBoardLinkPanel()

        #expect(store.navigateFocusedBoard(urlString: "after.example/path"))
        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://after.example/path"))
        #expect(store.temporaryContext == nil)
        #expect(!store.isDenMode)
    }

    @Test func updateBoardKeepsCurrentSheetForUnsupportedURL() throws {
        let board = board("Board", url: "https://before.example/")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            onSave: { savedState = $0 })

        store.updateBoard(
            boardID: board.id,
            url: URL(string: "mailto:user@example.com"),
            title: "Updated title")

        #expect(store.focusedBoard?.currentSheetURL == URL(string: "https://before.example/"))
        #expect(store.focusedBoard?.label == "Updated title")
        #expect(savedState == store.state)
    }

    @Test func boardFocusMovesAndWrapsAtBothEdges() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            store.focusNextBoard()
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)

            store.focusPreviousBoard()
            store.focusPreviousBoard()
            #expect(store.focusedDesk?.focusedBoardID == boards[2].id)

            store.focusNextBoard()
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test func focusingAlreadyFocusedBoardDoesNotSaveAgain() {
        let board = board("Focused")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) { _ in
            saveCount += 1
        }

        store.focusBoard(board.id)

        #expect(saveCount == 0)
    }

    @Test func boardMovementAvailabilityStopsAtDeskEdges() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards)]) { store in
            #expect(!store.canMoveBoard(boards[0].id, by: -1))
            #expect(store.canMoveBoard(boards[0].id, by: 1))
            #expect(store.canMoveBoard(boards[1].id, by: -1))
            #expect(store.canMoveBoard(boards[1].id, by: 1))
            #expect(store.canMoveBoard(boards[2].id, by: -1))
            #expect(!store.canMoveBoard(boards[2].id, by: 1))
        }
    }

    @Test func reorderingBoardKeepsItFocusedAndStopsAtDeskEdge() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.moveFocusedBoardLeft()
            store.moveFocusedBoardLeft()

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(store.centerFocusedBoardRequest == 1)
        }
    }

    @Test func boardDragPersistsOnlyItsFinalOrder() {
        let boards = [board("A"), board("B"), board("C")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        var savedStates: [DenState] = []
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) {
            savedStates.append($0)
        }

        #expect(store.beginBoardDrag(boards[0].id))
        store.previewBoardMove(boards[0].id, to: 2)
        #expect(savedStates.isEmpty)

        store.finishBoardDrag()
        #expect(savedStates.count == 1)
        #expect(savedStates[0].desks[0].boards.map(\.id) == [boards[1].id, boards[2].id, boards[0].id])
    }

    @Test func cancelledBoardDragRestoresAndPersistsOriginalOrder() {
        let boards = [board("A"), board("B"), board("C")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        var persistedState: DenState?
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) {
            persistedState = $0
        }

        #expect(store.beginBoardDrag(boards[0].id))
        store.previewBoardMove(boards[0].id, to: 2)
        store.restoreBoardOrder(boards.map(\.id), in: source.id)
        store.finishBoardDrag()

        #expect(store.focusedDesk?.boards.map(\.id) == boards.map(\.id))
        #expect(persistedState?.desks[0].boards.map(\.id) == boards.map(\.id))
    }

    @Test func movingBoardToDeskPlacesItAfterTargetAndFocusesIt() {
        let moved = board("Moved")
        let targetBoards = [board("Before"), board("Target"), board("After")]
        let source = desk("Source", boards: [moved])
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        withStore(desks: [source, target]) { store in
            store.moveFocusedBoardToNextDesk()

            #expect(store.state.desks[0].boards.isEmpty)
            #expect(store.state.desks[0].focusedBoardID == nil)
            #expect(
                store.state.desks[1].boards.map(\.id) == [
                    targetBoards[0].id, targetBoards[1].id, moved.id, targetBoards[2].id,
                ])
            #expect(store.focusedDesk?.id == target.id)
            #expect(store.focusedDesk?.focusedBoardID == moved.id)
        }
    }

    @Test func removingBoardFocusesPreviousBoard() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.removeFocusedBoard()

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(store.recentlyRemovedBoard?.board.id == boards[1].id)
        }
    }

    @Test func removingFirstBoardFocusesNextBoard() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            store.removeFocusedBoard()

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
        }
    }

    @Test func removingLastBoardFocusesPreviousBoard() {
        let boards = [board("A"), board("B")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.removeFocusedBoard()

            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test func removingUnfocusedBoardKeepsFocus() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.removeBoard(boards[0].id)

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
        }
    }

    @Test func removalReplacesRestoreCandidateAndDoesNotPersistIt() throws {
        let boards = [board("First"), board("Second")]
        let source = desk("Source", boards: boards, focusedBoardID: boards[0].id)
        var persistedState: DenState?
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) {
            persistedState = $0
        }

        store.removeFocusedBoard()
        store.removeFocusedBoard()
        let persisted = try #require(persistedState)

        #expect(store.recentlyRemovedBoard?.board.id == boards[1].id)
        #expect(persisted.desks[0].boards.isEmpty)
        #expect(DenStore(state: persisted).recentlyRemovedBoard == nil)
    }

    @Test func restorationUsesOriginalDeskIndexAndBoardIdentity() {
        let boards = [board("First"), board("Restored", width: 760), board("Last")]
        let source = desk("Source", boards: boards, focusedBoardID: boards[1].id)
        withStore(desks: [source]) { store in
            store.removeFocusedBoard()
            store.restoreRecentlyRemovedBoard()

            #expect(store.focusedDesk?.boards == boards)
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(store.recentlyRemovedBoard == nil)
        }
    }

    @Test func restorationCreatesANewBoardRuntime() throws {
        let removed = board("Removed")
        try withStore(desks: [desk("Desk", boards: [removed])]) { store in
            let originalRuntime = store.runtime(for: removed)

            store.removeFocusedBoard()
            #expect(store.runtimes[removed.id] == nil)

            store.restoreRecentlyRemovedBoard()
            let restoredBoard = try #require(store.focusedDesk?.boards.first)
            let restoredRuntime = store.runtime(for: restoredBoard)
            #expect(restoredRuntime !== originalRuntime)
        }
    }

    @Test func restorationFallsBackRightOfFocusedBoardWhenSourceDeskIsGone() {
        let removed = board("Removed")
        let source = desk("Source", boards: [removed])
        let targetBoards = [board("Before"), board("Focused"), board("After")]
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        withStore(desks: [source, target]) { store in
            store.removeFocusedBoard()
            store.deleteFocusedDesk()
            store.restoreRecentlyRemovedBoard()

            #expect(store.focusedDesk?.id == target.id)
            #expect(
                store.focusedDesk?.boards.map(\.id) == [
                    targetBoards[0].id, targetBoards[1].id, removed.id, targetBoards[2].id,
                ])
            #expect(store.focusedDesk?.focusedBoardID == removed.id)
        }
    }

    @Test func mouseResizeChangesTargetBoardWidthWithinBounds() {
        let boards = [board("First"), board("Second")]
        withStore(desks: [desk("Desk", boards: boards)]) { store in
            store.resizeBoard(boards[1].id, to: 760)
            #expect(store.focusedDesk?.boards.map(\.width) == [520, 760])

            store.resizeBoard(boards[1].id, to: 100)
            #expect(store.focusedDesk?.boards[1].width == 280)

            store.resizeBoard(boards[1].id, to: 2_000)
            #expect(store.focusedDesk?.boards[1].width == 1400)
        }
    }

    @Test func adjustsEveryBoardInFocusedDeskWithinBounds() {
        let boards = [board("Narrow", width: 280), board("Wide", width: 1_400)]
        let otherBoard = board("Other", width: 760)
        let firstDesk = desk("First", boards: boards, focusedBoardID: boards[0].id)
        let secondDesk = desk("Second", boards: [otherBoard])
        withStore(desks: [firstDesk, secondDesk]) { store in
            store.toggleFocusedBoardMaximized()

            store.adjustFocusedDeskBoardWidths(by: -80)
            #expect(store.focusedDesk?.boards.map(\.width) == [280, 1_320])
            #expect(store.state.desks[1].boards.map(\.width) == [760])
            #expect(store.maximizedBoardID == nil)

            store.adjustFocusedDeskBoardWidths(by: 160)
            #expect(store.focusedDesk?.boards.map(\.width) == [440, 1_400])
        }
    }

    @Test func resizesEveryBoardInFocusedDeskToFitCurrentWindow() {
        let firstBoards = [board("First", width: 440), board("Second", width: 760)]
        let otherBoard = board("Other", width: 980)
        let firstDesk = desk("First", boards: firstBoards, focusedBoardID: firstBoards[0].id)
        let secondDesk = desk("Second", boards: [otherBoard])
        withStore(desks: [firstDesk, secondDesk]) { store in
            store.updateBoardLayout(availableWidth: 1_180, spacing: 10)
            store.toggleFocusedBoardMaximized()
            let centerRequest = store.centerFocusedBoardRequest

            #expect(store.resizeFocusedDeskBoards(toFit: 3))
            #expect(
                store.focusedDesk?.boards.allSatisfy {
                    abs($0.width - 386.666_666_666_666_7) < 0.001
                } == true)
            #expect(store.state.desks[1].boards[0].width == 980)
            #expect(store.maximizedBoardID == nil)
            #expect(store.centerFocusedBoardRequest == centerRequest + 1)
        }
    }

    @Test func rejectsBoardFitCountsOutsideCurrentWidth() {
        let boards = [board("First"), board("Second")]
        withStore(desks: [desk("Desk", boards: boards)]) { store in
            store.updateBoardLayout(availableWidth: 1_080, spacing: 10)

            #expect(store.boardWidth(toFit: 3) != nil)
            #expect(store.boardWidth(toFit: 4) == nil)
            #expect(!store.resizeFocusedDeskBoards(toFit: 4))
            #expect(store.focusedDesk?.boards.map(\.width) == [520, 520])
        }
    }

    @Test func oneBoardFitUsesFullWindowBeyondManualResizeLimit() {
        withStore(desks: [desk("Desk", boards: [board("Wide")])]) { store in
            store.updateBoardLayout(availableWidth: 2_480, spacing: 10)

            #expect(store.resizeFocusedDeskBoards(toFit: 1))
            #expect(store.focusedDesk?.boards[0].width == 2_480)
        }
    }

    @Test func reloadingFocusedBoardDoesNotChangeDenState() {
        let current = board("Current", url: "https://example.com/path")
        withStore(desks: [desk("Desk", boards: [current])]) { store in
            let stateBeforeReload = store.state

            store.reloadFocusedBoard()

            #expect(store.state == stateBeforeReload)
        }
    }

    @Test func navigatingAnotherBoardFocusesIt() {
        let first = board("First")
        let second = board("Second")
        withStore(desks: [desk("Desk", boards: [first, second], focusedBoardID: first.id)]) { store in
            store.goBackInBoard(second.id)

            #expect(store.focusedDesk?.focusedBoardID == second.id)
        }
    }
    private func withStore(desks: [DeskState], body: (DenStore) throws -> Void) rethrows {
        let store = DenStore(state: DenState(desks: desks, focusedDeskID: desks[0].id))
        try body(store)
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

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
