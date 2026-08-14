import Foundation
import GhosttyTerminal
import GhosttyTheme

enum ZellijLaunchCommand {
    static func isValidExecutablePath(_ path: String) -> Bool {
        path.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
    }

    static func command(sessionName: String?, executablePath: String) -> String? {
        let executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidExecutablePath(executablePath) else { return nil }

        if let sessionName, !sessionName.isEmpty {
            return "\(shellQuote(executablePath)) attach --create \(shellQuote(sessionName))"
        }
        return "\(shellQuote(executablePath)) -l welcome"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum ZmxLaunchCommand {
    static func isValidExecutablePath(_ path: String) -> Bool {
        path.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
    }

    static func command(
        sessionName: String,
        executablePath: String,
        rootSessionName: String? = nil
    ) -> String? {
        let executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidExecutablePath(executablePath), !sessionName.isEmpty else { return nil }
        guard let rootSessionName = rootSessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rootSessionName.isEmpty
        else {
            return "\(shellQuote(executablePath)) attach \(shellQuote(sessionName))"
        }

        let rootLabel = shellQuote("den.root=\(rootSessionName)")
        let initializeRootLabel =
            "\(shellQuote(executablePath)) set . \(rootLabel) >/dev/null 2>&1 || true; "
            + "exec \"${SHELL:-/bin/zsh}\" -l"
        return "\(shellQuote(executablePath)) attach \(shellQuote(sessionName)) /bin/sh -lc "
            + shellQuote(initializeRootLabel)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

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

enum ZmxSessionNames {
    static func active(executablePath: String) -> Set<String>? {
        let executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ZmxLaunchCommand.isValidExecutablePath(executablePath) else { return nil }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["list", "--short"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return Set(
            text.split(whereSeparator: \.isNewline).compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }
                if let nameField = line.split(separator: "\t").first(where: { $0.hasPrefix("name=") }) {
                    return String(nameField.dropFirst("name=".count))
                }
                return String(line.split(separator: "\t").first ?? "")
            }
        )
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
