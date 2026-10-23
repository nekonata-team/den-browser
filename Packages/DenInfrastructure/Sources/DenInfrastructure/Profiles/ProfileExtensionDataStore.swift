import DenDomain
import Foundation

public enum ProfileExtensionDataStore {
    public static func remove(_ profileID: ProfileID) throws {
        try remove(profileID, directoryURL: defaultDirectoryURL())
    }

    public static func remove(_ profileID: ProfileID, directoryURL: URL) throws {
        let profileDirectory = directoryURL.appending(path: profileID.rawValue.uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.removeItem(at: profileDirectory)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Profiles that never loaded an extension have no directory.
        }
    }

    private static func defaultDirectoryURL() -> URL {
        // Matches WebKit's persistent storage layout for Den's non-sandboxed app.
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "WebKit", directoryHint: .isDirectory)
            .appending(
                path: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName, directoryHint: .isDirectory
            )
            .appending(path: "WebExtensions", directoryHint: .isDirectory)
    }
}
