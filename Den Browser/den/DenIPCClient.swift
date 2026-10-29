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
        case .socketPathTooLong(let path): "Socket path too long: \(path). Use a shorter --socket path."
        case .connect(let path, let message):
            "Could not connect to Den Browser at \(path): \(message). Open Den Browser and retry. For a custom socket, check --socket and DEN_SOCKET."
        case .send(let message): "Could not send request to Den Browser: \(message)"
        case .invalidResponse(let response):
            "Invalid response from Den Browser: \(response). Use the CLI bundled with the running Den Browser app."
        case .invalidBoardID(let id):
            "Invalid Board ID: \(id). Expected a UUID; run 'den board list -l' to find Board IDs."
        case .invalidProfileID(let id):
            "Invalid Profile ID: \(id). Expected a UUID; run 'den profile list' to find Profile IDs. Check the supplied ID or DEN_PROFILE."
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
            let message = (error as? ValidationError)?.message ?? error.localizedDescription
            let result = DenIPCOperationResult.failure(message)
            let responseData = (try? JSONEncoder().encode(result.publicJSON)) ?? Data()
            try writeResult(
                result, data: responseData, output: output, isHealth: false, failureExitCode: exitCode(for: error))
            return
        }

        let response: DenIPCResponse
        do {
            response = try sendRequest(request: request, socketPath: options.socketPath)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            throw exitCode(for: error)
        }

        let result = response.result
        let responseData = try JSONEncoder().encode(result.publicJSON)
        try writeResult(result, data: responseData, output: output, isHealth: operation == .health)
    }

    private static func exitCode(for error: Error) -> ExitCode {
        switch error {
        case is ValidationError, is DenIPCInputError,
            DenIPCClientError.invalidBoardID(_), DenIPCClientError.invalidProfileID(_), DenIPCClientError.usage(_),
            DenIPCClientError.socketPathTooLong(_):
            .validationFailure
        default:
            .failure
        }
    }

    private static func writeResult(
        _ result: DenIPCOperationResult,
        data responseData: Data,
        output: CLIOutputOptions,
        isHealth: Bool,
        failureExitCode: ExitCode = .failure
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
            throw failureExitCode
        }
    }

    private static func writeTextResult(_ payload: DenIPCResultPayload, output: CLIOutputOptions) {
        switch payload {
        case .empty, .interaction, .boardExistence:
            break
        case .message(let message), .closedBoard(_, let message):
            print(message)
        case .createdBoard(let id, _, _), .sheet(let id, _), .createdDesk(let id):
            print(id)
        case .removedDesk(let id):
            print("Removed Desk \(id)")
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
                let location = item.url ?? item.sessionName ?? item.workingDirectory ?? item.type
                print("\(item.id)\(titleSuffix) (\(location))")
            }
        case .drawerItem(let id, _):
            print(id)
        case .profiles(let profiles):
            writeProfiles(profiles)
        case .denOverview(let overview):
            writeBoards(overview.boards, showBoardIDs: output.showBoardIDs)
        case .navigation(_, let url), .url(let url):
            print(url)
        case .status(let status):
            print(status.map(String.init) ?? "null")
        case .dialogs(let dialogs):
            for dialog in dialogs {
                print("\(dialog.id.uuidString) save \(dialog.suggestedFilename)")
            }
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
        case .reading(let title, let url, let markdown):
            print("Title: \(title)\nURL: \(url)\n\n\(markdown)")
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
        let rawProfileID: String?
        switch operation {
        case .health, .profileList, .openProfile:
            rawProfileID = nil
        case .boardExists:
            rawProfileID = profileID
        default:
            rawProfileID = profileID ?? ProcessInfo.processInfo.environment["DEN_PROFILE"]
        }

        let parsedProfileID: UUID?
        if let rawProfileID {
            guard let id = UUID(uuidString: rawProfileID) else {
                throw DenIPCClientError.invalidProfileID(rawProfileID)
            }
            parsedProfileID = id
        } else {
            parsedProfileID = nil
        }

        if case .boardExists = operation {
            return DenIPCRequest(operation: operation, context: DenIPCCallerContext(profileID: parsedProfileID))
        }

        let requiresValidCallerBoardID: Bool
        switch operation {
        case .sheet(_, .automatic), .sheetWithSnapshot(_, .automatic, _),
            .boardClose(.automatic), .terminal(_, .automatic):
            requiresValidCallerBoardID = true
        default:
            requiresValidCallerBoardID = false
        }
        let parsedCallerBoardID: UUID?
        if let callerBoardID, let id = UUID(uuidString: callerBoardID) {
            parsedCallerBoardID = id
        } else if let callerBoardID, requiresValidCallerBoardID {
            throw DenIPCClientError.usage(
                "Invalid DEN_BOARD_ID: \(callerBoardID). Expected a UUID; pass --board <uuid> explicitly or unset DEN_BOARD_ID."
            )
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

    static func deskTarget(_ rawID: String?) throws -> DeskTarget {
        guard let rawID else { return .automatic }
        return .explicit(try requiredDeskID(rawID))
    }

    static func requiredDeskID(_ rawID: String) throws -> UUID {
        guard let id = UUID(uuidString: rawID) else {
            throw DenIPCClientError.usage(
                "Invalid Desk ID: \(rawID). Expected a UUID; run 'den desk list' to find Desk IDs.")
        }
        return id
    }

    static func requiredBoardID(_ rawID: String, invalidMessage: String? = nil) throws -> UUID {
        guard let id = UUID(uuidString: rawID) else {
            let error = DenIPCClientError.invalidBoardID(rawID)
            if let invalidMessage {
                throw DenIPCClientError.usage("\(error.localizedDescription) \(invalidMessage)")
            }
            throw error
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
