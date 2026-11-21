import AppKit
import Foundation

func writeJSON(_ result: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    var data = try encoder.encode(result)
    data.append(0x0A)
    try FileHandle.standardOutput.write(contentsOf: data)
}

func writeInputSourceMeasurements(from url: URL) throws {
    struct Measurement: Encodable {
        let durationMS: Double
        let contextMS: Double?
        let carbonMS: Double?
        let contextLookupMS: Double?
        let contextSelectMS: Double?
    }

    var groups: [String: [Measurement]] = [:]
    let text = try String(contentsOf: url, encoding: .utf8)
    for line in text.split(whereSeparator: \.isNewline) where line.contains("[PERF:INPUTSOURCE]") {
        var fields: [String: String] = [:]
        for token in line.split(separator: " ") {
            let pair = token.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { fields[String(pair[0])] = String(pair[1]) }
        }
        func duration(_ key: String) -> Double? {
            fields[key].flatMap(Double.init).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
        let stages = ["context", "carbon", "contextLookup", "contextSelect"]
        guard let match = fields["match"], ["same", "different", "unknown"].contains(match),
            let total = duration("duration"),
            fields["context"] != nil, fields["carbon"] != nil,
            stages.allSatisfy({ fields[$0] == nil || fields[$0] == "none" || duration($0) != nil })
        else {
            throw NSError(
                domain: "DenBenchmark",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Invalid input-source measurement: \(line)"]
            )
        }
        groups[match, default: []].append(
            Measurement(
                durationMS: total,
                contextMS: duration("context"),
                carbonMS: duration("carbon"),
                contextLookupMS: duration("contextLookup"),
                contextSelectMS: duration("contextSelect")
            )
        )
    }
    try writeJSON(groups)
}

struct Sample: Encodable {
    let appCPUPercent: Double
    let appCPUSeconds: Double
    let appRSSMB: Double
    let webKitCPUPercent: Double?
    let webKitCPUSeconds: Double?
    let webKitRSSMB: Double?
}

struct BenchmarkPhase: Encodable {
    let durationSeconds: Double
    let samples: [Sample]
}

struct BenchmarkResult: Encodable {
    let scenario: BenchmarkScenario
    let intervalSeconds: Double
    let startup: BenchmarkPhase
    let settle: BenchmarkPhase
    let idle: BenchmarkPhase
}

enum BenchmarkScenario: String, CaseIterable, Encodable {
    case emptyDesk = "empty-desk"
    case oneTerminalBoard = "one-terminal-board"
    case oneWebBoard = "one-web-board"
}

func benchmarkProfileSeed(for scenario: BenchmarkScenario, appBundlePath: String) throws -> Data {
    guard
        let bundle = Bundle(url: URL(fileURLWithPath: appBundlePath)),
        let resourceURL = bundle.url(forResource: "interaction-basics", withExtension: "html"),
        let html = try? String(contentsOf: resourceURL, encoding: .utf8)
    else {
        throw NSError(
            domain: "DenBenchmark",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not load benchmark Sheet fixture."]
        )
    }
    let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "#"))
    guard
        let encoded = html.addingPercentEncoding(withAllowedCharacters: allowed),
        let url = URL(string: "data:text/html,\(encoded)")
    else {
        throw NSError(
            domain: "DenBenchmark",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode benchmark Sheet fixture."]
        )
    }
    let webBoard: [String: Any] = [
        "id": "00000000-0000-0000-0000-000000000511",
        "label": "Web 1",
        "width": 520.0,
        "content": ["kind": "web", "currentSheetURL": url.absoluteString, "firstSheetURL": url.absoluteString],
        "sheetNavigationPaused": false,
    ]
    let terminalBoard: [String: Any] = [
        "id": "00000000-0000-0000-0000-000000000514",
        "label": "Terminal",
        "width": 520.0,
        "content": ["kind": "terminal", "workingDirectory": "/"],
        "sheetNavigationPaused": false,
    ]
    let boards: [[String: Any]]
    switch scenario {
    case .emptyDesk: boards = []
    case .oneTerminalBoard: boards = [terminalBoard]
    case .oneWebBoard: boards = [webBoard]
    }
    var desk: [String: Any] = [
        "id": "00000000-0000-0000-0000-000000000502",
        "label": "Benchmark",
        "boards": boards,
    ]
    if let focusedBoardID = boards.first?["id"] {
        desk["focusedBoardID"] = focusedBoardID
    }
    let seed: [String: Any] = [
        "schemaVersion": 2,
        "profile": [
            "id": "00000000-0000-0000-0000-000000000501",
            "name": "Benchmark",
            "color": "gray",
            "webProfileStore": ["kind": "default"],
        ],
        "den": [
            "desks": [desk],
            "focusedDeskID": "00000000-0000-0000-0000-000000000502",
        ],
        "deskPresets": [],
    ]
    return try JSONSerialization.data(withJSONObject: seed)
}

