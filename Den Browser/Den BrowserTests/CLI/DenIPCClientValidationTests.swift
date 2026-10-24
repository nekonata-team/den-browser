import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

struct DenIPCClientValidationTests {
    @Test(arguments: ["web", "terminal"], ["--left-of", "--right-of"])
    func boardCreationForwardsRelativeDestination(kind: String, option: String) async throws {
        // Arrange
        let id = UUID()
        let destination: DenBoardCreationDestination = option == "--left-of" ? .leftOf(id) : .rightOf(id)
        let expected: DenIPCOperation =
            kind == "web"
            ? .createWebBoard(payload: .init(url: "https://example.com/", focus: false), destination: destination)
            : .createTerminalBoard(payload: .init(path: nil, runCommand: nil, focus: false), destination: destination)
        let socketPath = temporarySocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data)
            return encodedResponse(request?.operation == expected ? .success() : .failure("Unexpected destination"))
        }
        defer { server.stop() }

        // Act
        let result = try await runCLI(
            ["board", kind, "new"] + (kind == "web" ? ["https://example.com/"] : []) + [option, id.uuidString],
            socketPath: socketPath)

        // Assert
        #expect(result.status == 0)
    }

    @Test(
        arguments: ["web", "terminal"],
        [
            ["--left-of", "invalid"], ["--right-of", "invalid"],
            ["--left-of", UUID().uuidString, "--right-of", UUID().uuidString],
            ["--desk", UUID().uuidString, "--left-of", UUID().uuidString],
            ["--desk", UUID().uuidString, "--right-of", UUID().uuidString],
        ])
    func boardCreationRejectsConflictingOrInvalidPlacement(kind: String, arguments: [String]) async throws {
        // Arrange
        let socketPath = temporarySocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { _ in encodedResponse(.success()) }
        defer { server.stop() }

        // Act
        let result = try await runCLI(
            ["board", kind, "new"] + (kind == "web" ? ["https://example.com/"] : []) + arguments,
            socketPath: socketPath)

        // Assert
        #expect(result.status != 0)
    }

    @Test(arguments: ["--left-of", "--right-of", "--desk"])
    func boardMoveForwardsExplicitDestination(option: String) async throws {
        // Arrange
        let boardID = UUID()
        let targetID = UUID()
        let destination: DenBoardMoveDestination
        switch option {
        case "--left-of": destination = .leftOf(targetID)
        case "--right-of": destination = .rightOf(targetID)
        default: destination = .desk(targetID)
        }
        let expected = DenIPCOperation.moveBoard(boardID: boardID, destination: destination)
        let socketPath = temporarySocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data)
            return encodedResponse(request?.operation == expected ? .success() : .failure("Unexpected move"))
        }
        defer { server.stop() }

        // Act
        let result = try await runCLI(
            ["board", "move", "--board", boardID.uuidString, option, targetID.uuidString], socketPath: socketPath)

        // Assert
        #expect(result.status == 0)
    }

    @Test(arguments: [
        [], ["--desk", UUID().uuidString], ["--board", UUID().uuidString],
        ["--board", "invalid", "--desk", UUID().uuidString],
        ["--board", UUID().uuidString, "--desk", "invalid"],
        ["--board", UUID().uuidString, "--left-of", "invalid"],
        ["--board", UUID().uuidString, "--right-of", "invalid"],
        ["--board", UUID().uuidString, "--left-of", UUID().uuidString, "--right-of", UUID().uuidString],
        ["--board", UUID().uuidString, "--desk", UUID().uuidString, "--left-of", UUID().uuidString],
        ["--board", UUID().uuidString, "--desk", UUID().uuidString, "--right-of", UUID().uuidString],
    ])
    func boardMoveRejectsMissingConflictingOrInvalidTargets(arguments: [String]) async throws {
        // Arrange
        let socketPath = temporarySocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { _ in encodedResponse(.success()) }
        defer { server.stop() }

        // Act
        let result = try await runCLI(["board", "move"] + arguments, socketPath: socketPath)

        // Assert
        #expect(result.status != 0)
    }

    @Test(arguments: [false, true], [false, true])
    func deskCommandsForwardExplicitOptions(remove: Bool, enabled: Bool) async throws {
        // Arrange
        let deskID = UUID()
        let socketPath = temporarySocketPath()
        let expected: DenIPCOperation =
            remove
            ? .removeDesk(deskID: deskID, force: enabled) : .createDesk(label: "Work", focus: enabled)
        let payload: DenIPCResultPayload =
            remove
            ? .removedDesk(id: deskID.uuidString) : .createdDesk(id: deskID.uuidString)
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data), request.operation == expected
            else { return encodedResponse(.failure("Unexpected Desk operation")) }
            return encodedResponse(.success(payload))
        }
        defer { server.stop() }
        let arguments =
            remove
            ? ["desk", "remove", "--desk", deskID.uuidString] + (enabled ? ["--force"] : [])
            : ["desk", "new", "Work"] + (enabled ? ["--focus"] : [])

        // Act
        let result = try await runCLI(arguments, socketPath: socketPath)
        let object = try jsonResult(result.output)

        // Assert
        #expect(result.status == 0)
        #expect(object[remove ? "removed_desk_id" : "desk_id"] as? String == deskID.uuidString)
    }

    @Test func deskRemovalRequiresExplicitTarget() async throws {
        // Arrange
        let socketPath = temporarySocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { _ in encodedResponse(.success()) }
        defer { server.stop() }

        // Act
        let result = try await runCLI(["desk", "remove"], socketPath: socketPath)

        // Assert
        #expect(result.status != 0)
    }

    @Test(arguments: ["web", "terminal", "list"], [false, true])
    func boardCommandsForwardDeskTarget(command: String, explicitDesk: Bool) async throws {
        // Arrange
        let deskID = UUID()
        let destination: DenBoardCreationDestination = explicitDesk ? .explicit(deskID) : .automatic
        let expected: DenIPCOperation
        let arguments: [String]
        switch command {
        case "web":
            expected = .createWebBoard(
                payload: DenBoardWebNewPayload(url: "https://example.com/", focus: true),
                destination: destination)
            arguments = ["board", "web", "new", "https://example.com/", "--focus"]
        case "terminal":
            expected = .createTerminalBoard(
                payload: DenBoardTerminalNewPayload(path: nil, runCommand: nil, focus: true),
                destination: destination)
            arguments = ["board", "terminal", "new", "--focus"]
        default:
            expected = .boardList(target: explicitDesk ? .explicit(deskID) : .automatic)
            arguments = ["board", "list", "-l"]
        }
        let socketPath = temporarySocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data) else {
                return encodedResponse(.failure("Could not decode request"))
            }
            return encodedResponse(request.operation == expected ? .success() : .failure("Unexpected destination"))
        }
        defer { server.stop() }

        // Act
        let result = try await runCLI(
            arguments + (explicitDesk ? ["--desk", deskID.uuidString] : []),
            socketPath: socketPath)

        // Assert
        #expect(result.status == 0)
    }

    @Test(arguments: [false, true])
    func dialogSaveForwardsDestinationAndExplicitOverwrite(overwrite: Bool) async throws {
        // Arrange
        let id = UUID()
        let socketPath = temporarySocketPath()
        let destination = URL(fileURLWithPath: "report.pdf").standardizedFileURL.path
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data) else {
                return encodedResponse(.failure("Could not decode request"))
            }
            let expected = DenIPCCommand.Sheet.dialog(.save(id: id, path: destination, overwrite: overwrite))
            guard request.operation == .sheet(command: expected, target: .automatic) else {
                return encodedResponse(.failure("Unexpected save destination or overwrite permission"))
            }
            return encodedResponse(.success())
        }
        defer { server.stop() }

        // Act
        let result = try await runCLI(
            ["board", "web", "dialog", "save", id.uuidString, "--path", "report.pdf"]
                + (overwrite ? ["--overwrite"] : []),
            socketPath: socketPath)

        // Assert
        #expect(result.status == 0)
    }

    @Test(arguments: [
        MalformedCLIInvocation(
            arguments: ["desk", "remove", "--desk", "bad-id"],
            expectedError: "Invalid desk ID: bad-id"
        ),
        MalformedCLIInvocation(
            arguments: ["board", "list", "--desk", "bad-id"],
            expectedError: "Invalid desk ID: bad-id"
        ),
        MalformedCLIInvocation(
            arguments: ["board", "web", "new", "https://example.com/", "--desk", "bad-id"],
            expectedError: "Invalid desk ID: bad-id"
        ),
        MalformedCLIInvocation(
            arguments: ["board", "terminal", "new", "--desk", "bad-id"],
            expectedError: "Invalid desk ID: bad-id"
        ),
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
    func malformedExplicitIDsReturnStructuredFailures(_ invocation: MalformedCLIInvocation) async throws {
        // Arrange
        let socketPath = temporarySocketPath()

        // Act
        let result = try await runCLI(invocation.arguments, socketPath: socketPath)
        let operationResult = try jsonResult(result.output)

        // Assert
        #expect(result.status != 0)
        #expect(operationResult["ok"] as? Bool == false)
        #expect(operationResult["error"] as? String == invocation.expectedError)
    }

    @Test func profileOpenUsesCLIProfileFallback() async throws {
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
                .success(.message(receivedFallback ? "profile fallback used" : "wrong request"))
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLI(
            ["profile", "open", "--profile", expectedProfileID.uuidString],
            socketPath: socketPath
        )
        let operationResult = try jsonResult(result.output)

        // Assert
        #expect(result.status == 0)
        #expect(operationResult["message"] as? String == "profile fallback used")
    }

    @Test(arguments: [["profile", "list"], ["health"]])
    func profileListAndHealthIgnoreUnusedInvalidScope(arguments: [String]) async throws {
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
                .success(.message(ignoredInvalidScope ? "unused scope ignored" : "wrong request"))
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLI(arguments + ["--profile", "bad-profile"], socketPath: socketPath)
        let operationResult = try jsonResult(result.output)

        // Assert
        #expect(result.status == 0)
        #expect(operationResult["message"] as? String == "unused scope ignored")
    }

    @Test func malformedAmbientCallerIsReportedForAutomaticTarget() async throws {
        // Arrange
        let socketPath = temporarySocketPath()

        // Act
        let result = try await runCLI(
            ["board", "web", "url"],
            socketPath: socketPath,
            environmentOverrides: ["DEN_BOARD_ID": "bad-caller"]
        )
        let operationResult = try jsonResult(result.output)

        // Assert
        #expect(result.status != 0)
        #expect(operationResult["error"] as? String == "No target Web Board found")
    }

    @Test func malformedAmbientCallerIsIgnoredForExplicitTarget() async throws {
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
                .success(.message(ignoredMalformedCaller ? "caller ignored" : "wrong request"))
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLI(
            ["board", "web", "url", "--board", explicitBoardID.uuidString],
            socketPath: socketPath,
            environmentOverrides: ["DEN_BOARD_ID": "bad-caller"]
        )
        let operationResult = try jsonResult(result.output)

        // Assert
        #expect(result.status == 0)
        #expect(operationResult["message"] as? String == "caller ignored")
    }

    @Test func resolvedTargetContextDoesNotLeakIntoCLIJSON() async throws {
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
                .success(.url("https://example.com/")),
                target: .board(profileID: profileID, boardID: boardID)
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLI(
            ["board", "web", "url", "--board", boardID.uuidString],
            socketPath: socketPath
        )
        let output = try jsonResult(result.output)

        // Assert
        #expect(result.status == 0)
        #expect(output["url"] as? String == "https://example.com/")
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

private func jsonResult(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
) async throws -> CLIResult {
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

    // Let the socket server's Tasks run while the CLI waits for its response.
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        process.terminationHandler = { _ in continuation.resume() }
        do {
            try process.run()
        } catch {
            continuation.resume(throwing: error)
        }
    }
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    _ = error.fileHandleForReading.readDataToEndOfFile()

    return CLIResult(status: process.terminationStatus, output: outputData)
}

private func temporarySocketPath() -> String {
    "/tmp/den-cli-validation-\(UUID().uuidString).sock"
}
