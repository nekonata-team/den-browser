import Foundation
import GhosttyTerminal
import GhosttyTheme

enum TerminalConfigurationSource {
    struct Resolution {
        let filePath: String?
        let theme: TerminalTheme
    }

    static let current = make()

    static func make(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Resolution {
        let home = fileManager.homeDirectoryForCurrentUser
        let xdgRoot: URL
        if let value = environment["XDG_CONFIG_HOME"], !value.isEmpty {
            xdgRoot = URL(fileURLWithPath: value, relativeTo: home).standardizedFileURL
        } else {
            xdgRoot = home.appending(path: ".config", directoryHint: .isDirectory)
        }

        let candidates = [
            xdgRoot.appending(path: "ghostty/config.ghostty"),
            xdgRoot.appending(path: "ghostty/config"),
            home.appending(path: "Library/Application Support/com.mitchellh.ghostty/config.ghostty"),
            home.appending(path: "Library/Application Support/com.mitchellh.ghostty/config"),
        ]
        let loadedCandidates = (arguments.contains("--ui-testing") ? [] : candidates)
            .filter { fileManager.fileExists(atPath: $0.path) }
        var lines = loadedCandidates.map { "config-file = \(quoted($0.path))" }

        let token = UUID().uuidString
        let directory = fileManager.temporaryDirectory
        let overrideURL = directory.appending(path: "den-browser-ghostty-\(token)-override.conf")
        let url = directory.appending(path: "den-browser-ghostty-\(token).conf")
        do {
            var overrides = ["clipboard-read = deny", "clipboard-write = deny"]
            if arguments.contains("--ui-testing") {
                overrides.append("command = /bin/zsh -f")
            }
            try overrides.joined(separator: "\n")
                .write(to: overrideURL, atomically: true, encoding: .utf8)
            lines.append("config-file = \(quoted(overrideURL.path))")
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return Resolution(
                filePath: url.path,
                theme: resolveTheme(from: loadedCandidates))
        } catch {
            NSLog("Could not create Den Browser Ghostty config: %@", error.localizedDescription)
            return Resolution(filePath: nil, theme: TerminalTheme())
        }
    }

    private static func resolveTheme(from candidates: [URL]) -> TerminalTheme {
        var value: String?
        for candidate in candidates {
            guard let contents = try? String(contentsOf: candidate, encoding: .utf8) else { continue }
            for rawLine in contents.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
                    continue
                }
                let key = line[..<separator].trimmingCharacters(in: .whitespaces)
                guard key == "theme" else { continue }
                value = unquoted(String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces))
            }
        }
        guard let value, !value.isEmpty else { return TerminalTheme() }

        var variants: [String: String] = [:]
        for item in value.split(separator: ",") {
            let pair = item.split(separator: ":", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            variants[pair[0].trimmingCharacters(in: .whitespaces)] =
                pair[1].trimmingCharacters(in: .whitespaces)
        }
        let names =
            if let light = variants["light"], let dark = variants["dark"] {
                (light, dark)
            } else {
                (value, value)
            }
        guard
            let light = GhosttyThemeCatalog.theme(named: names.0),
            let dark = GhosttyThemeCatalog.theme(named: names.1)
        else { return TerminalTheme() }
        return TerminalTheme(
            light: light.toTerminalConfiguration(),
            dark: dark.toTerminalConfiguration())
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
        return String(value.dropFirst().dropLast())
    }

    private static func quoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