final class BenchmarkTrace {
    private var events: [String] = []
    private var lineCount = 0

    func readNewLines(from url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(whereSeparator: \.isNewline)
        events.append(contentsOf: lines.dropFirst(lineCount).map(String.init))
        lineCount = lines.count
    }

    func webKitPIDs() -> Set<Int32> {
        Set(
            events.compactMap { event in
                guard let marker = event.range(of: "webProcessPID=") else { return nil }
                return Int32(event[marker.upperBound...].prefix { $0.isNumber })
            }
        )
    }

    func isReady(for scenario: BenchmarkScenario) -> Bool {
        let windowIsPresented = events.contains {
            $0.contains("ProfileWindowView.onAppear (window content presented)")
        }
        let webBoardHasFinishedNavigation = events.contains {
            $0.contains("BoardRuntime.didFinish navigation")
        }
        return windowIsPresented
            && (scenario != .oneWebBoard || (webBoardHasFinishedNavigation && !webKitPIDs().isEmpty))
    }
}

struct ProcessMetric {
    let pid: Int32
    let cpuSeconds: Double
    let elapsedSeconds: Double
    let rssMB: Double
}

struct ProcessSnapshot {
    let capturedAt: Date
    let processes: [Int32: ProcessMetric]
}

func parseProcessTime(_ value: Substring) -> Double? {
    let dayParts = value.split(separator: "-", maxSplits: 1)
    let days: Double
    let clock: Substring
    if dayParts.count == 2 {
        guard let parsedDays = Double(dayParts[0]) else { return nil }
        days = parsedDays
        clock = dayParts[1]
    } else {
        days = 0
        clock = value
    }

    let parts = clock.split(separator: ":")
    let clockSeconds: Double
    switch parts.count {
    case 3:
        guard let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]) else {
            return nil
        }
        clockSeconds = hours * 3600 + minutes * 60 + seconds
    case 2:
        guard let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        clockSeconds = minutes * 60 + seconds
    case 1:
        guard let seconds = Double(parts[0]) else { return nil }
        clockSeconds = seconds
    default:
        return nil
    }
    return days * 86_400 + clockSeconds
}

func queryProcessSnapshot() -> ProcessSnapshot? {
    let psProcess = Process()
    psProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
    psProcess.arguments = ["-axo", "pid,time,etime,rss"]
    let outPipe = Pipe()
    psProcess.standardOutput = outPipe
    guard (try? psProcess.run()) != nil else { return nil }
    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    psProcess.waitUntilExit()

    guard psProcess.terminationStatus == 0, let output = String(data: data, encoding: .utf8) else { return nil }

    var processes: [Int32: ProcessMetric] = [:]

    for line in output.components(separatedBy: .newlines).dropFirst() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 4,
            let pid = Int32(parts[0]),
            let cpuSeconds = parseProcessTime(parts[1]),
            let elapsedSeconds = parseProcessTime(parts[2]),
            let rssKB = Double(parts[3])
        else { continue }

        processes[pid] = ProcessMetric(
            pid: pid,
            cpuSeconds: cpuSeconds,
            elapsedSeconds: elapsedSeconds,
            rssMB: rssKB / 1024.0
        )
    }

    return ProcessSnapshot(capturedAt: Date(), processes: processes)
}

