import Foundation

private enum ProfileFileLoadError: Error {
    case read(Error)
    case decode(Error)
}

@MainActor
final class ProfilePersistence {
    private static let deferredSaveDelay: Duration = .milliseconds(300)

    struct LoadResult {
        var profiles: [PersistedProfile]
        var issues: [String]
        var canRewriteIndex: Bool
        var canReadDirectory: Bool
    }

    private let directoryURL: URL
    private let isEphemeral: Bool
    private let quarantineFile: (URL, URL) throws -> Void
    private var deferredSaves: [UUID: (id: UUID, task: Task<Void, Never>)] = [:]
    private(set) var profileSaveCount = 0

    init(
        directoryURL: URL,
        isEphemeral: Bool,
        quarantineFile: @escaping (URL, URL) throws -> Void
    ) {
        self.directoryURL = directoryURL
        self.isEphemeral = isEphemeral
        self.quarantineFile = quarantineFile
    }

    func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func profileDocumentExists(for id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: profileURL(for: id).path)
    }

    func removeProfileDocument(for id: UUID) throws {
        try FileManager.default.removeItem(at: profileURL(for: id))
    }

    func load() -> LoadResult {
        var issues: [String] = []
        var canRewriteIndex = true
        var canReadDirectory = true
        var profiles = scanProfiles(
            issues: &issues,
            canRewriteIndex: &canRewriteIndex,
            canReadDirectory: &canReadDirectory)
        guard canReadDirectory else {
            return LoadResult(
                profiles: [], issues: issues, canRewriteIndex: false, canReadDirectory: false)
        }

        let indexURL = directoryURL.appending(path: "profile-index.json")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            switch decode(ProfileIndex.self, from: indexURL) {
            case .success(let index):
                let byID = Dictionary(grouping: profiles, by: { $0.profile.id })
                if byID.contains(where: { $0.value.count > 1 }) {
                    canRewriteIndex = false
                    issues.append("Multiple Profile documents use the same Profile ID; the first document was kept.")
                }
                var orderedIDs = Set<UUID>()
                profiles =
                    index.profileIDs.compactMap { profileID in
                        guard orderedIDs.insert(profileID).inserted else { return nil }
                        return byID[profileID]?.first
                    } + profiles.filter { orderedIDs.insert($0.profile.id).inserted }
            case .failure(let failure):
                switch failure {
                case .read(let error):
                    canRewriteIndex = false
                    issues.append(
                        "Could not read the Profile index \(indexURL.lastPathComponent): \(error.localizedDescription)")
                case .decode(let error):
                    if let message = unsupportedSchemaMessage(for: indexURL, error: error) {
                        canRewriteIndex = false
                        issues.append(message)
                    } else if !quarantine(indexURL, reason: "invalid Profile index", issues: &issues) {
                        canRewriteIndex = false
                    }
                }
            }
        }
        return LoadResult(
            profiles: profiles, issues: issues, canRewriteIndex: canRewriteIndex, canReadDirectory: true)
    }

    func save(_ persisted: PersistedProfile) throws {
        guard !isEphemeral else { return }
        profileSaveCount += 1
        PerformanceTrace.mark("ProfilePersistence.save #\(profileSaveCount)", category: "Persistence")
        try write(persisted, to: profileURL(for: persisted.profile.id))
    }

    func saveIndex(profileIDs: [UUID]) throws {
        guard !isEphemeral else { return }
        try write(ProfileIndex(profileIDs: profileIDs), to: directoryURL.appending(path: "profile-index.json"))
    }

    var pendingDeferredSaveIDs: [UUID] { Array(deferredSaves.keys) }

    func scheduleDeferredSave(
        for profileID: UUID,
        operation: @escaping () -> Bool
    ) {
        cancelPendingDeferredSave(for: profileID)
        let id = UUID()
        let task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.deferredSaveDelay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                guard operation() else { continue }
                if self?.deferredSaves[profileID]?.id == id {
                    self?.deferredSaves.removeValue(forKey: profileID)
                }
                return
            }
        }
        deferredSaves[profileID] = (id, task)
    }

    func cancelPendingDeferredSave(for profileID: UUID) {
        deferredSaves.removeValue(forKey: profileID)?.task.cancel()
    }

    private func profileURL(for id: UUID) -> URL {
        directoryURL.appending(path: "\(id.uuidString.lowercased()).json")
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Den Browser/Profiles", directoryHint: .isDirectory)
    }

    nonisolated static func moveFileToQuarantine(_ source: URL, _ destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    private func scanProfiles(
        issues: inout [String],
        canRewriteIndex: inout Bool,
        canReadDirectory: inout Bool
    ) -> [PersistedProfile] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        } catch {
            canReadDirectory = false
            issues.append("Could not read the Profile directory: \(error.localizedDescription)")
            return []
        }

        var profiles: [PersistedProfile] = []
        for url in urls where url.pathExtension == "json" && url.lastPathComponent != "profile-index.json" {
            switch decodePersistedProfile(from: url) {
            case .success(let profile):
                let filename = url.deletingPathExtension().lastPathComponent
                guard profile.profile.id.uuidString.caseInsensitiveCompare(filename) == .orderedSame else {
                    if !quarantine(url, reason: "Profile filename and identity do not match", issues: &issues) {
                        canRewriteIndex = false
                    }
                    continue
                }
                profiles.append(profile)
            case .failure(let failure):
                switch failure {
                case .read(let error):
                    canRewriteIndex = false
                    issues.append("Could not read Profile \(url.lastPathComponent): \(error.localizedDescription)")
                case .decode(let error):
                    if let message = unsupportedSchemaMessage(for: url, error: error) {
                        canRewriteIndex = false
                        issues.append(message)
                    } else if !quarantine(url, reason: "invalid Profile document", issues: &issues) {
                        canRewriteIndex = false
                    }
                }
            }
        }
        return profiles.sorted { $0.profile.id.uuidString < $1.profile.id.uuidString }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encodeSignpost = PerformanceTrace.beginInterval("ProfilePersistence.encode")
        defer { PerformanceTrace.endInterval("ProfilePersistence.encode", encodeSignpost) }
        let data = try JSONEncoder.denEncoder.encode(value)
        let writeSignpost = PerformanceTrace.beginInterval("ProfilePersistence.fileWrite")
        defer { PerformanceTrace.endInterval("ProfilePersistence.fileWrite", writeSignpost) }
        try data.write(to: url, options: .atomic)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> Result<T, ProfileFileLoadError> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure(.read(error))
        }
        do {
            return .success(try JSONDecoder().decode(type, from: data))
        } catch {
            return .failure(.decode(error))
        }
    }

    private func decodePersistedProfile(from url: URL) -> Result<PersistedProfile, ProfileFileLoadError> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure(.read(error))
        }
        do {
            return .success(try PersistedProfileDocumentDecoder.decode(data))
        } catch {
            return .failure(.decode(error))
        }
    }

    @discardableResult
    private func quarantine(_ url: URL, reason: String, issues: inout [String]) -> Bool {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.appendingPathExtension("corrupt-\(stamp)")
        do {
            try quarantineFile(url, backup)
            issues.append("\(reason): \(url.lastPathComponent) was preserved as \(backup.lastPathComponent).")
            return true
        } catch {
            issues.append("Could not quarantine \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    private func unsupportedSchemaMessage(for url: URL, error: Error) -> String? {
        guard let error = error as? ProfilePersistenceError else { return nil }
        switch error {
        case .unsupportedProfileIndexSchema(let version):
            return "Profile index \(url.lastPathComponent) uses unsupported schema version \(version); it was kept."
        case .unsupportedPersistedProfileSchema(let version):
            return "Profile \(url.lastPathComponent) uses unsupported schema version \(version); it was kept."
        case .duplicateProfileIDs:
            return nil
        }
    }
}
