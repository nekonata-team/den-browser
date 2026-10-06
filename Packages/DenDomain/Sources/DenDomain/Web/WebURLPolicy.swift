import Foundation

public enum WebURLPolicy {
    public static func normalizePastedText(_ text: String, joiningLineBreaksWith separator: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \Character.isNewline)
            .joined(separator: separator)
    }

    public static func stripNewlines(_ text: String) -> String {
        guard text.contains(where: \.isNewline) else { return text }
        return text.filter { !$0.isNewline }
    }

    public static func isSupported(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "http" || scheme == "https" {
            return url.host?.isEmpty == false
        }
        if scheme == "file" {
            let host = url.host?.lowercased()
            return (host == nil || host == "" || host == "localhost")
                && url.path.hasPrefix("/")
                && !url.path.isEmpty
        }
        return false
    }

    public static func canonicalSheetURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if components.scheme?.lowercased() == "file" {
            components.scheme = "file"
            if components.host?.lowercased() == "localhost" {
                components.host = ""
            }
            return components.url ?? url
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
