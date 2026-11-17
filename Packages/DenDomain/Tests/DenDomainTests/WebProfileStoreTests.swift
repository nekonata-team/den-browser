import DenDomain
import Foundation
import Testing

struct WebProfileStoreTests {
    @Test func webProfileStoreRejectsDefaultKindWithIdentifier() {
        // Arrange
        let invalidData = Data("{\"kind\":\"default\",\"identifier\":\"\(UUID())\"}".utf8)

        // Act
        let performDecode = {
            try JSONDecoder().decode(WebProfileStore.self, from: invalidData)
        }

        // Assert
        #expect(throws: DecodingError.self, performing: performDecode)
    }

    @Test func webProfileStoreRejectsIdentifiedKindWithoutIdentifier() {
        // Arrange
        let invalidData = Data("{\"kind\":\"identified\"}".utf8)

        // Act
        let performDecode = {
            try JSONDecoder().decode(WebProfileStore.self, from: invalidData)
        }

        // Assert
        #expect(throws: DecodingError.self, performing: performDecode)
    }
}
