import Foundation

enum TutorialBoardStep: CaseIterable, Hashable {
    case openBoard, navigateBoards, createDesk, keyboardShortcuts, terminalBoard

    var isRequired: Bool { self != .keyboardShortcuts && self != .terminalBoard }

    static var requiredSteps: [Self] { allCases.filter(\.isRequired) }
}

struct TutorialBoardState: Equatable {
    var completedSteps: Set<TutorialBoardStep> = []
}
