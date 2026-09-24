import Foundation
import Testing

struct DenCLIVersionTests {
    @Test func reportsBundledAppVersion() throws {
        // Arrange
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["--version"]
        let output = Pipe()
        process.standardOutput = output
        let appVersion = try #require(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)

        // Act
        try process.run()
        let response = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // Assert
        let outputText = try #require(String(data: response, encoding: .utf8))
        #expect(process.terminationStatus == 0)
        #expect(outputText.contains(appVersion))
    }
}
