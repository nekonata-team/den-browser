import Foundation

enum TerminalConfigurationSource {
    static let filePath: String? = makeFile()

    private static func makeFile(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> String? {
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

        var lines = (arguments.contains("--ui-testing") ? [] : candidates)
            .filter { fileManager.fileExists(atPath: $0.path) }
            .map { "config-file = \(quoted($0.path))" }
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
            return url.path
        } catch {
            NSLog("Could not create Den Browser Ghostty config: %@", error.localizedDescription)
            return nil
        }
    }

    private static func quoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
