import Darwin
import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

struct DenMCPResponseTests {
    @Test func createInspectionBoardKeepsCreatedIDAndAddsResolvedTargetMetadata() throws {
        // Arrange
        let profileID = UUID()
        let targetBoardID = UUID()
        let createdBoardID = UUID()
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("den-mcp-\(UUID().uuidString).sock").path
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data),
                case .createInspectionBoard(let receivedTargetBoardID, let payload) = request.operation,
                receivedTargetBoardID == targetBoardID,
                payload == DenBoardInspectionNewPayload(focus: false)
            else {
                return encodedReply(.failure("Unexpected request"))
            }
            return encodedReply(
                .success(.createdBoard(id: createdBoardID.uuidString, message: nil, url: nil)),
                target: .board(profileID: profileID, boardID: targetBoardID)
            )
        }
        defer { server.stop() }

        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["mcp", "--socket", socketPath]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "DEN_SOCKET")
        environment.removeValue(forKey: "DEN_BOARD_ID")
        environment.removeValue(forKey: "DEN_PROFILE")
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        // Act
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        try writeMCPMessage(
            [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": [
                    "protocolVersion": "2025-06-18",
                    "capabilities": [String: String](),
                    "clientInfo": ["name": "Den BrowserTests", "version": "1"],
                ],
            ],
            to: input.fileHandleForWriting
        )
        let initialization = try readMCPMessage(from: output.fileHandleForReading)
        #expect(initialization["id"] as? Int == 1)
        #expect(initialization["result"] != nil)

        try writeMCPMessage(
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            to: input.fileHandleForWriting
        )
        try writeMCPMessage(
            [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": [
                    "name": "create_inspection_board",
                    "arguments": ["target_board_id": targetBoardID.uuidString],
                ],
            ],
            to: input.fileHandleForWriting
        )
        let toolResponse = try readMCPMessage(from: output.fileHandleForReading)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        // Assert
        let result = try #require(toolResponse["result"] as? [String: Any])
        let structuredContent = try #require(result["structuredContent"] as? [String: Any])
        #expect(process.terminationStatus == 0)
        #expect(result["isError"] as? Bool == false)
        #expect(structuredContent["profile_id"] as? String == profileID.uuidString)
        #expect(structuredContent["board_id"] as? String == createdBoardID.uuidString)
    }
}

private func encodedReply(
    _ result: DenIPCOperationResult,
    target: DenIPCTargetContext = .none
) -> Data {
    (try? JSONEncoder().encode(DenIPCResponse(result: result, target: target))) ?? Data()
}

private func writeMCPMessage(_ message: [String: Any], to input: FileHandle) throws {
    var data = try JSONSerialization.data(withJSONObject: message)
    data.append(UInt8(ascii: "\n"))
    input.write(data)
}

private func readMCPMessage(from output: FileHandle) throws -> [String: Any] {
    var message = Data()
    while true {
        var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 5_000) > 0 else {
            throw MCPProcessTestError.timedOut
        }
        let bytes = output.availableData
        guard !bytes.isEmpty else { throw MCPProcessTestError.closed }
        if let newline = bytes.firstIndex(of: UInt8(ascii: "\n")) {
            message.append(contentsOf: bytes[..<newline])
            break
        }
        message.append(bytes)
    }
    return try #require(JSONSerialization.jsonObject(with: message) as? [String: Any])
}

private enum MCPProcessTestError: Error {
    case timedOut
    case closed
}
