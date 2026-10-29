import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@MainActor
struct DrawerPlacementTests {
    @Test(arguments: [false, true])
    func missingItemOrDestinationDoesNotCreateDiscardOrNotify(missingItem: Bool) throws {
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let desk = DeskState(label: "Desk", boards: [])
        let initial = DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id, drawerItems: [item]))
        let shared = DenStateStore.make(initialState: initial)
        let persist: (DenState) -> Bool = { _ in
            Issue.record("Failed placement must not save")
            return true
        }
        let items = DrawerItems(store: shared.reader, writer: shared.writer, persist: persist)
        let creation = BoardCreation(
            store: shared.reader,
            writer: shared.writer,
            recents: Recents(store: shared.reader, writer: shared.writer, persist: persist),
            persist: persist,
            directoryExists: { _ in true })
        let placement = DrawerPlacement(store: shared.reader, writer: shared.writer, creation: creation, items: items)

        let result = placement.place(
            .init(
                itemID: missingItem ? UUID() : item.id, width: 640, searchEngine: .google,
                target: .init(presentedDeskID: desk.id, deskID: missingItem ? desk.id : DeskID())),
            notifyBoard: { _ in Issue.record("Failed placement must not notify Native") },
            notifyDrawer: { _ in Issue.record("Failed placement must not notify Drawer") })

        #expect(result == nil)
        #expect(shared.store.snapshot == initial)
    }

    @Test(arguments: [false, true])
    func successfulCreationConsumesOnlyRequestedItemAfterInsertionAndDoesNotRecordDiscardHistory(saveSucceeds: Bool)
        throws
    {
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let other = DrawerItem(url: try #require(URL(string: "https://other.example/")))
        let anchor = BoardState(label: "Anchor", width: 520, currentSheetURL: nil)
        let first = DeskState(label: "Presented", boards: [])
        let destination = DeskState(label: "Destination", boards: [anchor], focusedBoardID: anchor.id)
        var initial = DenSharedState(
            den: DenState(
                desks: [first, destination], focusedDeskID: first.id, drawerItems: [item, other]))
        initial.recentlyDiscardedDrawerItems = [other]
        let shared = DenStateStore.make(initialState: initial)
        var events: [String] = []
        let persist: (DenState) -> Bool = { state in
            #expect(state.desks[1].boards.count == 2)
            events.append(state.drawerItems.contains(item) ? "saveWithItem" : "saveWithoutItem")
            return saveSucceeds
        }
        let items = DrawerItems(store: shared.reader, writer: shared.writer, persist: persist)
        let creation = BoardCreation(
            store: shared.reader,
            writer: shared.writer,
            recents: Recents(store: shared.reader, writer: shared.writer, persist: persist),
            persist: persist,
            directoryExists: { _ in true })
        let placement = DrawerPlacement(store: shared.reader, writer: shared.writer, creation: creation, items: items)

        let result = try #require(
            placement.place(
                .init(
                    itemID: item.id, width: 720, searchEngine: .google,
                    target: .init(presentedDeskID: first.id, deskID: destination.id, afterBoardID: anchor.id)),
                notifyBoard: { notice in
                    switch notice {
                    case .willInsert:
                        #expect(shared.store.snapshot.den.drawerItems == [item, other])
                        #expect(shared.store.snapshot.den.desks[1].boards == [anchor])
                        events.append("attach")
                    case .didInsert:
                        #expect(shared.store.snapshot.den.drawerItems == [item, other])
                        events.append("inserted")
                    default: break
                    }
                },
                notifyDrawer: { notice in
                    guard case .didDiscard(let id, let previous, let advancesPeek, let focusNext) = notice else {
                        Issue.record("Unexpected placement notice")
                        return
                    }
                    #expect(id == item.id)
                    #expect(previous == [item, other])
                    #expect(!advancesPeek)
                    #expect(focusNext)
                    #expect(shared.store.snapshot.den.drawerItems == [other])
                    events.append("remove")
                }))

        #expect(events == ["attach", "inserted", "saveWithItem", "remove", "saveWithoutItem"])
        let state = shared.store.snapshot
        #expect(state.den.desks[0] == first)
        #expect(state.den.desks[1].boards.map(\.id) == [anchor.id, result])
        #expect(state.den.desks[1].boards[1].width == 720)
        #expect(state.den.desks[1].boards[1].currentSheetURL == item.url)
        #expect(state.den.desks[1].focusedBoardID == result)
        #expect(state.recentlyDiscardedDrawerItems == [other])
        #expect(state.recentItems == (saveSucceeds ? [.url(try #require(item.url))] : []))
    }
    @Test func terminalPlacementKeepsItsIdentitySessionAndRecentInput() throws {
        // Arrange
        let session = TerminalBoardState.zmx(
            ZmxBoardState(sessionName: "project-child", workingDirectory: "/work", rootSessionName: "project"))
        let item = DrawerItem(terminal: session, title: "Project")
        var initial = DenSharedState(den: .sample)
        initial.den.drawerItems = [item]
        let shared = DenStateStore.make(initialState: initial)
        let items = DrawerItems(store: shared.reader, writer: shared.writer)
        let creation = BoardCreation(
            store: shared.reader, writer: shared.writer,
            recents: Recents(store: shared.reader, writer: shared.writer), directoryExists: { _ in true })
        let placement = DrawerPlacement(store: shared.reader, writer: shared.writer, creation: creation, items: items)

        // Act
        let id = try #require(
            placement.place(
                .init(
                    itemID: item.id, width: 720, searchEngine: .google,
                    target: .init(presentedDeskID: initial.den.focusedDeskID)), notifyBoard: { _ in },
                notifyDrawer: { _ in }))

        // Assert
        let board = try #require(shared.store.snapshot.den.desks[0].boards.first(where: { $0.id == id }))
        #expect(id == BoardID(item.id))
        #expect(board.kind == .terminal(session))
        #expect(board.label == "Project")
        #expect(board.width == 720)
        #expect(shared.store.snapshot.den.drawerItems.isEmpty)
        #expect(shared.store.snapshot.recentItems == [.zmx(sessionName: "project-child")])
        #expect(shared.store.snapshot.recentlyDiscardedDrawerItems.isEmpty)
    }
}
