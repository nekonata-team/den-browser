import DenDomain
import Foundation
import SFSafeSymbols

public func recentItemSymbol(for item: RecentItem) -> SFSymbol {
    switch item {
    case .url(let url, _): url.isFileURL ? .document : .link
    case .search: .magnifyingglass
    case .terminal: BoardSymbol.terminal.symbol
    case .zellij: BoardSymbol.zellij.symbol
    case .zmx: BoardSymbol.zmx.symbol
    }
}
