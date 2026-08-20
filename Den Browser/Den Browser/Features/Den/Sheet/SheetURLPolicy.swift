import Foundation
import WebKit

enum SheetURLPolicy {
    static func normalizePastedText(_ text: String, joiningLineBreaksWith separator: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \Character.isNewline)
            .joined(separator: separator)
    }

    static func isSupported(_ url: URL) -> Bool {
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

    static func canonicalSheetURL(_ url: URL) -> URL {
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

extension WKWebView {
    @discardableResult
    func loadSheetURL(_ url: URL) -> WKNavigation? {
        guard url.isFileURL else { return load(URLRequest(url: url)) }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let resourceURL = components?.url ?? url
        let readAccessURL =
            resourceURL.hasDirectoryPath
            ? resourceURL
            : resourceURL.deletingLastPathComponent()
        return loadFileURL(url, allowingReadAccessTo: readAccessURL)
    }
}
