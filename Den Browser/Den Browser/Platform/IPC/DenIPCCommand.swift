import Foundation

nonisolated enum DenIPCCommand: Codable, Equatable, Sendable {
    enum Sheet: String, CaseIterable, Codable, Sendable {
        case open
        case url
        case reload
        case eval
        case text
        case back
        case forward
        case press
        case scroll
        case wait
        case screenshot
        case snapshot
        case query
        case get
        case isState = "is"
        case click
        case dblclick
        case fill
        case type
        case focus
        case drag
        case mouse
        case interact
    }

    enum WebBoard: String, CaseIterable, Codable, Sendable {
        case new
    }

    enum TerminalBoard: String, CaseIterable, Codable, Sendable {
        case new
    }

    enum Board: Codable, Equatable, Sendable {
        case list
        case focused
        case close
        case web(WebBoard)
        case terminal(TerminalBoard)
    }

    enum Desk: String, CaseIterable, Codable, Sendable {
        case list
    }

    enum Drawer: String, CaseIterable, Codable, Sendable {
        case list
        case keep
        case place
        case discard
    }

    enum Terminal: String, CaseIterable, Codable, Sendable {
        case text
        case send
        case run
        case kill
    }

    enum Profile: String, CaseIterable, Codable, Sendable {
        case list
        case open
    }

    case sheet(Sheet)
    case board(Board)
    case desk(Desk)
    case drawer(Drawer)
    case terminal(Terminal)
    case profile(Profile)
    case health

}
