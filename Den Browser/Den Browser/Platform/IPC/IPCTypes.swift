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
        case click
        case fill
    }

    enum WebBoard: String, CaseIterable, Codable, Sendable {
        case new
    }

    enum TerminalBoard: String, CaseIterable, Codable, Sendable {
        case new
    }

    enum Board: Codable, Equatable, Sendable {
        case list
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

    case sheet(Sheet)
    case board(Board)
    case desk(Desk)
    case drawer(Drawer)
    case terminal(Terminal)
    case health

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
    var sessionName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case label
        case url
        case sessionName = "session_name"
    }
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
