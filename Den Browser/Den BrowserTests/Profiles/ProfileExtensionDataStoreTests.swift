import DenDomain
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct ProfileExtensionDataStoreTests {
    @Test(arguments: [true, false])
    func removesOnlyRequestedProfileAndAllowsRetry(hasExtensionData: Bool) throws {
        // Arrange
        let root = FileManager.default.temporaryDirectory.appending(path: "ExtensionDataTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = ProfileID()
        let targetDirectory = root.appending(path: target.rawValue.uuidString)
        let otherDirectory = root.appending(path: ProfileID().rawValue.uuidString)
        try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)
        let otherData = otherDirectory.appending(path: "LocalStorage.db")
        try Data("keep".utf8).write(to: otherData)
        if hasExtensionData {
            let rules = targetDirectory.appending(path: "extension/DeclarativeNetRequestContentRuleList.data")
            try FileManager.default.createDirectory(
                at: rules.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("rules".utf8).write(to: rules)
        }

        // Act
        try ProfileExtensionDataStore.remove(target, directoryURL: root)
        try ProfileExtensionDataStore.remove(target, directoryURL: root)

        // Assert
        #expect(!FileManager.default.fileExists(atPath: targetDirectory.path))
        #expect(try Data(contentsOf: otherData) == Data("keep".utf8))
    }
}
