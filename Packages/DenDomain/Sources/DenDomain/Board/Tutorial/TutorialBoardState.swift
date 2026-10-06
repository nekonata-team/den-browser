import Foundation

public struct TutorialBoardState: Equatable {
    public var completedSteps: Set<TutorialBoardStep> = []

    public init(completedSteps: Set<TutorialBoardStep> = []) {
        self.completedSteps = completedSteps
    }

    @discardableResult
    public mutating func record(step: TutorialBoardStep) -> Bool {
        if step.isRequired,
            TutorialBoardStep.requiredSteps.first(where: { !completedSteps.contains($0) }) != step
        {
            return false
        }
        return completedSteps.insert(step).inserted
    }
}
