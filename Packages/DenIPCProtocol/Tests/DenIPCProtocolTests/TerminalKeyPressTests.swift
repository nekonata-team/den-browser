import DenIPCProtocol
import Foundation
import Testing

struct TerminalKeyPressTests {
    @Test(arguments: [
        "Enter", "Escape", "Tab", "Backspace", "Delete", "Home", "End", "PageUp", "PageDown",
        "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Space", "a", "9", "[", "+", "Plus",
    ])
    func parsesSupportedKeys(input: String) throws {
        let chord = try TerminalKeyPress(input)
        #expect(chord.key == (input == "Plus" ? "+" : input.lowercased()))
        #expect(chord.modifiers.isEmpty)
    }

    @Test func parsesModifiersAndRoundTripsTheCommand() throws {
        let chord = try TerminalKeyPress("Ctrl+Alt+Shift+Cmd+C")
        #expect(chord.key == "c")
        #expect(chord.modifiers == [.ctrl, .alt, .shift, .meta])
        #expect(try TerminalKeyPress("Shift+Tab").key == "tab")
        #expect(try TerminalKeyPress("Ctrl+Plus").key == "+")
        let operation = DenIPCOperation.terminal(command: .press(key: "Ctrl+C"), target: .automatic)
        #expect(try JSONDecoder().decode(DenIPCOperation.self, from: JSONEncoder().encode(operation)) == operation)
    }

    @Test(arguments: [
        "", "Unknown", "日本語", "é", "K", "\n", "Ctrl+", "Ctrl++", "Ctrl+Ctrl+C", "Cmd+Meta+C", "Hyper+Enter",
    ])
    func rejectsInvalidKeysAndModifiers(input: String) {
        #expect(throws: DenIPCInputError.self) { try TerminalKeyPress(input) }
    }
}
