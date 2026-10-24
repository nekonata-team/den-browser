import DenApplication
import DenDomain
import DenModels
import Testing

@MainActor
struct TutorialProgressTests {
    @Test func progressUsesFirstTutorialAndPreservesRequiredOrder() {
        // Arrange
        let first = BoardState(width: 520, tutorial: TutorialBoardState())
        let second = BoardState(width: 520, tutorial: TutorialBoardState())
        let desk = DeskState(label: "Desk", boards: [first, second])
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let progress = TutorialProgress(store: shared.reader, writer: shared.writer)
        // Act
        progress.record(.createDesk)
        let premature = shared.store.snapshot
        progress.record(.openBoard)
        progress.record(.navigateBoards)
        progress.record(.createDesk)
        progress.record(.openBoard)
        // Assert
        #expect(premature.den.desks[0].boards[0] == first)
        #expect(
            shared.store.snapshot.den.desks[0].boards[0].tutorialCompletedSteps
                == Set([.openBoard, .navigateBoards, .createDesk]))
        #expect(shared.store.snapshot.den.desks[0].boards[1] == second)
    }
}
