import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

@MainActor
final class InputOpeningActions {
    private let context: WindowNativeContext
    private let boardOpening: BoardOpeningActions
    private let drawer: DrawerActions
    private var storage: DenProfileResources { context.storage }
    private var preferences: AppPreferences { context.configuration.preferences }
    private var pasteboard: NSPasteboard { context.pasteboard }
    private var focusedBoard: BoardState? { context.focusedBoard }
    private var onWindowEffect: ((DenWindowEffect) -> Void)? { context.connection.onWindowEffect }

    init(context: WindowNativeContext, boardOpening: BoardOpeningActions, drawer: DrawerActions) {
        self.context = context
        self.boardOpening = boardOpening
        self.drawer = drawer
    }

    func openBoardFromClipboard(
        pasteboard: NSPasteboard? = nil, preferredWidth: Double? = nil, inDrawer: Bool = false
    ) {
        if case .rejected(let message) = storage.inputOpening.openClipboard(
            (pasteboard ?? self.pasteboard).string(forType: .string),
            context: boardOpening.inputOpeningContext(preferredWidth: preferredWidth, afterBoardID: focusedBoard?.id),
            inDrawer: inDrawer, notify: inputOpeningNotifications())
        {
            if let message { context.feedback.publish(message, severity: .warning) }
        }
    }

    func inputOpeningNotifications() -> (InputOpening.Notice) -> Void {
        { [self] notice in
            switch notice {
            case .willOpenBoard: onWindowEffect?(.openBoardResult(nil))
            case .board(let notice): boardOpening.boardCreationNotifications()(notice)
            case .drawer(let notice): drawer.drawerItemNotifications()(notice)
            case .keptInDrawer: context.feedback.publish("Kept in Drawer.", severity: .success)
            }
        }
    }

    func openInDrawer(input: String) -> String? {
        if case .rejected(let message) = storage.inputOpening.open(
            input, context: boardOpening.inputOpeningContext(), inDrawer: true, notify: inputOpeningNotifications())
        {
            return message
        }
        return nil
    }

    func handleExternalURL(_ url: URL) {
        let destination = preferences.externalLinkDestination
        let accepted = storage.inputOpening.openExternalURL(
            url, destination: destination, context: boardOpening.inputOpeningContext(afterBoardID: focusedBoard?.id),
            notify: inputOpeningNotifications())
        if !accepted, destination == .drawerPeek {
            context.feedback.publish("Only HTTP, HTTPS, and local file URLs are supported.", severity: .warning)
        }
    }
}
