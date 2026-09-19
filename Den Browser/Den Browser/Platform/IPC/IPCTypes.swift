import Darwin
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

nonisolated struct DenSheetInteractStep: Codable, Equatable, Sendable {
    var line: Int
    var text: String
    var command: DenIPCCommand.Sheet
    var payload: DenSheetPayload?
}

nonisolated enum DenSheetGetKind: String, Codable, Equatable, Sendable {
    case text
    case value
    case attribute
    case count
    case box
}

nonisolated struct DenSheetGetPayload: Codable, Equatable, Sendable {
    var kind: DenSheetGetKind
    var target: String
    var attribute: String?

    init(kind: DenSheetGetKind, target: String, attribute: String? = nil) throws {
        self.kind = kind
        self.target = target
        self.attribute = attribute
        try validate()
    }

    func validate() throws {
        guard !target.isEmpty else {
            throw DenIPCInputError.usage("The Sheet get target must not be empty")
        }
        if kind == .attribute {
            guard let attribute, !attribute.isEmpty else {
                throw DenIPCInputError.usage("The Sheet get attribute name must not be empty")
            }
        }
    }
}

nonisolated enum DenSheetState: String, Codable, Equatable, Sendable {
    case visible
    case enabled
    case checked
}

nonisolated struct DenSheetStatePayload: Codable, Equatable, Sendable {
    var state: DenSheetState
    var target: String

    init(state: DenSheetState, target: String) throws {
        self.state = state
        self.target = target
        try validate()
    }

    func validate() throws {
        guard !target.isEmpty else {
            throw DenIPCInputError.usage("The Sheet state target must not be empty")
        }
    }
}

nonisolated indirect enum DenSheetPayload: Codable, Equatable, Sendable {
    case open(DenSheetOpenPayload)
    case eval(DenSheetEvalPayload)
    case press(DenSheetPressPayload)
    case scroll(DenSheetScrollPayload)
    case wait(DenSheetWaitPayload)
    case screenshot(DenSheetScreenshotPayload)
    case snapshot(DenSheetSnapshotPayload)
    case query(DenSheetQueryPayload)
    case click(DenSheetClickPayload)
    case dblclick(DenSheetElementTargetPayload)
    case focus(DenSheetElementTargetPayload)
    case fill(DenSheetFillPayload)
    case type(DenSheetTypePayload)
    case drag(DenSheetDragPayload)
    case mouse(DenSheetMousePayload)
    case interact(DenSheetInteractPayload)
    case get(DenSheetGetPayload)
    case isState(DenSheetStatePayload)
}

nonisolated struct DenSheetInteractPayload: Codable, Equatable, Sendable {
    var steps: [DenSheetInteractStep]
    var full: Bool
}

nonisolated struct DenSheetOpenPayload: Codable, Equatable, Sendable {
    var url: String
}

nonisolated struct DenSheetEvalPayload: Codable, Equatable, Sendable {
    var script: String
}

nonisolated struct DenSheetPressPayload: Codable, Equatable, Sendable {
    var key: String
}

nonisolated struct DenSheetScrollPayload: Codable, Equatable, Sendable {
    var directionOrTarget: String?
}

nonisolated struct DenSheetWaitPayload: Codable, Equatable, Sendable {
    var target: String?
    var state: String?
    var url: String?
    var text: String?
    var loadState: String?
    var function: String?
    var timeout: Double
}

nonisolated struct DenSheetScreenshotPayload: Codable, Equatable, Sendable {
    var outputPath: String?
}

nonisolated struct DenSheetSnapshotPayload: Codable, Equatable, Sendable {
    var full: Bool
    var within: String?
}

nonisolated struct DenSheetQueryPayload: Codable, Equatable, Sendable {
    var selector: String
    var visible: Bool
    var all: Bool
    var fields: String?
}

nonisolated struct DenSheetClickPayload: Codable, Equatable, Sendable {
    var target: String?
    var role: String?
    var name: String?
    var exact: Bool
    var newBoard: Bool
    var focus: Bool
}

nonisolated struct DenSheetElementTargetPayload: Codable, Equatable, Sendable {
    var target: String
}

nonisolated struct DenSheetFillPayload: Codable, Equatable, Sendable {
    var target: String
    var value: String
}

