import DenApplication
import DenDomain
import Testing

@MainActor
struct DeskMovementTests {
    @Test func dragPreviewRestoresOrderWithoutSavingOrLosingUpdatedData() {
        // Arrange
        let first = DeskState(label: "First", boards: [])
        let second = DeskState(label: "Second", boards: [])
        let added = DeskState(label: "Added", boards: [])
        var initial = DenSharedState(den: DenState(desks: [first, second, added], focusedDeskID: second.id))
        initial.activeDrag = .desk(first.id)
        let shared = DenStateStore.make(initialState: initial)
        let movement = DeskMovement(
            store: shared.store, writer: shared.writer,
            persist: { _ in
                Issue.record("Preview/restore must not save")
                return true
            })

        // Act
        movement.preview(first.id, to: .init(rawValue: 1))
        shared.writer.update { $0.den.desks[0].label = "Updated" }
        movement.restoreOrder([first.id, second.id])

        // Assert
        #expect(shared.store.snapshot.den.desks.map(\.id) == [first.id, second.id, added.id])
        #expect(shared.store.snapshot.den.desks[1].label == "Updated")
        #expect(shared.store.snapshot.den.focusedDeskID == second.id)
    }

    @Test func finishingDeskDragClearsDragBeforeSaving() {
        // Arrange
        var initial = DenSharedState(den: .sample)
        initial.activeDrag = .desk(initial.den.focusedDeskID)
        let shared = DenStateStore.make(initialState: initial)
        var saves = 0
        let movement = DeskMovement(
            store: shared.store, writer: shared.writer,
            persist: { _ in
                #expect(shared.store.snapshot.activeDrag == nil)
                saves += 1
                return true
            })

        // Act
        movement.finishDrag()

        // Assert
        #expect(shared.store.snapshot.activeDrag == nil)
        #expect(saves == 1)
    }

    @Test(arguments: [false, true])
    func committedMoveIsRejectedDuringDrag(dragging: Bool) {
        // Arrange
        let first = DeskState(label: "First", boards: [])
        let second = DeskState(label: "Second", boards: [])
        var initial = DenSharedState(den: DenState(desks: [first, second], focusedDeskID: first.id))
        if dragging { initial.activeDrag = .desk(first.id) }
        let shared = DenStateStore.make(initialState: initial)
        var saves = 0
        let movement = DeskMovement(
            store: shared.store, writer: shared.writer,
            persist: { _ in
                saves += 1
                return true
            })

        // Act
        movement.move(first.id, by: 1)

        // Assert
        #expect(
            shared.store.snapshot.den.desks.map(\.id) == (dragging ? [first.id, second.id] : [second.id, first.id]))
        #expect(shared.store.snapshot.den.focusedDeskID == first.id)
        #expect(saves == (dragging ? 0 : 1))
    }
}
