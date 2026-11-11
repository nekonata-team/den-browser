import Foundation

public nonisolated struct TerminalKeyPress: Equatable, Sendable {
    public enum NamedKey: String, Sendable {
        case enter, escape, tab, backspace, delete, home, end, pageup, pagedown
        case arrowup, arrowdown, arrowleft, arrowright, space
    }

    public enum Modifier: String, Hashable, Sendable {
        case ctrl, alt, shift, meta
    }

    public let key: String
    public let modifiers: Set<Modifier>

    public init(_ input: String) throws {
        let parts = input == "+" ? ["+"] : input.components(separatedBy: "+")
        let rawKey = parts.last ?? ""
        let key = rawKey.lowercased()
        guard
            NamedKey(rawValue: key) != nil || key == "plus"
                || (rawKey.utf8.count == 1 && rawKey.utf8.allSatisfy { (33...126).contains($0) })
        else {
            throw DenIPCInputError.usage(
                "Unsupported terminal key: \(input). Use Enter, Escape, Tab, arrows, navigation keys, or a printable ASCII key."
            )
        }
        var modifiers: Set<Modifier> = []
        for part in parts.dropLast() {
            let name = part.lowercased()
            let modifier = Modifier(rawValue: name == "cmd" ? "meta" : name)
            guard let modifier, modifiers.insert(modifier).inserted else {
                throw DenIPCInputError.usage(
                    "Invalid terminal modifiers: \(input). Use Ctrl, Alt, Shift, or Meta (Cmd), each at most once; use Plus for '+'."
                )
            }
        }
        self.key = key == "plus" ? "+" : key
        self.modifiers = modifiers
    }
}
