import Foundation

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
