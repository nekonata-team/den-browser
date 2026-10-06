import AppKit
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct OverviewViewModelTests {

    @Test func denCommandsAreSuspendedByOverview() throws {
        // Arrange
        let first = board("First")
        let second = board("Second")
        try withTestViewModel(desks: [desk("Desk", boards: [first, second], focusedBoardID: first.id)]) { viewModel in
            let store = viewModel.store
            viewModel.showOverview()
            let openBoard = try #require(keyEvent("t", keyCode: 17))
            let editLink = try #require(keyEvent("l", keyCode: 37))
            let removeBoard = try #require(keyEvent("w", keyCode: 13))

            // Act
            let openHandled = KeyboardController.handle(openBoard, store: store, viewModel: viewModel)
            let editHandled = KeyboardController.handle(editLink, store: store, viewModel: viewModel)
            let removeHandled = KeyboardController.handle(removeBoard, store: store, viewModel: viewModel)

            // Assert
            #expect(openHandled)
            #expect(editHandled)
            #expect(removeHandled)
            #expect(viewModel.isOverviewPresented)
            #expect(!viewModel.isOpenBoardPanelPresented)
            #expect(!viewModel.isEditBoardLinkPanelPresented)
            #expect(store.focusedDesk?.boards.map(\.id) == [first.id, second.id])
        }
    }

    @Test func temporaryContextsAreExclusiveAndClearOverviewSelection() {
        // Arrange
        let board = board("Board")
        withTestViewModel(desks: [desk("Desk", boards: [board], focusedBoardID: board.id)]) { viewModel in
            viewModel.showOverview()
            #expect(viewModel.temporaryContext == .overview)
            #expect(viewModel.overview.selectionBoardID == board.id)

            // Act
            viewModel.showOpenBoardPanel()

            // Assert
            #expect(viewModel.temporaryContext == .openBoard)
            #expect(viewModel.overview.selectionDeskID == nil)
            #expect(viewModel.overview.selectionBoardID == nil)
            #expect(!viewModel.isOverviewPresented)
        }
    }

    @Test func overviewInitializesWithFirstBoardSelected() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)

        // Act
        withTestViewModel(desks: [desk1]) { viewModel in
            viewModel.showOverview()

            // Assert
            #expect(viewModel.overview.query == "")
            #expect(viewModel.overview.filterPhase == .inactive)
            #expect(viewModel.overview.selectionDeskID == desk1.id)
            #expect(viewModel.overview.selectionBoardID == googleBoard.id)
        }
    }

    @Test func overviewQuerySelectsFirstMatchingBoard() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let githubBoard = board("GitHub", url: "https://github.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)
        let desk2 = desk("Dev", boards: [githubBoard], focusedBoardID: githubBoard.id)

        withTestViewModel(desks: [desk1, desk2]) { viewModel in
            viewModel.showOverview()

            // Act
            viewModel.overview.setQuery("git")

            // Assert
            #expect(viewModel.overview.query == "git")
            #expect(viewModel.overview.selectionDeskID == desk2.id)
            #expect(viewModel.overview.selectionBoardID == githubBoard.id)
        }
    }

    @Test func overviewFilterMatchesCorrectBoards() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let githubBoard = board("GitHub", url: "https://github.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)
        let desk2 = desk("Dev", boards: [githubBoard], focusedBoardID: githubBoard.id)

        withTestViewModel(desks: [desk1, desk2]) { viewModel in
            viewModel.showOverview()

            // Act
            viewModel.overview.setQuery("oog")

            // Assert
            #expect(viewModel.overview.selectionDeskID == desk1.id)
            #expect(viewModel.overview.selectionBoardID == googleBoard.id)
            #expect(viewModel.overview.matchesFilter(googleBoard, in: desk1))
            #expect(!viewModel.overview.matchesFilter(githubBoard, in: desk2))
        }
    }

    @Test func overviewNonMatchingQueryClearsSelection() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)

        withTestViewModel(desks: [desk1]) { viewModel in
            viewModel.showOverview()

            // Act
            viewModel.overview.setQuery("nonexistent")

            // Assert
            #expect(viewModel.overview.selectionDeskID == nil)
            #expect(viewModel.overview.selectionBoardID == nil)
        }
    }

    @Test func overviewFilterModeConfirmsQueryAndEntersSelectingPhase() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)

        withTestViewModel(desks: [desk1]) { viewModel in
            viewModel.showOverview()

            // Act
            viewModel.overview.enterFilterMode()
            #expect(viewModel.overview.filterPhase == .filtering)
            viewModel.overview.setQuery("goog")
            viewModel.overview.confirmFilterQuery()

            // Assert
            #expect(viewModel.overview.filterPhase == .selecting)
            #expect(viewModel.overview.query == "goog")
        }
    }

    @Test func overviewClearQueryRestoresDefaultSelection() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let githubBoard = board("GitHub", url: "https://github.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)
        let desk2 = desk("Dev", boards: [githubBoard], focusedBoardID: githubBoard.id)

        withTestViewModel(desks: [desk1, desk2]) { viewModel in
            viewModel.showOverview()
            viewModel.overview.setQuery("git")

            // Act
            viewModel.overview.clearQuery()

            // Assert
            #expect(viewModel.overview.query == "")
            #expect(viewModel.overview.filterPhase == .inactive)
            #expect(viewModel.overview.selectionDeskID == desk2.id)
            #expect(viewModel.overview.selectionBoardID == githubBoard.id)
        }
    }

    @Test func overviewExitFilterModeClearsQueryAndPhase() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)

        withTestViewModel(desks: [desk1]) { viewModel in
            viewModel.showOverview()
            viewModel.overview.enterFilterMode()
            viewModel.overview.setQuery("goog")

            // Act
            viewModel.overview.exitFilterMode()

            // Assert
            #expect(viewModel.overview.filterPhase == .inactive)
            #expect(viewModel.overview.query == "")
        }
    }

    @Test func overviewBoardDragMovesAcrossDesksOnlyOnCommit() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let third = board("Third")
        let main = desk("Main", boards: [first, second], focusedBoardID: first.id)
        let other = desk("Other", boards: [third], focusedBoardID: third.id)
        var saveCount = 0
        let store = DenStore(
            state: DenState(desks: [main, other], focusedDeskID: main.id),
            onSave: { _ in saveCount += 1 })
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()

        // Act - begin drag
        let dragBegun = viewModel.beginOverviewBoardDrag(second.id)

        // Assert - drag begun without mutating order yet
        #expect(dragBegun)
        #expect(store.state.desks[0].boards.map(\.id) == [first.id, second.id])

        // Act - finish drag into target desk
        viewModel.overview.finishBoardDrag(second.id, toDeskID: other.id, at: 0)

        // Assert - order committed
        #expect(store.state.desks[0].boards.map(\.id) == [first.id])
        #expect(store.state.desks[1].boards.map(\.id) == [second.id, third.id])
        #expect(viewModel.overview.selectionBoardID == second.id)
        #expect(saveCount == 1)
    }

    @Test func overviewBoardDragIntoEmptyDeskFocusesMovedBoard() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let main = desk("Main", boards: [first, second], focusedBoardID: first.id)
        let empty = desk("Empty")
        let store = DenStore(state: DenState(desks: [main, empty], focusedDeskID: main.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()

        // Act
        #expect(viewModel.beginOverviewBoardDrag(second.id))
        viewModel.overview.finishBoardDrag(second.id, toDeskID: empty.id, at: 0)

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [first.id])
        #expect(store.state.desks[1].boards.map(\.id) == [second.id])
        #expect(store.state.desks[1].focusedBoardID == second.id)
        #expect(viewModel.overview.selectionBoardID == second.id)
    }

    @Test func overviewMovementActionIntoEmptyDeskFocusesMovedBoard() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let main = desk("Main", boards: [first, second], focusedBoardID: first.id)
        let empty = desk("Empty")
        let store = DenStore(state: DenState(desks: [main, empty], focusedDeskID: main.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()

        // Act
        viewModel.overview.selectBoard(second.id)
        viewModel.overview.moveSelectionBoardToNextDesk()

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [first.id])
        #expect(store.state.desks[1].boards.map(\.id) == [second.id])
        #expect(store.state.desks[1].focusedBoardID == second.id)
        #expect(viewModel.overview.selectionDeskID == empty.id)
        #expect(viewModel.overview.selectionBoardID == second.id)
    }

    @Test func overviewDeskMovementCarriesSelectedSideBoardGroup() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let source = desk("Source", boards: [target, side], focusedBoardID: target.id)
        let destination = desk("Destination")
        let store = DenStore(state: DenState(desks: [source, destination], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()
        viewModel.overview.selectBoard(side.id)

        viewModel.overview.moveSelectionBoardToNextDesk()

        #expect(store.state.desks[0].boards.isEmpty)
        #expect(store.state.desks[1].boards.map(\.id) == [target.id, side.id])
        #expect(viewModel.overview.selectionBoardID == side.id)
    }

    @Test func overviewDragCarriesSideBoardGroupToAnotherDesk() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let source = desk("Source", boards: [target, side], focusedBoardID: target.id)
        let destination = desk("Destination")
        let store = DenStore(state: DenState(desks: [source, destination], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()

        #expect(viewModel.beginOverviewBoardDrag(side.id))
        viewModel.overview.finishBoardDrag(side.id, toDeskID: destination.id, at: 0)

        #expect(store.state.desks[0].boards.isEmpty)
        #expect(store.state.desks[1].boards.map(\.id) == [target.id, side.id])
        #expect(viewModel.overview.selectionBoardID == side.id)
    }

    @Test func overviewReordersSideBoardGroupFromEitherMember() {
        let before = board("Before")
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let after = board("After")
        let source = desk("Desk", boards: [before, target, side, after])
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()
        viewModel.overview.selectBoard(side.id)

        viewModel.overview.moveSelectionBoardLeft()

        #expect(store.state.desks[0].boards.map(\.id) == [target.id, side.id, before.id, after.id])
        #expect(viewModel.overview.selectionBoardID == side.id)
    }

    @Test func overviewBoardDragCancellationLeavesEveryDeskUnchanged() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let third = board("Third")
        let main = desk("Main", boards: [first, second], focusedBoardID: first.id)
        let other = desk("Other", boards: [third], focusedBoardID: third.id)
        var saveCount = 0
        let store = DenStore(
            state: DenState(desks: [main, other], focusedDeskID: main.id),
            onSave: { _ in saveCount += 1 })
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()
        #expect(viewModel.beginOverviewBoardDrag(first.id))
        viewModel.overview.moveSelectionBoardRight()

        // Act
        viewModel.overview.cancelBoardDrag()

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [first.id, second.id])
        #expect(store.state.desks[1].boards.map(\.id) == [third.id])
        #expect(store.activeDrag == nil)
        #expect(saveCount == 0)
    }

    @Test func overviewBoardMovementAtDeskEdgesDoesNotSave() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let third = board("Third")
        let main = desk("Main", boards: [first, second, third], focusedBoardID: first.id)
        var saveCount = 0
        let store = DenStore(
            state: DenState(desks: [main], focusedDeskID: main.id),
            onSave: { _ in saveCount += 1 })
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()

        // Act
        viewModel.overview.selectBoard(first.id)
        viewModel.overview.moveSelectionBoardLeft()
        viewModel.overview.selectBoard(third.id)
        viewModel.overview.moveSelectionBoardRight()

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [first.id, second.id, third.id])
        #expect(saveCount == 0)
    }

    @Test func overviewBoardDragIsUnavailableWhileFiltering() {
        // Arrange
        let first = board("First")
        let desk = desk("Desk", boards: [first], focusedBoardID: first.id)
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()
        viewModel.overview.setQuery("First")

        // Act
        let begun = viewModel.beginOverviewBoardDrag(first.id)

        // Assert
        #expect(!begun)
        #expect(store.activeDrag == nil)
    }

    @Test func overviewMovementActionsMoveSelectedBoardWithinAndAcrossDesks() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let third = board("Third")
        let main = desk("Main", boards: [first, second], focusedBoardID: first.id)
        let other = desk("Other", boards: [third], focusedBoardID: third.id)
        let store = DenStore(state: DenState(desks: [main, other], focusedDeskID: main.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()

        // Act - move within desk
        viewModel.overview.selectBoard(second.id)
        viewModel.overview.moveSelectionBoardLeft()

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [second.id, first.id])
        #expect(viewModel.overview.selectionBoardID == second.id)

        // Act - move to next desk
        viewModel.overview.moveSelectionBoardToNextDesk()

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [first.id])
        #expect(store.state.desks[1].boards.map(\.id) == [third.id, second.id])
        #expect(viewModel.overview.selectionDeskID == other.id)
        #expect(viewModel.overview.selectionBoardID == second.id)
    }

    @Test func enteringAnEmptyDeskFromOverviewLeavesOverview() {
        // Arrange
        let board = board("Board")
        let main = desk("Main", boards: [board], focusedBoardID: board.id)
        let empty = desk("Empty")
        let store = DenStore(
            state: DenState(desks: [main, empty], focusedDeskID: main.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()

        // Act
        viewModel.overview.enterDesk(empty.id)

        // Assert
        #expect(store.presentedDeskID == empty.id)
        #expect(store.focusedDesk?.id == empty.id)
        #expect(store.focusedBoard == nil)
        #expect(!viewModel.isOverviewPresented)
        #expect(!viewModel.isDenMode)
    }

    @Test func removingSelectedBoardInOverviewUpdatesOverviewSelection() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let third = board("Third")
        let main = desk("Main", boards: [first, second, third], focusedBoardID: second.id)
        let store = DenStore(state: DenState(desks: [main], focusedDeskID: main.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()
        #expect(viewModel.overview.selectionBoardID == second.id)

        // Act
        store.removeBoard(second.id)

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [first.id, third.id])
        #expect(viewModel.overview.selectionDeskID == main.id)
        #expect(viewModel.overview.selectionBoardID == third.id)
        #expect(viewModel.isOverviewPresented)
    }

    @Test func removingOnlyBoardInDeskInOverviewLeavesDeskWithNilSelection() {
        // Arrange
        let onlyBoard = board("Only")
        let main = desk("Main", boards: [onlyBoard], focusedBoardID: onlyBoard.id)
        let store = DenStore(state: DenState(desks: [main], focusedDeskID: main.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()
        #expect(viewModel.overview.selectionBoardID == onlyBoard.id)

        // Act
        store.removeBoard(onlyBoard.id)

        // Assert
        #expect(store.state.desks[0].boards.isEmpty)
        #expect(viewModel.overview.selectionDeskID == main.id)
        #expect(viewModel.overview.selectionBoardID == nil)
        #expect(viewModel.isOverviewPresented)
    }

    @Test func moveOverviewDeskSelectionCanSelectEmptyDesk() {
        let board1 = board("Board1")
        let first = desk("First", boards: [board1], focusedBoardID: board1.id)
        let empty = desk("Empty")
        let store = DenStore(state: DenState(desks: [first, empty], focusedDeskID: first.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.showOverview()
        #expect(viewModel.overview.selectionDeskID == first.id)
        #expect(viewModel.overview.selectionBoardID == board1.id)

        viewModel.overview.selectNextDesk()
        #expect(viewModel.overview.selectionDeskID == empty.id)
        #expect(viewModel.overview.selectionBoardID == nil)

        viewModel.overview.selectNextDesk()
        #expect(viewModel.overview.selectionDeskID == first.id)
        #expect(viewModel.overview.selectionBoardID == board1.id)

        viewModel.overview.selectPreviousDesk()
        #expect(viewModel.overview.selectionDeskID == empty.id)
        #expect(viewModel.overview.selectionBoardID == nil)
    }

    private func keyEvent(_ character: String, keyCode: UInt16) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode)
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
