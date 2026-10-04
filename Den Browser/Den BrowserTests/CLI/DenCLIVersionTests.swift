import Foundation
import Testing

struct DenCLIVersionTests {
    @Test func reportsBundledAppVersion() throws {
        // Arrange
        let appExecutableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let symlinkURL = temporaryDirectory.appendingPathComponent("den")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: appExecutableURL)
        let appVersion = try #require(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)

        // Act
        for executableURL in [appExecutableURL, symlinkURL] {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["--version"]
            let output = Pipe()
            process.standardOutput = output

            try process.run()
            let response = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            // Assert
            let outputText = try #require(String(data: response, encoding: .utf8))
            #expect(process.terminationStatus == 0)
            #expect(outputText.contains(appVersion))
        }
    }
}
