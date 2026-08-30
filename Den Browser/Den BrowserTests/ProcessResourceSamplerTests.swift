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
}
