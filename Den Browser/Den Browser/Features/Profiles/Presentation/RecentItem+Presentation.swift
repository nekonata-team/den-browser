import SFSafeSymbols

extension RecentItem {
    var systemSymbol: SFSymbol {
        switch self {
        case .url: .link
        case .search: .magnifyingglass
        case .terminal: .appleTerminal
        case .zellij: .rectangleSplit3x1
        case .zmx: .appleTerminalOnRectangle
        }
    }
}
