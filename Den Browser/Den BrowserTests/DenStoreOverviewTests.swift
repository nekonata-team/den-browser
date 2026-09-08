import AppKit
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenStoreOverviewTests {

    @Test func denCommandsAreSuspendedByOverview() throws {
        // Arrange
        let first = board("First")
        let second = board("Second")
        try withStore(desks: [desk("Desk", boards: [first, second], focusedBoardID: first.id)]) { store in
            store.showOverview()
            let openBoard = try #require(keyEvent("t", keyCode: 17))
            let editLink = try #require(keyEvent("l", keyCode: 37))
            let removeBoard = try #require(keyEvent("w", keyCode: 13))

            // Act
            let openHandled = KeyboardController.handle(openBoard, store: store)
            let editHandled = KeyboardController.handle(editLink, store: store)
            let removeHandled = KeyboardController.handle(removeBoard, store: store)

            // Assert
            #expect(openHandled)
            #expect(editHandled)
            #expect(removeHandled)
            #expect(store.isOverviewPresented)
            #expect(!store.isOpenBoardPanelPresented)
            #expect(!store.isEditBoardLinkPanelPresented)
            #expect(store.focusedDesk?.boards.map(\.id) == [first.id, second.id])
        }
    }

    @Test func temporaryContextsAreExclusiveAndClearOverviewSelection() {
        // Arrange
        let board = board("Board")
        withStore(desks: [desk("Desk", boards: [board], focusedBoardID: board.id)]) { store in
            store.showOverview()
            #expect(store.temporaryContext == .overview)
            #expect(store.overviewSelectionBoardID == board.id)

            // Act
            store.showOpenBoardPanel()

            // Assert
            #expect(store.temporaryContext == .openBoard)
            #expect(store.overviewSelectionDeskID == nil)
            #expect(store.overviewSelectionBoardID == nil)
            #expect(!store.isOverviewPresented)
        }
    }

    @Test func overviewInitializesWithFirstBoardSelected() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)

        // Act
        withStore(desks: [desk1]) { store in
            store.showOverview()

            // Assert
            #expect(store.overviewQuery == "")
            #expect(store.overviewFilterPhase == .inactive)
            #expect(store.overviewSelectionDeskID == desk1.id)
            #expect(store.overviewSelectionBoardID == googleBoard.id)
        }
    }

    @Test func overviewQuerySelectsFirstMatchingBoard() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let githubBoard = board("GitHub", url: "https://github.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)
        let desk2 = desk("Dev", boards: [githubBoard], focusedBoardID: githubBoard.id)

        withStore(desks: [desk1, desk2]) { store in
            store.showOverview()

            // Act
            store.setOverviewQuery("git")

            // Assert
            #expect(store.overviewQuery == "git")
            #expect(store.overviewSelectionDeskID == desk2.id)
            #expect(store.overviewSelectionBoardID == githubBoard.id)
        }
    }

    @Test func overviewFilterMatchesCorrectBoards() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let githubBoard = board("GitHub", url: "https://github.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)
        let desk2 = desk("Dev", boards: [githubBoard], focusedBoardID: githubBoard.id)

        withStore(desks: [desk1, desk2]) { store in
            store.showOverview()

            // Act
            store.setOverviewQuery("oog")

            // Assert
            #expect(store.overviewSelectionDeskID == desk1.id)
            #expect(store.overviewSelectionBoardID == googleBoard.id)
            #expect(store.matchesOverviewFilter(googleBoard, in: desk1))
            #expect(!store.matchesOverviewFilter(githubBoard, in: desk2))
        }
    }

    @Test func overviewNonMatchingQueryClearsSelection() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)

        withStore(desks: [desk1]) { store in
            store.showOverview()

            // Act
            store.setOverviewQuery("nonexistent")

            // Assert
            #expect(store.overviewSelectionDeskID == nil)
            #expect(store.overviewSelectionBoardID == nil)
        }
    }

    @Test func overviewFilterModeConfirmsQueryAndEntersSelectingPhase() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)

        withStore(desks: [desk1]) { store in
            store.showOverview()

            // Act
            store.enterOverviewFilterMode()
            #expect(store.overviewFilterPhase == .filtering)
            store.setOverviewQuery("goog")
            store.confirmOverviewFilterQuery()

            // Assert
            #expect(store.overviewFilterPhase == .selecting)
            #expect(store.overviewQuery == "goog")
        }
    }

    @Test func overviewClearQueryRestoresDefaultSelection() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let githubBoard = board("GitHub", url: "https://github.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)
        let desk2 = desk("Dev", boards: [githubBoard], focusedBoardID: githubBoard.id)

        withStore(desks: [desk1, desk2]) { store in
            store.showOverview()
            store.setOverviewQuery("git")

            // Act
            store.clearOverviewQuery()

            // Assert
            #expect(store.overviewQuery == "")
            #expect(store.overviewFilterPhase == .inactive)
            #expect(store.overviewSelectionDeskID == desk2.id)
            #expect(store.overviewSelectionBoardID == githubBoard.id)
        }
    }

    @Test func overviewExitFilterModeClearsQueryAndPhase() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)

        withStore(desks: [desk1]) { store in
            store.showOverview()
            store.enterOverviewFilterMode()
            store.setOverviewQuery("goog")

            // Act
            store.exitOverviewFilterMode()

            // Assert
            #expect(store.overviewFilterPhase == .inactive)
            #expect(store.overviewQuery == "")
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
        store.showOverview()

        // Act - begin drag
        let dragBegun = store.beginOverviewBoardDrag(second.id)

        // Assert - drag begun without mutating order yet
        #expect(dragBegun)
        #expect(store.state.desks[0].boards.map(\.id) == [first.id, second.id])

        // Act - finish drag into target desk
        store.finishOverviewBoardDrag(second.id, toDeskID: other.id, at: 0)

        // Assert - order committed
        #expect(store.state.desks[0].boards.map(\.id) == [first.id])
        #expect(store.state.desks[1].boards.map(\.id) == [second.id, third.id])
        #expect(store.overviewSelectionBoardID == second.id)
        #expect(saveCount == 1)
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
        store.showOverview()
        #expect(store.beginOverviewBoardDrag(first.id))
        store.moveOverviewSelectionBoardRight()

        // Act
        store.cancelOverviewBoardDrag()

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [first.id, second.id])
        #expect(store.state.desks[1].boards.map(\.id) == [third.id])
        #expect(store.activeDrag == nil)
        #expect(saveCount == 0)
    }

    @Test func overviewBoardDragIsUnavailableWhileFiltering() {
        // Arrange
        let first = board("First")
        let desk = desk("Desk", boards: [first], focusedBoardID: first.id)
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))
        store.showOverview()
        store.setOverviewQuery("First")

        // Act
        let begun = store.beginOverviewBoardDrag(first.id)

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
        store.showOverview()

        // Act - move within desk
        store.selectBoardInOverview(second.id)
        store.moveOverviewSelectionBoardLeft()

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [second.id, first.id])
        #expect(store.overviewSelectionBoardID == second.id)

        // Act - move to next desk
        store.moveOverviewSelectionBoardToNextDesk()

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [first.id])
        #expect(store.state.desks[1].boards.map(\.id) == [third.id, second.id])
        #expect(store.overviewSelectionDeskID == other.id)
        #expect(store.overviewSelectionBoardID == second.id)
    }

    @Test func enteringAnEmptyDeskFromOverviewLeavesOverview() {
        // Arrange
        let board = board("Board")
        let main = desk("Main", boards: [board], focusedBoardID: board.id)
        let empty = desk("Empty")
        let store = DenStore(
            state: DenState(desks: [main, empty], focusedDeskID: main.id))
        store.showOverview()

        // Act
        store.enterOverviewDesk(empty.id)

        // Assert
        #expect(store.presentedDeskID == empty.id)
        #expect(store.focusedDesk?.id == empty.id)
        #expect(store.focusedBoard == nil)
        #expect(!store.isOverviewPresented)
        #expect(!store.isDenMode)
    }

    @Test func removingSelectedBoardInOverviewUpdatesOverviewSelection() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let third = board("Third")
        let main = desk("Main", boards: [first, second, third], focusedBoardID: second.id)
        let store = DenStore(state: DenState(desks: [main], focusedDeskID: main.id))
        store.showOverview()
        #expect(store.overviewSelectionBoardID == second.id)

        // Act
        store.removeBoard(second.id)

        // Assert
        #expect(store.state.desks[0].boards.map(\.id) == [first.id, third.id])
        #expect(store.overviewSelectionDeskID == main.id)
        #expect(store.overviewSelectionBoardID == third.id)
        #expect(store.isOverviewPresented)
    }

    @Test func removingOnlyBoardInDeskInOverviewLeavesDeskWithNilSelection() {
        // Arrange
        let onlyBoard = board("Only")
        let main = desk("Main", boards: [onlyBoard], focusedBoardID: onlyBoard.id)
        let store = DenStore(state: DenState(desks: [main], focusedDeskID: main.id))
        store.showOverview()
        #expect(store.overviewSelectionBoardID == onlyBoard.id)

        // Act
        store.removeBoard(onlyBoard.id)

        // Assert
        #expect(store.state.desks[0].boards.isEmpty)
        #expect(store.overviewSelectionDeskID == main.id)
        #expect(store.overviewSelectionBoardID == nil)
        #expect(store.isOverviewPresented)
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
