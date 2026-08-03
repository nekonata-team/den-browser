import Foundation

enum ExternalURLPolicy {
    private static let webKitSchemes = Set([
        "about",
        "blob",
        "data",
        "file",
        "http",
        "https",
        "javascript",
    ])

    static func isSupported(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return !webKitSchemes.contains(scheme)
    }
}
