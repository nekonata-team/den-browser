import AppKit
import Foundation

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

let cliArgs = Array(CommandLine.arguments.dropFirst())
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
    fputs("Usage: just benchmark <\(choices)> [-- --settle seconds --duration seconds --interval seconds]\n", stderr)
    exit(2)
}
guard settleSeconds.isFinite, settleSeconds >= 0,
    durationSeconds.isFinite, durationSeconds >= 0,
    intervalSeconds.isFinite, intervalSeconds > 0
else {
    fputs(
        "Error: --settle and --duration must be finite and non-negative; --interval must be finite and positive.\n",
        stderr)
    exit(2)
}
appArgs.append(contentsOf: ["--benchmark-scenario", selectedScenario.rawValue])
let benchmarkRunID = UUID().uuidString

var env = ProcessInfo.processInfo.environment
env["DEN_BENCHMARK"] = "1"
env["DEN_BENCHMARK_RUN_ID"] = benchmarkRunID
let traceFileURL = FileManager.default.temporaryDirectory
    .appending(path: "den-benchmark-\(benchmarkRunID).log")
_ = FileManager.default.createFile(atPath: traceFileURL.path, contents: Data())
env["DEN_BENCHMARK_TRACE_FILE"] = traceFileURL.path

print("Launching: \(appPath) \(appArgs.joined(separator: " "))")
let prelaunchSnapshot = queryProcessSnapshot()

final class OutputCollector {
    private var events: [String] = []
    private var lineCount = 0

    func add(_ line: String) {
        events.append(line)
        print("  \(line)")
        fflush(stdout)
    }

    func readNewLines(from url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(whereSeparator: \.isNewline)
        for line in lines.dropFirst(lineCount) {
            add(String(line))
        }
        lineCount = lines.count
    }

    func all() -> [String] {
        return events
    }

    func webKitPIDs() -> Set<Int32> {
        Set(
            events.compactMap { event in
                guard let marker = event.range(of: "webProcessPID=") else { return nil }
                return Int32(event[marker.upperBound...].prefix { $0.isNumber })
            })
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

let collector = OutputCollector()
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
let mainPID = app.processIdentifier
let suiteName = "dev.nekonata.denbrowser.benchmark.\(benchmarkRunID)"
let profileDirectory = FileManager.default.temporaryDirectory
    .appending(path: "DenBrowserBenchmark/\(benchmarkRunID)", directoryHint: .isDirectory)
func cleanBenchmarkFiles() {
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: profileDirectory)
    try? FileManager.default.removeItem(at: traceFileURL)
}
defer {
    if !app.isTerminated { _ = app.forceTerminate() }
    cleanBenchmarkFiles()
}

struct Sample {
    let appCPU: Double
    let appCPUSeconds: Double
    let appRSSMB: Double
    let webKitCPU: Double?
    let webKitCPUSeconds: Double
    let webKitRSSMB: Double
    var totalCPU: Double? {
        guard let webKitCPU else { return nil }
        return appCPU + webKitCPU
    }
    var totalRSSMB: Double { appRSSMB + webKitRSSMB }
}

enum BenchmarkScenario: String, CaseIterable {
    case emptyDesk = "empty-desk"
    case oneTerminalBoard = "one-terminal-board"
    case oneWebBoard = "one-web-board"
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
            rssMB: rssKB / 1024.0)
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

    let webKitMetrics = webKitPIDs.compactMap { pid -> (ProcessMetric, Double, Double)? in
        guard let metric = current.processes[pid],
            let cpu = processCPU(for: pid, current: current, previous: previous)
        else { return nil }
        return (metric, cpu.seconds, cpu.interval)
    }
    let webKitCPUSeconds = webKitMetrics.reduce(0) { $0 + $1.1 }
    let interval = webKitMetrics.map(\.2).max() ?? 0
    let webKitCPU =
        interval > 0
        ? webKitMetrics.reduce(0) { $0 + $1.1 / $1.2 * 100 }
        : nil
    let webKitRSS = webKitMetrics.reduce(0) { $0 + $1.0.rssMB }

    return Sample(
        appCPU: appCPU.seconds / appCPU.interval * 100,
        appCPUSeconds: appCPU.seconds,
        appRSSMB: appMetric.rssMB,
        webKitCPU: webKitCPU,
        webKitCPUSeconds: webKitCPUSeconds,
        webKitRSSMB: webKitRSS)
}

