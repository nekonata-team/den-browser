import AppKit
import Darwin
import DenApplication
import DenDomain
import DenIPCProtocol
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct DenMCPResponseTests {
    @Test func toolsUseLiveDenStateThroughStdioAndIPC() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = directory.appending(path: "reference.html")
        try "<title>Reference</title><main><h1>Reference</h1><button id='target'>Select me</button></main>"
            .write(to: page, atomically: true, encoding: .utf8)

        let socketPath = "/tmp/den-mcp-(UUID()).sock"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults()),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() },
            ipcSocketPath: socketPath
        )
        let profileID = manager.personalProfileID.rawValue.uuidString
        let session = try #require(manager.session(for: manager.personalProfileID))
        let originalDesk = session.navigation.presentedDeskID
        let originalBoard = try #require(
            session.boardOpening.createBoard(urlString: page.absoluteString, recentItem: .url(page, title: "Reference"))
        )
        let terminalBoard = try #require(
            session.boardOpening.createTerminalBoard(workingDirectory: directory.path, focus: false)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        try await loadInspection(in: session, boardID: originalBoard, window: window)
        session.desks.createDesk(label: "Research", preset: .empty)
        let firstDesk = session.navigation.presentedDeskID
        session.desks.createDesk(label: "Research", preset: .empty)
        let secondDesk = session.navigation.presentedDeskID
        session.boardNavigation.focusDesk(originalDesk)
        let notifications = session.resources.notificationOperations
        let old = try #require(notifications.record(title: nil, body: "Earlier", boardID: originalBoard))
        let read = try #require(notifications.record(title: nil, body: "Read", boardID: originalBoard))
        notifications.setRead(read.id, isRead: true)
        let latest = try #require(notifications.record(title: nil, body: "Latest", boardID: originalBoard))
        let expectedUnreadIDs = [latest.id.uuidString, old.id.uuidString]
        let expectedReadState = [latest.id.uuidString: false, read.id.uuidString: true, old.id.uuidString: false]

        let service = DenIPCService()
        service.start(profileManager: manager)
        defer { service.stop() }
        let pageURL = page.absoluteString
        let originalBoardID = originalBoard.rawValue.uuidString
        let terminalBoardID = terminalBoard.rawValue.uuidString
        let originalDeskID = originalDesk.rawValue.uuidString
        let firstDeskID = firstDesk.rawValue.uuidString
        let secondDeskID = secondDesk.rawValue.uuidString

        try await Task.detached {
            let client = try MCPProcess(socketPath: socketPath, profileID: profileID)
            let listed = try client.request("tools/list")
            let tools = try #require(listed["tools"] as? [[String: Any]])
            #expect(
                tools.compactMap { $0["name"] as? String } == [
                    "overview_den", "search_den", "act_on_result", "open_pages", "read_page", "read_selection",
                    "read_terminal", "list_notifications",
                ]
            )
            let schemas = tools.compactMap { $0["inputSchema"] as? [String: Any] }
            #expect(schemas.count == tools.count)

            let overview = try client.call("overview_den")
            #expect(overview["active_desk_id"] as? String == originalDeskID)
            #expect(overview["focused_board_id"] as? String == originalBoardID)
            #expect(overview["boards"] == nil)
            let ordered = try #require(overview["desks"] as? [[String: Any]])
            #expect(ordered.compactMap { $0["id"] as? String } == [originalDeskID, firstDeskID, secondDeskID])

            let ambiguous = try client.call("open_pages", ["pages": ["current"], "desk": "research"])
            let choices = try #require(ambiguous["choices"] as? [[String: Any]])
            #expect(choices.compactMap { $0["id"] as? String } == [firstDeskID, secondDeskID])
            #expect(try client.call("overview_den")["desks"] as? NSArray == ordered as NSArray)

            let opened = try client.call(
                "open_pages",
                ["pages": ["current", "invalid", pageURL], "desk": firstDeskID]
            )
            let results = try #require(opened["pages"] as? [[String: Any]])
            #expect(results.compactMap { $0["index"] as? Int } == [0, 1, 2])
            #expect(results[1]["error"] != nil)
            #expect(results[1]["board_id"] == nil)
            let firstBoard = try #require(results[0]["board_id"] as? String)
            let secondBoard = try #require(results[2]["board_id"] as? String)
            let retry = try client.call("open_pages", ["pages": [pageURL], "desk": firstDeskID])
            let retried = try #require((retry["pages"] as? [[String: Any]])?.first?["board_id"] as? String)
            let state = try client.call("overview_den")
            let firstDeskBoards = (state["desks"] as? [[String: Any]])?[1]["boards"] as? [[String: Any]]
            #expect(firstDeskBoards?.compactMap { $0["id"] as? String } == [firstBoard, secondBoard, retried])
            #expect(state["focused_board_id"] as? String == originalBoardID)

            let current = try client.call("read_page")
            #expect(current["board_id"] as? String == originalBoardID)
            #expect(current["title"] as? String == "Reference")
            #expect((current["markdown"] as? String)?.contains("# Reference") == true)
            #expect(current["url"] as? String == pageURL)
            let byURL = try client.call("read_page", ["url": pageURL])
            let byURLID = try #require(byURL["board_id"] as? String)
            #expect(byURLID != originalBoardID)
            #expect(try client.call("read_page", ["board_id": byURLID])["board_id"] as? String == byURLID)
            #expect(byURL["title"] as? String == "Reference")
            let selection = try client.call("read_selection")
            let inspection = try #require(selection["inspection"] as? [String: Any])
            #expect(inspection["target_board_id"] as? String == originalBoardID)
            #expect(inspection["document_id"] is String)
            #expect((inspection["selection"] as? [String: Any])?["id"] as? String == "target")
            let terminal = try client.call("read_terminal", ["board_id": terminalBoardID, "lines": 5])
            #expect(terminal["board_id"] as? String == terminalBoardID)
            #expect(terminal["text"] is String)
            let invalidLines = try client.call("read_terminal", ["lines": 0], expectError: true)
            #expect((invalidLines["error"] as? String)?.contains("positive integer") == true)
            let unread = try client.call("list_notifications", ["unread_only": true, "limit": 2])
            let unreadIDs = (unread["notifications"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
            #expect(unreadIDs == expectedUnreadIDs)
            let notifications = try #require(try client.call("list_notifications")["notifications"] as? [[String: Any]])
            #expect(notifications.count == expectedReadState.count)
            for notification in notifications {
                let id = try #require(notification["id"] as? String)
                #expect(notification["is_read"] as? Bool == expectedReadState[id])
            }
            let stateAfterReads = try client.call("overview_den")
            #expect(stateAfterReads["focused_board_id"] as? String == originalBoardID)

            let matches = try client.matches(pageURL)
            let boards = matches.filter { $0["kind"] as? String == "board" }
            #expect(boards.count >= 2)
            let kinds = matches.compactMap { $0["kind"] as? String }
            #expect(kinds.contains("recent"))
            let toClose = try #require(boards.first { $0["id"] as? String == firstBoard })
            let close = try ref(in: toClose, startingWith: "Close")
            let show = try ref(in: toClose, startingWith: "Show")
            let move = try ref(in: toClose, startingWith: "Choose")
            let destinations = try client.call("act_on_result", ["ref": move])
            let end = try #require(
                (destinations["destinations"] as? [[String: Any]])?.first {
                    ($0["effect"] as? String)?.contains(secondDeskID) == true
                }?["ref"] as? String
            )
            #expect(try client.call("act_on_result", ["ref": end])["board_id"] as? String == firstBoard)
            #expect(try client.call("act_on_result", ["ref": show])["board_id"] as? String == firstBoard)
            #expect(try client.call("act_on_result", ["ref": close])["closed_board_id"] as? String == firstBoard)
            let stale = try client.call("act_on_result", ["ref": show], expectError: true)
            #expect((stale["error"] as? String)?.contains("search_den") == true)

            let command = try #require(try client.matches("> New Desk").first)
            let create = try ref(in: command, startingWith: "Create")
            #expect(try client.call("act_on_result", ["ref": create])["required"] as? [String] == ["name"])
            let named = try client.call("act_on_result", ["ref": create, "name": "Empty"])
            let emptyDesk = try #require(named["desk_id"] as? String)

            let toRemove = try #require(try client.matches(firstDeskID).first)
            let remove = try ref(in: toRemove, startingWith: "Preview")
            let preview = try client.call("act_on_result", ["ref": remove])
            let confirmation = try #require((preview["confirmation"] as? [String: Any])?["ref"] as? String)
            #expect(preview["required"] as? [String] == ["delete_boards"])
            let blocked = try client.call("act_on_result", ["ref": confirmation])
            #expect(blocked["removed_desk_id"] == nil)
            _ = try client.call("open_pages", ["pages": [pageURL], "desk": firstDeskID])
            let updated = try client.call("act_on_result", ["ref": confirmation, "delete_boards": true])
            #expect((updated["message"] as? String)?.contains("contents changed") == true)
            let revised = try #require((updated["confirmation"] as? [String: Any])?["ref"] as? String)
            #expect(
                try client.call("act_on_result", ["ref": revised, "delete_boards": true])["removed_desk_id"] as? String
                    == firstDeskID
            )
            for deskID in [emptyDesk, secondDeskID] {
                let desk = try #require(try client.matches(deskID).first)
                let remove = try ref(in: desk, startingWith: "Preview")
                let preview = try client.call("act_on_result", ["ref": remove])
                let confirm = try #require((preview["confirmation"] as? [String: Any])?["ref"] as? String)
                #expect(try client.call("act_on_result", ["ref": confirm])["removed_desk_id"] as? String == deskID)
            }
            let lastDesk = try #require(try client.matches(originalDeskID).first)
            let previewLast = try ref(in: lastDesk, startingWith: "Preview")
            let lastError = try client.call("act_on_result", ["ref": previewLast], expectError: true)
            #expect((lastError["error"] as? String)?.contains("last Desk") == true)
        }.value
    }

    private func loadInspection(in session: ProfileWindowSession, boardID: BoardID, window: NSWindow) async throws {
        let board = try #require(session.resources.state.board(for: boardID))
        let runtime = session.runtimes.webRuntime(for: board)
        window.contentView = runtime.webView
        try await SheetInteraction.waitForFunction(
            expression: "document.querySelector('#target') !== null",
            in: runtime.webView,
            timeout: 20
        )
        _ = try #require(session.sideBoards.createInspectionBoard(targetBoardID: boardID, focus: false))
        _ = try await runtime.webView.evaluateJavaScript(InspectionPageScript.initialize)
        _ = try await runtime.webView.evaluateJavaScript(InspectionPageScript.startPicking)
        _ = try await runtime.webView.evaluateJavaScript(
            "document.querySelector('#target').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))"
        )
    }
}

