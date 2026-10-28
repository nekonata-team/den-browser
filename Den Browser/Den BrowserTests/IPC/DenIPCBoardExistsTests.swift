import AppKit
import DenDomain
import DenIPCProtocol
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@Suite(.serialized)
@MainActor
struct DenIPCBoardExistsTests {
    @Test(arguments: ["all", "matching", "other", "closed", "closed-all", "missing", "unknown"], [false, true])
    func lookupReturnsLocationOnlyWithinOpenProfileScope(scope: String, inspection: Bool) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = makeTestDefaults()
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: defaults, scriptSource: ""),
            preferences: AppPreferences(defaults: defaults), removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let callerSession = try #require(manager.session(for: manager.personalProfileID))
        let caller = try #require(callerSession.boardOpening.createBoard(urlString: "https://example.com/caller"))
        let profile = try #require(manager.createProfile(name: "Other", color: .blue))
        let route = ProfileWindowRoute(windowID: UUID(), profileID: profile.id)
        let session = try #require(manager.session(for: route))
        let originalDeskID = session.navigation.presentedDeskID
        session.desks.createDesk(label: "Target", preset: .empty)
        let deskID = session.navigation.presentedDeskID
        let primary = try #require(session.boardOpening.createBoard(urlString: "https://example.com/target"))
        let boardID =
            inspection
            ? try #require(session.sideBoards.createInspectionBoard(targetBoardID: primary, focus: false)) : primary
        session.boardNavigation.focusDesk(originalDeskID)
        let window = NSWindow()
        manager.register(window: window, for: route)
        if scope.hasPrefix("closed") { manager.unregister(window: window, for: route) }
        let profileID: UUID? =
            switch scope {
            case "matching", "closed": profile.id.rawValue
            case "other": manager.personalProfileID.rawValue
            case "unknown": UUID()
            default: nil
            }
        let queriedID = scope == "missing" ? UUID() : boardID.rawValue
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            DenIPCRequest(
                operation: .boardExists(boardID: queriedID),
                context: .init(profileID: profileID, callerBoardID: caller.rawValue)))

        // Assert
        if scope == "unknown" {
            #expect(!response.result.isOk)
            let message = try #require(response.result.error)
            #expect(message.contains("Profile not found: \(try #require(profileID).uuidString)"))
            #expect(message.contains("den profile list"))
            return
        }
        #expect(response.result.isOk)
        guard case .boardExistence(let returnedID, let location) = response.result.payload else {
            Issue.record("Expected Board existence payload")
            return
        }
        #expect(returnedID == queriedID.uuidString)
        let found = scope == "all" || scope == "matching"
        #expect((location != nil) == found)
        #expect(location?.deskID == (found ? deskID.rawValue.uuidString : nil))
        #expect(location?.profileID == (found ? profile.id.rawValue.uuidString : nil))
        #expect(session.navigation.presentedDeskID == originalDeskID)
        if scope.hasPrefix("closed") { #expect(!manager.hasWindow(for: profile.id)) }
    }
}
