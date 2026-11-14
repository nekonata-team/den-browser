import AppKit
import DenApplication
import DenDomain
import DenModels
import DenViews
import Foundation
import GhosttyTerminal
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct SideBoardTests {
    @Test func inspectionBoardLinksToWebBoardAndReusesIt() throws {
        let target = BoardState(label: "Target", width: 520, currentSheetURL: URL(string: "https://example.com"))
        let sourceDesk = makeTestDesk("Desk", boards: [target], focusedBoardID: target.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        let inspectionID = try #require(session.sideBoards.createInspectionBoard(targetBoardID: target.id))
        let inspection = try #require(session.resources.state.board(for: inspectionID))

        #expect(session.resources.state.desks[0].boards.map(\.id) == [target.id, inspectionID])
        #expect(session.navigation.focusedBoard?.id == inspectionID)
        #expect(inspection.isInspection)
        #expect(!inspection.isWeb)
        #expect(!inspection.isTerminal)
        #expect(inspection.isSideBoard)
        #expect(inspection.sideBoardTargetBoardID == target.id)
        #expect(try JSONDecoder().decode(BoardState.self, from: JSONEncoder().encode(inspection)) == inspection)
        #expect(session.sideBoards.createInspectionBoard(targetBoardID: target.id) == inspectionID)
        #expect(session.resources.state.desks[0].boards.count == 2)
    }

    @Test(arguments: [false, true], [false, true])
    func sideBoardDuplicatesItsPrimaryBoard(isInspection: Bool, fromFirstSheet: Bool) throws {
        // Arrange
        var target =
            isInspection
            ? makeTestBoard("Target", width: 800)
            : BoardState(label: "Target", width: 800, workingDirectory: "/tmp/primary")
        target.firstSheetURL = URL(string: "https://example.com/first")
        var side =
            isInspection
            ? BoardState(width: 360, targetBoardID: target.id)
            : BoardState(label: "Side", width: 360, workingDirectory: "/tmp/side")
        if !isInspection {
            side.firstSheetURL = URL(string: "https://example.com/first")
            side.role = .sideBoard(targetBoardID: target.id)
        }
        let sourceDesk = makeTestDesk("Desk", boards: [target, side], focusedBoardID: side.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        // Act
        if fromFirstSheet {
            session.zmx.duplicateFocusedBoardFromFirstSheet()
        } else {
            session.zmx.duplicateFocusedBoard()
        }

        // Assert
        let copy = try #require(session.navigation.focusedBoard)
        #expect(session.resources.state.desks[0].boards.map(\.id) == [target.id, side.id, copy.id])
        #expect(copy.id != target.id && copy.id != side.id)
        #expect(!copy.isSideBoard)
        #expect(copy.width == target.width)
        #expect(copy.label == target.label)
        #expect(copy.terminalWorkingDirectory == target.terminalWorkingDirectory)
        #expect(
            copy.currentSheetURL == (fromFirstSheet && target.isWeb ? target.firstSheetURL : target.currentSheetURL)
        )
    }

    @Test(arguments: [0, 1])
    func focusedBoardCreationKeepsSideBoardGroupAdjacent(focusedIndex: Int) throws {
        // Arrange
        let target = makeTestBoard("Target")
        var side = makeTestBoard("Side")
        side.role = .sideBoard(targetBoardID: target.id)
        let following = makeTestBoard("Following")
        let sourceDesk = makeTestDesk(
            "Desk",
            boards: [target, side, following],
            focusedBoardID: [target.id, side.id][focusedIndex]
        )
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        // Act
        let insertedID = try #require(session.boardOpening.createBoard(urlString: "https://new.example"))

        // Assert
        #expect(session.resources.state.desks[0].boards.map(\.id) == [target.id, side.id, insertedID, following.id])
    }

    @Test(arguments: [BoardState.minimumWidth, BuiltInDeskPreset.boardWidth, BoardState.maximumWidth])
    func inspectionBoardStartsAtCompactWidthRegardlessOfTargetWidth(targetWidth: Double) throws {
        // Arrange
        let target = BoardState(
            label: "Target",
            width: targetWidth,
            currentSheetURL: URL(string: "https://example.com")
        )
        let sourceDesk = makeTestDesk("Desk", boards: [target], focusedBoardID: target.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        // Act
        let inspectionID = try #require(session.sideBoards.createInspectionBoard(targetBoardID: target.id))
        let inspection = try #require(session.resources.state.board(for: inspectionID))

        // Assert
        #expect(inspection.width == 360)
    }

    @Test func inspectionBoardRequiresSideBoardRoleToDecode() {
        let boardID = UUID()
        let data = Data(
            """
            {"id":"\(boardID.uuidString)","label":"Inspection Board","width":390,"content":{"kind":"inspection"}}
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BoardState.self, from: data)
        }
    }

    @Test func boardWithoutRoleDecodesAsPrimary() throws {
        let boardID = UUID()
        let data = Data(
            """
            {"id":"\(boardID.uuidString)","label":"Web","width":520,"content":{"kind":"web"}}
            """.utf8
        )

        let board = try JSONDecoder().decode(BoardState.self, from: data)

        #expect(board.role == .primary)
    }

    @Test func boardGroupKeepsSideRoleSeparateFromBoardContent() throws {
        let target = makeTestBoard("Target")
        var side = BoardState(label: "Side Terminal", width: 390, workingDirectory: "/tmp")
        side.role = .sideBoard(targetBoardID: target.id)

        let group = try #require(BoardGroup.containing(side.id, in: [target, side]))

        #expect(!side.isInspection)
        #expect(group.primaryBoard.id == target.id)
        #expect(group.sideBoard?.id == side.id)
        #expect(group.boards.map(\.id) == [target.id, side.id])
        let encoded = try JSONEncoder().encode(side)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let role = try #require(object["role"] as? [String: Any])
        #expect(role["kind"] as? String == "sideBoard")
        #expect(role["targetBoardID"] as? String == target.id.rawValue.uuidString)
        #expect(object["sideBoard"] == nil)
        #expect(try JSONDecoder().decode(BoardState.self, from: encoded) == side)
    }
}
