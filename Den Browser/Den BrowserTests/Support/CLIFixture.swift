import DenIPCProtocol
import Foundation
import Testing

struct MalformedCLIInvocation: Sendable {
    let arguments: [String]
    let expectedError: String
}

struct CLIInvocationResult {
    let status: Int32
    let output: Data
    let error: Data
}

func parseCLIJSON(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

func encodeIPCResponse(
    _ result: DenIPCOperationResult,
    target: DenIPCTargetContext = .none
) -> Data {
    (try? JSONEncoder().encode(DenIPCResponse(result: result, target: target))) ?? Data()
}

func runCLITest(
    _ arguments: [String],
    socketPath: String,
    environmentOverrides: [String: String] = [:],
    forceJSON: Bool = true,
    standardInput: FileHandle? = nil
) async throws -> CLIInvocationResult {
    let process = Process()
    process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
    process.arguments = arguments + (forceJSON ? ["--json"] : []) + ["--socket", socketPath]
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
    if let standardInput { process.standardInput = standardInput }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        process.terminationHandler = { _ in continuation.resume() }
        do {
            try process.run()
        } catch {
            continuation.resume(throwing: error)
        }
    }
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()

    return CLIInvocationResult(status: process.terminationStatus, output: outputData, error: errorData)
}

func makeTemporaryCLISocketPath() -> String {
    "/tmp/den-cli-validation-\(UUID().uuidString).sock"
}