func processCPU(for pid: Int32, current: ProcessSnapshot, previous: ProcessSnapshot?) -> (
    seconds: Double, interval: Double
)? {
    guard let metric = current.processes[pid] else { return nil }
    let seconds: Double
    let interval: Double
    if let previous, let oldMetric = previous.processes[pid] {
        seconds = max(0, metric.cpuSeconds - oldMetric.cpuSeconds)
        interval = current.capturedAt.timeIntervalSince(previous.capturedAt)
    } else if let previous {
        seconds = metric.cpuSeconds
        interval = current.capturedAt.timeIntervalSince(previous.capturedAt)
    } else {
        seconds = metric.cpuSeconds
        interval = metric.elapsedSeconds
    }
    guard interval > 0 else { return nil }
    return (seconds, interval)
}

func makeSample(
    current: ProcessSnapshot,
    previous: ProcessSnapshot?,
    mainPID: Int32,
    webKitPIDs: Set<Int32>
) -> Sample? {
    guard let appMetric = current.processes[mainPID],
        let appCPU = processCPU(for: mainPID, current: current, previous: previous)
    else { return nil }

    let webKitMetrics = webKitPIDs.compactMap { pid -> (rssMB: Double, seconds: Double, interval: Double)? in
        guard let metric = current.processes[pid],
            let cpu = processCPU(for: pid, current: current, previous: previous)
        else { return nil }
        return (metric.rssMB, cpu.seconds, cpu.interval)
    }
    let webKitRSS = webKitMetrics.reduce(0) { $0 + $1.rssMB }

    return Sample(
        appCPUPercent: appCPU.seconds / appCPU.interval * 100,
        appCPUSeconds: appCPU.seconds,
        appRSSMB: appMetric.rssMB,
        webKitCPUPercent: webKitMetrics.isEmpty ? nil : webKitMetrics.reduce(0) { $0 + $1.seconds / $1.interval * 100 },
        webKitCPUSeconds: webKitMetrics.isEmpty ? nil : webKitMetrics.reduce(0) { $0 + $1.seconds },
        webKitRSSMB: webKitRSS > 0 ? webKitRSS : nil
    )
}

@MainActor struct BenchmarkSampler {
    let mainPID: Int32
    let trace: BenchmarkTrace
    let traceFileURL: URL
    let interval: Double

