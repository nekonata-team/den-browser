public nonisolated enum ExternalLinkDestination: String, CaseIterable, Identifiable, Sendable {
    case drawerPeek = "drawer-peek"
    case focusedBoard = "focused-board"

    public init?(storedValue: String) {
        if storedValue == "drawer-preview" {
            self = .drawerPeek
        } else {
            self.init(rawValue: storedValue)
        }
    }

    public var id: Self { self }

    public var label: String {
        switch self {
        case .drawerPeek: "Drawer Peek"
        case .focusedBoard: "Right of Focused Board"
        }
    }
}
