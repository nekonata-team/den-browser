import Foundation
import os

enum PerformanceTrace {
    private static let signposter = OSSignposter(
        subsystem: "dev.nekonata.denbrowser",
        category: "Performance"
    )
    private static let startTime = ContinuousClock.now
    static let isEnabled: Bool = {
        ProcessInfo.processInfo.environment["DEN_BENCHMARK"] != nil
            || ProcessInfo.processInfo.arguments.contains("--benchmark")
    }()

    static func mark(_ label: String, category: String = "App") {
        guard isEnabled else { return }
        let elapsed = startTime.duration(to: .now)
        let elapsedMilliseconds =
            Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        let line = String(format: "[PERF:%@] +%.2fms: %@", category.uppercased(), elapsedMilliseconds, label)
        print(line)
        fflush(stdout)

        guard let path = ProcessInfo.processInfo.environment["DEN_BENCHMARK_TRACE_FILE"] else { return }
        let url = URL(fileURLWithPath: path)
        guard let file = try? FileHandle(forWritingTo: url) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: Data((line + "\n").utf8))
    }

    static func beginInterval(_ name: StaticString) -> OSSignpostIntervalState? {
        guard isEnabled else { return nil }
        return signposter.beginInterval(name)
    }

    static func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState?) {
        guard isEnabled, let state else { return }
        signposter.endInterval(name, state)
    }
}