    func collectStartupSamples(
        app: NSRunningApplication,
        scenario: BenchmarkScenario,
        prelaunchSnapshot: ProcessSnapshot?
    ) async -> [Sample] {
        var samples: [Sample] = []
        var nextSampleTime = Date()
        var previousSnapshot = prelaunchSnapshot
        var lastSampleTime: Date?
        let deadline = Date().addingTimeInterval(30)

        while Date() < deadline && !app.isTerminated {
            trace.readNewLines(from: traceFileURL)
            if Date() >= nextSampleTime, let snapshot = queryProcessSnapshot() {
                recordSample(snapshot, after: previousSnapshot, in: &samples)
                previousSnapshot = snapshot
                lastSampleTime = snapshot.capturedAt
                nextSampleTime = snapshot.capturedAt.addingTimeInterval(interval)
            }
            if trace.isReady(for: scenario) {
                if lastSampleTime.map({ Date().timeIntervalSince($0) > 0.05 }) ?? true,
                    let snapshot = queryProcessSnapshot()
                {
                    recordSample(snapshot, after: previousSnapshot, in: &samples)
                }
                return samples
            }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return samples
            }
        }
        return samples
    }

    func collectSamples(for duration: Double) async -> [Sample] {
        var samples: [Sample] = []
        trace.readNewLines(from: traceFileURL)
        guard var previousSnapshot = queryProcessSnapshot() else { return samples }
        var nextSampleTime = previousSnapshot.capturedAt.addingTimeInterval(interval)
        let endTime = previousSnapshot.capturedAt.addingTimeInterval(duration)

        while nextSampleTime <= endTime {
            let sleepDuration = nextSampleTime.timeIntervalSinceNow
            if sleepDuration > 0 {
                do {
                    try await Task.sleep(for: .seconds(sleepDuration))
                } catch {
                    return samples
                }
            }

            trace.readNewLines(from: traceFileURL)
            if let snapshot = queryProcessSnapshot() {
                recordSample(snapshot, after: previousSnapshot, in: &samples)
                previousSnapshot = snapshot
            }
            nextSampleTime = max(
                nextSampleTime.addingTimeInterval(interval),
                Date().addingTimeInterval(interval)
            )
        }
        return samples
    }

    private func recordSample(
        _ snapshot: ProcessSnapshot,
        after previousSnapshot: ProcessSnapshot?,
        in samples: inout [Sample]
    ) {
        guard
            let sample = makeSample(
                current: snapshot,
                previous: previousSnapshot,
                mainPID: mainPID,
                webKitPIDs: trace.webKitPIDs()
            )
        else { return }
        samples.append(sample)
    }
}

