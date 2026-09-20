import Foundation

enum TerminalInputError: Error, Equatable {
    case missingDirectory(String)

    var message: String {
        switch self {
        case .missingDirectory(let path): "Terminal directory does not exist: \(path)"
        }
    }
}

enum ZellijInput: Equatable {
    case welcome
    case session(String)
}

enum ZmxInput: Equatable {
    case missingSessionName
    case session(String)
}

enum BoardInputResolver {
    static func resolveZellijInput(_ input: String) -> ZellijInput? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.first == ":zellij" else { return nil }
        guard parts.count == 2 else { return .welcome }

        let sessionName = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sessionName.isEmpty ? .welcome : .session(sessionName)
    }

    static func resolveZmxInput(_ input: String) -> ZmxInput? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.first == ":zmx" else { return nil }
        guard parts.count == 2 else { return .missingSessionName }

        let sessionName = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sessionName.isEmpty ? .missingSessionName : .session(sessionName)
    }

    static func resolveTerminalInput(
        _ input: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Result<String, TerminalInputError>? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.first == ":terminal" else { return nil }

        let rawPath =
            parts.count == 1
            ? ""
            : String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL
        if rawPath.isEmpty || rawPath == "~" {
            url = homeDirectory
        } else if rawPath.hasPrefix("~/") {
            url = homeDirectory.appending(path: String(rawPath.dropFirst(2)), directoryHint: .isDirectory)
        } else if rawPath.hasPrefix("/") {
            url = URL(fileURLWithPath: rawPath, isDirectory: true)
        } else {
            url = homeDirectory.appending(path: rawPath, directoryHint: .isDirectory)
        }
        return validateTerminalWorkingDirectory(url.standardizedFileURL.path, fileManager: fileManager)
    }

    static func validateTerminalWorkingDirectory(
        _ workingDirectory: String,
        fileManager: FileManager = .default
    ) -> Result<String, TerminalInputError> {
        let standardized = URL(fileURLWithPath: workingDirectory, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(.missingDirectory(standardized.path))
        }
        return .success(standardized.path)
    }

    static func normalizedURL(from text: String, searchEngine: SearchEngine) -> URL? {
        resolveOpenBoardInput(text, searchEngine: searchEngine).map { SheetURLPolicy.canonicalSheetURL($0.url) }
    }

    static func resolveOpenBoardInput(
        _ text: String,
        searchEngine: SearchEngine
    ) -> (url: URL, item: RecentItem)? {
        let trimmed = SheetURLPolicy.normalizePastedText(text, joiningLineBreaksWith: " ")
        guard !trimmed.isEmpty else { return nil }

        let urlText = SheetURLPolicy.normalizePastedText(text, joiningLineBreaksWith: "")
        if let url = URL(string: urlText), SheetURLPolicy.isSupported(url) {
            return (url, .url(url))
        }

        let scheme = URL(string: urlText)?.scheme?.lowercased()
        if !urlText.contains("://"),
            !urlText.contains(where: \.isWhitespace),
            scheme == nil || scheme == "localhost" || scheme?.contains(".") == true,
            let url = URL(string: "https://\(urlText)"),
            let host = url.host,
            host == "localhost" || host.contains(".")
        {
            return (url, .url(url))
        }

        // A non-supported scheme is an invalid URL, not a search term. Keep
        // search terms such as "swift: concurrency" valid by only treating
        // scheme-looking input without whitespace as an explicit URL.
        if !urlText.contains(where: \.isWhitespace), URL(string: urlText)?.scheme != nil {
            return nil
        }

        var components = URLComponents(string: searchEngine.searchURL)
        components?.queryItems = [
            URLQueryItem(name: searchEngine == .yahooJapan ? "p" : "q", value: trimmed)
        ]
        guard let url = components?.url else { return nil }
        return (url, .search(trimmed))
    }
}
