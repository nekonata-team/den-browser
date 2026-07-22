import Foundation

enum SheetURLPolicy {
    static func isSupported(_ url: URL) -> Bool {
        guard
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host,
            !host.isEmpty
        else { return false }
        return true
    }
}
