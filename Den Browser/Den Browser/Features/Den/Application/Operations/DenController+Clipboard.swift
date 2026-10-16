import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

extension DenController {
    func openBoardFromClipboard(
        pasteboard: NSPasteboard? = nil, preferredWidth: Double? = nil, inDrawer: Bool = false
    ) {
        let pasteboard = pasteboard ?? self.pasteboard
        guard
            let input = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !input.isEmpty
        else {
            reportFeedback("Clipboard is empty.", severity: .warning)
            return
        }

        if inDrawer {
            if let message = openInDrawer(input: input) { reportFeedback(message, severity: .warning) }
            return
        }

        onWindowEffect?(.openBoardResult(nil))
        if case .rejected(let message) = requestOpenBoard(
            input: input,
            preferredWidth: preferredWidth,
            afterBoardID: focusedBoard?.id)
        {
            reportFeedback(message ?? "Could not open board from clipboard.", severity: .warning)
        }
    }
}
