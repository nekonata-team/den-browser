import ArgumentParser
import Foundation
import MCP

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Run Den's Model Context Protocol server"
    )

    @Option(name: .customLong("socket"), help: "Custom Den Browser socket path")
    var socketPath: String?

    @Option(name: .customLong("profile"), help: "Target Profile UUID")
    var profileID: String?

    func run() async throws {
        let server = Server(
            name: "den",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )
        let runner = DenMCPToolRunner(socketPath: socketPath, profileID: profileID)
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: DenMCPToolDefinition.all.map(\.tool))
        }
        await server.withMethodHandler(CallTool.self) { params in
            await runner.call(params)
        }

        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}

private enum DenMCPToolName: String, Sendable {
    case inspectDen = "inspect_den"
    case openProfile = "open_profile"
    case createWebBoard = "create_web_board"
    case openSheet = "open_sheet"
    case inspectSheet = "inspect_sheet"
    case readSheetText = "read_sheet_text"
    case querySheet = "query_sheet"
    case readSheetElement = "read_sheet_element"
    case readSheetState = "read_sheet_state"
    case clickSheetElement = "click_sheet_element"
    case fillSheetField = "fill_sheet_field"
    case typeSheetText = "type_sheet_text"
    case pressSheetKey = "press_sheet_key"
    case scrollSheet = "scroll_sheet"
    case waitForSheet = "wait_for_sheet"
    case navigateSheetHistory = "navigate_sheet_history"
    case reloadSheet = "reload_sheet"
    case closeBoard = "close_board"
    case listDrawerItems = "list_drawer_items"
    case saveURLToDrawer = "save_url_to_drawer"
    case placeDrawerItem = "place_drawer_item"
    case discardDrawerItem = "discard_drawer_item"
    case createTerminalBoard = "create_terminal_board"
    case readTerminalSession = "read_terminal_session"
    case runTerminalCommand = "run_terminal_command"
}

private enum DenMCPArgument: String, Sendable {
    case profileID = "profile_id"
    case boardID = "board_id"
    case url
    case focus
    case full
    case within
    case selector
    case visible
    case all
    case fields
    case target
    case field
    case attribute
    case state
    case role
    case name
    case exact
    case openInNewBoard = "open_in_new_board"
    case focusNewBoard = "focus_new_board"
    case value
    case text
    case key
    case direction
    case loadState = "load_state"
    case timeoutSeconds = "timeout_seconds"
    case itemID = "item_id"
    case title
    case path
    case command
}

private enum DenMCPOutputField: String {
    case profiles
    case profile
    case profileID = "profile_id"
    case desks
    case activeDesk = "active_desk"
    case boards
    case focusedBoardID = "focused_board_id"
    case drawerItemCount = "drawer_item_count"
    case boardID = "board_id"
    case url
    case message
    case snapshot
    case text
    case elements
    case value
    case attribute
    case count
    case box
    case visible
    case enabled
    case checked
    case closedBoardID = "closed_board_id"
    case drawerItems = "drawer_items"
    case drawerItemID = "drawer_item_id"
}

private enum DenMCPReadSheetElementField: String, CaseIterable, Sendable {
    case text
    case value
    case attribute
    case count
    case box
}

private enum DenMCPReadSheetState: String, CaseIterable, Sendable {
    case visible
    case enabled
    case checked
}

private enum DenMCPScrollDirection: String, CaseIterable, Sendable {
    case down
    case upward = "up"
    case top
    case bottom
}

private enum DenMCPWaitState: String, CaseIterable, Sendable {
    case attached
    case visible
    case hidden
    case detached
}

private enum DenMCPLoadState: String, CaseIterable, Sendable {
    case commit
    case domContentLoaded = "domcontentloaded"
    case load
    case networkidle
}

private enum DenMCPHistoryDirection: String, CaseIterable, Sendable {
    case back
    case forward
}

private struct DenMCPToolDefinition: Sendable {
    let name: DenMCPToolName
    let description: String
    let properties: [DenMCPArgument: Value]
    let required: [DenMCPArgument]
    let annotations: Tool.Annotations

