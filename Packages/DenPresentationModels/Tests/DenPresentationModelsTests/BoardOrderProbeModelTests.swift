import DenApplication
import DenDomain
import DenPresentationModels
import Observation
import Synchronization
import Testing

private final class ChangeFlag: Sendable {
    let value = Mutex(false)
}

@MainActor
struct BoardOrderProbeModelTests {
    @Test func concreteOperationAndTwoModelsShareOneObservableSource() {
        // Arrange
        let first = BoardState(label: "First", width: 520, workingDirectory: "/tmp")
        let second = BoardState(label: "Second", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [first, second], focusedBoardID: first.id)
        let (state, writer) = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let movement = BoardMovement(state: state, writer: writer)
        let models = (0..<2).map { _ in
            BoardOrderProbeModel(state: state, movement: movement, deskID: desk.id)
        }
        let changes = models.map { model in
            let changed = ChangeFlag()
            withObservationTracking {
                _ = model.boards
            } onChange: {
                changed.value.withLock { $0 = true }
            }
            return changed
        }

        // Act
        models[0].reorder(first.id, to: BoardIndex(rawValue: 1))

        // Assert
        #expect(models.allSatisfy { $0.boards.map(\.id) == [second.id, first.id] })
        #expect(changes.allSatisfy { $0.value.withLock { $0 } })
    }
}
