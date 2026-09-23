import Foundation

nonisolated struct DenBoardInfo: Codable, Sendable {
    var id: String
    var type: String
    var label: String
    var url: String?
    var sessionName: String?
    var isFocused: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case label
        case url
        case sessionName = "session_name"
        case isFocused = "is_focused"
    }

    init(
        id: String,
        type: String,
        label: String,
        url: String? = nil,
        sessionName: String? = nil,
        isFocused: Bool = false
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.url = url
        self.sessionName = sessionName
        self.isFocused = isFocused
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

nonisolated struct DenSelectedProfileInfo: Codable, Sendable {
    var id: String
    var name: String
}

nonisolated struct DenBoundingBox: Codable, Equatable, Sendable {
    var originX: Double
    var originY: Double
    var width: Double
    var height: Double

    enum CodingKeys: String, CodingKey {
        case originX = "x"
        case originY = "y"
        case width
        case height
    }
}

nonisolated struct DenIPCResponse: Codable, Sendable {
    var isOk: Bool
    var error: String?
    var message: String?
    var boardId: String?
    var closedBoardId: String?
    var board: DenBoardInfo?
    var boards: [DenBoardInfo]?
    var desks: [DenDeskInfo]?
    var drawerItemId: String?
    var drawerItems: [DenDrawerItemInfo]?
    var profiles: [DenProfileInfo]?
    var profile: DenSelectedProfileInfo?
    var profileID: String?
    var activeDesk: DenDeskInfo?
    var focusedBoardID: String?
    var drawerItemCount: Int?
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
    var box: DenBoundingBox?
    var screenshotPath: String?
    var completedActions: Int?
    var failedActionIndex: Int?

    enum CodingKeys: String, CodingKey {
        case isOk = "ok"
        case error
        case message
        case boardId = "board_id"
        case closedBoardId = "closed_board_id"
        case board
        case boards
        case desks
        case drawerItemId = "drawer_item_id"
        case drawerItems = "drawer_items"
        case profiles
        case profile
        case profileID = "profile_id"
        case activeDesk = "active_desk"
        case focusedBoardID = "focused_board_id"
        case drawerItemCount = "drawer_item_count"
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
        case box
        case screenshotPath = "screenshot_path"
        case completedActions = "completed_actions"
        case failedActionIndex = "failed_action_index"
    }

    static func success(
        message: String? = nil,
        boardId: String? = nil,
        closedBoardId: String? = nil,
        board: DenBoardInfo? = nil,
        boards: [DenBoardInfo]? = nil,
        desks: [DenDeskInfo]? = nil,
        drawerItemId: String? = nil,
        drawerItems: [DenDrawerItemInfo]? = nil,
        profiles: [DenProfileInfo]? = nil,
        profile: DenSelectedProfileInfo? = nil,
        profileID: String? = nil,
        activeDesk: DenDeskInfo? = nil,
        focusedBoardID: String? = nil,
        drawerItemCount: Int? = nil,
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
        box: DenBoundingBox? = nil,
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
            board: board,
            boards: boards,
            desks: desks,
            drawerItemId: drawerItemId,
            drawerItems: drawerItems,
            profiles: profiles,
            profile: profile,
            profileID: profileID,
            activeDesk: activeDesk,
            focusedBoardID: focusedBoardID,
            drawerItemCount: drawerItemCount,
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
            box: box,
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
            board: nil,
            boards: nil,
            desks: nil,
            drawerItemId: nil,
            drawerItems: nil,
            profiles: nil,
            profile: nil,
            profileID: nil,
            activeDesk: nil,
            focusedBoardID: nil,
            drawerItemCount: nil,
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
