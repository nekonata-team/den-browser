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
    static let defaultHintAlphabet = "asdfghjkl"

    private(set) var sheetNavigationEnabled: Bool
    private(set) var sheetNavigationHintAlphabet: String
    private(set) var sheetNavigationIgnoredHosts: [String]
    private(set) var shortcutOverrides: [ShortcutAction: ShortcutOverride]
    private(set) var motionPreference: MotionPreference

    @ObservationIgnored private let defaults: UserDefaults

    private static let schemaVersionKey = "preferences.schemaVersion"
    private static let enabledKey = "features.vim-style-sheet-navigation.enabled"
    private static let hintAlphabetKey = "features.vim-style-sheet-navigation.hint-alphabet"
    private static let ignoredHostsKey = "features.vim-style-sheet-navigation.ignored-hosts"
    private static let shortcutKeyPrefix = "shortcuts."
    private static let motionKey = "appearance.motion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.set(Self.schemaVersion, forKey: Self.schemaVersionKey)
        sheetNavigationEnabled = defaults.bool(forKey: Self.enabledKey)
        sheetNavigationHintAlphabet =
            SheetNavigationManager.normalizeHintAlphabet(defaults.string(forKey: Self.hintAlphabetKey) ?? "")
            ?? Self.defaultHintAlphabet
        sheetNavigationIgnoredHosts = defaults.stringArray(forKey: Self.ignoredHostsKey) ?? []
        shortcutOverrides = [:]
        motionPreference =
            defaults.string(forKey: Self.motionKey).flatMap(MotionPreference.init(rawValue:))
            ?? .followSystem
        loadShortcutOverrides()
    }

    func setSheetNavigationEnabled(_ enabled: Bool) {
        sheetNavigationEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
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

    func shortcut(for action: ShortcutAction) -> ShortcutBinding? {
        guard let override = shortcutOverrides[action] else { return action.defaultBinding }
        return override.binding
    }

    func hasShortcutOverride(for action: ShortcutAction) -> Bool {
        shortcutOverrides[action] != nil
    }

    func setShortcut(_ binding: ShortcutBinding, for action: ShortcutAction) -> ShortcutValidationError? {
        guard binding.isRecordable else { return .invalid }
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

    private func shortcutDefaultsKey(for action: ShortcutAction) -> String {
        Self.shortcutKeyPrefix + action.rawValue
    }
}
