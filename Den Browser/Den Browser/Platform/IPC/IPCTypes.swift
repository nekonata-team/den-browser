import Foundation

nonisolated enum DenIPCCommand: Equatable, Sendable {
    enum Sheet: String, CaseIterable, Sendable {
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
        case click
        case fill
    }

    enum Board: String, CaseIterable, Sendable {
        case list
        case new
        case close
    }

    enum Desk: String, CaseIterable, Sendable {
        case list
    }

    enum Drawer: String, CaseIterable, Sendable {
        case list
        case keep
        case place
        case discard
    }

    enum Terminal: String, CaseIterable, Sendable {
        case list
        case new
        case text
        case send
        case kill
    }

    case sheet(Sheet)
    case board(Board)
    case desk(Desk)
    case drawer(Drawer)
    case terminal(Terminal)

    private static let allCommands: [Self] =
        Sheet.allCases.map { .sheet($0) }
        + Board.allCases.map { .board($0) }
        + Desk.allCases.map { .desk($0) }
        + Drawer.allCases.map { .drawer($0) }
        + Terminal.allCases.map { .terminal($0) }

    init?(wireValue: String) {
        guard let command = Self.allCommands.first(where: { $0.wireValue == wireValue }) else {
            return nil
        }
        self = command
    }

    var wireValue: String {
        switch self {
        case .sheet(let command): "sheet.\(command.rawValue)"
        case .board(let command): "board.\(command.rawValue)"
        case .desk(let command): "desk.\(command.rawValue)"
        case .drawer(let command): "drawer.\(command.rawValue)"
        case .terminal(let command): "terminal.\(command.rawValue)"
        }
    }
}

extension DenIPCCommand: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let wireValue = try container.decode(String.self).lowercased()
        guard let command = DenIPCCommand(wireValue: wireValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown IPC command: \(wireValue)")
        }
        self = command
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }
}

nonisolated struct DenIPCRequest: Codable, Sendable {
    var command: DenIPCCommand
    var args: [String] = []
    var boardID: String?
    var deskID: String?
    var callerBoardID: String?
}

nonisolated struct DenBoardInfo: Codable, Sendable {
    var id: String
    var type: String
    var label: String
    var url: String?
}

nonisolated struct DenDeskInfo: Codable, Sendable {
    var id: String
    var label: String
    var isActive: Bool
    var boardCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case isActive = "is_active"
        case boardCount = "board_count"
    }
}

nonisolated struct DenDrawerItemInfo: Codable, Sendable {
    var id: String
    var url: String
    var title: String?
}

nonisolated struct DenTerminalInfo: Codable, Sendable {
    var id: String
    var label: String
    var workingDirectory: String?
    var foregroundPid: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case workingDirectory = "working_directory"
        case foregroundPid = "foreground_pid"
    }
}

nonisolated struct DenIPCResponse: Codable, Sendable {
    var isOk: Bool
    var error: String?
    var message: String?
    var boardId: String?
    var closedBoardId: String?
    var boards: [DenBoardInfo]?
    var desks: [DenDeskInfo]?
    var drawerItemId: String?
    var drawerItems: [DenDrawerItemInfo]?
    var terminals: [DenTerminalInfo]?
    var url: String?
    var snapshot: String?
    var text: String?
    var value: String?
    var screenshotPath: String?

    enum CodingKeys: String, CodingKey {
        case isOk = "ok"
        case error
        case message
        case boardId = "board_id"
        case closedBoardId = "closed_board_id"
        case boards
        case desks
        case drawerItemId = "drawer_item_id"
        case drawerItems = "drawer_items"
        case terminals
        case url
        case snapshot
        case text
        case value
        case screenshotPath = "screenshot_path"
    }

    static func success(
        message: String? = nil,
        boardId: String? = nil,
        closedBoardId: String? = nil,
        boards: [DenBoardInfo]? = nil,
        desks: [DenDeskInfo]? = nil,
        drawerItemId: String? = nil,
        drawerItems: [DenDrawerItemInfo]? = nil,
        terminals: [DenTerminalInfo]? = nil,
        url: String? = nil,
        snapshot: String? = nil,
        text: String? = nil,
        value: String? = nil,
        screenshotPath: String? = nil
    ) -> DenIPCResponse {
        DenIPCResponse(
            isOk: true,
            error: nil,
            message: message,
            boardId: boardId,
            closedBoardId: closedBoardId,
            boards: boards,
            desks: desks,
            drawerItemId: drawerItemId,
            drawerItems: drawerItems,
            terminals: terminals,
            url: url,
            snapshot: snapshot,
            text: text,
            value: value,
            screenshotPath: screenshotPath
        )
    }

    static func failure(_ error: String) -> DenIPCResponse {
        DenIPCResponse(
            isOk: false,
            error: error,
            message: nil,
            boardId: nil,
            closedBoardId: nil,
            boards: nil,
            desks: nil,
            drawerItemId: nil,
            drawerItems: nil,
            url: nil,
            snapshot: nil,
            text: nil,
            value: nil,
            screenshotPath: nil
        )
    }
}
