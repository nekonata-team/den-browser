import Foundation

nonisolated struct TerminalCommandResult: Sendable {
    let terminationStatus: Int32
    let standardOutput: String
}

nonisolated struct ZmxSessionSnapshot: Sendable {
    let groups: [ZmxSessionGroup]
    let processNames: [String: String]
}

nonisolated protocol TerminalCommandRunning: Sendable {
    func run(executablePath: String, arguments: [String]) -> TerminalCommandResult?
}

nonisolated struct ProcessTerminalCommandRunner: TerminalCommandRunning {
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
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
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

nonisolated struct ZmxClient: Sendable {
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

    func sessionSnapshot() -> ZmxSessionSnapshot? {
        guard let sessions = sessionsWithRootLabels() else { return nil }
        return ZmxSessionSnapshot(
            groups: makeSessionGroups(from: sessions),
            processNames: processNames(for: sessions))
    }

    func sessionGroups() -> [ZmxSessionGroup]? {
        sessionSnapshot()?.groups
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

    private func processNames(for sessions: [ZmxSessionInfo]) -> [String: String] {
        var processNames = Dictionary(
            uniqueKeysWithValues: sessions.map { ($0.name, "Unknown") })
        guard let processes = processSnapshot() else { return processNames }

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

    private func processSnapshot() -> [Int32: ProcessInfo]? {
        guard
            let result = commandRunner.run(
                executablePath: "/bin/ps",
                arguments: ["-axo", "pid=,ppid=,pgid=,tpgid=,command="]),
            result.terminationStatus == 0
        else { return nil }

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

    private func sessionsWithRootLabels() -> [ZmxSessionInfo]? {
        guard isConfigured,
            let result = commandRunner.run(executablePath: executablePath, arguments: ["list"]),
            result.terminationStatus == 0
        else { return nil }

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

    func killSession(_ sessionName: String) -> Bool {
        let sessionName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConfigured, !sessionName.isEmpty,
            let result = commandRunner.run(
                executablePath: executablePath,
                arguments: ["kill", sessionName, "--force"])
        else { return false }
        return result.terminationStatus == 0
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
