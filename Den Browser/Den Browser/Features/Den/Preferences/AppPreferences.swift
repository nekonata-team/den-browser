import Foundation
import Observation

struct Essential: Codable, Equatable, Hashable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case id, name, key, input
    }

    let id: UUID
    var name: String
    var key: String
    var input: String

    init(id: UUID = UUID(), name: String, key: String, input: String) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = key == " " ? key : key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.input = input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            key: try container.decode(String.self, forKey: .key),
            input: try container.decode(String.self, forKey: .input))
    }

    var displayKey: String {
        key == " " ? "Space" : key
    }

    var isValid: Bool {
        !name.isEmpty
            && key.count == 1
            && key.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
            && !input.isEmpty
    }
}

enum SearchEngine: String, CaseIterable, Identifiable {
    case google
    case duckDuckGo
    case bing
    case brave
    case yahooJapan

    var id: Self { self }

    var label: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .brave: "Brave Search"
        case .yahooJapan: "Yahoo! JAPAN"
        }
    }

    var searchURL: String {
        switch self {
        case .google: "https://www.google.com/search"
        case .duckDuckGo: "https://duckduckgo.com/"
        case .bing: "https://www.bing.com/search"
        case .brave: "https://search.brave.com/search"
        case .yahooJapan: "https://search.yahoo.co.jp/search"
        }
    }
}

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

enum ExternalLinkDestination: String, CaseIterable, Identifiable {
    case drawerPreview = "drawer-preview"
    case focusedBoard = "focused-board"

    var id: Self { self }

    var label: String {
        switch self {
        case .drawerPreview: "Drawer Preview"
        case .focusedBoard: "Right of Focused Board"
        }
    }
}

@MainActor
@Observable
final class AppPreferences {
    static let schemaVersion = 1
    static let defaultDeskNumberBinding = ShortcutBinding(
        key: .character("1"), modifiers: [.command, .option])
    static let defaultSheetScale = 100
    static let defaultExternalLinkDestination: ExternalLinkDestination = .drawerPreview
    static let sheetScaleRange = 50...200

    private(set) var shortcutOverrides: [ConfigurableShortcut: ShortcutOverride]
    private(set) var deskNumberBinding: ShortcutBinding?
    private(set) var motionPreference: MotionPreference
    private(set) var uBOLiteEnabled: Bool
    private(set) var boardCentering: FocusedBoardCentering
    private(set) var externalLinkDestination: ExternalLinkDestination
    private(set) var sheetScale: Int
    private(set) var zellijPath: String
    private(set) var zmxPath: String
    private(set) var essentials: [Essential]
    private(set) var searchEngine: SearchEngine

    @ObservationIgnored private let defaults: UserDefaults