nonisolated struct DenSheetTypePayload: Codable, Equatable, Sendable {
    var target: String?
    var text: String
}

nonisolated struct DenSheetDragPayload: Codable, Equatable, Sendable {
    var source: String
    var destination: String?
    var deltaX: Double?
    var deltaY: Double?
    var steps: Int
}

nonisolated enum DenSheetMousePayload: Codable, Equatable, Sendable {
    case move(coordX: Double, coordY: Double)
    case down(button: String?)
    case release(button: String?)
    case click(coordX: Double, coordY: Double, button: String?, count: Int?)
    case wheel(deltaY: Double, deltaX: Double?)
}

nonisolated struct DenBoardWebNewPayload: Codable, Equatable, Sendable {
    var url: String
    var focus: Bool
}

nonisolated struct DenBoardTerminalNewPayload: Codable, Equatable, Sendable {
    var path: String?
    var runCommand: String?
    var focus: Bool
}

nonisolated enum DenBoardPayload: Codable, Equatable, Sendable {
    case webNew(DenBoardWebNewPayload)
    case terminalNew(DenBoardTerminalNewPayload)
}

nonisolated struct DenDrawerKeepPayload: Codable, Equatable, Sendable {
    var url: String
    var title: String?
}

nonisolated enum DenDrawerPayload: Codable, Equatable, Sendable {
    case keep(DenDrawerKeepPayload)
    case place(id: String)
    case discard(id: String)
}

nonisolated enum DenTerminalPayload: Codable, Equatable, Sendable {
    case send(text: String)
    case run(command: String)
    case kill(signal: String)
}

nonisolated enum DenProfilePayload: Codable, Equatable, Sendable {
    case open(profileID: String?)
}

nonisolated enum DenIPCRequestPayload: Codable, Equatable, Sendable {
    case sheet(DenSheetPayload)
    case board(DenBoardPayload)
    case drawer(DenDrawerPayload)
    case terminal(DenTerminalPayload)
    case profile(DenProfilePayload)
}

nonisolated enum DenIPCInputError: Error, Equatable, LocalizedError, Sendable {
    case usage(String)
    case legacyArguments

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            message
        case .legacyArguments:
            "The IPC request field 'args' is no longer supported; use 'payload'"
        }
    }
}

nonisolated struct DenIPCRequest: Codable, Sendable {
    var command: DenIPCCommand
    var payload: DenIPCRequestPayload?
    var boardID: String?
    var deskID: String?
    var callerBoardID: String?
    var profileID: String?

    init(
        command: DenIPCCommand,
        payload: DenIPCRequestPayload? = nil,
        boardID: String? = nil,
        deskID: String? = nil,
        callerBoardID: String? = nil,
        profileID: String? = nil
    ) {
        self.command = command
        self.payload = payload
        self.boardID = boardID
        self.deskID = deskID
        self.callerBoardID = callerBoardID
        self.profileID = profileID
    }

    enum CodingKeys: String, CodingKey {
        case command
        case payload
        case boardID
        case deskID
        case callerBoardID
        case profileID
        case args
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.args) {
            throw DenIPCInputError.legacyArguments
        }
        command = try container.decode(DenIPCCommand.self, forKey: .command)
        payload = try container.decodeIfPresent(DenIPCRequestPayload.self, forKey: .payload)
        boardID = try container.decodeIfPresent(String.self, forKey: .boardID)
        deskID = try container.decodeIfPresent(String.self, forKey: .deskID)
        callerBoardID = try container.decodeIfPresent(String.self, forKey: .callerBoardID)
        profileID = try container.decodeIfPresent(String.self, forKey: .profileID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(payload, forKey: .payload)
        try container.encodeIfPresent(boardID, forKey: .boardID)
        try container.encodeIfPresent(deskID, forKey: .deskID)
        try container.encodeIfPresent(callerBoardID, forKey: .callerBoardID)
        try container.encodeIfPresent(profileID, forKey: .profileID)
    }
}

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

nonisolated enum DenSocketOption {
    static func disableSIGPIPE(on fileDescriptor: Int32) {
        var nosigpipe: Int32 = 1
        setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
    }
}
