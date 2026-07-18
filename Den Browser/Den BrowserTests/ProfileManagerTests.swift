import AppKit
import Foundation
import Testing
import WebKit
@testable import Den_Browser

@MainActor
struct ProfileManagerTests {
    @Test func profileModelsRoundTripAndRejectUnknownSchema() throws {
        let profile = ProfileState(
            id: UUID(), name: "Work", color: .purple, webProfileStore: .identified(UUID()))
        let persisted = PersistedProfile(profile: profile, den: .sample)
        let encoded = try JSONEncoder().encode(persisted)

        #expect(try JSONDecoder().decode(PersistedProfile.self, from: encoded) == persisted)
        #expect(
            throws: DecodingError.self,
            performing: {
                try JSONDecoder().decode(
                    PersistedProfile.self,
                    from: Data("{\"schemaVersion\":2,\"profile\":{},\"den\":{}}".utf8))
            })
        #expect(
            throws: DecodingError.self,
            performing: {
                try JSONDecoder().decode(
                    ProfileIndex.self,
                    from: Data("{\"schemaVersion\":2,\"profileIDs\":[]}".utf8))
            })
    }

    @Test func profileDocumentWithoutDeskPresetsLoadsEmptyList() throws {
        let profile = ProfileState(
            id: UUID(), name: "Work", color: .purple, webProfileStore: .identified(UUID()))
        let encoded = try JSONEncoder().encode(PersistedProfile(profile: profile, den: .sample))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["deskPresets"] != nil)
        object.removeValue(forKey: "deskPresets")

        let decoded = try JSONDecoder().decode(
            PersistedProfile.self,
            from: JSONSerialization.data(withJSONObject: object))

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.deskPresets.isEmpty)
    }

    @Test func versionOneFixturesRemainReadableAndStable() throws {
        let profileData = try fixtureData("persisted-profile-v1")
        let persisted = try JSONDecoder().decode(PersistedProfile.self, from: profileData)
        let indexData = try fixtureData("profile-index-v1")
        let index = try JSONDecoder().decode(ProfileIndex.self, from: indexData)

        #expect(persisted.schemaVersion == 1)
        #expect(persisted.den.desks[0].boards[1].currentSheetURL == nil)
        #expect(persisted.deskPresets[0].boards[1].initialSheetURL == nil)
        #expect(index == ProfileIndex(profileIDs: [persisted.profile.id]))
        #expect(try jsonObject(JSONEncoder().encode(persisted)).isEqual(jsonObject(profileData)))
        #expect(try jsonObject(JSONEncoder().encode(index)).isEqual(jsonObject(indexData)))

        var futureObject = try #require(JSONSerialization.jsonObject(with: profileData) as? [String: Any])
        futureObject["futureField"] = true
        #expect(
            try JSONDecoder().decode(
                PersistedProfile.self,
                from: JSONSerialization.data(withJSONObject: futureObject)) == persisted)

        futureObject.removeValue(forKey: "profile")
        #expect(
            throws: DecodingError.self,
            performing: {
                try JSONDecoder().decode(
                    PersistedProfile.self,
                    from: JSONSerialization.data(withJSONObject: futureObject))
            })
    }

    @Test func webProfileStoreRejectsInvalidKindIdentifierPairs() {
        #expect(
            throws: DecodingError.self,
            performing: {
                try JSONDecoder().decode(
                    WebProfileStore.self,
                    from: Data("{\"kind\":\"default\",\"identifier\":\"\(UUID())\"}".utf8))
            })
        #expect(
            throws: DecodingError.self,
            performing: {
                try JSONDecoder().decode(
                    WebProfileStore.self,
                    from: Data("{\"kind\":\"identified\"}".utf8))
            })
    }

    @Test func appPreferencesPersistByKey() {
        let suiteName = "AppPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)

        preferences.setSheetNavigationEnabled(true)
        preferences.setSheetNavigationHintAlphabet("abc")
        preferences.setSheetNavigationIgnoredHosts(["example.com"])
        preferences.setMotionPreference(.standard)

        let restored = AppPreferences(defaults: defaults)
        let storedKeys = Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys)
        #expect(
            storedKeys == [
                "preferences.schemaVersion",
                "features.vim-style-sheet-navigation.enabled",
                "features.vim-style-sheet-navigation.hint-alphabet",
                "features.vim-style-sheet-navigation.ignored-hosts",
                "appearance.motion",
            ])
        #expect(defaults.integer(forKey: "preferences.schemaVersion") == 1)
        #expect(restored.sheetNavigationEnabled)
        #expect(restored.sheetNavigationHintAlphabet == "abc")
        #expect(restored.sheetNavigationIgnoredHosts == ["example.com"])
        #expect(restored.motionPreference == .standard)
    }

    @Test func appPreferencesMigrateLegacyValuesAndDoNotDowngradeFutureSchema() {
        let legacySuiteName = "AppPreferencesLegacyTests-\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuiteName)!
        defer { legacyDefaults.removePersistentDomain(forName: legacySuiteName) }
        legacyDefaults.set("abc", forKey: "features.vim-style-sheet-navigation.hint-alphabet")

        let migrated = AppPreferences(defaults: legacyDefaults)

        #expect(migrated.sheetNavigationHintAlphabet == "abc")
        #expect(legacyDefaults.integer(forKey: "preferences.schemaVersion") == 1)

        let futureSuiteName = "AppPreferencesFutureTests-\(UUID().uuidString)"
        let futureDefaults = UserDefaults(suiteName: futureSuiteName)!
        defer { futureDefaults.removePersistentDomain(forName: futureSuiteName) }
        futureDefaults.set(2, forKey: "preferences.schemaVersion")

        _ = AppPreferences(defaults: futureDefaults)

        #expect(futureDefaults.integer(forKey: "preferences.schemaVersion") == 2)
    }

    @Test func motionPreferenceFollowsOrOverridesSystemSetting() {
        #expect(
            DenMotion.shouldReduceMotion(
                preference: .followSystem,
                systemReduceMotion: true
            ))
        #expect(
            !DenMotion.shouldReduceMotion(
                preference: .followSystem,
                systemReduceMotion: false
            ))
        #expect(
            !DenMotion.shouldReduceMotion(
                preference: .standard,
                systemReduceMotion: true
            ))
        #expect(
            DenMotion.shouldReduceMotion(
                preference: .reduced,
                systemReduceMotion: false
            ))
    }

    @Test func profileManagerCreatesPersonalAndPersistsProfileOrderAndDen() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let personal = try #require(manager.profiles.first)

        #expect(personal.name == "Personal")
        #expect(personal.color == .blue)
        #expect(personal.webProfileStore == .default)
        let work = try #require(manager.createProfile(name: " Work ", color: .green))
        _ = manager.createProfile(name: "Work", color: .pink)
        #expect(manager.profiles.map(\.name) == ["Personal", "Work", "Work"])
        #expect(manager.updateProfile(work.id, name: "Office", color: .yellow))

        let store = try #require(manager.store(for: work.id))
        store.createDesk(label: "Restored", preset: .empty)
        let restored = makeProfileManager(directory: directory)

        #expect(restored.profiles.map(\.name) == ["Personal", "Office", "Work"])
        #expect(restored.store(for: work.id)?.focusedDesk?.label == "Restored")
    }

    @Test func loadingDoesNotRewriteExistingProfileDocuments() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileURL = profileURL(manager.personalProfileID, in: directory)
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: profileURL)) as? [String: Any])
        object["futureField"] = "preserved"
        let originalData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try originalData.write(to: profileURL)

        _ = makeProfileManager(directory: directory)

        #expect(try Data(contentsOf: profileURL) == originalData)
    }

    @Test func missingWindowProfileFallsBackToPersonalProfile() {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let personalID = manager.personalProfileID
        let window = NSWindow()

        #expect(manager.resolvedProfileID(personalID) == personalID)
        let missingID = UUID()
        #expect(manager.resolvedProfileID(missingID) == personalID)

        manager.register(window: window, for: missingID)
        #expect(manager.profileID(for: window) == personalID)
        manager.unregister(window: window, for: missingID)
        #expect(manager.profileID(for: window) == nil)
    }

    @Test func profileManagerPersistsDeskPresetsPerProfile() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let personalStore = try #require(manager.store(for: manager.personalProfileID))
        let work = try #require(manager.createProfile(name: "Work", color: .green))
        let workStore = try #require(manager.store(for: work.id))

        personalStore.addBoard(urlString: "https://example.com/bookmark?one=1")
        #expect(personalStore.saveFocusedDeskAsPreset(label: "Reading") == .created)

        let restored = makeProfileManager(directory: directory)
        #expect(restored.store(for: manager.personalProfileID)?.deskPresets.map(\.label) == ["Reading"])
        #expect(restored.store(for: work.id)?.deskPresets.isEmpty == true)
        #expect(workStore.deskPresets.isEmpty)
    }

    @Test func personalCannotBeDeletedAndAdditionalProfileCan() async throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let personalID = manager.personalProfileID
        let work = try #require(manager.createProfile(name: "Work", color: .gray))

        #expect(!(await manager.deleteProfile(personalID)))
        #expect(await manager.deleteProfile(work.id))
        #expect(manager.profiles.map(\.id) == [personalID])
    }

    @Test func failedWebsiteDataDeletionRestoresProfileDocument() async throws {
        struct ExpectedError: Error {}

        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        let navigation = SheetNavigationManager(preferences: preferences, scriptSource: "")
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            removeDataStore: { _ in throw ExpectedError() })
        let work = try #require(manager.createProfile(name: "Work", color: .gray))

        #expect(!(await manager.deleteProfile(work.id)))
        #expect(manager.profile(id: work.id) != nil)
        #expect(FileManager.default.fileExists(atPath: profileURL(work.id, in: directory).path))
        #expect(makeProfileManager(directory: directory).profile(id: work.id) != nil)
    }

    @Test func failedProfileWritesRollBackCreationAndUpdate() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let indexURL = directory.appending(path: "profile-index.json")
        try FileManager.default.removeItem(at: indexURL)
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: false)

        #expect(manager.createProfile(name: "Work", color: .green) == nil)
        #expect(manager.profiles.count == 1)

        try FileManager.default.removeItem(at: indexURL)
        let work = try #require(manager.createProfile(name: "Work", color: .green))
        let workURL = profileURL(work.id, in: directory)
        try FileManager.default.removeItem(at: workURL)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: false)

        #expect(!manager.updateProfile(work.id, name: "Changed"))
        #expect(manager.profile(id: work.id)?.name == "Work")
    }

    @Test func mismatchedProfileFilenameIsQuarantined() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let mismatchedURL = profileURL(UUID(), in: directory)
        try FileManager.default.moveItem(at: profileURL(work.id, in: directory), to: mismatchedURL)

        let restored = makeProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        #expect(restored.profile(id: work.id) == nil)
        #expect(names.contains { $0.hasPrefix("\(mismatchedURL.lastPathComponent).corrupt-") })
    }

    @Test func removedBoardRestorationIsLimitedToCurrentAppRun() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let personalID = manager.personalProfileID
        let store = try #require(manager.store(for: personalID))
        store.addBoard(urlString: "https://example.com")
        let boardID = try #require(store.focusedDesk?.focusedBoardID)

        store.removeFocusedBoard()
        let restored = makeProfileManager(directory: directory)

        #expect(store.recentlyRemovedBoard?.board.id == boardID)
        #expect(restored.store(for: personalID)?.focusedDesk?.boards.contains { $0.id == boardID } == false)
        #expect(restored.store(for: personalID)?.recentlyRemovedBoard == nil)
    }

    @Test func closingProfileWindowKeepsCurrentRunRestorationCandidate() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let store = try #require(manager.store(for: profileID))
        store.addBoard(urlString: "https://example.com")
        let boardID = try #require(store.focusedDesk?.focusedBoardID)
        store.removeFocusedBoard()
        let window = NSWindow()

        manager.register(window: window, for: profileID)
        manager.unregister(window: window, for: profileID)

        #expect(manager.store(for: profileID) === store)
        #expect(store.recentlyRemovedBoard?.board.id == boardID)
    }

    @Test func profileStoresUseSeparateWebKitStoresAndCallbacks() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "ProfileCallbackTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let navigation = SheetNavigationManager(preferences: preferences, scriptSource: "")
        navigation.setEnabled(true)
        let manager = ProfileManager(
            directoryURL: directory, sheetNavigation: navigation, removeDataStore: { _ in })
        let second = try #require(manager.createProfile(name: "Second", color: .pink))
        let firstStore = try #require(manager.store(for: manager.personalProfileID))
        let secondStore = try #require(manager.store(for: second.id))
        let firstBoard = board("First")
        let secondBoard = board("Second")
        firstStore.state = DenState(desks: [desk("First", boards: [firstBoard])], focusedDeskID: UUID())
        firstStore.focusDesk(firstStore.state.desks[0].id)
        secondStore.state = DenState(desks: [desk("Second", boards: [secondBoard])], focusedDeskID: UUID())
        secondStore.focusDesk(secondStore.state.desks[0].id)
        let firstWebView = firstStore.runtime(for: firstBoard).webView
        let secondWebView = secondStore.runtime(for: secondBoard).webView

        #expect(firstWebView.configuration.websiteDataStore !== secondWebView.configuration.websiteDataStore)
        #expect(
            navigation.handleScriptMessage(
                ["action": "openBoard", "url": "https://first.example/"], from: firstWebView))
        #expect(
            navigation.handleScriptMessage(
                ["action": "openBoard", "url": "https://second.example/"], from: secondWebView))
        #expect(
            firstStore.focusedDesk?.boards.contains {
                $0.currentSheetURL == URL(string: "https://first.example/")
            } == true)
        #expect(
            secondStore.focusedDesk?.boards.contains {
                $0.currentSheetURL == URL(string: "https://second.example/")
            } == true)
        #expect(
            firstStore.focusedDesk?.boards.contains {
                $0.currentSheetURL == URL(string: "https://second.example/")
            } == false)
    }

    @Test func corruptIndexIsQuarantinedAndRebuiltFromProfiles() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let indexURL = directory.appending(path: "profile-index.json")
        try Data("broken".utf8).write(to: indexURL)

        let restored = makeProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        #expect(restored.profiles.contains { $0.id == work.id })
        #expect(names.contains { $0.hasPrefix("profile-index.json.corrupt-") })
        #expect((try JSONDecoder().decode(ProfileIndex.self, from: Data(contentsOf: indexURL))).profileIDs.count == 2)
    }
    private func temporaryProfileDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "den-browser-profile-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func profileURL(_ id: UUID, in directory: URL) -> URL {
        directory.appending(path: "\(id.uuidString.lowercased()).json")
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(
            Bundle(for: PersistenceFixtureBundleToken.self)
                .url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func jsonObject(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private func makeProfileManager(directory: URL) -> ProfileManager {
        let suiteName = "ProfileManagerPreferences-\(UUID().uuidString)"
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        let navigation = SheetNavigationManager(preferences: preferences, scriptSource: "")
        return ProfileManager(
            directoryURL: directory, sheetNavigation: navigation, removeDataStore: { _ in })
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: URL(string: url))
    }
}

private final class PersistenceFixtureBundleToken {}
