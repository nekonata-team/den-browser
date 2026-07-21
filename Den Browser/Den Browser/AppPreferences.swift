import Foundation
import Observation

enum MotionPreference: String, CaseIterable, Identifiable {
    case followSystem = "follow-system"
    case standard
    case reduced

    var id: Self { self }

    var label: String {
        switch self {
        case .followSystem: "Follow System"
        case .standard: "Standard Motion"
        case .reduced: "Reduced Motion"
        }
    }
}

@MainActor
@Observable
final class AppPreferences {
    static let schemaVersion = 1
    static let defaultDeskNumberBinding = ShortcutBinding(
        key: .character("1"), modifiers: [.command, .option])
    static let defaultHintAlphabet = "asdfghjkl"
    static let defaultSheetScale = 100
    static let sheetScaleRange = 50...200

    private(set) var sheetNavigationEnabled: Bool
    private(set) var sheetNavigationHintAlphabet: String
    private(set) var sheetNavigationIgnoredHosts: [String]
    private(set) var shortcutOverrides: [ShortcutAction: ShortcutOverride]
    private(set) var deskNumberBinding: ShortcutBinding?
    private(set) var motionPreference: MotionPreference
    private(set) var nativePictureInPictureEnabled: Bool
    private(set) var boardCentering: FocusedBoardCentering
    private(set) var sheetScale: Int

    @ObservationIgnored private let defaults: UserDefaults

