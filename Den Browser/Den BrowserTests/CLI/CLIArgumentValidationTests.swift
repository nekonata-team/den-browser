import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

struct CLIArgumentValidationTests {
    @Test(arguments: ["Enter", "Shift+Tab", "Ctrl+C", "Alt+ArrowLeft", "Meta+A"])
    func terminalPressForwardsKeys(key: String) async throws {
        let boardID = UUID()
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data)
            return encodeIPCResponse(
                request?.operation == .terminal(command: .press(key: key), target: .explicit(boardID))
                    ? .success() : .failure("Unexpected terminal key")
            )
        }
        defer { server.stop() }
        let result = try await runCLITest(
            ["board", "terminal", "press", key, "--board", boardID.uuidString],
            socketPath: socketPath
        )
        #expect(result.status == 0)
        #expect(try parseCLIJSON(result.output)["ok"] as? Bool == true)
    }

    @Test(arguments: ["Unknown", "Ctrl+", "Hyper+Enter", "Ctrl+Ctrl+C"])
    func terminalPressRejectsInvalidKeysBeforeConnecting(key: String) async throws {
        let result = try await runCLITest(
            ["board", "terminal", "press", key],
            socketPath: makeTemporaryCLISocketPath()
        )
        #expect(result.status == 64)
    }

    @Test(arguments: [false, true])
    func notificationListForwardsFiltersAndReturnsPublicFields(filtered: Bool) async throws {
        // Arrange
        let boardID = UUID()
        let id = UUID()
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data)
            let expected = DenIPCOperation.listNotifications(
                unreadOnly: filtered,
                boardID: filtered ? boardID : nil,
                limit: filtered ? 10 : nil
            )
            return encodeIPCResponse(
                request?.operation == expected
                    ? .success(
                        .notifications([
                            DenNotificationInfo(
                                id: id,
                                title: "Title",
                                body: "Body",
                                boardID: boardID,
                                createdAt: "2026-11-11T00:00:00Z",
                                isRead: false
                            )
                        ])
                    ) : .failure("Unexpected notification request")
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["notification", "list"] + (filtered ? ["--unread", "--board", boardID.uuidString, "--limit", "10"] : []),
            socketPath: socketPath
        )
        let object = try parseCLIJSON(result.output)
        let item = try #require((object["notifications"] as? [[String: Any]])?.first)

        // Assert
        #expect(result.status == 0)
        #expect(item["id"] as? String == id.uuidString)
        #expect(item["board_id"] as? String == boardID.uuidString)
        #expect(item["created_at"] as? String == "2026-11-11T00:00:00Z")
        #expect(item["is_read"] as? Bool == false)
        #expect(item["title"] as? String == "Title")
        #expect(item["body"] as? String == "Body")
    }

    @Test(arguments: [false, true])
    func notificationReadForwardsIdentity(isRead: Bool) async throws {
        // Arrange
        let id = UUID()
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data)
            return encodeIPCResponse(
                request?.operation == .setNotificationRead(id: id, isRead: isRead) ? .success() : .failure("Wrong ID")
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["notification", isRead ? "read" : "unread", id.uuidString],
            socketPath: socketPath
        )

        // Assert
        #expect(result.status == 0)
        #expect(try parseCLIJSON(result.output)["ok"] as? Bool == true)
    }

    @Test(arguments: [
        ["list", "--limit", "0"], ["list", "--limit", "-1"], ["list", "--limit", "1.5"],
        ["list", "--board", "invalid"], ["read", "invalid"], ["read"], ["list", "--count"],
        ["unread", "invalid"], ["unread"],
    ])
    func notificationRejectsInvalidArguments(arguments: [String]) async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()

        // Act
        let result = try await runCLITest(["notification"] + arguments, socketPath: socketPath)

        // Assert
        #expect(result.status == 64)
    }

    @Test(arguments: [nil, 1, 200] as [Int?])
    func terminalTextForwardsHistoryLimit(lines: Int?) async throws {
        // Arrange
        let boardID = UUID()
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data)
            return encodeIPCResponse(
                request?.operation == .terminal(command: .text(lines: lines), target: .explicit(boardID))
                    ? .success(.text("retained output")) : .failure("Unexpected request")
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["board", "terminal", "text", "--board", boardID.uuidString]
                + (lines.map { ["--lines", String($0)] } ?? []),
            socketPath: socketPath
        )
        let object = try parseCLIJSON(result.output)

        // Assert
        #expect(result.status == 0)
        #expect(object["text"] as? String == "retained output")
    }

    @Test(arguments: ["0", "-1", "1.5", "invalid"])
    func terminalTextRejectsInvalidHistoryLimit(value: String) async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()

        // Act
        let result = try await runCLITest(["board", "terminal", "text", "--lines", value], socketPath: socketPath)

        // Assert
        #expect(result.status == 64)
    }

    @Test(arguments: [["health"], ["board", "exists", "--board", UUID().uuidString]])
    func connectionFailureExplainsSocketAndRecovery(arguments: [String]) async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()

        // Act
        let result = try await runCLITest(arguments, socketPath: socketPath)
        let message = try #require(String(data: result.error, encoding: .utf8))

        // Assert
        #expect(result.status == 1)
        #expect(message.contains(socketPath))
        #expect(message.contains("Open Den Browser and retry"))
        #expect(message.contains("--socket and DEN_SOCKET"))
    }

    @Test(arguments: [false, true])
    func webStateResultSeparatesFalseFromFailure(fails: Bool) async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { _ in
            encodeIPCResponse(fails ? .failure("Board not found") : .success(.visible(false)))
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(["board", "web", "is", "visible", "@e1"], socketPath: socketPath)
        let object = try parseCLIJSON(result.output)

        // Assert
        #expect(result.status == (fails ? 1 : 0))
        #expect(object["ok"] as? Bool == !fails)
        #expect(object["visible"] as? Bool == (fails ? nil : false))
        #expect(object["error"] as? String == (fails ? "Board not found" : nil))
    }

    @Test func oversizedSocketPathUsesValidationFailure() async throws {
        // Arrange
        let socketPath = "/tmp/" + String(repeating: "a", count: 200)

        // Act
        let result = try await runCLITest(["health"], socketPath: socketPath)
        let message = try #require(String(data: result.error, encoding: .utf8))

        // Assert
        #expect(result.status == 64)
        #expect(message.contains("Socket path too long"))
        #expect(message.contains("Use a shorter --socket path"))
    }

    @Test(arguments: [["board", "web", "new"], ["board", "terminal", "new"], ["board", "move"]])
    func placementHelpExplainsExclusiveOptions(command: [String]) async throws {
        // Arrange
        let arguments = command + ["--help"]

        // Act
        let result = try await runCLITest(arguments, socketPath: makeTemporaryCLISocketPath())
        let help = try #require(String(data: result.output, encoding: .utf8))

        // Assert
        #expect(result.status == 0)
        #expect(help.contains("--left-of <board-id>"))
        #expect(help.contains("--right-of <board-id>"))
        #expect(help.contains("--end-of <desk-id>"))
        #expect(help.lowercased().contains("mutually exclusive"))
        #expect(help.contains(command.last == "move" ? "exactly one" : "at most one"))
    }

    @Test(arguments: ["web", "terminal"])
    func placementConflictExplainsArgumentsWithoutInternalError(kind: String) async throws {
        // Arrange
        let arguments = ["board", kind, "new"] + (kind == "web" ? ["https://example.com/"] : [])

        // Act
        let result = try await runCLITest(
            arguments + ["--left-of", UUID().uuidString, "--end-of", UUID().uuidString],
            socketPath: makeTemporaryCLISocketPath()
        )
        let object = try parseCLIJSON(result.output)
        let message = try #require(object["error"] as? String)

        // Assert
        #expect(result.status == 64)
        #expect(message == "Specify at most one of --left-of, --right-of, or --end-of")
    }

    @Test func interactStateErrorPreservesCauseAndLine() async throws {
        // Arrange
        let script = "url\nis unknown @e1"

        // Act
        let result = try await runCLITest(
            ["board", "web", "interact", script],
            socketPath: makeTemporaryCLISocketPath()
        )
        let message = try #require(String(data: result.error, encoding: .utf8))

        // Assert
        #expect(result.status == 64)
        #expect(message.contains("Line 2: Unknown state: unknown. Use visible, enabled, or checked."))
        #expect(!message.contains("ArgumentParser"))
        #expect(!message.contains("ValidationError"))
    }

    @Test(arguments: ["web", "terminal"], ["--left-of", "--right-of"])
    func boardCreationForwardsRelativeDestination(kind: String, option: String) async throws {
        // Arrange
        let id = UUID()
        let destination: DenBoardCreationDestination = option == "--left-of" ? .leftOf(id) : .rightOf(id)
        let expected: DenIPCOperation =
            kind == "web"
            ? .createWebBoard(payload: .init(url: "https://example.com/", focus: false), destination: destination)
            : .createTerminalBoard(payload: .init(path: nil, runCommand: nil, focus: false), destination: destination)
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data)
            return encodeIPCResponse(request?.operation == expected ? .success() : .failure("Unexpected destination"))
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["board", kind, "new"] + (kind == "web" ? ["https://example.com/"] : []) + [option, id.uuidString],
            socketPath: socketPath
        )

        // Assert
        #expect(result.status == 0)
    }

    @Test(
        arguments: ["web", "terminal"],
        [
            ["--left-of", "invalid"], ["--right-of", "invalid"],
            ["--left-of", UUID().uuidString, "--right-of", UUID().uuidString],
            ["--end-of", UUID().uuidString, "--left-of", UUID().uuidString],
            ["--end-of", UUID().uuidString, "--right-of", UUID().uuidString],
        ]
    )
    func boardCreationRejectsConflictingOrInvalidPlacement(kind: String, arguments: [String]) async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { _ in encodeIPCResponse(.success()) }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["board", kind, "new"] + (kind == "web" ? ["https://example.com/"] : []) + arguments,
            socketPath: socketPath
        )

        // Assert
        #expect(result.status == 64)
    }

    @Test(arguments: ["--left-of", "--right-of", "--end-of"])
    func boardMoveForwardsExplicitDestination(option: String) async throws {
        // Arrange
        let boardID = UUID()
        let targetID = UUID()
        let destination: DenBoardMoveDestination
        switch option {
        case "--left-of": destination = .leftOf(targetID)
        case "--right-of": destination = .rightOf(targetID)
        default: destination = .endOfDesk(targetID)
        }
        let expected = DenIPCOperation.moveBoard(boardID: boardID, destination: destination)
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data)
            return encodeIPCResponse(request?.operation == expected ? .success() : .failure("Unexpected move"))
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["board", "move", "--board", boardID.uuidString, option, targetID.uuidString],
            socketPath: socketPath
        )

        // Assert
        #expect(result.status == 0)
    }

    @Test(arguments: [false, true], [false, true])
    func deskCommandsForwardExplicitOptions(remove: Bool, enabled: Bool) async throws {
        // Arrange
        let deskID = UUID()
        let socketPath = makeTemporaryCLISocketPath()
        let expected: DenIPCOperation =
            remove
            ? .removeDesk(deskID: deskID, force: enabled) : .createDesk(label: "Work", focus: enabled)
        let payload: DenIPCResultPayload =
            remove
            ? .removedDesk(id: deskID.uuidString) : .createdDesk(id: deskID.uuidString)
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data), request.operation == expected
            else { return encodeIPCResponse(.failure("Unexpected Desk operation")) }
            return encodeIPCResponse(.success(payload))
        }
        defer { server.stop() }
        let arguments =
            remove
            ? ["desk", "remove", "--desk", deskID.uuidString] + (enabled ? ["--force"] : [])
            : ["desk", "new", "Work"] + (enabled ? ["--focus"] : [])

        // Act
        let result = try await runCLITest(arguments, socketPath: socketPath)
        let object = try parseCLIJSON(result.output)

        // Assert
        #expect(result.status == 0)
        #expect(object[remove ? "removed_desk_id" : "desk_id"] as? String == deskID.uuidString)
    }

    @Test(arguments: [false, true])
    func dialogSaveForwardsDestinationAndExplicitOverwrite(overwrite: Bool) async throws {
        // Arrange
        let id = UUID()
        let socketPath = makeTemporaryCLISocketPath()
        let destination = URL(fileURLWithPath: "report.pdf").standardizedFileURL.path
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data) else {
                return encodeIPCResponse(.failure("Could not decode request"))
            }
            let expected = DenIPCCommand.Sheet.dialog(.save(id: id, path: destination, overwrite: overwrite))
            guard request.operation == .sheet(command: expected, target: .automatic) else {
                return encodeIPCResponse(.failure("Unexpected save destination or overwrite permission"))
            }
            return encodeIPCResponse(.success())
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["board", "web", "dialog", "save", id.uuidString, "--path", "report.pdf"]
                + (overwrite ? ["--overwrite"] : []),
            socketPath: socketPath
        )

        // Assert
        #expect(result.status == 0)
    }

    @Test(arguments: [
        MalformedCLIInvocation(
            arguments: ["desk", "remove", "--desk", "bad-id"],
            expectedError: "Invalid Desk ID: bad-id. Expected a UUID; run 'den desk list' to find Desk IDs."
        ),
        MalformedCLIInvocation(
            arguments: ["board", "list", "--desk", "bad-id"],
            expectedError: "Invalid Desk ID: bad-id. Expected a UUID; run 'den desk list' to find Desk IDs."
        ),
        MalformedCLIInvocation(
            arguments: ["board", "web", "new", "https://example.com/", "--end-of", "bad-id"],
            expectedError: "Invalid Desk ID: bad-id. Expected a UUID; run 'den desk list' to find Desk IDs."
        ),
        MalformedCLIInvocation(
            arguments: ["board", "terminal", "new", "--end-of", "bad-id"],
            expectedError: "Invalid Desk ID: bad-id. Expected a UUID; run 'den desk list' to find Desk IDs."
        ),
        MalformedCLIInvocation(
            arguments: ["board", "web", "url", "--board", "bad-id"],
            expectedError: "Invalid Board ID: bad-id. Expected a UUID; run 'den board list -l' to find Board IDs."
        ),
        MalformedCLIInvocation(
            arguments: ["board", "terminal", "text", "--board", "bad-id"],
            expectedError: "Invalid Board ID: bad-id. Expected a UUID; run 'den board list -l' to find Board IDs."
        ),
        MalformedCLIInvocation(
            arguments: ["board", "close", "--board", "bad-id"],
            expectedError: "Invalid Board ID: bad-id. Expected a UUID; run 'den board list -l' to find Board IDs."
        ),
        MalformedCLIInvocation(
            arguments: ["board", "inspection", "read", "--board", "bad-id"],
            expectedError:
                "Invalid Board ID: bad-id. Expected a UUID; run 'den board list -l' to find Board IDs. Usage: den board inspection read --board <inspection-board-id>"
        ),
        MalformedCLIInvocation(
            arguments: ["board", "inspection", "new", "--target", "bad-id"],
            expectedError:
                "Invalid Board ID: bad-id. Expected a UUID; run 'den board list -l' to find Board IDs. Usage: den board inspection new --target <web-board-id>"
        ),
        MalformedCLIInvocation(
            arguments: ["board", "web", "url", "--profile", "bad-id"],
            expectedError:
                "Invalid Profile ID: bad-id. Expected a UUID; run 'den profile list' to find Profile IDs. Check the supplied ID or DEN_PROFILE."
        ),
        MalformedCLIInvocation(
            arguments: ["profile", "open", "bad-id"],
            expectedError:
                "Invalid Profile ID: bad-id. Expected a UUID; run 'den profile list' to find Profile IDs. Check the supplied ID or DEN_PROFILE."
        ),
        MalformedCLIInvocation(
            arguments: ["board", "web", "get", "value", ""],
            expectedError: "The Sheet get target must not be empty"
        ),
    ])
    func malformedExplicitIDsReturnStructuredFailures(_ invocation: MalformedCLIInvocation) async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()

        // Act
        let result = try await runCLITest(invocation.arguments, socketPath: socketPath)
        let operationResult = try parseCLIJSON(result.output)

        // Assert
        #expect(result.status == 64)
        #expect(operationResult["ok"] as? Bool == false)
        #expect(operationResult["error"] as? String == invocation.expectedError)
    }

    @Test(arguments: [["profile", "list"], ["health"]])
    func profileListAndHealthIgnoreUnusedInvalidScope(arguments: [String]) async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()
        let expectedOperation: DenIPCOperation = arguments == ["health"] ? .health : .profileList
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data) else {
                return encodeIPCResponse(.failure("Could not decode request"))
            }
            let ignoredInvalidScope =
                request.operation == expectedOperation
                && request.context.profileID == nil
                && request.context.callerBoardID == nil
            return encodeIPCResponse(
                .success(.message(ignoredInvalidScope ? "unused scope ignored" : "wrong request"))
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(arguments + ["--profile", "bad-profile"], socketPath: socketPath)
        let operationResult = try parseCLIJSON(result.output)

        // Assert
        #expect(result.status == 0)
        #expect(operationResult["message"] as? String == "unused scope ignored")
    }
}
