public nonisolated enum ExternalLinkDestination: String, CaseIterable, Identifiable, Sendable {
    case drawerPreview = "drawer-preview"
    case focusedBoard = "focused-board"

    public var id: Self { self }

    public var label: String {
        switch self {
        case .drawerPreview: "Drawer Preview"
        case .focusedBoard: "Right of Focused Board"
        }
    }
}