    var tool: Tool {
        Tool(
            name: name.rawValue,
            description: description,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(Self.wireProperties(properties)),
                "required": .array(required.map { .string($0.rawValue) }),
                "additionalProperties": .bool(false),
            ]),
            annotations: annotations,
            outputSchema: DenMCPToolDefinition.outputSchema(for: name)
        )
    }

    static let all: [Self] = [
        .init(
            .inspectDen, "Inspect Profiles, Desks, Boards, focus, and Drawer count.", [.profileID: uuid()],
            readOnly: true),
        .init(.openProfile, "Open or activate a Profile Window.", [.profileID: uuid()], [.profileID]),
        .init(
            .createWebBoard, "Create a Web Board from a URL, hostname, or search query; focus defaults to false.",
            [.url: string(), .profileID: uuid(), .focus: bool()], [.url]),
        .init(
            .openSheet, "Navigate the target Web Board to a URL or search query.",
            [.url: string(), .profileID: uuid(), .boardID: uuid()], [.url]),
        .init(
            .inspectSheet, "Read the Current Sheet URL and semantic snapshot; full defaults to false.",
            [.profileID: uuid(), .boardID: uuid(), .full: bool(), .within: string()], readOnly: true),
        .init(.readSheetText, "Read visible text from the Current Sheet.", sheetTarget, readOnly: true),
        .init(
            .querySheet,
            "Return matching elements; fields defaults to tag, role, name, and text; visible and all default to false.",
            merge(
                sheetTarget,
                [
                    .selector: string(), .visible: bool(), .all: bool(),
                    .fields: stringArray(
                        "Use tag, role, name, text, value, checked, disabled, selected, expanded, class, or attr:<name>."
                    ),
                ]), [.selector], readOnly: true),
        .init(
            .readSheetElement,
            "Read an element's text, value, attribute, count, or box; attribute requires an attribute name.",
            merge(
                sheetTarget,
                [
                    .target: string(), .field: enumeration(DenMCPReadSheetElementField.self),
                    .attribute: string(),
                ]), [.target, .field], readOnly: true),
        .init(
            .readSheetState, "Check whether a Sheet element is visible, enabled, or checked.",
            merge(
                sheetTarget,
                [
                    .target: string(), .state: enumeration(DenMCPReadSheetState.self),
                ]), [.target, .state], readOnly: true),
        .init(
            .clickSheetElement, "Click by target or by role and name; focus_new_board requires open_in_new_board.",
            merge(
                sheetTarget,
                [
                    .target: string(), .role: string(), .name: string(), .exact: bool(),
                    .openInNewBoard: bool(), .focusNewBoard: bool(),
                ]), destructive: false),
        .init(
            .fillSheetField, "Fill an input, textarea, or editable Sheet element.",
            merge(
                sheetTarget,
                [
                    .target: string(), .value: string(),
                ]), [.target, .value], destructive: false),
        .init(
            .typeSheetText, "Type text into a target or the focused Sheet element.",
            merge(
                sheetTarget,
                [
                    .text: string(), .target: string(),
                ]), [.text], destructive: false),
        .init(
            .pressSheetKey, "Press a supported key in the target Sheet.", merge(sheetTarget, [.key: string()]),
            [.key], destructive: false),
        .init(
            .scrollSheet, "Provide direction or target, not both; direction defaults to down.",
            merge(
                sheetTarget,
                [
                    .direction: enumeration(DenMCPScrollDirection.self), .target: string(),
                ]), destructive: false),
        .init(
            .waitForSheet,
            "Wait for exactly one target, URL, text, or load_state; state requires target; timeout defaults to 10 seconds.",
            merge(
                sheetTarget,
                [
                    .target: string(), .state: enumeration(DenMCPWaitState.self),
                    .url: string(), .text: string(),
                    .loadState: enumeration(DenMCPLoadState.self),
                    .timeoutSeconds: number(),
                ]), destructive: false),
        .init(
            .navigateSheetHistory, "Move the target Sheet Stack backward or forward.",
            merge(
                sheetTarget,
                [
                    .direction: enumeration(DenMCPHistoryDirection.self)
                ]), [.direction], destructive: false),
        .init(.reloadSheet, "Reload the target Current Sheet.", sheetTarget, destructive: false),
        .init(
            .closeBoard, "Remove a Board from its Desk and end its live runtime.",
            [
                .boardID: uuid(), .profileID: uuid(),
            ], [.boardID], destructive: true),
        .init(.listDrawerItems, "List Drawer Items by ID, title, and URL.", profileTarget, readOnly: true),
        .init(
            .saveURLToDrawer, "Keep a URL in the Den-wide Drawer.",
            merge(
                profileTarget,
                [
                    .url: string(), .title: string(),
                ]), [.url], destructive: false),
        .init(
            .placeDrawerItem, "Place a Drawer Item on the active Desk as a Web Board.",
            merge(profileTarget, [.itemID: string()]), [.itemID], destructive: false),
        .init(
            .discardDrawerItem, "Discard a Drawer Item.", merge(profileTarget, [.itemID: string()]), [.itemID],
            destructive: true),
        .init(
            .createTerminalBoard,
            "Create a Terminal Board at an optional working directory; focus defaults to false.",
            merge(
                profileTarget,
                [
                    .path: string(), .focus: bool(),
                ]), destructive: false),
        .init(
            .readTerminalSession, "Read the visible buffer of a Terminal Session.", terminalTarget, readOnly: true),
        .init(
            .runTerminalCommand, "Send a command to the target Terminal Session and press Enter.",
            merge(
                terminalTarget,
                [
                    .command: string()
                ]), [.command], destructive: true),
    ]

    private static let profileTarget: [DenMCPArgument: Value] = [.profileID: uuid()]
    private static let sheetTarget: [DenMCPArgument: Value] = [.profileID: uuid(), .boardID: uuid()]
    private static let terminalTarget: [DenMCPArgument: Value] = [.profileID: uuid(), .boardID: uuid()]
    private static let objectSchema: Value = .object(["type": .string("object"), "additionalProperties": .bool(true)])
    private static let arraySchema: Value = .object([
        "type": .string("array"),
        "items": .object(["type": .string("object"), "additionalProperties": .bool(true)]),
    ])
    private static let stringSchema: Value = .object(["type": .string("string")])
    private static let integerSchema: Value = .object(["type": .string("integer")])
    private static let booleanSchema: Value = .object(["type": .string("boolean")])

    private static func outputSchema(for name: DenMCPToolName) -> Value {
        let profile: [DenMCPOutputField: Value] = [.profileID: stringSchema]
        let board: [DenMCPOutputField: Value] = [.profileID: stringSchema, .boardID: stringSchema]
        let fields: [DenMCPOutputField: Value] =
            switch name {
            case .inspectDen:
                [
                    .profiles: arraySchema, .profile: objectSchema, .profileID: stringSchema,
                    .desks: arraySchema, .activeDesk: objectSchema, .boards: arraySchema,
                    .focusedBoardID: stringSchema, .drawerItemCount: integerSchema,
                ]
            case .openProfile: profile.merging([.message: stringSchema]) { _, new in new }
            case .createWebBoard, .createTerminalBoard:
                profile.merging([.boardID: stringSchema]) { _, new in new }
            case .openSheet: board.merging([.url: stringSchema, .message: stringSchema]) { _, new in new }
            case .inspectSheet: board.merging([.url: stringSchema, .snapshot: stringSchema]) { _, new in new }
            case .readSheetText, .readTerminalSession: board.merging([.text: stringSchema]) { _, new in new }
            case .querySheet: board.merging([.elements: arraySchema]) { _, new in new }
            case .readSheetElement:
                board.merging([
                    .text: stringSchema, .value: stringSchema, .attribute: stringSchema,
                    .count: integerSchema, .box: objectSchema,
                ]) { _, new in new }
            case .readSheetState:
                board.merging([
                    .visible: booleanSchema, .enabled: booleanSchema, .checked: booleanSchema,
                ]) { _, new in new }
            case .clickSheetElement:
                board.merging([.message: stringSchema, .url: stringSchema]) { _, new in new }
            case .closeBoard:
                board.merging([.closedBoardID: stringSchema, .message: stringSchema]) { _, new in new }
            case .listDrawerItems: profile.merging([.drawerItems: arraySchema]) { _, new in new }
            case .saveURLToDrawer:
                profile.merging([.drawerItemID: stringSchema, .message: stringSchema]) { _, new in new }
            case .placeDrawerItem: board.merging([.message: stringSchema]) { _, new in new }
            case .discardDrawerItem: profile.merging([.message: stringSchema]) { _, new in new }
            case .fillSheetField, .typeSheetText, .pressSheetKey, .scrollSheet, .waitForSheet,
                .navigateSheetHistory, .reloadSheet, .runTerminalCommand:
                board.merging([.message: stringSchema]) { _, new in new }
            }
        return .object([
            "type": .string("object"),
            "properties": .object(wireProperties(fields)),
            "additionalProperties": .bool(false),
        ])
    }

    private init(
        _ name: DenMCPToolName,
        _ description: String,
        _ properties: [DenMCPArgument: Value],
        _ required: [DenMCPArgument] = [],
        readOnly: Bool? = nil,
        destructive: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.properties = properties
        self.required = required
        annotations = .init(readOnlyHint: readOnly, destructiveHint: destructive)
    }

    private static func merge<Key: Hashable>(_ first: [Key: Value], _ second: [Key: Value]) -> [Key: Value] {
        first.merging(second) { _, new in new }
    }

    private static func wireProperties<Key: RawRepresentable>(_ properties: [Key: Value]) -> [String: Value]
    where Key.RawValue == String {
        Dictionary(uniqueKeysWithValues: properties.map { ($0.key.rawValue, $0.value) })
    }

    private static func string(_ description: String? = nil, format: String? = nil) -> Value {
        var schema: [String: Value] = ["type": .string("string")]
        if let description { schema["description"] = .string(description) }
        if let format { schema["format"] = .string(format) }
        return .object(schema)
    }

    private static func uuid() -> Value { string(format: "uuid") }
    private static func bool() -> Value { .object(["type": .string("boolean")]) }
    private static func number() -> Value { .object(["type": .string("number"), "minimum": .int(0)]) }
    private static func stringArray(_ description: String? = nil) -> Value {
        var schema: [String: Value] = ["type": .string("array"), "items": string()]
        if let description { schema["description"] = .string(description) }
        return .object(schema)
    }
    private static func enumeration<Option: RawRepresentable & CaseIterable>(_ type: Option.Type) -> Value
    where Option.RawValue == String {
        .object(["type": .string("string"), "enum": .array(type.allCases.map { .string($0.rawValue) })])
    }
}

