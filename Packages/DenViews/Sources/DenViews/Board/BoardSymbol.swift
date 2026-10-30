import DenDomain
import SFSafeSymbols

enum BoardSymbol {
    case web, inspection, terminal, zellij, zmx, tutorial

    var symbol: SFSymbol {
        switch self {
        case .web: .globe
        case .inspection: .magnifyingglass
        case .terminal: .appleTerminal
        case .zellij: .rectangle3Group
        case .zmx: .appleTerminalOnRectangle
        case .tutorial: .book
        }
    }
}

public func boardSymbol(for kind: BoardKind) -> SFSymbol {
    switch kind {
    case .web: BoardSymbol.web.symbol
    case .inspection: BoardSymbol.inspection.symbol
    case .terminal(.shell): BoardSymbol.terminal.symbol
    case .terminal(.zellij): BoardSymbol.zellij.symbol
    case .terminal(.zmx): BoardSymbol.zmx.symbol
    case .tutorial: BoardSymbol.tutorial.symbol
    }
}

func boardSymbol(for kind: DeskPresetBoardKind) -> SFSymbol {
    switch kind {
    case .web: BoardSymbol.web.symbol
    case .inspection: BoardSymbol.inspection.symbol
    case .terminal(.shell): BoardSymbol.terminal.symbol
    case .terminal(.zellij): BoardSymbol.zellij.symbol
    case .terminal(.zmx): BoardSymbol.zmx.symbol
    }
}
