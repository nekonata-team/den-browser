import DenIPCProtocol
import Foundation
import Testing

struct DenDrawerItemInfoTests {
    @Test func terminalItemsRoundTripWithoutAURL() throws {
        // Arrange
        let item = DenDrawerItemInfo(
            id: UUID().uuidString, title: "Project", type: "zmx",
            workingDirectory: "/work", sessionName: "project")

        // Act
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(DenDrawerItemInfo.self, from: data)

        // Assert
        #expect(decoded.id == item.id)
        #expect(decoded.type == "zmx")
        #expect(decoded.url == nil)
        #expect(decoded.workingDirectory == "/work")
        #expect(decoded.sessionName == "project")
    }

    @Test func legacyWebItemsWithoutATypeRemainReadable() throws {
        // Arrange
        let data = Data(#"{"id":"item","url":"https://example.com/","title":"Web"}"#.utf8)

        // Act
        let item = try JSONDecoder().decode(DenDrawerItemInfo.self, from: data)

        // Assert
        #expect(item.type == "web")
        #expect(item.url == "https://example.com/")
    }
}
