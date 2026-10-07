import DenDomain
import Foundation
import Testing

struct DeskIDTests {
    @Test func encodesAndDecodesAsFoundationUUIDJSONScalar() throws {
        // Arrange
        let uuid = UUID()
        let deskID = DeskID(uuid)
        let uuidData = try JSONEncoder().encode(uuid)

        // Act
        let deskIDData = try JSONEncoder().encode(deskID)
        let decoded = try JSONDecoder().decode(DeskID.self, from: uuidData)

        // Assert
        #expect(deskIDData == uuidData)
        #expect(decoded == deskID)
    }
}
