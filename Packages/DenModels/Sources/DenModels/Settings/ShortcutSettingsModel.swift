import Foundation
import Observation

@MainActor
@Observable
public final class ShortcutSettingsModel {
    @ObservationIgnored private let readShortcutOverrides: () -> [ConfigurableShortcut: ShortcutOverride]
    @ObservationIgnored private let readDeskNumberBinding: () -> ShortcutBinding?
    @ObservationIgnored private let onShortcut: (ConfigurableShortcut) -> ShortcutBinding?
    @ObservationIgnored private let onSetShortcut: (ShortcutBinding, ConfigurableShortcut) -> ShortcutValidationError?
    @ObservationIgnored private let onHasShortcutOverride: (ConfigurableShortcut) -> Bool
    @ObservationIgnored private let onResetShortcut: (ConfigurableShortcut) -> Void
    @ObservationIgnored private let onClearShortcut: (ConfigurableShortcut) -> Void
    @ObservationIgnored private let onSetDeskNumberBinding: (ShortcutBinding) -> ShortcutValidationError?
    @ObservationIgnored private let onHasDeskNumberBindingOverride: () -> Bool
    @ObservationIgnored private let onResetDeskNumberBinding: () -> Void
    @ObservationIgnored private let onClearDeskNumberBinding: () -> Void
    @ObservationIgnored private let onResetAllShortcuts: () -> Void

    public init(
        shortcutOverrides: @escaping () -> [ConfigurableShortcut: ShortcutOverride],
        deskNumberBinding: @escaping () -> ShortcutBinding?,
        shortcut: @escaping (ConfigurableShortcut) -> ShortcutBinding?,
        setShortcut: @escaping (ShortcutBinding, ConfigurableShortcut) -> ShortcutValidationError?,
        hasShortcutOverride: @escaping (ConfigurableShortcut) -> Bool,
        resetShortcut: @escaping (ConfigurableShortcut) -> Void,
        clearShortcut: @escaping (ConfigurableShortcut) -> Void,
        setDeskNumberBinding: @escaping (ShortcutBinding) -> ShortcutValidationError?,
        hasDeskNumberBindingOverride: @escaping () -> Bool,
        resetDeskNumberBinding: @escaping () -> Void,
        clearDeskNumberBinding: @escaping () -> Void,
        resetAllShortcuts: @escaping () -> Void
    ) {
        self.readShortcutOverrides = shortcutOverrides
        self.readDeskNumberBinding = deskNumberBinding
        self.onShortcut = shortcut
        self.onSetShortcut = setShortcut
        self.onHasShortcutOverride = hasShortcutOverride
        self.onResetShortcut = resetShortcut
        self.onClearShortcut = clearShortcut
        self.onSetDeskNumberBinding = setDeskNumberBinding
        self.onHasDeskNumberBindingOverride = hasDeskNumberBindingOverride
        self.onResetDeskNumberBinding = resetDeskNumberBinding
        self.onClearDeskNumberBinding = clearDeskNumberBinding
        self.onResetAllShortcuts = resetAllShortcuts
    }

    public var shortcutOverrides: [ConfigurableShortcut: ShortcutOverride] { readShortcutOverrides() }
    public var deskNumberBinding: ShortcutBinding? { readDeskNumberBinding() }
    public func shortcut(for action: ConfigurableShortcut) -> ShortcutBinding? { onShortcut(action) }
    public func setShortcut(_ binding: ShortcutBinding, for action: ConfigurableShortcut) -> ShortcutValidationError? {
        onSetShortcut(binding, action)
    }
    public func hasShortcutOverride(for action: ConfigurableShortcut) -> Bool { onHasShortcutOverride(action) }
    public func resetShortcut(for action: ConfigurableShortcut) { onResetShortcut(action) }
    public func clearShortcut(for action: ConfigurableShortcut) { onClearShortcut(action) }
    public func setDeskNumberBinding(_ binding: ShortcutBinding) -> ShortcutValidationError? {
        onSetDeskNumberBinding(binding)
    }
    public func hasDeskNumberBindingOverride() -> Bool { onHasDeskNumberBindingOverride() }
    public func resetDeskNumberBinding() { onResetDeskNumberBinding() }
    public func clearDeskNumberBinding() { onClearDeskNumberBinding() }
    public func resetAllShortcuts() { onResetAllShortcuts() }
}
