import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

extension DenController {
    func openBoardFromClipboard(
        pasteboard: NSPasteboard? = nil, preferredWidth: Double? = nil, inDrawer: Bool = false
    ) {
        if case .rejected(let message) = storage.inputOpening.openClipboard(
            (pasteboard ?? self.pasteboard).string(forType: .string),
            context: inputOpeningContext(preferredWidth: preferredWidth, afterBoardID: focusedBoard?.id),
            inDrawer: inDrawer, notify: inputOpeningNotifications())
        {
            if let message { reportFeedback(message, severity: .warning) }
        }
    }
}
