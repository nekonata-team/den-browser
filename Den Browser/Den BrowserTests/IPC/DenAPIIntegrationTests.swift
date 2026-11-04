import DenDomain
import DenIPCProtocol
import DenInfrastructure
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenAPIIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func cliSettingsInjectBeforePageScriptsFocusBoardsAndRestoreFromDisk() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let html = directory.appendingPathComponent("sketch.html")
        try "<script>window.apiAtStart = typeof den;</script><p>Sketch</p>".write(
            to: html, atomically: true, encoding: .utf8)
        let defaults = makeTestDefaults()
        let manager = ProfileManager(
            directoryURL: directory.appendingPathComponent("profiles"),
            sheetNavigation: SheetNavigationManager(defaults: defaults, scriptSource: ""),
            preferences: AppPreferences(defaults: defaults), removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let session = try #require(manager.session(for: manager.personalProfileID))
        defer { session.runtimes.releaseRuntimes() }
        let destination = try #require(session.boardOpening.createBoard(urlString: "https://example.com/"))
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            .init(
                operation: .createWebBoard(
                    payload: .init(url: html.absoluteString, focus: false, denAPI: true), destination: .automatic)))
        guard case .createdBoard(let rawID, _, _) = response.result.payload, let uuid = UUID(uuidString: rawID) else {
            Issue.record("Expected created Board: \(response.result.error ?? "missing result")")
            return
        }
        let id = BoardID(uuid)
        let runtime = try #require(session.resources.webRuntimes[id])
        try await SheetInteraction.waitForFunction(expression: "window.apiAtStart === 'object'", in: runtime.webView)
        _ = try await runtime.webView.callAsyncJavaScript(
            "await den.boards.focus(id);", arguments: ["id": destination.rawValue.uuidString], in: nil,
            contentWorld: .page)

        // Assert
        #expect(session.connection.focusedBoardID() == destination)
        let persisted = ProfilePersistence(
            directoryURL: directory.appendingPathComponent("profiles"), isEphemeral: false,
            quarantineFile: { try FileManager.default.moveItem(at: $0, to: $1) }
        ).load()
        let board = persisted.profiles.first(where: { $0.profile.id == manager.personalProfileID })?.den.board(for: id)
        #expect(board?.denAPIEnabled == true)

        // Act / Assert: normal reload preserves; explicit disable persists false.
        let target = BoardTarget.explicit(uuid)
        let preserved = await service.handleRequest(.init(operation: .sheet(command: .reload, target: target)))
        #expect(preserved.result.isOk)
        #expect(session.resources.state.board(for: id)?.denAPIEnabled == true)
        let disabled = await service.handleRequest(
            .init(
                operation: .sheet(
                    command: .reloadWithDenAPI(enabled: false), target: target)))
        #expect(disabled.result.isOk)
        #expect(session.resources.state.board(for: id)?.denAPIEnabled == false)
        let saved = ProfilePersistence(
            directoryURL: directory.appendingPathComponent("profiles"), isEphemeral: false,
            quarantineFile: { try FileManager.default.moveItem(at: $0, to: $1) }
        ).load()
        #expect(
            saved.profiles.first(where: { $0.profile.id == manager.personalProfileID })?.den.board(for: id)?
                .denAPIEnabled == false)
    }
}
