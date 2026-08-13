import AppKit
import Foundation

@MainActor
final class KeyboardController {
    private var monitor: Any?

    func start(
        profileManager: ProfileManager,
        preferences: AppPreferences,
        openSettings: @escaping @MainActor () -> Void
    ) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak profileManager, weak preferences] event in
            guard let store = profileManager?.store(for: event.window), let preferences else { return event }
            return Self.handle(
                event,
                store: store,
                preferences: preferences,
                openSettings: openSettings) ? nil : event
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    @discardableResult
    static func handle(
        _ event: NSEvent,
        store: DenStore,
        preferences: AppPreferences? = nil,
        openSettings: @MainActor () -> Void = {}
    ) -> Bool {
        let decision = decision(for: event, store: store, preferences: preferences)
        apply(decision, store: store, openSettings: openSettings)
        return !decision.isForwarded
    }

    static func decision(
        for event: NSEvent,
        store: DenStore,
        preferences: AppPreferences? = nil
    ) -> InputDecision {
        let preferences = preferences ?? store.preferences
        return KeyboardRouter.route(
            event: KeyEvent(event),
            context: InputContext(store: store, event: event),
            shortcuts: ShortcutConfiguration(preferences: preferences))
    }

    private static func apply(
        _ decision: InputDecision,
        store: DenStore,
        openSettings: @MainActor () -> Void
    ) {
        guard case .perform(let action) = decision else { return }
        AppActionHandler.perform(action, store: store, openSettings: openSettings)
    }
}

private extension InputDecision {
    var isForwarded: Bool {
        if case .forward = self { return true }
        return false
    }
}
