import Foundation
import Testing

@testable import Den_Browser

struct DenSheetCommandTests {
    @Test(arguments: [false, true])
    func snapshotForwardsFullMode(full: Bool) async throws {
        // Arrange
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("den-cli-\(UUID().uuidString).sock").path
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            do {
                let request = try JSONDecoder().decode(DenIPCRequest.self, from: data)
                let isFull = request.args.contains("--full")
                return try JSONEncoder().encode(
                    DenIPCResponse.success(snapshot: isFull ? "full" : "interactive"))
            } catch {
                return Data()
            }
        }
        defer { server.stop() }
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["sheet", "snapshot", "--socket", socketPath] + (full ? ["--full"] : [])
        let output = Pipe()
        process.standardOutput = output

        // Act
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        let response = try JSONDecoder().decode(
            DenIPCResponse.self, from: output.fileHandleForReading.readDataToEndOfFile())

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(response.snapshot == (full ? "full" : "interactive"))
    }

    @Test func interactForwardsActionsAndSnapshotMode() async throws {
        // Arrange
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("den-cli-\(UUID().uuidString).sock").path
        let script = """
            # First click
            click @e1
            fill @e2 "penguin"
            """
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            do {
                let request = try JSONDecoder().decode(DenIPCRequest.self, from: data)
                let steps = try JSONDecoder().decode(
                    [DenSheetInteractStep].self,
                    from: Data((request.args.first ?? "").utf8)
                )
                let expectedSteps: [DenSheetInteractStep] = [
                    DenSheetInteractStep(line: 2, text: "click @e1", args: ["click", "@e1"]),
                    DenSheetInteractStep(line: 3, text: "fill @e2 \"penguin\"", args: ["fill", "@e2", "penguin"]),
                ]
                let isExpected =
                    request.command == .sheet(.interact)
                    && request.args.contains("--full")
                    && steps == expectedSteps
                return try JSONEncoder().encode(
                    DenIPCResponse.success(snapshot: isExpected ? "full" : "unexpected")
                )
            } catch {
                return Data()
            }
        }
        defer { server.stop() }
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = [
            "sheet", "interact", script, "--full", "--socket", socketPath,
        ]
        let output = Pipe()
        process.standardOutput = output

        // Act
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        let response = try JSONDecoder().decode(
            DenIPCResponse.self,
            from: output.fileHandleForReading.readDataToEndOfFile()
        )

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(response.snapshot == "full")
    }

    @Test func interactHandlesCommentsSemicolonsAndQuotes() async throws {
        // Arrange
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("den-cli-\(UUID().uuidString).sock").path
        let script = """
            # Setup actions
            click --role button --name "Search items" --exact ; wait #results --state visible
            fill @e2 'penguin'
            press Enter
            """
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            do {
                let request = try JSONDecoder().decode(DenIPCRequest.self, from: data)
                let steps = try JSONDecoder().decode(
                    [DenSheetInteractStep].self,
                    from: Data((request.args.first ?? "").utf8)
                )
                let expectedSteps: [DenSheetInteractStep] = [
                    DenSheetInteractStep(
                        line: 2,
                        text: "click --role button --name \"Search items\" --exact",
                        args: ["click", "--role", "button", "--name", "Search items", "--exact"]
                    ),
                    DenSheetInteractStep(
                        line: 2,
                        text: "wait #results --state visible",
                        args: ["wait", "#results", "--state", "visible"]
                    ),
                    DenSheetInteractStep(line: 3, text: "fill @e2 'penguin'", args: ["fill", "@e2", "penguin"]),
                    DenSheetInteractStep(line: 4, text: "press Enter", args: ["press", "Enter"]),
                ]
                let isExpected =
                    request.command == .sheet(.interact)
                    && steps == expectedSteps
                return try JSONEncoder().encode(
                    DenIPCResponse.success(snapshot: isExpected ? "script-ok" : "unexpected")
                )
            } catch {
                return Data()
            }
        }
        defer { server.stop() }

        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["sheet", "interact", script, "--socket", socketPath]
        let output = Pipe()
        process.standardOutput = output

        // Act
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        let response = try JSONDecoder().decode(
            DenIPCResponse.self,
            from: output.fileHandleForReading.readDataToEndOfFile()
        )

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(response.snapshot == "script-ok")
    }

    @Test func interactReadsFromStandardInputWithHyphenArgument() async throws {
        // Arrange
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("den-cli-\(UUID().uuidString).sock").path
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            do {
                let request = try JSONDecoder().decode(DenIPCRequest.self, from: data)
                let steps = try JSONDecoder().decode(
                    [DenSheetInteractStep].self,
                    from: Data((request.args.first ?? "").utf8)
                )
                let isExpected =
                    request.command == .sheet(.interact)
                    && steps.count == 1
                    && steps[0].args == ["click", "@e1"]
                return try JSONEncoder().encode(
                    DenIPCResponse.success(snapshot: isExpected ? "stdin-ok" : "unexpected")
                )
            } catch {
                return Data()
            }
        }
        defer { server.stop() }

        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["sheet", "interact", "-", "--socket", socketPath]
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe

        // Act
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
                inputPipe.fileHandleForWriting.write(Data("click @e1\n".utf8))
                try inputPipe.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        let response = try JSONDecoder().decode(
            DenIPCResponse.self,
            from: outputPipe.fileHandleForReading.readDataToEndOfFile()
        )

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(response.snapshot == "stdin-ok")
    }
}
