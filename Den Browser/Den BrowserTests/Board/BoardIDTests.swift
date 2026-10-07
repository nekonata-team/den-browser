import DenDomain
import Foundation
import Testing

struct BoardIDTests {
    @Test func encodesAndDecodesAsFoundationUUIDJSONScalar() throws {
        // Arrange
        let uuid = UUID()
        let boardID = BoardID(uuid)
        let uuidData = try JSONEncoder().encode(uuid)

        // Act
        let boardIDData = try JSONEncoder().encode(boardID)
        let decoded = try JSONDecoder().decode(BoardID.self, from: uuidData)

        // Assert
        #expect(boardIDData == uuidData)
        #expect(decoded == boardID)
    }
}
