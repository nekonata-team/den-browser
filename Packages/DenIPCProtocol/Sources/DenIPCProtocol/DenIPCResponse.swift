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

public nonisolated enum DenIPCResultPayload: Codable, Sendable {
    case empty
    case message(String)
    case createdBoard(id: String, message: String?, url: String?)
    case navigation(message: String, url: String)
    case closedBoard(id: String, message: String)
    case board(DenBoardInfo)
    case boards([DenBoardInfo])
    case desks([DenDeskInfo])
    case drawerItems([DenDrawerItemInfo])
    case drawerItem(id: String, message: String)
    case profiles([DenProfileInfo])
    case denOverview(DenIPCOverview)
    case sheet(boardID: String, url: String)
    case url(String)
    case elements([DenSheetElementInfo])
    case text(String)
    case value(String)
    case checked(Bool)
    case attribute(String)
    case count(Int)
    case visible(Bool)
    case enabled(Bool)
    case box(DenBoundingBox)
    case screenshotPath(String)
    case inspection(DenInspectionReadInfo)
    case interaction(completedActions: Int, failedActionIndex: Int?)
}

public nonisolated struct DenIPCOverview: Codable, Sendable {
    public var profiles: [DenProfileInfo]
    public var profile: DenSelectedProfileInfo
    public var profileID: String
    public var desks: [DenDeskInfo]
    public var activeDesk: DenDeskInfo?
    public var boards: [DenBoardInfo]
    public var focusedBoardID: String?
    public var drawerItemCount: Int

    public init(
        profiles: [DenProfileInfo],
        profile: DenSelectedProfileInfo,
        profileID: String,
        desks: [DenDeskInfo],
        activeDesk: DenDeskInfo?,
        boards: [DenBoardInfo],
        focusedBoardID: String?,
        drawerItemCount: Int
    ) {
        self.profiles = profiles
        self.profile = profile
        self.profileID = profileID
        self.desks = desks
        self.activeDesk = activeDesk
        self.boards = boards
        self.focusedBoardID = focusedBoardID
        self.drawerItemCount = drawerItemCount
    }
}

public nonisolated enum DenIPCOperationOutcome: Codable, Sendable {
    case success(DenIPCResultPayload)
    case failure(error: String, payload: DenIPCResultPayload?)
}

public nonisolated struct DenIPCOperationResult: Codable, Sendable {
    public var outcome: DenIPCOperationOutcome
    public var snapshot: String?

    public var isOk: Bool {
        if case .success = outcome { true } else { false }
    }

    public var error: String? {
        guard case .failure(let error, _) = outcome else { return nil }
        return error
    }

    public var payload: DenIPCResultPayload? {
        switch outcome {
        case .success(let payload): payload
        case .failure(_, let payload): payload
        }
    }

    public func failing(with error: String) -> DenIPCOperationResult {
        .failure(error, payload: payload, snapshot: snapshot)
    }

    public var completedActions: Int? {
        guard case .interaction(let completedActions, _) = payload else { return nil }
        return completedActions
    }

    public var failedActionIndex: Int? {
        guard case .interaction(_, let failedActionIndex) = payload else { return nil }
        return failedActionIndex
    }

    public var publicJSON: DenIPCOperationResultJSON {
        DenIPCOperationResultJSON(result: self)
    }

    public init(outcome: DenIPCOperationOutcome, snapshot: String? = nil) {
        self.outcome = outcome
        self.snapshot = snapshot
    }

    public static func success(
        _ payload: DenIPCResultPayload = .empty,
        snapshot: String? = nil
    ) -> DenIPCOperationResult {
        DenIPCOperationResult(outcome: .success(payload), snapshot: snapshot)
    }

    public static func failure(
        _ error: String,
        payload: DenIPCResultPayload? = nil,
        snapshot: String? = nil
    ) -> DenIPCOperationResult {
        DenIPCOperationResult(outcome: .failure(error: error, payload: payload), snapshot: snapshot)
    }
}

