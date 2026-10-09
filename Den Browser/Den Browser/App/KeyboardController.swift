import AppKit
import Foundation

@MainActor
final class KeyboardController {
    private var monitor: Any?
    private var windowModels: [ObjectIdentifier: DenWindowModel] = [:]

    func register(windowModel: DenWindowModel, for window: NSWindow) {
        windowModels[ObjectIdentifier(window)] = windowModel
    }

    func unregister(window: NSWindow) {
        windowModels.removeValue(forKey: ObjectIdentifier(window))
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
                let controller = profileManager?.controller(for: event.window),
                let window = event.window,
                let windowModel = self.windowModels[ObjectIdentifier(window)],
                let preferences
            else { return event }
            return Self.handle(
                event,
                controller: controller,
                windowModel: windowModel,
                preferences: preferences,
                openSettings: openSettings) ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        self.monitor = nil
        windowModels.removeAll()
    }

    @discardableResult
    static func handle(
        _ event: NSEvent,
        controller: DenController,
        windowModel: DenWindowModel,
        preferences: AppPreferences? = nil,
        openSettings: @MainActor () -> Void = {}
    ) -> Bool {
        let decision = decision(
            for: event,
            controller: controller,
            windowModel: windowModel,
            preferences: preferences)
        apply(decision, controller: controller, windowModel: windowModel, openSettings: openSettings)
        return !decision.isForwarded
    }

    static func decision(
        for event: NSEvent,
        controller: DenController,
        windowModel: DenWindowModel,
        preferences: AppPreferences? = nil
    ) -> InputDecision {
        let preferences = preferences ?? controller.preferences
        return KeyboardRouter.route(
            event: KeyEvent(event),
            context: InputContext(controller: controller, windowModel: windowModel, event: event),
            shortcuts: ShortcutConfiguration(preferences: preferences))
    }

    private static func apply(
        _ decision: InputDecision,
        controller: DenController,
        windowModel: DenWindowModel,
        openSettings: @MainActor () -> Void
    ) {
        guard case .perform(let action) = decision else { return }
        AppActionHandler.perform(action, controller: controller, windowModel: windowModel, openSettings: openSettings)
    }
}

private extension InputDecision {
    var isForwarded: Bool {
        if case .forward = self { return true }
        return false
    }
}
