import DenDomain
import Foundation

enum DenOperationEvent: Equatable {
    case webBoardOpened
    case terminalBoardOpened
    case deskCreated
    case denModeEntered
    case boardFocusMoved
    case keyboardShortcutsShown
}

extension DenOperationEvent {
    var tutorialStep: TutorialBoardStep? {
        switch self {
        case .webBoardOpened: .openBoard
        case .terminalBoardOpened: .terminalBoard
        case .deskCreated: .createDesk
        case .boardFocusMoved: .navigateBoards
        case .keyboardShortcutsShown: .keyboardShortcuts
        case .denModeEntered: nil
        }
    }
}
