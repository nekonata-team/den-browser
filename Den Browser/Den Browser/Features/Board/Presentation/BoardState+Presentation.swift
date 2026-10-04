import SFSafeSymbols

extension BoardState {
    var systemSymbol: SFSymbol {
        switch kind {
        case .web: .globe
        case .inspection: .magnifyingglass
        case .terminal(.shell): .appleTerminal
        case .terminal(.zellij): .rectangle3Group
        case .terminal(.zmx): .appleTerminalOnRectangle
        case .tutorial: .book
        }
    }
}
