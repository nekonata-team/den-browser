import DenDomain
import Foundation

enum BoardOperationOrigin: Equatable {
    case interactive
    case cli
}

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

struct BoardLinkFocusIntent: Equatable {
    let id: UUID
    let boardID: UUID
    let origin: BoardOperationOrigin

    init(boardID: UUID, origin: BoardOperationOrigin = .interactive) {
        id = UUID()
        self.boardID = boardID
        self.origin = origin
    }
}

struct BoardRemovalIntent: Equatable {
    let id: UUID
    let origin: BoardOperationOrigin

    init(origin: BoardOperationOrigin) {
        id = UUID()
        self.origin = origin
    }
}
