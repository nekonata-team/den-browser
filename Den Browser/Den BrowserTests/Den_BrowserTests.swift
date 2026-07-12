import AppKit
import Foundation
import Testing
@testable import Den_Browser

@MainActor
struct Den_BrowserTests {
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

    @Test func placingCutBoardInSameDeskUsesFocusedBoardAsTarget() {
        let boards = [board("Cut"), board("Target"), board("After")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            store.cutFocusedBoard()
            store.placeCutBoard()

            #expect(store.cutBoard == nil)
            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test func restoringCutBoardKeepsDeskCreatedAfterCut() {
        let cut = board("Source")
        withStore(desks: [desk("First", boards: [cut])]) { store in
            store.cutFocusedBoard()
            store.createDesk(label: "Destination", template: .empty)
            store.restoreCutBoard()

            #expect(store.cutBoard == nil)
            #expect(store.state.desks.count == 2)
            #expect(store.focusedDesk?.label == "First")
            #expect(store.state.desks[0].boards.first?.id == cut.id)
        }
    }

    @Test func placesCutBoardIntoDifferentDesk() {
        let cut = board("Cut")
        let targetBoards = [board("Target"), board("After")]
        let source = desk("Source", boards: [cut])
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[0].id)
        withStore(desks: [source, target]) { store in
            store.cutFocusedBoard()
            store.focusNextDesk()
            store.placeCutBoard()

            #expect(store.cutBoard == nil)
            #expect(store.state.desks[0].boards.isEmpty)
            #expect(store.state.desks[1].boards.map(\.id) == [targetBoards[0].id, cut.id, targetBoards[1].id])
            #expect(store.focusedDesk?.focusedBoardID == cut.id)
        }
    }

    @Test func cutBoardPreventsAnotherCutUntilPlacedOrRestored() {
        let boards = [board("First"), board("Second")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            store.cutFocusedBoard()
            store.cutFocusedBoard()

            #expect(store.cutBoard?.board.id == boards[0].id)
            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id])
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

    @Test func deletingDeskWithBoardsOrLastDeskDoesNothing() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        withStore(desks: [populated, empty]) { store in
            store.deleteFocusedDesk()
            #expect(store.state.desks.count == 2)

            store.focusDesk(empty.id)
            store.deleteFocusedDesk()
            #expect(store.state.desks.count == 1)

            store.deleteFocusedDesk()
            #expect(store.state.desks.count == 1)
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
        let url = temporaryPersistenceURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = DenStore(state: DenState(desks: [first, second], focusedDeskID: second.id), persistenceURL: url)

        writer.focusDesk(first.id)
        let restored = DenStore(persistenceURL: url)

        #expect(restored.state == writer.state)
        #expect(restored.state.desks.map(\.id) == [first.id, second.id])
        #expect(restored.state.desks[0].boards.map(\.id) == firstBoards.map(\.id))
        #expect(restored.state.desks.map(\.label) == ["First", "Second"])
        #expect(restored.state.desks[0].boards.map(\.label) == ["One", "Two"])
        #expect(restored.state.desks[0].boards.map(\.width) == [440, 760])
        #expect(
            restored.state.desks[0].boards.map(\.currentURLString) == [
                "https://one.example/path", "https://two.example/",
            ])
        #expect(restored.state.focusedDeskID == first.id)
        #expect(restored.state.desks.map(\.focusedBoardID) == [firstBoards[1].id, secondBoards[0].id])
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

    @Test func webPointerFocusSuppressesExplicitActivation() {
        var state = PointerFocusState()

        let handledPointer = state.handlePointerDown()
        let activatedAfterPointer = state.updateFocus(true)
        #expect(handledPointer)
        #expect(!activatedAfterPointer)
        _ = state.updateFocus(false)
        let activatedAfterKeyboardFocus = state.updateFocus(true)
        #expect(activatedAfterKeyboardFocus)
    }

    @Test func disabledWebPointerFocusHasNoCallbackOrSuppression() {
        var state = PointerFocusState()
        _ = state.handlePointerDown()
        state.updateEnabled(false)

        let handledPointer = state.handlePointerDown()
        #expect(!handledPointer)
        state.updateEnabled(true)
        let activated = state.updateFocus(true)
        #expect(activated)
    }

    private func withStore(desks: [DeskState], body: (DenStore) throws -> Void) rethrows {
        let url = temporaryPersistenceURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = DenStore(state: DenState(desks: desks, focusedDeskID: desks[0].id), persistenceURL: url)
        try body(store)
    }

    private func temporaryPersistenceURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "den-browser-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "den-state.json")
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentURLString: url)
    }
}
