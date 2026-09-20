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
                let isFull: Bool
                if case .sheet(.snapshot(let payload)) = request.command {
                    isFull = payload.full
                } else {
                    isFull = false
                }
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
                let expectedSteps: [DenSheetInteractStep] = [
                    DenSheetInteractStep(
                        line: 2,
                        text: "click @e1",
                        command: .click(
                            DenSheetClickPayload(
                                target: "@e1",
                                role: nil,
                                name: nil,
                                exact: false,
                                newBoard: false,
                                focus: false
                            )
                        )
                    ),
                    DenSheetInteractStep(
                        line: 3,
                        text: "fill @e2 \"penguin\"",
                        command: .fill(DenSheetFillPayload(target: "@e2", value: "penguin"))
                    ),
                ]
                let isExpected: Bool
                if case .sheet(.interact(let payload)) = request.command {
                    isExpected = payload.full && payload.steps == expectedSteps
                } else {
                    isExpected = false
                }
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
                let expectedSteps: [DenSheetInteractStep] = [
                    DenSheetInteractStep(
                        line: 2,
                        text: "click --role button --name \"Search items\" --exact",
                        command: .click(
                            DenSheetClickPayload(
                                target: nil,
                                role: "button",
                                name: "Search items",
                                exact: true,
                                newBoard: false,
                                focus: false
                            )
                        )
                    ),
                    DenSheetInteractStep(
                        line: 2,
                        text: "wait #results --state visible",
                        command: .wait(
                            DenSheetWaitPayload(
                                target: "#results",
                                state: "visible",
                                url: nil,
                                text: nil,
                                loadState: nil,
                                function: nil,
                                timeout: 10
                            )
                        )
                    ),
                    DenSheetInteractStep(
                        line: 3,
                        text: "fill @e2 'penguin'",
                        command: .fill(DenSheetFillPayload(target: "@e2", value: "penguin"))
                    ),
                    DenSheetInteractStep(
                        line: 4,
                        text: "press Enter",
                        command: .press(DenSheetPressPayload(key: "Enter"))
                    ),
                ]
                let isExpected: Bool
                if case .sheet(.interact(let payload)) = request.command {
                    isExpected = payload.steps == expectedSteps
                } else {
                    isExpected = false
                }
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
                let isExpected: Bool
                if case .sheet(.interact(let payload)) = request.command {
                    isExpected =
                        payload.steps.count == 1
                        && payload.steps[0].command
                            == .click(
                                DenSheetClickPayload(
                                    target: "@e1",
                                    role: nil,
                                    name: nil,
                                    exact: false,
                                    newBoard: false,
                                    focus: false
                                )
                            )
                } else {
                    isExpected = false
                }
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

    @Test func clickForwardsNewBoardAndFocusFlags() async throws {
        // Arrange
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("den-cli-\(UUID().uuidString).sock").path
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            do {
                let request = try JSONDecoder().decode(DenIPCRequest.self, from: data)
                let isExpected =
                    request.command
                    == .sheet(
                        .click(
                            DenSheetClickPayload(
                                target: "@e1",
                                role: nil,
                                name: nil,
                                exact: false,
                                newBoard: true,
                                focus: true
                            )
                        )
                    )
                return try JSONEncoder().encode(
                    DenIPCResponse.success(boardId: isExpected ? "created-board-id" : "unexpected")
                )
            } catch {
                return Data()
            }
        }
        defer { server.stop() }

        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["sheet", "click", "@e1", "--new-board", "--focus", "--socket", socketPath]
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
        #expect(response.boardId == "created-board-id")
    }
}
