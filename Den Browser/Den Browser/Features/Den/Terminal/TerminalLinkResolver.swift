import Foundation

enum TerminalLink: Equatable {
    case web(URL)
    case localFile(URL)
}

enum TerminalLinkResolver {
    static func resolve(_ rawValue: String, relativeTo workingDirectory: String) -> TerminalLink? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let url = URL(string: value), url.scheme != nil {
            guard SheetURLPolicy.isSupported(url) else { return nil }
            let canonicalURL = SheetURLPolicy.canonicalSheetURL(url)
            return canonicalURL.isFileURL
                ? existingLocalFileURL(canonicalURL).map(TerminalLink.localFile)
                : .web(canonicalURL)
        }

        let expandedPath = NSString(string: value).expandingTildeInPath
        let pathURL = URL(
            fileURLWithPath: expandedPath,
            relativeTo: URL(fileURLWithPath: workingDirectory, isDirectory: true)
        ).standardizedFileURL
        return existingLocalFileURL(pathURL).map(TerminalLink.localFile)
    }

    private static func existingLocalFileURL(_ url: URL) -> URL? {
        let host = url.host?.lowercased() ?? ""
        guard
            url.isFileURL,
            host.isEmpty || host == "localhost",
            !url.path.isEmpty,
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }
}
