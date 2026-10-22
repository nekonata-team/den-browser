public import DenDomain

@MainActor
public struct WebSettingsModel {
    private let readSearchEngine: () -> SearchEngine
    public var searchEngine: SearchEngine { readSearchEngine() }
    private let readAutomaticPIPOnDeskSwitch: () -> Bool
    public var automaticPIPOnDeskSwitch: Bool { readAutomaticPIPOnDeskSwitch() }
    private let readUBOLiteEnabled: () -> Bool
    public var uBOLiteEnabled: Bool { readUBOLiteEnabled() }
    private let readIsInstalled: () -> Bool
    public var isInstalled: Bool { readIsInstalled() }
    private let readInstalledVersion: () -> String?
    public var installedVersion: String? { readInstalledVersion() }
    private let readIsBusy: () -> Bool
    public var isBusy: Bool { readIsBusy() }
    private let readErrorMessage: () -> String?
    public var errorMessage: String? { readErrorMessage() }
    public let setSearchEngine: (SearchEngine) -> Void
    public let setAutomaticPIPOnDeskSwitch: (Bool) -> Void
    public let setUBOLiteEnabled: (Bool) -> Void
    public let openOptions: () -> Void
    public let update: () async -> Void
    public let install: () async -> Void
    public let uninstall: () -> Void

    public init(
        searchEngine: @escaping () -> SearchEngine, automaticPIPOnDeskSwitch: @escaping () -> Bool,
        uBOLiteEnabled: @escaping () -> Bool, isInstalled: @escaping () -> Bool,
        installedVersion: @escaping () -> String?, isBusy: @escaping () -> Bool, errorMessage: @escaping () -> String?,
        setSearchEngine: @escaping (SearchEngine) -> Void, setAutomaticPIPOnDeskSwitch: @escaping (Bool) -> Void,
        setUBOLiteEnabled: @escaping (Bool) -> Void, openOptions: @escaping () -> Void,
        update: @escaping () async -> Void, install: @escaping () async -> Void, uninstall: @escaping () -> Void
    ) {
        self.readSearchEngine = searchEngine
        self.readAutomaticPIPOnDeskSwitch = automaticPIPOnDeskSwitch
        self.readUBOLiteEnabled = uBOLiteEnabled
        self.readIsInstalled = isInstalled
        self.readInstalledVersion = installedVersion
        self.readIsBusy = isBusy
        self.readErrorMessage = errorMessage
        self.setSearchEngine = setSearchEngine
        self.setAutomaticPIPOnDeskSwitch = setAutomaticPIPOnDeskSwitch
        self.setUBOLiteEnabled = setUBOLiteEnabled
        self.openOptions = openOptions
        self.update = update
        self.install = install
        self.uninstall = uninstall
    }
}
