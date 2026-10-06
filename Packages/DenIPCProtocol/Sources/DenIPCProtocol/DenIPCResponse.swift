import Foundation

public nonisolated struct DenBoardInfo: Codable, Sendable {
    public var id: String
    public var type: String
    public var label: String
    public var url: String?
    public var sessionName: String?
    public var targetBoardID: String?
    public var isFocused: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case label
        case url
        case sessionName = "session_name"
        case targetBoardID = "target_board_id"
        case isFocused = "is_focused"
    }

    public init(
        id: String,
        type: String,
        label: String,
        url: String? = nil,
        sessionName: String? = nil,
        targetBoardID: String? = nil,
        isFocused: Bool = false
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.url = url
        self.sessionName = sessionName
        self.targetBoardID = targetBoardID
        self.isFocused = isFocused
    }
}

public nonisolated struct DenDeskInfo: Codable, Sendable {
    public var id: String
    public var label: String
    public var isActive: Bool
    public var boardCount: Int

    public init(
        id: String,
        label: String,
        isActive: Bool,
        boardCount: Int
    ) {
        self.id = id
        self.label = label
        self.isActive = isActive
        self.boardCount = boardCount
    }
    enum CodingKeys: String, CodingKey {
        case id
        case label
        case isActive = "is_active"
        case boardCount = "board_count"
    }
}

public nonisolated struct DenDrawerItemInfo: Codable, Sendable {
    public var id: String
    public var url: String
    public var title: String?

    public init(
        id: String,
        url: String,
        title: String? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
    }
}

public nonisolated struct DenSheetElementInfo: Codable, Sendable {
    public var ref: String
    public var tag: String?
    public var role: String?
    public var name: String?
    public var text: String?
    public var value: String?
    public var checked: Bool?
    public var disabled: Bool?
    public var selected: Bool?
    public var expanded: Bool?
    public var visible: Bool
    public var attributes: [String: String]?

    public init(
        ref: String,
        tag: String? = nil,
        role: String? = nil,
        name: String? = nil,
        text: String? = nil,
        value: String? = nil,
        checked: Bool? = nil,
        disabled: Bool? = nil,
        selected: Bool? = nil,
        expanded: Bool? = nil,
        visible: Bool,
        attributes: [String: String]? = nil
    ) {
        self.ref = ref
        self.tag = tag
        self.role = role
        self.name = name
        self.text = text
        self.value = value
        self.checked = checked
        self.disabled = disabled
        self.selected = selected
        self.expanded = expanded
        self.visible = visible
        self.attributes = attributes
    }
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

    public func encode(to encoder: Encoder) throws {
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

public nonisolated struct DenProfileInfo: Codable, Sendable {
    public var id: String
    public var name: String
    public var isActive: Bool
    public var hasWindow: Bool

    public init(
        id: String,
        name: String,
        isActive: Bool,
        hasWindow: Bool
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.hasWindow = hasWindow
    }
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isActive = "is_active"
        case hasWindow = "has_window"
    }
}

public nonisolated struct DenSelectedProfileInfo: Codable, Sendable {
    public var id: String
    public var name: String

    public init(
        id: String,
        name: String
    ) {
        self.id = id
        self.name = name
    }
}

public nonisolated struct DenBoundingBox: Codable, Equatable, Sendable {
    public var originX: Double
    public var originY: Double
    public var width: Double
    public var height: Double

    public init(
        originX: Double,
        originY: Double,
        width: Double,
        height: Double
    ) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }
    enum CodingKeys: String, CodingKey {
        case originX = "x"
        case originY = "y"
        case width
        case height
    }
}

public nonisolated struct DenIPCResponse: Codable, Sendable {
    public var isOk: Bool
    public var error: String?
    public var message: String?
    public var boardId: String?
    public var closedBoardId: String?
    public var board: DenBoardInfo?
    public var boards: [DenBoardInfo]?
    public var desks: [DenDeskInfo]?
    public var drawerItemId: String?
    public var drawerItems: [DenDrawerItemInfo]?
    public var profiles: [DenProfileInfo]?
    public var profile: DenSelectedProfileInfo?
    public var profileID: String?
    public var activeDesk: DenDeskInfo?
    public var focusedBoardID: String?
    public var drawerItemCount: Int?
    public var url: String?
    public var snapshot: String?
    public var elements: [DenSheetElementInfo]?
    public var text: String?
    public var value: String?
    public var checked: Bool?
    public var attribute: String?
    public var count: Int?
    public var visible: Bool?
    public var enabled: Bool?
    public var box: DenBoundingBox?
    public var screenshotPath: String?
    public var inspection: DenInspectionReadInfo?
    public var completedActions: Int?
    public var failedActionIndex: Int?

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
        case inspection
        case completedActions = "completed_actions"
        case failedActionIndex = "failed_action_index"
    }

    public static func success(
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
        inspection: DenInspectionReadInfo? = nil,
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
            inspection: inspection,
            completedActions: completedActions,
            failedActionIndex: failedActionIndex
        )
    }

    public static func failure(
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
            inspection: nil,
            completedActions: completedActions,
            failedActionIndex: failedActionIndex
        )
    }
}