    private static let schemaVersionKey = "preferences.schemaVersion"
    private static let enabledKey = "features.vim-style-sheet-navigation.enabled"
    private static let hintAlphabetKey = "features.vim-style-sheet-navigation.hint-alphabet"
    private static let ignoredHostsKey = "features.vim-style-sheet-navigation.ignored-hosts"
    private static let shortcutKeyPrefix = "shortcuts."
    private static let deskNumberShortcutKey = "shortcuts.desk-number"
    private static let deskNumberShortcutDisabledKey = "shortcuts.desk-number.disabled"
    private static let motionKey = "appearance.motion"
    private static let nativePictureInPictureEnabledKey =
        "features.native-picture-in-picture.enabled"
    private static let boardCenteringKey = "appearance.board-centering"
    private static let sheetScaleKey = "appearance.sheet-scale"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateIfNeeded(defaults)
        sheetNavigationEnabled = defaults.bool(forKey: Self.enabledKey)
        sheetNavigationHintAlphabet =
            SheetNavigationManager.normalizeHintAlphabet(defaults.string(forKey: Self.hintAlphabetKey) ?? "")
            ?? Self.defaultHintAlphabet
        sheetNavigationIgnoredHosts = defaults.stringArray(forKey: Self.ignoredHostsKey) ?? []
        shortcutOverrides = [:]
        deskNumberBinding = Self.loadDeskNumberBinding(defaults)
        motionPreference =
            defaults.string(forKey: Self.motionKey).flatMap(MotionPreference.init(rawValue:))
            ?? .followSystem
        nativePictureInPictureEnabled = defaults.bool(
            forKey: Self.nativePictureInPictureEnabledKey)
        boardCentering =
            defaults.string(forKey: Self.boardCenteringKey).flatMap(FocusedBoardCentering.init(rawValue:))
            ?? .never
        sheetScale =
            Self.normalizedSheetScale(defaults.object(forKey: Self.sheetScaleKey) as? Int)
            ?? Self.defaultSheetScale
        loadShortcutOverrides()
    }

    private static func migrateIfNeeded(_ defaults: UserDefaults) {
        var version = defaults.object(forKey: schemaVersionKey) as? Int ?? 0
        guard version <= schemaVersion else { return }

        while version < schemaVersion {
            switch version {
            case 0:
                // Version 1 adopts existing per-key preferences without changing them.
                break
            default:
                return
            }
            version += 1
            defaults.set(version, forKey: schemaVersionKey)
        }
    }

    func setSheetNavigationEnabled(_ enabled: Bool) {
        sheetNavigationEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    func setNativePictureInPictureEnabled(_ enabled: Bool) {
        nativePictureInPictureEnabled = enabled
        defaults.set(enabled, forKey: Self.nativePictureInPictureEnabledKey)
    }

    func setSheetNavigationHintAlphabet(_ alphabet: String) {
        sheetNavigationHintAlphabet = alphabet
        defaults.set(alphabet, forKey: Self.hintAlphabetKey)
    }

    func setSheetNavigationIgnoredHosts(_ hosts: [String]) {
        sheetNavigationIgnoredHosts = hosts
        defaults.set(hosts, forKey: Self.ignoredHostsKey)
    }

    func setMotionPreference(_ preference: MotionPreference) {
        motionPreference = preference
        defaults.set(preference.rawValue, forKey: Self.motionKey)
    }

    func setBoardCentering(_ mode: FocusedBoardCentering) {
        boardCentering = mode
        defaults.set(mode.rawValue, forKey: Self.boardCenteringKey)
    }

    func setSheetScale(_ scale: Int) {
        guard Self.sheetScaleRange.contains(scale) else { return }
        sheetScale = scale
        defaults.set(scale, forKey: Self.sheetScaleKey)
    }

    func shortcut(for action: ShortcutAction) -> ShortcutBinding? {
        guard let override = shortcutOverrides[action] else { return action.defaultBinding }
        return override.binding
    }

    func setDeskNumberBinding(_ binding: ShortcutBinding) -> ShortcutValidationError? {
        guard binding.key.deskNumber != nil,
            binding.modifiers.hasPrimaryModifier
        else { return .invalid }

        if let conflict = ShortcutAction.allCases.first(where: {
            guard let actionBinding = shortcut(for: $0) else { return false }
            return actionBinding.key.deskNumber != nil
                && actionBinding.modifiers == binding.modifiers
        }) {
            return .conflict(conflict)
        }

        if binding == Self.defaultDeskNumberBinding {
            resetDeskNumberBinding()
        } else {
            deskNumberBinding = binding
            defaults.removeObject(forKey: Self.deskNumberShortcutDisabledKey)
            persistDeskNumberBinding()
        }
        return nil
    }

    func hasDeskNumberBindingOverride() -> Bool {
        defaults.data(forKey: Self.deskNumberShortcutKey) != nil
            || defaults.bool(forKey: Self.deskNumberShortcutDisabledKey)
    }

    func resetDeskNumberBinding() {
        deskNumberBinding = Self.defaultDeskNumberBinding
        defaults.removeObject(forKey: Self.deskNumberShortcutKey)
        defaults.removeObject(forKey: Self.deskNumberShortcutDisabledKey)
    }

    func clearDeskNumberBinding() {
        deskNumberBinding = nil
        defaults.removeObject(forKey: Self.deskNumberShortcutKey)
        defaults.set(true, forKey: Self.deskNumberShortcutDisabledKey)
    }

    func hasShortcutOverride(for action: ShortcutAction) -> Bool {
        shortcutOverrides[action] != nil
    }

    func setShortcut(_ binding: ShortcutBinding, for action: ShortcutAction) -> ShortcutValidationError? {
        guard binding.isRecordable else { return .invalid }
        if let deskNumberBinding,
            binding.key.deskNumber != nil,
            binding.modifiers == deskNumberBinding.modifiers
        {
            return .conflictWithDeskNumber
        }
        if let conflict = conflictingAction(for: binding, excluding: action) {
            return .conflict(conflict)
        }

        if binding == action.defaultBinding {
            resetShortcut(for: action)
        } else {
            shortcutOverrides[action] = .assigned(binding)
            persistShortcutOverride(for: action)
        }
        return nil
    }

    func clearShortcut(for action: ShortcutAction) {
        guard action.canBeUnassigned else { return }
        shortcutOverrides[action] = .unassigned
        persistShortcutOverride(for: action)
    }

    func resetShortcut(for action: ShortcutAction) {
        shortcutOverrides.removeValue(forKey: action)
        defaults.removeObject(forKey: shortcutDefaultsKey(for: action))
    }

    func resetAllShortcuts() {
        for action in ShortcutAction.allCases {
            defaults.removeObject(forKey: shortcutDefaultsKey(for: action))
        }
        shortcutOverrides.removeAll()
        resetDeskNumberBinding()
    }

    func conflictingAction(for binding: ShortcutBinding, excluding action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { candidate in
            candidate != action && shortcut(for: candidate) == binding
        }
    }

    private func loadShortcutOverrides() {
        for action in ShortcutAction.allCases {
            let key = shortcutDefaultsKey(for: action)
            guard let data = defaults.data(forKey: key) else { continue }
            guard
                let override = try? PropertyListDecoder().decode(ShortcutOverride.self, from: data),
                isValid(override, for: action)
            else {
                defaults.removeObject(forKey: key)
                continue
            }
            shortcutOverrides[action] = override
        }

        for action in ShortcutAction.allCases {
            guard let binding = shortcutOverrides[action]?.binding else { continue }
            if conflictingAction(for: binding, excluding: action) != nil {
                resetShortcut(for: action)
            }
        }
    }

    private func isValid(_ override: ShortcutOverride, for action: ShortcutAction) -> Bool {
        switch override {
        case .assigned(let binding): binding.isRecordable
        case .unassigned: action.canBeUnassigned
        }
    }

    private func persistShortcutOverride(for action: ShortcutAction) {
        guard
            let override = shortcutOverrides[action],
            let data = try? PropertyListEncoder().encode(override)
        else { return }
        defaults.set(data, forKey: shortcutDefaultsKey(for: action))
    }

    private func persistDeskNumberBinding() {
        guard let deskNumberBinding,
            let data = try? PropertyListEncoder().encode(deskNumberBinding)
        else { return }
        defaults.set(data, forKey: Self.deskNumberShortcutKey)
    }

    private static func loadDeskNumberBinding(_ defaults: UserDefaults) -> ShortcutBinding? {
        if defaults.bool(forKey: deskNumberShortcutDisabledKey) {
            return nil
        }
        guard let data = defaults.data(forKey: deskNumberShortcutKey) else {
            return defaultDeskNumberBinding
        }
        guard
            let binding = try? PropertyListDecoder().decode(ShortcutBinding.self, from: data),
            binding.key.deskNumber != nil,
            binding.modifiers.hasPrimaryModifier
        else {
            defaults.removeObject(forKey: deskNumberShortcutKey)
            return defaultDeskNumberBinding
        }
        return binding
    }

    private func shortcutDefaultsKey(for action: ShortcutAction) -> String {
        Self.shortcutKeyPrefix + action.rawValue
    }

    private static func normalizedSheetScale(_ scale: Int?) -> Int? {
        guard let scale, sheetScaleRange.contains(scale) else { return nil }
        return scale
    }
}
