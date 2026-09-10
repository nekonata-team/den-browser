import ArgumentParser
import Darwin
import Foundation

struct CLIOptions: ParsableArguments {
    @Flag(name: .customLong("json"), help: "Output response as JSON")
    var isJSON = false

    @Option(name: .customLong("socket"), help: "Custom socket path (defaults to ~/.den/den.sock)")
    var socketPath: String?
}

struct BoardTargetOptions: ParsableArguments {
    @OptionGroup var common: CLIOptions

    @Option(name: .customLong("board"), help: "Target specific Board ID (defaults to the ambient Board)")
    var boardID: String?
}

enum DenIPCClient {
    static func execute(command: DenIPCCommand, args: [String], options: CLIOptions) throws {
        try execute(
            command: command,
            args: args,
            isJSON: options.isJSON,
            boardID: nil,
            socketPath: options.socketPath)
    }

    static func execute(command: DenIPCCommand, args: [String], options: BoardTargetOptions) throws {
        try execute(
            command: command,
            args: args,
            isJSON: options.common.isJSON,
            boardID: options.boardID,
            socketPath: options.common.socketPath)
    }

    private static func execute(
        command: DenIPCCommand,
        args: [String],
        isJSON: Bool,
        boardID: String?,
        socketPath: String?
    ) throws {
        let env = ProcessInfo.processInfo.environment
        let callerBoardID = env["DEN_BOARD_ID"]

        let socketPath: String = {
            if let custom = socketPath { return custom }
            if let envSocket = env["DEN_SOCKET"], !envSocket.isEmpty { return envSocket }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return "\(home)/.den/den.sock"
        }()

        let request = DenIPCRequest(
            command: command,
            args: args,
            boardID: boardID,
            deskID: nil,
            callerBoardID: callerBoardID)

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

        let isJSONOutput = isJSON || isatty(STDOUT_FILENO) == 0

        if isJSONOutput {
            if let jsonString = String(data: responseData, encoding: .utf8) {
                print(jsonString.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else {
            if response.isOk {
                if command == .health {
                    print("healthy")
                } else if let boardId = response.boardId {
                    print(boardId)
                } else if let boards = response.boards {
                    for currentBoard in boards {
                        let urlSuffix = currentBoard.url.map { " (\($0))" } ?? ""
                        print("[\(currentBoard.type)] \(currentBoard.id) - \(currentBoard.label)\(urlSuffix)")
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
                } else if let url = response.url {
                    print(url)
                } else if let text = response.text {
                    print(text)
                } else if let value = response.value {
                    print(value)
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
