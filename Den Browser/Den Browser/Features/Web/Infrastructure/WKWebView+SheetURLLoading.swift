import Foundation
import WebKit

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