    private static let schemaVersionKey = "preferences.schema.version"
    private static let shortcutKeyPrefix = "preferences.shortcuts.actions."
    private static let deskNumberShortcutKey = "preferences.shortcuts.desk-number.binding"
    private static let deskNumberShortcutDisabledKey =
        "preferences.shortcuts.desk-number.disabled"
    private static let motionKey = "preferences.appearance.motion.mode"
    private static let uBOLiteEnabledKey = "preferences.content-blocking.ubolite.enabled"
    private static let boardCenteringKey = "preferences.appearance.board-centering.mode"
    private static let externalLinkDestinationKey = "preferences.external-links.destination"
    private static let sheetScaleKey = "preferences.appearance.sheet-scale.percent"
    private static let zellijPathKey = "preferences.terminal.zellij.executable-path"
    private static let zmxPathKey = "preferences.terminal.zmx.executable-path"
    private static let essentialsKey = "preferences.essentials.items"
    private static let searchEngineKey = "preferences.search.engine"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateIfNeeded(defaults)
        shortcutOverrides = [:]
        deskNumberBinding = Self.loadDeskNumberBinding(defaults)
        motionPreference =
            defaults.string(forKey: Self.motionKey).flatMap(MotionPreference.init(rawValue:))
            ?? .followSystem
        uBOLiteEnabled = defaults.bool(forKey: Self.uBOLiteEnabledKey)
        boardCentering =
            defaults.string(forKey: Self.boardCenteringKey).flatMap(FocusedBoardCentering.init(rawValue:))
            ?? .never
        externalLinkDestination =
            defaults.string(forKey: Self.externalLinkDestinationKey).flatMap(ExternalLinkDestination.init(rawValue:))
            ?? Self.defaultExternalLinkDestination
        sheetScale =
            Self.normalizedSheetScale(defaults.object(forKey: Self.sheetScaleKey) as? Int)
            ?? Self.defaultSheetScale
        zellijPath = defaults.string(forKey: Self.zellijPathKey) ?? ""
        zmxPath = defaults.string(forKey: Self.zmxPathKey) ?? ""
        essentials = Self.loadEssentials(defaults)
        searchEngine = defaults.string(forKey: Self.searchEngineKey).flatMap(SearchEngine.init(rawValue:)) ?? .google
        loadShortcutOverrides()
    }

    private static func migrateIfNeeded(_ defaults: UserDefaults) {
        var version = defaults.object(forKey: schemaVersionKey) as? Int ?? 0
        guard version <= schemaVersion else { return }

        while version < schemaVersion {
            switch version {
            case 0:
                // Version 1 records the current preference schema; missing values use defaults.
                break
            default:
                return
            }
            version += 1
            defaults.set(version, forKey: schemaVersionKey)
        }
    }

    func setSearchEngine(_ engine: SearchEngine) {
        searchEngine = engine
        defaults.set(engine.rawValue, forKey: Self.searchEngineKey)
    }

    func setUBOLiteEnabled(_ enabled: Bool) {
        uBOLiteEnabled = enabled
        defaults.set(enabled, forKey: Self.uBOLiteEnabledKey)
    }

    func setMotionPreference(_ preference: MotionPreference) {
        motionPreference = preference
        defaults.set(preference.rawValue, forKey: Self.motionKey)
    }

    func setBoardCentering(_ mode: FocusedBoardCentering) {
        boardCentering = mode
        defaults.set(mode.rawValue, forKey: Self.boardCenteringKey)
    }

    func setExternalLinkDestination(_ destination: ExternalLinkDestination) {
        externalLinkDestination = destination
        defaults.set(destination.rawValue, forKey: Self.externalLinkDestinationKey)
    }

    func setSheetScale(_ scale: Int) {
        guard Self.sheetScaleRange.contains(scale) else { return }
        sheetScale = scale
        defaults.set(scale, forKey: Self.sheetScaleKey)
    }

    func setZellijPath(_ path: String) {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        zellijPath = normalized
        defaults.set(normalized, forKey: Self.zellijPathKey)
    }

    func setZmxPath(_ path: String) {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        zmxPath = normalized
        defaults.set(normalized, forKey: Self.zmxPathKey)
    }

    @discardableResult
    func setEssentials(_ essentials: [Essential]) -> Bool {
        guard Self.areValidEssentials(essentials), let data = try? PropertyListEncoder().encode(essentials) else {
            return false
        }
        self.essentials = essentials
        if essentials.isEmpty {
            defaults.removeObject(forKey: Self.essentialsKey)
        } else {
            defaults.set(data, forKey: Self.essentialsKey)
        }
        return true
    }

    func shortcut(for action: ConfigurableShortcut) -> ShortcutBinding? {
        guard let override = shortcutOverrides[action] else { return action.defaultBinding }
        return override.binding
    }

    func setDeskNumberBinding(_ binding: ShortcutBinding) -> ShortcutValidationError? {
        guard binding.key.deskNumber != nil,
            binding.modifiers.hasPrimaryModifier
        else { return .invalid }

        if let conflict = ConfigurableShortcut.allCases.first(where: {
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

    func hasShortcutOverride(for action: ConfigurableShortcut) -> Bool {
        shortcutOverrides[action] != nil
    }

    func setShortcut(_ binding: ShortcutBinding, for action: ConfigurableShortcut) -> ShortcutValidationError? {
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

    func clearShortcut(for action: ConfigurableShortcut) {
        guard action.canBeUnassigned else { return }
        shortcutOverrides[action] = .unassigned
        persistShortcutOverride(for: action)
    }

    func resetShortcut(for action: ConfigurableShortcut) {
        shortcutOverrides.removeValue(forKey: action)
        defaults.removeObject(forKey: shortcutDefaultsKey(for: action))
    }

    func resetAllShortcuts() {
        for action in ConfigurableShortcut.allCases {
            defaults.removeObject(forKey: shortcutDefaultsKey(for: action))
        }
        shortcutOverrides.removeAll()
        resetDeskNumberBinding()
    }

    func conflictingAction(
        for binding: ShortcutBinding,
        excluding action: ConfigurableShortcut
    ) -> ConfigurableShortcut? {
        ConfigurableShortcut.allCases.first { candidate in
            candidate != action && shortcut(for: candidate) == binding
        }
    }

    private func loadShortcutOverrides() {
        for action in ConfigurableShortcut.allCases {
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

        for action in ConfigurableShortcut.allCases {
            guard let binding = shortcutOverrides[action]?.binding else { continue }
            if conflictingAction(for: binding, excluding: action) != nil {
                resetShortcut(for: action)
            }
        }
    }

    private func isValid(_ override: ShortcutOverride, for action: ConfigurableShortcut) -> Bool {
        switch override {
        case .assigned(let binding): binding.isRecordable
        case .unassigned: action.canBeUnassigned
        }
    }

    private func persistShortcutOverride(for action: ConfigurableShortcut) {
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

    private static func loadEssentials(_ defaults: UserDefaults) -> [Essential] {
        guard let data = defaults.data(forKey: essentialsKey),
            let essentials = try? PropertyListDecoder().decode([Essential].self, from: data),
            areValidEssentials(essentials)
        else {
            defaults.removeObject(forKey: essentialsKey)
            return []
        }
        return essentials
    }

    private static func areValidEssentials(_ essentials: [Essential]) -> Bool {
        var ids: Set<UUID> = []
        var keys: Set<String> = []
        return essentials.allSatisfy { essential in
            essential.isValid
                && ids.insert(essential.id).inserted
                && keys.insert(essential.key).inserted
        }
    }

    private func shortcutDefaultsKey(for action: ConfigurableShortcut) -> String {
        Self.shortcutKeyPrefix + action.rawValue
    }

    private static func normalizedSheetScale(_ scale: Int?) -> Int? {
        guard let scale, sheetScaleRange.contains(scale) else { return nil }
        return scale
    }
}
