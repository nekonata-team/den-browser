import AppKit
import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class ProfileManager {
    private(set) var profiles: [ProfileState] = []
    private(set) var errorMessage: String?
    var clearBrowsingDataProfileID: UUID?
    var clearBrowsingDataWindowID: UUID?
    private(set) var windowAssignmentRevision = 0

    @ObservationIgnored private let persistence: ProfilePersistence
    @ObservationIgnored private var persistedProfiles: [UUID: PersistedProfile] = [:]
    var profileSaveCount: Int { persistence.profileSaveCount }
    @ObservationIgnored private var storages: [UUID: DenStorage] = [:]
    @ObservationIgnored private var stores: [UUID: DenStore] = [:]
    @ObservationIgnored private var storeProfileIDs: [UUID: UUID] = [:]
    @ObservationIgnored private var windows: [UUID: RegisteredWindow] = [:]
    @ObservationIgnored private var websiteDataStores: [UUID: WKWebsiteDataStore] = [:]
    @ObservationIgnored private var webExtensionHosts: [UUID: MV3WebExtensionHost] = [:]
    @ObservationIgnored private let sheetNavigation: SheetNavigationManager
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored let uboliteInstaller: UBOLiteInstaller
    @ObservationIgnored private let webExtensionDescriptors: [WebExtensionDescriptor]
    @ObservationIgnored private let removeDataStore: (UUID) async throws -> Void
    @ObservationIgnored private let removeWebsiteDataTypes: (WKWebsiteDataStore, Set<String>) async throws -> Void
    @ObservationIgnored private let initialProfile: PersistedProfile?
    @ObservationIgnored private let isEphemeral: Bool
    @ObservationIgnored private let websiteDataStore: (WebProfileStore) -> WKWebsiteDataStore
    let ipcSocketPath: String

    var personalProfileID: UUID {
        profiles.first(where: { $0.webProfileStore == .default })?.id
            ?? profiles.first?.id
            ?? UUID()
    }

    var isPrivateDen: Bool { isEphemeral }

    init(
        directoryURL: URL = ProfileManager.defaultDirectoryURL(),
        sheetNavigation: SheetNavigationManager,
        preferences: AppPreferences,
        uboliteInstaller: UBOLiteInstaller = UBOLiteInstaller(),
        removeDataStore: @escaping (UUID) async throws -> Void = ProfileManager.removeWebsiteDataStore,
        removeWebsiteDataTypes: @escaping (WKWebsiteDataStore, Set<String>) async throws -> Void = ProfileManager
            .removeWebsiteDataTypes,
        initialProfile: PersistedProfile? = nil,
        isEphemeral: Bool = false,
        websiteDataStore: @escaping (WebProfileStore) -> WKWebsiteDataStore,
        webExtensionDescriptors: [WebExtensionDescriptor] = [],
        ipcSocketPath: String = DenSocketPath.resolve(),
        quarantineFile: @escaping (URL, URL) throws -> Void = ProfilePersistence.moveFileToQuarantine
    ) {
        self.persistence = ProfilePersistence(
            directoryURL: directoryURL,
            isEphemeral: isEphemeral,
            quarantineFile: quarantineFile)
        self.sheetNavigation = sheetNavigation
        self.preferences = preferences
        self.uboliteInstaller = uboliteInstaller
        self.removeDataStore = removeDataStore
        self.removeWebsiteDataTypes = removeWebsiteDataTypes
        self.initialProfile = initialProfile
        self.isEphemeral = isEphemeral
        self.websiteDataStore = websiteDataStore
        self.webExtensionDescriptors = webExtensionDescriptors
        self.ipcSocketPath = ipcSocketPath
        load()
    }

    func profile(id: UUID) -> ProfileState? {
        profiles.first { $0.id == id }
    }

    func resolvedProfileID(_ requestedID: UUID) -> UUID {
        profile(id: requestedID) == nil ? personalProfileID : requestedID
    }

    func store(for profileID: UUID) -> DenStore? {
        store(for: ProfileWindowRoute(windowID: profileID, profileID: profileID))
    }

    func store(for route: ProfileWindowRoute) -> DenStore? {
        let profileID = resolvedProfileID(route.profileID)
        if let store = stores[route.windowID], storeProfileIDs[route.windowID] == profileID {
            return store
        }
        guard let storage = storage(for: profileID) else { return nil }
        let requestedDeskID = route.deskID ?? storage.state.focusedDeskID
        let presentedDeskID = availableDeskID(
            preferred: requestedDeskID,
            profileID: profileID,
            excludingWindowID: route.windowID)
        guard let presentedDeskID else { return nil }
        let webExtensionHost = webExtensionHost(for: profileID)
        let webExtensionWindow = webExtensionHost?.window(for: route.windowID)

        let store = DenStore(
            storage: storage,
            presentedDeskID: presentedDeskID,
            websiteDataStore: profileWebsiteDataStore(for: profileID),
            sheetNavigation: sheetNavigation,
            preferences: preferences,
            webExtensionHost: webExtensionHost,
            webExtensionWindow: webExtensionWindow,
            canPresentDesk: { [weak self] deskID in
                self?.canPresent(deskID, profileID: profileID, excludingWindowID: route.windowID) ?? true
            },
            onDeskPresentationRequest: { [weak self] deskID in
                self?.requestDeskPresentation(
                    deskID,
                    profileID: profileID,
                    windowID: route.windowID) ?? true
            },
            onWillResetDen: { [weak self] in
                self?.closeOtherWindows(profileID: profileID, excludingWindowID: route.windowID)
            },
            profileID: profileID,
            ipcSocketPath: ipcSocketPath)
        stores[route.windowID] = store
        storeProfileIDs[route.windowID] = profileID
        return store
    }

    @discardableResult
    func createProfile(name: String, color: ProfileColor) -> ProfileState? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let profile = ProfileState(
            id: UUID(), name: name, color: color, webProfileStore: .identified(UUID()))
        let persisted = PersistedProfile(profile: profile, den: .sample)
        profiles.append(profile)
        persistedProfiles[profile.id] = persisted
        do {
            try persistence.save(persisted)
            try persistence.saveIndex(profileIDs: profiles.map(\.id))
            return profile
        } catch {
            profiles.removeAll { $0.id == profile.id }
            persistedProfiles.removeValue(forKey: profile.id)
            try? persistence.removeProfileDocument(for: profile.id)
            reportSaveError(error)
            return nil
        }
    }

    func updateProfile(_ profileID: UUID, name: String? = nil, color: ProfileColor? = nil) -> Bool {
        guard
            let index = profiles.firstIndex(where: { $0.id == profileID }),
            var original = persistedProfiles[profileID]
        else { return false }
        refreshDenData(in: &original, for: profileID)
        persistedProfiles[profileID] = original
        if let name {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return false }
            profiles[index].name = name
        }
        if let color { profiles[index].color = color }
        persistedProfiles[profileID]?.profile = profiles[index]
        do {
            if let persisted = persistedProfiles[profileID] {
                try persistence.save(persisted)
                cancelPendingDeferredSave(for: profileID)
            }
            return true
        } catch {
            profiles[index] = original.profile
            persistedProfiles[profileID] = original
            reportSaveError(error)
            return false
        }
    }

    func deleteProfile(_ profileID: UUID) async -> Bool {
        guard
            let profile = profile(id: profileID),
            case .identified(let dataStoreID) = profile.webProfileStore
        else { return false }

        closeWindows(for: profileID)
        let hadDocument = persistence.profileDocumentExists(for: profileID)
        do {
            try await removeDataStore(dataStoreID)
            if hadDocument { try persistence.removeProfileDocument(for: profileID) }
            profiles.removeAll { $0.id == profileID }
            persistedProfiles.removeValue(forKey: profileID)
            cancelPendingDeferredSave(for: profileID)
            do {
                try persistence.saveIndex(profileIDs: profiles.map(\.id))
            } catch {
                reportSaveError(error)
            }
            return true
        } catch {
            errorMessage = "Could not delete Profile: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func clearBrowsingData(categories: Set<BrowsingDataCategory>, profileID: UUID) async -> Bool {
        guard let profile = profile(id: profileID) else { return false }
        let types = categories.websiteDataTypes
        guard !types.isEmpty else { return true }

        let store = websiteDataStore(profile.webProfileStore)
        do {
            try await removeWebsiteDataTypes(store, types)
            return true
        } catch {
            errorMessage = "Could not clear browsing data: \(error.localizedDescription)"
            return false
        }
    }

    func clearError() { errorMessage = nil }

    func setUBOLiteEnabled(_ enabled: Bool) {
        preferences.setUBOLiteEnabled(enabled)

        for (windowID, store) in stores {
            let profileID = storeProfileIDs[windowID]
            let host = enabled ? profileID.flatMap(webExtensionHost(for:)) : nil
            let extensionWindow = host?.window(for: windowID)
            store.updateWebExtensionHost(host, window: extensionWindow)
        }

        if !enabled {
            let hosts = Array(webExtensionHosts.values)
            webExtensionHosts.removeAll()
            hosts.forEach { $0.dispose() }
        }
    }

    func focusWebExtensionWindow(for route: ProfileWindowRoute) {
        guard let profileID = storeProfileIDs[route.windowID],
            let host = webExtensionHosts[profileID]
        else { return }
        host.focusWindow(host.window(for: route.windowID))
    }

    func presentUBOLitePopup(anchorView: NSView? = nil) {
        guard preferences.uBOLiteEnabled else { return }
        let target = extensionPresentationTarget()
        let profileID = target?.registration.profileID ?? personalProfileID
        guard let host = webExtensionHost(for: profileID) else { return }
        if let target {
            host.focusWindow(host.window(for: target.windowID))
        }
        host.presentActionPopup(
            from: anchorView?.window ?? NSApp.keyWindow,
            anchorView: anchorView)
    }

    func presentUBOLiteOptions() {
        guard preferences.uBOLiteEnabled else { return }
        let target = extensionPresentationTarget()
        let profileID = target?.registration.profileID ?? personalProfileID
        guard let host = webExtensionHost(for: profileID) else { return }
        host.presentOptionsPage()
    }

    @discardableResult
    func updateUBOLite() async -> Bool {
        let success = await uboliteInstaller.install()
        if success, preferences.uBOLiteEnabled {
            let hosts = Array(webExtensionHosts.values)
            webExtensionHosts.removeAll()
            hosts.forEach { $0.dispose() }

            for (windowID, store) in stores {
                let profileID = storeProfileIDs[windowID]
                let host = profileID.flatMap(webExtensionHost(for:))
                let extensionWindow = host?.window(for: windowID)
                store.updateWebExtensionHost(host, window: extensionWindow)
            }
        }
        return success
    }

    func register(window: NSWindow, for route: ProfileWindowRoute) {
        let profileID = resolvedProfileID(route.profileID)
        windows[route.windowID] = RegisteredWindow(profileID: profileID, window: window)
        focusWebExtensionWindow(for: route)
        windowAssignmentRevision &+= 1
    }

    func unregister(window: NSWindow, for route: ProfileWindowRoute) {
        guard let profileID = cleanupWindow(windowID: route.windowID, matchingWindow: window) else {
            return
        }
        releaseSharedResourcesIfUnused(for: profileID)
    }

    func store(for window: NSWindow?) -> DenStore? {
        guard let window else { return nil }
        let windowID = windows.first(where: { $0.value.window === window })?.key
        return windowID.flatMap { stores[$0] }
    }

    func activateWindow(for profileID: UUID) -> Bool {
        let profileID = resolvedProfileID(profileID)
        let window =
            NSApp.orderedWindows.first { candidate in
                windows.values.contains { $0.profileID == profileID && $0.window === candidate }
            } ?? windows.values.first { $0.profileID == profileID }?.window
        guard let window else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    var openWindowAction: ((ProfileWindowRoute) -> Void)?

    @discardableResult
    func openWindow(for profileID: UUID) -> Bool {
        if activateWindow(for: profileID) {
            return true
        }
        guard let openWindowAction else { return false }
        openWindowAction(ProfileWindowRoute(profileID: profileID))
        return true
    }

    func canOpenDeskInNewWindow(
        _ deskID: UUID,
        profileID: UUID,
        sourceWindowID: UUID
    ) -> Bool {
        _ = windowAssignmentRevision
        guard canPresent(deskID, profileID: profileID, excludingWindowID: sourceWindowID),
            let source = stores[sourceWindowID]
        else { return false }
        return source.presentedDeskID != deskID
            || availableReplacementDeskID(
                for: deskID,
                profileID: profileID,
                excludingWindowID: sourceWindowID) != nil
    }

    func isDeskPresentedInAnotherWindow(
        _ deskID: UUID,
        profileID: UUID,
        excludingWindowID: UUID
    ) -> Bool {
        _ = windowAssignmentRevision
        return !canPresent(deskID, profileID: profileID, excludingWindowID: excludingWindowID)
    }

    func routeForOpeningDesk(
        _ deskID: UUID,
        profileID: UUID,
        sourceWindowID: UUID
    ) -> ProfileWindowRoute? {
        guard canOpenDeskInNewWindow(deskID, profileID: profileID, sourceWindowID: sourceWindowID),
            let source = stores[sourceWindowID]
        else { return nil }
        if source.presentedDeskID == deskID {
            guard
                let replacementDeskID = availableReplacementDeskID(
                    for: deskID,
                    profileID: profileID,
                    excludingWindowID: sourceWindowID)
            else { return nil }
            source.focusDesk(replacementDeskID)
        }
        let route = ProfileWindowRoute(profileID: profileID, deskID: deskID)
        guard store(for: route)?.presentedDeskID == deskID else { return nil }
        return route
    }

    private func storage(for profileID: UUID) -> DenStorage? {
        if let storage = storages[profileID] { return storage }
        guard let persisted = persistedProfiles[profileID] else { return nil }
        let normalizedState = DenStore.normalizedPersistedState(persisted.den)
        let storage = DenStorage(
            state: normalizedState,
            deskPresets: persisted.deskPresets,
            recentItems: persisted.recentItems,
            onSave: { [weak self] den in self?.saveDen(den, for: profileID) ?? false },
            onDeferredSave: { [weak self] in self?.scheduleDeferredSave(for: profileID) },
            onDeskPresetsSave: { [weak self] presets in self?.saveDeskPresets(presets, for: profileID) ?? false },
            onRecentItemsSave: { [weak self] items in self?.saveRecentItems(items, for: profileID) ?? false })
        storages[profileID] = storage
        if normalizedState != persisted.den {
            _ = saveDen(normalizedState, for: profileID)
        }
        return storage
    }

    private func profileWebsiteDataStore(for profileID: UUID) -> WKWebsiteDataStore {
        if let store = websiteDataStores[profileID] { return store }
        let store = persistedProfiles[profileID].map { websiteDataStore($0.profile.webProfileStore) } ?? .default()
        websiteDataStores[profileID] = store
        return store
    }

    private func extensionPresentationTarget() -> (windowID: UUID, registration: RegisteredWindow)? {
        if let keyWindow = NSApp.keyWindow,
            let target = windows.first(where: { $0.value.window === keyWindow })
        {
            return (target.key, target.value)
        }
        for window in NSApp.orderedWindows {
            if let target = windows.first(where: { $0.value.window === window }) {
                return (target.key, target.value)
            }
        }
        return nil
    }

    func activeStore() -> DenStore? {
        if let target = extensionPresentationTarget() {
            return stores[target.windowID]
        }
        return stores.values.first
    }

    func activeProfileID() -> UUID? {
        if let target = extensionPresentationTarget() {
            return storeProfileIDs[target.windowID]
        }
        if let firstWindowID = stores.keys.first {
            return storeProfileIDs[firstWindowID]
        }
        return nil
    }

    func store(forProfileID profileID: UUID) -> DenStore? {
        if let target = extensionPresentationTarget(),
            storeProfileIDs[target.windowID] == profileID,
            let store = stores[target.windowID]
        {
            return store
        }
        for (windowID, pID) in storeProfileIDs where pID == profileID {
            if let store = stores[windowID] {
                return store
            }
        }
        return nil
    }

    func profileID(for storage: DenStorage) -> UUID? {
        for (profileID, candidateStorage) in storages where candidateStorage === storage {
            return profileID
        }
        return nil
    }

    func profileID(for store: DenStore) -> UUID? {
        for (windowID, storeInstance) in stores where storeInstance === store {
            return storeProfileIDs[windowID]
        }
        return profileID(for: store.storage)
    }

    func stores(for profileID: UUID) -> [DenStore] {
        storeProfileIDs.compactMap { windowID, pID in
            pID == profileID ? stores[windowID] : nil
        }
    }

    func store(for profileID: UUID, presentingDeskID: UUID?) -> DenStore? {
        let profileStores = stores(for: profileID)
        if let presentingDeskID,
            let presentingStore = profileStores.first(where: { $0.presentedDeskID == presentingDeskID })
        {
            return presentingStore
        }
        return store(forProfileID: profileID)
    }

    func hasWindow(for profileID: UUID) -> Bool {
        storeProfileIDs.values.contains(profileID)
    }

    var allStores: [DenStore] {
        Array(stores.values)
    }

    private var effectiveDescriptors: [WebExtensionDescriptor] {
        if !webExtensionDescriptors.isEmpty {
            return webExtensionDescriptors
        }
        return uboliteInstaller.descriptor.map { [$0] } ?? []
    }

    private func webExtensionHost(for profileID: UUID) -> MV3WebExtensionHost? {
        let descriptors = effectiveDescriptors
        guard preferences.uBOLiteEnabled, !descriptors.isEmpty else { return nil }
        if let host = webExtensionHosts[profileID] {
            return host
        }
        let host = MV3WebExtensionHost(
            profileID: profileID,
            websiteDataStore: profileWebsiteDataStore(for: profileID),
            userContentController: sheetNavigation.userContentController,
            descriptors: descriptors)
        webExtensionHosts[profileID] = host
        return host
    }

    private func canPresent(_ deskID: UUID, profileID: UUID, excludingWindowID: UUID) -> Bool {
        !stores.contains { windowID, store in
            windowID != excludingWindowID
                && storeProfileIDs[windowID] == profileID
                && store.presentedDeskID == deskID
        }
    }

    private func requestDeskPresentation(_ deskID: UUID, profileID: UUID, windowID: UUID) -> Bool {
        guard
            let ownerWindowID = stores.first(where: { candidateWindowID, store in
                candidateWindowID != windowID
                    && storeProfileIDs[candidateWindowID] == profileID
                    && store.presentedDeskID == deskID
            })?.key
        else { return true }
        windows[ownerWindowID]?.window?.makeKeyAndOrderFront(nil)
        return false
    }

    private func availableDeskID(
        preferred: UUID,
        profileID: UUID,
        excludingWindowID: UUID
    ) -> UUID? {
        guard let storage = storages[profileID] else { return nil }
        if storage.state.desks.contains(where: { $0.id == preferred }),
            canPresent(preferred, profileID: profileID, excludingWindowID: excludingWindowID)
        {
            return preferred
        }
        return storage.state.desks.first {
            canPresent($0.id, profileID: profileID, excludingWindowID: excludingWindowID)
        }?.id
    }

    private func availableReplacementDeskID(
        for deskID: UUID,
        profileID: UUID,
        excludingWindowID: UUID
    ) -> UUID? {
        guard let desks = storages[profileID]?.state.desks,
            let currentIndex = desks.firstIndex(where: { $0.id == deskID })
        else { return nil }
        let orderedCandidates = desks[(currentIndex + 1)...] + desks[..<currentIndex]
        return orderedCandidates.first {
            $0.id != deskID
                && canPresent($0.id, profileID: profileID, excludingWindowID: excludingWindowID)
        }?.id
    }

    @discardableResult
    private func cleanupWindow(
        windowID: UUID,
        matchingWindow: NSWindow? = nil,
        closeNativeWindow: Bool = false
    ) -> UUID? {
        if let matchingWindow, windows[windowID]?.window !== matchingWindow {
            return nil
        }
        let registration = windows.removeValue(forKey: windowID)
        stores.removeValue(forKey: windowID)?.releaseWindowResources()
        let profileID = storeProfileIDs.removeValue(forKey: windowID) ?? registration?.profileID
        if let profileID {
            webExtensionHosts[profileID]?.closeWindow(id: windowID)
        }
        if closeNativeWindow {
            registration?.window?.close()
        }
        windowAssignmentRevision &+= 1
        return profileID
    }

    private func releaseSharedResourcesIfUnused(for profileID: UUID) {
        let profileID = resolvedProfileID(profileID)
        guard !storeProfileIDs.values.contains(profileID),
            !windows.values.contains(where: { $0.profileID == profileID })
        else { return }
        if let storage = storages.removeValue(forKey: profileID) {
            releaseRuntimes(storage)
        }
        websiteDataStores.removeValue(forKey: profileID)
        webExtensionHosts.removeValue(forKey: profileID)?.dispose()
    }

    private func closeWindows(for profileID: UUID, excludingWindowID: UUID? = nil) {
        var targetWindowIDs = Set<UUID>()
        for (windowID, reg) in windows where reg.profileID == profileID {
            targetWindowIDs.insert(windowID)
        }
        for (windowID, pID) in storeProfileIDs where pID == profileID {
            targetWindowIDs.insert(windowID)
        }
        if let excludingWindowID {
            targetWindowIDs.remove(excludingWindowID)
        }
        for windowID in targetWindowIDs {
            cleanupWindow(windowID: windowID, closeNativeWindow: true)
        }
        releaseSharedResourcesIfUnused(for: profileID)
    }

    private func closeOtherWindows(profileID: UUID, excludingWindowID: UUID) {
        closeWindows(for: profileID, excludingWindowID: excludingWindowID)
    }

    private func releaseRuntimes(_ storage: DenStorage) {
        for runtime in storage.runtimes.values { runtime.dispose() }
        storage.runtimes.removeAll()
        for runtime in storage.terminalRuntimes.values { runtime.dispose() }
        storage.terminalRuntimes.removeAll()
        storage.runtimeOwners.removeAll()
    }

    private func load() {
        PerformanceTrace.mark("ProfileManager.load start", category: "Launch")
        let signpost = PerformanceTrace.beginInterval("ProfileManager.load")
        defer { PerformanceTrace.endInterval("ProfileManager.load", signpost) }
        if isEphemeral {
            let profile = initialProfile ?? Self.personalProfile()
            persistedProfiles = [profile.profile.id: profile]
            profiles = [profile.profile]
            return
        }
        do {
            try persistence.prepareDirectory()
        } catch {
            errorMessage = "Could not read Profiles: \(error.localizedDescription)"
            return
        }
        let result = persistence.load()
        var loadIssues = result.issues
        let canRewriteIndex = result.canRewriteIndex
        var loaded = result.profiles
        guard result.canReadDirectory else {
            errorMessage = loadIssues.joined(separator: "\n\n")
            return
        }
        PerformanceTrace.mark("ProfileManager.scanProfiles finished (\(loaded.count) found)", category: "Launch")

        var newPersonalProfile: PersistedProfile?
        if !loaded.contains(where: { $0.profile.webProfileStore == .default }) {
            let personalProfile = initialProfile ?? Self.personalProfile()
            loaded.insert(personalProfile, at: 0)
            newPersonalProfile = personalProfile
        }
        loaded = deduplicated(loaded)
        persistedProfiles = Dictionary(uniqueKeysWithValues: loaded.map { ($0.profile.id, $0) })
        profiles = loaded.map(\.profile)
        if let newPersonalProfile {
            do {
                try persistence.save(newPersonalProfile)
            } catch {
                loadIssues.append("Could not save the new Personal Profile: \(error.localizedDescription)")
            }
        }
        if canRewriteIndex {
            do {
                try persistence.saveIndex(profileIDs: profiles.map(\.id))
            } catch {
                loadIssues.append("Could not save the Profile index: \(error.localizedDescription)")
            }
        }
        if !loadIssues.isEmpty {
            errorMessage = loadIssues.joined(separator: "\n\n")
        }
        PerformanceTrace.mark("ProfileManager.load completed (\(profiles.count) profiles loaded)", category: "Launch")
    }

    private func deduplicated(_ profiles: [PersistedProfile]) -> [PersistedProfile] {
        var ids: Set<UUID> = []
        var hasDefault = false
        return profiles.filter {
            guard ids.insert($0.profile.id).inserted else { return false }
            if $0.profile.webProfileStore == .default {
                guard !hasDefault else { return false }
                hasDefault = true
            }
            return true
        }
    }

    @discardableResult
    private func saveDen(_ den: DenState, for profileID: UUID) -> Bool {
        guard var persisted = persistedProfiles[profileID] else { return false }
        persisted.den = den
        if let storage = storages[profileID] {
            persisted.deskPresets = storage.deskPresets
            persisted.recentItems = storage.recentItems
        }
        persistedProfiles[profileID] = persisted
        do {
            try persistence.save(persisted)
            cancelPendingDeferredSave(for: profileID)
            return true
        } catch {
            reportSaveError(error)
            return false
        }
    }

    @discardableResult
    private func saveDeskPresets(_ deskPresets: [PersonalDeskPreset], for profileID: UUID) -> Bool {
        guard var persisted = persistedProfiles[profileID] else { return false }
        refreshDenData(in: &persisted, for: profileID)
        persisted.deskPresets = deskPresets
        persistedProfiles[profileID] = persisted
        do {
            try persistence.save(persisted)
            cancelPendingDeferredSave(for: profileID)
            return true
        } catch {
            reportSaveError(error)
            return false
        }
    }

    @discardableResult
    private func saveRecentItems(_ recentItems: [RecentItem], for profileID: UUID) -> Bool {
        guard var persisted = persistedProfiles[profileID] else { return false }
        refreshDenData(in: &persisted, for: profileID)
        persisted.recentItems = recentItems
        persistedProfiles[profileID] = persisted
        do {
            try persistence.save(persisted)
            cancelPendingDeferredSave(for: profileID)
            return true
        } catch {
            reportSaveError(error)
            return false
        }
    }

    // The manager chooses each snapshot from DenStorage; persistence owns the timer and pending Task.
    func flushPendingDeferredSaves() {
        for profileID in persistence.pendingDeferredSaveIDs {
            guard let storage = storages[profileID] else {
                cancelPendingDeferredSave(for: profileID)
                continue
            }
            if storage.activeDrag != nil {
                guard let persisted = persistedProfiles[profileID] else { continue }
                do {
                    try persistence.save(persisted)
                    cancelPendingDeferredSave(for: profileID)
                } catch {
                    reportSaveError(error)
                }
            } else {
                _ = saveDen(storage.state, for: profileID)
            }
        }
    }

    private func scheduleDeferredSave(for profileID: UUID) {
        guard
            !isEphemeral,
            var persisted = persistedProfiles[profileID],
            storages[profileID] != nil
        else { return }
        refreshDenData(in: &persisted, for: profileID)
        persistedProfiles[profileID] = persisted
        persistence.scheduleDeferredSave(for: profileID) { [weak self] in
            guard let self, let storage = self.storages[profileID] else { return true }
            guard storage.activeDrag == nil else { return false }
            _ = self.saveDen(storage.state, for: profileID)
            return true
        }
    }

    private func cancelPendingDeferredSave(for profileID: UUID) {
        persistence.cancelPendingDeferredSave(for: profileID)
    }

    private func refreshDenData(in persisted: inout PersistedProfile, for profileID: UUID) {
        guard let storage = storages[profileID] else { return }
        if storage.activeDrag == nil {
            persisted.den = storage.state
        }
        persisted.deskPresets = storage.deskPresets
        persisted.recentItems = storage.recentItems
    }

    private func reportSaveError(_ error: Error) {
        errorMessage = "Could not save Profiles: \(error.localizedDescription)"
    }

    private static func personalProfile() -> PersistedProfile {
        PersistedProfile(
            profile: ProfileState(id: UUID(), name: "Personal", color: .blue, webProfileStore: .default),
            den: .sample)
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        ProfilePersistence.defaultDirectoryURL()
    }

    private static func removeWebsiteDataStore(_ identifier: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private static func removeWebsiteDataTypes(from store: WKWebsiteDataStore, types: Set<String>) async throws {
        let records = await withCheckedContinuation {
            (continuation: CheckedContinuation<[WKWebsiteDataRecord], Never>) in
            store.fetchDataRecords(ofTypes: types) { records in
                continuation.resume(returning: records)
            }
        }
        guard !records.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: types, for: records) {
                continuation.resume()
            }
        }
    }
}

private final class RegisteredWindow {
    let profileID: UUID
    weak var window: NSWindow?

    init(profileID: UUID, window: NSWindow) {
        self.profileID = profileID
        self.window = window
    }
}
