import AppKit
import DenApplication
import DenDomain
import DenIPCProtocol
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenIPCNotificationTests {
    @Test(arguments: [false, true], [nil, 1, 10] as [Int?])
    func listingFiltersBeforeLimitingWithoutMarkingRead(unreadOnly: Bool, limit: Int?) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeManager(directory: directory)
        let session = try #require(manager.session(for: manager.personalProfileID))
        let operations = session.resources.notificationOperations
        let source = BoardID()
        let first = try #require(operations.record(title: nil, body: "First", boardID: source))
        let second = try #require(operations.record(title: "Title", body: "Second", boardID: source))
        operations.markRead(second.id)
        let third = try #require(operations.record(title: nil, body: "Third", boardID: source))
        operations.record(title: nil, body: "Other Board", boardID: BoardID())
        let before = session.resources.snapshot.notifications
        let deskID = session.navigation.presentedDeskID
        let service = DenIPCService(profileManager: manager)

        // Act
        let result = await service.handleRequest(
            DenIPCRequest(operation: .listNotifications(unreadOnly: unreadOnly, boardID: source.rawValue, limit: limit))
        ).result

        // Assert
        #expect(result.isOk)
        guard case .notifications(let items) = result.payload else {
            Issue.record("Expected Notifications")
            return
        }
        let expected = unreadOnly ? [third, first] : [third, second, first]
        #expect(items.map(\.id) == Array(expected.prefix(limit ?? expected.count)).map(\.id))
        #expect(items.allSatisfy { $0.boardID == source.rawValue })
        #expect(items.first?.body == "Third")
        #expect(items.first?.createdAt == third.createdAt.ISO8601Format())
        #expect(session.resources.snapshot.notifications == before)
        #expect(session.navigation.presentedDeskID == deskID)
    }

    @Test(arguments: [false, true])
    func settingReadIsIdempotentAndDoesNotOpenTheSourceOrCrossProfiles(isRead: Bool) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeManager(directory: directory)
        let session = try #require(manager.session(for: manager.personalProfileID))
        let other = try #require(manager.createProfile(name: "Other", color: .blue))
        let route = ProfileWindowRoute(windowID: UUID(), profileID: other.id)
        let otherSession = try #require(manager.session(for: route))
        let window = NSWindow()
        manager.register(window: window, for: route)
        defer { manager.unregister(window: window, for: route) }
        let notification = try #require(
            session.resources.notificationOperations.record(title: nil, body: "Message", boardID: BoardID()))
        session.resources.notificationOperations.setRead(notification.id, isRead: !isRead)
        let untouched = try #require(
            session.resources.notificationOperations.record(title: nil, body: "Other", boardID: BoardID()))
        let service = DenIPCService(profileManager: manager)
        let read = DenIPCRequest(
            operation: .setNotificationRead(id: notification.id, isRead: isRead),
            context: .init(profileID: manager.personalProfileID.rawValue))

        // Act
        let wrongProfile = await service.handleRequest(
            DenIPCRequest(operation: read.operation, context: .init(profileID: other.id.rawValue)))
        let otherList = await service.handleRequest(
            DenIPCRequest(
                operation: .listNotifications(unreadOnly: false, boardID: nil, limit: nil),
                context: .init(profileID: other.id.rawValue)))
        let firstRead = await service.handleRequest(read)
        let secondRead = await service.handleRequest(read)
        let missing = await service.handleRequest(
            DenIPCRequest(operation: .setNotificationRead(id: UUID(), isRead: isRead), context: read.context))

        // Assert
        #expect(!wrongProfile.result.isOk)
        guard case .notifications(let items) = otherList.result.payload else {
            Issue.record("Expected Notifications")
            return
        }
        #expect(items.isEmpty)
        #expect(firstRead.result.isOk)
        #expect(secondRead.result.isOk)
        #expect(!missing.result.isOk)
        #expect(session.resources.snapshot.notifications.first { $0.id == notification.id }?.isRead == isRead)
        #expect(session.resources.snapshot.notifications.first { $0.id == untouched.id }?.isRead == false)
        #expect(otherSession.resources.snapshot.notifications.isEmpty)
    }

    @Test(arguments: [0, -1])
    func invalidLimitsFailAtTheIPCBoundary(limit: Int) async {
        // Arrange
        let service = DenIPCService()

        // Act
        let result = await service.handleRequest(
            DenIPCRequest(operation: .listNotifications(unreadOnly: false, boardID: nil, limit: limit)))

        // Assert
        #expect(!result.result.isOk)
        #expect(result.result.error == "--limit must be a positive integer")
    }

    private func makeManager(directory: URL) -> ProfileManager {
        ProfileManager(
            directoryURL: directory,
            sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in }, websiteDataStore: { _ in .nonPersistent() })
    }
}
