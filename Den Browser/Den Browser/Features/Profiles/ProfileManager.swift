import AppKit
import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class ProfileManager {
    private(set) var profiles: [ProfileState] = []
    private(set) var errorMessage: String?
    var openProfilePanelProfileID: UUID?
    var openProfilePanelWindowID: UUID?
    var clearBrowsingDataProfileID: UUID?
    var clearBrowsingDataWindowID: UUID?
    private(set) var windowAssignmentRevision = 0

    @ObservationIgnored private let directoryURL: URL
    @ObservationIgnored private var persistedProfiles: [UUID: PersistedProfile] = [:]
    @ObservationIgnored private var storages: [UUID: DenStorage] = [:]
    @ObservationIgnored private var stores: [UUID: DenStore] = [:]
    @ObservationIgnored private var storeProfileIDs: [UUID: UUID] = [:]
    @ObservationIgnored private var windows: [UUID: RegisteredWindow] = [:]
    @ObservationIgnored private var websiteDataStores: [UUID: WKWebsiteDataStore] = [:]
    @ObservationIgnored private var webExtensionHosts: [UUID: MV3WebExtensionHost] = [:]
    @ObservationIgnored private let sheetNavigation: SheetNavigationManager
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let webExtensionDescriptors: [BundledWebExtensionDescriptor]
    @ObservationIgnored private let removeDataStore: (UUID) async throws -> Void
    @ObservationIgnored private let removeWebsiteDataTypes: (WKWebsiteDataStore, Set<String>) async throws -> Void
    @ObservationIgnored private let initialProfile: PersistedProfile?
    @ObservationIgnored private let websiteDataStore: (WebProfileStore) -> WKWebsiteDataStore

    var personalProfileID: UUID {
        profiles.first(where: { $0.webProfileStore == .default })?.id
            ?? profiles.first?.id
            ?? UUID()
    }

    init(
        directoryURL: URL = ProfileManager.defaultDirectoryURL(),
        sheetNavigation: SheetNavigationManager,
        preferences: AppPreferences = AppPreferences(),
        removeDataStore: @escaping (UUID) async throws -> Void = ProfileManager.removeWebsiteDataStore,
        removeWebsiteDataTypes: @escaping (WKWebsiteDataStore, Set<String>) async throws -> Void = ProfileManager
            .removeWebsiteDataTypes,
        initialProfile: PersistedProfile? = nil,
        websiteDataStore: ((WebProfileStore) -> WKWebsiteDataStore)? = nil,
        webExtensionDescriptors: [BundledWebExtensionDescriptor] = []
    ) {
        self.directoryURL = directoryURL
        self.sheetNavigation = sheetNavigation
        self.preferences = preferences
        self.removeDataStore = removeDataStore
        self.removeWebsiteDataTypes = removeWebsiteDataTypes
        self.initialProfile = initialProfile
        self.websiteDataStore = websiteDataStore ?? { $0.websiteDataStore }
        self.webExtensionDescriptors = webExtensionDescriptors
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
            })
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
            try save(persisted)
            try saveIndex()
            return profile
        } catch {
            profiles.removeAll { $0.id == profile.id }
            persistedProfiles.removeValue(forKey: profile.id)
            try? FileManager.default.removeItem(at: profileURL(for: profile.id))
            reportSaveError(error)
            return nil
        }
    }

    func updateProfile(_ profileID: UUID, name: String? = nil, color: ProfileColor? = nil) -> Bool {
        guard
            let index = profiles.firstIndex(where: { $0.id == profileID }),
            let original = persistedProfiles[profileID]
        else { return false }
        if let name {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return false }
            profiles[index].name = name
        }
        if let color { profiles[index].color = color }
        persistedProfiles[profileID]?.profile = profiles[index]
        do {
            if let persisted = persistedProfiles[profileID] { try save(persisted) }
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
        removeStores(for: profileID)
        if let storage = storages.removeValue(forKey: profileID) {
            releaseRuntimes(storage)
        }
        websiteDataStores.removeValue(forKey: profileID)
        webExtensionHosts.removeValue(forKey: profileID)?.dispose()
        let profileURL = profileURL(for: profileID)
        let hadDocument = FileManager.default.fileExists(atPath: profileURL.path)
        do {
            if hadDocument { try FileManager.default.removeItem(at: profileURL) }
            try await removeDataStore(dataStoreID)
            profiles.removeAll { $0.id == profileID }
            persistedProfiles.removeValue(forKey: profileID)
            do {
                try saveIndex()
            } catch {
                reportSaveError(error)
            }
            return true
        } catch {
            if hadDocument, let persisted = persistedProfiles[profileID] {
                do {
                    try save(persisted)
                } catch {
                    reportSaveError(error)
                    return false
                }
            }
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

    func register(window: NSWindow, for route: ProfileWindowRoute) {
        let profileID = resolvedProfileID(route.profileID)
        windows[route.windowID] = RegisteredWindow(profileID: profileID, window: window)
        focusWebExtensionWindow(for: route)
        windowAssignmentRevision &+= 1
    }

    func unregister(window: NSWindow, for route: ProfileWindowRoute) {
        guard windows[route.windowID]?.window === window else { return }
        windows.removeValue(forKey: route.windowID)
        stores.removeValue(forKey: route.windowID)?.releaseWindowResources()
        if let profileID = storeProfileIDs[route.windowID] {
            webExtensionHosts[profileID]?.closeWindow(id: route.windowID)
        }
        windowAssignmentRevision &+= 1
        let profileID = storeProfileIDs.removeValue(forKey: route.windowID) ?? resolvedProfileID(route.profileID)
        guard !storeProfileIDs.values.contains(profileID), let storage = storages.removeValue(forKey: profileID) else {
            return
        }
        releaseRuntimes(storage)
        websiteDataStores.removeValue(forKey: profileID)
        webExtensionHosts.removeValue(forKey: profileID)?.dispose()
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
            onSave: { [weak self] den in self?.saveDen(den, for: profileID) },
            onDeskPresetsSave: { [weak self] presets in self?.saveDeskPresets(presets, for: profileID) },
            onRecentItemsSave: { [weak self] items in self?.saveRecentItems(items, for: profileID) ?? false })
        storages[profileID] = storage
        if normalizedState != persisted.den {
            saveDen(normalizedState, for: profileID)
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

    private func webExtensionHost(for profileID: UUID) -> MV3WebExtensionHost? {
        guard preferences.uBOLiteEnabled, !webExtensionDescriptors.isEmpty else { return nil }
        if let host = webExtensionHosts[profileID] {
            return host
        }
        let host = MV3WebExtensionHost(
            profileID: profileID,
            websiteDataStore: profileWebsiteDataStore(for: profileID),
            userContentController: sheetNavigation.userContentController,
            descriptors: webExtensionDescriptors)
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

    private func closeWindows(for profileID: UUID) {
        let matchingWindows = windows.filter { $0.value.profileID == profileID }
        for (windowID, registration) in matchingWindows {
            windows.removeValue(forKey: windowID)
            stores.removeValue(forKey: windowID)?.releaseWindowResources()
            webExtensionHosts[profileID]?.closeWindow(id: windowID)
            storeProfileIDs.removeValue(forKey: windowID)
            registration.window?.close()
        }
    }

    private func closeOtherWindows(profileID: UUID, excludingWindowID: UUID) {
        let matchingWindows = windows.filter {
            $0.key != excludingWindowID && $0.value.profileID == profileID
        }
        for (windowID, registration) in matchingWindows {
            windows.removeValue(forKey: windowID)
            stores.removeValue(forKey: windowID)?.releaseWindowResources()
            webExtensionHosts[profileID]?.closeWindow(id: windowID)
            storeProfileIDs.removeValue(forKey: windowID)
            registration.window?.close()
        }
        let remainingWindowIDs = storeProfileIDs.compactMap {
            $0.key != excludingWindowID && $0.value == profileID ? $0.key : nil
        }
        for windowID in remainingWindowIDs {
            stores.removeValue(forKey: windowID)?.releaseWindowResources()
            webExtensionHosts[profileID]?.closeWindow(id: windowID)
            storeProfileIDs.removeValue(forKey: windowID)
        }
    }

    private func removeStores(for profileID: UUID) {
        let windowIDs = storeProfileIDs.compactMap { $0.value == profileID ? $0.key : nil }
        for windowID in windowIDs {
            let profileID = storeProfileIDs[windowID]
            stores.removeValue(forKey: windowID)?.releaseWindowResources()
            if let profileID {
                webExtensionHosts[profileID]?.closeWindow(id: windowID)
            }
            storeProfileIDs.removeValue(forKey: windowID)
        }
    }

    private func releaseRuntimes(_ storage: DenStorage) {
        for runtime in storage.runtimes.values { runtime.dispose() }
        storage.runtimes.removeAll()
        for runtime in storage.terminalRuntimes.values { runtime.dispose() }
        storage.terminalRuntimes.removeAll()
        storage.runtimeOwners.removeAll()
    }

    private func load() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var loaded = scanProfiles()
        let indexURL = directoryURL.appending(path: "profile-index.json")
        if let index = decode(ProfileIndex.self, from: indexURL) {
            let byID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.profile.id, $0) })
            loaded =
                index.profileIDs.compactMap { byID[$0] }
                + loaded.filter { !index.profileIDs.contains($0.profile.id) }
        } else if FileManager.default.fileExists(atPath: indexURL.path) {
            quarantine(indexURL)
        }

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
                try save(newPersonalProfile)
            } catch {
                reportSaveError(error)
            }
        }
        do {
            try saveIndex()
        } catch {
            reportSaveError(error)
        }
    }

    private func scanProfiles() -> [PersistedProfile] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: directoryURL, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" && $0.lastPathComponent != "profile-index.json" }
            .compactMap { url in
                guard let profile = decode(PersistedProfile.self, from: url) else {
                    quarantine(url)
                    return nil
                }
                let filename = url.deletingPathExtension().lastPathComponent
                guard profile.profile.id.uuidString.caseInsensitiveCompare(filename) == .orderedSame else {
                    quarantine(url)
                    return nil
                }
                return profile
            }
            .sorted { $0.profile.id.uuidString < $1.profile.id.uuidString }
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

    private func saveDen(_ den: DenState, for profileID: UUID) {
        guard var persisted = persistedProfiles[profileID] else { return }
        let original = persisted
        persisted.den = den
        persistedProfiles[profileID] = persisted
        do {
            try save(persisted)
        } catch {
            persistedProfiles[profileID] = original
            reportSaveError(error)
        }
    }

    private func saveDeskPresets(_ deskPresets: [PersonalDeskPreset], for profileID: UUID) {
        guard var persisted = persistedProfiles[profileID] else { return }
        let original = persisted
        persisted.deskPresets = deskPresets
        persistedProfiles[profileID] = persisted
        do {
            try save(persisted)
        } catch {
            persistedProfiles[profileID] = original
            reportSaveError(error)
        }
    }

    private func saveRecentItems(_ recentItems: [RecentItem], for profileID: UUID) -> Bool {
        guard var persisted = persistedProfiles[profileID] else { return false }
        let original = persisted
        persisted.recentItems = recentItems
        persistedProfiles[profileID] = persisted
        do {
            try save(persisted)
            return true
        } catch {
            persistedProfiles[profileID] = original
            reportSaveError(error)
            return false
        }
    }

    private func save(_ persisted: PersistedProfile) throws {
        try write(persisted, to: profileURL(for: persisted.profile.id))
    }

    private func saveIndex() throws {
        try write(ProfileIndex(profileIDs: profiles.map(\.id)), to: directoryURL.appending(path: "profile-index.json"))
    }

    private func profileURL(for id: UUID) -> URL {
        directoryURL.appending(path: "\(id.uuidString.lowercased()).json")
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder.denEncoder.encode(value)
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }

    private func reportSaveError(_ error: Error) {
        errorMessage = "Could not save Profiles: \(error.localizedDescription)"
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func quarantine(_ url: URL) {
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.appendingPathExtension("corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Den Browser/Profiles", directoryHint: .isDirectory)
    }

    private static func personalProfile() -> PersistedProfile {
        PersistedProfile(
            profile: ProfileState(id: UUID(), name: "Personal", color: .blue, webProfileStore: .default),
            den: .sample)
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
