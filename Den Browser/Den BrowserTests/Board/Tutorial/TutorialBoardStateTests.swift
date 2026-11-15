import DenDomain
import DenModels
import Testing

@testable import Den_Browser

@MainActor
struct TutorialBoardStateTests {
    @Test func recordsRequiredStepsInOrderAndOptionalStepsOnce() {
        // Arrange
        var state = TutorialBoardState()

        // Act
        let recordedOptionalBeforeRequired = state.record(step: .terminalBoard)
        let recordedOptionalAgain = state.record(step: .terminalBoard)
        let skippedAhead = state.record(step: .createDesk)
        let openedBoard = state.record(step: .openBoard)
        let navigatedBoards = state.record(step: .navigateBoards)
        let createdDesk = state.record(step: .createDesk)

        // Assert
        #expect(recordedOptionalBeforeRequired)
        #expect(!recordedOptionalAgain)
        #expect(!skippedAhead)
        #expect(openedBoard)
        #expect(navigatedBoards)
        #expect(createdDesk)
        #expect(state.completedSteps == Set(TutorialBoardStep.requiredSteps).union([.terminalBoard]))
    }
}
