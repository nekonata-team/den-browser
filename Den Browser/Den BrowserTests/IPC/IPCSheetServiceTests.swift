import AppKit
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
struct IPCSheetServiceTests {
    @Test func sheetNavigateUsesSharedInputResolution() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-sheet-open-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceSheetOpenPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let boardID = try #require(session.boardOpening.createBoard(urlString: "https://example.com/"))
        let service = DenIPCService(profileManager: manager)

        let hostnameResponse = await service.handleResult(
            makeIPCRequest(
                .sheet(
                    command: .navigate(DenSheetNavigatePayload(url: "localhost:3000")),
                    target: .explicit(boardID.rawValue)
                )
            )
        )
        #expect(hostnameResponse.isOk)
        guard case .navigation(_, let url) = try #require(hostnameResponse.payload) else {
            Issue.record("Expected navigation payload")
            return
        }
        #expect(url == "https://localhost:3000/")

        let unsupportedResponse = await service.handleResult(
            makeIPCRequest(
                .sheet(
                    command: .navigate(DenSheetNavigatePayload(url: "mailto:user@example.com")),
                    target: .explicit(boardID.rawValue)
                )
            )
        )
        #expect(unsupportedResponse.isOk == false)
    }

    @Test(arguments: [
        ("text/html", "<body>Visible<span hidden>Hidden</span><script>/* Script */</script></body>", "Visible"),
        ("application/xml", "<response><message>API result</message></response>", "API result"),
        ("text/plain", "Plain text result", "Plain text result"),
    ])
    func sheetTextReadsHTMLAndDocumentsWithoutHTMLBody(mimeType: String, content: String, expected: String) async throws
    {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-sheet-text-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceSheetTextPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let boardID = try #require(session.boardOpening.createBoard(urlString: "https://text.example/"))
        let board = try #require(session.resources.state.board(for: boardID))
        let runtime = session.runtimes.webRuntime(for: board)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            content,
            mimeType: mimeType,
            baseURL: URL(string: "https://text.example/")!,
            in: runtime.webView
        )
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            makeIPCRequest(.sheet(command: .text, target: .explicit(boardID.rawValue)))
        )

        // Assert
        #expect(response.isOk)
        guard case .text(let text) = response.payload else {
            Issue.record("Expected Sheet text payload")
            return
        }
        #expect(text == expected)
    }

    @Test func sheetClickWithNewBoardCreatesWebBoard() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-sheet-click-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceSheetClickPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let boardID = try #require(session.boardOpening.createBoard(urlString: "https://example.com/"))
        let board = try #require(session.resources.state.board(for: boardID))
        let runtime = session.runtimes.webRuntime(for: board)

        let waiter = SheetInteractionWebViewLoadWaiter()
        let html = """
            <!DOCTYPE html>
            <html>
            <body>
                <a id="test-link" href="https://example.com/subpage">Subpage</a>
            </body>
            </html>
            """
        await waiter.load(html, baseURL: URL(string: "https://example.com")!, in: runtime.webView)

        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            makeIPCRequest(
                .sheet(
                    command: .click(
                        DenSheetClickPayload(
                            target: "#test-link",
                            role: nil,
                            name: nil,
                            exact: false,
                            newBoard: true,
                            focus: false
                        )
                    ),
                    target: .explicit(boardID.rawValue)
                )
            )
        )

        // Assert
        #expect(response.isOk)
        guard case .createdBoard(let newBoardIDString, _, let url) = try #require(response.payload) else {
            Issue.record("Expected created Board payload")
            return
        }
        let newBoardID = BoardID(try #require(UUID(uuidString: newBoardIDString)))
        #expect(session.resources.state.board(for: newBoardID) != nil)
        #expect(url == "https://example.com/subpage")
    }

    @Test func sheetCommandCanReturnSnapshotWithItsOriginalResult() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-sheet-snapshot-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceSheetSnapshotPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let boardID = try #require(session.boardOpening.createBoard(urlString: "https://snapshot.example/"))
        let board = try #require(session.resources.state.board(for: boardID))
        let runtime = session.runtimes.webRuntime(for: board)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <body><button id="continue">Before</button></body>
            """,
            baseURL: URL(string: "https://snapshot.example/")!,
            in: runtime.webView
        )
        let service = DenIPCService(profileManager: manager)

        // Act
        let script = "document.querySelector('button').textContent = 'After'; 'eval-result'"
        let response = await service.handleRequest(
            makeIPCRequest(
                .sheetWithSnapshot(
                    command: .eval(DenSheetEvalPayload(script: script)),
                    target: .explicit(boardID.rawValue),
                    snapshot: DenSheetSnapshotPayload(full: false)
                )
            )
        )
        let result = response.result

        // Assert
        #expect(result.isOk)
        if case .value(let value) = result.payload {
            #expect(value == "eval-result")
        } else {
            Issue.record("Expected evaluated value payload")
        }
        #expect(result.snapshot?.contains("After") == true)
        if case .board(let profileID, let resolvedBoardID) = response.target {
            #expect(profileID == manager.personalProfileID.rawValue)
            #expect(resolvedBoardID == boardID.rawValue)
        } else {
            Issue.record("Expected the Sheet Board as the response target")
        }
    }

    @Test func sheetInteractKeepsInitialBoardWhenFocusChangesDuringWait() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-interact-focus-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceInteractFocusPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let firstBoardID = try #require(session.boardOpening.createBoard(urlString: "https://first.example/"))
        let secondBoardID = try #require(session.boardOpening.createBoard(urlString: "https://second.example/"))
        session.boardNavigation.focusBoard(firstBoardID)
        let firstBoard = try #require(session.resources.state.board(for: firstBoardID))
        let secondBoard = try #require(session.resources.state.board(for: secondBoardID))
        let firstRuntime = session.runtimes.webRuntime(for: firstBoard)
        let secondRuntime = session.runtimes.webRuntime(for: secondBoard)
        let firstWaiter = SheetInteractionWebViewLoadWaiter()
        let secondWaiter = SheetInteractionWebViewLoadWaiter()
        await firstWaiter.load(
            """
            <!doctype html>
            <body>
              <button id="continue" onclick="this.textContent = 'Clicked'">Continue</button>
              <script>window.waitStarted = null; window.targetReady = null;</script>
            </body>
            """,
            baseURL: URL(string: "https://first.example/")!,
            in: firstRuntime.webView
        )
        await secondWaiter.load(
            """
            <!doctype html>
            <body><p>Second Board</p></body>
            """,
            baseURL: URL(string: "https://second.example/")!,
            in: secondRuntime.webView
        )
        let service = DenIPCService(profileManager: manager)
        let readyToken = UUID().uuidString
        let payload = DenSheetInteractPayload(
            steps: [
                DenSheetInteractStep(
                    line: 1,
                    text: "wait",
                    command: .wait(
                        DenSheetWaitPayload(
                            target: nil,
                            state: nil,
                            url: nil,
                            text: nil,
                            loadState: nil,
                            function:
                                "(() => { window.waitStarted = '\(readyToken)'; return window.targetReady === '\(readyToken)'; })()",
                            timeout: 2
                        )
                    )
                ),
                DenSheetInteractStep(
                    line: 2,
                    text: "click #continue",
                    command: .click(
                        DenSheetClickPayload(
                            target: "#continue",
                            role: nil,
                            name: nil,
                            exact: false,
                            newBoard: false,
                            focus: false,
                        )
                    )
                ),
            ])

        // Act
        let interactTask = Task {
            await service.handleResult(
                makeIPCRequest(
                    .sheetWithSnapshot(
                        command: .interact(payload),
                        target: .automatic,
                        snapshot: DenSheetSnapshotPayload(full: false)
                    )
                )
            )
        }
        var waitStarted = false
        let waitDeadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < waitDeadline {
            let value = try? await firstRuntime.webView.evaluateJavaScript(
                "window.waitStarted === '\(readyToken)'"
            )
            if (value as? Bool) == true {
                waitStarted = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(waitStarted)
        session.boardNavigation.focusBoard(secondBoardID)
        _ = try await firstRuntime.webView.evaluateJavaScript(
            "window.targetReady = '\(readyToken)'"
        )
        let response = await interactTask.value

        // Assert
        #expect(response.isOk)
        #expect(response.completedActions == 2)
        #expect(response.snapshot?.contains("Clicked") == true)
    }

    @Test func sheetInteractSnapshotsOnlyWhenRequested() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-interact-snapshot-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceInteractSnapshotPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let boardID = try #require(session.boardOpening.createBoard(urlString: "https://interact.example/"))
        let board = try #require(session.resources.state.board(for: boardID))
        let webView = session.runtimes.webRuntime(for: board).webView
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            "<!doctype html><body><button id=\"continue\">Continue</button><h2>Static detail</h2></body>",
            baseURL: URL(string: "https://interact.example/")!,
            in: webView
        )
        let service = DenIPCService(profileManager: manager)

        func request(target: String, snapshot: DenSheetSnapshotPayload? = nil) -> DenIPCRequest {
            let command = DenIPCCommand.Sheet.interact(
                DenSheetInteractPayload(
                    steps: [
                        DenSheetInteractStep(
                            line: 1,
                            text: "click \(target)",
                            command: .click(
                                DenSheetClickPayload(
                                    target: target,
                                    role: nil,
                                    name: nil,
                                    exact: false,
                                    newBoard: false,
                                    focus: false
                                )
                            )
                        )
                    ])
            )
            let operation: DenIPCOperation
            if let snapshot {
                operation = .sheetWithSnapshot(
                    command: command,
                    target: .explicit(boardID.rawValue),
                    snapshot: snapshot
                )
            } else {
                operation = .sheet(command: command, target: .explicit(boardID.rawValue))
            }
            return makeIPCRequest(operation)
        }

        // Act
        let success = await service.handleResult(request(target: "#continue"))
        let failure = await service.handleResult(request(target: "#missing"))
        let successWithSnapshot = await service.handleResult(
            request(target: "#continue", snapshot: DenSheetSnapshotPayload(full: false))
        )
        let failureWithSnapshotReply = await service.handleRequest(
            request(target: "#missing", snapshot: DenSheetSnapshotPayload(full: false))
        )
        let failureWithSnapshot = failureWithSnapshotReply.result
        let fullSnapshot = await service.handleResult(
            request(target: "#continue", snapshot: DenSheetSnapshotPayload(full: true))
        )

        // Assert
        #expect(success.isOk)
        #expect(success.snapshot == nil)
        #expect(success.completedActions == 1)
        #expect(failure.isOk == false)
        #expect(failure.snapshot == nil)
        #expect(failure.completedActions == 0)
        #expect(failure.failedActionIndex == 0)
        #expect(successWithSnapshot.isOk)
        #expect(successWithSnapshot.snapshot?.contains("Continue") == true)
        #expect(successWithSnapshot.snapshot?.contains("Static detail") == false)
        #expect(successWithSnapshot.completedActions == 1)
        #expect(failureWithSnapshot.isOk == false)
        #expect(failureWithSnapshot.snapshot?.contains("Continue") == true)
        #expect(failureWithSnapshot.completedActions == 0)
        #expect(failureWithSnapshot.failedActionIndex == 0)
        if case .board(let profileID, let targetBoardID) = failureWithSnapshotReply.target {
            #expect(profileID == manager.personalProfileID.rawValue)
            #expect(targetBoardID == boardID.rawValue)
        } else {
            Issue.record("Expected the failed Sheet action's resolved Board target")
        }
        #expect(fullSnapshot.isOk)
        #expect(fullSnapshot.snapshot?.contains("Static detail") == true)
    }

    @Test func sheetInteractFailsWhenInitialBoardDisappearsDuringWait() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-interact-removal-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceInteractRemovalPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let firstBoardID = try #require(session.boardOpening.createBoard(urlString: "https://first.example/"))
        let secondBoardID = try #require(session.boardOpening.createBoard(urlString: "https://second.example/"))
        session.boardNavigation.focusBoard(firstBoardID)
        let firstBoard = try #require(session.resources.state.board(for: firstBoardID))
        let secondBoard = try #require(session.resources.state.board(for: secondBoardID))
        let firstRuntime = session.runtimes.webRuntime(for: firstBoard)
        let secondRuntime = session.runtimes.webRuntime(for: secondBoard)
        let firstWaiter = SheetInteractionWebViewLoadWaiter()
        let secondWaiter = SheetInteractionWebViewLoadWaiter()
        await firstWaiter.load(
            """
            <!doctype html>
            <body>
              <button id="continue">Continue</button>
              <script>window.waitStarted = null; window.targetReady = null;</script>
            </body>
            """,
            baseURL: URL(string: "https://first.example/")!,
            in: firstRuntime.webView
        )
        await secondWaiter.load(
            """
            <!doctype html>
            <body><button id="continue">Second Board</button></body>
            """,
            baseURL: URL(string: "https://second.example/")!,
            in: secondRuntime.webView
        )
        let service = DenIPCService(profileManager: manager)
        let readyToken = UUID().uuidString
        let payload = DenSheetInteractPayload(
            steps: [
                DenSheetInteractStep(
                    line: 1,
                    text: "wait",
                    command: .wait(
                        DenSheetWaitPayload(
                            target: nil,
                            state: nil,
                            url: nil,
                            text: nil,
                            loadState: nil,
                            function:
                                "(() => { window.waitStarted = '\(readyToken)'; return window.targetReady === '\(readyToken)'; })()",
                            timeout: 2
                        )
                    )
                ),
                DenSheetInteractStep(
                    line: 2,
                    text: "click #continue",
                    command: .click(
                        DenSheetClickPayload(
                            target: "#continue",
                            role: nil,
                            name: nil,
                            exact: false,
                            newBoard: false,
                            focus: false,
                        )
                    )
                ),
            ])

        // Act
        let interactTask = Task {
            await service.handleResult(
                makeIPCRequest(
                    .sheet(
                        command: .interact(payload),
                        target: .explicit(firstBoardID.rawValue)
                    )
                )
            )
        }
        var waitStarted = false
        let waitDeadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < waitDeadline {
            let value = try? await firstRuntime.webView.evaluateJavaScript(
                "window.waitStarted === '\(readyToken)'"
            )
            if (value as? Bool) == true {
                waitStarted = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(waitStarted)
        session.boardRemoval.removeBoard(firstBoardID)
        session.boardNavigation.focusBoard(secondBoardID)
        _ = try await firstRuntime.webView.evaluateJavaScript(
            "window.targetReady = '\(readyToken)'"
        )
        let response = await interactTask.value

        // Assert
        #expect(response.isOk == false)
        #expect(response.error == "Target Web Board no longer exists: \(firstBoardID.rawValue.uuidString)")
        #expect(response.completedActions == 0)
        #expect(response.failedActionIndex == 0)
    }
}
