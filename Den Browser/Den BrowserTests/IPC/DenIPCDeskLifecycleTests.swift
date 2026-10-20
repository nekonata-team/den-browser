import DenDomain
import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenIPCDeskLifecycleTests {
    @Test(arguments: [false, true])
    func newDeskUsesCallerDeskAsInsertionAnchor(focus: Bool) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeManager(directory: directory)
        let controller = try #require(manager.controller(for: manager.personalProfileID))
        let visibleDeskID = controller.presentedDeskID
        let visibleBoardID = try #require(controller.createBoard(urlString: "https://example.com/"))
        controller.createDesk(label: "Caller", preset: .empty)
        let callerDeskID = controller.presentedDeskID
        let callerBoardID = try #require(controller.createBoard(urlString: "https://example.com/caller"))
        #expect(controller.setFocusedDesk(visibleDeskID))
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            DenIPCRequest(
                operation: .createDesk(label: "  New  ", focus: focus),
                context: DenIPCCallerContext(callerBoardID: callerBoardID.rawValue)))

        // Assert
        #expect(response.result.isOk)
        let created = try #require(controller.state.desks.last)
        #expect(controller.state.desks.map(\.id) == [visibleDeskID, callerDeskID, created.id])
        #expect(created.label == "New")
        #expect(created.boards.isEmpty)
        #expect(controller.presentedDeskID == (focus ? created.id : visibleDeskID))
        if !focus { #expect(controller.focusedBoard?.id == visibleBoardID) }
        guard case .createdDesk(let id) = response.result.payload else {
            Issue.record("Expected created Desk identity")
            return
        }
        #expect(id == created.id.rawValue.uuidString)
    }

    @Test(arguments: [false, true])
    func removeEmptyDeskPreservesOrReplacesFocus(visible: Bool) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeManager(directory: directory)
        let controller = try #require(manager.controller(for: manager.personalProfileID))
        let originalDeskID = controller.presentedDeskID
        controller.createDesk(label: "Remove", preset: .empty)
        let targetID = controller.presentedDeskID
        if !visible { #expect(controller.setFocusedDesk(originalDeskID)) }
        let service = DenIPCService(profileManager: manager)

        // Act
        let result = await service.handleRequest(
            DenIPCRequest(operation: .removeDesk(deskID: targetID.rawValue, force: false))
        ).result

        // Assert
        #expect(result.isOk)
        #expect(controller.state.desks.map(\.id) == [originalDeskID])
        #expect(controller.presentedDeskID == originalDeskID)
        guard case .removedDesk(let id) = result.payload else {
            Issue.record("Expected removed Desk identity")
            return
        }
        #expect(id == targetID.rawValue.uuidString)
    }

    @Test(arguments: [false, true])
    func occupiedDeskRequiresExplicitForce(force: Bool) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeManager(directory: directory)
        let controller = try #require(manager.controller(for: manager.personalProfileID))
        controller.createDesk(label: "Occupied", preset: .empty)
        let targetID = controller.presentedDeskID
        let boardID = try #require(controller.createBoard(urlString: "https://example.com/"))
        let service = DenIPCService(profileManager: manager)

        // Act
        let result = await service.handleRequest(
            DenIPCRequest(operation: .removeDesk(deskID: targetID.rawValue, force: force))
        ).result

        // Assert
        #expect(result.isOk == force)
        #expect(controller.state.desks.contains(where: { $0.id == targetID }) == !force)
        #expect((controller.board(for: boardID) != nil) == !force)
        if !force {
            #expect(result.error?.contains("Boards: 1") == true)
            #expect(result.error?.contains("--force") == true)
        }
    }

    @Test(arguments: [false, true])
    func lastDeskCannotBeRemovedEvenWithForce(force: Bool) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeManager(directory: directory)
        let controller = try #require(manager.controller(for: manager.personalProfileID))
        let targetID = controller.presentedDeskID
        let service = DenIPCService(profileManager: manager)

        // Act
        let result = await service.handleRequest(
            DenIPCRequest(operation: .removeDesk(deskID: targetID.rawValue, force: force))
        ).result

        // Assert
        #expect(!result.isOk)
        #expect(result.error == "The last Desk cannot be removed")
        #expect(controller.state.desks.map(\.id) == [targetID])
    }

    @Test(arguments: ["", " \n "])
    func emptyLabelDoesNotCreateDesk(label: String) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeManager(directory: directory)
        let controller = try #require(manager.controller(for: manager.personalProfileID))
        let deskIDs = controller.state.desks.map(\.id)
        let service = DenIPCService(profileManager: manager)

        // Act
        let result = await service.handleRequest(DenIPCRequest(operation: .createDesk(label: label, focus: true)))
            .result

        // Assert
        #expect(!result.isOk)
        #expect(controller.state.desks.map(\.id) == deskIDs)
    }

    private func makeManager(directory: URL) -> ProfileManager {
        ProfileManager(
            directoryURL: directory,
            sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: "DeskCLI-\(UUID().uuidString)")),
            removeDataStore: { _ in }, websiteDataStore: { _ in .nonPersistent() })
    }
}
