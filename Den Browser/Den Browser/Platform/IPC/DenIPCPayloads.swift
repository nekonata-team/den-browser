import Foundation

nonisolated struct DenSheetInteractStep: Codable, Equatable, Sendable {
    var line: Int
    var text: String
    var command: DenIPCCommand.Sheet
}

nonisolated struct DenSheetGetTargetPayload: Codable, Equatable, Sendable {
    let target: String

    init(target: String) throws {
        self.target = target
        try validate()
    }

    private func validate() throws {
        guard !target.isEmpty else {
            throw DenIPCInputError.usage("The Sheet get target must not be empty")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(target: container.decode(String.self, forKey: .target))
    }

    private enum CodingKeys: String, CodingKey {
        case target
    }
}

nonisolated struct DenSheetGetAttributePayload: Codable, Equatable, Sendable {
    let target: String
    let attribute: String

    init(target: String, attribute: String) throws {
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

    init(from decoder: Decoder) throws {
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

nonisolated struct DenSheetStatePayload: Codable, Equatable, Sendable {
    var target: String

    init(target: String) throws {
        self.target = target
        try validate()
    }

    func validate() throws {
        guard !target.isEmpty else {
            throw DenIPCInputError.usage("The Sheet state target must not be empty")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(target: container.decode(String.self, forKey: .target))
    }

    private enum CodingKeys: String, CodingKey {
        case target
    }
}

nonisolated struct DenSheetInteractPayload: Codable, Equatable, Sendable {
    var steps: [DenSheetInteractStep]
    var full: Bool
    var noSnapshot: Bool = false
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

nonisolated struct DenSheetMousePayload: Codable, Equatable, Sendable {
    var coordX: Double?
    var coordY: Double?
    var button: String?
    var count: Int?
    var deltaX: Double?
    var deltaY: Double?
}

nonisolated struct DenBoardWebNewPayload: Codable, Equatable, Sendable {
    var url: String
    var focus: Bool
    var width: Double?
}

nonisolated struct DenBoardTerminalNewPayload: Codable, Equatable, Sendable {
    var path: String?
    var runCommand: String?
    var focus: Bool
    var width: Double?
}

nonisolated struct DenBoardInspectionNewPayload: Codable, Equatable, Sendable {
    var focus: Bool
}

nonisolated struct DenInspectionElementInfo: Codable, Sendable {
    var nodeID: String?
    var ref: String?
    var selector: String?
    var tag: String
    var id: String
    var className: String
    var role: String
    var ariaLabel: String
    var text: String
    var attributes: [String]
    var labels: [String]
    var capturedAt: String?
    var isConnected: Bool

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

nonisolated struct DenInspectionNodeInfo: Codable, Sendable {
    var nodeID: String
    var tag: String
    var attributes: [DenInspectionAttributeInfo]
    var text: String
    var childCount: Int

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case tag, attributes, text
        case childCount = "child_count"
    }
}

nonisolated struct DenInspectionAttributeInfo: Codable, Sendable {
    var name: String
    var value: String
}

nonisolated struct DenInspectionEventInfo: Codable, Sendable {
    var id: String
    var time: String
    var level: String
    var message: String
}

nonisolated struct DenInspectionReadInfo: Codable, Sendable {
    var boardID: String
    var targetBoardID: String
    var url: String?
    var pageGeneration: Int
    var documentID: String
    var capturedAt: String
    var collectionStartedAt: String?
    var selection: DenInspectionElementInfo?
    var ancestors: [DenInspectionNodeInfo]
    var events: [DenInspectionEventInfo]
    var eventsDropped: Int

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

    func encode(to encoder: Encoder) throws {
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

nonisolated struct DenDrawerKeepPayload: Codable, Equatable, Sendable {
    var url: String
    var title: String?
}
