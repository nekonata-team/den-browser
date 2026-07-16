import AppKit
import Foundation
import Testing
@testable import Den_Browser

@MainActor
struct DenStoreTests {
    @Test func createsEmptyDeskAfterFocusedDesk() {
        withStore(desks: [desk("First"), desk("Second")]) { store in
            store.createDesk(label: "  Writing  ", template: .empty)

            #expect(store.state.desks.map(\.label) == ["First", "Writing", "Second"])
            #expect(store.focusedDesk?.label == "Writing")
            #expect(store.focusedDesk?.boards.isEmpty == true)
        }
    }

    @Test func createsChatGPTTemplateWithThreeBoards() {
        withStore(desks: [desk("First")]) { store in
            store.createDesk(label: "AI", template: .chatGPTThree)

            #expect(store.focusedDesk?.boards.count == 3)
            #expect(store.focusedDesk?.boards.allSatisfy { $0.currentURLString == "https://chatgpt.com/" } == true)
            #expect(store.focusedDesk?.boards.allSatisfy { $0.width == 520 } == true)
            #expect(store.focusedDesk?.focusedBoardID == store.focusedDesk?.boards.first?.id)
        }
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

    @Test func reorderingBoardKeepsItFocusedAndStopsAtDeskEdge() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.moveFocusedBoardLeft()
            store.moveFocusedBoardLeft()

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
        }
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

