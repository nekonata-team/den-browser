import ArgumentParser
import Darwin
import DenIPCProtocol
import Foundation

struct CLIOptions: ParsableArguments {
    @Flag(name: .customLong("json"), help: "Output response as JSON")
    var isJSON = false

    @Option(name: .customLong("socket"), help: "Custom socket path (defaults to ~/.den/den.sock)")
    var socketPath: String?

    @Option(name: .customLong("profile"), help: "Target Profile UUID (defaults to $DEN_PROFILE or ambient)")
    var profileID: String?
}

struct BoardTargetOptions: ParsableArguments {
    @OptionGroup var common: CLIOptions

    @Option(name: .customLong("board"), help: "Target specific Board ID (defaults to the ambient Board)")
    var boardID: String?
}

struct WebTargetOptions: ParsableArguments {
    @OptionGroup var target: BoardTargetOptions

    @Flag(name: .long, help: "Include a semantic snapshot with the command result")
    var snapshot = false

    var snapshotPayload: DenSheetSnapshotPayload? {
        snapshot ? DenSheetSnapshotPayload(full: false) : nil
    }
}

private struct CLIOutputOptions {
    let isJSON: Bool
    let showBoardIDs: Bool
}

private enum DenIPCClientError: LocalizedError {
    case createSocket(String)
    case socketPathTooLong(String)
    case connect(String, String)
    case send(String)
    case invalidResponse(String)
    case invalidBoardID(String)
    case invalidProfileID(String)
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .createSocket(let message): "Could not create socket: \(message)"
        case .socketPathTooLong(let path): "Socket path too long: \(path)"
        case .connect(let path, let message): "Could not connect to Den Browser at \(path): \(message)"
        case .send(let message): "Could not send request to Den Browser: \(message)"
        case .invalidResponse(let response): "Invalid response from Den Browser: \(response)"
        case .invalidBoardID(let id): "Invalid board ID: \(id)"
        case .invalidProfileID(let id): "Invalid profile ID: \(id)"
        case .usage(let message): message
        }
    }
}

enum DenIPCClient {
    static func sheetOperation(
        command: DenIPCCommand.Sheet,
        target: BoardTarget,
        snapshot: DenSheetSnapshotPayload? = nil
    ) -> DenIPCOperation {
        guard let snapshot else { return .sheet(command: command, target: target) }
        return .sheetWithSnapshot(command: command, target: target, snapshot: snapshot)
    }

    static func execute(
        operation: @autoclosure () throws -> DenIPCOperation,
        options: CLIOptions,
        showBoardIDs: Bool = false
    ) throws {
        try execute(
            operation: operation,
            options: options,
            output: CLIOutputOptions(isJSON: options.isJSON, showBoardIDs: showBoardIDs)
        )
    }

    static func execute(
        command: @autoclosure () throws -> DenIPCCommand.Sheet,
        options: WebTargetOptions
    ) throws {
        try execute(
            operation: sheetOperation(
                command: try command(),
                target: try boardTarget(options.target.boardID),
                snapshot: options.snapshotPayload
            ),
            options: options.target.common
        )
    }

    static func execute(
        command: @autoclosure () throws -> DenIPCCommand.Sheet,
        options: WebTargetOptions,
        snapshot: DenSheetSnapshotPayload
    ) throws {
        try execute(
            operation: sheetOperation(
                command: try command(),
                target: try boardTarget(options.target.boardID),
                snapshot: snapshot
            ),
            options: options.target.common
        )
    }

    private static func execute(
        operation buildOperation: () throws -> DenIPCOperation,
        options: CLIOptions,
        output: CLIOutputOptions
    ) throws {
        let operation: DenIPCOperation
        let request: DenIPCRequest
        do {
            operation = try buildOperation()
            request = try makeRequest(
                operation: operation,
                profileID: options.profileID
            )
        } catch {
            let result = DenIPCOperationResult.failure(error.localizedDescription)
            let responseData = (try? JSONEncoder().encode(result.publicJSON)) ?? Data()
            try writeResult(result, data: responseData, output: output, isHealth: false)
            return
        }

        let response: DenIPCResponse
        do {
            response = try sendRequest(request: request, socketPath: options.socketPath)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            throw ExitCode.failure
        }

        let result = response.result
        let responseData = try JSONEncoder().encode(result.publicJSON)
        try writeResult(result, data: responseData, output: output, isHealth: operation == .health)
    }

