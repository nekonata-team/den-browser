public nonisolated enum SearchEngine: String, CaseIterable, Identifiable, Sendable {
    case google
    case duckDuckGo
    case bing
    case brave
    case yahooJapan

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .brave: "Brave Search"
        case .yahooJapan: "Yahoo! JAPAN"
        }
    }

    public var searchURL: String {
        switch self {
        case .google: "https://www.google.com/search"
        case .duckDuckGo: "https://duckduckgo.com/"
        case .bing: "https://www.bing.com/search"
        case .brave: "https://search.brave.com/search"
        case .yahooJapan: "https://search.yahoo.co.jp/search"
        }
    }
}
