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
                    from: Data("{\"schemaVersion\":3,\"profile\":{},\"den\":{}}".utf8))
            })
        #expect(
            throws: DecodingError.self,
            performing: {
                try JSONDecoder().decode(
                    ProfileIndex.self,
                    from: Data("{\"schemaVersion\":2,\"profileIDs\":[]}".utf8))
            })
    }

    @Test func profilePersistsBoardSheetNavigationPause() throws {
        let board = BoardState(
            label: "Paused",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/"),
            sheetNavigationPaused: true)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let profile = ProfileState(
            id: UUID(), name: "Work", color: .purple, webProfileStore: .identified(UUID()))
        let persisted = PersistedProfile(
            profile: profile,
            den: DenState(desks: [desk], focusedDeskID: desk.id))

        let encoded = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(PersistedProfile.self, from: encoded)

        #expect(decoded.den.desks[0].boards[0].sheetNavigationPaused)
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

        #expect(decoded.schemaVersion == 2)
        #expect(decoded.deskPresets.isEmpty)
    }

    @Test func profileDocumentWithoutRecentItemsLoadsEmptyList() throws {
        let profile = ProfileState(
            id: UUID(), name: "Work", color: .purple, webProfileStore: .identified(UUID()))
        let recentItems: [RecentItem] = [
            .url(URL(string: "https://example.com")!),
            .search("Swift"),
            .terminal(workingDirectory: "/tmp"),
            .zellij(sessionName: nil),
            .zellij(sessionName: "project-a"),
            .zmx(sessionName: "project-a"),
        ]
        let encoded = try JSONEncoder().encode(
            PersistedProfile(
                profile: profile,
                den: .sample,
                recentItems: recentItems))
        #expect(
            try JSONDecoder().decode(PersistedProfile.self, from: encoded).recentItems == recentItems)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "recentItems")

        let decoded = try JSONDecoder().decode(
            PersistedProfile.self,
            from: JSONSerialization.data(withJSONObject: object))

        #expect(decoded.recentItems.isEmpty)
    }

    @Test func versionOneFixturesMigrateToVersionTwo() throws {
        let profileData = try fixtureData("persisted-profile-v1")
        let persisted = try JSONDecoder().decode(PersistedProfile.self, from: profileData)
        let indexData = try fixtureData("profile-index-v1")
        let index = try JSONDecoder().decode(ProfileIndex.self, from: indexData)

        #expect(persisted.schemaVersion == 2)
        #expect(persisted.den.desks[0].boards[1].currentSheetURL == nil)
        #expect(persisted.den.desks[0].boards[0].firstSheetURL == nil)
        #expect(persisted.den.desks[0].boards.allSatisfy { !$0.sheetNavigationPaused })
        #expect(persisted.deskPresets[0].boards[1].initialSheetURL == nil)
        #expect(index == ProfileIndex(profileIDs: [persisted.profile.id]))
        let migrated = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(persisted)) as? [String: Any])
        #expect(migrated["schemaVersion"] as? Int == 2)
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

        #expect(preferences.sheetScale == AppPreferences.defaultSheetScale)
        preferences.setSheetScale(49)
        preferences.setSheetScale(201)
        #expect(preferences.sheetScale == AppPreferences.defaultSheetScale)

        preferences.setMotionPreference(.standard)
        preferences.setNativePictureInPictureEnabled(true)
        preferences.setUBOLiteEnabled(true)
        preferences.setSheetScale(80)
        preferences.setZellijPath(" /opt/homebrew/bin/zellij ")
        preferences.setZmxPath(" /opt/homebrew/bin/zmx ")

        let restored = AppPreferences(defaults: defaults)
        let storedKeys = Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys)
        #expect(
            storedKeys == [
                "preferences.schema.version",
                "preferences.appearance.motion.mode",
                "preferences.picture-in-picture.enabled",
                "preferences.content-blocking.ubolite.enabled",
                "preferences.appearance.sheet-scale.percent",
                "preferences.terminal.zellij.executable-path",
                "preferences.terminal.zmx.executable-path",
            ])
        #expect(defaults.integer(forKey: "preferences.schema.version") == 1)
        #expect(restored.motionPreference == .standard)
        #expect(restored.nativePictureInPictureEnabled)
        #expect(restored.uBOLiteEnabled)
        #expect(restored.sheetScale == 80)
        #expect(restored.zellijPath == "/opt/homebrew/bin/zellij")
        #expect(restored.zmxPath == "/opt/homebrew/bin/zmx")
    }

    @Test func appPreferencesPersistEssentialsWithoutProfileOwnership() throws {
        let suiteName = "AppPreferencesEssentialsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let essentials = [
            Essential(name: "ChatGPT", key: "C", input: "https://chatgpt.com"),
            Essential(name: "Terminal", key: "T", input: ":terminal ~/Projects"),
        ]

        #expect(preferences.setEssentials(essentials))
        #expect(AppPreferences(defaults: defaults).essentials == essentials)
        #expect(
            !preferences.setEssentials(
                [essentials[0], Essential(name: "Duplicate", key: "C", input: "other")]))
        let lowercase = Essential(name: "Lowercase", key: "c", input: "other")
        #expect(preferences.setEssentials([essentials[0], lowercase]))
        #expect(AppPreferences(defaults: defaults).essentials == [essentials[0], lowercase])
        preferences.setEssentials([])
        #expect(AppPreferences(defaults: defaults).essentials.isEmpty)
    }

    @Test func appPreferencesInitializeMissingSchema() {
        let suiteName = "AppPreferencesMissingSchemaTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)

        #expect(defaults.integer(forKey: "preferences.schema.version") == 1)
        #expect(preferences.sheetScale == AppPreferences.defaultSheetScale)
    }

    @Test func appPreferencesDoNotDowngradeFutureSchema() {
        let suiteName = "AppPreferencesFutureSchemaTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(2, forKey: "preferences.schema.version")

        _ = AppPreferences(defaults: defaults)

        #expect(defaults.integer(forKey: "preferences.schema.version") == 2)
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

    @Test func profileWindowsShareDenAndPresentDistinctDesks() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let sourceRoute = ProfileWindowRoute(windowID: profileID, profileID: profileID)
        let source = try #require(manager.store(for: sourceRoute))
        source.createDesk(label: "Second", preset: .empty)
        let detachedDeskID = source.presentedDeskID

        let detachedRoute = try #require(
            manager.routeForOpeningDesk(
                detachedDeskID,
                profileID: profileID,
                sourceWindowID: sourceRoute.windowID))
        let detached = try #require(manager.store(for: detachedRoute))

        #expect(source.storage === detached.storage)
        #expect(source.presentedDeskID != detachedDeskID)
        #expect(detached.presentedDeskID == detachedDeskID)
        #expect(
            manager.isDeskPresentedInAnotherWindow(
                detachedDeskID,
                profileID: profileID,
                excludingWindowID: sourceRoute.windowID))
        detached.renameFocusedDesk(to: "Detached")
        #expect(source.state.desks.first { $0.id == detachedDeskID }?.label == "Detached")

        let sourceDeskID = source.presentedDeskID
        source.focusDesk(detachedDeskID)
        #expect(source.presentedDeskID == sourceDeskID)
        #expect(
            !manager.canOpenDeskInNewWindow(
                sourceDeskID,
                profileID: profileID,
                sourceWindowID: sourceRoute.windowID))

        let detachedWindow = NSWindow()
        manager.register(window: detachedWindow, for: detachedRoute)
        manager.unregister(window: detachedWindow, for: detachedRoute)
        #expect(
            !manager.isDeskPresentedInAnotherWindow(
                detachedDeskID,
                profileID: profileID,
                excludingWindowID: sourceRoute.windowID))
        source.focusDesk(detachedDeskID)
        #expect(source.presentedDeskID == detachedDeskID)
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

    @Test func missingProfileFallsBackToPersonalProfile() {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let personalID = manager.personalProfileID

        #expect(manager.resolvedProfileID(personalID) == personalID)
        let missingID = UUID()
        #expect(manager.resolvedProfileID(missingID) == personalID)
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
        let navigation = SheetNavigationManager(
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard,
            scriptSource: "")
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

    @Test func profileStoresUseSeparateWebKitStoresAndCallbacks() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "ProfileCallbackTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let navigation = SheetNavigationManager(defaults: defaults, scriptSource: "")
        navigation.setEnabled(true)
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            preferences: preferences,
            removeDataStore: { _ in })
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

    @Test func clearBrowsingDataRequestsSelectedWebsiteDataTypes() async throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let navigation = SheetNavigationManager(
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard,
            scriptSource: "")

        var removedTypes: Set<String>?
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            removeWebsiteDataTypes: { _, types in
                removedTypes = types
            })
        let personalID = manager.personalProfileID

        let success = await manager.clearBrowsingData(
            categories: [.cookies, .cache], profileID: personalID)

        #expect(success)
        #expect(
            removedTypes
                == Set([
                    WKWebsiteDataTypeCookies,
                    WKWebsiteDataTypeDiskCache,
                    WKWebsiteDataTypeMemoryCache,
                ]))
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
        let navigation = SheetNavigationManager(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard,
            scriptSource: "")
        return ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            preferences: preferences,
            removeDataStore: { _ in })
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: URL(string: url))
    }

}

private final class PersistenceFixtureBundleToken {}
