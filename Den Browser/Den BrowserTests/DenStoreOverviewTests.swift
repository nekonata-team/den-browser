import AppKit
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenStoreOverviewTests {

    @Test func denCommandsAreSuspendedByOverview() throws {
        let first = board("First")
        let second = board("Second")
        try withStore(desks: [desk("Desk", boards: [first, second], focusedBoardID: first.id)]) { store in
            store.showOverview()
            let openBoard = try #require(keyEvent("t", keyCode: 17))
            let editLink = try #require(keyEvent("l", keyCode: 37))
            let removeBoard = try #require(keyEvent("w", keyCode: 13))

            #expect(KeyboardController.handle(openBoard, store: store))
            #expect(KeyboardController.handle(editLink, store: store))
            #expect(KeyboardController.handle(removeBoard, store: store))
            #expect(store.isOverviewPresented)
            #expect(!store.isOpenBoardPanelPresented)
            #expect(!store.isEditBoardLinkPanelPresented)
            #expect(store.focusedDesk?.boards.map(\.id) == [first.id, second.id])
        }
    }

    @Test func temporaryContextsAreExclusiveAndClearOverviewSelection() {
        let board = board("Board")
        withStore(desks: [desk("Desk", boards: [board], focusedBoardID: board.id)]) { store in
            store.showOverview()
            #expect(store.temporaryContext == .overview)
            #expect(store.overviewSelectionBoardID == board.id)

            store.showOpenBoardPanel()

            #expect(store.temporaryContext == .openBoard)
            #expect(store.overviewSelectionDeskID == nil)
            #expect(store.overviewSelectionBoardID == nil)
            #expect(!store.isOverviewPresented)
        }
    }

    @Test func overviewFilteringAndNavigation() {
        let googleBoard = board("Google", url: "https://google.com")
        let githubBoard = board("GitHub", url: "https://github.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)
        let desk2 = desk("Dev", boards: [githubBoard], focusedBoardID: githubBoard.id)

        withStore(desks: [desk1, desk2]) { store in
            // 1. Show overview
            store.showOverview()
            #expect(store.overviewQuery == "")
            #expect(store.overviewFilterPhase == .inactive)
            #expect(store.overviewSelectionDeskID == desk1.id)
            #expect(store.overviewSelectionBoardID == googleBoard.id)

            // 2. Set query matching githubBoard
            store.setOverviewQuery("git")
            #expect(store.overviewQuery == "git")
            // Selection should jump to first matching board (githubBoard in desk2)
            #expect(store.overviewSelectionDeskID == desk2.id)
            #expect(store.overviewSelectionBoardID == githubBoard.id)

            // 3. Re-set query matching googleBoard
            store.setOverviewQuery("oog")
            #expect(store.overviewSelectionDeskID == desk1.id)
            #expect(store.overviewSelectionBoardID == googleBoard.id)

            // 4. Test matchesOverviewFilter
            #expect(store.matchesOverviewFilter(googleBoard, in: desk1))
            #expect(!store.matchesOverviewFilter(githubBoard, in: desk2))

            // 5. Non-matching query clears selection
            store.setOverviewQuery("nonexistent")
            #expect(store.overviewSelectionDeskID == nil)
            #expect(store.overviewSelectionBoardID == nil)

            // 6. Enter filter mode, type query, and confirm it
            store.enterOverviewFilterMode()
            #expect(store.overviewFilterPhase == .filtering)
            store.setOverviewQuery("git")
            store.confirmOverviewFilterQuery()
            #expect(store.overviewFilterPhase == .selecting)
            #expect(store.overviewQuery == "git")

            // 7. Clear query in normal mode
            store.clearOverviewQuery()
            #expect(store.overviewQuery == "")
            #expect(store.overviewFilterPhase == .inactive)
            #expect(store.overviewSelectionDeskID == desk2.id)
            #expect(store.overviewSelectionBoardID == githubBoard.id)

            // 8. Escape clears filter mode and query
            store.enterOverviewFilterMode()
            store.exitOverviewFilterMode()
            #expect(store.overviewFilterPhase == .inactive)
            #expect(store.overviewQuery == "")
        }
    }

    @Test func overviewBoardDragMovesAcrossDesksOnlyOnCommit() {
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

        #expect(store.beginOverviewBoardDrag(second.id))
        #expect(store.state.desks[0].boards.map(\.id) == [first.id, second.id])
        store.finishOverviewBoardDrag(second.id, toDeskID: other.id, at: 0)
        #expect(store.state.desks[0].boards.map(\.id) == [first.id])
        #expect(store.state.desks[1].boards.map(\.id) == [second.id, third.id])
        #expect(store.overviewSelectionBoardID == second.id)
        #expect(saveCount == 1)
    }

    @Test func overviewBoardDragCancellationLeavesEveryDeskUnchanged() {
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
        #expect(store.state.desks[0].boards.map(\.id) == [first.id, second.id])
        store.cancelOverviewBoardDrag()

        #expect(store.state.desks[0].boards.map(\.id) == [first.id, second.id])
        #expect(store.state.desks[1].boards.map(\.id) == [third.id])
        #expect(store.activeDrag == nil)
        #expect(saveCount == 0)
    }

    @Test func overviewBoardDragIsUnavailableWhileFiltering() {
        let first = board("First")
        let desk = desk("Desk", boards: [first], focusedBoardID: first.id)
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))
        store.showOverview()
        store.setOverviewQuery("First")

        #expect(!store.beginOverviewBoardDrag(first.id))
        #expect(store.activeDrag == nil)
    }

    @Test func overviewMovementActionsMoveSelectedBoardWithinAndAcrossDesks() {
        let first = board("First")
        let second = board("Second")
        let third = board("Third")
        let main = desk("Main", boards: [first, second], focusedBoardID: first.id)
        let other = desk("Other", boards: [third], focusedBoardID: third.id)
        let store = DenStore(state: DenState(desks: [main, other], focusedDeskID: main.id))
        store.showOverview()

        store.selectBoardInOverview(second.id)
        store.moveOverviewSelectionBoardLeft()
        #expect(store.state.desks[0].boards.map(\.id) == [second.id, first.id])
        #expect(store.overviewSelectionBoardID == second.id)

        store.moveOverviewSelectionBoardToNextDesk()
        #expect(store.state.desks[0].boards.map(\.id) == [first.id])
        #expect(store.state.desks[1].boards.map(\.id) == [third.id, second.id])
        #expect(store.overviewSelectionDeskID == other.id)
        #expect(store.overviewSelectionBoardID == second.id)
    }

    @Test func enteringAnEmptyDeskFromOverviewLeavesOverview() {
        let board = board("Board")
        let main = desk("Main", boards: [board], focusedBoardID: board.id)
        let empty = desk("Empty")
        let store = DenStore(
            state: DenState(desks: [main, empty], focusedDeskID: main.id))
        store.showOverview()

        store.enterOverviewDesk(empty.id)

        #expect(store.presentedDeskID == empty.id)
        #expect(store.focusedDesk?.id == empty.id)
        #expect(store.focusedBoard == nil)
        #expect(!store.isOverviewPresented)
        #expect(!store.isDenMode)
    }

    @Test func removingSelectedBoardInOverviewUpdatesOverviewSelection() {
        let first = board("First")
        let second = board("Second")
        let third = board("Third")
        let main = desk("Main", boards: [first, second, third], focusedBoardID: second.id)
        let store = DenStore(state: DenState(desks: [main], focusedDeskID: main.id))
        store.showOverview()
        #expect(store.overviewSelectionBoardID == second.id)

        store.removeBoard(second.id)

        #expect(store.state.desks[0].boards.map(\.id) == [first.id, third.id])
        #expect(store.overviewSelectionDeskID == main.id)
        #expect(store.overviewSelectionBoardID == third.id)
        #expect(store.isOverviewPresented)
    }

    @Test func removingOnlyBoardInDeskInOverviewLeavesDeskWithNilSelection() {
        let onlyBoard = board("Only")
        let main = desk("Main", boards: [onlyBoard], focusedBoardID: onlyBoard.id)
        let store = DenStore(state: DenState(desks: [main], focusedDeskID: main.id))
        store.showOverview()
        #expect(store.overviewSelectionBoardID == onlyBoard.id)

        store.removeBoard(onlyBoard.id)

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
