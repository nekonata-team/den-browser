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
            #expect(store.state.desks[1].boards.map(\.id) == [targetBoards[0].id, targetBoards[1].id, moved.id, targetBoards[2].id])
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

    @Test func placingHeldBoardInSameDeskUsesFocusedBoardAsTarget() {
        let boards = [board("Held"), board("Target"), board("After")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            store.holdFocusedBoard()
            store.placeHeldBoard()

            #expect(store.heldBoardID == nil)
            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test func cancelingHoldKeepsDeskCreatedAfterHold() {
        let held = board("Source")
        withStore(desks: [desk("First", boards: [held])]) { store in
            store.holdFocusedBoard()
            store.createDesk(label: "Destination", template: .empty)
            store.cancelHeldBoard()

            #expect(store.heldBoardID == nil)
            #expect(store.state.desks.count == 2)
            #expect(store.focusedDesk?.label == "Destination")
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

            #expect(store.heldBoardID == nil)
            #expect(store.state.desks[0].boards.isEmpty)
            #expect(store.state.desks[1].boards.map(\.id) == [targetBoards[0].id, held.id, targetBoards[1].id])
            #expect(store.focusedDesk?.focusedBoardID == held.id)
        }
    }

    @Test func persistedStateRestoresDeskAndBoardDataAndFocus() throws {
        let firstBoards = [board("One", width: 440, url: "https://one.example/path"), board("Two", width: 760, url: "https://two.example/")]
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
        #expect(restored.state.desks[0].boards.map(\.currentURLString) == ["https://one.example/path", "https://two.example/"])
        #expect(restored.state.focusedDeskID == first.id)
        #expect(restored.state.desks.map(\.focusedBoardID) == [firstBoards[1].id, secondBoards[0].id])
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
