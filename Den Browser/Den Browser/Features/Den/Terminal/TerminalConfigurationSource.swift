import Foundation
import GhosttyTerminal
import GhosttyTheme

enum ZmxSessionNameGenerator {
    static func normalizedSuffix(_ suffix: String) -> String {
        suffix.filter { character in
            character.isASCII
                && (character.isLetter || character.isNumber || "-_".contains(character) || character == ".")
        }
    }

    static func nextName(rootSessionName: String, suffix: String, occupiedNames: Set<String>) -> String {
        let cleanSuffix = normalizedSuffix(suffix)
        if cleanSuffix.isEmpty {
            var number = 2
            var candidate = "\(rootSessionName)-\(number)"
            while occupiedNames.contains(candidate) {
                number += 1
                candidate = "\(rootSessionName)-\(number)"
            }
            return candidate
        }

        let baseName = "\(rootSessionName)-\(cleanSuffix)"
        var candidate = baseName
        var number = 2
        while occupiedNames.contains(candidate) {
            candidate = "\(baseName)-\(number)"
            number += 1
        }
        return candidate
    }
}

enum TerminalConfigurationSource {
    struct Resolution {
        let configSource: TerminalController.ConfigSource
        let theme: TerminalTheme
    }

    static func make(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        commandOverride: String? = nil
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
        var contents = loadedCandidates.compactMap {
            try? String(contentsOf: $0, encoding: .utf8)
        }
        .map { removingSetting("theme", from: $0) }
        .map { commandOverride == nil ? $0 : removingSetting("command", from: $0) }
        .joined(separator: "\n")

        if let commandOverride {
            if !contents.isEmpty { contents.append("\n") }
            contents.append("command = \(commandOverride)")
        } else if arguments.contains("--ui-testing") {
            if !contents.isEmpty { contents.append("\n") }
            contents.append("command = /bin/zsh -f")
        }

        return Resolution(
            configSource: .generated(contents),
            theme: resolveTheme(from: loadedCandidates))
    }

    private static func removingSetting(_ keyToRemove: String, from contents: String) -> String {
        contents
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .filter { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#"),
                    let separator = line.firstIndex(of: "=")
                else { return true }
                let key = line[..<separator].trimmingCharacters(in: .whitespaces)
                return key != keyToRemove
            }
            .joined(separator: "\n")
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
}
