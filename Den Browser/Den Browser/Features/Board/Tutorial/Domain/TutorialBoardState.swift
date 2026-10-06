import Foundation

enum TutorialBoardStep: CaseIterable, Hashable {
    case openBoard, navigateBoards, createDesk, keyboardShortcuts, terminalBoard

    var isRequired: Bool { self != .keyboardShortcuts && self != .terminalBoard }

    static var requiredSteps: [Self] { allCases.filter(\.isRequired) }
}

struct TutorialBoardState: Equatable {
    var completedSteps: Set<TutorialBoardStep> = []

    @discardableResult
    mutating func record(step: TutorialBoardStep) -> Bool {
        if step.isRequired,
            TutorialBoardStep.requiredSteps.first(where: { !completedSteps.contains($0) }) != step
        {
            return false
        }
        return completedSteps.insert(step).inserted
    }
}
