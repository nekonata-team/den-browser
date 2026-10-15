import AppKit
import DenApplication
import DenDomain
import DenInfrastructure
import DenPresentationModels
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
        #expect(!manager.isPrivateDen)

        let personalController = try #require(manager.controller(for: personal.id))
        #expect(manager.profileID(for: personalController) == personal.id)
        #expect(
            ProfileColor.presets.allSatisfy {
                let rgb = profileRGB(for: $0)
                return rgb.red > 0 || rgb.green > 0 || rgb.blue > 0
            })
    }

    @Test func ephemeralProfileManagerKeepsProfileAndDenStateInMemory() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            initialProfile: PersistedProfile(
                profile: ProfileState(
                    id: ProfileID(),
                    name: "Private Den",
                    color: .gray,
                    webProfileStore: .default),
                den: .sample),
            isEphemeral: true,
            websiteDataStore: { _ in .nonPersistent() })
        let profile = try #require(manager.profiles.first)
        let controller = try #require(manager.controller(for: profile.id))

        _ = controller.createBoard(urlString: "https://example.com/private")

        #expect(profile.name == "Private Den")
        #expect(manager.isPrivateDen)
        #expect(controller.focusedDesk?.boards.count == 1)
        #expect(controller.save())
        #expect(manager.profileSaveCount == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test(arguments: [false, true])
    func overviewSnapshotsPersistOnlyForOrdinaryProfiles(isEphemeral: Bool) async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory, isEphemeral: isEphemeral)
        let profileID = manager.personalProfileID
        let controller = try #require(manager.controller(for: profileID))
        let board = board("Snapshot")
        controller.storage.state.desks[0].boards = [board]
        controller.storage.state.desks[0].focusedBoardID = board.id
        #expect(controller.save())
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 12, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        let image = NSImage(size: CGSize(width: 16, height: 12))
        image.addRepresentation(bitmap)

        // Act
        controller.facingCache.setFacing(image, for: board.id)
        await controller.facingCache.flushPendingWrites()
        let restoredManager = makeProfileManager(directory: directory, isEphemeral: isEphemeral)
        let restoredController = try #require(restoredManager.controller(for: restoredManager.personalProfileID))
        await restoredController.facingCache.loadFacing(for: board.id)

        // Assert
        #expect((restoredController.facingCache.image(for: board.id) != nil) == !isEphemeral)
        #expect(
            FileManager.default.fileExists(atPath: directory.appending(path: "BoardFacings").path) == !isEphemeral
        )
        #expect(restoredController.webRuntimes.isEmpty)
        #expect(restoredController.terminalRuntimes.isEmpty)
    }

    @Test func extensionHostStaysUnloadedForEmptyAndTerminalStores() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(
            directory: directory,
            isEphemeral: true,
            webExtensionDescriptors: [extensionFixtureDescriptor()],
            uBOLiteEnabled: true)
        defer { manager.setUBOLiteEnabled(false) }
        let profileID = manager.personalProfileID
        let controller = try #require(manager.controller(for: profileID))
        #expect(controller.webExtensionHost == nil)
        let terminal = BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Terminal", boards: [terminal], focusedBoardID: terminal.id)
        controller.storage.state = DenState(
            desks: [desk],
            focusedDeskID: desk.id)
        let window = NSWindow()
        let route = ProfileWindowRoute(windowID: profileID.rawValue, profileID: profileID)
        defer { manager.unregister(window: window, for: route) }

        // Act
        manager.register(window: window, for: route)
        manager.focusWebExtensionWindow(for: route)
        manager.setUBOLiteEnabled(false)
        manager.setUBOLiteEnabled(true)

        // Assert
        #expect(controller.webExtensionHost == nil)
        #expect(controller.webExtensionWindow == nil)
    }

    @Test func firstWebRuntimeLoadsOneSharedHostAcrossProfileWindows() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(
            directory: directory,
            isEphemeral: true,
            webExtensionDescriptors: [extensionFixtureDescriptor()])
        defer { manager.setUBOLiteEnabled(false) }
        let profileID = manager.personalProfileID
        let firstRoute = ProfileWindowRoute(windowID: profileID.rawValue, profileID: profileID)
        let first = try #require(manager.controller(for: firstRoute))
        manager.setUBOLiteEnabled(true)
        let sourceDeskID = first.presentedDeskID
        let boardID = try #require(
            first.createBoard(urlString: URL(fileURLWithPath: #filePath).absoluteString))
        let board = try #require(first.board(for: boardID))
        let firstRuntime = first.webRuntime(for: board)
        first.createDesk(label: "Second", preset: .empty)
        let secondRoute = try #require(
            manager.routeForOpeningDesk(
                sourceDeskID,
                profileID: profileID,
                sourceWindowID: firstRoute.windowID))
        let second = try #require(manager.controller(for: secondRoute))

        #expect(first.webExtensionHost != nil)
        #expect(second.webExtensionHost == nil)

        // Act
        let secondRuntime = second.webRuntime(for: board)

        // Assert
        #expect(firstRuntime === secondRuntime)
        #expect(first.webExtensionHost?.controller === second.webExtensionHost?.controller)
        #expect(first.webExtensionWindow !== second.webExtensionWindow)
        #expect(first.webExtensionWindow?.tabs.isEmpty == true)
        #expect(second.webExtensionWindow?.tabs.count == 1)
    }

    @Test func drawerPeekRequestsHost() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(
            directory: directory,
            isEphemeral: true,
            webExtensionDescriptors: [extensionFixtureDescriptor()])
        let profileID = manager.personalProfileID
        let controller = try #require(manager.controller(for: profileID))
        let fileURL = URL(fileURLWithPath: #filePath)
        let itemID = try #require(controller.keepInDrawer(fileURL, opensDrawer: false))
        let item = try #require(controller.state.drawerItems.first { $0.id == itemID })
        manager.setUBOLiteEnabled(true)
        defer { manager.setUBOLiteEnabled(false) }

        // Act
        let firstPeek = controller.drawerRuntime(for: item)

        // Assert
        #expect(controller.webExtensionHost != nil)
        #expect(controller.webExtensionWindow?.tabs.count == 1)
        #expect(firstPeek.id == item.id)
    }

    @Test func disablingExtensionDisconnectsLiveDrawerPeek() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(
            directory: directory,
            isEphemeral: true,
            webExtensionDescriptors: [extensionFixtureDescriptor()])
        let controller = try #require(manager.controller(for: manager.personalProfileID))
        let itemID = try #require(controller.keepInDrawer(URL(fileURLWithPath: #filePath), opensDrawer: false))
        let item = try #require(controller.state.drawerItems.first { $0.id == itemID })
        manager.setUBOLiteEnabled(true)
        let peek = controller.drawerRuntime(for: item)
        defer { manager.setUBOLiteEnabled(false) }

        // Act
        manager.setUBOLiteEnabled(false)

        // Assert
        #expect(controller.drawerPeekRuntime == nil)
        #expect(controller.webExtensionHost == nil)
        #expect(peek.webView.navigationDelegate == nil)
    }

    @Test func enablingExtensionAppliesToExistingWebRuntimeDemand() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(
            directory: directory,
            isEphemeral: true,
            webExtensionDescriptors: [extensionFixtureDescriptor()])
        let controller = try #require(manager.controller(for: manager.personalProfileID))
        let board = BoardState(label: "Web", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        controller.storage.state = DenState(desks: [desk], focusedDeskID: desk.id)
        _ = controller.webRuntime(for: board)
        defer { manager.setUBOLiteEnabled(false) }
        #expect(controller.webExtensionHost == nil)

        // Act
        manager.setUBOLiteEnabled(true)
        _ = controller.webRuntime(for: board)

        // Assert
        #expect(controller.webExtensionHost != nil)
        #expect(controller.webExtensionWindow?.tabs.count == 1)
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
        let workController = try #require(manager.controller(for: work.id))
        workController.createDesk(label: "Restored", preset: .empty)
        let restored = makeProfileManager(directory: directory)

        // Assert
        #expect(updated)
        #expect(restored.profiles.map(\.name) == ["Personal", "Office", "Work"])
        #expect(restored.controller(for: work.id)?.focusedDesk?.label == "Restored")
    }

    @Test func profileWindowsShareDenAndPresentDistinctDesks() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let sourceRoute = ProfileWindowRoute(windowID: profileID.rawValue, profileID: profileID)
        let source = try #require(manager.controller(for: sourceRoute))
        source.createDesk(label: "Second", preset: .empty)
        let detachedDeskID = source.presentedDeskID

        // Act
        let detachedRoute = try #require(
            manager.routeForOpeningDesk(
                detachedDeskID,
                profileID: profileID,
                sourceWindowID: sourceRoute.windowID))
        let detached = try #require(manager.controller(for: detachedRoute))

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
        let missingID = ProfileID()

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
        let personalController = try #require(manager.controller(for: manager.personalProfileID))
        let work = try #require(manager.createProfile(name: "Work", color: .green))
        let workController = try #require(manager.controller(for: work.id))

        // Act
        _ = personalController.createBoard(urlString: "https://example.com/bookmark?one=1")
        let saveResult = personalController.saveFocusedDeskAsPreset(label: "Reading")
        let restored = makeProfileManager(directory: directory)

        // Assert
        #expect(saveResult == .created)
        #expect(restored.controller(for: manager.personalProfileID)?.deskPresets.map(\.label) == ["Reading"])
        #expect(restored.controller(for: work.id)?.deskPresets.isEmpty == true)
        #expect(workController.deskPresets.isEmpty)
    }

    @Test func personalCannotBeDeletedAndAdditionalProfileCan() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
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
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var removedWebsiteData = false
        var removedExtensionData = false
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: makeTestDefaults(), scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in removedWebsiteData = true },
            removeExtensionData: { _ in removedExtensionData = true },
            websiteDataStore: { _ in .nonPersistent() })
        let work = try #require(manager.createProfile(name: "Work", color: .gray))
        let route = ProfileWindowRoute(profileID: work.id)
        let window = NSWindow()
        if hasRegisteredWindow {
            manager.register(window: window, for: route)
        } else {
            _ = try #require(manager.controller(for: route))
        }

        // Act
        let deleted = await manager.deleteProfile(work.id)

        // Assert
        #expect(!manager.canDeleteProfile(work.id))
        #expect(!deleted)
        #expect(!removedWebsiteData)
        #expect(!removedExtensionData)
        #expect(manager.profile(id: work.id) != nil)
        #expect(FileManager.default.fileExists(atPath: profileURL(work.id, in: directory).path))
    }

    @Test func closingProfileWindowMakesDeletionAvailable() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .gray))
        let route = ProfileWindowRoute(profileID: work.id)
        let window = NSWindow()
        _ = try #require(manager.controller(for: route))
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
        let directory = temporaryProfileDirectory()
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
            websiteDataStore: { _ in .nonPersistent() })
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
        let controller = manager.controller(for: work.id)
        let personalOpened = manager.openWindow(for: manager.personalProfileID)
        resumeRemoval?.resume()
        let deleted = await deletion?.value

        // Assert
        #expect(!canDeleteWhileWaiting)
        #expect(!canOpenWhileWaiting)
        #expect(!reopened)
        #expect(controller == nil)
        #expect(!duplicateDeleted)
        #expect(removalCount == 1)
        #expect(personalOpened)
        #expect(openedProfiles == [manager.personalProfileID])
        #expect(deleted == !fails)
        #expect(manager.canDeleteProfile(work.id) == fails)
        #expect(manager.canOpenWindow(for: work.id) == fails)
        if fails {
            #expect(manager.openWindow(for: work.id))
            #expect(manager.controller(for: work.id) != nil)
        }
    }

    @Test func canOpenWindowReportsAvailability() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: makeTestDefaults(), scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            websiteDataStore: { _ in .nonPersistent() })

        // Assert
        #expect(manager.canOpenWindow(for: manager.personalProfileID))
        #expect(!manager.canOpenWindow(for: ProfileID()))
    }

    @Test func failedExtensionDataDeletionKeepsProfileForRetry() async throws {
        // Arrange
        struct ExpectedError: Error {}
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: makeTestDefaults(), scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in },
            removeExtensionData: { _ in throw ExpectedError() },
            websiteDataStore: { _ in .nonPersistent() })
        let work = try #require(manager.createProfile(name: "Work", color: .gray))

        // Act
        let deleted = await manager.deleteProfile(work.id)

        // Assert
        #expect(!deleted)
        #expect(manager.errorMessage != nil)
        #expect(manager.profile(id: work.id) != nil)
        #expect(FileManager.default.fileExists(atPath: profileURL(work.id, in: directory).path))
    }

    @Test func failedWebsiteDataDeletionRestoresProfileDocument() async throws {
        // Arrange
        struct ExpectedError: Error {}
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let navigation = SheetNavigationManager(
            defaults: makeTestDefaults(),
            scriptSource: "")
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in throw ExpectedError() },
            websiteDataStore: { _ in .nonPersistent() })
        let work = try #require(manager.createProfile(name: "Work", color: .gray))

        // Act
        let deleted = await manager.deleteProfile(work.id)

        // Assert
        #expect(!deleted)
        #expect(manager.profile(id: work.id) != nil)
        #expect(manager.controller(for: work.id) != nil)
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
        let mismatchedURL = profileURL(ProfileID(), in: directory)
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
        let uppercaseURL = directory.appending(path: "\(work.id.rawValue.uuidString.uppercased()).json")
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
        let controller = try #require(manager.controller(for: personalID))
        _ = controller.createBoard(urlString: "https://example.com")
        let boardID = try #require(controller.focusedDesk?.focusedBoardID)

        // Act
        controller.removeFocusedBoard()
        let restored = makeProfileManager(directory: directory)

        // Assert
        #expect(controller.recentlyRemovedBoards.first?.board.id == boardID)
        #expect(restored.controller(for: personalID)?.focusedDesk?.boards.contains { $0.id == boardID } == false)
        #expect(restored.controller(for: personalID)?.recentlyRemovedBoards.isEmpty == true)
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
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let second = try #require(manager.createProfile(name: "Second", color: .pink))
        let firstController = try #require(manager.controller(for: manager.personalProfileID))
        let secondController = try #require(manager.controller(for: second.id))
        let firstBoard = board("First")
        let secondBoard = board("Second")
        firstController.storage.state = DenState(desks: [desk("First", boards: [firstBoard])], focusedDeskID: DeskID())
        firstController.focusDesk(firstController.state.desks[0].id)
        secondController.storage.state = DenState(
            desks: [desk("Second", boards: [secondBoard])], focusedDeskID: DeskID())
        secondController.focusDesk(secondController.state.desks[0].id)
        let firstWebView = firstController.webRuntime(for: firstBoard).webView
        let secondWebView = secondController.webRuntime(for: secondBoard).webView

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
            firstController.focusedDesk?.boards.contains {
                $0.currentSheetURL == URL(string: "https://first.example/")
            } == true)
        #expect(
            secondController.focusedDesk?.boards.contains {
                $0.currentSheetURL == URL(string: "https://second.example/")
            } == true)
        #expect(
            firstController.focusedDesk?.boards.contains {
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

    @Test func unsupportedProfileSchemaIsKeptAndReported() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let profileURL = profileURL(work.id, in: directory)
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: profileURL)) as? [String: Any])
        object["schemaVersion"] = PersistedProfile.currentSchemaVersion + 1
        let unsupportedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try unsupportedData.write(to: profileURL)

        // Act
        let restored = makeProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        // Assert
        #expect(try Data(contentsOf: profileURL) == unsupportedData)
        #expect(!names.contains { $0.hasPrefix("\(profileURL.lastPathComponent).corrupt-") })
        #expect(restored.profile(id: work.id) == nil)
        #expect(restored.errorMessage?.contains("unsupported schema version") == true)
    }

    @Test func unreadableProfileIsKeptAndReported() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let profileURL = profileURL(work.id, in: directory)
        try FileManager.default.removeItem(at: profileURL)
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: false)

        // Act
        let restored = makeProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        // Assert
        #expect(FileManager.default.fileExists(atPath: profileURL.path))
        #expect(!names.contains { $0.hasPrefix("\(profileURL.lastPathComponent).corrupt-") })
        #expect(restored.profile(id: work.id) == nil)
        #expect(restored.errorMessage?.contains("Could not read Profile") == true)
    }

    @Test func failedProfileQuarantineIsReportedWithoutRewritingIndex() throws {
        // Arrange
        struct ExpectedError: Error {}
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let profileURL = profileURL(work.id, in: directory)
        let indexURL = directory.appending(path: "profile-index.json")
        let indexData = try Data(contentsOf: indexURL)
        try Data("broken".utf8).write(to: profileURL)

        // Act
        let restored = makeProfileManager(
            directory: directory,
            quarantineFile: { _, _ in throw ExpectedError() })

        // Assert
        #expect(restored.profile(id: work.id) == nil)
        #expect(try Data(contentsOf: profileURL) == Data("broken".utf8))
        #expect(try Data(contentsOf: indexURL) == indexData)
        #expect(restored.errorMessage?.contains("Could not quarantine") == true)
    }

    @Test func duplicateProfileIDsInIndexAreQuarantinedAndRebuilt() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let indexURL = directory.appending(path: "profile-index.json")
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any])
        object["profileIDs"] = [
            manager.personalProfileID.rawValue.uuidString,
            manager.personalProfileID.rawValue.uuidString,
        ]
        try JSONSerialization.data(withJSONObject: object).write(to: indexURL)

        // Act
        let restored = makeProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let rebuiltIndex = try JSONDecoder().decode(ProfileIndex.self, from: Data(contentsOf: indexURL))

        // Assert
        #expect(restored.profile(id: work.id) != nil)
        #expect(Set(rebuiltIndex.profileIDs).count == rebuiltIndex.profileIDs.count)
        #expect(names.contains { $0.hasPrefix("profile-index.json.corrupt-") })
    }

    @Test func clearBrowsingDataRequestsSelectedWebsiteDataTypes() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let navigation = SheetNavigationManager(
            defaults: makeTestDefaults(),
            scriptSource: "")
        var removedTypes: Set<String>?
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeWebsiteDataTypes: { _, types in
                removedTypes = types
            },
            websiteDataStore: { _ in .nonPersistent() })
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
        let controller = try #require(manager.controller(for: manager.personalProfileID))
        let targetURL = URL(string: "https://example.com/updated")

        // Act
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        _ = controller.createBoard(urlString: "https://example.com/updated")
        #expect(manager.errorMessage != nil)
        #expect(controller.latestFeedback?.severity == .error)
        #expect(controller.latestFeedback?.body == manager.errorMessage)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #expect(controller.saveDeskPresets())

        // Assert
        let restored = makeProfileManager(directory: directory)
        let recontrollerdController = try #require(restored.controller(for: manager.personalProfileID))
        #expect(recontrollerdController.focusedDesk?.boards.contains { $0.currentSheetURL == targetURL } == true)
    }

    @Test func boardAndRecentArePersistedInOneProfileWrite() throws {
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let controller = try #require(manager.controller(for: manager.personalProfileID))
        let url = try #require(URL(string: "https://example.com/aggregated"))

        let writesBefore = manager.profileSaveCount
        _ = controller.createBoard(urlString: url.absoluteString, recentItem: .url(url))

        #expect(manager.profileSaveCount == writesBefore + 1)

        let restored = makeProfileManager(directory: directory)
        let recontrollerdController = try #require(restored.controller(for: manager.personalProfileID))
        #expect(recontrollerdController.focusedDesk?.boards.contains { $0.currentSheetURL == url } == true)
        #expect(recontrollerdController.recentItems == [.url(url)])
    }

    @Test func deferredSaveWaitsUntilChangesAreQuietAndWritesLatestStateOnce() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let controller = try #require(manager.controller(for: manager.personalProfileID))
        let firstDeskID = try #require(controller.state.desks.first?.id)
        controller.createDesk(label: "Second", preset: .empty)
        let secondDeskID = try #require(controller.state.desks.last?.id)
        let writesBefore = manager.profileSaveCount

        // Act
        controller.focusDesk(firstDeskID)
        try await Task.sleep(for: .milliseconds(200))
        controller.focusDesk(secondDeskID)
        #expect(manager.profileSaveCount == writesBefore)
        try await Task.sleep(for: .milliseconds(200))
        #expect(manager.profileSaveCount == writesBefore)

        let saveDeadline = ContinuousClock.now + .seconds(2)
        while manager.profileSaveCount == writesBefore, ContinuousClock.now < saveDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Assert
        #expect(manager.profileSaveCount == writesBefore + 1)
        let restored = makeProfileManager(directory: directory)
        #expect(restored.controller(for: manager.personalProfileID)?.state.focusedDeskID == secondDeskID)
    }

    @Test func boardWidthAdjustmentsShareDeferredSaveAndSkipUnchangedWidths() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let controller = try #require(manager.controller(for: profileID))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let first = board("First", width: BoardState.maximumWidth)
        let second = board("Second", width: BoardState.maximumWidth)
        controller.storage.state.desks[0].boards = [first, second]
        controller.storage.state.desks[0].focusedBoardID = first.id
        #expect(controller.save())
        let writesBefore = manager.profileSaveCount

        // Act
        windowModel.adjustFocusedDeskBoardWidths(by: 10)
        #expect(manager.profileSaveCount == writesBefore)
        windowModel.maximizedBoardID = first.id
        windowModel.adjustFocusedBoardWidth(by: 20)
        #expect(windowModel.maximizedBoardID == nil)
        #expect(manager.profileSaveCount == writesBefore)
        windowModel.adjustFocusedBoardWidth(by: -20)
        try await Task.sleep(for: .milliseconds(100))
        windowModel.adjustFocusedDeskBoardWidths(by: 10)
        #expect(manager.profileSaveCount == writesBefore)
        let saveDeadline = ContinuousClock.now + .seconds(2)
        while manager.profileSaveCount == writesBefore, ContinuousClock.now < saveDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Assert
        #expect(manager.profileSaveCount == writesBefore + 1)
        let restored = try #require(makeProfileManager(directory: directory).controller(for: profileID))
        #expect(restored.state.desks[0].boards.map(\.width) == [BoardState.maximumWidth - 10, BoardState.maximumWidth])
    }

    @Test func successfulImmediateSaveCancelsPendingDeferredSave() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let controller = try #require(manager.controller(for: manager.personalProfileID))
        let firstDeskID = try #require(controller.state.desks.first?.id)
        controller.createDesk(label: "Second", preset: .empty)
        let writesBefore = manager.profileSaveCount

        // Act
        controller.focusDesk(firstDeskID)
        #expect(controller.saveDeskPresets())
        try await Task.sleep(for: .milliseconds(50))

        // Assert
        #expect(manager.profileSaveCount == writesBefore + 1)
        let restored = makeProfileManager(directory: directory)
        #expect(restored.controller(for: manager.personalProfileID)?.state.focusedDeskID == firstDeskID)
    }

    @Test func flushPendingDeferredSavesWritesBeforeReturning() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let controller = try #require(manager.controller(for: manager.personalProfileID))
        let firstDeskID = try #require(controller.state.desks.first?.id)
        controller.createDesk(label: "Second", preset: .empty)
        let writesBefore = manager.profileSaveCount

        // Act
        controller.focusDesk(firstDeskID)
        manager.flushPendingDeferredSaves()

        // Assert
        #expect(manager.profileSaveCount == writesBefore + 1)
        let restored = makeProfileManager(directory: directory)
        #expect(restored.controller(for: manager.personalProfileID)?.state.focusedDeskID == firstDeskID)
    }

    @Test func flushDuringBoardDragWritesTheLastStableProfileSnapshot() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let controller = try #require(manager.controller(for: profileID))
        let composition = DenWindowComposition(controller: controller)
        composition.connect()
        defer { composition.disconnect() }
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let deskState = desk("Main", boards: [firstBoard, secondBoard], focusedBoardID: firstBoard.id)
        controller.storage.state = DenState(desks: [deskState], focusedDeskID: deskState.id)
        #expect(controller.save())
        let writesBefore = manager.profileSaveCount

        // Act
        controller.focusBoard(secondBoard.id)
        #expect(controller.beginBoardDrag(firstBoard.id))
        controller.previewBoardMove(secondBoard.id, to: BoardIndex(rawValue: 0))
        manager.flushPendingDeferredSaves()

        // Assert
        #expect(manager.profileSaveCount == writesBefore + 1)
        let restored = try #require(makeProfileManager(directory: directory).controller(for: profileID))
        #expect(restored.focusedDesk?.focusedBoardID == secondBoard.id)
        #expect(restored.focusedDesk?.boards.map(\.id) == [firstBoard.id, secondBoard.id])
    }

    @Test func immediatePresetSaveDuringBoardDragKeepsStableDeskOrder() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let controller = try #require(manager.controller(for: profileID))
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let deskState = desk("Main", boards: [firstBoard, secondBoard], focusedBoardID: firstBoard.id)
        controller.storage.state = DenState(desks: [deskState], focusedDeskID: deskState.id)
        #expect(controller.save())

        // Act
        controller.focusBoard(secondBoard.id)
        #expect(controller.beginBoardDrag(firstBoard.id))
        controller.previewBoardMove(secondBoard.id, to: BoardIndex(rawValue: 0))
        #expect(controller.saveDeskPresets())

        // Assert
        let restored = try #require(makeProfileManager(directory: directory).controller(for: profileID))
        #expect(restored.focusedDesk?.focusedBoardID == secondBoard.id)
        #expect(restored.focusedDesk?.boards.map(\.id) == [firstBoard.id, secondBoard.id])
    }

    @Test func expiredDeferredSaveWaitsForOverviewDragCancellation() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let controller = try #require(manager.controller(for: profileID))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let firstBoard = board("First")
        let secondBoard = board("Second")
        let deskState = desk("Main", boards: [firstBoard, secondBoard], focusedBoardID: firstBoard.id)
        controller.storage.state = DenState(desks: [deskState], focusedDeskID: deskState.id)
        #expect(controller.save())
        let writesBefore = manager.profileSaveCount

        // Act
        controller.focusBoard(secondBoard.id)
        windowModel.showOverview()
        #expect(windowModel.beginOverviewBoardDrag(firstBoard.id))
        try await Task.sleep(for: .milliseconds(350))
        #expect(manager.profileSaveCount == writesBefore)
        windowModel.overview.cancelBoardDrag()
        let dragSaveDeadline = ContinuousClock.now + .seconds(2)
        while manager.profileSaveCount == writesBefore, ContinuousClock.now < dragSaveDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Assert
        #expect(manager.profileSaveCount == writesBefore + 1)
        let restored = try #require(makeProfileManager(directory: directory).controller(for: profileID))
        #expect(restored.focusedDesk?.focusedBoardID == secondBoard.id)
    }

    @Test func failedImmediateSaveKeepsPendingDeferredSave() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let controller = try #require(manager.controller(for: profileID))
        let firstDeskID = try #require(controller.state.desks.first?.id)
        controller.createDesk(label: "Second", preset: .empty)
        let writesBefore = manager.profileSaveCount
        let profileURL = directory.appending(path: "\(profileID.rawValue.uuidString.lowercased()).json")
        try FileManager.default.removeItem(at: profileURL)
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: false)

        // Act
        controller.focusDesk(firstDeskID)
        #expect(!controller.saveDeskPresets())
        #expect(manager.errorMessage != nil)
        try FileManager.default.removeItem(at: profileURL)
        let failedSaveDeadline = ContinuousClock.now + .seconds(2)
        while manager.profileSaveCount < writesBefore + 2, ContinuousClock.now < failedSaveDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Assert
        #expect(manager.profileSaveCount == writesBefore + 2)
        let restored = makeProfileManager(directory: directory)
        #expect(restored.controller(for: profileID)?.state.focusedDeskID == firstDeskID)
    }

    @Test func multipleWindowsRetainSharedRuntimesWhenNonFinalWindowCloses() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let route1 = ProfileWindowRoute(windowID: UUID(), profileID: profileID)
        let window1 = NSWindow()
        let window2 = NSWindow()

        let controller1 = try #require(manager.controller(for: route1))
        manager.register(window: window1, for: route1)
        controller1.createDesk(label: "SecondDesk", preset: .empty)
        let secondDeskID = controller1.presentedDeskID

        let route2 = try #require(
            manager.routeForOpeningDesk(
                secondDeskID,
                profileID: profileID,
                sourceWindowID: route1.windowID))
        let controller2 = try #require(manager.controller(for: route2))
        manager.register(window: window2, for: route2)

        let targetBoard = board("SharedBoard")
        controller1.storage.state = DenState(desks: [desk("Main", boards: [targetBoard])], focusedDeskID: DeskID())
        controller1.focusDesk(controller1.state.desks[0].id)
        let runtime = controller1.webRuntime(for: targetBoard)

        // Act
        manager.unregister(window: window1, for: route1)

        // Assert
        #expect(runtime.webView.navigationDelegate != nil)
        #expect(controller2.storage.webRuntimes[targetBoard.id] === runtime)
    }

    @Test func sharedRuntimeDeliversEventsAfterItsOwnerWindowCloses() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let route1 = ProfileWindowRoute(windowID: UUID(), profileID: profileID)
        let window1 = NSWindow()
        let window2 = NSWindow()
        var owner: DenController? = manager.controller(for: route1)
        manager.register(window: window1, for: route1)
        let firstDeskID = try #require(owner?.presentedDeskID)
        owner?.createDesk(label: "SecondDesk", preset: .empty)
        let secondDeskID = try #require(owner?.presentedDeskID)
        let route2 = try #require(
            manager.routeForOpeningDesk(
                secondDeskID,
                profileID: profileID,
                sourceWindowID: route1.windowID))
        let otherWindowController = try #require(manager.controller(for: route2))
        manager.register(window: window2, for: route2)

        let targetBoard = BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
        let firstDeskIndex = try #require(owner?.state.desks.firstIndex { $0.id == firstDeskID })
        owner?.storage.state.desks[firstDeskIndex].boards = [targetBoard]
        owner?.storage.state.desks[firstDeskIndex].focusedBoardID = targetBoard.id
        owner?.focusDesk(firstDeskID)
        let runtime = try #require(owner?.terminalRuntime(for: targetBoard))
        let storage = try #require(owner?.storage)

        // Act
        manager.unregister(window: window1, for: route1)
        owner = nil
        runtime.terminalDidChangeTitle("Updated after close")

        // Assert
        #expect(storage.state.desks.first { $0.id == firstDeskID }?.boards.first?.label == "Updated after close")
        #expect(otherWindowController.storage === storage)
    }

    @Test func retainedStorageAndRuntimeDoNotKeepStoreAliveAfterProfileManagerDeallocates() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var manager: ProfileManager? = makeProfileManager(directory: directory)
        let profileID = try #require(manager?.personalProfileID)
        let route = ProfileWindowRoute(windowID: UUID(), profileID: profileID)
        var controller: DenController? = manager?.controller(for: route)
        let targetBoard = board("TargetBoard")
        let targetDesk = desk("Main", boards: [targetBoard])
        controller?.storage.state = DenState(desks: [targetDesk], focusedDeskID: targetDesk.id)
        controller?.focusDesk(targetDesk.id)
        let runtime = try #require(controller?.webRuntime(for: targetBoard))
        let storage = try #require(controller?.storage)
        weak let weakController = controller

        // Act
        controller = nil
        manager = nil

        // Assert
        #expect(weakController == nil)
        #expect(storage.webRuntimes[targetBoard.id] === runtime)
    }

    @Test func closingFinalWindowReleasesSharedRuntimes() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let route = ProfileWindowRoute(windowID: UUID(), profileID: profileID)
        let window = NSWindow()

        let controller = try #require(manager.controller(for: route))
        manager.register(window: window, for: route)

        let targetBoard = board("TargetBoard")
        controller.storage.state = DenState(desks: [desk("Main", boards: [targetBoard])], focusedDeskID: DeskID())
        controller.focusDesk(controller.state.desks[0].id)
        let runtime = controller.webRuntime(for: targetBoard)

        // Act
        manager.unregister(window: window, for: route)

        // Assert
        #expect(runtime.webView.navigationDelegate == nil)
    }

    @Test func failedProfileDeletionPreservesProfileState() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        struct RemovalError: Error {}
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in throw RemovalError() },
            websiteDataStore: { _ in .nonPersistent() })

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
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        struct RemovalError: Error {}
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in throw RemovalError() },
            websiteDataStore: { _ in .nonPersistent() })

        let profile = try #require(manager.createProfile(name: "TestProfile", color: .green))
        _ = await manager.deleteProfile(profile.id)

        // Act
        let recoveredController = manager.controller(for: profile.id)

        // Assert
        #expect(recoveredController != nil)
    }

    private func temporaryProfileDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "den-browser-profile-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func profileURL(_ id: ProfileID, in directory: URL) -> URL {
        directory.appending(path: "\(id.rawValue.uuidString.lowercased()).json")
    }

    private func makeProfileManager(
        directory: URL,
        quarantineFile: ((URL, URL) throws -> Void)? = nil,
        isEphemeral: Bool = false,
        webExtensionDescriptors: [WebExtensionDescriptor] = [],
        uBOLiteEnabled: Bool = false
    ) -> ProfileManager {
        let suiteName = "ProfileManagerPreferences-\(UUID().uuidString)"
        let defaults = makeTestDefaults(suiteName: suiteName)
        let preferences = AppPreferences(defaults: defaults)
        if uBOLiteEnabled { preferences.setUBOLiteEnabled(true) }
        let navigation = SheetNavigationManager(
            defaults: defaults,
            scriptSource: "")
        return ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            preferences: preferences,
            removeDataStore: { _ in },
            removeExtensionData: { profileID in
                try ProfileExtensionDataStore.remove(
                    profileID, directoryURL: directory.appending(path: "WebExtensions"))
            },
            isEphemeral: isEphemeral,
            websiteDataStore: { _ in .nonPersistent() },
            webExtensionDescriptors: webExtensionDescriptors,
            quarantineFile: quarantineFile ?? { source, destination in
                try FileManager.default.moveItem(at: source, to: destination)
            })
    }

    private func extensionFixtureDescriptor() -> WebExtensionDescriptor {
        WebExtensionDescriptor(
            identifier: "test.extension",
            directoryURL: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Fixtures/MV3Extension", directoryHint: .isDirectory))
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: BoardID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: URL(string: url))
    }
}
