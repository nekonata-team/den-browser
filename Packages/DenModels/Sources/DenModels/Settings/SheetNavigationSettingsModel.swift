import Observation

@MainActor
@Observable
public final class SheetNavigationSettingsModel {
    @ObservationIgnored private let readEnabled: () -> Bool
    @ObservationIgnored private let readAlphabet: () -> String
    @ObservationIgnored private let readHosts: () -> [String]
    @ObservationIgnored private let writeEnabled: (Bool) -> Void
    @ObservationIgnored private let writeAlphabet: (String) -> Bool
    @ObservationIgnored private let writeHosts: (String) -> Bool
    @ObservationIgnored private let normalizeAlphabet: (String) -> String?
    @ObservationIgnored private let normalizeHosts: (String) -> [String]?

    public init(
        isEnabled: @escaping () -> Bool, hintAlphabet: @escaping () -> String,
        ignoredHosts: @escaping () -> [String], setEnabled: @escaping (Bool) -> Void,
        setHintAlphabet: @escaping (String) -> Bool, setIgnoredSites: @escaping (String) -> Bool,
        normalizeAlphabet: @escaping (String) -> String?, normalizeHosts: @escaping (String) -> [String]?
    ) {
        self.readEnabled = isEnabled
        self.readAlphabet = hintAlphabet
        self.readHosts = ignoredHosts
        self.writeEnabled = setEnabled
        self.writeAlphabet = setHintAlphabet
        self.writeHosts = setIgnoredSites
        self.normalizeAlphabet = normalizeAlphabet
        self.normalizeHosts = normalizeHosts
    }

    public var isEnabled: Bool { readEnabled() }
    public var hintAlphabet: String { readAlphabet() }
    public var ignoredHosts: [String] { readHosts() }
    public func setEnabled(_ enabled: Bool) { writeEnabled(enabled) }
    public func setHintAlphabet(_ alphabet: String) -> Bool { writeAlphabet(alphabet) }
    public func setIgnoredSites(_ sites: String) -> Bool { writeHosts(sites) }
    public func normalizeHintAlphabet(_ alphabet: String) -> String? { normalizeAlphabet(alphabet) }
    public func normalizeIgnoredSites(_ sites: String) -> [String]? { normalizeHosts(sites) }
}
