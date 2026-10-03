import AppKit
import WebKit

@MainActor
final class ProfileExtensionCoordinator {
    let installer: UBOLiteInstaller

    private let preferences: AppPreferences
    private let userContentController: WKUserContentController
    private let descriptors: [WebExtensionDescriptor]
    private let isEphemeral: Bool
    private var hosts: [UUID: MV3WebExtensionHost] = [:]

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

    func host(for profileID: UUID, websiteDataStore: WKWebsiteDataStore) -> MV3WebExtensionHost? {
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

    func setEnabled(_ enabled: Bool, stores: [(windowID: UUID, profileID: UUID?, store: DenStore)]) {
        preferences.setUBOLiteEnabled(enabled)
        updateStores(stores)
        if !enabled { disposeAllHosts() }
    }

    func focusWindow(profileID: UUID, windowID: UUID) {
        guard let host = hosts[profileID] else { return }
        host.focusWindow(host.window(for: windowID))
    }

    func presentPopup(
        profileID: UUID,
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

    func presentOptions(profileID: UUID, websiteDataStore: WKWebsiteDataStore) {
        guard let host = host(for: profileID, websiteDataStore: websiteDataStore) else { return }
        host.presentOptionsPage()
    }

    func closeWindow(profileID: UUID, windowID: UUID) {
        hosts[profileID]?.closeWindow(id: windowID)
    }

    func releaseProfile(_ profileID: UUID) {
        hosts.removeValue(forKey: profileID)?.dispose()
    }

    func updateUBOLite(stores: [(windowID: UUID, profileID: UUID?, store: DenStore)]) async -> Bool {
        let success = await installer.install()
        guard success, preferences.uBOLiteEnabled else { return success }
        disposeAllHosts()
        updateStores(stores)
        return true
    }

    private var effectiveDescriptors: [WebExtensionDescriptor] {
        if !descriptors.isEmpty { return descriptors }
        return installer.descriptor.map { [$0] } ?? []
    }

    private func updateStores(_ stores: [(windowID: UUID, profileID: UUID?, store: DenStore)]) {
        for (windowID, profileID, store) in stores {
            let host: MV3WebExtensionHost?
            if store.hasWebExtensionDemand, let profileID {
                host = self.host(for: profileID, websiteDataStore: store.websiteDataStore)
            } else {
                host = nil
            }
            store.updateWebExtensionHost(host, window: host?.window(for: windowID))
        }
    }

    private func disposeAllHosts() {
        let currentHosts = Array(hosts.values)
        hosts.removeAll()
        currentHosts.forEach { $0.dispose() }
    }
}
