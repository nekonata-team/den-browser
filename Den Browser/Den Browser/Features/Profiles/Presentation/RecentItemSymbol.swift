import DenDomain
import SFSafeSymbols

func recentItemSymbol(for item: RecentItem) -> SFSymbol {
    switch item {
    case .url: .link
    case .search: .magnifyingglass
    case .terminal: .appleTerminal
    case .zellij: .rectangleSplit3x1
    case .zmx: .appleTerminalOnRectangle
    }
}
