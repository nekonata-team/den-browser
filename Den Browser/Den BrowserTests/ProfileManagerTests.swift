import AppKit
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct ProfileManagerTests {

    @Test func profileManagerCreatesPersonalProfileByDefault() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Act
        let manager = makeProfileManager(directory: directory)

        // Assert
        let personal = try #require(manager.profiles.first)
        #expect(personal.name == "Personal")
        #expect(personal.color == .blue)
        #expect(personal.webProfileStore == .default)

        let personalStore = try #require(manager.store(for: personal.id))
        #expect(manager.profileID(for: personalStore) == personal.id)
        #expect(ProfileColor.presets.allSatisfy { $0.rgb.red > 0 || $0.rgb.green > 0 || $0.rgb.blue > 0 })
    }

    @Test func profileManagerPersistsProfileOrderAndUpdates() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: " Work ", color: .green))
        _ = manager.createProfile(name: "Work", color: .pink)

        // Act
        let updated = manager.updateProfile(work.id, name: "Office", color: .yellow)
        let workStore = try #require(manager.store(for: work.id))
        workStore.createDesk(label: "Restored", preset: .empty)
        let restored = makeProfileManager(directory: directory)

        // Assert
        #expect(updated)
        #expect(restored.profiles.map(\.name) == ["Personal", "Office", "Work"])
        #expect(restored.store(for: work.id)?.focusedDesk?.label == "Restored")
    }

    @Test func profileWindowsShareDenAndPresentDistinctDesks() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let sourceRoute = ProfileWindowRoute(windowID: profileID, profileID: profileID)
        let source = try #require(manager.store(for: sourceRoute))
        source.createDesk(label: "Second", preset: .empty)
        let detachedDeskID = source.presentedDeskID

        // Act
        let detachedRoute = try #require(
            manager.routeForOpeningDesk(
                detachedDeskID,
                profileID: profileID,
                sourceWindowID: sourceRoute.windowID))
        let detached = try #require(manager.store(for: detachedRoute))

        // Assert - shared storage, distinct presented desk
        #expect(source.storage === detached.storage)
        #expect(source.presentedDeskID != detachedDeskID)
        #expect(detached.presentedDeskID == detachedDeskID)
        #expect(
            manager.isDeskPresentedInAnotherWindow(
                detachedDeskID,
                profileID: profileID,
                excludingWindowID: sourceRoute.windowID))

        // Act - rename in one window reflects in shared state
        detached.renameFocusedDesk(to: "Detached")

        // Assert
        #expect(source.state.desks.first { $0.id == detachedDeskID }?.label == "Detached")

        // Act - source window cannot re-focus desk presented elsewhere
        let sourceDeskID = source.presentedDeskID
        source.focusDesk(detachedDeskID)

        // Assert
        #expect(source.presentedDeskID == sourceDeskID)
        #expect(
            !manager.canOpenDeskInNewWindow(
                sourceDeskID,
                profileID: profileID,
                sourceWindowID: sourceRoute.windowID))

        // Act - closing detached window allows source to focus that desk again
        let detachedWindow = NSWindow()
        manager.register(window: detachedWindow, for: detachedRoute)
        manager.unregister(window: detachedWindow, for: detachedRoute)
        source.focusDesk(detachedDeskID)

        // Assert
        #expect(
            !manager.isDeskPresentedInAnotherWindow(
                detachedDeskID,
                profileID: profileID,
                excludingWindowID: sourceRoute.windowID))
        #expect(source.presentedDeskID == detachedDeskID)
    }

    @Test func loadingDoesNotRewriteExistingProfileDocuments() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileURL = profileURL(manager.personalProfileID, in: directory)
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: profileURL)) as? [String: Any])
        object["futureField"] = "preserved"
        let originalData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try originalData.write(to: profileURL)

        // Act
        _ = makeProfileManager(directory: directory)

        // Assert
        #expect(try Data(contentsOf: profileURL) == originalData)
    }

    @Test func missingProfileFallsBackToPersonalProfile() {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let personalID = manager.personalProfileID
        let missingID = UUID()

        // Act
        let resolvedPersonal = manager.resolvedProfileID(personalID)
        let resolvedMissing = manager.resolvedProfileID(missingID)

        // Assert
        #expect(resolvedPersonal == personalID)
        #expect(resolvedMissing == personalID)
    }

    @Test func profileManagerPersistsDeskPresetsPerProfile() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let personalStore = try #require(manager.store(for: manager.personalProfileID))
        let work = try #require(manager.createProfile(name: "Work", color: .green))
        let workStore = try #require(manager.store(for: work.id))

        // Act
        personalStore.addBoard(urlString: "https://example.com/bookmark?one=1")
        let saveResult = personalStore.saveFocusedDeskAsPreset(label: "Reading")
        let restored = makeProfileManager(directory: directory)

        // Assert
        #expect(saveResult == .created)
        #expect(restored.store(for: manager.personalProfileID)?.deskPresets.map(\.label) == ["Reading"])
        #expect(restored.store(for: work.id)?.deskPresets.isEmpty == true)
        #expect(workStore.deskPresets.isEmpty)
    }

    @Test func personalCannotBeDeletedAndAdditionalProfileCan() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let personalID = manager.personalProfileID
        let work = try #require(manager.createProfile(name: "Work", color: .gray))

        // Act
        let personalDeleted = await manager.deleteProfile(personalID)
        let workDeleted = await manager.deleteProfile(work.id)

        // Assert
        #expect(!personalDeleted)
        #expect(workDeleted)
        #expect(manager.profiles.map(\.id) == [personalID])
    }

    @Test func failedWebsiteDataDeletionRestoresProfileDocument() async throws {
        // Arrange
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

        // Act
        let deleted = await manager.deleteProfile(work.id)

        // Assert
        #expect(!deleted)
        #expect(manager.profile(id: work.id) != nil)
        #expect(manager.store(for: work.id) != nil)
        #expect(FileManager.default.fileExists(atPath: profileURL(work.id, in: directory).path))
        #expect(makeProfileManager(directory: directory).profile(id: work.id) != nil)
    }

    @Test func failedProfileCreationRollsBackIndex() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let indexURL = directory.appending(path: "profile-index.json")
        try FileManager.default.removeItem(at: indexURL)
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: false)

        // Act
        let created = manager.createProfile(name: "Work", color: .green)

        // Assert
        #expect(created == nil)
        #expect(manager.profiles.count == 1)
    }

    @Test func failedProfileUpdateRollsBackState() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .green))
        let workURL = profileURL(work.id, in: directory)
        try FileManager.default.removeItem(at: workURL)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: false)

        // Act
        let updated = manager.updateProfile(work.id, name: "Changed")

        // Assert
        #expect(!updated)
        #expect(manager.profile(id: work.id)?.name == "Work")
    }

    @Test func mismatchedProfileFilenameIsQuarantined() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let mismatchedURL = profileURL(UUID(), in: directory)
        try FileManager.default.moveItem(at: profileURL(work.id, in: directory), to: mismatchedURL)

        // Act
        let restored = makeProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        // Assert
        #expect(restored.profile(id: work.id) == nil)
        #expect(names.contains { $0.hasPrefix("\(mismatchedURL.lastPathComponent).corrupt-") })
    }

    @Test func uppercaseProfileFilenameIsLoadedWithoutQuarantine() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let uppercaseURL = directory.appending(path: "\(work.id.uuidString.uppercased()).json")
        try FileManager.default.moveItem(at: profileURL(work.id, in: directory), to: uppercaseURL)

        // Act
        let restored = makeProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        // Assert
        #expect(restored.profile(id: work.id)?.name == "Work")
        #expect(!names.contains { $0.contains(".corrupt-") })
    }

    @Test func removedBoardRestorationIsLimitedToCurrentAppRun() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let personalID = manager.personalProfileID
        let store = try #require(manager.store(for: personalID))
        store.addBoard(urlString: "https://example.com")
        let boardID = try #require(store.focusedDesk?.focusedBoardID)

        // Act
        store.removeFocusedBoard()
        let restored = makeProfileManager(directory: directory)

        // Assert
        #expect(store.recentlyRemovedBoards.first?.board.id == boardID)
        #expect(restored.store(for: personalID)?.focusedDesk?.boards.contains { $0.id == boardID } == false)
        #expect(restored.store(for: personalID)?.recentlyRemovedBoards.isEmpty == true)
    }

    @Test func profileStoresUseSeparateWebKitStoresAndCallbacks() throws {
        // Arrange
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

        // Act
        let firstHandled = navigation.handleScriptMessage(
            ["action": "openBoard", "url": "https://first.example/"], from: firstWebView)
        let secondHandled = navigation.handleScriptMessage(
            ["action": "openBoard", "url": "https://second.example/"], from: secondWebView)

        // Assert
        #expect(firstWebView.configuration.websiteDataStore !== secondWebView.configuration.websiteDataStore)
        #expect(firstHandled)
        #expect(secondHandled)
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
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let indexURL = directory.appending(path: "profile-index.json")
        try Data("broken".utf8).write(to: indexURL)

        // Act
        let restored = makeProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let rebuiltIndex = try JSONDecoder().decode(ProfileIndex.self, from: Data(contentsOf: indexURL))

        // Assert
        #expect(restored.profiles.contains { $0.id == work.id })
        #expect(names.contains { $0.hasPrefix("profile-index.json.corrupt-") })
        #expect(rebuiltIndex.profileIDs.count == 2)
    }

    @Test func clearBrowsingDataRequestsSelectedWebsiteDataTypes() async throws {
        // Arrange
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

        // Act
        let success = await manager.clearBrowsingData(
            categories: [.cookies, .cache], profileID: personalID)

        // Assert
        #expect(success)
        #expect(
            removedTypes
                == Set([
                    WKWebsiteDataTypeCookies,
                    WKWebsiteDataTypeDiskCache,
                    WKWebsiteDataTypeMemoryCache,
                ]))
    }

    @Test func failedSaveRetainsLatestStateForSubsequentWrite() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let targetURL = URL(string: "https://example.com/updated")

        // Act
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        store.addBoard(urlString: "https://example.com/updated")
        #expect(manager.errorMessage != nil)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #expect(store.saveDeskPresets())

        // Assert
        let restored = makeProfileManager(directory: directory)
        let restoredStore = try #require(restored.store(for: manager.personalProfileID))
        #expect(restoredStore.focusedDesk?.boards.contains { $0.currentSheetURL == targetURL } == true)
    }

    private func temporaryProfileDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "den-browser-profile-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func profileURL(_ id: UUID, in directory: URL) -> URL {
        directory.appending(path: "\(id.uuidString.lowercased()).json")
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
