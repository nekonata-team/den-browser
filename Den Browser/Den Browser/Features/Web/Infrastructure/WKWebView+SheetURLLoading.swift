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
        if resourceURL.pathExtension.lowercased() == "json",
            let data = try? Data(contentsOf: resourceURL)
        {
            return load(data, mimeType: "application/json", characterEncodingName: "utf-8", baseURL: url)
        }
        let readAccessURL =
            resourceURL.hasDirectoryPath
            ? resourceURL
            : resourceURL.deletingLastPathComponent()
        return loadFileURL(url, allowingReadAccessTo: readAccessURL)
    }
}
