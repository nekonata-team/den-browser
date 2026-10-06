import AppKit
import Foundation

@MainActor
final class KeyboardController {
    private var monitor: Any?
    private var viewModels: [ObjectIdentifier: DenViewModel] = [:]

    func register(viewModel: DenViewModel, for window: NSWindow) {
        viewModels[ObjectIdentifier(window)] = viewModel
    }

    func unregister(window: NSWindow) {
        viewModels.removeValue(forKey: ObjectIdentifier(window))
    }

    func start(
        profileManager: ProfileManager,
        preferences: AppPreferences,
        openSettings: @escaping @MainActor () -> Void
    ) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self, weak profileManager, weak preferences] event in
            guard let self,
                let store = profileManager?.store(for: event.window),
                let window = event.window,
                let viewModel = self.viewModels[ObjectIdentifier(window)],
                let preferences
            else { return event }
            return Self.handle(
                event,
                store: store,
                viewModel: viewModel,
                preferences: preferences,
                openSettings: openSettings) ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        self.monitor = nil
        viewModels.removeAll()
    }

    @discardableResult
    static func handle(
        _ event: NSEvent,
        store: DenStore,
        viewModel: DenViewModel,
        preferences: AppPreferences? = nil,
        openSettings: @MainActor () -> Void = {}
    ) -> Bool {
        let decision = decision(
            for: event,
            store: store,
            viewModel: viewModel,
            preferences: preferences)
        apply(decision, viewModel: viewModel, openSettings: openSettings)
        return !decision.isForwarded
    }

    static func decision(
        for event: NSEvent,
        store: DenStore,
        viewModel: DenViewModel,
        preferences: AppPreferences? = nil
    ) -> InputDecision {
        let preferences = preferences ?? store.preferences
        return KeyboardRouter.route(
            event: KeyEvent(event),
            context: InputContext(store: store, viewModel: viewModel, event: event),
            shortcuts: ShortcutConfiguration(preferences: preferences))
    }

    private static func apply(
        _ decision: InputDecision,
        viewModel: DenViewModel,
        openSettings: @MainActor () -> Void
    ) {
        guard case .perform(let action) = decision else { return }
        AppActionHandler.perform(action, viewModel: viewModel, openSettings: openSettings)
    }
}

private extension InputDecision {
    var isForwarded: Bool {
        if case .forward = self { return true }
        return false
    }
}
