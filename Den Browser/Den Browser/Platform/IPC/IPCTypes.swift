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
        case fill
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

nonisolated struct DenSheetInteractStep: Codable, Equatable, Sendable {
    var line: Int
    var text: String
    var args: [String]
}

nonisolated struct DenIPCRequest: Codable, Sendable {
    var command: DenIPCCommand
    var args: [String] = []
    var boardID: String?
    var deskID: String?
    var callerBoardID: String?
    var profileID: String?
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

nonisolated struct DenSheetElementInfo: Codable, Sendable {
    var ref: String
    var tag: String?
    var role: String?
    var name: String?
    var text: String?
    var value: String?
    var checked: Bool?
    var disabled: Bool?
    var selected: Bool?
    var expanded: Bool?
    var visible: Bool
    var attributes: [String: String]?

    enum CodingKeys: String, CodingKey {
        case ref
        case tag
        case role
        case name
        case text
        case value
        case checked
        case disabled
        case selected
        case expanded
        case visible
        case attributes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ref, forKey: .ref)
        try container.encodeIfPresent(tag, forKey: .tag)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(checked, forKey: .checked)
        try container.encodeIfPresent(disabled, forKey: .disabled)
        try container.encodeIfPresent(selected, forKey: .selected)
        try container.encodeIfPresent(expanded, forKey: .expanded)
        try container.encode(visible, forKey: .visible)
        if let attributes, !attributes.isEmpty {
            try container.encode(attributes, forKey: .attributes)
        }
    }
}

nonisolated struct DenProfileInfo: Codable, Sendable {
    var id: String
    var name: String
    var isActive: Bool
    var hasWindow: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isActive = "is_active"
        case hasWindow = "has_window"
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
    var profiles: [DenProfileInfo]?
    var url: String?
    var snapshot: String?
    var elements: [DenSheetElementInfo]?
    var text: String?
    var value: String?
    var checked: Bool?
    var attribute: String?
    var count: Int?
    var visible: Bool?
    var enabled: Bool?
    var screenshotPath: String?
    var completedActions: Int?
    var failedActionIndex: Int?

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
        case profiles
        case url
        case snapshot
        case elements
        case text
        case value
        case checked
        case attribute
        case count
        case visible
        case enabled
        case screenshotPath = "screenshot_path"
        case completedActions = "completed_actions"
        case failedActionIndex = "failed_action_index"
    }

    static func success(
        message: String? = nil,
        boardId: String? = nil,
        closedBoardId: String? = nil,
        boards: [DenBoardInfo]? = nil,
        desks: [DenDeskInfo]? = nil,
        drawerItemId: String? = nil,
        drawerItems: [DenDrawerItemInfo]? = nil,
        profiles: [DenProfileInfo]? = nil,
        url: String? = nil,
        snapshot: String? = nil,
        elements: [DenSheetElementInfo]? = nil,
        text: String? = nil,
        value: String? = nil,
        checked: Bool? = nil,
        attribute: String? = nil,
        count: Int? = nil,
        visible: Bool? = nil,
        enabled: Bool? = nil,
        screenshotPath: String? = nil,
        completedActions: Int? = nil,
        failedActionIndex: Int? = nil
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
            profiles: profiles,
            url: url,
            snapshot: snapshot,
            elements: elements,
            text: text,
            value: value,
            checked: checked,
            attribute: attribute,
            count: count,
            visible: visible,
            enabled: enabled,
            screenshotPath: screenshotPath,
            completedActions: completedActions,
            failedActionIndex: failedActionIndex
        )
    }

    static func failure(
        _ error: String,
        snapshot: String? = nil,
        completedActions: Int? = nil,
        failedActionIndex: Int? = nil
    ) -> DenIPCResponse {
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
            profiles: nil,
            url: nil,
            snapshot: snapshot,
            elements: nil,
            text: nil,
            value: nil,
            checked: nil,
            attribute: nil,
            count: nil,
            visible: nil,
            enabled: nil,
            screenshotPath: nil,
            completedActions: completedActions,
            failedActionIndex: failedActionIndex
        )
    }
}
