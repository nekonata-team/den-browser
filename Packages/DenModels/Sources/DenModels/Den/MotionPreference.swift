public enum MotionPreference: String, CaseIterable, Identifiable {
    public static let standardSpatialDuration = 0.20

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
