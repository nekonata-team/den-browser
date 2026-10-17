import AppKit
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DownloadSaveDialogsTests {
    @Test func acceptsDestinationAndResolvesOnlyOnce() throws {
        // Arrange
        let dialogs = DownloadSaveDialogs()
        defer { dialogs.cancelAll() }
        let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        var replies: [URL?] = []
        var allowsOverwrite: Bool?
        let id = register(in: dialogs) { url, overwrite in
            replies.append(url)
            allowsOverwrite = overwrite
        }

        // Act
        try dialogs.save(id: id, path: destination.path, overwrite: false)
        dialogs.resolve(id: id, destination: nil, overwrite: true)

        // Assert
        #expect(replies == [destination])
        #expect(allowsOverwrite == false)
        #expect(throws: DownloadSaveDialogError.self) { try dialogs.cancel(id: id) }
    }

    @Test(arguments: [false, true])
    func existingEntryRequiresExplicitOverwrite(symlink: Bool) throws {
        // Arrange
        let dialogs = DownloadSaveDialogs()
        defer { dialogs.cancelAll() }
        let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        if symlink {
            try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: "/missing-file")
        } else {
            try Data("original".utf8).write(to: destination)
        }
        var replies: [URL?] = []
        let id = register(in: dialogs) { url, _ in replies.append(url) }

        // Act
        #expect(throws: DownloadSaveDialogError.self) {
            try dialogs.save(id: id, path: destination.path, overwrite: false)
        }

        // Assert
        #expect(replies.isEmpty)
        #expect(dialogs.pending[id] != nil)
    }

    @Test(arguments: ["relative.pdf", "/", "/missing-\(UUID().uuidString)/report.pdf"])
    func invalidDestinationLeavesRequestPending(path: String) {
        // Arrange
        let dialogs = DownloadSaveDialogs()
        defer { dialogs.cancelAll() }
        var replies = 0
        let id = register(in: dialogs) { _, _ in replies += 1 }

        // Act
        #expect(throws: DownloadSaveDialogError.self) {
            try dialogs.save(id: id, path: path, overwrite: true)
        }

        // Assert
        #expect(replies == 0)
        #expect(dialogs.pending[id] != nil)
    }

    private func register(
        in dialogs: DownloadSaveDialogs, completion: @escaping @MainActor (URL?, Bool) -> Void
    ) -> UUID {
        dialogs.register(
            panel: NSSavePanel(), suggestedFilename: "report.pdf", downloadKey: ObjectIdentifier(dialogs),
            completion: completion)
    }
}
