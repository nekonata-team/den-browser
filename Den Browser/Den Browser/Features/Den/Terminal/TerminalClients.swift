import Foundation

struct TerminalCommandResult {
    let terminationStatus: Int32
    let standardOutput: String
}

protocol TerminalCommandRunning {
    func run(executablePath: String, arguments: [String]) -> TerminalCommandResult?
}

struct ProcessTerminalCommandRunner: TerminalCommandRunning {
    func run(executablePath: String, arguments: [String]) -> TerminalCommandResult? {
        let executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TerminalExecutablePath.isValid(executablePath) else { return nil }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let standardOutput = String(data: data, encoding: .utf8) else { return nil }
        return TerminalCommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: standardOutput)
    }
}

struct ZellijClient {
    let executablePath: String

    var isConfigured: Bool {
        TerminalExecutablePath.isValid(executablePath)
    }

    func launchCommand(sessionName: String?) -> String? {
        let executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TerminalExecutablePath.isValid(executablePath) else { return nil }

        if let sessionName, !sessionName.isEmpty {
            return
                "\(TerminalExecutablePath.shellQuote(executablePath)) attach --create \(TerminalExecutablePath.shellQuote(sessionName))"
        }
        return "\(TerminalExecutablePath.shellQuote(executablePath)) -l welcome"
    }
}

struct ZmxClient {
    let executablePath: String
    private let commandRunner: any TerminalCommandRunning

    init(
        executablePath: String,
        commandRunner: any TerminalCommandRunning = ProcessTerminalCommandRunner()
    ) {
        self.executablePath = executablePath
        self.commandRunner = commandRunner
    }

    var isConfigured: Bool {
        TerminalExecutablePath.isValid(executablePath)
    }

    func launchCommand(sessionName: String, rootSessionName: String? = nil) -> String? {
        let executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TerminalExecutablePath.isValid(executablePath), !sessionName.isEmpty else { return nil }
        guard let rootSessionName = rootSessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rootSessionName.isEmpty
        else {
            return
                "\(TerminalExecutablePath.shellQuote(executablePath)) attach \(TerminalExecutablePath.shellQuote(sessionName))"
        }

        let rootLabel = TerminalExecutablePath.shellQuote("den.root=\(rootSessionName)")
        let initializeRootLabel =
            "\(TerminalExecutablePath.shellQuote(executablePath)) set . \(rootLabel) >/dev/null 2>&1 || true; "
            + "exec \"${SHELL:-/bin/zsh}\" -l"
        return
            "\(TerminalExecutablePath.shellQuote(executablePath)) attach \(TerminalExecutablePath.shellQuote(sessionName)) /bin/sh -lc "
            + TerminalExecutablePath.shellQuote(initializeRootLabel)
    }

    func activeSessionNames() -> Set<String>? {
        guard isConfigured,
            let result = commandRunner.run(
                executablePath: executablePath,
                arguments: ["list", "--short"]),
            result.terminationStatus == 0
        else { return nil }

        return Set(
            result.standardOutput.split(whereSeparator: \.isNewline).compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }
                if let nameField = line.split(separator: "\t").first(where: { $0.hasPrefix("name=") }) {
                    let name = String(nameField.dropFirst("name=".count))
                    return name.isEmpty ? nil : name
                }
                let name = String(line.split(separator: "\t").first ?? "")
                return name.isEmpty ? nil : name
            })
    }

    func rootSessionName(for sessionName: String) -> String? {
        let sessionName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConfigured, !sessionName.isEmpty,
            let result = commandRunner.run(
                executablePath: executablePath,
                arguments: ["get", sessionName, "den.root"]),
            result.terminationStatus == 0
        else { return nil }

        let rootSessionName = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return rootSessionName.isEmpty ? nil : rootSessionName
    }
}

private enum TerminalExecutablePath {
    static func isValid(_ path: String) -> Bool {
        path.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
