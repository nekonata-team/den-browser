import DenDomain
import Foundation
import Testing

struct ProfileColorTests {
    @Test func customProfileColorRoundTrips() throws {
        // Arrange
        let color = ProfileColor.custom(ProfileRGB(red: 58, green: 134, blue: 255))

        // Act
        let encoded = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(ProfileColor.self, from: encoded)

        // Assert
        #expect(decoded == color)
    }

    @Test func profileColorDecodesPersistedPresetString() throws {
        // Arrange
        let data = Data("\"purple\"".utf8)

        // Act
        let decoded = try JSONDecoder().decode(ProfileColor.self, from: data)

        // Assert
        #expect(decoded == .purple)
    }
}