private struct DenMCPToolRunner: Sendable {
    let socketPath: String?
    let profileID: String?

    func call(_ params: CallTool.Parameters) async -> CallTool.Result {
        guard let name = DenMCPToolName(rawValue: params.name),
            let definition = DenMCPToolDefinition.all.first(where: { $0.name == name })
        else {
            return Self.error("Unknown Den tool: \(params.name)")
        }

        do {
            let input = try DenMCPToolInput(params.arguments ?? [:], definition: definition)
            let command = try makeCommand(input, name: name)
            let (response, _) = try DenIPCClient.sendRequest(
                command: command,
                socketPath: socketPath,
                profileID: try input.string(.profileID) ?? profileID,
                boardID: try input.string(.boardID),
                includeTargetContext: true
            )
            guard response.isOk else {
                return Self.error(response.error ?? "Den Browser request failed")
            }
            return try Self.success(response)
        } catch {
            return Self.error(error.localizedDescription)
        }
    }

    private func makeCommand(_ input: DenMCPToolInput, name: DenMCPToolName) throws -> DenIPCCommand {
        switch name {
        case .inspectDen:
            return .inspectDen
        case .openProfile:
            return .profile(.open(profileID: try input.requiredString(.profileID)))
        case .createWebBoard:
            return .board(
                .web(
                    .new(
                        DenBoardWebNewPayload(
                            url: try input.requiredString(.url), focus: try input.boolean(.focus))))
            )
        case .openSheet:
            return .sheet(.open(DenSheetOpenPayload(url: try input.requiredString(.url))))
        case .inspectSheet:
            return .sheet(
                .inspect(
                    DenSheetSnapshotPayload(full: try input.boolean(.full), within: try input.string(.within)))
            )
        case .readSheetText:
            return .sheet(.text)
        case .querySheet:
            let fields = try input.strings(.fields)
            return .sheet(
                .query(
                    DenSheetQueryPayload(
                        selector: try input.requiredString(.selector),
                        visible: try input.boolean(.visible),
                        all: try input.boolean(.all),
                        fields: fields.isEmpty ? nil : fields.joined(separator: ",")
                    ))
            )
        case .readSheetElement:
            let target = try input.requiredString(.target)
            switch try input.requiredEnum(.field, as: DenMCPReadSheetElementField.self) {
            case .text: return .sheet(.get(.text(try DenSheetGetTargetPayload(target: target))))
            case .value: return .sheet(.get(.value(try DenSheetGetTargetPayload(target: target))))
            case .attribute:
                return .sheet(
                    .get(
                        .attribute(
                            try DenSheetGetAttributePayload(
                                target: target,
                                attribute: try input.requiredString(.attribute)
                            )))
                )
            case .count: return .sheet(.get(.count(try DenSheetGetTargetPayload(target: target))))
            case .box: return .sheet(.get(.box(try DenSheetGetTargetPayload(target: target))))
            }
        case .readSheetState:
            let target = try DenSheetStatePayload(target: input.requiredString(.target))
            switch try input.requiredEnum(.state, as: DenMCPReadSheetState.self) {
            case .visible: return .sheet(.isState(.visible(target)))
            case .enabled: return .sheet(.isState(.enabled(target)))
            case .checked: return .sheet(.isState(.checked(target)))
            }
        case .clickSheetElement:
            let target = try input.string(.target)
            let role = try input.string(.role)
            let elementName = try input.string(.name)
            let openInNewBoard = try input.boolean(.openInNewBoard)
            let focusNewBoard = try input.boolean(.focusNewBoard)
            guard (target != nil) != (role != nil || elementName != nil), (role == nil) == (elementName == nil) else {
                throw input.invalid(.target, "provide target or both role and name")
            }
            guard !focusNewBoard || openInNewBoard else {
                throw input.invalid(.focusNewBoard, "requires open_in_new_board")
            }
            return .sheet(
                .click(
                    DenSheetClickPayload(
                        target: target,
                        role: role,
                        name: elementName,
                        exact: try input.boolean(.exact),
                        newBoard: openInNewBoard,
                        focus: focusNewBoard
                    ))
            )
        case .fillSheetField:
            return .sheet(
                .fill(
                    DenSheetFillPayload(
                        target: try input.requiredString(.target), value: try input.requiredString(.value)
                    ))
            )
        case .typeSheetText:
            return .sheet(
                .type(
                    DenSheetTypePayload(target: try input.string(.target), text: try input.requiredString(.text)))
            )
        case .pressSheetKey:
            return .sheet(.press(DenSheetPressPayload(key: try input.requiredString(.key))))
        case .scrollSheet:
            let direction = try input.enumValue(.direction, as: DenMCPScrollDirection.self)
            let target = try input.string(.target)
            guard direction == nil || target == nil else {
                throw input.invalid(.direction, "provide direction or target")
            }
            return .sheet(
                .scroll(
                    DenSheetScrollPayload(
                        directionOrTarget: direction?.rawValue ?? target ?? DenMCPScrollDirection.down.rawValue))
            )
        case .waitForSheet:
            let target = try input.string(.target)
            let url = try input.string(.url)
            let text = try input.string(.text)
            let loadState = try input.enumValue(.loadState, as: DenMCPLoadState.self)
            let conditionCount = [target != nil, url != nil, text != nil, loadState != nil].filter { $0 }.count
            guard conditionCount == 1 else {
                throw input.invalid(.target, "provide exactly one of target, url, text, or load_state")
            }
            let state = try input.enumValue(.state, as: DenMCPWaitState.self)
            guard target != nil || state == nil else {
                throw input.invalid(.state, "requires target")
            }
            return .sheet(
                .wait(
                    DenSheetWaitPayload(
                        target: target,
                        state: state?.rawValue,
                        url: url,
                        text: text,
                        loadState: loadState?.rawValue,
                        function: nil,
                        timeout: try input.number(.timeoutSeconds, default: 10)
                    ))
            )
        case .navigateSheetHistory:
            switch try input.requiredEnum(.direction, as: DenMCPHistoryDirection.self) {
            case .back: return .sheet(.back)
            case .forward: return .sheet(.forward)
            }
        case .reloadSheet:
            return .sheet(.reload)
        case .closeBoard:
            return .board(.close)
        case .listDrawerItems:
            return .drawer(.list)
        case .saveURLToDrawer:
            return .drawer(
                .keep(DenDrawerKeepPayload(url: try input.requiredString(.url), title: try input.string(.title)))
            )
        case .placeDrawerItem:
            return .drawer(.place(id: try input.requiredString(.itemID)))
        case .discardDrawerItem:
            return .drawer(.discard(id: try input.requiredString(.itemID)))
        case .createTerminalBoard:
            let path = try input.string(.path).map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            return .board(
                .terminal(
                    .new(
                        DenBoardTerminalNewPayload(
                            path: path,
                            runCommand: nil,
                            focus: try input.boolean(.focus)
                        )))
            )
        case .readTerminalSession:
            return .terminal(.text)
        case .runTerminalCommand:
            return .terminal(.run(command: try input.requiredString(.command)))
        }
    }

