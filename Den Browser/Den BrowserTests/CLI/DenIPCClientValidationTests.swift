import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

struct DenIPCClientValidationTests {
    @Test(arguments: [
        MalformedCLIInvocation(
            arguments: ["board", "web", "url", "--board", "bad-id"],
            expectedError: "Invalid board ID: bad-id"
        ),
        MalformedCLIInvocation(
            arguments: ["board", "terminal", "text", "--board", "bad-id"],
            expectedError: "Invalid board ID: bad-id"
        ),
        MalformedCLIInvocation(
            arguments: ["board", "close", "--board", "bad-id"],
            expectedError: "Invalid board ID: bad-id"
        ),
        MalformedCLIInvocation(
            arguments: ["board", "inspection", "read", "--board", "bad-id"],
            expectedError: "Usage: den board inspection read --board <inspection-board-id>"
        ),
        MalformedCLIInvocation(
            arguments: ["board", "inspection", "new", "--target", "bad-id"],
            expectedError: "Usage: den board inspection new --target <web-board-id>"
        ),
        MalformedCLIInvocation(
            arguments: ["board", "web", "url", "--profile", "bad-id"],
            expectedError: "Invalid profile ID: bad-id"
        ),
        MalformedCLIInvocation(
            arguments: ["profile", "open", "bad-id"],
            expectedError: "Invalid profile ID: bad-id"
        ),
    ])
    func malformedExplicitIDsReturnStructuredFailures(_ invocation: MalformedCLIInvocation) throws {
        // Arrange
        let socketPath = temporarySocketPath()

        // Act
        let result = try runCLI(invocation.arguments, socketPath: socketPath)
        let operationResult = try JSONDecoder().decode(DenIPCOperationResult.self, from: result.output)

        // Assert
        #expect(result.status != 0)
        #expect(operationResult.isOk == false)
        #expect(operationResult.error == invocation.expectedError)
    }

    @Test func profileOpenUsesCLIProfileFallback() throws {
        // Arrange
        let expectedProfileID = UUID()
        let socketPath = temporarySocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data) else {
                return encodedResponse(.failure("Could not decode request"))
            }
            let receivedFallback =
                request.operation == .openProfile(profileID: expectedProfileID)
                && request.context.profileID == nil
            return encodedResponse(
                .success(message: receivedFallback ? "profile fallback used" : "wrong request")
            )
        }
        defer { server.stop() }

        // Act
        let result = try runCLI(
            ["profile", "open", "--profile", expectedProfileID.uuidString],
            socketPath: socketPath
        )
        let operationResult = try JSONDecoder().decode(DenIPCOperationResult.self, from: result.output)

        // Assert
        #expect(result.status == 0)
        #expect(operationResult.message == "profile fallback used")
    }

    @Test(arguments: [["profile", "list"], ["health"]])
    func profileListAndHealthIgnoreUnusedInvalidScope(arguments: [String]) throws {
        // Arrange
        let socketPath = temporarySocketPath()
        let expectedOperation: DenIPCOperation = arguments == ["health"] ? .health : .profileList
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data) else {
                return encodedResponse(.failure("Could not decode request"))
            }
            let ignoredInvalidScope =
                request.operation == expectedOperation
                && request.context.profileID == nil
                && request.context.callerBoardID == nil
            return encodedResponse(
                .success(message: ignoredInvalidScope ? "unused scope ignored" : "wrong request")
            )
        }
        defer { server.stop() }

        // Act
        let result = try runCLI(arguments + ["--profile", "bad-profile"], socketPath: socketPath)
        let operationResult = try JSONDecoder().decode(DenIPCOperationResult.self, from: result.output)

        // Assert
        #expect(result.status == 0)
        #expect(operationResult.message == "unused scope ignored")
    }

    @Test func malformedAmbientCallerIsReportedForAutomaticTarget() throws {
        // Arrange
        let socketPath = temporarySocketPath()

        // Act
        let result = try runCLI(
            ["board", "web", "url"],
            socketPath: socketPath,
            environmentOverrides: ["DEN_BOARD_ID": "bad-caller"]
        )
        let operationResult = try JSONDecoder().decode(DenIPCOperationResult.self, from: result.output)

        // Assert
        #expect(result.status != 0)
        #expect(operationResult.error == "No target Web Board found")
    }

    @Test func malformedAmbientCallerIsIgnoredForExplicitTarget() throws {
        // Arrange
        let explicitBoardID = UUID()
        let socketPath = temporarySocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data) else {
                return encodedResponse(.failure("Could not decode request"))
            }
            let ignoredMalformedCaller =
                request.operation
                == .sheet(command: .url, target: .explicit(explicitBoardID))
                && request.context.callerBoardID == nil
            return encodedResponse(
                .success(message: ignoredMalformedCaller ? "caller ignored" : "wrong request")
            )
        }
        defer { server.stop() }

        // Act
        let result = try runCLI(
            ["board", "web", "url", "--board", explicitBoardID.uuidString],
            socketPath: socketPath,
            environmentOverrides: ["DEN_BOARD_ID": "bad-caller"]
        )
        let operationResult = try JSONDecoder().decode(DenIPCOperationResult.self, from: result.output)

        // Assert
        #expect(result.status == 0)
        #expect(operationResult.message == "caller ignored")
    }

    @Test func resolvedTargetContextDoesNotLeakIntoCLIJSON() throws {
        // Arrange
        let profileID = UUID()
        let boardID = UUID()
        let socketPath = temporarySocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data),
                request.operation == .sheet(command: .url, target: .explicit(boardID))
            else {
                return encodedResponse(.failure("Unexpected request"))
            }
            return encodedResponse(
                .success(url: "https://example.com/"),
                target: .board(profileID: profileID, boardID: boardID)
            )
        }
        defer { server.stop() }

        // Act
        let result = try runCLI(
            ["board", "web", "url", "--board", boardID.uuidString],
            socketPath: socketPath
        )
        let operationResult = try JSONDecoder().decode(DenIPCOperationResult.self, from: result.output)
        let output = try #require(JSONSerialization.jsonObject(with: result.output) as? [String: Any])

        // Assert
        #expect(result.status == 0)
        #expect(operationResult.url == "https://example.com/")
        #expect(output["profile_id"] == nil)
        #expect(output["target"] == nil)
    }
}

struct MalformedCLIInvocation: Sendable {
    let arguments: [String]
    let expectedError: String
}

private struct CLIResult {
    let status: Int32
    let output: Data
}

private func encodedResponse(
    _ result: DenIPCOperationResult,
    target: DenIPCTargetContext = .none
) -> Data {
    (try? JSONEncoder().encode(DenIPCResponse(result: result, target: target))) ?? Data()
}

private func runCLI(
    _ arguments: [String],
    socketPath: String,
    environmentOverrides: [String: String] = [:]
) throws -> CLIResult {
    let process = Process()
    process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
    process.arguments = arguments + ["--json", "--socket", socketPath]
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "DEN_SOCKET")
    environment.removeValue(forKey: "DEN_BOARD_ID")
    environment.removeValue(forKey: "DEN_PROFILE")
    environment.merge(environmentOverrides) { _, override in override }
    process.environment = environment

    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error

    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    _ = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return CLIResult(status: process.terminationStatus, output: outputData)
}

private func temporarySocketPath() -> String {
    "/tmp/den-cli-validation-\(UUID().uuidString).sock"
}