/// Encodes the typed result as the flat JSON object consumed by CLI and MCP.
public nonisolated struct DenIPCOperationResultJSON: Encodable, Sendable {
    private let result: DenIPCOperationResult

    public init(result: DenIPCOperationResult) {
        self.result = result
    }

    private enum CodingKeys: String, CodingKey {
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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(result.isOk, forKey: .isOk)
        try container.encodeIfPresent(result.error, forKey: .error)
        try container.encodeIfPresent(result.snapshot, forKey: .snapshot)

        guard let payload = result.payload else { return }
        switch payload {
        case .empty:
            break
        case .message(let message):
            try container.encode(message, forKey: .message)
        case .createdBoard(let id, let message, let url):
            try container.encode(id, forKey: .boardId)
            try container.encodeIfPresent(message, forKey: .message)
            try container.encodeIfPresent(url, forKey: .url)
        case .navigation(let message, let url):
            try container.encode(message, forKey: .message)
            try container.encode(url, forKey: .url)
        case .closedBoard(let id, let message):
            try container.encode(id, forKey: .closedBoardId)
            try container.encode(message, forKey: .message)
        case .board(let board):
            try container.encode(board.id, forKey: .boardId)
            try container.encode(board, forKey: .board)
        case .boards(let boards):
            try container.encode(boards, forKey: .boards)
        case .desks(let desks):
            try container.encode(desks, forKey: .desks)
        case .drawerItems(let items):
            try container.encode(items, forKey: .drawerItems)
        case .drawerItem(let id, let message):
            try container.encode(id, forKey: .drawerItemId)
            try container.encode(message, forKey: .message)
        case .profiles(let profiles):
            try container.encode(profiles, forKey: .profiles)
        case .denOverview(let overview):
            try container.encode(overview.profiles, forKey: .profiles)
            try container.encode(overview.profile, forKey: .profile)
            try container.encode(overview.profileID, forKey: .profileID)
            try container.encode(overview.desks, forKey: .desks)
            try container.encodeIfPresent(overview.activeDesk, forKey: .activeDesk)
            try container.encode(overview.boards, forKey: .boards)
            try container.encodeIfPresent(overview.focusedBoardID, forKey: .focusedBoardID)
            try container.encode(overview.drawerItemCount, forKey: .drawerItemCount)
        case .sheet(let boardID, let url):
            try container.encode(boardID, forKey: .boardId)
            try container.encode(url, forKey: .url)
        case .url(let url):
            try container.encode(url, forKey: .url)
        case .elements(let elements):
            try container.encode(elements, forKey: .elements)
        case .text(let text):
            try container.encode(text, forKey: .text)
        case .value(let value):
            try container.encode(value, forKey: .value)
        case .checked(let checked):
            try container.encode(checked, forKey: .checked)
        case .attribute(let attribute):
            try container.encode(attribute, forKey: .attribute)
        case .count(let count):
            try container.encode(count, forKey: .count)
        case .visible(let visible):
            try container.encode(visible, forKey: .visible)
        case .enabled(let enabled):
            try container.encode(enabled, forKey: .enabled)
        case .box(let box):
            try container.encode(box, forKey: .box)
        case .screenshotPath(let path):
            try container.encode(path, forKey: .screenshotPath)
        case .inspection(let details):
            try container.encode(details.boardID, forKey: .boardId)
            try container.encode(details, forKey: .inspection)
        case .interaction(let completedActions, let failedActionIndex):
            try container.encode(completedActions, forKey: .completedActions)
            try container.encodeIfPresent(failedActionIndex, forKey: .failedActionIndex)
        }
    }
}

public nonisolated enum DenIPCTargetContext: Codable, Equatable, Sendable {
    case none
    case profile(profileID: UUID)
    case board(profileID: UUID, boardID: UUID)
}

public nonisolated struct DenIPCResponse: Codable, Sendable {
    public var result: DenIPCOperationResult
    public var target: DenIPCTargetContext

    public init(result: DenIPCOperationResult, target: DenIPCTargetContext) {
        self.result = result
        self.target = target
    }
}
