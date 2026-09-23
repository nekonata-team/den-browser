import Foundation

nonisolated enum DenSocketPath {
    static func temporary(
        prefix: String,
        identifier: String = UUID().uuidString,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> String {
        temporaryDirectory.appending(path: "\(prefix)-\(identifier).sock").path
    }

    static func resolve(
        explicit: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        if let explicit { return explicit }
        if let socket = environment["DEN_SOCKET"], !socket.isEmpty {
            return socket
        }
        return homeDirectory.appending(path: ".den/den.sock").path
    }
}
