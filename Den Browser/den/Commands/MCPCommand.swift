import ArgumentParser
import DenIPCProtocol
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
        let server = Server(name: "den", version: "1.0.0", capabilities: .init(tools: .init()))
        let socketPath = socketPath
        let profileID = profileID
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: DenMCPTool.allCases.map(\.definition))
        }
        await server.withMethodHandler(CallTool.self) { params in
            try DenMCPTool.call(params, socketPath: socketPath, profileID: profileID)
        }
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}

private enum DenMCPTool: String, CaseIterable, Sendable {
    case overview = "overview_den"
    case search = "search_den"
    case act = "act_on_result"
    case moveBoard = "move_board"
    case createDesk = "create_desk"
    case openPages = "open_pages"
    case readPage = "read_page"
    case readSelection = "read_selection"
    case readTerminal = "read_terminal"
    case notifications = "list_notifications"

    var definition: Tool {
        switch self {
        case .overview:
            return tool(
                "Get the current Profile's ordered Desks and Boards, including the presented Desk and focused Board."
            )
        case .search:
            return tool(
                "Search Universal Search without changing focus. Results distinguish existing Boards from inputs that create Web Boards, and supply action refs.",
                [
                    "query": string("Name, URL, keywords, UUID, or Universal Search command query."),
                    "kinds": .object([
                        "type": .string("array"),
                        "description": .string("Filter matches by kind. Omit to include all kinds."),
                        "minItems": .int(1),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array(DenMCPTool.searchKinds.map(Value.string)),
                        ]),
                    ]),
                    "limit": limit,
                ],
                required: ["query"]
            )
        case .act:
            return tool(
                "Execute the exact action identified by ref. Search again if a ref expires or its target changes.",
                [
                    "ref": string("Action ref from search_den.", format: "uuid")
                ],
                required: ["ref"]
            )
        case .moveBoard:
            return tool(
                "Move a Board Group to the end of a Desk or beside another Board. Specify board_id and exactly one of desk_id, left_of, or right_of.",
                [
                    "board_id": string("Board UUID to move.", format: "uuid"),
                    "desk_id": string("Destination Desk UUID (places at end of Desk).", format: "uuid"),
                    "left_of": string("Place left of this Board UUID.", format: "uuid"),
                    "right_of": string("Place right of this Board UUID.", format: "uuid"),
                ],
                required: ["board_id"]
            )
        case .createDesk:
            return tool(
                "Create a new Desk from an optional built-in preset (empty, chatGPT, gemini) or a Personal Desk Preset from overview_den. Leaves the presented Desk as it was unless focus is true.",
                [
                    "name": string("Label for the new Desk."),
                    "preset": string(
                        "Built-in preset (empty, chatGPT, gemini) or Personal Desk Preset label or UUID. Omit for an empty Desk."
                    ),
                    "focus": boolean("Switch to the new Desk after creating it (default false)."),
                ],
                required: ["name"]
            )
        case .openPages:
            return tool(
                "Append new Web Boards in input order without switching Desks or changing existing focus. For partial success, retry only entries with an error and reuse the returned Desk ID.",
                [
                    "pages": .object([
                        "type": .string("array"), "minItems": .int(1), "maxItems": .int(20),
                        "items": string("Absolute URL or 'current' for the focused Web Board's page."),
                    ]),
                    "desk": string(
                        "Existing Desk label or UUID. Omit for the presented Desk. An ambiguous label returns choices before making changes."
                    ),
                    "new_desk": string("Label for a new empty Desk. Supply this or desk."),
                ],
                required: ["pages"]
            )
        case .readPage:
            return tool(
                "Read title, actual URL, Markdown, and Board ID. Omit arguments for the focused Web Board's page. Providing a URL opens a new Web Board on the presented Desk without selecting it, including when reading later fails.",
                ["board_id": boardID, "url": string("Absolute URL. Supply this or board_id.")]
            )
        case .readSelection:
            return tool(
                "Read a human's Inspection selection, its ancestors, source page and freshness. An ambiguous target returns Inspection Board choices. Leaves selection and focus as they were.",
                ["board_id": string("Inspection Board UUID.", format: "uuid")]
            )
        case .readTerminal:
            return tool(
                "Read visible screen text or recent history lines from a Terminal Board without changing focus. Omit board_id for the focused Terminal Board or the first Terminal Board on the presented Desk.",
                [
                    "board_id": string("Terminal Board UUID.", format: "uuid"),
                    "lines": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "description": .string("Read the last N lines of retained history, including the screen."),
                    ]),
                ]
            )
        case .notifications:
            return tool(
                "List retained Notifications from the current Profile, newest first, preserving read state.",
                ["unread_only": boolean("Include only unread Notifications."), "limit": limit]
            )
        }
    }

    static func call(_ params: CallTool.Parameters, socketPath: String?, profileID: String?) throws -> CallTool.Result {
        do {
            guard let tool = Self(rawValue: params.name) else {
                throw DenIPCInputError.usage("Unknown Den tool: \(params.name)")
            }
            let arguments = params.arguments ?? [:]
            let operation = try tool.operation(arguments)
            let request = try DenIPCClient.makeRequest(operation: operation, profileID: profileID, callerBoardID: nil)
            let response = try DenIPCClient.sendRequest(request: request, socketPath: socketPath)
            return try tool.result(response)
        } catch {
            return try Self.makeResult(
                Value.object(["error": .string(error.localizedDescription)]),
                isError: true
            )
        }
    }

    private func operation(_ arguments: [String: Value]) throws -> DenIPCOperation {
        let input = DenMCPInput(arguments: arguments)
        let operation: DenIPCOperation
        switch self {
        case .overview:
            operation = .inspectDen(target: .automatic)
        case .search:
            let query = try input.required("query", as: String.self)
            guard query.utf8.count <= 8_192 else { throw DenIPCInputError.usage("Query is too long") }
            let kinds: [String]? = try input.decode("kinds")
            if let kinds {
                guard !kinds.isEmpty, kinds.allSatisfy(Self.searchKinds.contains) else {
                    throw DenIPCInputError.usage(
                        "'kinds' must be a non-empty array of: \(Self.searchKinds.joined(separator: ", "))"
                    )
                }
            }
            operation = try .mcp(.search(query: query, limit: input.limit(), kinds: kinds))
        case .act:
            operation = try .mcp(.act(ref: input.required("ref", as: UUID.self)))
        case .moveBoard:
            let boardID = try input.required("board_id", as: UUID.self)
            let deskID: UUID? = try input.decode("desk_id")
            let leftOf: UUID? = try input.decode("left_of")
            let rightOf: UUID? = try input.decode("right_of")
            let destination: DenBoardMoveDestination
            switch (deskID, leftOf, rightOf) {
            case (let id?, nil, nil): destination = .endOfDesk(id)
            case (nil, let id?, nil): destination = .leftOf(id)
            case (nil, nil, let id?): destination = .rightOf(id)
            default:
                throw DenIPCInputError.usage("Specify exactly one of 'desk_id', 'left_of', or 'right_of'")
            }
            operation = .moveBoard(boardID: boardID, destination: destination)
        case .createDesk:
            operation = try .mcp(
                .createDesk(
                    name: input.required("name", as: String.self),
                    preset: input.decode("preset"),
                    focus: input.decode("focus") ?? false
                )
            )
        case .openPages:
            operation = try .mcp(
                .openPages(
                    pages: input.required("pages", as: [String].self),
                    desk: input.decode("desk"),
                    newDesk: input.decode("new_desk")
                )
            )
        case .readPage:
            operation = try .mcp(.readPage(boardID: input.decode("board_id"), url: input.decode("url")))
        case .readSelection:
            operation = try .mcp(.readSelection(boardID: input.decode("board_id")))
        case .readTerminal:
            let lines: Int? = try input.decode("lines")
            if let lines, lines <= 0 {
                throw DenIPCInputError.usage("'lines' must be a positive integer")
            }
            let target: BoardTarget = try input.decode("board_id").map(BoardTarget.explicit) ?? .automatic
            operation = .terminal(command: .text(lines: lines), target: target)
        case .notifications:
            operation = try .listNotifications(
                unreadOnly: input.decode("unread_only") ?? false,
                boardID: nil,
                limit: input.limit()
            )
        }
        if case .object(let schema) = definition.inputSchema,
            case .object(let properties) = schema["properties"],
            let unknown = arguments.keys.sorted().first(where: { properties[$0] == nil })
        {
            throw DenIPCInputError.usage("Unknown argument '\(unknown)' for \(rawValue)")
        }
        return operation
    }

    private func result(_ response: DenIPCResponse) throws -> CallTool.Result {
        let data = try JSONEncoder().encode(response.result.publicJSON)
        var output = try JSONDecoder().decode([String: Value].self, from: data)
        output.removeValue(forKey: "ok")
        if self == .overview {
            if case .object(let desk) = output.removeValue(forKey: "active_desk") {
                output["active_desk_id"] = desk["id"]
            }
            for key in ["boards", "profiles", "profile_id"] {
                output.removeValue(forKey: key)
            }
        } else {
            switch response.target {
            case .none: break
            case .profile(let profileID):
                output["profile_id"] = .string(profileID.uuidString)
            case .board(let profileID, let boardID):
                output["profile_id"] = .string(profileID.uuidString)
                output["board_id"] = output["board_id"] ?? .string(boardID.uuidString)
            }
        }
        return try Self.makeResult(Value.object(output), isError: !response.result.isOk)
    }

    private static func makeResult(_ value: Value, isError: Bool) throws -> CallTool.Result {
        guard let text = String(bytes: try JSONEncoder().encode(value), encoding: .utf8) else {
            throw DenIPCInputError.usage("Den Browser returned an invalid result")
        }
        return try CallTool.Result(
            content: [.text(text: text, annotations: nil, _meta: nil)],
            structuredContent: value,
            isError: isError
        )
    }

    private func tool(_ description: String, _ properties: [String: Value] = [:], required: [String] = []) -> Tool {
        let annotations: Tool.Annotations
        switch self {
        case .overview, .search, .readSelection, .readTerminal, .notifications:
            annotations = .init(readOnlyHint: true, openWorldHint: false)
        case .createDesk, .moveBoard, .openPages, .readPage:
            annotations = .init(readOnlyHint: false, destructiveHint: false)
        case .act:
            annotations = .init(readOnlyHint: false, destructiveHint: true)
        }
        return Tool(
            name: rawValue,
            description: description,
            inputSchema: .object([
                "type": .string("object"), "properties": .object(properties),
                "required": .array(required.map(Value.string)), "additionalProperties": .bool(false),
            ]),
            annotations: annotations
        )
    }

    private static let searchKinds = ["board", "desk", "recent", "essential", "input"]

    private var boardID: Value { string("Web Board UUID.", format: "uuid") }

    private var limit: Value {
        .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(20), "default": .int(5)])
    }

    private func string(_ description: String, format: String? = nil) -> Value {
        var schema: [String: Value] = ["type": .string("string"), "description": .string(description)]
        if let format { schema["format"] = .string(format) }
        return .object(schema)
    }

    private func boolean(_ description: String) -> Value {
        .object(["type": .string("boolean"), "description": .string(description)])
    }
}

private struct DenMCPInput {
    let arguments: [String: Value]

    func decode<T: Decodable>(_ key: String) throws -> T? {
        guard let value = arguments[key] else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
        } catch {
            throw DenIPCInputError.usage("Invalid '\(key)' argument")
        }
    }

    func required<T: Decodable>(_ key: String, as type: T.Type) throws -> T {
        guard let value: T = try decode(key) else { throw DenIPCInputError.usage("'\(key)' is required") }
        return value
    }

    func limit() throws -> Int {
        let value: Int = try decode("limit") ?? 5
        guard (1...20).contains(value) else { throw DenIPCInputError.usage("'limit' must be between 1 and 20") }
        return value
    }
}
