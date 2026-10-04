import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct TerminalLinkResolverTests {
    @Test func resolvesWebURLsAndExistingLocalPaths() throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "TerminalLinkResolverTests-\(UUID().uuidString)",
                directoryHint: .isDirectory)
        let file = directory.appending(path: "reports/summary.pdf")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Act
        let webLink = TerminalLinkResolver.resolve(
            "https://example.com/path",
            relativeTo: directory.path)
        let fileLink = TerminalLinkResolver.resolve(
            "reports/summary.pdf",
            relativeTo: directory.path)

        // Assert
        #expect(webLink == .web(URL(string: "https://example.com/path")!))
        #expect(fileLink == .localFile(file.standardizedFileURL))
    }

    @Test func resolvesExplicitLocalFileURLAndRejectsRemoteOrMissingFiles() throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "TerminalLinkResolverTests-\(UUID().uuidString)",
                directoryHint: .isDirectory)
        let file = directory.appending(path: "notes.md")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Act
        let explicitLink = TerminalLinkResolver.resolve(
            file.absoluteString,
            relativeTo: directory.path)
        let remoteLink = TerminalLinkResolver.resolve(
            "file://server/share/notes.md",
            relativeTo: directory.path)
        let missingLink = TerminalLinkResolver.resolve(
            "missing.md",
            relativeTo: directory.path)

        // Assert
        #expect(explicitLink == .localFile(file.standardizedFileURL))
        #expect(remoteLink == nil)
        #expect(missingLink == nil)
    }
}
