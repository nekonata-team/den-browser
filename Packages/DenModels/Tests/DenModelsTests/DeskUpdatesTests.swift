import DenApplication
import DenDomain
import DenModels
import Testing

@MainActor
struct DeskUpdatesTests {
    @Test(arguments: ["  Renamed  ", "   "])
    func renameNotifiesBeforeSavingEvenForEmptyInput(label: String) {
        let desk = DeskState(label: "Original", boards: [])
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let expectedLabel = label == "   " ? desk.label : "Renamed"
        var events: [String] = []
        let updates = DeskUpdates(
            store: shared.reader, writer: shared.writer,
            persist: { state in
                #expect(state.desks[0].label == expectedLabel)
                events.append("save")
                return false
            })

        updates.rename(desk.id, to: label) {
            #expect(shared.store.snapshot.den.desks[0].label == expectedLabel)
            events.append("notify")
        }

        #expect(events == ["notify", "save"])
        #expect(shared.store.snapshot.den.desks[0].label == expectedLabel)
    }

    @Test func scrollSavesOnlyChangedOffsetsAndDefersDuringDrag() {
        let desk = DeskState(label: "Desk", boards: [])
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var savedOffsets: [Double?] = []
        let updates = DeskUpdates(
            store: shared.reader, writer: shared.writer,
            persist: { state in
                savedOffsets.append(state.desks[0].scrollOffsetX)
                return true
            })

        updates.saveScrollOffset(nil, for: desk.id)
        updates.saveScrollOffset(120, for: desk.id)
        updates.saveScrollOffset(120, for: desk.id)
        updates.saveScrollOffset(nil, for: desk.id)
        shared.writer.update { $0.activeDrag = .desk(desk.id) }
        updates.saveScrollOffset(240, for: desk.id)

        #expect(savedOffsets == [120, nil])
        #expect(shared.store.snapshot.den.desks[0].scrollOffsetX == 240)
    }

    @Test func acceptedSelectionRecordsSharedFocusWithoutSavingAndMissingTargetsDoNothing() {
        let first = DeskState(label: "First", boards: [])
        let second = DeskState(label: "Second", boards: [])
        let shared = DenStateStore.make(
            initialState: DenSharedState(
                den: DenState(
                    desks: [first, second], focusedDeskID: first.id)))
        let updates = DeskUpdates(
            store: shared.reader, writer: shared.writer,
            persist: { _ in
                Issue.record("These updates must not save")
                return true
            })

        updates.recordPresentedDesk(second.id)
        #expect(shared.store.snapshot.den.focusedDeskID == second.id)
        let selected = shared.store.snapshot
        let missing = DeskID()
        updates.recordPresentedDesk(missing)
        updates.rename(missing, to: "Missing") { Issue.record("Missing target must not notify") }
        updates.saveScrollOffset(120, for: missing)

        #expect(shared.store.snapshot == selected)
    }
}
