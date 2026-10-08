import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

struct DenIPCOperationResultTests {
    @Test func publicProjectionKeepsElementValuesAndOmitsAbsentFields() throws {
        // Arrange
        let element = DenSheetElementInfo(
            ref: "@e1",
            tag: "input",
            role: "textbox",
            name: "Subject",
            value: "",
            checked: false,
            disabled: false,
            visible: false,
            attributes: ["class": "subject"]
        )
        // Act
        let data = try JSONEncoder().encode(DenIPCOperationResult.success(.elements([element])).publicJSON)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedElement = try #require(object["elements"] as? [[String: Any]])[0]

        // Assert
        #expect(object["ok"] as? Bool == true)
        #expect(object["error"] == nil)
        #expect(object["snapshot"] == nil)
        #expect(object["value"] == nil)
        #expect(encodedElement["ref"] as? String == "@e1")
        #expect(encodedElement["visible"] as? Bool == false)
        #expect(encodedElement["value"] as? String == "")
        #expect((encodedElement["checked"] as? NSNumber)?.boolValue == false)
        #expect((encodedElement["disabled"] as? NSNumber)?.boolValue == false)
    }

    @Test func publicProjectionKeepsEmptyAndFalseScalarValues() throws {
        // Arrange
        let emptyValue = DenIPCOperationResult.success(.value(""))
        let falseValue = DenIPCOperationResult.success(.checked(false))

        // Act
        let emptyData = try JSONEncoder().encode(emptyValue.publicJSON)
        let falseData = try JSONEncoder().encode(falseValue.publicJSON)
        let emptyObject = try #require(JSONSerialization.jsonObject(with: emptyData) as? [String: Any])
        let falseObject = try #require(JSONSerialization.jsonObject(with: falseData) as? [String: Any])

        // Assert
        #expect(emptyObject["value"] as? String == "")
        #expect((falseObject["checked"] as? NSNumber)?.boolValue == false)
    }

    @Test func publicProjectionKeepsBoardIdentityWithBoardDetails() throws {
        // Arrange
        let board = DenBoardInfo(
            id: "4F72344C-F4E3-438D-99CB-2F12A79F0004",
            type: "inspection",
            label: "Example",
            targetBoardID: "A9A24751-62CD-4C0D-9E1A-4EB0B63EB122",
            isFocused: true
        )
        // Act
        let data = try JSONEncoder().encode(DenIPCOperationResult.success(.board(board)).publicJSON)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedBoard = try #require(object["board"] as? [String: Any])

        // Assert
        #expect(object["board_id"] as? String == board.id)
        #expect(encodedBoard["id"] as? String == board.id)
        #expect(encodedBoard["type"] as? String == "inspection")
        #expect(encodedBoard["target_board_id"] as? String == "A9A24751-62CD-4C0D-9E1A-4EB0B63EB122")
        #expect(encodedBoard["is_focused"] as? Bool == true)
    }

    @Test func failedInteractResultKeepsProgressAndSnapshot() throws {
        // Arrange
        let result = DenIPCOperationResult.failure(
            "Element not found: @e3",
            payload: .interaction(completedActions: 2, failedActionIndex: 2),
            snapshot: "@e1 button \"Done\""
        )
        // Act
        let data = try JSONEncoder().encode(result.publicJSON)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Assert
        #expect(object["ok"] as? Bool == false)
        #expect(object["error"] as? String == "Element not found: @e3")
        #expect(object["snapshot"] as? String == "@e1 button \"Done\"")
        #expect((object["completed_actions"] as? NSNumber)?.intValue == 2)
        #expect((object["failed_action_index"] as? NSNumber)?.intValue == 2)
    }

    @Test func postProcessingFailureRetainsSuccessfulPayloadAndSnapshot() throws {
        // Arrange
        let successfulResult = DenIPCOperationResult.success(
            .sheet(boardID: "board-1", url: "https://example.com/"),
            snapshot: "button \"Continue\""
        )

        // Act
        let result = successfulResult.failing(with: "Command succeeded, but snapshot failed")
        let data = try JSONEncoder().encode(result.publicJSON)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Assert
        #expect(object["ok"] as? Bool == false)
        #expect(object["error"] as? String == "Command succeeded, but snapshot failed")
        #expect(object["board_id"] as? String == "board-1")
        #expect(object["url"] as? String == "https://example.com/")
        #expect(object["snapshot"] as? String == "button \"Continue\"")
    }

    @Test func inspectionPayloadUsesStableSnakeCaseJSONFields() throws {
        // Arrange
        let selection = DenInspectionElementInfo(
            nodeID: "n1",
            ref: "@e1",
            selector: "html > body > input",
            tag: "input",
            id: "email",
            className: "",
            role: "textbox",
            ariaLabel: "Email",
            text: "",
            attributes: ["type=\"email\""],
            labels: ["Email"],
            capturedAt: "2026-09-26T00:00:00.000Z",
            isConnected: true)
        let inspection = DenInspectionReadInfo(
            boardID: "inspection-board",
            targetBoardID: "web-board",
            url: "https://example.com/",
            pageGeneration: 3,
            documentID: "document-1",
            capturedAt: "2026-09-26T00:00:01.000Z",
            collectionStartedAt: "2026-09-26T00:00:00.000Z",
            selection: selection,
            ancestors: [],
            events: [
                DenInspectionEventInfo(
                    id: "event-1", time: "2026-09-26T00:00:00.500Z", level: "log", message: "loaded")
            ],
            eventsDropped: 2)
        // Act
        let result = DenIPCOperationResult.success(.inspection(inspection))
        let data = try JSONEncoder().encode(result.publicJSON)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedInspection = try #require(object["inspection"] as? [String: Any])
        let encodedSelection = try #require(encodedInspection["selection"] as? [String: Any])

        // Assert
        #expect(object["board_id"] as? String == inspection.boardID)
        #expect(encodedInspection["target_board_id"] as? String == "web-board")
        #expect(encodedInspection["document_id"] as? String == "document-1")
        #expect(encodedInspection["events_dropped"] as? Int == 2)
        #expect(encodedSelection["node_id"] as? String == "n1")
        #expect(encodedSelection["captured_at"] as? String == "2026-09-26T00:00:00.000Z")
        #expect(encodedSelection["is_connected"] as? Bool == true)

        var unselected = inspection
        unselected.selection = nil
        let unselectedResult = DenIPCOperationResult.success(.inspection(unselected))
        let unselectedData = try JSONEncoder().encode(unselectedResult.publicJSON)
        let unselectedObject = try #require(JSONSerialization.jsonObject(with: unselectedData) as? [String: Any])
        let unselectedInspection = try #require(unselectedObject["inspection"] as? [String: Any])
        #expect(unselectedInspection["selection"] is NSNull)
    }

    @Test func publicProjectionKeepsBoundingBoxShape() throws {
        // Arrange
        let box = DenBoundingBox(originX: 10, originY: 20, width: 300, height: 150)
        let result = DenIPCOperationResult.success(.box(box))

        // Act
        let data = try JSONEncoder().encode(result.publicJSON)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedBox = try #require(object["box"] as? [String: Any])

        // Assert
        #expect(encodedBox["x"] as? Double == 10)
        #expect(encodedBox["y"] as? Double == 20)
        #expect(encodedBox["width"] as? Double == 300)
        #expect(encodedBox["height"] as? Double == 150)
    }
}
