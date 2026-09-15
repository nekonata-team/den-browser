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
}
