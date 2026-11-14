import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

struct CLICommandExecutionTests {
    @Test(arguments: [[], ["--json"], ["--text"], ["--text", "-l"]])
    func overviewPreservesLayoutAndOutputSelection(flags: [String]) async throws {
        // Arrange
        let profileID = UUID()
        let deskID = UUID().uuidString
        let boardID = UUID().uuidString
        let sideID = UUID().uuidString
        let terminalID = UUID().uuidString
        let longLabel = String(repeating: "界", count: 40)
        let boards = [
            DenBoardInfo(id: boardID, type: "web", label: "Docs\n[API]", isFocused: false),
            DenBoardInfo(id: sideID, type: "inspection", label: "Console", targetBoardID: boardID, isFocused: true),
            DenBoardInfo(id: terminalID, type: "terminal", label: longLabel, isFocused: false),
        ]
        let desk = DenDeskInfo(id: deskID, label: "Work", isActive: true, boardCount: 3, boards: boards)
        let empty = DenDeskInfo(id: UUID().uuidString, label: "Empty", isActive: false, boardCount: 0, boards: [])
        let overview = DenIPCOverview(
            profiles: [],
            profile: .init(id: profileID.uuidString, name: "Default"),
            profileID: profileID.uuidString,
            desks: [desk, empty],
            activeDesk: desk,
            boards: boards,
            focusedBoardID: sideID,
            drawerItemCount: 0
        )
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data)
            return encodeIPCResponse(
                request?.operation == .inspectDen(target: .automatic) && request?.context.profileID == profileID
                    ? .success(.denOverview(overview)) : .failure("Unexpected request")
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["overview", "--profile", profileID.uuidString] + flags,
            socketPath: socketPath,
            forceJSON: false
        )

        // Assert
        #expect(result.status == 0)
        if flags.contains("--text") {
            let text = try #require(String(data: result.output, encoding: .utf8))
            let long = flags.contains("-l")
            #expect(text.contains(long ? "* 1: Work" : "* Work"))
            #expect(
                text.contains(
                    long
                        ? "[2: web: Docs (API) | 3: inspection: Console *]"
                        : "[web: Docs (API) | inspection: Console *]"
                )
            )
            #expect(text.contains("  (empty)"))
            #expect(text.contains("]  [\(long ? "4: " : "")terminal: \(String(longLabel.prefix(31)))…]"))
            #expect(text.contains(boardID) == long)
            if long {
                #expect(text.contains("1: desk \(deskID) - Work"))
                #expect(text.contains("3: inspection \(sideID) - Console"))
                #expect(text.contains("4: terminal \(terminalID) - \(longLabel)"))
            }
        } else {
            let object = try parseCLIJSON(result.output)
            let desks = try #require(object["desks"] as? [[String: Any]])
            let nestedBoards = try #require(desks.first?["boards"] as? [[String: Any]])
            #expect(nestedBoards.map { $0["id"] as? String } == [boardID, sideID, terminalID])
            #expect(nestedBoards[1]["target_board_id"] as? String == boardID)
            #expect((desks.last?["boards"] as? [Any])?.isEmpty == true)
        }
    }

    @Test func overviewRejectsConflictingFormats() async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()

        // Act
        let result = try await runCLITest(["overview", "--text", "--json"], socketPath: socketPath, forceJSON: false)

        // Assert
        #expect(result.status == 64)
        #expect(String(data: result.error, encoding: .utf8)?.contains("Specify only one of --text or --json") == true)
    }

    @Test func boardResizeSendsRequestedWidthAndReturnsAppliedWidth() async throws {
        // Arrange
        let boardID = UUID()
        let socketPath = makeTemporaryCLISocketPath()
        let server = DenSocketServer(socketPath: socketPath)
        try server.start { data in
            let request = try? JSONDecoder().decode(DenIPCRequest.self, from: data)
            return encodeIPCResponse(
                request?.operation == .resizeBoard(boardID: boardID, width: 2_000)
                    ? .success(.resizedBoard(id: boardID.uuidString, width: 960)) : .failure("Unexpected request")
            )
        }
        defer { server.stop() }

        // Act
        let result = try await runCLITest(
            ["board", "resize", "--board", boardID.uuidString, "--width", "2000"],
            socketPath: socketPath
        )
        let object = try parseCLIJSON(result.output)

        // Assert
        #expect(result.status == 0)
        #expect(object["board_id"] as? String == boardID.uuidString)
        #expect(object["width"] as? Double == 960)
    }

    @Test(arguments: [
        ["--width", "900"], ["--board", "invalid", "--width", "900"],
        ["--board", UUID().uuidString], ["--board", UUID().uuidString, "--width", "0"],
        ["--board", UUID().uuidString, "--width", "-1"],
        ["--board", UUID().uuidString, "--width", "nan"],
        ["--board", UUID().uuidString, "--width", "inf"],
    ])
    func boardResizeRejectsInvalidArguments(arguments: [String]) async throws {
        // Arrange
        let socketPath = makeTemporaryCLISocketPath()

        // Act
        let result = try await runCLITest(["board", "resize"] + arguments, socketPath: socketPath)

        // Assert
        #expect(result.status == 64)
    }
}
