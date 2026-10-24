import DenApplication
import DenDomain
import DenModels
import Foundation
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
            store: shared.reader, writer: shared.writer,
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
    @Test func webMetadataInvalidatesBeforeSavingAndTitleOnlyDoesNotSave() {
        // Arrange
        let board = BoardState(label: "Initial", width: 520, currentSheetURL: URL(string: "https://example.com/")!)
        let desk = DeskState(label: "Desk", boards: [board])
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var events: [String] = []
        let updates = BoardUpdates(
            store: shared.reader, writer: shared.writer,
            persist: { _ in
                events.append("save")
                return true
            })
        let recents = Recents(store: shared.reader, writer: shared.writer)

        // Act
        updates.updateWeb(board.id, url: URL(string: "https://example.com/next")!, title: "Next", recents: recents) {
            events.append("invalidate")
        }
        updates.updateWeb(board.id, url: nil, title: "Latest", recents: recents) { events.append("unexpected") }

        // Assert
        #expect(events == ["invalidate", "save"])
        #expect(shared.store.snapshot.den.desks[0].boards[0].label == "Latest")
        #expect(shared.store.snapshot.den.desks[0].boards[0].currentSheetURL?.path == "/next")
    }

    @Test func terminalDirectorySavesOnceWhileTitleAndRepeatedDirectoryDoNot() {
        // Arrange
        let board = BoardState(label: "Initial", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [board])
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var saves = 0
        let updates = BoardUpdates(
            store: shared.reader, writer: shared.writer,
            persist: { _ in
                saves += 1
                return true
            })

        // Act
        updates.updateTerminal(board.id, workingDirectory: "/tmp/project", title: "Project")
        updates.updateTerminal(board.id, workingDirectory: "/tmp/project", title: "Current")
        updates.updateTerminal(board.id, workingDirectory: "", title: "")

        // Assert
        #expect(saves == 1)
        #expect(shared.store.snapshot.den.desks[0].boards[0].terminalWorkingDirectory == "/tmp/project")
        #expect(shared.store.snapshot.den.desks[0].boards[0].label == "Current")
    }
}
