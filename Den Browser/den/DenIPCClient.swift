import ArgumentParser
import Darwin
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

private struct CLIOutputOptions {
    let isJSON: Bool
    let showBoardIDs: Bool
}

enum DenIPCClient {
    static func execute(
        command: DenIPCCommand,
        args: [String],
        options: CLIOptions,
        showBoardIDs: Bool = false
    ) throws {
        try execute(
            command: command,
            args: args,
            options: options,
            output: CLIOutputOptions(isJSON: options.isJSON, showBoardIDs: showBoardIDs),
            boardID: nil
        )
    }

    static func execute(command: DenIPCCommand, args: [String], options: BoardTargetOptions) throws {
        try execute(
            command: command,
            args: args,
            options: options.common,
            output: CLIOutputOptions(isJSON: options.common.isJSON, showBoardIDs: false),
            boardID: options.boardID
        )
    }

    private static func execute(
        command: DenIPCCommand,
        args: [String],
        options: CLIOptions,
        output: CLIOutputOptions,
        boardID: String?
    ) throws {
        let env = ProcessInfo.processInfo.environment
        let callerBoardID = env["DEN_BOARD_ID"]
        let effectiveProfileID = options.profileID ?? env["DEN_PROFILE"]

        let socketPath: String = {
            if let custom = options.socketPath { return custom }
            if let envSocket = env["DEN_SOCKET"], !envSocket.isEmpty { return envSocket }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return "\(home)/.den/den.sock"
        }()

        let request = DenIPCRequest(
            command: command,
            args: args,
            boardID: boardID,
            deskID: nil,
            callerBoardID: callerBoardID,
            profileID: effectiveProfileID)

        guard let requestData = try? JSONEncoder().encode(request) else {
            fputs("Error: Failed to encode request\n", stderr)
            throw ExitCode.failure
        }

        let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            fputs("Error: Failed to create socket\n", stderr)
            throw ExitCode.failure
        }
        defer { close(socketDescriptor) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            fputs("Error: Socket path too long: \(socketPath)\n", stderr)
            throw ExitCode.failure
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            pathBytes.withUnsafeBytes { source in
                buffer.copyMemory(from: source)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                connect(socketDescriptor, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            let errMsg = String(cString: strerror(errno))
            fputs("Error: Could not connect to Den Browser at \(socketPath): \(errMsg)\n", stderr)
            throw ExitCode.failure
        }

        var packet = requestData
        packet.append(UInt8(ascii: "\n"))

        packet.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let writtenBytes = write(socketDescriptor, base.advanced(by: written), rawBuffer.count - written)
                guard writtenBytes > 0 else { break }
                written += writtenBytes
            }
        }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let readBytes = read(socketDescriptor, &buffer, buffer.count)
            guard readBytes > 0 else { break }
            responseData.append(buffer, count: readBytes)
            if responseData.contains(UInt8(ascii: "\n")) { break }
        }

        guard let response = try? JSONDecoder().decode(DenIPCResponse.self, from: responseData) else {
            let rawStr = String(data: responseData, encoding: .utf8) ?? ""
            fputs("Error: Invalid response from Den Browser: \(rawStr)\n", stderr)
            throw ExitCode.failure
        }

        let isJSONOutput = output.isJSON || isatty(STDOUT_FILENO) == 0

        if isJSONOutput {
            if let jsonString = String(data: responseData, encoding: .utf8) {
                print(jsonString.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else {
            if response.isOk {
                if command == .health {
                    print("healthy")
                } else if let board = response.board {
                    let type = "[\(board.type)]"
                    let boardIDPrefix = output.showBoardIDs ? "\(board.id) - " : ""
                    let secondary = board.url ?? board.sessionName
                    let secondarySuffix = secondary.map { " (\($0))" } ?? ""
                    print("* \(type) \(boardIDPrefix)\(board.label)\(secondarySuffix)")
                } else if let boardId = response.boardId {
                    print(boardId)
                } else if let boards = response.boards {

                    let typeColumnWidth =
                        boards
                        .map { "[\($0.type)]".count }
                        .max() ?? 0

                    for currentBoard in boards {
                        let mark = currentBoard.isFocused ? "*" : " "
                        let type = "[\(currentBoard.type)]"
                            .padding(toLength: typeColumnWidth, withPad: " ", startingAt: 0)
                        let boardIDPrefix = output.showBoardIDs ? "\(currentBoard.id) - " : ""
                        let secondary = currentBoard.url ?? currentBoard.sessionName
                        let secondarySuffix = secondary.map { " (\($0))" } ?? ""
                        print(
                            "\(mark) \(type) \(boardIDPrefix)"
                                + "\(currentBoard.label)\(secondarySuffix)"
                        )
                    }
                } else if let profiles = response.profiles {
                    let nameWidth = profiles.map(\.name.count).max() ?? 4
                    let paddedNameHeader = "NAME".padding(toLength: max(nameWidth, 4), withPad: " ", startingAt: 0)
                    print("  \(paddedNameHeader)  ID                                    ACTIVE  WINDOW")
                    for profile in profiles {
                        let mark = profile.isActive ? "*" : " "
                        let paddedName = profile.name.padding(toLength: max(nameWidth, 4), withPad: " ", startingAt: 0)
                        let activeStr = (profile.isActive ? "yes" : "no").padding(
                            toLength: 6, withPad: " ", startingAt: 0)
                        let windowStr = profile.hasWindow ? "yes" : "no"
                        print("\(mark) \(paddedName)  \(profile.id)  \(activeStr)  \(windowStr)")
                    }
                } else if let desks = response.desks {
                    for currentDesk in desks {
                        let mark = currentDesk.isActive ? "*" : " "
                        print("\(mark) \(currentDesk.id) - \(currentDesk.label) (\(currentDesk.boardCount) boards)")
                    }
                } else if let drawerItems = response.drawerItems {
                    for item in drawerItems {
                        let titleSuffix = item.title.map { " - \($0)" } ?? ""
                        print("\(item.id)\(titleSuffix) (\(item.url))")
                    }
                } else if let drawerItemId = response.drawerItemId {
                    print(drawerItemId)
                } else if let snapshot = response.snapshot {
                    print(snapshot)
                } else if let elements = response.elements {
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
                } else if let url = response.url {
                    print(url)
                } else if let text = response.text {
                    print(text)
                } else if let value = response.value {
                    print(value)
                } else if let checked = response.checked {
                    print(checked ? "true" : "false")
                } else if let attribute = response.attribute {
                    print(attribute)
                } else if let count = response.count {
                    print(count)
                } else if let visible = response.visible {
                    print(visible ? "true" : "false")
                } else if let enabled = response.enabled {
                    print(enabled ? "true" : "false")
                } else if let screenshotPath = response.screenshotPath {
                    print(screenshotPath)
                } else if let message = response.message {
                    print(message)
                }
            } else {
                fputs("Error: \(response.error ?? "Unknown error")\n", stderr)
            }
        }

        if !response.isOk {
            throw ExitCode.failure
        }
    }
}
