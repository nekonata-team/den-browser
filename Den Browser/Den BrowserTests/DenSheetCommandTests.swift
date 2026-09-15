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
}
