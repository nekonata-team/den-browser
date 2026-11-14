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
struct ProfileManagerPersistenceTests {
    @Test(arguments: [false, true])
    func overviewSnapshotsPersistOnlyForOrdinaryProfiles(isEphemeral: Bool) async throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory, isEphemeral: isEphemeral)
        let profileID = manager.personalProfileID
        let session = try #require(manager.session(for: profileID))
        let board = makeTestBoard("Snapshot")
        session.resources.state.desks[0].boards = [board]
        session.resources.state.desks[0].focusedBoardID = board.id
        #expect(session.resources.save())
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 16,
                pixelsHigh: 12,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let image = NSImage(size: CGSize(width: 16, height: 12))
        image.addRepresentation(bitmap)

        // Act
        session.resources.facingCache.setFacing(image, for: board.id)
        await session.resources.facingCache.flushPendingWrites()
        let restoredManager = makeTestProfileManager(directory: directory, isEphemeral: isEphemeral)
        let restoredSession = try #require(restoredManager.session(for: restoredManager.personalProfileID))
        await restoredSession.resources.facingCache.loadFacing(for: board.id)

        // Assert
        #expect((restoredSession.resources.facingCache.image(for: board.id) != nil) == !isEphemeral)
        #expect(
            FileManager.default.fileExists(atPath: directory.appending(path: "BoardFacings").path) == !isEphemeral
        )
        #expect(restoredSession.resources.webRuntimes.isEmpty)
        #expect(restoredSession.resources.terminalRuntimes.isEmpty)
    }

    @Test func emptyPersistedDenRecoversAndSavesOneDesk() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profile = try #require(manager.profiles.first)
        let persistence = ProfilePersistence(
            directoryURL: directory,
            isEphemeral: false,
            quarantineFile: ProfilePersistence.moveFileToQuarantine
        )
        try persistence.save(
            PersistedProfile(
                profile: profile,
                den: DenState(desks: [], focusedDeskID: DeskID())
            )
        )

        // Act
        let restored = makeTestProfileManager(directory: directory)
        let session = try #require(restored.session(for: profile.id))
        let saved = try JSONDecoder().decode(
            PersistedProfile.self,
            from: Data(contentsOf: makeProfileURL(profile.id, in: directory))
        )

        // Assert
        #expect(session.resources.state.desks.count == 1)
        #expect(session.navigation.focusedDesk != nil)
        #expect(saved.den == session.resources.state)
    }

    @Test func loadingDoesNotRewriteExistingProfileDocuments() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profileURL = makeProfileURL(manager.personalProfileID, in: directory)
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: profileURL)) as? [String: Any]
        )
        object["futureField"] = "preserved"
        let originalData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try originalData.write(to: profileURL)

        // Act
        _ = makeTestProfileManager(directory: directory)

        // Assert
        #expect(try Data(contentsOf: profileURL) == originalData)
    }

    @Test func profileManagerPersistsDeskPresetsPerProfile() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let personalSession = try #require(manager.session(for: manager.personalProfileID))
        let work = try #require(manager.createProfile(name: "Work", color: .green))
        let workSession = try #require(manager.session(for: work.id))

        // Act
        _ = personalSession.boardOpening.createBoard(urlString: "https://example.com/bookmark?one=1")
        let saveResult = personalSession.presets.saveFocusedDeskAsPreset(label: "Reading")
        let restored = makeTestProfileManager(directory: directory)

        // Assert
        #expect(saveResult == .created)
        #expect(restored.session(for: manager.personalProfileID)?.resources.deskPresets.map(\.label) == ["Reading"])
        #expect(restored.session(for: work.id)?.resources.deskPresets.isEmpty == true)
        #expect(workSession.resources.deskPresets.isEmpty)
    }

    @Test func mismatchedProfileFilenameIsQuarantined() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let mismatchedURL = makeProfileURL(ProfileID(), in: directory)
        try FileManager.default.moveItem(at: makeProfileURL(work.id, in: directory), to: mismatchedURL)

        // Act
        let restored = makeTestProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        // Assert
        #expect(restored.profile(id: work.id) == nil)
        #expect(names.contains { $0.hasPrefix("\(mismatchedURL.lastPathComponent).corrupt-") })
    }

    @Test func uppercaseProfileFilenameIsLoadedWithoutQuarantine() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let uppercaseURL = directory.appending(path: "\(work.id.rawValue.uuidString.uppercased()).json")
        try FileManager.default.moveItem(at: makeProfileURL(work.id, in: directory), to: uppercaseURL)

        // Act
        let restored = makeTestProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        // Assert
        #expect(restored.profile(id: work.id)?.name == "Work")
        #expect(!names.contains { $0.contains(".corrupt-") })
    }

    @Test func corruptIndexIsQuarantinedAndRebuiltFromProfiles() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let indexURL = directory.appending(path: "profile-index.json")
        try Data("broken".utf8).write(to: indexURL)

        // Act
        let restored = makeTestProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let rebuiltIndex = try JSONDecoder().decode(ProfileIndex.self, from: Data(contentsOf: indexURL))

        // Assert
        #expect(restored.profiles.contains { $0.id == work.id })
        #expect(names.contains { $0.hasPrefix("profile-index.json.corrupt-") })
        #expect(rebuiltIndex.profileIDs.count == 2)
    }

    @Test func unsupportedProfileSchemaIsKeptAndReported() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let profileURL = makeProfileURL(work.id, in: directory)
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: profileURL)) as? [String: Any]
        )
        object["schemaVersion"] = PersistedProfile.currentSchemaVersion + 1
        let unsupportedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try unsupportedData.write(to: profileURL)

        // Act
        let restored = makeTestProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        // Assert
        #expect(try Data(contentsOf: profileURL) == unsupportedData)
        #expect(!names.contains { $0.hasPrefix("\(profileURL.lastPathComponent).corrupt-") })
        #expect(restored.profile(id: work.id) == nil)
        #expect(restored.errorMessage?.contains("unsupported schema version") == true)
    }

    @Test func unreadableProfileIsKeptAndReported() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let profileURL = makeProfileURL(work.id, in: directory)
        try FileManager.default.removeItem(at: profileURL)
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: false)

        // Act
        let restored = makeTestProfileManager(directory: directory)
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
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let profileURL = makeProfileURL(work.id, in: directory)
        let indexURL = directory.appending(path: "profile-index.json")
        let indexData = try Data(contentsOf: indexURL)
        try Data("broken".utf8).write(to: profileURL)

        // Act
        let restored = makeTestProfileManager(
            directory: directory,
            quarantineFile: { _, _ in throw ExpectedError() }
        )

        // Assert
        #expect(restored.profile(id: work.id) == nil)
        #expect(try Data(contentsOf: profileURL) == Data("broken".utf8))
        #expect(try Data(contentsOf: indexURL) == indexData)
        #expect(restored.errorMessage?.contains("Could not quarantine") == true)
    }

    @Test func duplicateProfileIDsInIndexAreQuarantinedAndRebuilt() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let work = try #require(manager.createProfile(name: "Work", color: .purple))
        let indexURL = directory.appending(path: "profile-index.json")
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any]
        )
        object["profileIDs"] = [
            manager.personalProfileID.rawValue.uuidString,
            manager.personalProfileID.rawValue.uuidString,
        ]
        try JSONSerialization.data(withJSONObject: object).write(to: indexURL)

        // Act
        let restored = makeTestProfileManager(directory: directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let rebuiltIndex = try JSONDecoder().decode(ProfileIndex.self, from: Data(contentsOf: indexURL))

        // Assert
        #expect(restored.profile(id: work.id) != nil)
        #expect(Set(rebuiltIndex.profileIDs).count == rebuiltIndex.profileIDs.count)
        #expect(names.contains { $0.hasPrefix("profile-index.json.corrupt-") })
    }

    @Test func failedSaveRetainsLatestStateForSubsequentWrite() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let manager = makeTestProfileManager(directory: directory)
        let session = try #require(manager.session(for: manager.personalProfileID))
        let targetURL = URL(string: "https://example.com/updated")

        // Act
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        _ = session.boardOpening.createBoard(urlString: "https://example.com/updated")
        #expect(manager.errorMessage != nil)
        #expect(session.feedback.latest?.severity == .error)
        #expect(session.feedback.latest?.body == manager.errorMessage)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #expect(session.resources.saveDeskPresets())

        // Assert
        let restored = makeTestProfileManager(directory: directory)
        let restoredSession = try #require(restored.session(for: manager.personalProfileID))
        #expect(
            restoredSession.navigation.focusedDesk?.boards.contains { $0.currentSheetURL == targetURL } == true
        )
    }

    @Test func boardAndRecentArePersistedInOneProfileWrite() throws {
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let session = try #require(manager.session(for: manager.personalProfileID))
        let url = try #require(URL(string: "https://example.com/aggregated"))

        let writesBefore = manager.profileSaveCount
        _ = session.boardOpening.createBoard(urlString: url.absoluteString, recentItem: .url(url))

        #expect(manager.profileSaveCount == writesBefore + 1)

        let restored = makeTestProfileManager(directory: directory)
        let restoredSession = try #require(restored.session(for: manager.personalProfileID))
        #expect(restoredSession.navigation.focusedDesk?.boards.contains { $0.currentSheetURL == url } == true)
        #expect(restoredSession.resources.recentItems == [.url(url)])
    }

    @Test func deferredSaveWaitsUntilChangesAreQuietAndWritesLatestStateOnce() async throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let session = try #require(manager.session(for: manager.personalProfileID))
        let firstDeskID = try #require(session.resources.state.desks.first?.id)
        session.desks.createDesk(label: "Second", preset: .empty)
        let secondDeskID = try #require(session.resources.state.desks.last?.id)
        let writesBefore = manager.profileSaveCount

        // Act
        session.boardNavigation.focusDesk(firstDeskID)
        try await Task.sleep(for: .milliseconds(200))
        session.boardNavigation.focusDesk(secondDeskID)
        #expect(manager.profileSaveCount == writesBefore)
        try await Task.sleep(for: .milliseconds(200))
        #expect(manager.profileSaveCount == writesBefore)

        let saveDeadline = ContinuousClock.now + .seconds(2)
        while manager.profileSaveCount == writesBefore, ContinuousClock.now < saveDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Assert
        #expect(manager.profileSaveCount == writesBefore + 1)
        let restored = makeTestProfileManager(directory: directory)
        #expect(restored.session(for: manager.personalProfileID)?.resources.state.focusedDeskID == secondDeskID)
    }

    @Test func boardWidthAdjustmentsShareDeferredSaveAndSkipUnchangedWidths() async throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let session = try #require(manager.session(for: profileID))
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let first = makeTestBoard("First", width: BoardState.maximumWidth)
        let second = makeTestBoard("Second", width: BoardState.maximumWidth)
        session.resources.state.desks[0].boards = [first, second]
        session.resources.state.desks[0].focusedBoardID = first.id
        #expect(session.resources.save())
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
        let restored = try #require(makeTestProfileManager(directory: directory).session(for: profileID))
        #expect(
            restored.resources.state.desks[0].boards.map(\.width) == [
                BoardState.maximumWidth - 10, BoardState.maximumWidth,
            ]
        )
    }

    @Test func successfulImmediateSaveCancelsPendingDeferredSave() async throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let session = try #require(manager.session(for: manager.personalProfileID))
        let firstDeskID = try #require(session.resources.state.desks.first?.id)
        session.desks.createDesk(label: "Second", preset: .empty)
        let writesBefore = manager.profileSaveCount

        // Act
        session.boardNavigation.focusDesk(firstDeskID)
        #expect(session.resources.saveDeskPresets())
        try await Task.sleep(for: .milliseconds(50))

        // Assert
        #expect(manager.profileSaveCount == writesBefore + 1)
        let restored = makeTestProfileManager(directory: directory)
        #expect(restored.session(for: manager.personalProfileID)?.resources.state.focusedDeskID == firstDeskID)
    }

    @Test func flushPendingDeferredSavesWritesBeforeReturning() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let session = try #require(manager.session(for: manager.personalProfileID))
        let firstDeskID = try #require(session.resources.state.desks.first?.id)
        session.desks.createDesk(label: "Second", preset: .empty)
        let writesBefore = manager.profileSaveCount

        // Act
        session.boardNavigation.focusDesk(firstDeskID)
        manager.flushPendingDeferredSaves()

        // Assert
        #expect(manager.profileSaveCount == writesBefore + 1)
        let restored = makeTestProfileManager(directory: directory)
        #expect(restored.session(for: manager.personalProfileID)?.resources.state.focusedDeskID == firstDeskID)
    }

    @Test func flushDuringBoardDragWritesTheLastStableProfileSnapshot() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let session = try #require(manager.session(for: profileID))
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        let firstBoard = makeTestBoard("First")
        let secondBoard = makeTestBoard("Second")
        let deskState = makeTestDesk("Main", boards: [firstBoard, secondBoard], focusedBoardID: firstBoard.id)
        session.resources.state = DenState(desks: [deskState], focusedDeskID: deskState.id)
        #expect(session.resources.save())
        let writesBefore = manager.profileSaveCount

        // Act
        session.boardNavigation.focusBoard(secondBoard.id)
        #expect(session.boardNavigation.beginBoardDrag(firstBoard.id))
        session.resources.boardMovement.preview(
            secondBoard.id,
            to: BoardIndex(rawValue: 0),
            in: session.navigation.presentedDeskID
        )
        manager.flushPendingDeferredSaves()

        // Assert
        #expect(manager.profileSaveCount == writesBefore + 1)
        let restored = try #require(makeTestProfileManager(directory: directory).session(for: profileID))
        #expect(restored.navigation.focusedDesk?.focusedBoardID == secondBoard.id)
        #expect(restored.navigation.focusedDesk?.boards.map(\.id) == [firstBoard.id, secondBoard.id])
    }

    @Test func immediatePresetSaveDuringBoardDragKeepsStableDeskOrder() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let session = try #require(manager.session(for: profileID))
        let firstBoard = makeTestBoard("First")
        let secondBoard = makeTestBoard("Second")
        let deskState = makeTestDesk("Main", boards: [firstBoard, secondBoard], focusedBoardID: firstBoard.id)
        session.resources.state = DenState(desks: [deskState], focusedDeskID: deskState.id)
        #expect(session.resources.save())

        // Act
        session.boardNavigation.focusBoard(secondBoard.id)
        #expect(session.boardNavigation.beginBoardDrag(firstBoard.id))
        session.resources.boardMovement.preview(
            secondBoard.id,
            to: BoardIndex(rawValue: 0),
            in: session.navigation.presentedDeskID
        )
        #expect(session.resources.saveDeskPresets())

        // Assert
        let restored = try #require(makeTestProfileManager(directory: directory).session(for: profileID))
        #expect(restored.navigation.focusedDesk?.focusedBoardID == secondBoard.id)
        #expect(restored.navigation.focusedDesk?.boards.map(\.id) == [firstBoard.id, secondBoard.id])
    }

    @Test func expiredDeferredSaveWaitsForOverviewDragCancellation() async throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let session = try #require(manager.session(for: profileID))
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let firstBoard = makeTestBoard("First")
        let secondBoard = makeTestBoard("Second")
        let deskState = makeTestDesk("Main", boards: [firstBoard, secondBoard], focusedBoardID: firstBoard.id)
        session.resources.state = DenState(desks: [deskState], focusedDeskID: deskState.id)
        #expect(session.resources.save())
        let writesBefore = manager.profileSaveCount

        // Act
        session.boardNavigation.focusBoard(secondBoard.id)
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
        let restored = try #require(makeTestProfileManager(directory: directory).session(for: profileID))
        #expect(restored.navigation.focusedDesk?.focusedBoardID == secondBoard.id)
    }

    @Test func failedImmediateSaveKeepsPendingDeferredSave() async throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let session = try #require(manager.session(for: profileID))
        let firstDeskID = try #require(session.resources.state.desks.first?.id)
        session.desks.createDesk(label: "Second", preset: .empty)
        let writesBefore = manager.profileSaveCount
        let profileURL = directory.appending(path: "\(profileID.rawValue.uuidString.lowercased()).json")
        try FileManager.default.removeItem(at: profileURL)
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: false)

        // Act
        session.boardNavigation.focusDesk(firstDeskID)
        #expect(!session.resources.saveDeskPresets())
        #expect(manager.errorMessage != nil)
        try FileManager.default.removeItem(at: profileURL)
        let failedSaveDeadline = ContinuousClock.now + .seconds(2)
        while manager.profileSaveCount < writesBefore + 2, ContinuousClock.now < failedSaveDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Assert
        #expect(manager.profileSaveCount == writesBefore + 2)
        let restored = makeTestProfileManager(directory: directory)
        #expect(restored.session(for: profileID)?.resources.state.focusedDeskID == firstDeskID)
    }
}
