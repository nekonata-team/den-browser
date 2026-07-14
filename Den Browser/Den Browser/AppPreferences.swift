import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    static let schemaVersion = 1
    static let defaultHintAlphabet = "asdfghjkl"

    private(set) var sheetNavigationEnabled: Bool
    private(set) var sheetNavigationHintAlphabet: String
    private(set) var sheetNavigationIgnoredHosts: [String]

    @ObservationIgnored private let defaults: UserDefaults

    private static let schemaVersionKey = "preferences.schemaVersion"
    private static let enabledKey = "features.vim-style-sheet-navigation.enabled"
    private static let hintAlphabetKey = "features.vim-style-sheet-navigation.hint-alphabet"
    private static let ignoredHostsKey = "features.vim-style-sheet-navigation.ignored-hosts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.set(Self.schemaVersion, forKey: Self.schemaVersionKey)
        sheetNavigationEnabled = defaults.bool(forKey: Self.enabledKey)
        sheetNavigationHintAlphabet =
            SheetNavigationManager.normalizeHintAlphabet(defaults.string(forKey: Self.hintAlphabetKey) ?? "")
            ?? Self.defaultHintAlphabet
        sheetNavigationIgnoredHosts = defaults.stringArray(forKey: Self.ignoredHostsKey) ?? []
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
}
