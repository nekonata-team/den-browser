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
    var clearBrowsingDataProfileID: UUID?

    @ObservationIgnored private let directoryURL: URL
    @ObservationIgnored private var persistedProfiles: [UUID: PersistedProfile] = [:]
    @ObservationIgnored private var stores: [UUID: DenStore] = [:]
    @ObservationIgnored private var windows: [UUID: WeakWindow] = [:]
    @ObservationIgnored private let sheetNavigation: SheetNavigationManager
    @ObservationIgnored private let preferences: AppPreferences
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
        websiteDataStore: ((WebProfileStore) -> WKWebsiteDataStore)? = nil
    ) {
        self.directoryURL = directoryURL
        self.sheetNavigation = sheetNavigation
        self.preferences = preferences
        self.removeDataStore = removeDataStore
        self.removeWebsiteDataTypes = removeWebsiteDataTypes
        self.initialProfile = initialProfile
        self.websiteDataStore = websiteDataStore ?? { $0.websiteDataStore }
        load()
    }

    func profile(id: UUID) -> ProfileState? {
        profiles.first { $0.id == id }
    }

    func resolvedProfileID(_ requestedID: UUID) -> UUID {
        profile(id: requestedID) == nil ? personalProfileID : requestedID
    }

    func store(for profileID: UUID) -> DenStore? {
        guard let persisted = persistedProfiles[profileID] else { return nil }
        if let store = stores[profileID] { return store }

        let store = DenStore(
            state: persisted.den,
            websiteDataStore: websiteDataStore(persisted.profile.webProfileStore),
            sheetNavigation: sheetNavigation,
            preferences: preferences,
            deskPresets: persisted.deskPresets,
            recentItems: persisted.recentItems,
            onSave: { [weak self] den in
                self?.saveDen(den, for: profileID)
            },
            onDeskPresetsSave: { [weak self] presets in
                self?.saveDeskPresets(presets, for: profileID)
            },
            onRecentItemsSave: { [weak self] items in
                self?.saveRecentItems(items, for: profileID) ?? false
            })
        stores[profileID] = store
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

        closeWindow(for: profileID)
        stores.removeValue(forKey: profileID)?.releaseRuntimes()
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

    @discardableResult
    func register(window: NSWindow, for profileID: UUID) -> Bool {
        let profileID = resolvedProfileID(profileID)
        if let existingWindow = windows[profileID]?.window, existingWindow !== window {
            if existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
            }
            DispatchQueue.main.async { [weak window] in
                window?.close()
            }
            return false
        }
        windows[profileID] = WeakWindow(window)
        return true
    }

    func unregister(window: NSWindow, for profileID: UUID) {
        let profileID = resolvedProfileID(profileID)
        guard windows[profileID]?.window === window else { return }
        windows.removeValue(forKey: profileID)
        stores[profileID]?.releaseRuntimes()
    }

    func store(for window: NSWindow?) -> DenStore? {
        guard let window else { return nil }
        let profileID = windows.first(where: { $0.value.window === window })?.key
        return profileID.flatMap(store(for:))
    }

    private func closeWindow(for profileID: UUID) {
        let profileID = resolvedProfileID(profileID)
        guard let window = windows.removeValue(forKey: profileID)?.window else { return }
        window.close()
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
                guard profile.profile.id.uuidString.lowercased() == url.deletingPathExtension().lastPathComponent else {
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

private final class WeakWindow {
    weak var window: NSWindow?

    init(_ window: NSWindow) {
        self.window = window
    }
}