@MainActor func runBenchmark(_ cliArgs: [String]) async throws -> BenchmarkResult {
    let appBundlePath = ".derived-data/Build/Products/Debug/Den Browser.app"
    let appPath = "\(appBundlePath)/Contents/MacOS/Den Browser"

    guard FileManager.default.fileExists(atPath: appPath) else {
        fputs("Error: App binary not found at \(appPath). Run 'just build' first.\n", stderr)
        exit(1)
    }

    var appArgs: [String] = []
    var selectedScenario: BenchmarkScenario?
    var settleSeconds: Double = 4.0
    var durationSeconds: Double = 10.0
    var intervalSeconds: Double = 1.0

    var index = 0
    while index < cliArgs.count {
        let arg = cliArgs[index]
        if arg == "--scenario" {
            guard index + 1 < cliArgs.count else {
                fputs("Error: --scenario requires a value.\n", stderr)
                exit(2)
            }
            let value = cliArgs[index + 1]
            guard let scenario = BenchmarkScenario(rawValue: value) else {
                fputs("Error: Unsupported benchmark scenario '\(value)'.\n", stderr)
                exit(2)
            }
            selectedScenario = scenario
            index += 2
        } else if arg == "--" {
            index += 1
        } else if arg == "--settle", index + 1 < cliArgs.count {
            settleSeconds = Double(cliArgs[index + 1]) ?? 4.0
            index += 2
        } else if arg == "--duration", index + 1 < cliArgs.count {
            durationSeconds = Double(cliArgs[index + 1]) ?? 10.0
            index += 2
        } else if arg == "--interval", index + 1 < cliArgs.count {
            intervalSeconds = Double(cliArgs[index + 1]) ?? 1.0
            index += 2
        } else {
            appArgs.append(arg)
            index += 1
        }
    }

    guard let selectedScenario else {
        let choices = BenchmarkScenario.allCases.map(\.rawValue).joined(separator: "|")
        fputs(
            "Usage: just benchmark <\(choices)> [-- --settle seconds --duration seconds --interval seconds]\n",
            stderr
        )
        exit(2)
    }
    guard settleSeconds.isFinite, settleSeconds >= 0,
        durationSeconds.isFinite, durationSeconds >= 0,
        intervalSeconds.isFinite, intervalSeconds > 0
    else {
        fputs(
            "Error: --settle and --duration must be finite and non-negative; --interval must be finite and positive.\n",
            stderr
        )
        exit(2)
    }
    let benchmarkRunID = UUID().uuidString
    let suiteName = "dev.nekonata.denbrowser.benchmark.\(benchmarkRunID)"
    let runDirectory = FileManager.default.temporaryDirectory
        .appending(path: "DenBrowserBenchmark", directoryHint: .isDirectory)
        .appending(path: benchmarkRunID, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: runDirectory) }
    let seedURL = runDirectory.appending(path: "initial-profile.json")
    try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
    try benchmarkProfileSeed(for: selectedScenario, appBundlePath: appBundlePath).write(to: seedURL, options: .atomic)
    appArgs.append(contentsOf: [
        "--benchmark-scenario", selectedScenario.rawValue,
        "--initial-profile", seedURL.path,
    ])

    var env = ProcessInfo.processInfo.environment
    env["DEN_BENCHMARK"] = "1"
    env["DEN_BENCHMARK_RUN_ID"] = benchmarkRunID
    let traceFileURL = FileManager.default.temporaryDirectory
        .appending(path: "den-benchmark-\(benchmarkRunID).log")
    _ = FileManager.default.createFile(atPath: traceFileURL.path, contents: Data())
    env["DEN_BENCHMARK_TRACE_FILE"] = traceFileURL.path
    defer {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plistURL)
        try? FileManager.default.removeItem(at: traceFileURL)
    }

    let prelaunchSnapshot = queryProcessSnapshot()

    let trace = BenchmarkTrace()
    let launchConfiguration = NSWorkspace.OpenConfiguration()
    launchConfiguration.arguments = appArgs
    launchConfiguration.environment = env
    launchConfiguration.activates = true
    launchConfiguration.createsNewApplicationInstance = true
    let launchRequestedAt = Date()
    let app: NSRunningApplication = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<NSRunningApplication, Error>) in
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: appBundlePath),
            configuration: launchConfiguration
        ) { app, error in
            if let app {
                continuation.resume(returning: app)
            } else {
                continuation.resume(throwing: error ?? NSError(domain: "DenBenchmark", code: 1))
            }
        }
    }
    defer { if !app.isTerminated { _ = app.forceTerminate() } }
    let sampler = BenchmarkSampler(
        mainPID: app.processIdentifier,
        trace: trace,
        traceFileURL: traceFileURL,
        interval: intervalSeconds
    )

    let startupSamples = await sampler.collectStartupSamples(
        app: app,
        scenario: selectedScenario,
        prelaunchSnapshot: prelaunchSnapshot
    )
    trace.readNewLines(from: traceFileURL)
    let startupDuration = Date().timeIntervalSince(launchRequestedAt)
    guard trace.isReady(for: selectedScenario) else {
        throw NSError(
            domain: "DenBenchmark",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Benchmark window or scenario did not become ready within 30 seconds."
            ]
        )
    }

    let settleSamples = await sampler.collectSamples(for: settleSeconds)
    let idleSamples = await sampler.collectSamples(for: durationSeconds)

    _ = app.terminate()
    for _ in 0..<20 where !app.isTerminated {
        try await Task.sleep(for: .milliseconds(100))
    }

    return BenchmarkResult(
        scenario: selectedScenario,
        intervalSeconds: intervalSeconds,
        startup: BenchmarkPhase(durationSeconds: startupDuration, samples: startupSamples),
        settle: BenchmarkPhase(durationSeconds: settleSeconds, samples: settleSamples),
        idle: BenchmarkPhase(durationSeconds: durationSeconds, samples: idleSamples)
    )
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    if arguments.first == "--input-source-log" {
        guard arguments.count == 2 else {
            fputs("Usage: swift scripts/measure.swift --input-source-log <trace-file>\n", stderr)
            exit(2)
        }
        try writeInputSourceMeasurements(from: URL(fileURLWithPath: arguments[1]))
    } else {
        try await writeJSON(runBenchmark(arguments))
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
