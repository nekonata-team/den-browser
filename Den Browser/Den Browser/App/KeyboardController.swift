import AppKit
import DenApplication
import DenPresentationModels
import Foundation
import SwiftUI

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
                let session = profileManager?.session(for: event.window),
                let window = event.window,
                let windowModel = self.windowModels[ObjectIdentifier(window)],
                let preferences
            else { return event }
            return Self.handle(
                event,
                session: session,
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
        session: ProfileWindowSession,
        windowModel: DenWindowModel,
        preferences: AppPreferences? = nil,
        openSettings: @MainActor () -> Void = {}
    ) -> Bool {
        let decision = decision(
            for: event,
            session: session,
            windowModel: windowModel,
            preferences: preferences)
        apply(decision, session: session, windowModel: windowModel, openSettings: openSettings)
        return !decision.isForwarded
    }

    static func decision(
        for event: NSEvent,
        session: ProfileWindowSession,
        windowModel: DenWindowModel,
        preferences: AppPreferences? = nil
    ) -> InputDecision {
        let preferences = preferences ?? session.configuration.preferences
        return KeyboardRouter.route(
            event: KeyEvent(event),
            context: InputContext(session: session, windowModel: windowModel, event: event),
            shortcuts: ShortcutConfiguration(preferences: preferences))
    }

    static func handleNotificationKeyPress(
        _ press: KeyPress,
        session: ProfileWindowSession,
        windowModel: DenWindowModel
    ) -> KeyPress.Result {
        guard windowModel.isNotificationListPresented else { return .ignored }
        let decision = KeyboardRouter.route(
            event: KeyEvent(notificationKeyPress: press),
            context: InputContext(session: session, windowModel: windowModel),
            shortcuts: ShortcutConfiguration(preferences: session.configuration.preferences))
        apply(decision, session: session, windowModel: windowModel, openSettings: {})
        return decision.isForwarded ? .ignored : .handled
    }

    private static func apply(
        _ decision: InputDecision,
        session: ProfileWindowSession,
        windowModel: DenWindowModel,
        openSettings: @MainActor () -> Void
    ) {
        guard case .perform(let action) = decision else { return }
        AppActionHandler.perform(action, session: session, windowModel: windowModel, openSettings: openSettings)
    }
}

private extension InputDecision {
    var isForwarded: Bool {
        if case .forward = self { return true }
        return false
    }
}
