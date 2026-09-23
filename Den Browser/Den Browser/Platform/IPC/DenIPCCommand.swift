import Foundation

nonisolated enum DenSheetGetCommand: Codable, Equatable, Sendable {
    case text(DenSheetGetTargetPayload)
    case value(DenSheetGetTargetPayload)
    case attribute(DenSheetGetAttributePayload)
    case count(DenSheetGetTargetPayload)
    case box(DenSheetGetTargetPayload)
}

nonisolated enum DenSheetIsCommand: Codable, Equatable, Sendable {
    case visible(DenSheetStatePayload)
    case enabled(DenSheetStatePayload)
    case checked(DenSheetStatePayload)
}

nonisolated enum DenSheetMouseCommand: Codable, Equatable, Sendable {
    case move(DenSheetMousePayload)
    case down(DenSheetMousePayload)
    case release(DenSheetMousePayload)
    case click(DenSheetMousePayload)
    case wheel(DenSheetMousePayload)
}

nonisolated enum DenBoardWebCommand: Codable, Equatable, Sendable {
    case new(DenBoardWebNewPayload)
}

nonisolated enum DenBoardTerminalCommand: Codable, Equatable, Sendable {
    case new(DenBoardTerminalNewPayload)
}

nonisolated enum DenIPCCommand: Codable, Equatable, Sendable {
    indirect enum Sheet: Codable, Equatable, Sendable {
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

    enum Board: Codable, Equatable, Sendable {
        case list
        case focused
        case close
        case web(DenBoardWebCommand)
        case terminal(DenBoardTerminalCommand)
    }

    enum Desk: Codable, Equatable, Sendable {
        case list
    }

    enum Drawer: Codable, Equatable, Sendable {
        case list
        case keep(DenDrawerKeepPayload)
        case place(id: String)
        case discard(id: String)
    }

    enum Terminal: Codable, Equatable, Sendable {
        case text
        case send(text: String)
        case run(command: String)
        case kill(signal: String)
    }

    enum Profile: Codable, Equatable, Sendable {
        case list
        case open(profileID: String?)
    }

    case sheet(Sheet)
    case board(Board)
    case desk(Desk)
    case drawer(Drawer)
    case terminal(Terminal)
    case profile(Profile)
    case inspectDen
    case health
}
