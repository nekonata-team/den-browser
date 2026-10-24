import DenApplication
import DenDomain
import Testing

nonisolated struct SharedOperationsWithoutActorTests {
    private final class State {
        var snapshot: DenSharedState

        init(_ snapshot: DenSharedState) { self.snapshot = snapshot }
    }

    @Test func notificationsUseCallerOwnedStateWithoutAnActorOrModel() throws {
        // Arrange
        let board = BoardState(width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [board])
        let state = State(DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let reader = DenStateReader { state.snapshot }
        let writer = DenStateWriter { mutation in mutation(&state.snapshot) }
        let operations = NotificationOperations(store: reader, writer: writer)

        // Act
        let notification = try #require(operations.record(title: nil, body: "Message", boardID: board.id))
        let source = operations.prepareOpen(notification)

        // Assert
        #expect(source == board.id)
        #expect(state.snapshot.notifications.first?.isRead == true)
        #expect(operations.unreadCount() == 0)
    }

    @Test func creationCommitsBeforeCompletionAndSavesWithoutAModel() throws {
        // Arrange
        let desk = DeskState(label: "Desk", boards: [])
        let state = State(DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let reader = DenStateReader { state.snapshot }
        let writer = DenStateWriter { mutation in mutation(&state.snapshot) }
        let board = BoardState(width: 520, workingDirectory: "/tmp")
        var events: [String] = []
        let creation = BoardCreation(
            store: reader, writer: writer, recents: Recents(store: reader, writer: writer),
            persist: { den in
                #expect(den.desks[0].boards.map(\.id) == [board.id])
                events.append("save")
                return true
            }, directoryExists: { _ in true })

        // Act
        let inserted = try #require(
            creation.insert(board, target: .init(presentedDeskID: desk.id)) { notice in
                switch notice {
                case .willInsert:
                    #expect(state.snapshot.den.desks[0].boards.isEmpty)
                    events.append("prepare")
                case .didInsert:
                    #expect(state.snapshot.den.desks[0].boards.map(\.id) == [board.id])
                    events.append("complete")
                default: break
                }
            })

        // Assert
        #expect(inserted == board.id)
        #expect(events == ["prepare", "save", "complete"])
    }
}
