import DenDomain
import DenInfrastructure
import Foundation
import Testing

struct ProfilePersistenceTests {
    @Test func persistedModelsValidateSchemaVersionsAndConditionalRecentItemsEncoding() throws {
        // Arrange
        let profile = ProfileState(
            id: ProfileID(),
            name: "Work",
            color: .purple,
            webProfileStore: .default
        )
        let recents: [RecentItem] = [.search("swift"), .terminal(workingDirectory: "/tmp")]
        let withRecents = PersistedProfile(profile: profile, den: .sample, recentItems: recents)
        let withoutRecents = PersistedProfile(profile: profile, den: .sample)

        // Act
        let withRecentsData = try JSONEncoder().encode(withRecents)
        let withoutRecentsData = try JSONEncoder().encode(withoutRecents)
        let decodedWithRecents = try JSONDecoder().decode(PersistedProfile.self, from: withRecentsData)
        let emptyObject = try #require(
            JSONSerialization.jsonObject(with: withoutRecentsData) as? [String: Any]
        )

        // Assert
        #expect(decodedWithRecents == withRecents)
        #expect(decodedWithRecents.recentItems == recents)
        #expect(emptyObject["recentItems"] == nil)

        let invalidProfileData = Data("{\"schemaVersion\":99,\"profile\":{},\"den\":{}}".utf8)
        #expect(throws: ProfilePersistenceError.self) {
            try JSONDecoder().decode(PersistedProfile.self, from: invalidProfileData)
        }

        let validIndex = ProfileIndex(profileIDs: [profile.id])
        let decodedIndex = try JSONDecoder().decode(ProfileIndex.self, from: try JSONEncoder().encode(validIndex))
        #expect(decodedIndex == validIndex)

        let invalidIndexVersion = Data("{\"schemaVersion\":2,\"profileIDs\":[]}".utf8)
        #expect(throws: ProfilePersistenceError.self) {
            try JSONDecoder().decode(ProfileIndex.self, from: invalidIndexVersion)
        }

        let duplicateIndex = Data(
            "{\"schemaVersion\":1,\"profileIDs\":[\"\(profile.id.rawValue.uuidString)\",\"\(profile.id.rawValue.uuidString)\"]}"
                .utf8
        )
        #expect(throws: ProfilePersistenceError.self) {
            try JSONDecoder().decode(ProfileIndex.self, from: duplicateIndex)
        }
    }

    @Test func decoderRejectsUnsupportedSchemaVersions() {
        // Arrange
        let zeroVersion = Data("{\"schemaVersion\":0}".utf8)
        let futureVersion = Data("{\"schemaVersion\":\(PersistedProfile.currentSchemaVersion + 1)}".utf8)

        // Act / Assert
        #expect(throws: ProfilePersistenceError.self) {
            try PersistedProfileDocumentDecoder.decode(zeroVersion)
        }
        #expect(throws: ProfilePersistenceError.self) {
            try PersistedProfileDocumentDecoder.decode(futureVersion)
        }
    }

    @Test func decoderMigratesVersionOneLegacyBoardsAndDeskPresets() throws {
        // Arrange
        let v1JSON = Data(
            #"""
            {"schemaVersion":1,"profile":{"id":"00000000-0000-0000-0000-000000000100","name":"Work","color":"purple",
            "webProfileStore":{"kind":"default"}},"den":{"focusedDeskID":"00000000-0000-0000-0000-000000000201",
            "desks":[{"id":"00000000-0000-0000-0000-000000000201","label":"Main","boards":[
            {"id":"00000000-0000-0000-0000-000000000301","label":"Research","width":520,
            "currentSheetURL":"https://example.com/research","firstSheetURL":"https://example.com/start",
            "sheetNavigationPaused":true}]}]},"deskPresets":[{"id":"00000000-0000-0000-0000-000000000401",
            "label":"Research","boards":[{"label":"Start","width":520,"initialSheetURL":"https://example.com/start"}]}]}
            """#.utf8
        )

        // Act
        let persisted = try PersistedProfileDocumentDecoder.decode(v1JSON)

        // Assert
        #expect(persisted.schemaVersion == PersistedProfile.currentSchemaVersion)
        #expect(persisted.den.desks[0].boards[0].currentSheetURL?.absoluteString == "https://example.com/research")
        #expect(persisted.den.desks[0].boards[0].firstSheetURL?.absoluteString == "https://example.com/start")
        #expect(persisted.den.desks[0].boards[0].sheetNavigationPaused)
        #expect(persisted.deskPresets[0].boards[0].initialSheetURL?.absoluteString == "https://example.com/start")
    }

    @Test func decoderMigratesVersionTwoBoardsPresetsAndVersionThreeDrawerItems() throws {
        // Arrange
        let v2JSON = Data(
            #"""
            {"schemaVersion":2,"profile":{"id":"00000000-0000-0000-0000-000000000100","name":"Work","color":"purple",
            "webProfileStore":{"kind":"default"}},"den":{"focusedDeskID":"00000000-0000-0000-0000-000000000201",
            "desks":[{"id":"00000000-0000-0000-0000-000000000201","label":"Migration","boards":[
            {"id":"00000000-0000-0000-0000-000000000301","label":"Web","width":520,"role":{"kind":"primary"},
            "content":{"kind":"web","currentSheetURL":"https://example.com/current"},"sheetNavigationPaused":true},
            {"id":"00000000-0000-0000-0000-000000000302","label":"Shell","width":640,"role":{"kind":"primary"},
            "content":{"kind":"terminal","workingDirectory":"/work"}},
            {"id":"00000000-0000-0000-0000-000000000303","label":"Zellij","width":640,"role":{"kind":"primary"},
            "content":{"kind":"zellij","sessionName":"project"}},
            {"id":"00000000-0000-0000-0000-000000000304","label":"zmx","width":640,"role":{"kind":"primary"},
            "content":{"kind":"zmx","sessionName":"project-zmx","workingDirectory":"/work/zmx"}}]}]},
            "deskPresets":[{"id":"00000000-0000-0000-0000-000000000401","label":"Preset","boards":[
            {"label":"Shell","width":640,"content":{"kind":"terminal","workingDirectory":"/preset"}},
            {"label":"Zellij","width":640,"content":{"kind":"zellij","sessionName":"preset-zellij"}},
            {"label":"zmx","width":640,"content":{"kind":"zmx","sessionName":"preset-zmx"}}]}]}
            """#.utf8
        )
        let v3JSON = Data(
            #"""
            {"schemaVersion":3,"profile":{"id":"00000000-0000-0000-0000-000000000501","name":"Work","color":"gray",
            "webProfileStore":{"kind":"default"}},"den":{"focusedDeskID":"00000000-0000-0000-0000-000000000502",
            "desks":[{"id":"00000000-0000-0000-0000-000000000502","label":"Desk","boards":[]}],
            "drawerItems":[{"id":"00000000-0000-0000-0000-000000000401",
            "url":"https://example.com/article","title":"Article"}]},"deskPresets":[]}
            """#.utf8
        )

        // Act
        let migratedV2 = try PersistedProfileDocumentDecoder.decode(v2JSON)
        let migratedV3 = try PersistedProfileDocumentDecoder.decode(v3JSON)

        // Assert
        #expect(migratedV2.den.desks[0].boards[0].sheetNavigationPaused)
        #expect(migratedV2.den.desks[0].boards[1].terminalWorkingDirectory == "/work")
        #expect(migratedV2.den.desks[0].boards[2].zellijSessionName == "project")
        #expect(migratedV2.den.desks[0].boards[3].zmxSessionName == "project-zmx")
        #expect(migratedV2.deskPresets[0].boards[0].terminalWorkingDirectory == "/preset")
        #expect(migratedV2.deskPresets[0].boards[1].zellijSessionName == "preset-zellij")
        #expect(migratedV2.deskPresets[0].boards[2].zmxSessionName == "preset-zmx")
        #expect(migratedV3.schemaVersion == PersistedProfile.currentSchemaVersion)
        #expect(migratedV3.den.drawerItems.first?.url == URL(string: "https://example.com/article"))
        #expect(migratedV3.den.drawerItems.first?.title == "Article")
    }

    @Test func saveAndIndexRespectEphemeralModeAndLoadFollowsIndexOrder() throws {
        // Arrange
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ProfilePersistence(
            directoryURL: directory,
            isEphemeral: false,
            quarantineFile: ProfilePersistence.moveFileToQuarantine
        )
        try persistence.prepareDirectory()

        let first = makePersistedProfile(name: "First")
        let second = makePersistedProfile(name: "Second")
        let unindexed = makePersistedProfile(name: "Unindexed")
        try persistence.save(first)
        try persistence.save(second)
        try persistence.save(unindexed)
        try persistence.saveIndex(profileIDs: [second.profile.id, first.profile.id])
        try Data("ignore".utf8).write(to: directory.appending(path: "notes.txt"))

        let ephemeral = ProfilePersistence(
            directoryURL: directory,
            isEphemeral: true,
            quarantineFile: ProfilePersistence.moveFileToQuarantine
        )
        let ephemeralProfile = makePersistedProfile(name: "Ephemeral")
        try ephemeral.save(ephemeralProfile)
        try ephemeral.saveIndex(profileIDs: [ephemeralProfile.profile.id])

        // Act
        let loaded = persistence.load()

        // Assert
        #expect(persistence.profileSaveCount == 3)
        #expect(ephemeral.profileSaveCount == 0)
        #expect(persistence.profileDocumentExists(for: first.profile.id))
        #expect(!persistence.profileDocumentExists(for: ephemeralProfile.profile.id))
        #expect(loaded.canReadDirectory)
        #expect(loaded.canRewriteIndex)
        #expect(loaded.issues.isEmpty)
        #expect(loaded.profiles.map(\.profile.id) == [second.profile.id, first.profile.id, unindexed.profile.id])

        try persistence.removeProfileDocument(for: unindexed.profile.id)
        #expect(!persistence.profileDocumentExists(for: unindexed.profile.id))
    }

    @Test func loadQuarantinesCorruptAndMismatchedFilesAndPreservesUnsupportedSchemas() throws {
        // Arrange
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ProfilePersistence(
            directoryURL: directory,
            isEphemeral: false,
            quarantineFile: ProfilePersistence.moveFileToQuarantine
        )
        try persistence.prepareDirectory()

        let valid = makePersistedProfile(name: "Valid")
        let uppercaseID = ProfileID()
        let uppercase = PersistedProfile(
            profile: ProfileState(id: uppercaseID, name: "Upper", color: .green, webProfileStore: .default),
            den: .sample
        )
        let mismatched = makePersistedProfile(name: "Mismatched")
        try persistence.save(valid)
        try Data(try JSONEncoder().encode(uppercase)).write(
            to: directory.appending(path: "\(uppercaseID.rawValue.uuidString.uppercased()).json")
        )
        try Data(try JSONEncoder().encode(mismatched)).write(
            to: directory.appending(path: "\(ProfileID().rawValue.uuidString.lowercased()).json")
        )
        try Data("not-json".utf8).write(to: directory.appending(path: "corrupt-profile.json"))
        try Data("not-json".utf8).write(to: directory.appending(path: "profile-index.json"))

        // Act
        let loaded = persistence.load()
        let filenames = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        // Assert
        #expect(loaded.canReadDirectory)
        #expect(loaded.canRewriteIndex)
        #expect(Set(loaded.profiles.map(\.profile.id)) == [valid.profile.id, uppercaseID])
        #expect(filenames.contains { $0.hasPrefix("corrupt-profile.json.corrupt-") })
        #expect(filenames.contains { $0.hasPrefix("profile-index.json.corrupt-") })
        #expect(loaded.issues.count == 3)

        // Unsupported profile & index schema prevent index rewriting and are kept intact
        let unsupportedProfileURL = directory.appending(path: "\(ProfileID().rawValue.uuidString.lowercased()).json")
        try Data("{\"schemaVersion\":999}".utf8).write(to: unsupportedProfileURL)
        try Data("{\"schemaVersion\":99,\"profileIDs\":[]}".utf8).write(
            to: directory.appending(path: "profile-index.json")
        )
        let unsupportedLoad = persistence.load()
        #expect(!unsupportedLoad.canRewriteIndex)
        #expect(unsupportedLoad.issues.contains { $0.contains("unsupported schema version 999") })
        #expect(unsupportedLoad.issues.contains { $0.contains("unsupported schema version 99") })
    }

    @Test func loadReportsReadFailuresAndQuarantineErrorsWithoutRewritingIndex() throws {
        // Arrange
        struct QuarantineError: Error {}
        let missing = ProfilePersistence(
            directoryURL: FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID())"),
            isEphemeral: false,
            quarantineFile: ProfilePersistence.moveFileToQuarantine
        )
        let missingResult = missing.load()
        #expect(!missingResult.canReadDirectory)
        #expect(!missingResult.canRewriteIndex)
        #expect(missingResult.profiles.isEmpty)
        #expect(!missingResult.issues.isEmpty)

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("broken".utf8).write(to: directory.appending(path: "profile-index.json"))
        try Data("broken".utf8).write(
            to: directory.appending(path: "\(ProfileID().rawValue.uuidString.lowercased()).json")
        )
        let failingQuarantine = ProfilePersistence(
            directoryURL: directory,
            isEphemeral: false,
            quarantineFile: { _, _ in throw QuarantineError() }
        )

        // Act
        let failedResult = failingQuarantine.load()

        // Assert
        #expect(failedResult.canReadDirectory)
        #expect(!failedResult.canRewriteIndex)
        #expect(failedResult.issues.count == 2)
        #expect(failedResult.issues.allSatisfy { $0.contains("Could not quarantine") })
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "DenInfrastructurePersistenceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePersistedProfile(name: String) -> PersistedProfile {
        PersistedProfile(
            profile: ProfileState(id: ProfileID(), name: name, color: .blue, webProfileStore: .default),
            den: .sample
        )
    }
}
