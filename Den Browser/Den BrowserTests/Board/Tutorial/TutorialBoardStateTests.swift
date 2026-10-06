import DenDomain
import Testing

@testable import Den_Browser

@MainActor
struct TutorialBoardStateTests {
    @Test func recordsRequiredStepsInOrder() {
        // Arrange
        var state = TutorialBoardState()

        // Act
        let skippedAhead = state.record(step: .createDesk)
        let openedBoard = state.record(step: .openBoard)
        let navigatedBoards = state.record(step: .navigateBoards)
        let createdDesk = state.record(step: .createDesk)

        // Assert
        #expect(!skippedAhead)
        #expect(openedBoard)
        #expect(navigatedBoards)
        #expect(createdDesk)
        #expect(state.completedSteps == Set(TutorialBoardStep.requiredSteps))
    }

    @Test func recordsOptionalStepsAnytimeAndOnlyOnce() {
        // Arrange
        var state = TutorialBoardState()

        // Act
        let recordedBeforeRequiredSteps = state.record(step: .terminalBoard)
        let recordedAgain = state.record(step: .terminalBoard)

        // Assert
        #expect(recordedBeforeRequiredSteps)
        #expect(!recordedAgain)
        #expect(state.completedSteps == [.terminalBoard])
    }
}
