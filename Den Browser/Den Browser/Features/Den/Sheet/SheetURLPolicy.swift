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

    static func canonicalSheetURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        normalize(&components)
        return components.url ?? url
    }

    private static func normalize(_ components: inout URLComponents) {
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path.isEmpty {
            components.path = "/"
        }
    }
}
