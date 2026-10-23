import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import WebKit

@MainActor
final class ProfileExtensionCoordinator {
    let installer: UBOLiteInstaller

    private let preferences: AppPreferences
    private let userContentController: WKUserContentController
    private let descriptors: [WebExtensionDescriptor]
    private let isEphemeral: Bool
    private var hosts: [ProfileID: MV3WebExtensionHost] = [:]

    init(
        installer: UBOLiteInstaller,
        preferences: AppPreferences,
        userContentController: WKUserContentController,
        descriptors: [WebExtensionDescriptor],
        isEphemeral: Bool
    ) {
        self.installer = installer
        self.preferences = preferences
        self.userContentController = userContentController
        self.descriptors = descriptors
        self.isEphemeral = isEphemeral
    }

    var canUseExtensions: Bool {
        preferences.uBOLiteEnabled && !effectiveDescriptors.isEmpty
    }

    func host(for profileID: ProfileID, websiteDataStore: WKWebsiteDataStore) -> MV3WebExtensionHost? {
        guard canUseExtensions else { return nil }
        if let host = hosts[profileID] { return host }
        let host = MV3WebExtensionHost(
            profileID: profileID,
            websiteDataStore: websiteDataStore,
            userContentController: userContentController,
            descriptors: effectiveDescriptors,
            isEphemeral: isEphemeral)
        hosts[profileID] = host
        return host
    }

    func setEnabled(
        _ enabled: Bool, sessions: [(windowID: UUID, profileID: ProfileID?, session: ProfileWindowSession)]
    ) {
        preferences.setUBOLiteEnabled(enabled)
        updateSessions(sessions)
        if !enabled { disposeAllHosts() }
    }

    func focusWindow(profileID: ProfileID, windowID: UUID) {
        guard let host = hosts[profileID] else { return }
        host.focusWindow(host.window(for: windowID))
    }

    func presentPopup(
        profileID: ProfileID,
        windowID: UUID?,
        websiteDataStore: WKWebsiteDataStore,
        from window: NSWindow?,
        anchorView: NSView?
    ) {
        guard let host = host(for: profileID, websiteDataStore: websiteDataStore) else { return }
        if let windowID {
            host.focusWindow(host.window(for: windowID))
        }
        host.presentActionPopup(from: window, anchorView: anchorView)
    }

    func presentOptions(profileID: ProfileID, websiteDataStore: WKWebsiteDataStore) {
        guard let host = host(for: profileID, websiteDataStore: websiteDataStore) else { return }
        host.presentOptionsPage()
    }

    func closeWindow(profileID: ProfileID, windowID: UUID) {
        hosts[profileID]?.closeWindow(id: windowID)
    }

    func releaseProfile(_ profileID: ProfileID) {
        hosts.removeValue(forKey: profileID)?.dispose()
    }

    func updateUBOLite(sessions: [(windowID: UUID, profileID: ProfileID?, session: ProfileWindowSession)]) async
        -> Bool
    {
        let success = await installer.install()
        guard success, preferences.uBOLiteEnabled else { return success }
        disposeAllHosts()
        updateSessions(sessions)
        return true
    }

    private var effectiveDescriptors: [WebExtensionDescriptor] {
        if !descriptors.isEmpty { return descriptors }
        return installer.descriptor.map { [$0] } ?? []
    }

    private func updateSessions(
        _ sessions: [(windowID: UUID, profileID: ProfileID?, session: ProfileWindowSession)]
    ) {
        for (windowID, profileID, session) in sessions {
            let host: MV3WebExtensionHost?
            if session.runtimes.hasWebExtensionDemand, let profileID {
                host = self.host(for: profileID, websiteDataStore: session.configuration.websiteDataStore)
            } else {
                host = nil
            }
            session.runtimes.updateWebExtensionHost(host, window: host?.window(for: windowID))
        }
    }

    private func disposeAllHosts() {
        let currentHosts = Array(hosts.values)
        hosts.removeAll()
        for host in currentHosts {
            host.dispose()
        }
    }
}