    @Test func closingBoardFocusesBoardThatTakesItsPosition() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.closeFocusedBoard()

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[2].id)
        }
    }

    @Test func closingLastBoardFocusesPreviousBoard() {
        let boards = [board("A"), board("B")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.closeFocusedBoard()

            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test func closingUnfocusedBoardKeepsFocus() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.closeBoard(boards[0].id)

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
        }
    }

    @Test func placingHeldBoardInSameDeskUsesFocusedBoardAsTarget() {
        let boards = [board("Held"), board("Target"), board("After")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            store.holdFocusedBoard()
            store.placeHeldBoard()

            #expect(store.heldBoard == nil)
            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test func shiftPPlacesHeldBoardLeftOfFocusedBoard() throws {
        let held = board("Held")
        let targetBoards = [board("Before"), board("Target")]
        let source = desk("Source", boards: [held])
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        try withStore(desks: [source, target]) { store in
            store.isDenMode = true
            store.holdFocusedBoard()
            store.focusNextDesk()
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .shift,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "P",
                    charactersIgnoringModifiers: "p",
                    isARepeat: false,
                    keyCode: 35
                ))

            #expect(KeyboardController.handle(event, store: store))
            #expect(store.heldBoard == nil)
            #expect(store.focusedDesk?.boards.map(\.id) == [targetBoards[0].id, held.id, targetBoards[1].id])
            #expect(store.focusedDesk?.focusedBoardID == held.id)
        }
    }

    @Test func restoringHeldBoardKeepsDeskCreatedWhileHeld() {
        let held = board("Source")
        withStore(desks: [desk("First", boards: [held])]) { store in
            store.holdFocusedBoard()
            store.createDesk(label: "Destination", template: .empty)
            store.restoreHeldBoard()

            #expect(store.heldBoard == nil)
            #expect(store.state.desks.count == 2)
            #expect(store.focusedDesk?.label == "First")
            #expect(store.state.desks[0].boards.first?.id == held.id)
        }
    }

    @Test func placesHeldBoardIntoDifferentDesk() {
        let held = board("Held")
        let targetBoards = [board("Target"), board("After")]
        let source = desk("Source", boards: [held])
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[0].id)
        withStore(desks: [source, target]) { store in
            store.holdFocusedBoard()
            store.focusNextDesk()
            store.placeHeldBoard()

            #expect(store.heldBoard == nil)
            #expect(store.state.desks[0].boards.isEmpty)
            #expect(store.state.desks[1].boards.map(\.id) == [targetBoards[0].id, held.id, targetBoards[1].id])
            #expect(store.focusedDesk?.focusedBoardID == held.id)
        }
    }

    @Test func heldBoardPreventsAnotherHoldUntilPlacedOrRestored() {
        let boards = [board("First"), board("Second")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            store.holdFocusedBoard()
            store.holdFocusedBoard()

            #expect(store.heldBoard?.board.id == boards[0].id)
            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id])
        }
    }

    @Test func persistedStateIncludesHeldBoardAtItsSource() throws {
        let held = board("Held")
        let source = desk("Source", boards: [held])
        var persistedState: DenState?
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) {
            persistedState = $0
        }

        store.holdFocusedBoard()
        let restored = try #require(persistedState)

        #expect(restored.desks[0].boards.map(\.id) == [held.id])
        #expect(restored.desks[0].focusedBoardID == held.id)
    }

    @Test func sourceDeskCannotBeDeletedWhileItsBoardIsHeld() {
        let held = board("Held")
        let source = desk("Source", boards: [held])
        let target = desk("Target")
        withStore(desks: [source, target]) { store in
            store.holdFocusedBoard()

            #expect(!store.canDeleteFocusedDesk)
            store.deleteFocusedDesk()
            #expect(store.state.desks.map(\.id) == [source.id, target.id])
            #expect(store.deskPendingDeletion == nil)
        }
    }

    @Test func deskCreationStopsAtTenDesks() {
        let desks = (1...DenStore.maximumDeskCount).map { desk("Desk \($0)") }
        withStore(desks: desks) { store in
            store.createDesk(label: "Overflow", template: .empty)

            #expect(store.state.desks.count == DenStore.maximumDeskCount)
            #expect(!store.canCreateDesk)
        }
    }

    @Test func deletingEmptyDeskFocusesDeskThatTakesItsPosition() {
        let first = desk("First")
        let empty = desk("Empty")
        let third = desk("Third")
        withStore(desks: [first, empty, third]) { store in
            store.focusDesk(empty.id)
            store.deleteFocusedDesk()

            #expect(store.state.desks.map(\.id) == [first.id, third.id])
            #expect(store.focusedDesk?.id == third.id)
        }
    }

    @Test func deletingDeskWithBoardsRequiresConfirmation() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        withStore(desks: [populated, empty]) { store in
            store.deleteFocusedDesk()

            #expect(store.state.desks.count == 2)
            #expect(store.deskPendingDeletion?.id == populated.id)

            store.focusDesk(empty.id)
            store.confirmDeskDeletion()
            #expect(store.state.desks.map(\.id) == [empty.id])
            #expect(store.focusedDesk?.id == empty.id)
            #expect(store.deskPendingDeletion == nil)
        }
    }

    @Test func cancellingDeskDeletionKeepsBoards() {
        let populated = desk("Populated", boards: [board("Board")])
        let empty = desk("Empty")
        withStore(desks: [populated, empty]) { store in
            store.deleteFocusedDesk()
            store.cancelDeskDeletion()

            #expect(store.state.desks.map(\.id) == [populated.id, empty.id])
            #expect(store.deskPendingDeletion == nil)
        }
    }

    @Test func lastDeskCannotBeDeleted() {
        let onlyDesk = desk("Only")
        withStore(desks: [onlyDesk]) { store in
            store.deleteFocusedDesk()

            #expect(store.state.desks.count == 1)
            #expect(store.deskPendingDeletion == nil)
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

    @Test func persistedStateRestoresDeskAndBoardDataAndFocus() throws {
        let firstBoards = [
            board("One", width: 440, url: "https://one.example/path"),
            board("Two", width: 760, url: "https://two.example/"),
        ]
        let secondBoards = [board("Three", width: 980, url: "https://three.example/query?q=1")]
        let first = desk("First", boards: firstBoards, focusedBoardID: firstBoards[1].id)
        let second = desk("Second", boards: secondBoards, focusedBoardID: secondBoards[0].id)
        var persistedState: DenState?
        let writer = DenStore(state: DenState(desks: [first, second], focusedDeskID: second.id)) {
            persistedState = $0
        }

        writer.focusDesk(first.id)
        let restored = try #require(persistedState)

        #expect(restored == writer.state)
        #expect(restored.desks.map(\.id) == [first.id, second.id])
        #expect(restored.desks[0].boards.map(\.id) == firstBoards.map(\.id))
        #expect(restored.desks.map(\.label) == ["First", "Second"])
        #expect(restored.desks[0].boards.map(\.label) == ["One", "Two"])
        #expect(restored.desks[0].boards.map(\.width) == [440, 760])
        #expect(
            restored.desks[0].boards.map(\.currentURLString) == [
                "https://one.example/path", "https://two.example/",
            ])
        #expect(restored.focusedDeskID == first.id)
        #expect(restored.desks.map(\.focusedBoardID) == [firstBoards[1].id, secondBoards[0].id])
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

    @Test func rejectsBoardFitCountsOutsideCurrentWidthOrWhileHoldingBoard() {
        let boards = [board("First"), board("Second")]
        withStore(desks: [desk("Desk", boards: boards)]) { store in
            store.updateBoardLayout(availableWidth: 1_080, spacing: 10)

            #expect(store.boardWidth(toFit: 3) != nil)
            #expect(store.boardWidth(toFit: 4) == nil)
            #expect(!store.resizeFocusedDeskBoards(toFit: 4))
            #expect(store.focusedDesk?.boards.map(\.width) == [520, 520])

            store.holdFocusedBoard()
            store.showBoardWidthPanel()
            #expect(!store.canResizeFocusedDeskBoards(toFit: 3))
            #expect(store.boardWidthPanelMessage == "Place or restore the Held Board first")
        }
    }

    @Test func oneBoardFitUsesFullWindowBeyondManualResizeLimit() {
        withStore(desks: [desk("Desk", boards: [board("Wide")])]) { store in
            store.updateBoardLayout(availableWidth: 2_480, spacing: 10)

            #expect(store.resizeFocusedDeskBoards(toFit: 1))
            #expect(store.focusedDesk?.boards[0].width == 2_480)
        }
    }

    @Test func commandTOpensBoardPanelFromOverview() throws {
        try withStore(desks: [desk("Desk")]) { store in
            store.showOverview()
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .command,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "t",
                    charactersIgnoringModifiers: "t",
                    isARepeat: false,
                    keyCode: 17
                ))

            #expect(KeyboardController.handle(event, store: store))
            #expect(store.isOpenBoardPanelPresented)
            #expect(!store.isOverviewPresented)
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

    @Test func escapePassesThroughToSheetInput() throws {
        try withStore(desks: [desk("Desk")]) { store in
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

            #expect(!KeyboardController.handle(event, store: store))
            #expect(!store.isDenMode)
        }
    }

    @Test func escapeRestoresHeldBoardBeforeExitingDenMode() throws {
        let held = board("Held")
        try withStore(desks: [desk("Desk", boards: [held])]) { store in
            store.isDenMode = true
            store.holdFocusedBoard()
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

            #expect(KeyboardController.handle(event, store: store))
            #expect(store.heldBoard == nil)
            #expect(store.focusedDesk?.boards.map(\.id) == [held.id])
            #expect(store.isDenMode)

            #expect(KeyboardController.handle(event, store: store))
            #expect(!store.isDenMode)
        }
    }

    @Test func controlCommaTogglesDenMode() throws {
        try withStore(desks: [desk("Desk")]) { store in
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

            #expect(KeyboardController.handle(event, store: store))
            #expect(store.isDenMode)
            #expect(KeyboardController.handle(event, store: store))
            #expect(!store.isDenMode)
        }
    }

    @Test func controlPeriodPassesThroughToSheetInput() throws {
        try withStore(desks: [desk("Desk")]) { store in
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

            #expect(!KeyboardController.handle(event, store: store))
            #expect(!store.isDenMode)
        }
    }

    @Test func commandOptionArrowsNavigateBoardsWithoutEnteringDenMode() throws {
        let boards = [board("First"), board("Second")]
        try withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            let right = try arrowEvent(.rightArrow, modifiers: [.command, .option])
            let left = try arrowEvent(.leftArrow, modifiers: [.command, .option])

            #expect(KeyboardController.handle(right, store: store))
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(!store.isDenMode)

            #expect(KeyboardController.handle(left, store: store))
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(!store.isDenMode)
        }
    }

    @Test func shiftCommandOptionArrowsMoveFocusedBoardWithoutEnteringDenMode() throws {
        let boards = [board("First"), board("Second")]
        try withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            let right = try arrowEvent(.rightArrow, modifiers: [.command, .option, .shift])
            let left = try arrowEvent(.leftArrow, modifiers: [.command, .option, .shift])

            #expect(KeyboardController.handle(right, store: store))
            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id])
            #expect(!store.isDenMode)

            #expect(KeyboardController.handle(left, store: store))
            #expect(store.focusedDesk?.boards.map(\.id) == boards.map(\.id))
            #expect(!store.isDenMode)
        }
    }

    @Test func commandQPassesThroughFromDenMode() throws {
        try withStore(desks: [desk("Desk")]) { store in
            store.isDenMode = true
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

            #expect(!KeyboardController.handle(event, store: store))
            #expect(store.isDenMode)
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

    @Test func denModeMaximizesAndCentersFocusedBoardWithoutChangingDenState() throws {
        let current = board("Current", width: 520)
        try withStore(desks: [desk("Desk", boards: [current])]) { store in
            store.isDenMode = true
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

            #expect(KeyboardController.handle(maximize, store: store))
            #expect(store.maximizedBoardID == current.id)
            let requestAfterMaximize = store.centerFocusedBoardRequest
            #expect(KeyboardController.handle(center, store: store))
            #expect(store.centerFocusedBoardRequest == requestAfterMaximize + 1)
            #expect(KeyboardController.handle(maximize, store: store))
            #expect(store.maximizedBoardID == nil)
            #expect(store.state == stateBeforeCommands)
        }
    }

    @Test func denModeBoardWidthPanelAcceptsOnlyFitSelectionKeys() throws {
        let boards = [board("First"), board("Second")]
        try withStore(desks: [desk("Desk", boards: boards)]) { store in
            store.isDenMode = true
            store.updateBoardLayout(availableWidth: 1_180, spacing: 10)
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

            #expect(KeyboardController.handle(open, store: store))
            #expect(store.isBoardWidthPanelPresented)
            #expect(KeyboardController.handle(ignoredMovement, store: store))
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(KeyboardController.handle(select, store: store))
            #expect(!store.isBoardWidthPanelPresented)
            #expect(store.isDenMode)
            #expect(
                store.focusedDesk?.boards.allSatisfy {
                    abs($0.width - 386.666_666_666_666_7) < 0.001
                } == true)
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
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ))
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentURLString: url)
    }
}
