import DenDomain
import Foundation
import Testing

struct ProfileIDTests {
    @Test func encodesAndDecodesAsFoundationUUIDJSONScalar() throws {
        // Arrange
        let uuid = UUID()
        let profileID = ProfileID(uuid)
        let uuidData = try JSONEncoder().encode(uuid)

        // Act
        let profileIDData = try JSONEncoder().encode(profileID)
        let decoded = try JSONDecoder().decode(ProfileID.self, from: uuidData)

        // Assert
        #expect(profileIDData == uuidData)
        #expect(decoded == profileID)
    }
}
