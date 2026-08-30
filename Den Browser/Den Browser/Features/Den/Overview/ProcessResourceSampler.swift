import Darwin
import Foundation

struct ProcessResourceUsage: Equatable, Sendable {
    let cpuPercent: Double?
    let memoryBytes: UInt64
    let processCount: Int
}

struct ProcessResourceSample: Equatable, Sendable {
    let cpuTimeNanos: UInt64
    let memoryBytes: UInt64
    let processCount: Int
}

struct ProcessResourceSampler {
    private struct PreviousSample {
        let time: ContinuousClock.Instant
        let value: ProcessResourceSample
    }

    private var previous: [String: PreviousSample] = [:]

    mutating func usage(
        key: String,
        pids: [pid_t],
        now: ContinuousClock.Instant = .now
    ) -> ProcessResourceUsage? {
        guard let sample = Self.sample(pids: pids) else {
            previous[key] = nil
            return nil
        }

        let cpuPercent: Double?
        if let old = previous[key], sample.cpuTimeNanos >= old.value.cpuTimeNanos {
            let elapsed = old.time.duration(to: now)
            let elapsedNanos =
                Double(elapsed.components.seconds) * 1_000_000_000
                + Double(elapsed.components.attoseconds) / 1_000_000_000
            cpuPercent =
                elapsedNanos > 0
                ? Double(sample.cpuTimeNanos - old.value.cpuTimeNanos) / elapsedNanos * 100
                : nil
        } else {
            cpuPercent = nil
        }
        previous[key] = PreviousSample(time: now, value: sample)
        return ProcessResourceUsage(
            cpuPercent: cpuPercent,
            memoryBytes: sample.memoryBytes,
            processCount: sample.processCount)
    }

    static func processGroupPIDs(_ processGroupID: pid_t) -> [pid_t] {
        guard processGroupID > 0 else { return [] }
        let capacity = max(proc_listpgrppids(processGroupID, nil, 0), 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity))
        let count = pids.withUnsafeMutableBytes {
            proc_listpgrppids(processGroupID, $0.baseAddress, Int32($0.count))
        }
        guard count > 0 else { return [] }
        let pidCount = min(Int(count), pids.count)
        return Array(pids.prefix(pidCount)).filter { $0 > 0 }
    }

    private static func sample(pids: [pid_t]) -> ProcessResourceSample? {
        let values = Set(pids).compactMap(processUsage)
        guard !values.isEmpty else { return nil }
        return ProcessResourceSample(
            cpuTimeNanos: values.reduce(0) { $0 + $1.cpuTimeNanos },
            memoryBytes: values.reduce(0) { $0 + $1.memoryBytes },
            processCount: values.count)
    }

    private static func processUsage(pid: pid_t) -> ProcessResourceSample? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return ProcessResourceSample(
            cpuTimeNanos: info.ri_user_time + info.ri_system_time,
            memoryBytes: info.ri_phys_footprint,
            processCount: 1)
    }
}
