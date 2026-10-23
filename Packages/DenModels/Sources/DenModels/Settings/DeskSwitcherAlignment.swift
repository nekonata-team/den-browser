public enum DeskSwitcherAlignment: String, CaseIterable, Identifiable {
    case left
    case center

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .left: "Left"
        case .center: "Center"
        }
    }
}
