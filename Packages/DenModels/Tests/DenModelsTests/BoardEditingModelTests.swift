import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@MainActor
struct BoardEditingModelTests {
    @Test func editingReadsTheCurrentWindowTargetAndPreservesNativeNotificationOrder() {
        let first = BoardState(label: "First", width: 520, currentSheetURL: URL(string: "https://first.example/"))
        let second = BoardState(label: "Second", width: 520, currentSheetURL: URL(string: "https://second.example/"))
        let desk = DeskState(label: "Desk", boards: [first, second], focusedBoardID: first.id)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var target = first.id
        var events: [String] = []
        let model = BoardEditingModel(
            state: shared.store,
            updates: BoardUpdates(
                store: shared.reader, writer: shared.writer,
                persist: { _ in
                    events.append("save")
                    return true
                }),
            recents: Recents(store: shared.reader, writer: shared.writer),
            movement: BoardMovement(state: shared.reader, writer: shared.writer),
            focusedBoard: { shared.store.snapshot.den.desks[0].boards.first { $0.id == target } },
            essentials: { [] }, searchEngine: { .google }, finishEditing: { events.append("finish") },
            loadURL: { id, url in
                #expect(id == second.id)
                #expect(url.absoluteString == "https://updated.example/")
                events.append("load")
            }, restoreInput: {}, duplicateZmx: { _ in }, focus: { target = $0 }, center: {})

        model.renameFocusedBoard(to: " Renamed ")
        target = second.id
        #expect(model.navigateFocusedBoard(urlString: "updated.example"))
        #expect(events == ["finish", "save", "finish", "save", "load"])
        #expect(model.focusedBoard?.id == second.id)
        #expect(shared.store.snapshot.den.desks[0].boards[0].customLabel == "Renamed")
        #expect(shared.store.snapshot.den.desks[0].boards[0].currentSheetURL == first.currentSheetURL)

        target = BoardID()
        model.renameFocusedBoard(to: "Missing")
        #expect(!model.navigateFocusedBoard(urlString: "unavailable.example"))
        #expect(events.count == 5)
    }
}
