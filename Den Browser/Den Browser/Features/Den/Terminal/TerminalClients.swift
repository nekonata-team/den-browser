import Foundation
import Subprocess
import System

nonisolated struct TerminalCommandResult: Sendable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String

    init(
        terminationStatus: Int32,
        standardOutput: String,
        standardError: String = ""
    ) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

nonisolated struct TerminalCommandError: LocalizedError, Equatable, Sendable {
    let message: String
    var errorDescription: String? { message }
}

nonisolated struct ZmxSessionSnapshot: Sendable {
    let groups: [ZmxSessionGroup]
    let processNames: [String: String]
}

nonisolated protocol TerminalCommandRunning: Sendable {
    func run(
        executablePath: String,
        arguments: [String],
        timeout: Duration
    ) async throws -> TerminalCommandResult
}

nonisolated extension TerminalCommandRunning {
    func run(
        executablePath: String,
        arguments: [String]
    ) async throws -> TerminalCommandResult {
        try await run(
            executablePath: executablePath,
            arguments: arguments,
            timeout: .seconds(5))
    }
}

nonisolated struct SubprocessCommandRunner: TerminalCommandRunning {
    private static let outputLimit = 1024 * 1024

    func run(
        executablePath: String,
        arguments: [String],
        timeout: Duration
    ) async throws -> TerminalCommandResult {
        let executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TerminalExecutablePath.isValid(executablePath) else {
            throw TerminalCommandError(message: "Invalid executable path: \(executablePath)")
        }

        return try await withThrowingTaskGroup(of: TerminalCommandResult.self) { group in
            group.addTask {
                try await runSubprocess(executablePath: executablePath, arguments: arguments)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TerminalCommandError(message: "Command timed out: \(executablePath)")
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }

    private func runSubprocess(
        executablePath: String,
        arguments: [String]
    ) async throws -> TerminalCommandResult {
        var platformOptions = PlatformOptions()
        platformOptions.teardownSequence = [
            .gracefulShutDown(allowedDurationToNextStep: .milliseconds(200))
        ]
        let result = try await Subprocess.run(
            .path(.init(executablePath)),
            arguments: Arguments(arguments),
            platformOptions: platformOptions,
            output: .string(limit: Self.outputLimit),
            error: .string(limit: Self.outputLimit))
        return TerminalCommandResult(
            terminationStatus: Self.terminationStatus(from: result.terminationStatus),
            standardOutput: result.standardOutput,
            standardError: result.standardError)
    }

    private static func terminationStatus(from status: TerminationStatus) -> Int32 {
        switch status {
        case .exited(let code), .signaled(let code):
            code
        }
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

nonisolated struct ZmxClient: Sendable {
    let executablePath: String
    private let commandRunner: any TerminalCommandRunning

    init(
        executablePath: String,
        commandRunner: any TerminalCommandRunning = SubprocessCommandRunner()
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
        let attachCommand = "/usr/bin/env -u ZMX_SESSION \(TerminalExecutablePath.shellQuote(executablePath)) attach"
        guard let rootSessionName = rootSessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rootSessionName.isEmpty
        else {
            return "\(attachCommand) \(TerminalExecutablePath.shellQuote(sessionName))"
        }

        let rootLabel = TerminalExecutablePath.shellQuote("den.root=\(rootSessionName)")
        let initializeRootLabel =
            "\(TerminalExecutablePath.shellQuote(executablePath)) set . \(rootLabel) >/dev/null 2>&1 || true; "
            + "exec \"${SHELL:-/bin/zsh}\" -l"
        return
            "\(attachCommand) \(TerminalExecutablePath.shellQuote(sessionName)) /bin/sh -lc "
            + TerminalExecutablePath.shellQuote(initializeRootLabel)
    }

    func activeSessionNames() async throws -> Set<String> {
        let result = try await run(arguments: ["list", "--short"])

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

    func rootSessionName(for sessionName: String) async throws -> String? {
        let sessionName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionName.isEmpty else { return nil }
        let result = try await run(arguments: ["get", sessionName, "den.root"])

        let rootSessionName = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return rootSessionName.isEmpty ? nil : rootSessionName
    }

    func sessionSnapshot() async throws -> ZmxSessionSnapshot {
        let sessions = try await sessionsWithRootLabels()
        return ZmxSessionSnapshot(
            groups: makeSessionGroups(from: sessions),
            processNames: try await processNames(for: sessions))
    }

    func foregroundProcessGroupID(for sessionName: String) async throws -> pid_t? {
        let sessions = try await sessionsWithRootLabels()
        guard
            let session = sessions.first(where: { $0.name == sessionName }),
            let sessionPID = session.pid
        else { return nil }
        let processes = try await processSnapshot()
        guard let sessionProcess = processes[sessionPID] else { return nil }

        let foregroundProcessGroupID = sessionProcess.terminalProcessGroupID
        if foregroundProcessGroupID > 0 {
            return pid_t(foregroundProcessGroupID)
        }
        return pid_t(sessionPID)
    }

    private func makeSessionGroups(from sessions: [ZmxSessionInfo]) -> [ZmxSessionGroup] {
        var childrenByRoot: [String: [String]] = [:]
        var rootSessionNames = Set(sessions.map(\.name))
        for session in sessions {
            guard let rootSessionName = session.rootSessionName,
                rootSessionName != session.name
            else { continue }
            rootSessionNames.remove(session.name)
            childrenByRoot[rootSessionName, default: []].append(session.name)
        }

        let activeSessionNames = Set(sessions.map(\.name))
        let groupNames = rootSessionNames.union(childrenByRoot.keys).sorted()
        return groupNames.map { rootSessionName in
            ZmxSessionGroup(
                rootSessionName: rootSessionName,
                isRootActive: activeSessionNames.contains(rootSessionName),
                childSessionNames: childrenByRoot[rootSessionName, default: []].sorted())
        }
    }

    private func processNames(for sessions: [ZmxSessionInfo]) async throws -> [String: String] {
        var processNames = Dictionary(
            uniqueKeysWithValues: sessions.map { ($0.name, "Unknown") })
        let processes: [Int32: ProcessInfo]
        do {
            processes = try await processSnapshot()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return processNames
        }

        for session in sessions {
            guard let pid = session.pid, let sessionProcess = processes[pid] else { continue }
            if let processName = foregroundProcessName(
                for: session,
                sessionProcess: sessionProcess,
                processes: processes)
            {
                processNames[session.name] = processName
            }
        }
        return processNames
    }

    private func processSnapshot() async throws -> [Int32: ProcessInfo] {
        let result = try await run(
            executablePath: "/bin/ps",
            arguments: ["-axo", "pid=,ppid=,pgid=,tpgid=,command="])

        var processes: [Int32: ProcessInfo] = [:]
        for rawLine in result.standardOutput.split(whereSeparator: \.isNewline) {
            let fields = rawLine.split(
                maxSplits: 4,
                omittingEmptySubsequences: true,
                whereSeparator: \.isWhitespace)
            guard fields.count == 5,
                let pid = Int32(fields[0]),
                let parentPID = Int32(fields[1]),
                let processGroupID = Int32(fields[2]),
                let terminalProcessGroupID = Int32(fields[3]),
                let executableName = executableName(from: String(fields[4]))
            else { continue }
            processes[pid] = ProcessInfo(
                pid: pid,
                parentPID: parentPID,
                processGroupID: processGroupID,
                terminalProcessGroupID: terminalProcessGroupID,
                executableName: executableName)
        }
        return processes
    }

    private func foregroundProcessName(
        for session: ZmxSessionInfo,
        sessionProcess: ProcessInfo,
        processes: [Int32: ProcessInfo]
    ) -> String? {
        let shellName = sessionProcess.executableName
        let foregroundProcessGroupID = sessionProcess.terminalProcessGroupID
        guard foregroundProcessGroupID > 0 else { return "Idle · \(shellName)" }

        let foregroundProcesses = processes.values.filter {
            $0.processGroupID == foregroundProcessGroupID
        }
        guard !foregroundProcesses.isEmpty else { return "Idle · \(shellName)" }

        let foregroundPIDs = Set(foregroundProcesses.map(\.pid))
        let firstProcess =
            foregroundProcesses
            .sorted { $0.pid < $1.pid }
            .first { !foregroundPIDs.contains($0.parentPID) }
            ?? foregroundProcesses.min { $0.pid < $1.pid }
        guard let firstProcess else { return "Idle · \(shellName)" }
        if firstProcess.pid == session.pid {
            return "Idle · \(firstProcess.executableName)"
        }
        return firstProcess.executableName
    }

    private func executableName(from command: String) -> String? {
        guard let firstArgument = command.split(whereSeparator: \.isWhitespace).first else {
            return nil
        }
        let name = URL(fileURLWithPath: String(firstArgument)).lastPathComponent
        let normalizedName = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalizedName.isEmpty ? nil : normalizedName
    }

    private func sessionsWithRootLabels() async throws -> [ZmxSessionInfo] {
        let result = try await run(arguments: ["list"])

        return result.standardOutput.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let fields = rawLine.split(separator: "\t")
            guard
                let nameField = fields.first,
                let nameStart = nameField.range(of: "name=")
            else { return nil }
            let name = nameField[nameStart.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let pid = fields.first { $0.hasPrefix("pid=") }.flatMap {
                Int32($0.dropFirst("pid=".count).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let rootSessionName = fields.first { $0.hasPrefix("den.root=") }.map {
                String($0.dropFirst("den.root=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ZmxSessionInfo(
                name: String(name),
                pid: pid,
                rootSessionName: rootSessionName?.isEmpty == false ? rootSessionName : nil)
        }
    }

    func killSession(_ sessionName: String) async throws {
        let sessionName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionName.isEmpty else {
            throw TerminalCommandError(message: "A zmx Session name is required.")
        }
        _ = try await run(arguments: ["kill", sessionName, "--force"])
    }

    private func run(
        executablePath: String? = nil,
        arguments: [String]
    ) async throws -> TerminalCommandResult {
        let executablePath = executablePath ?? self.executablePath
        guard TerminalExecutablePath.isValid(executablePath) else {
            throw TerminalCommandError(message: "Invalid executable path: \(executablePath)")
        }
        let result = try await commandRunner.run(
            executablePath: executablePath,
            arguments: arguments)
        guard result.terminationStatus == 0 else {
            let diagnostic = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = diagnostic.isEmpty ? "" : ": \(diagnostic)"
            throw TerminalCommandError(
                message: "Command exited with status \(result.terminationStatus)\(suffix)")
        }
        return result
    }
}

private struct ZmxSessionInfo: Sendable {
    let name: String
    let pid: Int32?
    let rootSessionName: String?
}

private struct ProcessInfo: Sendable {
    let pid: Int32
    let parentPID: Int32
    let processGroupID: Int32
    let terminalProcessGroupID: Int32
    let executableName: String
}

private nonisolated enum TerminalExecutablePath {
    static func isValid(_ path: String) -> Bool {
        path.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
