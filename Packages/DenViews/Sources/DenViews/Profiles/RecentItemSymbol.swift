import DenDomain
import Foundation
import SFSafeSymbols

public func recentItemSymbol(for item: RecentItem) -> SFSymbol {
    switch item {
    case .url(let url, _): url.isFileURL ? .document : .link
    case .search: .magnifyingglass
    case .terminal: .appleTerminal
    case .zellij: .rectangleSplit3x1
    case .zmx: .appleTerminalOnRectangle
    }
}
