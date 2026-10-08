import Foundation

public nonisolated struct DenSheetInteractStep: Codable, Equatable, Sendable {
    public var line: Int
    public var text: String
    public var command: DenIPCCommand.Sheet

    public init(
        line: Int,
        text: String,
        command: DenIPCCommand.Sheet
    ) {
        self.line = line
        self.text = text
        self.command = command
    }
}

public nonisolated struct DenSheetGetTargetPayload: Codable, Equatable, Sendable {
    public let target: String

    public init(target: String) throws {
        self.target = target
        try validate()
    }

    private func validate() throws {
        guard !target.isEmpty else {
            throw DenIPCInputError.usage("The Sheet get target must not be empty")
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(target: container.decode(String.self, forKey: .target))
    }

    private enum CodingKeys: String, CodingKey {
        case target
    }
}

public nonisolated struct DenSheetGetAttributePayload: Codable, Equatable, Sendable {
    public let target: String
    public let attribute: String

    public init(target: String, attribute: String) throws {
        self.target = target
        self.attribute = attribute
        try validate()
    }

    private func validate() throws {
        guard !target.isEmpty else {
            throw DenIPCInputError.usage("The Sheet get target must not be empty")
        }
        guard !attribute.isEmpty else {
            throw DenIPCInputError.usage("The Sheet get attribute name must not be empty")
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            target: container.decode(String.self, forKey: .target),
            attribute: container.decode(String.self, forKey: .attribute)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case attribute
    }
}

public nonisolated struct DenSheetStatePayload: Codable, Equatable, Sendable {
    public var target: String

    public init(target: String) throws {
        self.target = target
        try validate()
    }

    public func validate() throws {
        guard !target.isEmpty else {
            throw DenIPCInputError.usage("The Sheet state target must not be empty")
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(target: container.decode(String.self, forKey: .target))
    }

    private enum CodingKeys: String, CodingKey {
        case target
    }
}

public nonisolated struct DenSheetInteractPayload: Codable, Equatable, Sendable {
    public var steps: [DenSheetInteractStep]

    public init(steps: [DenSheetInteractStep]) {
        self.steps = steps
    }
}

public nonisolated struct DenSheetNavigatePayload: Codable, Equatable, Sendable {
    public var url: String

    public init(
        url: String
    ) {
        self.url = url
    }
}

public nonisolated struct DenSheetEvalPayload: Codable, Equatable, Sendable {
    public var script: String

    public init(
        script: String
    ) {
        self.script = script
    }
}

public nonisolated struct DenSheetPressPayload: Codable, Equatable, Sendable {
    public var key: String

    public init(
        key: String
    ) {
        self.key = key
    }
}

public nonisolated struct DenSheetScrollPayload: Codable, Equatable, Sendable {
    public var directionOrTarget: String?

    public init(
        directionOrTarget: String? = nil
    ) {
        self.directionOrTarget = directionOrTarget
    }
}

public nonisolated struct DenSheetWaitPayload: Codable, Equatable, Sendable {
    public var target: String?
    public var state: String?
    public var url: String?
    public var text: String?
    public var loadState: String?
    public var function: String?
    public var timeout: Double

    public init(
        target: String? = nil,
        state: String? = nil,
        url: String? = nil,
        text: String? = nil,
        loadState: String? = nil,
        function: String? = nil,
        timeout: Double
    ) {
        self.target = target
        self.state = state
        self.url = url
        self.text = text
        self.loadState = loadState
        self.function = function
        self.timeout = timeout
    }
}

public nonisolated struct DenSheetScreenshotPayload: Codable, Equatable, Sendable {
    public var outputPath: String?

    public init(
        outputPath: String? = nil
    ) {
        self.outputPath = outputPath
    }
}

public nonisolated struct DenSheetSnapshotPayload: Codable, Equatable, Sendable {
    public var full: Bool
    public var within: String?

    public init(
        full: Bool,
        within: String? = nil
    ) {
        self.full = full
        self.within = within
    }
}

public nonisolated struct DenSheetQueryPayload: Codable, Equatable, Sendable {
    public var selector: String
    public var visible: Bool
    public var all: Bool
    public var fields: String?

    public init(
        selector: String,
        visible: Bool,
        all: Bool,
        fields: String? = nil
    ) {
        self.selector = selector
        self.visible = visible
        self.all = all
        self.fields = fields
    }
}

public nonisolated struct DenSheetClickPayload: Codable, Equatable, Sendable {
    public var target: String?
    public var role: String?
    public var name: String?
    public var exact: Bool
    public var newBoard: Bool
    public var focus: Bool

    public init(
        target: String? = nil,
        role: String? = nil,
        name: String? = nil,
        exact: Bool,
        newBoard: Bool,
        focus: Bool
    ) {
        self.target = target
        self.role = role
        self.name = name
        self.exact = exact
        self.newBoard = newBoard
        self.focus = focus
    }
}

public nonisolated struct DenSheetElementTargetPayload: Codable, Equatable, Sendable {
    public var target: String

    public init(
        target: String
    ) {
        self.target = target
    }
}

public nonisolated struct DenSheetFillPayload: Codable, Equatable, Sendable {
    public var target: String
    public var value: String

    public init(
        target: String,
        value: String
    ) {
        self.target = target
        self.value = value
    }
}

public nonisolated struct DenSheetTypePayload: Codable, Equatable, Sendable {
    public var target: String?
    public var text: String

    public init(
        target: String? = nil,
        text: String
    ) {
        self.target = target
        self.text = text
    }
}

public nonisolated struct DenSheetDragPayload: Codable, Equatable, Sendable {
    public var source: String
    public var destination: String?
    public var deltaX: Double?
    public var deltaY: Double?
    public var steps: Int

    public init(
        source: String,
        destination: String? = nil,
        deltaX: Double? = nil,
        deltaY: Double? = nil,
        steps: Int
    ) {
        self.source = source
        self.destination = destination
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.steps = steps
    }
}

public nonisolated struct DenSheetMousePayload: Codable, Equatable, Sendable {
    public var coordX: Double?
    public var coordY: Double?
    public var button: String?
    public var count: Int?
    public var deltaX: Double?
    public var deltaY: Double?

    public init(
        coordX: Double? = nil,
        coordY: Double? = nil,
        button: String? = nil,
        count: Int? = nil,
        deltaX: Double? = nil,
        deltaY: Double? = nil
    ) {
        self.coordX = coordX
        self.coordY = coordY
        self.button = button
        self.count = count
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

public nonisolated struct DenBoardWebNewPayload: Codable, Equatable, Sendable {
    public var url: String
    public var focus: Bool
    public var width: Double?

    public init(
        url: String,
        focus: Bool,
        width: Double? = nil
    ) {
        self.url = url
        self.focus = focus
        self.width = width
    }
}

public nonisolated struct DenBoardTerminalNewPayload: Codable, Equatable, Sendable {
    public var path: String?
    public var runCommand: String?
    public var focus: Bool
    public var width: Double?

    public init(
        path: String? = nil,
        runCommand: String? = nil,
        focus: Bool,
        width: Double? = nil
    ) {
        self.path = path
        self.runCommand = runCommand
        self.focus = focus
        self.width = width
    }
}

public nonisolated struct DenBoardInspectionNewPayload: Codable, Equatable, Sendable {
    public var focus: Bool

    public init(
        focus: Bool
    ) {
        self.focus = focus
    }
}

public nonisolated struct DenInspectionElementInfo: Codable, Sendable {
    public var nodeID: String?
    public var ref: String?
    public var selector: String?
    public var tag: String
    public var id: String
    public var className: String
    public var role: String
    public var ariaLabel: String
    public var text: String
    public var attributes: [String]
    public var labels: [String]
    public var capturedAt: String?
    public var isConnected: Bool

    public init(
        nodeID: String? = nil,
        ref: String? = nil,
        selector: String? = nil,
        tag: String,
        id: String,
        className: String,
        role: String,
        ariaLabel: String,
        text: String,
        attributes: [String],
        labels: [String],
        capturedAt: String? = nil,
        isConnected: Bool
    ) {
        self.nodeID = nodeID
        self.ref = ref
        self.selector = selector
        self.tag = tag
        self.id = id
        self.className = className
        self.role = role
        self.ariaLabel = ariaLabel
        self.text = text
        self.attributes = attributes
        self.labels = labels
        self.capturedAt = capturedAt
        self.isConnected = isConnected
    }
    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case ref, selector
        case tag, id
        case className = "class_name"
        case role
        case ariaLabel = "aria_label"
        case text, attributes, labels
        case capturedAt = "captured_at"
        case isConnected = "is_connected"
    }
}

public nonisolated struct DenInspectionNodeInfo: Codable, Sendable {
    public var nodeID: String
    public var tag: String
    public var attributes: [DenInspectionAttributeInfo]
    public var text: String
    public var childCount: Int

    public init(
        nodeID: String,
        tag: String,
        attributes: [DenInspectionAttributeInfo],
        text: String,
        childCount: Int
    ) {
        self.nodeID = nodeID
        self.tag = tag
        self.attributes = attributes
        self.text = text
        self.childCount = childCount
    }
    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case tag, attributes, text
        case childCount = "child_count"
    }
}

public nonisolated struct DenInspectionAttributeInfo: Codable, Sendable {
    public var name: String
    public var value: String

    public init(
        name: String,
        value: String
    ) {
        self.name = name
        self.value = value
    }
}

public nonisolated struct DenInspectionEventInfo: Codable, Sendable {
    public var id: String
    public var time: String
    public var level: String
    public var message: String

    public init(
        id: String,
        time: String,
        level: String,
        message: String
    ) {
        self.id = id
        self.time = time
        self.level = level
        self.message = message
    }
}

public nonisolated struct DenInspectionReadInfo: Codable, Sendable {
    public var boardID: String
    public var targetBoardID: String
    public var url: String?
    public var pageGeneration: Int
    public var documentID: String
    public var capturedAt: String
    public var collectionStartedAt: String?
    public var selection: DenInspectionElementInfo?
    public var ancestors: [DenInspectionNodeInfo]
    public var events: [DenInspectionEventInfo]
    public var eventsDropped: Int

    public init(
        boardID: String,
        targetBoardID: String,
        url: String? = nil,
        pageGeneration: Int,
        documentID: String,
        capturedAt: String,
        collectionStartedAt: String? = nil,
        selection: DenInspectionElementInfo? = nil,
        ancestors: [DenInspectionNodeInfo],
        events: [DenInspectionEventInfo],
        eventsDropped: Int
    ) {
        self.boardID = boardID
        self.targetBoardID = targetBoardID
        self.url = url
        self.pageGeneration = pageGeneration
        self.documentID = documentID
        self.capturedAt = capturedAt
        self.collectionStartedAt = collectionStartedAt
        self.selection = selection
        self.ancestors = ancestors
        self.events = events
        self.eventsDropped = eventsDropped
    }
    enum CodingKeys: String, CodingKey {
        case boardID = "board_id"
        case targetBoardID = "target_board_id"
        case url
        case pageGeneration = "page_generation"
        case documentID = "document_id"
        case capturedAt = "captured_at"
        case collectionStartedAt = "collection_started_at"
        case selection, ancestors, events
        case eventsDropped = "events_dropped"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(boardID, forKey: .boardID)
        try container.encode(targetBoardID, forKey: .targetBoardID)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(pageGeneration, forKey: .pageGeneration)
        try container.encode(documentID, forKey: .documentID)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encodeIfPresent(collectionStartedAt, forKey: .collectionStartedAt)
        try container.encode(selection, forKey: .selection)
        try container.encode(ancestors, forKey: .ancestors)
        try container.encode(events, forKey: .events)
        try container.encode(eventsDropped, forKey: .eventsDropped)
    }
}

public nonisolated struct DenDrawerKeepPayload: Codable, Equatable, Sendable {
    public var url: String
    public var title: String?

    public init(
        url: String,
        title: String? = nil
    ) {
        self.url = url
        self.title = title
    }
}
