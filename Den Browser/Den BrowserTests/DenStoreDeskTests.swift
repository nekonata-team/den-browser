import AppKit
import Foundation
import Testing
@testable import Den_Browser

@MainActor
struct DenStoreDeskTests {

    @Test func createsEmptyDeskAfterFocusedDesk() {
        withStore(desks: [desk("First"), desk("Second")]) { store in
            store.createDesk(label: "  Writing  ", preset: .empty)

            #expect(store.state.desks.map(\.label) == ["First", "Writing", "Second"])
            #expect(store.focusedDesk?.label == "Writing")
            #expect(store.focusedDesk?.boards.isEmpty == true)
        }
    }

    @Test func createsChatGPTPresetWithThreeBoards() {
        withStore(desks: [desk("First")]) { store in
            store.createDesk(label: "AI", preset: .chatGPT)

            #expect(store.focusedDesk?.boards.count == 3)
            #expect(
                store.focusedDesk?.boards.allSatisfy {
                    $0.currentSheetURL == URL(string: "https://chatgpt.com/")
                } == true)
            #expect(store.focusedDesk?.boards.allSatisfy { $0.width == 520 } == true)
            #expect(store.focusedDesk?.focusedBoardID == store.focusedDesk?.boards.first?.id)
        }
    }

    @Test func createsGeminiPresetWithThreeBoards() {
        withStore(desks: [desk("First")]) { store in
            store.createDesk(label: "Gemini", preset: .gemini)

            #expect(store.focusedDesk?.boards.count == 3)
            #expect(
                store.focusedDesk?.boards.allSatisfy {
                    $0.currentSheetURL == URL(string: "https://gemini.google.com/") && $0.width == 520
                } == true)
        }
    }

    @Test func deskCreationStopsAtTenDesks() {
        let desks = (1...DenStore.maximumDeskCount).map { desk("Desk \($0)") }
        withStore(desks: desks) { store in
            store.createDesk(label: "Overflow", preset: .empty)

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

    @Test func deskDragReordersPersistedDesksWithoutChangingTheirContents() {
        let firstBoard = board("First Board")
        let secondBoard = board("Second Board")
        let first = desk("First", boards: [firstBoard], focusedBoardID: firstBoard.id)
        let second = desk("Second", boards: [secondBoard], focusedBoardID: secondBoard.id)
        let third = desk("Third")
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [first, second, third], focusedDeskID: first.id),
            onSave: { savedState = $0 })

        #expect(store.beginDeskDrag(second.id))
        store.previewDeskMove(second.id, to: 2)
        store.updateBoard(
            boardID: secondBoard.id,
            url: URL(string: "https://updated.example/"),
            title: "Updated title")

        #expect(savedState == nil)

        store.finishDeskDrag()

        #expect(store.state.desks.map(\.id) == [first.id, third.id, second.id])
        #expect(store.focusedDesk?.id == first.id)
        #expect(store.state.desks[2].boards.map(\.id) == [secondBoard.id])
        #expect(store.state.desks[2].focusedBoardID == secondBoard.id)
        #expect(store.state.desks[2].boards[0].currentSheetURL == URL(string: "https://updated.example/"))
        #expect(store.state.desks[2].boards[0].label == "Updated title")
        #expect(savedState == store.state)

        store.previewDeskMove(second.id, to: 2)
        #expect(store.state.desks.map(\.id) == [first.id, third.id, second.id])
    }

    @Test func cancellingDeskDragPersistsRestoredOrderAfterBoardUpdate() {
        let firstBoard = board("First Board")
        let secondBoard = board("Second Board")
        let first = desk("First", boards: [firstBoard], focusedBoardID: firstBoard.id)
        let second = desk("Second", boards: [secondBoard], focusedBoardID: secondBoard.id)
        let third = desk("Third")
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [first, second, third], focusedDeskID: first.id),
            onSave: { savedState = $0 })

        #expect(store.beginDeskDrag(second.id))
        store.previewDeskMove(second.id, to: 2)
        store.updateBoard(
            boardID: secondBoard.id,
            url: URL(string: "https://updated.example/"),
            title: "Updated title")
        #expect(savedState == nil)

        store.restoreDeskOrder([first.id, second.id, third.id])
        store.finishDeskDrag()

        #expect(store.state.desks.map(\.id) == [first.id, second.id, third.id])
        #expect(store.state.desks[1].boards[0].currentSheetURL == URL(string: "https://updated.example/"))
        #expect(store.state.desks[1].boards[0].label == "Updated title")
        #expect(savedState == store.state)
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

    @Test func deskRenaming() {
        let b1 = board("Google")
        let desk1 = desk("Main", boards: [b1], focusedBoardID: b1.id)

        withStore(desks: [desk1]) { store in
            // 1. Enter Den Mode, show rename panel
            store.isDenMode = true
            store.showRenameDeskPanel()
            #expect(store.isRenameDeskPanelPresented)

            // 2. Rename the desk to a custom name
            store.renameFocusedDesk(to: "Web Search")
            #expect(!store.isRenameDeskPanelPresented)
            #expect(store.focusedDesk?.label == "Web Search")

            // 3. Rename with empty name should be ignored (keep old name)
            store.showRenameDeskPanel()
            store.renameFocusedDesk(to: "")
            #expect(!store.isRenameDeskPanelPresented)
            #expect(store.focusedDesk?.label == "Web Search")
        }
    }

    private func withStore(desks: [DeskState], body: (DenStore) throws -> Void) rethrows {
        let store = DenStore(state: DenState(desks: desks, focusedDeskID: desks[0].id))
        try body(store)
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
