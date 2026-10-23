public nonisolated enum DrawerStyle: String, CaseIterable, Identifiable, Sendable {
    case floating
    case bottom

    public var id: Self { self }

    public var label: String {
        switch self {
        case .floating: "Floating"
        case .bottom: "Bottom"
        }
    }
}
