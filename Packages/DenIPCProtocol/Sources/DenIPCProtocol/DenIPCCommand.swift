import Foundation

public nonisolated enum DenSheetGetCommand: Codable, Equatable, Sendable {
    case text(DenSheetGetTargetPayload)
    case value(DenSheetGetTargetPayload)
    case attribute(DenSheetGetAttributePayload)
    case count(DenSheetGetTargetPayload)
    case box(DenSheetGetTargetPayload)
}

public nonisolated enum DenSheetIsCommand: Codable, Equatable, Sendable {
    case visible(DenSheetStatePayload)
    case enabled(DenSheetStatePayload)
    case checked(DenSheetStatePayload)
}

public nonisolated enum DenSheetMouseCommand: Codable, Equatable, Sendable {
    case move(DenSheetMousePayload)
    case down(DenSheetMousePayload)
    case release(DenSheetMousePayload)
    case click(DenSheetMousePayload)
    case wheel(DenSheetMousePayload)
}

public nonisolated enum DenBoardWebCommand: Codable, Equatable, Sendable {
    case new(DenBoardWebNewPayload)
}

public nonisolated enum DenBoardTerminalCommand: Codable, Equatable, Sendable {
    case new(DenBoardTerminalNewPayload)
}

public nonisolated enum DenBoardInspectionCommand: Codable, Equatable, Sendable {
    case new(DenBoardInspectionNewPayload)
}

public nonisolated enum DenIPCCommand: Codable, Equatable, Sendable {
    public indirect enum Sheet: Codable, Equatable, Sendable {
        case open(DenSheetOpenPayload)
        case inspect(DenSheetSnapshotPayload)
        case url
        case reload
        case eval(DenSheetEvalPayload)
        case text
        case back
        case forward
        case press(DenSheetPressPayload)
        case scroll(DenSheetScrollPayload)
        case wait(DenSheetWaitPayload)
        case screenshot(DenSheetScreenshotPayload)
        case snapshot(DenSheetSnapshotPayload)
        case query(DenSheetQueryPayload)
        case get(DenSheetGetCommand)
        case isState(DenSheetIsCommand)
        case click(DenSheetClickPayload)
        case dblclick(DenSheetElementTargetPayload)
        case fill(DenSheetFillPayload)
        case type(DenSheetTypePayload)
        case focus(DenSheetElementTargetPayload)
        case drag(DenSheetDragPayload)
        case mouse(DenSheetMouseCommand)
        case interact(DenSheetInteractPayload)
    }

    public enum Board: Codable, Equatable, Sendable {
        case list
        case focused
        case close
        case web(DenBoardWebCommand)
        case terminal(DenBoardTerminalCommand)
        case inspection(DenBoardInspectionCommand)
    }

    public enum Desk: Codable, Equatable, Sendable {
        case list
    }

    public enum Drawer: Codable, Equatable, Sendable {
        case list
        case keep(DenDrawerKeepPayload)
        case place(id: String)
        case discard(id: String)
    }

    public enum Terminal: Codable, Equatable, Sendable {
        case text
        case send(text: String)
        case run(command: String)
        case kill(signal: String)
    }

    public enum Inspection: Codable, Equatable, Sendable {
        case read
    }

    public enum Profile: Codable, Equatable, Sendable {
        case list
        case open(profileID: String?)
    }

    case sheet(Sheet)
    case board(Board)
    case desk(Desk)
    case drawer(Drawer)
    case terminal(Terminal)
    case inspection(Inspection)
    case profile(Profile)
    case inspectDen
    case health
}
