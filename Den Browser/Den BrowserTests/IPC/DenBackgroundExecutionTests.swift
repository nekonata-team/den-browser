import DenApplication
import DenDomain
import DenIPCProtocol
import DenInfrastructure
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenBackgroundExecutionTests {
    @Test(arguments: [false, true])
    func hiddenBoardSettingAppliesImmediatelyPersistsAndPreservesFocus(initiallyEnabled: Bool) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let html = directory.appendingPathComponent("probe.html")
        try
            "<script>window.framesRun=0;function f(){framesRun++;requestAnimationFrame(f)}requestAnimationFrame(f)</script>"
            .write(to: html, atomically: true, encoding: .utf8)
        let defaults = makeTestDefaults()
        let manager = ProfileManager(
            directoryURL: directory.appendingPathComponent("profiles"),
            sheetNavigation: SheetNavigationManager(defaults: defaults, scriptSource: ""),
            preferences: AppPreferences(defaults: defaults),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        defer { session.runtimes.releaseRuntimes() }
        let shown = session.navigation.presentedDeskID
        session.desks.createDesk(label: "Hidden", preset: .empty)
        let hidden = session.navigation.presentedDeskID
        session.boardNavigation.focusDesk(shown)
        let service = DenIPCService(profileManager: manager)

        // Act: create on another Desk without focusing it.
        let response = await service.handleRequest(
            .init(
                operation: .createWebBoard(
                    payload: .init(url: html.absoluteString, focus: false, backgroundExecution: initiallyEnabled),
                    destination: .endOfDesk(hidden.rawValue)
                )
            )
        )
        guard case .createdBoard(let rawID, _, _) = response.result.payload, let uuid = UUID(uuidString: rawID) else {
            Issue.record("Expected a created Board")
            return
        }
        let id = BoardID(uuid)
        let runtime = try #require(session.resources.webRuntimes[id])
        let read = await service.handleRequest(
            .init(operation: .boardBackgroundExecution(enabled: nil, target: .explicit(uuid)))
        )

        // Assert the read operation preserves the saved setting.
        guard case .enabled(let enabled) = read.result.payload else {
            Issue.record("Expected enabled state")
            return
        }
        #expect(enabled == initiallyEnabled)

        // Act: explicitly enable twice; it must never toggle back off or reload.
        for _ in 0..<2 {
            let result = await service.handleRequest(
                .init(operation: .boardBackgroundExecution(enabled: true, target: .explicit(uuid)))
            )
            #expect(result.result.isOk)
        }
        try await SheetInteraction.waitForFunction(expression: "window.framesRun > 1", in: runtime.webView)

        // Assert runtime identity, background rendering, persistence, and unchanged Desk.
        #expect(session.resources.webRuntimes[id] === runtime)
        #expect(try await runtime.webView.evaluateJavaScript("document.visibilityState") as? String == "visible")
        #expect(session.navigation.presentedDeskID == shown)
        let persistence = ProfilePersistence(
            directoryURL: directory.appendingPathComponent("profiles"),
            isEphemeral: false,
            quarantineFile: { try FileManager.default.moveItem(at: $0, to: $1) }
        )
        #expect(persistence.load().profiles.first?.den.board(for: id)?.backgroundExecutionEnabled == true)

        // Act / Assert: reads are available during a drag, but setting changes are rejected.
        session.resources.activeDrag = .board(id)
        let duringDrag = await service.handleRequest(
            .init(operation: .boardBackgroundExecution(enabled: nil, target: .explicit(uuid)))
        )
        #expect(duringDrag.result.isOk)
        let rejected = await service.handleRequest(
            .init(operation: .boardBackgroundExecution(enabled: false, target: .explicit(uuid)))
        )
        #expect(!rejected.result.isOk)
        #expect(session.resources.state.board(for: id)?.backgroundExecutionEnabled == true)
        session.resources.activeDrag = nil

        // Act / Assert: disable applies without changing the page or focus.
        let disabled = await service.handleRequest(
            .init(operation: .boardBackgroundExecution(enabled: false, target: .explicit(uuid)))
        )
        #expect(disabled.result.isOk)
        try await SheetInteraction.waitForFunction(
            expression: "document.visibilityState === 'hidden'",
            in: runtime.webView
        )
        #expect(session.resources.state.board(for: id)?.backgroundExecutionEnabled == false)
        #expect(persistence.load().profiles.first?.den.board(for: id)?.backgroundExecutionEnabled == false)
        #expect(session.navigation.presentedDeskID == shown)
    }
}
