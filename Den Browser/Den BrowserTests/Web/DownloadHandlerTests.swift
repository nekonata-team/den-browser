import AppKit
import DenDomain
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DownloadHandlerTests {
    @Test(arguments: [false, true])
    func interruptedDownloadCancelsPendingSaveRequest(downloadFailed: Bool) {
        // Arrange
        let handler = DownloadHandler()
        defer { handler.dispose() }
        var replies: [URL?] = []
        handler.saveDialogs.register(
            panel: NSSavePanel(), suggestedFilename: "report.pdf", downloadKey: ObjectIdentifier(handler)
        ) { url, _ in replies.append(url) }

        // Act
        if downloadFailed {
            handler.failDownload(for: ObjectIdentifier(handler))
        } else {
            handler.dispose()
        }

        // Assert
        #expect(replies == [nil])
        #expect(handler.saveDialogs.pending.isEmpty)
    }

    @Test func fileAppearingDuringDownloadIsPreservedWithoutOverwrite() throws {
        // Arrange
        let handler = DownloadHandler()
        defer { handler.dispose() }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "report.pdf")
        let temporary = DownloadHandler.temporaryDownloadURL(for: destination)
        let keyOwner = NSObject()
        let key = ObjectIdentifier(keyOwner)
        handler.registerPendingDownload(
            for: key, destinationURL: destination, temporaryURL: temporary, allowsOverwrite: false)
        try Data("downloaded".utf8).write(to: temporary)
        // A file appears after the destination was accepted.
        try Data("original".utf8).write(to: destination)

        // Act
        let completed = handler.completeDownload(for: key)

        // Assert
        #expect(!completed)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "original")
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    @Test(arguments: ["finish", "fail", "dispose"])
    func endingDownloadFinalizesOrDiscardsTemporaryFile(event: String) throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "download.txt")
        let temporary = DownloadHandler.temporaryDownloadURL(for: destination)
        let original = Data("original".utf8)
        let downloaded = Data("downloaded".utf8)
        try original.write(to: destination)
        try downloaded.write(to: temporary)
        let download = NSObject()
        let key = ObjectIdentifier(download)
        let handler = DownloadHandler()
        defer { handler.dispose() }
        var finishedFilename: String?
        var failedFilename: String?
        var activityEvents: [DownloadActivityEvent] = []
        handler.onActivity = { activityEvents.append($0) }
        handler.onFinished = { finishedFilename = $0 }
        handler.onFailed = { failedFilename = $0 }
        let activityID = handler.registerPendingDownload(
            for: key, destinationURL: destination, temporaryURL: temporary)

        // Act
        switch event {
        case "finish": handler.completeDownload(for: key)
        case "fail": handler.failDownload(for: key)
        default: handler.dispose()
        }

        // Assert
        #expect(try Data(contentsOf: destination) == (event == "finish" ? downloaded : original))
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        #expect(finishedFilename == (event == "finish" ? destination.lastPathComponent : nil))
        #expect(failedFilename == (event == "fail" ? destination.lastPathComponent : nil))
        #expect(
            activityEvents == [
                .started(DownloadActivity(id: activityID, filename: destination.lastPathComponent)),
                .ended(id: activityID),
            ])
    }
}
