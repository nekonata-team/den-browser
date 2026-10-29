import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@MainActor
struct DrawerTransferTests {
    @Test(arguments: [false, true])
    func moveAtomicallyTransfersContentAndIdentityWithoutRemovalHistory(terminal: Bool) throws {
        // Arrange
        let url = try #require(URL(string: "https://example.com/work"))
        let board =
            terminal
            ? BoardState(label: "Work", width: 640, workingDirectory: "/tmp")
            : BoardState(label: "Work", width: 640, currentSheetURL: url)
        let neighbor = BoardState(label: "Neighbor", width: 520, currentSheetURL: url)
        let desk = DeskState(
            label: "Desk", boards: [board, neighbor], focusedBoardID: board.id, anchorBoardID: board.id)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var events: [String] = []
        let transfer = DrawerTransfer(
            store: shared.reader, writer: shared.writer,
            persist: { state in
                #expect(state.desks[0].boards == [neighbor])
                #expect(state.drawerItems.first?.id == board.id.rawValue)
                events.append("save")
                return true
            })

        // Act
        let id = transfer.move(board.id) { notice in
            switch notice {
            case .willMove:
                #expect(shared.store.snapshot.den.desks[0] == desk)
                #expect(shared.store.snapshot.den.drawerItems.isEmpty)
                events.append("prepare")
            case .didMove:
                #expect(shared.store.snapshot.den.desks[0].boards == [neighbor])
                #expect(shared.store.snapshot.den.drawerItems.first?.id == board.id.rawValue)
                events.append("moved")
            }
        }

        // Assert
        let item = try #require(shared.store.snapshot.den.drawerItems.first)
        #expect(id == board.id.rawValue)
        #expect(item.title == "Work")
        #expect(terminal ? item.terminal == .shell(workingDirectory: "/tmp") : item.url == url)
        #expect(shared.store.snapshot.den.desks[0].focusedBoardID == neighbor.id)
        #expect(shared.store.snapshot.den.desks[0].anchorBoardID == nil)
        #expect(shared.store.snapshot.recentlyRemovedBoards.isEmpty)
        #expect(shared.store.snapshot.recentlyDiscardedDrawerItems.isEmpty)
        #expect(events == ["prepare", "moved", "save"])
    }

    @Test func groupedUnsupportedAndMissingBoardsRemainUntouched() throws {
        // Arrange
        let primary = BoardState(label: "Web", width: 640, currentSheetURL: URL(string: "https://example.com"))
        var side = BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
        side.role = .sideBoard(targetBoardID: primary.id)
        let tutorial = BoardState(width: 520, tutorial: TutorialBoardState())
        let empty = BoardState(label: "Empty", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: [primary, side, tutorial, empty])
        let initial = DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id))
        let shared = DenStateStore.make(initialState: initial)
        let transfer = DrawerTransfer(
            store: shared.reader, writer: shared.writer,
            persist: { _ in
                Issue.record("Rejected move must not save")
                return true
            })

        // Act / Assert
        for id in [primary.id, side.id, tutorial.id, empty.id, BoardID()] {
            #expect(transfer.move(id, notify: { _ in Issue.record("Rejected move must not notify") }) == nil)
            #expect(shared.store.snapshot == initial)
        }
    }
}
