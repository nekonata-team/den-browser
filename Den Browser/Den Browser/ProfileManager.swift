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

    @ObservationIgnored private let directoryURL: URL
    @ObservationIgnored private var persistedProfiles: [UUID: PersistedProfile] = [:]
    @ObservationIgnored private var stores: [UUID: DenStore] = [:]
    @ObservationIgnored private var windows: [UUID: WeakWindow] = [:]
    @ObservationIgnored private let sheetNavigation: SheetNavigationManager
    @ObservationIgnored private let removeDataStore: (UUID) async throws -> Void

    var personalProfileID: UUID {
        profiles.first(where: { $0.webProfileStore == .default })?.id
            ?? profiles.first?.id
            ?? UUID()
    }

    init(
        directoryURL: URL = ProfileManager.defaultDirectoryURL(),
        sheetNavigation: SheetNavigationManager,
        removeDataStore: @escaping (UUID) async throws -> Void = ProfileManager.removeWebsiteDataStore
    ) {
        self.directoryURL = directoryURL
        self.sheetNavigation = sheetNavigation
        self.removeDataStore = removeDataStore
        load()
    }

    func profile(id: UUID) -> ProfileState? {
        profiles.first { $0.id == id }
    }

    func store(for profileID: UUID) -> DenStore? {
        guard let persisted = persistedProfiles[profileID] else { return nil }
        if let store = stores[profileID] { return store }

        let store = DenStore(
            state: persisted.den,
            websiteDataStore: persisted.profile.webProfileStore.websiteDataStore,
            sheetNavigation: sheetNavigation
        ) { [weak self] den in
            self?.saveDen(den, for: profileID)
        }
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

    func clearError() { errorMessage = nil }

    func register(window: NSWindow, for profileID: UUID) {
        windows[profileID] = WeakWindow(window)
    }

    func unregister(window: NSWindow, for profileID: UUID) {
        guard windows[profileID]?.window === window else { return }
        windows.removeValue(forKey: profileID)
        stores.removeValue(forKey: profileID)?.releaseRuntimes()
    }

    func profileID(for window: NSWindow?) -> UUID? {
        guard let window else { return nil }
        return windows.first(where: { $0.value.window === window })?.key
    }

    func activeStore() -> DenStore? {
        profileID(for: NSApp.keyWindow).flatMap(store(for:))
    }

    func closeWindow(for profileID: UUID) {
        windows[profileID]?.window?.close()
        windows.removeValue(forKey: profileID)
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

        if !loaded.contains(where: { $0.profile.webProfileStore == .default }) {
            loaded.insert(Self.personalProfile(), at: 0)
        }
        loaded = deduplicated(loaded)
        persistedProfiles = Dictionary(uniqueKeysWithValues: loaded.map { ($0.profile.id, $0) })
        profiles = loaded.map(\.profile)
        for persisted in loaded {
            do {
                try save(persisted)
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
}

private final class WeakWindow {
    weak var window: NSWindow?
    init(_ window: NSWindow) { self.window = window }
}
