public enum FocusedBoardCentering: String, CaseIterable, Identifiable {
    case never
    case always
    case onOverflow = "on-overflow"

    public var id: Self { self }

    public var label: String {
        switch self {
        case .never: "Never"
        case .always: "Always"
        case .onOverflow: "When Overflowing"
        }
    }
}
