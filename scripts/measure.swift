import Foundation

let appPath = ".derived-data/Build/Products/Debug/Den Browser.app/Contents/MacOS/Den Browser"

guard FileManager.default.fileExists(atPath: appPath) else {
    fputs("Error: App binary not found at \(appPath). Run 'just build' first.\n", stderr)
    exit(1)
}

var appArgs: [String] = []
var settleSeconds: Double = 4.0
var durationSeconds: Double = 10.0
var intervalSeconds: Double = 1.0

let cliArgs = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < cliArgs.count {
    let arg = cliArgs[index]
    if arg == "--settle", index + 1 < cliArgs.count {
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

let process = Process()
process.executableURL = URL(fileURLWithPath: appPath)
process.arguments = appArgs
var env = ProcessInfo.processInfo.environment
env["DEN_BENCHMARK"] = "1"
process.environment = env

let pipe = Pipe()
process.standardOutput = pipe
process.standardError = pipe

print("Launching: \(appPath) \(appArgs.joined(separator: " "))")

final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func add(_ line: String) {
        lock.lock()
        events.append(line)
        lock.unlock()
        print("  \(line)")
        fflush(stdout)
    }

    func all() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

let collector = OutputCollector()

try process.run()
let mainPID = process.processIdentifier

Task {
    for try await line in pipe.fileHandleForReading.bytes.lines
    where line.contains("[PERF:") {
        collector.add(line)
    }
}

print("\nWaiting \(settleSeconds)s for startup & settling...")
Thread.sleep(forTimeInterval: settleSeconds)

struct Sample {
    let appCPU: Double
    let appRSSMB: Double
    let webKitCPU: Double
    let webKitRSSMB: Double
    var totalCPU: Double { appCPU + webKitCPU }
    var totalRSSMB: Double { appRSSMB + webKitRSSMB }
}

func queryMetrics(for mainPID: Int32) -> Sample? {
    let psProcess = Process()
    psProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
    psProcess.arguments = ["-eo", "pid,ppid,%cpu,rss,command"]
    let outPipe = Pipe()
    psProcess.standardOutput = outPipe
    guard (try? psProcess.run()) != nil else { return nil }
    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    psProcess.waitUntilExit()

    guard let output = String(data: data, encoding: .utf8) else { return nil }

    var appCPU = 0.0
    var appRSS = 0.0
    var webKitCPU = 0.0
    var webKitRSS = 0.0

    for line in output.components(separatedBy: .newlines).dropFirst() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let parts = trimmed.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard parts.count == 5,
            let pid = Int32(parts[0]),
            let ppid = Int32(parts[1]),
            let cpu = Double(parts[2]),
            let rssKB = Double(parts[3])
        else { continue }

        let rssMB = rssKB / 1024.0
        let command = String(parts[4])

        if pid == mainPID {
            appCPU += cpu
            appRSS += rssMB
        } else if command.contains("com.apple.WebKit") || ppid == mainPID {
            webKitCPU += cpu
            webKitRSS += rssMB
        }
    }

    return Sample(appCPU: appCPU, appRSSMB: appRSS, webKitCPU: webKitCPU, webKitRSSMB: webKitRSS)
}

print("\nSampling idle performance for \(durationSeconds)s (interval: \(intervalSeconds)s)...")
var samples: [Sample] = []
let startTime = Date()

while Date().timeIntervalSince(startTime) < durationSeconds {
    if let sample = queryMetrics(for: mainPID) {
        samples.append(sample)
        let formatted = String(
            format:
                "\r  [Sample %d] App CPU: %5.1f%% | WebKit CPU: %5.1f%% | Total CPU: %5.1f%% | App RSS: %6.1fMB | WebKit RSS: %6.1fMB",
            samples.count, sample.appCPU, sample.webKitCPU, sample.totalCPU, sample.appRSSMB, sample.webKitRSSMB
        )
        fputs(formatted, stdout)
        fflush(stdout)
    }
    Thread.sleep(forTimeInterval: intervalSeconds)
}

print("\n\nTerminating app...")
process.terminate()
process.waitUntilExit()

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

if !samples.isEmpty {
    let count = Double(samples.count)
    let appCPUs = samples.map(\.appCPU)
    let webKitCPUs = samples.map(\.webKitCPU)
    let totalCPUs = samples.map(\.totalCPU)
    let appRSS = samples.map(\.appRSSMB)
    let webKitRSS = samples.map(\.webKitRSSMB)
    let totalRSS = samples.map(\.totalRSSMB)

    print("\n--- 2. Idle CPU Usage (Samples: \(samples.count)) ---")
    print(
        String(format: "  Main App Process:   avg %.2f%%, max %.2f%%", appCPUs.reduce(0, +) / count, appCPUs.max() ?? 0)
    )
    print(
        String(
            format: "  WebKit Processes:   avg %.2f%%, max %.2f%%", webKitCPUs.reduce(0, +) / count,
            webKitCPUs.max() ?? 0))
    print(
        String(
            format: "  Total Idle CPU:     avg %.2f%%, max %.2f%%", totalCPUs.reduce(0, +) / count, totalCPUs.max() ?? 0
        ))

    print("\n--- 3. Idle Memory RSS ---")
    print(
        String(
            format: "  Main App Process:   avg %.1f MB (latest: %.1f MB)", appRSS.reduce(0, +) / count, appRSS.last ?? 0
        ))
    print(
        String(
            format: "  WebKit Processes:   avg %.1f MB (latest: %.1f MB)", webKitRSS.reduce(0, +) / count,
            webKitRSS.last ?? 0))
    print(
        String(
            format: "  Total RSS Memory:   avg %.1f MB (latest: %.1f MB)", totalRSS.reduce(0, +) / count,
            totalRSS.last ?? 0))
}
print("============================================================")
