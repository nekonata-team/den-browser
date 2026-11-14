import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

struct CLITargetRoutingTests {
    @Test(arguments: [false, true], ["invalid", UUID().uuidString])
    func boardExistsUsesOnlyExplicitProfileScope(explicit: Bool, ambientProfile: String) async throws {
        // Arrange
        let boardID = UUID()
        let profileID = UUID()
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data)
            let expected = DenIPCRequest(
                operation: .boardExists(boardID: boardID),
                context: .init(profileID: explicit ? profileID : nil)
            )
            return encodeIPCResponse(request == expected ? .success() : .failure("Unexpected scope"))
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["board", "exists", "--board", boardID.uuidString]
                + (explicit ? ["--profile", profileID.uuidString] : []),
            socketPath: socketPath,
            environmentOverrides: ["DEN_PROFILE": ambientProfile, "DEN_BOARD_ID": UUID().uuidString]
        )

        // Assert
        #expect(result.status == 0)
    }

    @Test(arguments: ["found", "missing", "error"])
    func boardExistsReturnsStatusAndLocation(state: String) async throws {
        // Arrange
        let boardID = UUID().uuidString
        let location = DenBoardLocation(deskID: UUID().uuidString, profileID: UUID().uuidString)
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { _ in
            encodeIPCResponse(
                state == "error"
                    ? .failure("Lookup failed")
                    : .success(.boardExistence(boardID: boardID, location: state == "found" ? location : nil))
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(["board", "exists", "--board", boardID], socketPath: socketPath)
        let object = try parseCLIJSON(result.output)

        // Assert
        #expect(result.status == (state == "error" ? 1 : 0))
        #expect(object["ok"] as? Bool == (state != "error"))
        if state != "error" {
            #expect(object["board_id"] as? String == boardID)
            #expect(object["exists"] as? Bool == (state == "found"))
        }
        #expect(object["desk_id"] as? String == (state == "found" ? location.deskID : nil))
        #expect(object["profile_id"] as? String == (state == "found" ? location.profileID : nil))
    }

    @Test(arguments: [
        ["--board", "invalid"],
        ["--board", UUID().uuidString, "--profile", "invalid"],
        [],
    ])
    func boardExistsInvalidArgumentsUseValidationFailure(arguments: [String]) async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()

        // Act
        let result = try await runCLITest(["board", "exists"] + arguments, socketPath: socketPath)

        // Assert
        #expect(result.status == 64)
    }

    @Test(arguments: [
        [], ["--end-of", UUID().uuidString], ["--board", UUID().uuidString],
        ["--board", "invalid", "--end-of", UUID().uuidString],
        ["--board", UUID().uuidString, "--end-of", "invalid"],
        ["--board", UUID().uuidString, "--left-of", "invalid"],
        ["--board", UUID().uuidString, "--right-of", "invalid"],
        ["--board", UUID().uuidString, "--left-of", UUID().uuidString, "--right-of", UUID().uuidString],
        ["--board", UUID().uuidString, "--end-of", UUID().uuidString, "--left-of", UUID().uuidString],
        ["--board", UUID().uuidString, "--end-of", UUID().uuidString, "--right-of", UUID().uuidString],
    ])
    func boardMoveRejectsMissingConflictingOrInvalidTargets(arguments: [String]) async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { _ in encodeIPCResponse(.success()) }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(["board", "move"] + arguments, socketPath: socketPath)

        // Assert
        #expect(result.status == 64)
    }

    @Test func deskRemovalRequiresExplicitTarget() async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { _ in encodeIPCResponse(.success()) }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(["desk", "remove"], socketPath: socketPath)

        // Assert
        #expect(result.status == 64)
    }

    @Test(arguments: ["web", "terminal", "list"], [false, true])
    func boardCommandsForwardDeskTarget(command: String, explicitDesk: Bool) async throws {
        // Arrange
        let deskID = UUID()
        let destination: DenBoardCreationDestination = explicitDesk ? .endOfDesk(deskID) : .automatic
        let expected: DenIPCOperation
        let arguments: [String]
        switch command {
        case "web":
            expected = .createWebBoard(
                payload: DenBoardWebNewPayload(url: "https://example.com/", focus: true),
                destination: destination
            )
            arguments = ["board", "web", "new", "https://example.com/", "--focus"]
        case "terminal":
            expected = .createTerminalBoard(
                payload: DenBoardTerminalNewPayload(path: nil, runCommand: nil, focus: true),
                destination: destination
            )
            arguments = ["board", "terminal", "new", "--focus"]
        default:
            expected = .boardList(target: explicitDesk ? .explicit(deskID) : .automatic)
            arguments = ["board", "list", "-l"]
        }
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data) else {
                return encodeIPCResponse(.failure("Could not decode request"))
            }
            return encodeIPCResponse(request.operation == expected ? .success() : .failure("Unexpected destination"))
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            arguments + (explicitDesk ? [command == "list" ? "--desk" : "--end-of", deskID.uuidString] : []),
            socketPath: socketPath
        )

        // Assert
        #expect(result.status == 0)
    }

    @Test func profileOpenUsesCLIProfileFallback() async throws {
        // Arrange
        let expectedProfileID = UUID()
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data) else {
                return encodeIPCResponse(.failure("Could not decode request"))
            }
            let receivedFallback =
                request.operation == .openProfile(profileID: expectedProfileID)
                && request.context.profileID == nil
            return encodeIPCResponse(
                .success(.message(receivedFallback ? "profile fallback used" : "wrong request"))
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["profile", "open", "--profile", expectedProfileID.uuidString],
            socketPath: socketPath
        )
        let operationResult = try parseCLIJSON(result.output)

        // Assert
        #expect(result.status == 0)
        #expect(operationResult["message"] as? String == "profile fallback used")
    }

    @Test func malformedAmbientCallerIsReportedForAutomaticTarget() async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()

        // Act
        let result = try await runCLITest(
            ["board", "web", "url"],
            socketPath: socketPath,
            environmentOverrides: ["DEN_BOARD_ID": "bad-caller"]
        )
        let operationResult = try parseCLIJSON(result.output)

        // Assert
        #expect(result.status == 64)
        #expect(
            operationResult["error"] as? String
                == "Invalid DEN_BOARD_ID: bad-caller. Expected a UUID; pass --board <uuid> explicitly or unset DEN_BOARD_ID."
        )
    }

    @Test func malformedAmbientCallerIsIgnoredForExplicitTarget() async throws {
        // Arrange
        let explicitBoardID = UUID()
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data) else {
                return encodeIPCResponse(.failure("Could not decode request"))
            }
            let ignoredMalformedCaller =
                request.operation
                == .sheet(command: .url, target: .explicit(explicitBoardID))
                && request.context.callerBoardID == nil
            return encodeIPCResponse(
                .success(.message(ignoredMalformedCaller ? "caller ignored" : "wrong request"))
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["board", "web", "url", "--board", explicitBoardID.uuidString],
            socketPath: socketPath,
            environmentOverrides: ["DEN_BOARD_ID": "bad-caller"]
        )
        let operationResult = try parseCLIJSON(result.output)

        // Assert
        #expect(result.status == 0)
        #expect(operationResult["message"] as? String == "caller ignored")
    }

    @Test func resolvedTargetContextDoesNotLeakIntoCLIJSON() async throws {
        // Arrange
        let profileID = UUID()
        let boardID = UUID()
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data),
                request.operation == .sheet(command: .url, target: .explicit(boardID))
            else {
                return encodeIPCResponse(.failure("Unexpected request"))
            }
            return encodeIPCResponse(
                .success(.url("https://example.com/")),
                target: .board(profileID: profileID, boardID: boardID)
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["board", "web", "url", "--board", boardID.uuidString],
            socketPath: socketPath
        )
        let output = try parseCLIJSON(result.output)

        // Assert
        #expect(result.status == 0)
        #expect(output["url"] as? String == "https://example.com/")
        #expect(output["profile_id"] == nil)
        #expect(output["target"] == nil)
    }
}
