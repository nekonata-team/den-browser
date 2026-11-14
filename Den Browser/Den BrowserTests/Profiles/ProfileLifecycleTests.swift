import AppKit
import DenApplication
import DenDomain
import DenInfrastructure
import DenModels
import DenViews
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct ProfileLifecycleTests {
    @Test func skillMaintenanceRequiresAVisibleProfileWindow() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let session = try #require(manager.session(for: manager.personalProfileID))
        let state = session.resources.state

        // Act
        let error = manager.runSkillMaintenance(.install)

        // Assert
        #expect(error != nil)
        #expect(session.resources.state == state)
    }

    @Test func resetClosesOtherWindowsInSameProfileAndPreservesOtherProfiles() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let sourceRoute = ProfileWindowRoute(windowID: profileID.rawValue, profileID: profileID)
        let source = try #require(manager.session(for: sourceRoute))
        source.desks.createDesk(label: "Detached", preset: .empty)
        let route = try #require(
            manager.routeForOpeningDesk(
                source.navigation.presentedDeskID,
                profileID: profileID,
                sourceWindowID: sourceRoute.windowID
            )
        )
        let detached = try #require(manager.session(for: route))
        let shared = source.resources
        let otherProfile = try #require(manager.createProfile(name: "Other", color: .blue))
        let other = try #require(manager.session(for: otherProfile.id))
        other.boardOpening.createTerminalBoard(workingDirectory: "/tmp")
        let otherState = other.resources.state

        // Act
        source.reset.resetDen()

        // Assert
        #expect(source.resources === shared)
        #expect(detached.resources === shared)
        #expect(manager.sessions(for: profileID).count == 1)
        #expect(manager.sessions(for: profileID).first === source)
        #expect(
            !manager.isDeskPresentedInAnotherWindow(
                detached.navigation.presentedDeskID,
                profileID: profileID,
                excludingWindowID: sourceRoute.windowID
            )
        )
        #expect(source.resources.state.desks.count == 1)
        #expect(source.navigation.presentedDeskID == source.resources.state.desks[0].id)
        #expect(source.resources.state.desks[0].boards.isEmpty)
        #expect(manager.sessions(for: otherProfile.id).first === other)
        #expect(other.resources.state == otherState)
    }

    @Test func profileManagerCreatesPersonalProfileByDefault() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Act
        let manager = makeTestProfileManager(directory: directory)

        // Assert
        let personal = try #require(manager.profiles.first)
        #expect(personal.name == "Personal")
        #expect(personal.color == .blue)
        #expect(personal.webProfileStore == .default)
        #expect(!manager.isPrivateDen)

        let personalSession = try #require(manager.session(for: personal.id))
        #expect(manager.profileID(for: personalSession) == personal.id)
        #expect(
            ProfileColor.presets.allSatisfy {
                let rgb = profileRGB(for: $0)
                return rgb.red > 0 || rgb.green > 0 || rgb.blue > 0
            }
        )
    }

    @Test func ephemeralProfileManagerKeepsProfileAndDenStateInMemory() throws {
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            initialProfile: PersistedProfile(
                profile: ProfileState(
                    id: ProfileID(),
                    name: "Private Den",
                    color: .gray,
                    webProfileStore: .default
                ),
                den: .sample
            ),
            isEphemeral: true,
            websiteDataStore: { _ in .nonPersistent() }
        )
        let profile = try #require(manager.profiles.first)
        let session = try #require(manager.session(for: profile.id))

        _ = session.boardOpening.createBoard(urlString: "https://example.com/private")

        #expect(profile.name == "Private Den")
        #expect(manager.isPrivateDen)
        #expect(session.navigation.focusedDesk?.boards.count == 1)
        #expect(session.resources.save())
        #expect(manager.profileSaveCount == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func profileManagerPersistsProfileOrderAndUpdates() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: " Work ", color: .green))
        _ = manager.createProfile(name: "Work", color: .pink)

        // Act
        let updated = manager.updateProfile(work.id, name: "Office", color: .yellow)
        let workSession = try #require(manager.session(for: work.id))
        workSession.desks.createDesk(label: "Restored", preset: .empty)
        let restored = makeTestProfileManager(directory: directory)

        // Assert
        #expect(updated)
        #expect(restored.profiles.map(\.name) == ["Personal", "Office", "Work"])
        #expect(restored.session(for: work.id)?.navigation.focusedDesk?.label == "Restored")
    }

    @Test func restoredWindowRoutesSelectTheirOwnDesks() throws {
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let session = try #require(manager.session(for: profileID))
        let firstDeskID = session.navigation.presentedDeskID
        session.desks.createDesk(label: "Second", preset: .empty)
        let secondDeskID = session.navigation.presentedDeskID
        let routes = [
            ProfileWindowRoute(profileID: profileID, deskID: firstDeskID),
            ProfileWindowRoute(profileID: profileID, deskID: secondDeskID),
        ]

        let decoded = try JSONDecoder().decode([ProfileWindowRoute].self, from: JSONEncoder().encode(routes))
        let restored = makeTestProfileManager(directory: directory)

        #expect(restored.session(for: decoded[0])?.navigation.presentedDeskID == firstDeskID)
        #expect(restored.session(for: decoded[1])?.navigation.presentedDeskID == secondDeskID)
    }

    @Test func profileWindowsShareDenAndPresentDistinctDesks() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let sourceRoute = ProfileWindowRoute(windowID: profileID.rawValue, profileID: profileID)
        let source = try #require(manager.session(for: sourceRoute))
        source.desks.createDesk(label: "Second", preset: .empty)
        let detachedDeskID = source.navigation.presentedDeskID

        // Act
        let detachedRoute = try #require(
            manager.routeForOpeningDesk(
                detachedDeskID,
                profileID: profileID,
                sourceWindowID: sourceRoute.windowID
            )
        )
        let detached = try #require(manager.session(for: detachedRoute))

        // Assert - shared storage, distinct presented desk
        #expect(source.resources === detached.resources)
        #expect(source.navigation.presentedDeskID != detachedDeskID)
        #expect(detached.navigation.presentedDeskID == detachedDeskID)
        #expect(
            manager.isDeskPresentedInAnotherWindow(
                detachedDeskID,
                profileID: profileID,
                excludingWindowID: sourceRoute.windowID
            )
        )

        // Act - rename in one window reflects in shared state
        detached.desks.renameFocusedDesk(to: "Detached")

        // Assert
        #expect(source.resources.state.desks.first { $0.id == detachedDeskID }?.label == "Detached")

        // Act - source window cannot re-focus desk presented elsewhere
        let sourceDeskID = source.navigation.presentedDeskID
        source.boardNavigation.focusDesk(detachedDeskID)

        // Assert
        #expect(source.navigation.presentedDeskID == sourceDeskID)
        #expect(
            !manager.canOpenDeskInNewWindow(
                sourceDeskID,
                profileID: profileID,
                sourceWindowID: sourceRoute.windowID
            )
        )

        // Act - closing detached window allows source to focus that desk again
        let detachedWindow = NSWindow()
        manager.register(window: detachedWindow, for: detachedRoute)
        manager.unregister(window: detachedWindow, for: detachedRoute)
        source.boardNavigation.focusDesk(detachedDeskID)

        // Assert
        #expect(
            !manager.isDeskPresentedInAnotherWindow(
                detachedDeskID,
                profileID: profileID,
                excludingWindowID: sourceRoute.windowID
            )
        )
        #expect(source.navigation.presentedDeskID == detachedDeskID)
    }

    @Test func missingProfileFallsBackToPersonalProfile() {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let personalID = manager.personalProfileID
        let missingID = ProfileID()

        // Act
        let resolvedPersonal = manager.resolvedProfileID(personalID)
        let resolvedMissing = manager.resolvedProfileID(missingID)

        // Assert
        #expect(resolvedPersonal == personalID)
        #expect(resolvedMissing == personalID)
    }

    @Test func personalCannotBeDeletedAndAdditionalProfileCan() async throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let personalID = manager.personalProfileID
        let work = try #require(manager.createProfile(name: "Work", color: .gray))
        let extensionRoot = directory.appending(path: "WebExtensions")
        let personalExtensions = extensionRoot.appending(path: personalID.rawValue.uuidString)
        let workExtensions = extensionRoot.appending(path: work.id.rawValue.uuidString)
        try FileManager.default.createDirectory(at: personalExtensions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workExtensions, withIntermediateDirectories: true)
        try Data("compiled rules".utf8).write(to: workExtensions.appending(path: "ContentRuleList.data"))

        // Act
        let personalDeleted = await manager.deleteProfile(personalID)
        let workDeleted = await manager.deleteProfile(work.id)

        // Assert
        #expect(!personalDeleted)
        #expect(workDeleted)
        #expect(manager.profiles.map(\.id) == [personalID])
        #expect(!FileManager.default.fileExists(atPath: workExtensions.path))
        #expect(FileManager.default.fileExists(atPath: personalExtensions.path))
    }

    @Test(arguments: [true, false])
    func openProfileCannotBeDeleted(hasRegisteredWindow: Bool) async throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var removedWebsiteData = false
        var removedExtensionData = false
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: makeTestDefaults(), scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in removedWebsiteData = true },
            removeExtensionData: { _ in removedExtensionData = true },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let work = try #require(manager.createProfile(name: "Work", color: .gray))
        let route = ProfileWindowRoute(profileID: work.id)
        let window = NSWindow()
        if hasRegisteredWindow {
            manager.register(window: window, for: route)
        } else {
            _ = try #require(manager.session(for: route))
        }

        // Act
        let deleted = await manager.deleteProfile(work.id)

        // Assert
        #expect(!manager.canDeleteProfile(work.id))
        #expect(!deleted)
        #expect(!removedWebsiteData)
        #expect(!removedExtensionData)
        #expect(manager.profile(id: work.id) != nil)
        #expect(FileManager.default.fileExists(atPath: makeProfileURL(work.id, in: directory).path))
    }

    @Test func closingProfileWindowMakesDeletionAvailable() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .gray))
        let route = ProfileWindowRoute(profileID: work.id)
        let window = NSWindow()
        _ = try #require(manager.session(for: route))
        manager.register(window: window, for: route)

        // Act
        manager.unregister(window: window, for: route)

        // Assert
        #expect(manager.canDeleteProfile(work.id))
    }

    @Test(arguments: [false, true])
    func deletingProfileRejectsReopeningAndDuplicateDeletion(fails: Bool) async throws {
        // Arrange
        struct ExpectedError: Error {}
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var removalStarted: CheckedContinuation<Void, Never>?
        var resumeRemoval: CheckedContinuation<Void, Never>?
        var removalCount = 0
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: makeTestDefaults(), scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in
                removalCount += 1
                guard removalCount == 1 else { return }
                await withCheckedContinuation { continuation in
                    resumeRemoval = continuation
                    removalStarted?.resume()
                }
                if fails { throw ExpectedError() }
            },
            removeExtensionData: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let work = try #require(manager.createProfile(name: "Work", color: .gray))
        var openedProfiles: [ProfileID] = []
        manager.openWindowAction = { openedProfiles.append($0.profileID) }
        var deletion: Task<Bool, Never>?

        // Act
        await withCheckedContinuation { continuation in
            removalStarted = continuation
            deletion = Task { await manager.deleteProfile(work.id) }
        }
        let canDeleteWhileWaiting = manager.canDeleteProfile(work.id)
        let canOpenWhileWaiting = manager.canOpenWindow(for: work.id)
        let reopened = manager.openWindow(for: work.id)
        let duplicateDeleted = await manager.deleteProfile(work.id)
        let session = manager.session(for: work.id)
        let personalOpened = manager.openWindow(for: manager.personalProfileID)
        resumeRemoval?.resume()
        let deleted = await deletion?.value

        // Assert
        #expect(!canDeleteWhileWaiting)
        #expect(!canOpenWhileWaiting)
        #expect(!reopened)
        #expect(session == nil)
        #expect(!duplicateDeleted)
        #expect(removalCount == 1)
        #expect(personalOpened)
        #expect(openedProfiles == [manager.personalProfileID])
        #expect(deleted == !fails)
        #expect(manager.canDeleteProfile(work.id) == fails)
        #expect(manager.canOpenWindow(for: work.id) == fails)
        if fails {
            #expect(manager.openWindow(for: work.id))
            #expect(manager.session(for: work.id) != nil)
        }
    }

    @Test func canOpenWindowReportsAvailability() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: makeTestDefaults(), scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            websiteDataStore: { _ in .nonPersistent() }
        )

        // Assert
        #expect(manager.canOpenWindow(for: manager.personalProfileID))
        #expect(!manager.canOpenWindow(for: ProfileID()))
    }

    @Test func failedExtensionDataDeletionKeepsProfileForRetry() async throws {
        // Arrange
        struct ExpectedError: Error {}
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: makeTestDefaults(), scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in },
            removeExtensionData: { _ in throw ExpectedError() },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let work = try #require(manager.createProfile(name: "Work", color: .gray))

        // Act
        let deleted = await manager.deleteProfile(work.id)

        // Assert
        #expect(!deleted)
        #expect(manager.errorMessage != nil)
        #expect(manager.profile(id: work.id) != nil)
        #expect(FileManager.default.fileExists(atPath: makeProfileURL(work.id, in: directory).path))
    }

    @Test func failedWebsiteDataDeletionRestoresProfileDocument() async throws {
        // Arrange
        struct ExpectedError: Error {}
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let navigation = SheetNavigationManager(
            defaults: makeTestDefaults(),
            scriptSource: ""
        )
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in throw ExpectedError() },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let work = try #require(manager.createProfile(name: "Work", color: .gray))

        // Act
        let deleted = await manager.deleteProfile(work.id)

        // Assert
        #expect(!deleted)
        #expect(manager.profile(id: work.id) != nil)
        #expect(manager.session(for: work.id) != nil)
        #expect(FileManager.default.fileExists(atPath: makeProfileURL(work.id, in: directory).path))
        #expect(makeTestProfileManager(directory: directory).profile(id: work.id) != nil)
    }

    @Test func failedProfileCreationRollsBackIndex() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
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
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .green))
        let workURL = makeProfileURL(work.id, in: directory)
        try FileManager.default.removeItem(at: workURL)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: false)

        // Act
        let updated = manager.updateProfile(work.id, name: "Changed")

        // Assert
        #expect(!updated)
        #expect(manager.profile(id: work.id)?.name == "Work")
    }

    @Test func removedBoardRestorationIsLimitedToCurrentAppRun() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let personalID = manager.personalProfileID
        let session = try #require(manager.session(for: personalID))
        _ = session.boardOpening.createBoard(urlString: "https://example.com")
        let boardID = try #require(session.navigation.focusedDesk?.focusedBoardID)

        // Act
        session.boardRemoval.removeFocusedBoard()
        let restored = makeTestProfileManager(directory: directory)

        // Assert
        #expect(session.resources.recentlyRemovedBoards.first?.board.id == boardID)
        #expect(
            restored.session(for: personalID)?.navigation.focusedDesk?.boards.contains { $0.id == boardID } == false
        )
        #expect(restored.session(for: personalID)?.resources.recentlyRemovedBoards.isEmpty == true)
    }

    @Test func clearBrowsingDataRequestsSelectedWebsiteDataTypes() async throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let navigation = SheetNavigationManager(
            defaults: makeTestDefaults(),
            scriptSource: ""
        )
        var removedTypes: Set<String>?
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeWebsiteDataTypes: { _, types in
                removedTypes = types
            },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let personalID = manager.personalProfileID

        // Act
        let success = await manager.clearBrowsingData(
            categories: [.cookies, .cache],
            profileID: personalID
        )

        // Assert
        #expect(success)
        #expect(
            removedTypes
                == Set([
                    WKWebsiteDataTypeCookies,
                    WKWebsiteDataTypeDiskCache,
                    WKWebsiteDataTypeMemoryCache,
                ])
        )
    }

    @Test func failedProfileDeletionPreservesProfileState() async throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        struct RemovalError: Error {}
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in throw RemovalError() },
            websiteDataStore: { _ in .nonPersistent() }
        )

        let profile = try #require(manager.createProfile(name: "TestProfile", color: .green))

        // Act
        let deleted = await manager.deleteProfile(profile.id)

        // Assert
        #expect(!deleted)
        #expect(manager.errorMessage != nil)
        #expect(manager.profiles.contains { $0.id == profile.id })
    }

    @Test func failedProfileDeletionAllowsSubsequentStoreAccess() async throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        struct RemovalError: Error {}
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in throw RemovalError() },
            websiteDataStore: { _ in .nonPersistent() }
        )

        let profile = try #require(manager.createProfile(name: "TestProfile", color: .green))
        _ = await manager.deleteProfile(profile.id)

        // Act
        let recoveredSession = manager.session(for: profile.id)

        // Assert
        #expect(recoveredSession != nil)
    }
}
