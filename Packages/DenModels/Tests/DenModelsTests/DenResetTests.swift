import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@MainActor
struct DenResetTests {
    @Test(arguments: ["board", "desk", "none"])
    func resetPreservesCleanupOrderAndKeepsRecentsAndPresets(drag: String) throws {
        // Arrange
        let board = BoardState(label: "Old", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Old", boards: [board], focusedBoardID: board.id)
        let item = DrawerItem(url: try #require(URL(string: "https://example.com")))
        var initial = DenSharedState(
            den: DenState(desks: [desk], focusedDeskID: desk.id, drawerItems: [item]),
            deskPresets: [.init(label: "Keep", desk: desk)], recentItems: [.search("keep")])
        if drag == "board" { initial.activeDrag = .board(board.id) }
        if drag == "desk" { initial.activeDrag = .desk(desk.id) }
        initial.notifications = [DenNotification(title: "Old", body: "", boardID: board.id)]
        initial.recentlyRemovedBoards = [
            RecentlyRemovedBoard(board: board, sourceDeskID: desk.id, sourceBoardIndex: .init(rawValue: 0))
        ]
        initial.recentlyDiscardedDrawerItems = [item]
        let shared = DenStateStore.make(initialState: initial)
        var events: [String] = []
        var saved: DenState?
        let reset = DenReset(
            store: shared.reader, writer: shared.writer,
            persist: { state in
                #expect(shared.store.snapshot.notifications.isEmpty)
                #expect(shared.store.snapshot.activeDrag == nil)
                saved = state
                events.append("save")
                return false
            })

        // Act
        reset.perform { notice in
            switch notice {
            case .prepare:
                #expect(shared.store.snapshot == initial)
                events.append("prepare")
            case .cancelDrag(let current):
                #expect(current == initial.activeDrag)
                #expect(shared.store.snapshot.den == initial.den)
                events.append("cancel")
            case .stateReplaced(let id):
                #expect(shared.store.snapshot.den.focusedDeskID == id)
                #expect(shared.store.snapshot.den.desks.first?.id == id)
                #expect(shared.store.snapshot.activeDrag == initial.activeDrag)
                events.append("state")
            case .clearInputRequests:
                #expect(shared.store.snapshot.activeDrag == nil)
                #expect(!shared.store.snapshot.recentlyRemovedBoards.isEmpty)
                events.append("input")
            case .clearWindowReferences:
                #expect(shared.store.snapshot.recentlyRemovedBoards.isEmpty)
                #expect(shared.store.snapshot.recentlyDiscardedDrawerItems.isEmpty)
                events.append("references")
            case .finished:
                #expect(events.last == "save")
                events.append("finished")
            }
        }

        // Assert
        let expected =
            ["prepare"] + (drag == "none" ? [] : ["cancel"])
            + ["state", "input", "references", "save", "finished"]
        #expect(events == expected)
        #expect(shared.store.snapshot.den.desks.count == 1)
        #expect(shared.store.snapshot.den.desks[0].label == "Main")
        #expect(shared.store.snapshot.den.desks[0].boards.isEmpty)
        #expect(shared.store.snapshot.den.drawerItems.isEmpty)
        #expect(shared.store.snapshot.recentItems == initial.recentItems)
        #expect(shared.store.snapshot.deskPresets == initial.deskPresets)
        #expect(saved == shared.store.snapshot.den)
    }
}