let canMeasureWebKit = selectedScenario == .oneWebBoard
func printSample(_ sample: Sample, index: Int, phase: String) {
    let webKitCPU = sample.webKitCPU.map { String(format: "%5.1f%%", $0) } ?? "  N/A "
    let totalCPU = sample.totalCPU.map { String(format: "%5.1f%%", $0) } ?? "  N/A "
    let webKitRSS = sample.webKitRSSMB > 0 ? String(format: "%6.1fMB", sample.webKitRSSMB) : "    N/A"
    let formatted = String(
        format:
            "\r  [\(phase) Sample %d] App CPU: %5.1f%% | WebKit CPU: %@ | Total CPU: %@ | App RSS: %6.1fMB | WebKit RSS: %@",
        index, sample.appCPU, webKitCPU, totalCPU, sample.appRSSMB, webKitRSS
    )
    fputs(formatted, stdout)
    fflush(stdout)
}

@MainActor func collectStartupSamples(prelaunchSnapshot: ProcessSnapshot?) async -> [Sample] {
    var samples: [Sample] = []
    var nextSampleTime = Date()
    var previousSnapshot = prelaunchSnapshot
    var lastSampleTime: Date?
    let deadline = Date().addingTimeInterval(30)

    while Date() < deadline && !app.isTerminated {
        collector.readNewLines(from: traceFileURL)
        if Date() >= nextSampleTime, let snapshot = queryProcessSnapshot() {
            if let sample = makeSample(
                current: snapshot,
                previous: previousSnapshot,
                mainPID: mainPID,
                webKitPIDs: collector.webKitPIDs())
            {
                samples.append(sample)
                printSample(sample, index: samples.count, phase: "Startup")
            }
            previousSnapshot = snapshot
            lastSampleTime = snapshot.capturedAt
            nextSampleTime = snapshot.capturedAt.addingTimeInterval(intervalSeconds)
        }
        if collector.isReady(for: selectedScenario) {
            if lastSampleTime.map({ Date().timeIntervalSince($0) > 0.05 }) ?? true,
                let snapshot = queryProcessSnapshot()
            {
                if let sample = makeSample(
                    current: snapshot,
                    previous: previousSnapshot,
                    mainPID: mainPID,
                    webKitPIDs: collector.webKitPIDs())
                {
                    samples.append(sample)
                    printSample(sample, index: samples.count, phase: "Startup")
                }
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

@MainActor func collectSamples(for duration: Double, phase: String) async -> [Sample] {
    var samples: [Sample] = []
    collector.readNewLines(from: traceFileURL)
    guard var previousSnapshot = queryProcessSnapshot() else { return samples }
    var nextSampleTime = previousSnapshot.capturedAt.addingTimeInterval(intervalSeconds)
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

        collector.readNewLines(from: traceFileURL)
        if let snapshot = queryProcessSnapshot() {
            if let sample = makeSample(
                current: snapshot,
                previous: previousSnapshot,
                mainPID: mainPID,
                webKitPIDs: collector.webKitPIDs())
            {
                samples.append(sample)
                printSample(sample, index: samples.count, phase: phase)
            }
            previousSnapshot = snapshot
        }
        nextSampleTime = max(
            nextSampleTime.addingTimeInterval(intervalSeconds),
            Date().addingTimeInterval(intervalSeconds))
    }
    return samples
}

func printPhaseSummary(_ phase: String, samples: [Sample], duration: Double) {
    print("\n--- \(phase) (Samples: \(samples.count)) ---")
    guard !samples.isEmpty else {
        print("  No samples recorded")
        return
    }

    let appCPUSeconds = samples.reduce(0) { $0 + $1.appCPUSeconds }
    let appCPUs = samples.map(\.appCPU)
    let appRSS = samples.map(\.appRSSMB)
    let appCPUAverage = appCPUSeconds / duration * 100
    print(
        String(
            format: "  App CPU:            avg %.2f%%, max %.2f%%", appCPUAverage, appCPUs.max() ?? 0)
    )
    print(
        String(
            format: "  App RSS:            avg %.1f MB, latest %.1f MB", appRSS.reduce(0, +) / Double(samples.count),
            appRSS.last ?? 0)
    )

    guard canMeasureWebKit else {
        print("  WebKit:             N/A (no Web Board)")
        print(
            String(format: "  Combined CPU:       avg %.2f%%, max %.2f%% (App only)", appCPUAverage, appCPUs.max() ?? 0)
        )
        print(
            String(
                format: "  Combined RSS:       avg %.1f MB, latest %.1f MB (App only)",
                appRSS.reduce(0, +) / Double(samples.count), appRSS.last ?? 0))
        return
    }
    let webKitSamples = samples.filter { $0.webKitCPU != nil }
    let webKitRSSSamples = samples.filter { $0.webKitRSSMB > 0 }
    guard !webKitRSSSamples.isEmpty else {
        print("  WebKit/combined:    N/A (no WebKit process PID during this phase)")
        return
    }

    let webKitCPUSeconds = webKitSamples.reduce(0) { $0 + $1.webKitCPUSeconds }
    let webKitCPUs = webKitSamples.compactMap(\.webKitCPU)
    let combinedCPUAverage = (appCPUSeconds + webKitCPUSeconds) / duration * 100
    let hasCombinedCPUSample = samples.contains { $0.totalCPU != nil }
    let totalCPUmax = max(appCPUs.max() ?? 0, samples.compactMap(\.totalCPU).max() ?? 0)
    if webKitSamples.isEmpty {
        print("  WebKit CPU:         N/A (no full interval measured)")
    } else {
        let webKitCPUAverage = webKitCPUSeconds / duration * 100
        print(
            String(
                format: "  WebKit CPU:         avg %.2f%%, max %.2f%% (%d samples)",
                webKitCPUAverage, webKitCPUs.max() ?? 0, webKitSamples.count)
        )
    }
    if !hasCombinedCPUSample {
        print(
            String(
                format: "  Combined CPU:       avg %.2f%%, max %.2f%% (App or combined sample)", combinedCPUAverage,
                totalCPUmax))
    } else {
        print(
            String(
                format: "  Combined CPU:       avg %.2f%%, max %.2f%%",
                combinedCPUAverage, totalCPUmax)
        )
    }
    let webKitRSS = webKitRSSSamples.map(\.webKitRSSMB)
    let totalRSS = webKitRSSSamples.map(\.totalRSSMB)
    print(
        String(
            format: "  WebKit RSS:         avg %.1f MB, latest %.1f MB",
            webKitRSS.reduce(0, +) / Double(webKitRSSSamples.count), webKitRSS.last ?? 0)
    )
    print(
        String(
            format: "  Combined RSS:       avg %.1f MB, latest %.1f MB",
            totalRSS.reduce(0, +) / Double(webKitRSSSamples.count), totalRSS.last ?? 0)
    )
}

print("\nSampling startup until the scenario is ready...")
let startupSamples = await collectStartupSamples(prelaunchSnapshot: prelaunchSnapshot)
collector.readNewLines(from: traceFileURL)
let startupDuration = Date().timeIntervalSince(launchRequestedAt)
guard collector.isReady(for: selectedScenario) else {
    printPhaseSummary("Startup", samples: startupSamples, duration: startupDuration)
    _ = app.forceTerminate()
    cleanBenchmarkFiles()
    fputs("Error: Benchmark window or scenario did not become ready within 30 seconds.\n", stderr)
    exit(1)
}

print("\nSampling post-ready settle for \(settleSeconds)s...")
let settleSamples = await collectSamples(for: settleSeconds, phase: "Settle")

print("\nSampling idle performance for \(durationSeconds)s...")
let idleSamples = await collectSamples(for: durationSeconds, phase: "Idle")

print("\n\nTerminating app...")
_ = app.terminate()
for _ in 0..<20 where !app.isTerminated {
    try await Task.sleep(for: .milliseconds(100))
}
if !app.isTerminated {
    _ = app.forceTerminate()
}
collector.readNewLines(from: traceFileURL)

print("\n============================================================")
print("         PERFORMANCE MEASUREMENT SUMMARY")
print("============================================================")

print("\n--- 1. Trace Milestones ---")
let events = collector.all()
if events.isEmpty {
    print("  (No trace events recorded)")
} else {
    for event in events {
        print("  \(event)")
    }
}

print("\n--- 2. Benchmark Scenario ---")
print("  Name:                \(selectedScenario.rawValue)")
print(String(format: "  Launch requested → scenario ready: %.2fs", startupDuration))
printPhaseSummary("3. Startup until ready", samples: startupSamples, duration: startupDuration)
printPhaseSummary("4. Post-ready settle", samples: settleSamples, duration: settleSeconds)
printPhaseSummary("5. Post-settle idle", samples: idleSamples, duration: durationSeconds)
print("============================================================")
