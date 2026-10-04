import Darwin
import Testing

@testable import Den_Browser

@MainActor
struct ProcessResourceSamplerTests {
    @Test func samplesCurrentProcessAndProcessGroup() {
        var sampler = ProcessResourceSampler()

        let usage = sampler.usage(key: "current", pids: [getpid()])
        let groupPIDs = ProcessResourceSampler.processGroupPIDs(getpgrp())

        #expect(usage?.cpuPercent == nil)
        #expect(usage?.memoryBytes ?? 0 > 0)
        #expect(usage?.processCount == 1)
        #expect(groupPIDs.contains(getpid()))
        #expect(ProcessResourceSampler.processGroupPIDs(0).isEmpty)
        #expect(ProcessResourceSampler.processGroupPIDs(-1).isEmpty)
    }

    @Test func resetsCPUComparisonWhenProcessIDsChange() {
        var cpuTime: UInt64 = 100
        var sampler = ProcessResourceSampler { _ in
            defer { cpuTime += 100 }
            return ProcessResourceSample(cpuTimeNanos: cpuTime, memoryBytes: 1, processCount: 1)
        }
        let start = ContinuousClock.now

        let first = sampler.usage(key: "terminal", pids: [101], now: start)
        let changed = sampler.usage(
            key: "terminal", pids: [202], now: start.advanced(by: .seconds(1)))
        let same = sampler.usage(
            key: "terminal", pids: [202], now: start.advanced(by: .seconds(2)))

        #expect(first?.cpuPercent == nil)
        #expect(changed?.cpuPercent == nil)
        #expect(same?.cpuPercent != nil)
    }
}
