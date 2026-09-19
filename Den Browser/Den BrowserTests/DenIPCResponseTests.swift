import Foundation
import Testing

@testable import Den_Browser

struct DenIPCResponseTests {
    @Test func sheetPayloadKeepsEmptyAndFalseValuesInJSON() throws {
        // Arrange
        let element = DenSheetElementInfo(
            ref: "@e1",
            tag: "input",
            role: "textbox",
            name: "Subject",
            text: nil,
            value: "",
            checked: false,
            disabled: false,
            selected: nil,
            expanded: nil,
            visible: false,
            attributes: ["class": "subject"]
        )
        let response = DenIPCResponse.success(
            elements: [element],
            value: "",
            checked: false
        )

        // Act
        let data = try JSONEncoder().encode(response)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedElement = try #require(object["elements"] as? [[String: Any]])[0]

        // Assert
        #expect(object["ok"] as? Bool == true)
        #expect(object["value"] as? String == "")
        #expect((object["checked"] as? NSNumber)?.boolValue == false)
        #expect(encodedElement["ref"] as? String == "@e1")
        #expect(encodedElement["visible"] as? Bool == false)
        #expect(encodedElement["value"] as? String == "")
        #expect((encodedElement["checked"] as? NSNumber)?.boolValue == false)
    }

    @Test func failedInteractResponseKeepsProgressAndSnapshot() throws {
        // Arrange
        let response = DenIPCResponse.failure(
            "Element not found: @e3",
            snapshot: "@e1 button \"Done\"",
            completedActions: 2,
            failedActionIndex: 2
        )

        // Act
        let data = try JSONEncoder().encode(response)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Assert
        #expect(object["ok"] as? Bool == false)
        #expect(object["snapshot"] as? String == "@e1 button \"Done\"")
        #expect((object["completed_actions"] as? NSNumber)?.intValue == 2)
        #expect((object["failed_action_index"] as? NSNumber)?.intValue == 2)
    }

    @Test func boardPayloadKeepsFocusedStateInJSON() throws {
        // Arrange
        let board = DenBoardInfo(
            id: "4F72344C-F4E3-438D-99CB-2F12A79F0004",
            type: "web",
            label: "Example",
            url: "https://example.com",
            sessionName: nil,
            isFocused: true
        )
        let response = DenIPCResponse.success(
            boardId: board.id,
            board: board,
            boards: [board]
        )

        // Act
        let data = try JSONEncoder().encode(response)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedBoard = try #require(object["board"] as? [String: Any])
        let encodedBoards = try #require(object["boards"] as? [[String: Any]])

        // Assert
        #expect(object["ok"] as? Bool == true)
        #expect(object["board_id"] as? String == "4F72344C-F4E3-438D-99CB-2F12A79F0004")
        #expect(encodedBoard["id"] as? String == "4F72344C-F4E3-438D-99CB-2F12A79F0004")
        #expect(encodedBoard["type"] as? String == "web")
        #expect(encodedBoard["is_focused"] as? Bool == true)
        #expect(encodedBoards.first?["is_focused"] as? Bool == true)
    }

    @Test func boxPayloadKeepsBoundingBoxInJSON() throws {
        // Arrange
        let box = DenBoundingBox(originX: 10, originY: 20, width: 300, height: 150)
        let response = DenIPCResponse.success(box: box)

        // Act
        let data = try JSONEncoder().encode(response)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedBox = try #require(object["box"] as? [String: Any])

        // Assert
        #expect(object["ok"] as? Bool == true)
        #expect(encodedBox["x"] as? Double == 10)
        #expect(encodedBox["y"] as? Double == 20)
        #expect(encodedBox["width"] as? Double == 300)
        #expect(encodedBox["height"] as? Double == 150)
    }
}
