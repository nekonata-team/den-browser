import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct OverviewModelTests {
    @Test func denCommandsAreSuspendedByOverview() throws {
        // Arrange
        let first = board("First")
        let second = board("Second")
        try withTestWindowModel(desks: [desk("Desk", boards: [first, second], focusedBoardID: first.id)]) {
            windowModel, controller in
            windowModel.showOverview()
            let openBoard = try #require(keyEvent("t", keyCode: 17))
            let editLink = try #require(keyEvent("l", keyCode: 37))
            let removeBoard = try #require(keyEvent("w", keyCode: 13))

            // Act
            let openHandled = KeyboardController.handle(openBoard, controller: controller, windowModel: windowModel)
            let editHandled = KeyboardController.handle(editLink, controller: controller, windowModel: windowModel)
            let removeHandled = KeyboardController.handle(removeBoard, controller: controller, windowModel: windowModel)

            // Assert
            #expect(openHandled)
            #expect(editHandled)
            #expect(removeHandled)
            #expect(windowModel.isOverviewPresented)
            #expect(!windowModel.isOpenBoardPanelPresented)
            #expect(!windowModel.isEditBoardLinkPanelPresented)
            #expect(controller.focusedDesk?.boards.map(\.id) == [first.id, second.id])
        }
    }

    @Test func temporaryContextsAreExclusiveAndClearOverviewSelection() {
        // Arrange
        let board = board("Board")
        withTestWindowModel(desks: [desk("Desk", boards: [board], focusedBoardID: board.id)]) { windowModel, _ in
            windowModel.showOverview()
            #expect(windowModel.temporaryContext == .overview)
            #expect(windowModel.overview.selectionBoardID == board.id)

            // Act
            windowModel.showOpenBoardPanel()

            // Assert
            #expect(windowModel.temporaryContext == .openBoard)
            #expect(windowModel.overview.selectionDeskID == nil)
            #expect(windowModel.overview.selectionBoardID == nil)
            #expect(!windowModel.isOverviewPresented)
        }
    }

    @Test func overviewInitializesWithFirstBoardSelected() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)

        // Act
        withTestWindowModel(desks: [desk1]) { windowModel, _ in
            windowModel.showOverview()

            // Assert
            #expect(windowModel.overview.query == "")
            #expect(windowModel.overview.filterPhase == .inactive)
            #expect(windowModel.overview.selectionDeskID == desk1.id)
            #expect(windowModel.overview.selectionBoardID == googleBoard.id)
        }
    }

    @Test func overviewQuerySelectsFirstMatchingBoard() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let githubBoard = board("GitHub", url: "https://github.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)
        let desk2 = desk("Dev", boards: [githubBoard], focusedBoardID: githubBoard.id)

        withTestWindowModel(desks: [desk1, desk2]) { windowModel, _ in
            windowModel.showOverview()

            // Act
            windowModel.overview.setQuery("git")

            // Assert
            #expect(windowModel.overview.query == "git")
            #expect(windowModel.overview.selectionDeskID == desk2.id)
            #expect(windowModel.overview.selectionBoardID == githubBoard.id)
        }
    }

    @Test func returnToCurrentDeskRestoresFocusAndClearsSearch() {
        // Arrange
        let currentBoard = board("Current")
        let otherBoard = board("Other")
        let currentDesk = desk("Current Desk", boards: [currentBoard], focusedBoardID: currentBoard.id)
        let otherDesk = desk("Other Desk", boards: [otherBoard], focusedBoardID: otherBoard.id)
        withTestWindowModel(desks: [currentDesk, otherDesk]) { windowModel, controller in
            windowModel.showOverview()
            let overview = windowModel.overview
            overview.enterFilterMode()
            overview.setQuery("Other")
            let resetRequest = overview.canvasResetRequest

            // Act
            overview.returnToCurrentDesk()

            // Assert
            #expect(overview.query.isEmpty)
            #expect(overview.filterPhase == .inactive)
            #expect(overview.selectionDeskID == currentDesk.id)
            #expect(overview.selectionBoardID == currentBoard.id)
            #expect(overview.canvasResetRequest == resetRequest + 1)
            #expect(controller.focusedDesk?.id == currentDesk.id)
            #expect(windowModel.isOverviewPresented)
        }
    }

    @Test func overviewFilterMatchesCorrectBoards() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let githubBoard = board("GitHub", url: "https://github.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)
        let desk2 = desk("Dev", boards: [githubBoard], focusedBoardID: githubBoard.id)

        withTestWindowModel(desks: [desk1, desk2]) { windowModel, _ in
            windowModel.showOverview()

            // Act
            windowModel.overview.setQuery("oog")

            // Assert
            #expect(windowModel.overview.selectionDeskID == desk1.id)
            #expect(windowModel.overview.selectionBoardID == googleBoard.id)
            #expect(windowModel.overview.matchesFilter(googleBoard, in: desk1))
            #expect(!windowModel.overview.matchesFilter(githubBoard, in: desk2))
        }
    }

    @Test func overviewNonMatchingQueryClearsSelection() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)

        withTestWindowModel(desks: [desk1]) { windowModel, _ in
            windowModel.showOverview()

            // Act
            windowModel.overview.setQuery("nonexistent")

            // Assert
            #expect(windowModel.overview.selectionDeskID == nil)
            #expect(windowModel.overview.selectionBoardID == nil)
        }
    }

    @Test func overviewFilterModeConfirmsQueryAndEntersSelectingPhase() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)

        withTestWindowModel(desks: [desk1]) { windowModel, _ in
            windowModel.showOverview()

            // Act
            windowModel.overview.enterFilterMode()
            #expect(windowModel.overview.filterPhase == .filtering)
            windowModel.overview.setQuery("goog")
            windowModel.overview.confirmFilterQuery()

            // Assert
            #expect(windowModel.overview.filterPhase == .selecting)
            #expect(windowModel.overview.query == "goog")
        }
    }

    @Test func overviewClearQueryRestoresDefaultSelection() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let githubBoard = board("GitHub", url: "https://github.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)
        let desk2 = desk("Dev", boards: [githubBoard], focusedBoardID: githubBoard.id)

        withTestWindowModel(desks: [desk1, desk2]) { windowModel, _ in
            windowModel.showOverview()
            windowModel.overview.setQuery("git")

            // Act
            windowModel.overview.clearQuery()

            // Assert
            #expect(windowModel.overview.query == "")
            #expect(windowModel.overview.filterPhase == .inactive)
            #expect(windowModel.overview.selectionDeskID == desk2.id)
            #expect(windowModel.overview.selectionBoardID == githubBoard.id)
        }
    }

    @Test func overviewExitFilterModeClearsQueryAndPhase() {
        // Arrange
        let googleBoard = board("Google", url: "https://google.com")
        let desk1 = desk("Main", boards: [googleBoard], focusedBoardID: googleBoard.id)

        withTestWindowModel(desks: [desk1]) { windowModel, _ in
            windowModel.showOverview()
            windowModel.overview.enterFilterMode()
            windowModel.overview.setQuery("goog")

            // Act
            windowModel.overview.exitFilterMode()

            // Assert
            #expect(windowModel.overview.filterPhase == .inactive)
            #expect(windowModel.overview.query == "")
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
        let controller = DenController(
            state: DenState(desks: [main, other], focusedDeskID: main.id),
            onSave: { _ in saveCount += 1 })
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()

        // Act - begin drag
        let dragBegun = windowModel.beginOverviewBoardDrag(second.id)

        // Assert - drag begun without mutating order yet
        #expect(dragBegun)
        #expect(controller.state.desks[0].boards.map(\.id) == [first.id, second.id])

        // Act - finish drag into target desk
        windowModel.overview.finishBoardDrag(second.id, toDeskID: other.id, at: BoardIndex(rawValue: 0))

        // Assert - order committed
        #expect(controller.state.desks[0].boards.map(\.id) == [first.id])
        #expect(controller.state.desks[1].boards.map(\.id) == [second.id, third.id])
        #expect(windowModel.overview.selectionBoardID == second.id)
        #expect(saveCount == 1)
    }

    @Test func overviewBoardDragIntoEmptyDeskFocusesMovedBoard() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let main = desk("Main", boards: [first, second], focusedBoardID: first.id)
        let empty = desk("Empty")
        let controller = DenController(state: DenState(desks: [main, empty], focusedDeskID: main.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()

        // Act
        #expect(windowModel.beginOverviewBoardDrag(second.id))
        windowModel.overview.finishBoardDrag(second.id, toDeskID: empty.id, at: BoardIndex(rawValue: 0))

        // Assert
        #expect(controller.state.desks[0].boards.map(\.id) == [first.id])
        #expect(controller.state.desks[1].boards.map(\.id) == [second.id])
        #expect(controller.state.desks[1].focusedBoardID == second.id)
        #expect(windowModel.overview.selectionBoardID == second.id)
    }

    @Test func overviewMovementActionIntoEmptyDeskFocusesMovedBoard() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let main = desk("Main", boards: [first, second], focusedBoardID: first.id)
        let empty = desk("Empty")
        let controller = DenController(state: DenState(desks: [main, empty], focusedDeskID: main.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()

        // Act
        windowModel.overview.selectBoard(second.id)
        windowModel.overview.moveSelectionBoardToNextDesk()

        // Assert
        #expect(controller.state.desks[0].boards.map(\.id) == [first.id])
        #expect(controller.state.desks[1].boards.map(\.id) == [second.id])
        #expect(controller.state.desks[1].focusedBoardID == second.id)
        #expect(windowModel.overview.selectionDeskID == empty.id)
        #expect(windowModel.overview.selectionBoardID == second.id)
    }

    @Test func overviewDeskMovementCarriesSelectedSideBoardGroup() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let source = desk("Source", boards: [target, side], focusedBoardID: target.id)
        let destination = desk("Destination")
        let controller = DenController(state: DenState(desks: [source, destination], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()
        windowModel.overview.selectBoard(side.id)

        windowModel.overview.moveSelectionBoardToNextDesk()

        #expect(controller.state.desks[0].boards.isEmpty)
        #expect(controller.state.desks[1].boards.map(\.id) == [target.id, side.id])
        #expect(windowModel.overview.selectionBoardID == side.id)
    }

    @Test func overviewDragCarriesSideBoardGroupToAnotherDesk() {
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let source = desk("Source", boards: [target, side], focusedBoardID: target.id)
        let destination = desk("Destination")
        let controller = DenController(state: DenState(desks: [source, destination], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()

        #expect(windowModel.beginOverviewBoardDrag(side.id))
        windowModel.overview.finishBoardDrag(
            side.id, toDeskID: destination.id, at: BoardIndex(rawValue: 0))

        #expect(controller.state.desks[0].boards.isEmpty)
        #expect(controller.state.desks[1].boards.map(\.id) == [target.id, side.id])
        #expect(windowModel.overview.selectionBoardID == side.id)
    }

    @Test func overviewReordersSideBoardGroupFromEitherMember() {
        let before = board("Before")
        let target = board("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let after = board("After")
        let source = desk("Desk", boards: [before, target, side, after])
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()
        windowModel.overview.selectBoard(side.id)

        windowModel.overview.moveSelectionBoardLeft()

        #expect(controller.state.desks[0].boards.map(\.id) == [target.id, side.id, before.id, after.id])
        #expect(windowModel.overview.selectionBoardID == side.id)
    }

    @Test func overviewBoardDragCancellationLeavesEveryDeskUnchanged() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let third = board("Third")
        let main = desk("Main", boards: [first, second], focusedBoardID: first.id)
        let other = desk("Other", boards: [third], focusedBoardID: third.id)
        var saveCount = 0
        let controller = DenController(
            state: DenState(desks: [main, other], focusedDeskID: main.id),
            onSave: { _ in saveCount += 1 })
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()
        #expect(windowModel.beginOverviewBoardDrag(first.id))
        windowModel.overview.moveSelectionBoardRight()

        // Act
        windowModel.overview.cancelBoardDrag()

        // Assert
        #expect(controller.state.desks[0].boards.map(\.id) == [first.id, second.id])
        #expect(controller.state.desks[1].boards.map(\.id) == [third.id])
        #expect(controller.activeDrag == nil)
        #expect(saveCount == 0)
    }

    @Test func overviewBoardMovementAtDeskEdgesDoesNotSave() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let third = board("Third")
        let main = desk("Main", boards: [first, second, third], focusedBoardID: first.id)
        var saveCount = 0
        let controller = DenController(
            state: DenState(desks: [main], focusedDeskID: main.id),
            onSave: { _ in saveCount += 1 })
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()

        // Act
        windowModel.overview.selectBoard(first.id)
        windowModel.overview.moveSelectionBoardLeft()
        windowModel.overview.selectBoard(third.id)
        windowModel.overview.moveSelectionBoardRight()

        // Assert
        #expect(controller.state.desks[0].boards.map(\.id) == [first.id, second.id, third.id])
        #expect(saveCount == 0)
    }

    @Test func overviewBoardDragIsUnavailableWhileFiltering() {
        // Arrange
        let first = board("First")
        let desk = desk("Desk", boards: [first], focusedBoardID: first.id)
        let controller = DenController(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()
        windowModel.overview.setQuery("First")

        // Act
        let begun = windowModel.beginOverviewBoardDrag(first.id)

        // Assert
        #expect(!begun)
        #expect(controller.activeDrag == nil)
    }

    @Test func overviewMovementActionsMoveSelectedBoardWithinAndAcrossDesks() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let third = board("Third")
        let main = desk("Main", boards: [first, second], focusedBoardID: first.id)
        let other = desk("Other", boards: [third], focusedBoardID: third.id)
        let controller = DenController(state: DenState(desks: [main, other], focusedDeskID: main.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()

        // Act - move within desk
        windowModel.overview.selectBoard(second.id)
        windowModel.overview.moveSelectionBoardLeft()

        // Assert
        #expect(controller.state.desks[0].boards.map(\.id) == [second.id, first.id])
        #expect(windowModel.overview.selectionBoardID == second.id)

        // Act - move to next desk
        windowModel.overview.moveSelectionBoardToNextDesk()

        // Assert
        #expect(controller.state.desks[0].boards.map(\.id) == [first.id])
        #expect(controller.state.desks[1].boards.map(\.id) == [third.id, second.id])
        #expect(windowModel.overview.selectionDeskID == other.id)
        #expect(windowModel.overview.selectionBoardID == second.id)
    }

    @Test func enteringAnEmptyDeskFromOverviewLeavesOverview() {
        // Arrange
        let board = board("Board")
        let main = desk("Main", boards: [board], focusedBoardID: board.id)
        let empty = desk("Empty")
        let controller = DenController(
            state: DenState(desks: [main, empty], focusedDeskID: main.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()

        // Act
        windowModel.overview.enterDesk(empty.id)

        // Assert
        #expect(controller.presentedDeskID == empty.id)
        #expect(controller.focusedDesk?.id == empty.id)
        #expect(controller.focusedBoard == nil)
        #expect(!windowModel.isOverviewPresented)
        #expect(!windowModel.isDenMode)
    }

    @Test func removingSelectedBoardInOverviewUpdatesOverviewSelection() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let third = board("Third")
        let main = desk("Main", boards: [first, second, third], focusedBoardID: second.id)
        let controller = DenController(state: DenState(desks: [main], focusedDeskID: main.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()
        #expect(windowModel.overview.selectionBoardID == second.id)

        // Act
        controller.removeBoard(second.id)

        // Assert
        #expect(controller.state.desks[0].boards.map(\.id) == [first.id, third.id])
        #expect(windowModel.overview.selectionDeskID == main.id)
        #expect(windowModel.overview.selectionBoardID == third.id)
        #expect(windowModel.isOverviewPresented)
    }

    @Test func removingOnlyBoardInDeskInOverviewLeavesDeskWithNilSelection() {
        // Arrange
        let onlyBoard = board("Only")
        let main = desk("Main", boards: [onlyBoard], focusedBoardID: onlyBoard.id)
        let controller = DenController(state: DenState(desks: [main], focusedDeskID: main.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()
        #expect(windowModel.overview.selectionBoardID == onlyBoard.id)

        // Act
        controller.removeBoard(onlyBoard.id)

        // Assert
        #expect(controller.state.desks[0].boards.isEmpty)
        #expect(windowModel.overview.selectionDeskID == main.id)
        #expect(windowModel.overview.selectionBoardID == nil)
        #expect(windowModel.isOverviewPresented)
    }

    @Test func moveOverviewDeskSelectionCanSelectEmptyDesk() {
        let board1 = board("Board1")
        let first = desk("First", boards: [board1], focusedBoardID: board1.id)
        let empty = desk("Empty")
        let controller = DenController(state: DenState(desks: [first, empty], focusedDeskID: first.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.showOverview()
        #expect(windowModel.overview.selectionDeskID == first.id)
        #expect(windowModel.overview.selectionBoardID == board1.id)

        windowModel.overview.selectNextDesk()
        #expect(windowModel.overview.selectionDeskID == empty.id)
        #expect(windowModel.overview.selectionBoardID == nil)

        windowModel.overview.selectNextDesk()
        #expect(windowModel.overview.selectionDeskID == first.id)
        #expect(windowModel.overview.selectionBoardID == board1.id)

        windowModel.overview.selectPreviousDesk()
        #expect(windowModel.overview.selectionDeskID == empty.id)
        #expect(windowModel.overview.selectionBoardID == nil)
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

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: BoardID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