private nonisolated func ref(in match: [String: Any], startingWith prefix: String) throws -> String {
    let actions = try #require(match["actions"] as? [[String: Any]])
    return try #require(actions.first { ($0["effect"] as? String)?.hasPrefix(prefix) == true }?["ref"] as? String)
}

private nonisolated final class MCPProcess {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var nextID = 1

    init(socketPath: String, profileID: String) throws {
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/den")
        process.arguments = ["mcp", "--socket", socketPath, "--profile", profileID]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        _ = try request(
            "initialize",
            [
                "protocolVersion": "2025-06-18",
                "capabilities": [String: String](),
                "clientInfo": ["name": "Den BrowserTests", "version": "1"],
            ]
        )
        try writeMCPMessage(["jsonrpc": "2.0", "method": "notifications/initialized"], to: input.fileHandleForWriting)
    }

    deinit {
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    func request(_ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try writeMCPMessage(
            ["jsonrpc": "2.0", "id": id, "method": method, "params": params],
            to: input.fileHandleForWriting
        )
        let response = try readMCPMessage(from: output.fileHandleForReading)
        #expect(response["id"] as? Int == id)
        return try #require(response["result"] as? [String: Any], "(response)")
    }

    func call(_ name: String, _ args: [String: Any] = [:], expectError: Bool = false) throws -> [String: Any] {
        let result = try request("tools/call", ["name": name, "arguments": args])
        #expect(result["isError"] as? Bool == expectError, "(name): (result)")
        return try #require(result["structuredContent"] as? [String: Any])
    }

    func matches(_ query: String) throws -> [[String: Any]] {
        try #require(try call("search_den", ["query": query, "limit": 20])["matches"] as? [[String: Any]])
    }
}

private nonisolated func writeMCPMessage(_ message: [String: Any], to input: FileHandle) throws {
    var data = try JSONSerialization.data(withJSONObject: message)
    data.append(UInt8(ascii: "\n"))
    input.write(data)
}

private nonisolated func readMCPMessage(from output: FileHandle) throws -> [String: Any] {
    var message = Data()
    while true {
        var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 15_000) > 0 else {
            throw MCPProcessTestError.timedOut
        }
        let bytes = output.availableData
        guard !bytes.isEmpty else { throw MCPProcessTestError.closed }
        if let newline = bytes.firstIndex(of: UInt8(ascii: "\n")) {
            message.append(contentsOf: bytes[..<newline])
            break
        }
        message.append(bytes)
    }
    return try #require(JSONSerialization.jsonObject(with: message) as? [String: Any])
}

private enum MCPProcessTestError: Error {
    case timedOut
    case closed
}
