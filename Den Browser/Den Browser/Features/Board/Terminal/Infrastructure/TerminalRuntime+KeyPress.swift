import DenIPCProtocol
import GhosttyTerminal

extension TerminalRuntime {
    func pressKey(_ chord: DenIPCProtocol.TerminalKeyPress) -> Bool {
        var modifiers: TerminalInputModifiers = []
        for modifier in chord.modifiers {
            switch modifier {
            case .ctrl: modifiers.insert(.ctrl)
            case .alt: modifiers.insert(.alt)
            case .shift: modifiers.insert(.shift)
            case .meta: modifiers.insert(.super_)
            }
        }
        let key: TerminalKey
        switch DenIPCProtocol.TerminalKeyPress.NamedKey(rawValue: chord.key) {
        case .enter: key = .enter
        case .escape: key = .escape
        case .tab: key = .tab
        case .backspace: key = .backspace
        case .delete: key = .delete
        case .home: key = .home
        case .end: key = .end
        case .pageup: key = .pageUp
        case .pagedown: key = .pageDown
        case .arrowup: key = .arrowUp
        case .arrowdown: key = .arrowDown
        case .arrowleft: key = .arrowLeft
        case .arrowright: key = .arrowRight
        case .space: key = .space
        case nil:
            guard let character = chord.key.first,
                let press = GhosttyTerminal.TerminalKeyPress(typing: character, modifiers: modifiers)
            else { return false }
            return terminalView.sendKey(press)
        }
        return terminalView.sendKey(key, modifiers: modifiers)
    }
}
