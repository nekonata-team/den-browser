import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

struct DenAPICommandTests {
    @Test(arguments: ["new", "enable", "disable", "preserve"])
    func flagsReachTheApp(mode: String) async throws {
        // Arrange
        let socket = FileManager.default.temporaryDirectory.appendingPathComponent("den-api-\(UUID()).sock").path
        let server = DenSocketServer(socketPath: socket)
        let expected: DenIPCOperation
        var arguments = ["board", "web"]
        switch mode {
        case "new":
            arguments += ["new", "/tmp/sketch.html", "--den-api"]
            expected = .createWebBoard(
                payload: .init(url: "/tmp/sketch.html", focus: false, denAPI: true), destination: .automatic)
        default:
            arguments += ["reload"]
            if mode == "enable" { arguments += ["--den-api"] }
            if mode == "disable" { arguments += ["--no-den-api"] }
            expected = .sheet(
                command: mode == "preserve" ? .reload : .reloadWithDenAPI(enabled: mode == "enable"), target: .automatic
            )
        }
        try server.start { data in
            let operation = try? JSONDecoder().decode(DenIPCRequest.self, from: data).operation
            let response = DenIPCResponse(
                result: operation == expected ? .success() : .failure("Unexpected operation"), target: .none)
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
        #expect(output.contains("\"ok\":true"))
    }

    @Test func contradictoryReloadFlagsFailBeforeConnecting() async throws {
        // Arrange / Act
        let (status, _) = try await run(["board", "web", "reload", "--den-api", "--no-den-api"])

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
        let errors = Pipe()
        process.standardError = errors
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
