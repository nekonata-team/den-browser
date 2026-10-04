import Foundation

enum TutorialBoardStep: CaseIterable, Hashable {
    case openBoard, navigateBoards, createDesk, keyboardShortcuts, terminalBoard

    var completionEvents: [DenOperationEvent] {
        switch self {
        case .openBoard: [.webBoardOpened]
        case .navigateBoards: [.boardFocusMoved]
        case .createDesk: [.deskCreated]
        case .keyboardShortcuts: [.keyboardShortcutsShown]
        case .terminalBoard: [.terminalBoardOpened]
        }
    }

    var isRequired: Bool { self != .keyboardShortcuts && self != .terminalBoard }

    static var requiredSteps: [Self] { allCases.filter(\.isRequired) }
}

struct TutorialBoardState: Equatable {
    var completedSteps: Set<TutorialBoardStep> = []
}
