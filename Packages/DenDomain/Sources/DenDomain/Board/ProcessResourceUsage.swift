public struct ProcessResourceUsage: Equatable, Sendable {
    public let cpuPercent: Double?
    public let memoryBytes: UInt64
    public let processCount: Int
    public init(cpuPercent: Double?, memoryBytes: UInt64, processCount: Int) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.processCount = processCount
    }
}
