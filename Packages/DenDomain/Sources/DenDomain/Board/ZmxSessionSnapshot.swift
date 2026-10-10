public nonisolated struct ZmxSessionGroup: Identifiable, Equatable, Sendable {
    public let rootSessionName: String
    public let isRootActive: Bool
    public let childSessionNames: [String]

    public var id: String { rootSessionName }

    public init(rootSessionName: String, isRootActive: Bool, childSessionNames: [String]) {
        self.rootSessionName = rootSessionName
        self.isRootActive = isRootActive
        self.childSessionNames = childSessionNames
    }
}

public nonisolated struct ZmxSessionSnapshot: Sendable {
    public let groups: [ZmxSessionGroup]
    public let processNames: [String: String]

    public init(groups: [ZmxSessionGroup], processNames: [String: String]) {
        self.groups = groups
        self.processNames = processNames
    }
}