    private static func success(_ response: DenIPCResponse) throws -> CallTool.Result {
        guard case .object(var output) = try Value(response) else {
            return error("Den Browser returned an invalid result")
        }
        output.removeValue(forKey: "ok")
        output.removeValue(forKey: "error")
        let value = Value.object(output)
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            return error("Den Browser returned an invalid result")
        }
        return try CallTool.Result(
            content: [.text(text: text, annotations: nil, _meta: nil)],
            structuredContent: value,
            isError: false
        )
    }

    private static func error(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }
}

private struct DenMCPToolInput {
    let arguments: [DenMCPArgument: Value]

    init(_ arguments: [String: Value], definition: DenMCPToolDefinition) throws {
        var parsed: [DenMCPArgument: Value] = [:]
        for (key, value) in arguments {
            guard let argument = DenMCPArgument(rawValue: key) else {
                throw DenMCPInputError("Unknown argument '\(key)' for \(definition.name.rawValue)")
            }
            guard definition.properties[argument] != nil else {
                throw DenMCPInputError("Argument '\(key)' is not recognized for \(definition.name.rawValue)")
            }
            parsed[argument] = value
        }
        for key in definition.required where parsed[key] == nil {
            throw DenMCPInputError("Invalid '\(key.rawValue)' argument: is required")
        }
        self.arguments = parsed
    }

