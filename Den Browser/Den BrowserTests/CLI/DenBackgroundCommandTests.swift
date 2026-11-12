import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

struct DenBackgroundCommandTests {
    @Test(arguments: ["read", "on", "off", "new"])
    func commandSendsSettingAndExplicitTarget(mode: String) async throws {
        // Arrange
        let boardID = UUID()
        let socket = "/tmp/den-background-\(UUID()).sock"
        let server = DenSocketServer(socketPath: socket)
        var arguments = ["board", "web"]
        let expected: DenIPCOperation
        if mode == "new" {
            arguments += ["new", "/tmp/probe.html", "--background"]
            expected = .createWebBoard(
                payload: .init(url: "/tmp/probe.html", focus: false, backgroundExecution: true),
                destination: .automatic
            )
        } else {
            arguments += ["background", "--board", boardID.uuidString]
            if mode != "read" { arguments.append(mode) }
            expected = .boardBackgroundExecution(
                enabled: mode == "read" ? nil : mode == "on",
                target: .explicit(boardID)
            )
        }
        try server.start { data in
            let operation = try? JSONDecoder().decode(DenIPCRequest.self, from: data).operation
            let response = DenIPCResponse(
                result: operation == expected ? .success(.enabled(true)) : .failure("Unexpected operation"),
                target: .none
            )
            var encoded = (try? JSONEncoder().encode(response)) ?? Data()
            encoded.append(10)
            return encoded
        }
        defer { server.stop() }
        arguments += ["--socket", socket, "--json"]

        // Act
        let (status, output) = try await run(arguments)

        // Assert
        #expect(status == 0)
        #expect(output.contains("\"enabled\":true"))
    }

    @Test func invalidStateFailsBeforeConnecting() async throws {
        // Arrange / Act
        let (status, _) = try await run(["board", "web", "background", "maybe"])
        // Assert
        #expect(status != 0)
    }

    private func run(_ arguments: [String]) async throws -> (Int32, String) {
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "DEN_BOARD_ID")
        environment.removeValue(forKey: "DEN_PROFILE")
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        return (
            process.terminationStatus,
            try #require(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
        )
    }
}
