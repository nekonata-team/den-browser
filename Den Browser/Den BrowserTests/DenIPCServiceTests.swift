import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct DenIPCServiceTests {
    @Test func healthCommandReturnsHealthyWithoutAnActiveProfile() async {
        let service = DenIPCService()
        let response = await service.handleRequest(DenIPCRequest(command: .health))

        #expect(response.isOk)
        #expect(response.message == nil)
    }

    @Test func webBoardCreationStartsRuntime() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-service-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServicePreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard,
                scriptSource: ""),
            preferences: AppPreferences(defaults: UserDefaults(suiteName: suiteName) ?? .standard),
            removeDataStore: { _ in })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            DenIPCRequest(command: .board(.web(.new)), args: ["https://example.com/"]))

        // Assert
        let boardID = try #require(response.boardId.flatMap(UUID.init(uuidString:)))
        #expect(store.runtimes[boardID] != nil)
    }

    @Test func drawerPlacementStartsWebRuntime() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-service-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServicePreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard,
                scriptSource: ""),
            preferences: AppPreferences(defaults: UserDefaults(suiteName: suiteName) ?? .standard),
            removeDataStore: { _ in })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let itemID = try #require(
            store.keepInDrawerInBackground(URL(string: "https://example.com/drawer")!))
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            DenIPCRequest(command: .drawer(.place), args: [itemID.uuidString]))

        // Assert
        let boardID = try #require(response.boardId.flatMap(UUID.init(uuidString:)))
        #expect(store.runtimes[boardID] != nil)
    }

    @Test func profileListCommandReturnsAllProfiles() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-service-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServicePreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard,
                scriptSource: ""),
            preferences: AppPreferences(defaults: UserDefaults(suiteName: suiteName) ?? .standard),
            removeDataStore: { _ in })
        _ = try #require(manager.store(for: manager.personalProfileID))
        let profile2 = try #require(manager.createProfile(name: "Work", color: .blue))
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            DenIPCRequest(command: .profile(.list)))

        // Assert
        #expect(response.isOk)
        let profiles = try #require(response.profiles)
        #expect(profiles.count == 2)
        let personal = try #require(profiles.first(where: { $0.id == manager.personalProfileID.uuidString }))
        #expect(personal.hasWindow == true)
        let work = try #require(profiles.first(where: { $0.id == profile2.id.uuidString }))
        #expect(work.name == "Work")
        #expect(work.hasWindow == false)
    }

    @Test func deskListCommandWithProfileIDReturnsDesksForTargetProfile() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-desk-profile-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceDeskPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard,
                scriptSource: ""),
            preferences: AppPreferences(defaults: UserDefaults(suiteName: suiteName) ?? .standard),
            removeDataStore: { _ in })
        _ = try #require(manager.store(for: manager.personalProfileID))
        let profile2 = try #require(manager.createProfile(name: "Work", color: .blue))
        let store2 = try #require(manager.store(for: profile2.id))
        store2.createDesk(label: "Work Desk", preset: .empty)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            DenIPCRequest(command: .desk(.list), profileID: profile2.id.uuidString))

        // Assert
        #expect(response.isOk)
        let desks = try #require(response.desks)
        #expect(desks.contains(where: { $0.label == "Work Desk" }))
    }
}
