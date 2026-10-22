public enum MotionPreference: String, CaseIterable, Identifiable {
    case followSystem = "follow-system"
    case standard
    case reduced

    public var id: Self { self }

    public var label: String {
        switch self {
        case .followSystem: "Follow System"
        case .standard: "Standard Motion"
        case .reduced: "Reduced Motion"
        }
    }
}
