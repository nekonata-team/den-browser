import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

struct DenWebCommandTests {
    @Test func webCommandForwardsOptionalSnapshotAlongsideResult() async throws {
        // Arrange
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("den-cli-\(UUID().uuidString).sock").path
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            do {
                let request = try JSONDecoder().decode(DenIPCRequest.self, from: data)
                let includesSnapshot = requestSnapshotPayload(request) != nil
                return try encodeResponse(
                    DenIPCOperationResult.success(
                        includesSnapshot ? .url("https://example.com/") : .empty,
                        snapshot: includesSnapshot ? "@e1 button \"Continue\"" : nil
                    ))
            } catch {
                return Data()
            }
        }
        defer { server.stop() }
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["board", "web", "url", "--snapshot", "--socket", socketPath]
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
        let operationResult = try jsonResult(output.fileHandleForReading.readDataToEndOfFile())

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(operationResult["url"] as? String == "https://example.com/")
        #expect(operationResult["snapshot"] as? String == "@e1 button \"Continue\"")
    }

    @Test(arguments: [false, true])
    func snapshotForwardsFullMode(full: Bool) async throws {
        // Arrange
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("den-cli-\(UUID().uuidString).sock").path
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            do {
                let request = try JSONDecoder().decode(DenIPCRequest.self, from: data)
                let isExpected =
                    request.operation
                    == .sheet(
                        command: .snapshot(DenSheetSnapshotPayload(full: full)),
                        target: .automatic
                    )
                return try encodeResponse(
                    DenIPCOperationResult.success(
                        .empty,
                        snapshot: isExpected ? (full ? "full" : "interactive") : "unexpected"
                    )
                )
            } catch {
                return Data()
            }
        }
        defer { server.stop() }
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["board", "web", "snapshot", "--socket", socketPath] + (full ? ["--full"] : [])
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
        let operationResult = try jsonResult(output.fileHandleForReading.readDataToEndOfFile())

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(operationResult["snapshot"] as? String == (full ? "full" : "interactive"))
    }

    @Test func interactForwardsActionsAndSnapshotMode() async throws {
        // Arrange
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("den-cli-\(UUID().uuidString).sock").path
        let script = """
            # Navigate before filling
            navigate https://example.com
            fill @e2 "penguin"
            """
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            do {
                let request = try JSONDecoder().decode(DenIPCRequest.self, from: data)
                let expectedSteps: [DenSheetInteractStep] = [
                    DenSheetInteractStep(
                        line: 2,
                        text: "navigate https://example.com",
                        command: .navigate(DenSheetNavigatePayload(url: "https://example.com"))
                    ),
                    DenSheetInteractStep(
                        line: 3,
                        text: "fill @e2 \"penguin\"",
                        command: .fill(DenSheetFillPayload(target: "@e2", value: "penguin"))
                    ),
                ]
                let isExpected: Bool
                if case .sheetWithSnapshot(.interact(let payload), _, let snapshot) = request.operation {
                    isExpected = snapshot.full && payload.steps == expectedSteps
                } else {
                    isExpected = false
                }
                return try encodeResponse(
                    DenIPCOperationResult.success(.empty, snapshot: isExpected ? "full" : "unexpected")
                )
            } catch {
                return Data()
            }
        }
        defer { server.stop() }
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = [
            "board", "web", "interact", script, "--snapshot", "--full", "--socket", socketPath,
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
        let operationResult = try jsonResult(output.fileHandleForReading.readDataToEndOfFile())

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(operationResult["snapshot"] as? String == "full")
    }

    @Test func interactDefaultsToNoSnapshot() async throws {
        // Arrange
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("den-cli-\(UUID().uuidString).sock").path
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            do {
                let request = try JSONDecoder().decode(DenIPCRequest.self, from: data)
                let includeSnapshot: Bool
                includeSnapshot = requestSnapshotPayload(request) != nil
                return try encodeResponse(
                    DenIPCOperationResult.success(
                        includeSnapshot ? .empty : .interaction(completedActions: 1, failedActionIndex: nil),
                        snapshot: includeSnapshot ? "unexpected" : nil,
                    ))
            } catch {
                return Data()
            }
        }
        defer { server.stop() }
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["board", "web", "interact", "click @e1", "--socket", socketPath]
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
        let operationResult = try jsonResult(output.fileHandleForReading.readDataToEndOfFile())

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(operationResult["snapshot"] == nil)
        #expect(operationResult["completed_actions"] as? Int == 1)
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
                if case .sheet(.interact(let payload), _) = request.operation {
                    isExpected = payload.steps == expectedSteps
                } else {
                    isExpected = false
                }
                return try encodeResponse(
                    DenIPCOperationResult.success(.empty, snapshot: isExpected ? "script-ok" : "unexpected")
                )
            } catch {
                return Data()
            }
        }
        defer { server.stop() }

        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["board", "web", "interact", script, "--socket", socketPath]
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
        let operationResult = try jsonResult(output.fileHandleForReading.readDataToEndOfFile())

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(operationResult["snapshot"] as? String == "script-ok")
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
                if case .sheet(.interact(let payload), _) = request.operation {
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
                return try encodeResponse(
                    DenIPCOperationResult.success(.empty, snapshot: isExpected ? "stdin-ok" : "unexpected")
                )
            } catch {
                return Data()
            }
        }
        defer { server.stop() }

        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["board", "web", "interact", "-", "--socket", socketPath]
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
        let operationResult = try jsonResult(outputPipe.fileHandleForReading.readDataToEndOfFile())

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(operationResult["snapshot"] as? String == "stdin-ok")
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
                    request.operation
                    == .sheet(
                        command: .click(
                            DenSheetClickPayload(
                                target: "@e1",
                                role: nil,
                                name: nil,
                                exact: false,
                                newBoard: true,
                                focus: true
                            )
                        ),
                        target: .automatic
                    )
                return try encodeResponse(
                    DenIPCOperationResult.success(
                        .createdBoard(id: isExpected ? "created-board-id" : "unexpected", message: nil, url: nil)
                    )
                )
            } catch {
                return Data()
            }
        }
        defer { server.stop() }

        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["board", "web", "click", "@e1", "--new-board", "--focus", "--socket", socketPath]
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
        let operationResult = try jsonResult(output.fileHandleForReading.readDataToEndOfFile())

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(operationResult["board_id"] as? String == "created-board-id")
    }
}

private func requestSnapshotPayload(_ request: DenIPCRequest) -> DenSheetSnapshotPayload? {
    guard case .sheetWithSnapshot(_, _, let snapshot) = request.operation else { return nil }
    return snapshot
}

private func encodeResponse(_ result: DenIPCOperationResult) throws -> Data {
    try JSONEncoder().encode(DenIPCResponse(result: result, target: .none))
}

private func jsonResult(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
