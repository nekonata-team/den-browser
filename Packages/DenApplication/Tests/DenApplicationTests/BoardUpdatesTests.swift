import DenApplication
import DenDomain
import Testing

@MainActor
struct BoardUpdatesTests {
    @Test func editingNotifiesBeforeSaveAndRetainsChangesOnSaveFailure() {
        // Arrange
        let board = BoardState(label: "Board", width: 520, zmxSessionName: "session")
        let desk = DeskState(label: "Desk", boards: [board])
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var events: [String] = []
        let updates = BoardUpdates(
            store: shared.store, writer: shared.writer,
            persist: { _ in
                events.append("save")
                return false
            })
        // Act
        updates.recordZmxRoot("root", for: board.id)
        updates.recordZmxRoot("root", for: board.id)
        updates.rename(board.id, to: " Custom ") { events.append("rename") }
        let url = updates.navigate(board.id, to: "example.com", searchEngine: .google) { events.append("navigate") }
        // Assert
        #expect(events == ["save", "rename", "save", "navigate", "save"])
        #expect(shared.store.snapshot.den.desks[0].boards[0].customLabel == "Custom")
        #expect(shared.store.snapshot.den.desks[0].boards[0].zmxRootSessionName == "root")
        #expect(url?.absoluteString == "https://example.com/")
    }
}
