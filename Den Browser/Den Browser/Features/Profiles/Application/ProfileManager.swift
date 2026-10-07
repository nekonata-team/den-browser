import AppKit
import DenDomain
import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class ProfileManager {
    private(set) var profiles: [ProfileState] = []
    private(set) var errorMessage: String?
    var clearBrowsingDataProfileID: ProfileID?
    var clearBrowsingDataWindowID: UUID?
    private(set) var windowAssignmentRevision = 0

    @ObservationIgnored private let persistence: ProfilePersistence
    @ObservationIgnored private var persistedProfiles: [ProfileID: PersistedProfile] = [:]
    var profileSaveCount: Int { persistence.profileSaveCount }
    @ObservationIgnored private var storages: [ProfileID: DenStorage] = [:]
    @ObservationIgnored private var runtimeOwners: [ProfileID: [BoardID: DenStore]] = [:]
    @ObservationIgnored private let windowRegistry = ProfileWindowRegistry()
    @ObservationIgnored private var websiteDataStores: [ProfileID: WKWebsiteDataStore] = [:]
    @ObservationIgnored private let extensionCoordinator: ProfileExtensionCoordinator
    @ObservationIgnored private let sheetNavigation: SheetNavigationManager
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let removeDataStore: (UUID) async throws -> Void
    @ObservationIgnored private let removeWebsiteDataTypes: (WKWebsiteDataStore, Set<String>) async throws -> Void
    @ObservationIgnored private let initialProfile: PersistedProfile?
    @ObservationIgnored private let isEphemeral: Bool
    @ObservationIgnored private let websiteDataStore: (WebProfileStore) -> WKWebsiteDataStore
    let ipcSocketPath: String

    var uboliteInstaller: UBOLiteInstaller { extensionCoordinator.installer }

    var personalProfileID: ProfileID {
        profiles.first(where: { $0.webProfileStore == .default })?.id
            ?? profiles.first?.id
            ?? ProfileID()
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
        self.extensionCoordinator = ProfileExtensionCoordinator(
            installer: uboliteInstaller,
            preferences: preferences,
            userContentController: sheetNavigation.userContentController,
            descriptors: webExtensionDescriptors,
            isEphemeral: isEphemeral)
        self.removeDataStore = removeDataStore
        self.removeWebsiteDataTypes = removeWebsiteDataTypes
        self.initialProfile = initialProfile
        self.isEphemeral = isEphemeral
        self.websiteDataStore = websiteDataStore
        self.ipcSocketPath = ipcSocketPath
        load()
    }

    func profile(id: ProfileID) -> ProfileState? {
        profiles.first { $0.id == id }
    }

    func resolvedProfileID(_ requestedID: ProfileID) -> ProfileID {
        profile(id: requestedID) == nil ? personalProfileID : requestedID
    }

    func store(for profileID: ProfileID) -> DenStore? {
        store(for: ProfileWindowRoute(windowID: profileID.rawValue, profileID: profileID))
    }

    func store(for route: ProfileWindowRoute) -> DenStore? {
        let profileID = resolvedProfileID(route.profileID)
        if let store = windowRegistry.store(for: route.windowID),
            windowRegistry.profileID(for: route.windowID) == profileID
        {
            return store
        }
        guard let storage = storage(for: profileID) else { return nil }
        let requestedDeskID = route.deskID ?? storage.state.focusedDeskID
        let presentedDeskID = availableDeskID(
            preferred: requestedDeskID,
            profileID: profileID,
            excludingWindowID: route.windowID)
        guard let presentedDeskID else { return nil }
        let store = DenStore(
            storage: storage,
            presentedDeskID: presentedDeskID,
            websiteDataStore: profileWebsiteDataStore(for: profileID),
            sheetNavigation: sheetNavigation,
            preferences: preferences,
            requestWebExtensionContext: { [weak self] in
                guard let self,
                    let host = self.extensionCoordinator.host(
                        for: profileID,
                        websiteDataStore: self.profileWebsiteDataStore(for: profileID))
                else { return nil }
                return (host, host.window(for: route.windowID))
            },
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
        windowRegistry.setStore(store, windowID: route.windowID, profileID: profileID)
        return store
    }

    @discardableResult
    func createProfile(name: String, color: ProfileColor) -> ProfileState? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let profile = ProfileState(
            id: ProfileID(), name: name, color: color, webProfileStore: .identified(UUID()))
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

    func updateProfile(_ profileID: ProfileID, name: String? = nil, color: ProfileColor? = nil) -> Bool {
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

    func deleteProfile(_ profileID: ProfileID) async -> Bool {
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
    func clearBrowsingData(categories: Set<BrowsingDataCategory>, profileID: ProfileID) async -> Bool {
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
        extensionCoordinator.setEnabled(enabled, stores: windowRegistry.storeEntries())
    }

    func focusWebExtensionWindow(for route: ProfileWindowRoute) {
        guard let profileID = windowRegistry.profileID(for: route.windowID) else { return }
        extensionCoordinator.focusWindow(profileID: profileID, windowID: route.windowID)
    }

    func presentUBOLitePopup(anchorView: NSView? = nil) {
        guard extensionCoordinator.canUseExtensions else { return }
        let target = extensionPresentationTarget()
        let profileID = target?.registration.profileID ?? personalProfileID
        extensionCoordinator.presentPopup(
            profileID: profileID,
            windowID: target?.windowID,
            websiteDataStore: profileWebsiteDataStore(for: profileID),
            from: anchorView?.window ?? NSApp.keyWindow,
            anchorView: anchorView)
    }

    func presentUBOLiteOptions() {
        guard extensionCoordinator.canUseExtensions else { return }
        let target = extensionPresentationTarget()
        let profileID = target?.registration.profileID ?? personalProfileID
        extensionCoordinator.presentOptions(
            profileID: profileID,
            websiteDataStore: profileWebsiteDataStore(for: profileID))
    }

    @discardableResult
    func updateUBOLite() async -> Bool {
        await extensionCoordinator.updateUBOLite(stores: windowRegistry.storeEntries())
    }

    func register(window: NSWindow, for route: ProfileWindowRoute) {
        let profileID = resolvedProfileID(route.profileID)
        windowRegistry.register(window: window, profileID: profileID, windowID: route.windowID)
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
        return windowRegistry.store(for: window)
    }

    func activateWindow(for profileID: ProfileID) -> Bool {
        let profileID = resolvedProfileID(profileID)
        let window = windowRegistry.window(for: profileID)
        guard let window else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    var openWindowAction: ((ProfileWindowRoute) -> Void)? {
        get { windowRegistry.openWindowAction }
        set { windowRegistry.openWindowAction = newValue }
    }

    @discardableResult
    func openWindow(for profileID: ProfileID) -> Bool {
        if activateWindow(for: profileID) {
            return true
        }
        guard let openWindowAction else { return false }
        openWindowAction(ProfileWindowRoute(profileID: profileID))
        return true
    }

    func canOpenDeskInNewWindow(
        _ deskID: DeskID,
        profileID: ProfileID,
        sourceWindowID: UUID
    ) -> Bool {
        _ = windowAssignmentRevision
        guard canPresent(deskID, profileID: profileID, excludingWindowID: sourceWindowID),
            let source = windowRegistry.store(for: sourceWindowID)
        else { return false }
        return source.presentedDeskID != deskID
            || availableReplacementDeskID(
                for: deskID,
                profileID: profileID,
                excludingWindowID: sourceWindowID) != nil
    }

    func isDeskPresentedInAnotherWindow(
        _ deskID: DeskID,
        profileID: ProfileID,
        excludingWindowID: UUID
    ) -> Bool {
        _ = windowAssignmentRevision
        return !canPresent(deskID, profileID: profileID, excludingWindowID: excludingWindowID)
    }

    func routeForOpeningDesk(
        _ deskID: DeskID,
        profileID: ProfileID,
        sourceWindowID: UUID
    ) -> ProfileWindowRoute? {
        guard canOpenDeskInNewWindow(deskID, profileID: profileID, sourceWindowID: sourceWindowID),
            let source = windowRegistry.store(for: sourceWindowID)
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

    private func storage(for profileID: ProfileID) -> DenStorage? {
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
            onRecentItemsSave: { [weak self] items in self?.saveRecentItems(items, for: profileID) ?? false },
            onRuntimeOwnerChange: { [weak self] boardID, store in
                self?.setRuntimeOwner(store, boardID: boardID, profileID: profileID)
            })
        storages[profileID] = storage
        if normalizedState != persisted.den {
            _ = saveDen(normalizedState, for: profileID)
        }
        return storage
    }

    private func profileWebsiteDataStore(for profileID: ProfileID) -> WKWebsiteDataStore {
        if let store = websiteDataStores[profileID] { return store }
        let store = persistedProfiles[profileID].map { websiteDataStore($0.profile.webProfileStore) } ?? .default()
        websiteDataStores[profileID] = store
        return store
    }

    private func extensionPresentationTarget() -> (windowID: UUID, registration: RegisteredWindow)? {
        windowRegistry.presentationTarget()
    }

    func activeStore() -> DenStore? {
        windowRegistry.activeStore(preferredWindowID: extensionPresentationTarget()?.windowID)
    }

    func activeProfileID() -> ProfileID? {
        windowRegistry.activeProfileID(preferredWindowID: extensionPresentationTarget()?.windowID)
    }

    func store(forProfileID profileID: ProfileID) -> DenStore? {
        windowRegistry.store(forProfileID: profileID, preferredWindowID: extensionPresentationTarget()?.windowID)
    }

    func profileID(for storage: DenStorage) -> ProfileID? {
        for (profileID, candidateStorage) in storages where candidateStorage === storage {
            return profileID
        }
        return nil
    }

    func profileID(for store: DenStore) -> ProfileID? {
        windowRegistry.profileID(for: store) ?? profileID(for: store.storage)
    }

    func stores(for profileID: ProfileID) -> [DenStore] {
        windowRegistry.stores(for: profileID)
    }

    func store(for profileID: ProfileID, presentingDeskID: DeskID?) -> DenStore? {
        let profileStores = stores(for: profileID)
        if let presentingDeskID,
            let presentingStore = profileStores.first(where: { $0.presentedDeskID == presentingDeskID })
        {
            return presentingStore
        }
        return store(forProfileID: profileID)
    }

    func hasWindow(for profileID: ProfileID) -> Bool {
        windowRegistry.hasStore(for: profileID)
    }

    var allStores: [DenStore] {
        windowRegistry.allStores()
    }

    private func canPresent(_ deskID: DeskID, profileID: ProfileID, excludingWindowID: UUID) -> Bool {
        !windowRegistry.storeEntries().contains { entry in
            entry.windowID != excludingWindowID
                && entry.profileID == profileID
                && entry.store.presentedDeskID == deskID
        }
    }

    private func requestDeskPresentation(_ deskID: DeskID, profileID: ProfileID, windowID: UUID) -> Bool {
        guard
            let ownerWindowID = windowRegistry.storeEntries().first(where: { entry in
                entry.windowID != windowID
                    && entry.profileID == profileID
                    && entry.store.presentedDeskID == deskID
            })?.windowID
        else { return true }
        windowRegistry.registeredWindow(for: ownerWindowID)?.makeKeyAndOrderFront(nil)
        return false
    }

    private func availableDeskID(
        preferred: DeskID,
        profileID: ProfileID,
        excludingWindowID: UUID
    ) -> DeskID? {
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
        for deskID: DeskID,
        profileID: ProfileID,
        excludingWindowID: UUID
    ) -> DeskID? {
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
    ) -> ProfileID? {
        guard windowRegistry.matches(windowID: windowID, matchingWindow: matchingWindow) else {
            return nil
        }
        let removedWindow = windowRegistry.removeWindow(windowID: windowID)
        removedWindow.store?.releaseWindowResources()
        let profileID = removedWindow.profileID
        if let profileID {
            extensionCoordinator.closeWindow(profileID: profileID, windowID: windowID)
        }
        if closeNativeWindow {
            removedWindow.registration?.window?.close()
        }
        windowAssignmentRevision &+= 1
        return profileID
    }

    private func releaseSharedResourcesIfUnused(for profileID: ProfileID) {
        let profileID = resolvedProfileID(profileID)
        guard !windowRegistry.hasStore(for: profileID),
            !windowRegistry.hasWindow(for: profileID)
        else { return }
        if let storage = storages.removeValue(forKey: profileID) {
            releaseRuntimes(storage, profileID: profileID)
        }
        websiteDataStores.removeValue(forKey: profileID)
        extensionCoordinator.releaseProfile(profileID)
    }

    private func closeWindows(for profileID: ProfileID, excludingWindowID: UUID? = nil) {
        var targetWindowIDs = Set<UUID>()
        targetWindowIDs.formUnion(windowRegistry.windowIDs(for: profileID))
        targetWindowIDs.formUnion(windowRegistry.storeWindowIDs(for: profileID))
        if let excludingWindowID {
            targetWindowIDs.remove(excludingWindowID)
        }
        for windowID in targetWindowIDs {
            cleanupWindow(windowID: windowID, closeNativeWindow: true)
        }
        releaseSharedResourcesIfUnused(for: profileID)
    }

    private func closeOtherWindows(profileID: ProfileID, excludingWindowID: UUID) {
        closeWindows(for: profileID, excludingWindowID: excludingWindowID)
    }

    private func setRuntimeOwner(_ store: DenStore?, boardID: BoardID, profileID: ProfileID) {
        if let store {
            runtimeOwners[profileID, default: [:]][boardID] = store
        } else {
            runtimeOwners[profileID]?.removeValue(forKey: boardID)
            if runtimeOwners[profileID]?.isEmpty == true {
                runtimeOwners.removeValue(forKey: profileID)
            }
        }
    }

    private func releaseRuntimes(_ storage: DenStorage, profileID: ProfileID) {
        for runtime in storage.webRuntimes.values { runtime.dispose() }
        storage.webRuntimes.removeAll()
        for runtime in storage.terminalRuntimes.values { runtime.dispose() }
        storage.terminalRuntimes.removeAll()
        runtimeOwners.removeValue(forKey: profileID)
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
        var ids: Set<ProfileID> = []
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
    private func saveDen(_ den: DenState, for profileID: ProfileID) -> Bool {
        guard var persisted = persistedProfiles[profileID] else { return false }
        persisted.den = DenStore.normalizedPersistedState(den)
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
    private func saveDeskPresets(_ deskPresets: [PersonalDeskPreset], for profileID: ProfileID) -> Bool {
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
    private func saveRecentItems(_ recentItems: [RecentItem], for profileID: ProfileID) -> Bool {
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

    private func scheduleDeferredSave(for profileID: ProfileID) {
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

    private func cancelPendingDeferredSave(for profileID: ProfileID) {
        persistence.cancelPendingDeferredSave(for: profileID)
    }

    private func refreshDenData(in persisted: inout PersistedProfile, for profileID: ProfileID) {
        persisted.den = DenStore.normalizedPersistedState(persisted.den)
        guard let storage = storages[profileID] else { return }
        if storage.activeDrag == nil {
            persisted.den = DenStore.normalizedPersistedState(storage.state)
        }
        persisted.deskPresets = storage.deskPresets
        persisted.recentItems = storage.recentItems
    }

    private func reportSaveError(_ error: Error) {
        errorMessage = "Could not save Profiles: \(error.localizedDescription)"
    }

    private static func personalProfile() -> PersistedProfile {
        PersistedProfile(
            profile: ProfileState(id: ProfileID(), name: "Personal", color: .blue, webProfileStore: .default),
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
