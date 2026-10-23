import DenDomain
import Observation

public nonisolated enum DefaultBrowserStatus: Sendable {
    case loading
    case denBrowser
    case other(String)
    case mixed
    case unavailable

    public var label: String {
        switch self {
        case .loading: "Checking…"
        case .denBrowser: "Den Browser"
        case .other(let name): name
        case .mixed: "Different apps"
        case .unavailable: "Unavailable"
        }
    }

    public var isDenBrowser: Bool {
        if case .denBrowser = self { return true }
        return false
    }
}

@MainActor
@Observable
public final class DefaultBrowserSettingsModel {
    public private(set) var status: DefaultBrowserStatus = .loading
    public private(set) var isSettingDefault = false
    public var errorMessage: String?
    @ObservationIgnored private let readDestination: () -> ExternalLinkDestination
    @ObservationIgnored private let writeDestination: (ExternalLinkDestination) -> Void
    @ObservationIgnored private let loadStatus: () async -> DefaultBrowserStatus
    @ObservationIgnored private let setDefault: () async -> Void

    public init(
        destination: @escaping () -> ExternalLinkDestination,
        setDestination: @escaping (ExternalLinkDestination) -> Void,
        loadStatus: @escaping () async -> DefaultBrowserStatus, setDefault: @escaping () async -> Void
    ) {
        self.readDestination = destination
        self.writeDestination = setDestination
        self.loadStatus = loadStatus
        self.setDefault = setDefault
    }

    public var externalLinkDestination: ExternalLinkDestination { readDestination() }
    public func setExternalLinkDestination(_ value: ExternalLinkDestination) { writeDestination(value) }
    public func refreshStatus() async { status = await loadStatus() }

    public func makeDefaultBrowser() async {
        isSettingDefault = true
        await setDefault()
        await refreshStatus()
        isSettingDefault = false
        if !status.isDenBrowser {
            errorMessage = "macOS did not accept the change. You can set the default browser in System Settings."
        }
    }
}