    private static func writeResult(
        _ result: DenIPCOperationResult,
        data responseData: Data,
        output: CLIOutputOptions,
        isHealth: Bool
    ) throws {
        let isJSONOutput = output.isJSON || isatty(STDOUT_FILENO) == 0

        if isJSONOutput {
            if let jsonString = String(data: responseData, encoding: .utf8) {
                print(jsonString.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else {
            if !result.isOk {
                fputs("Error: \(result.error ?? "Unknown error")\n", stderr)
            } else if isHealth {
                print("healthy")
            } else {
                if let payload = result.payload {
                    writeTextResult(payload, output: output)
                }
                if let completedActions = result.completedActions {
                    print("Completed \(completedActions) actions")
                }
                if let snapshot = result.snapshot {
                    print(snapshot)
                }
            }
        }

        if !result.isOk {
            throw ExitCode.failure
        }
    }

    private static func writeTextResult(_ payload: DenIPCResultPayload, output: CLIOutputOptions) {
        switch payload {
        case .empty, .interaction:
            break
        case .message(let message), .closedBoard(_, let message):
            print(message)
        case .createdBoard(let id, _, _), .sheet(let id, _):
            print(id)
        case .board(let board):
            writeBoard(board, showBoardIDs: output.showBoardIDs)
        case .boards(let boards):
            writeBoards(boards, showBoardIDs: output.showBoardIDs)
        case .desks(let desks):
            for desk in desks {
                let mark = desk.isActive ? "*" : " "
                print("\(mark) \(desk.id) - \(desk.label) (\(desk.boardCount) boards)")
            }
        case .drawerItems(let items):
            for item in items {
                let titleSuffix = item.title.map { " - \($0)" } ?? ""
                print("\(item.id)\(titleSuffix) (\(item.url))")
            }
        case .drawerItem(let id, _):
            print(id)
        case .profiles(let profiles):
            writeProfiles(profiles)
        case .denOverview(let overview):
            writeBoards(overview.boards, showBoardIDs: output.showBoardIDs)
        case .navigation(_, let url), .url(let url):
            print(url)
        case .elements(let elements):
            for element in elements {
                var line = element.ref
                if let tag = element.tag {
                    line += " <\(tag)>"
                }
                if let role = element.role {
                    line += " [\(role)]"
                }
                if let text = element.text, !text.isEmpty {
                    line += " \"\(text)\""
                }
                print(line)
            }
        case .text(let text), .value(let text), .attribute(let text), .screenshotPath(let text):
            print(text)
        case .checked(let checked), .visible(let checked), .enabled(let checked):
            print(checked ? "true" : "false")
        case .count(let count):
            print(count)
        case .box(let box):
            print("x: \(box.originX), y: \(box.originY), width: \(box.width), height: \(box.height)")
        case .inspection(let details):
            print("Inspection Board \(details.boardID) for Web Board \(details.targetBoardID)")
            print(details.url ?? "(no URL)")
            if let selection = details.selection {
                print("Selected <\(selection.tag)> \(selection.role) \"\(selection.text)\"")
            } else {
                print("No element selected")
            }
        }
    }

    private static func writeBoard(_ board: DenBoardInfo, showBoardIDs: Bool) {
        let type = "[\(board.type)]"
        let boardIDPrefix = showBoardIDs ? "\(board.id) - " : ""
        let secondary = board.url ?? board.sessionName
        let secondarySuffix = secondary.map { " (\($0))" } ?? ""
        print("* \(type) \(boardIDPrefix)\(board.label)\(secondarySuffix)")
    }

    private static func writeBoards(_ boards: [DenBoardInfo], showBoardIDs: Bool) {
        let typeColumnWidth = boards.map { "[\($0.type)]".count }.max() ?? 0
        for board in boards {
            let mark = board.isFocused ? "*" : " "
            let type = "[\(board.type)]".padding(toLength: typeColumnWidth, withPad: " ", startingAt: 0)
            let boardIDPrefix = showBoardIDs ? "\(board.id) - " : ""
            let secondary = board.url ?? board.sessionName
            let secondarySuffix = secondary.map { " (\($0))" } ?? ""
            print("\(mark) \(type) \(boardIDPrefix)\(board.label)\(secondarySuffix)")
        }
    }

    private static func writeProfiles(_ profiles: [DenProfileInfo]) {
        let nameWidth = profiles.map(\.name.count).max() ?? 4
        let paddedNameHeader = "NAME".padding(toLength: max(nameWidth, 4), withPad: " ", startingAt: 0)
        print("  \(paddedNameHeader)  ID                                    ACTIVE  WINDOW")
        for profile in profiles {
            let mark = profile.isActive ? "*" : " "
            let paddedName = profile.name.padding(toLength: max(nameWidth, 4), withPad: " ", startingAt: 0)
            let activeStr = (profile.isActive ? "yes" : "no").padding(toLength: 6, withPad: " ", startingAt: 0)
            let windowStr = profile.hasWindow ? "yes" : "no"
            print("\(mark) \(paddedName)  \(profile.id)  \(activeStr)  \(windowStr)")
        }
    }

    static func sendRequest(
        request: DenIPCRequest,
        socketPath explicitSocketPath: String? = nil
    ) throws -> DenIPCResponse {
        let environment = ProcessInfo.processInfo.environment
        let socketPath = DenSocketPath.resolve(explicit: explicitSocketPath, environment: environment)
        let requestData = try JSONEncoder().encode(request)

        let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw DenIPCClientError.createSocket(String(cString: strerror(errno)))
        }
        defer { close(socketDescriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw DenIPCClientError.socketPathTooLong(socketPath)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            pathBytes.withUnsafeBytes { source in
                buffer.copyMemory(from: source)
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw DenIPCClientError.connect(socketPath, String(cString: strerror(errno)))
        }

        var packet = requestData
        packet.append(UInt8(ascii: "\n"))
        var writeError: Int32?
        packet.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var written = 0
            while written < buffer.count {
                let count = send(
                    socketDescriptor,
                    baseAddress.advanced(by: written),
                    buffer.count - written,
                    MSG_NOSIGNAL
                )
                guard count > 0 else {
                    writeError = errno
                    break
                }
                written += count
            }
        }
        if let writeError {
            throw DenIPCClientError.send(String(cString: strerror(writeError)))
        }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(socketDescriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            responseData.append(buffer, count: count)
            if responseData.contains(UInt8(ascii: "\n")) { break }
        }

        guard let response = try? JSONDecoder().decode(DenIPCResponse.self, from: responseData) else {
            throw DenIPCClientError.invalidResponse(String(data: responseData, encoding: .utf8) ?? "")
        }
        return response
    }

    static func makeRequest(
        operation: DenIPCOperation,
        profileID: String? = nil,
        callerBoardID: String? = ProcessInfo.processInfo.environment["DEN_BOARD_ID"]
    ) throws -> DenIPCRequest {
        let usesProfileScope: Bool
        switch operation {
        case .health, .profileList, .openProfile:
            usesProfileScope = false
        default:
            usesProfileScope = true
        }

        let rawProfileID =
            usesProfileScope
            ? profileID ?? ProcessInfo.processInfo.environment["DEN_PROFILE"]
            : nil
        let parsedProfileID: UUID?
        if let rawProfileID {
            guard let id = UUID(uuidString: rawProfileID) else {
                throw DenIPCClientError.invalidProfileID(rawProfileID)
            }
            parsedProfileID = id
        } else {
            parsedProfileID = nil
        }

        let callerError: String?
        switch operation {
        case .sheet(command: .navigate(_), target: .automatic),
            .sheetWithSnapshot(command: .navigate(_), target: .automatic, snapshot: _):
            callerError = "No Web Board found. Use 'den board web new <url>' to create a new board."
        case .sheet(_, .automatic),
            .sheetWithSnapshot(_, .automatic, _),
            .boardClose(.automatic):
            callerError = "No target Web Board found"
        case .terminal(_, .automatic):
            callerError = "No target Terminal Board found"
        default:
            callerError = nil
        }
        let parsedCallerBoardID: UUID?
        if let callerBoardID, let id = UUID(uuidString: callerBoardID) {
            parsedCallerBoardID = id
        } else if callerBoardID != nil, let callerError {
            throw DenIPCClientError.usage(callerError)
        } else {
            parsedCallerBoardID = nil
        }

        return DenIPCRequest(
            operation: operation,
            context: DenIPCCallerContext(profileID: parsedProfileID, callerBoardID: parsedCallerBoardID)
        )
    }

    static func boardTarget(_ rawID: String?) throws -> BoardTarget {
        guard let rawID else { return .automatic }
        return .explicit(try requiredBoardID(rawID))
    }

    static func requiredBoardID(_ rawID: String, invalidMessage: String? = nil) throws -> UUID {
        guard let id = UUID(uuidString: rawID) else {
            if let invalidMessage {
                throw DenIPCClientError.usage(invalidMessage)
            }
            throw DenIPCClientError.invalidBoardID(rawID)
        }
        return id
    }

    static func profileToOpen(_ explicitID: String?, options: CLIOptions) throws -> UUID {
        let rawID = explicitID ?? options.profileID ?? ProcessInfo.processInfo.environment["DEN_PROFILE"]
        guard let rawID else {
            throw DenIPCClientError.usage("Usage: den profile open <uuid>")
        }
        guard let id = UUID(uuidString: rawID) else {
            throw DenIPCClientError.invalidProfileID(rawID)
        }
        return id
    }
}