    func requiredString(_ key: DenMCPArgument) throws -> String {
        guard let value = try string(key) else { throw invalid(key, "is required") }
        return value
    }

    func string(_ key: DenMCPArgument) throws -> String? { try decode(key, as: String.self) }

    func boolean(_ key: DenMCPArgument, default defaultValue: Bool = false) throws -> Bool {
        try decode(key, as: Bool.self) ?? defaultValue
    }

    func number(_ key: DenMCPArgument, default defaultValue: Double) throws -> Double {
        let value = try decode(key, as: Double.self) ?? defaultValue
        guard value.isFinite, value >= 0 else { throw invalid(key, "must be a finite non-negative number") }
        return value
    }

    func strings(_ key: DenMCPArgument) throws -> [String] { try decode(key, as: [String].self) ?? [] }

    func enumValue<Option: RawRepresentable & CaseIterable>(
        _ key: DenMCPArgument,
        as type: Option.Type
    ) throws -> Option? where Option.RawValue == String {
        guard let rawValue = try string(key) else { return nil }
        guard let option = Option(rawValue: rawValue) else {
            let choices = type.allCases.map(\.rawValue).joined(separator: ", ")
            throw invalid(key, "must be one of: \(choices)")
        }
        return option
    }

    func requiredEnum<Option: RawRepresentable & CaseIterable>(
        _ key: DenMCPArgument,
        as type: Option.Type
    ) throws -> Option where Option.RawValue == String {
        guard let option = try enumValue(key, as: type) else { throw invalid(key, "is required") }
        return option
    }

    func invalid(_ key: DenMCPArgument, _ reason: String) -> DenMCPInputError {
        DenMCPInputError("Invalid '\(key.rawValue)' argument: \(reason)")
    }

    private func decode<T: Decodable>(_ key: DenMCPArgument, as type: T.Type) throws -> T? {
        guard let value = arguments[key] else { return nil }
        do {
            return try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
        } catch {
            throw invalid(key, "has the wrong type")
        }
    }
}

private struct DenMCPInputError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
