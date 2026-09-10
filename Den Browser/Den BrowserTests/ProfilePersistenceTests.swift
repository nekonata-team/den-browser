import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct ProfilePersistenceTests {

    @Test func profileModelsRoundTrip() throws {
        // Arrange
        let profile = ProfileState(
            id: UUID(), name: "Work", color: .purple, webProfileStore: .identified(UUID()))
        let persisted = PersistedProfile(profile: profile, den: .sample)

        // Act
        let encoded = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(PersistedProfile.self, from: encoded)

        // Assert
        #expect(decoded == persisted)
    }

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

    @Test func profileModelsRejectUnknownSchemaVersion() {
        // Arrange
        let invalidData = Data("{\"schemaVersion\":3,\"profile\":{},\"den\":{}}".utf8)

        // Act
        let performDecode = {
            try JSONDecoder().decode(PersistedProfile.self, from: invalidData)
        }

        // Assert
        #expect(throws: DecodingError.self, performing: performDecode)
    }

    @Test func profileIndexRejectsUnknownSchemaVersion() {
        // Arrange
        let invalidData = Data("{\"schemaVersion\":2,\"profileIDs\":[]}".utf8)

        // Act
        let performDecode = {
            try JSONDecoder().decode(ProfileIndex.self, from: invalidData)
        }

        // Assert
        #expect(throws: DecodingError.self, performing: performDecode)
    }

    @Test func profilePersistsBoardSheetNavigationPause() throws {
        // Arrange
        let board = BoardState(
            label: "Paused",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/"),
            sheetNavigationPaused: true)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let profile = ProfileState(
            id: UUID(), name: "Work", color: .purple, webProfileStore: .identified(UUID()))
        let persisted = PersistedProfile(
            profile: profile,
            den: DenState(desks: [desk], focusedDeskID: desk.id))

        // Act
        let encoded = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(PersistedProfile.self, from: encoded)

        // Assert
        #expect(decoded.den.desks[0].boards[0].sheetNavigationPaused)
    }

    @Test func profileDocumentWithoutDeskPresetsLoadsEmptyList() throws {
        // Arrange
        let profile = ProfileState(
            id: UUID(), name: "Work", color: .purple, webProfileStore: .identified(UUID()))
        let encoded = try JSONEncoder().encode(PersistedProfile(profile: profile, den: .sample))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["deskPresets"] != nil)
        object.removeValue(forKey: "deskPresets")
        let dataWithoutPresets = try JSONSerialization.data(withJSONObject: object)

        // Act
        let decoded = try JSONDecoder().decode(PersistedProfile.self, from: dataWithoutPresets)

        // Assert
        #expect(decoded.schemaVersion == 2)
        #expect(decoded.deskPresets.isEmpty)
    }

    @Test func profileDocumentWithoutRecentItemsLoadsEmptyList() throws {
        // Arrange
        let profile = ProfileState(
            id: UUID(), name: "Work", color: .purple, webProfileStore: .identified(UUID()))
        let recentItems: [RecentItem] = [
            .url(URL(string: "https://example.com")!),
            .search("Swift"),
            .terminal(workingDirectory: "/tmp"),
            .zellij(sessionName: nil),
            .zellij(sessionName: "project-a"),
            .zmx(sessionName: "project-a"),
        ]
        let encoded = try JSONEncoder().encode(
            PersistedProfile(
                profile: profile,
                den: .sample,
                recentItems: recentItems))
        #expect(
            try JSONDecoder().decode(PersistedProfile.self, from: encoded).recentItems == recentItems)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "recentItems")
        let dataWithoutRecentItems = try JSONSerialization.data(withJSONObject: object)

        // Act
        let decoded = try JSONDecoder().decode(PersistedProfile.self, from: dataWithoutRecentItems)

        // Assert
        #expect(decoded.recentItems.isEmpty)
    }

    @Test func versionOneFixturesMigrateToVersionTwo() throws {
        // Arrange
        let profileData = try fixtureData("persisted-profile-v1")
        let indexData = try fixtureData("profile-index-v1")

        // Act
        let persisted = try JSONDecoder().decode(PersistedProfile.self, from: profileData)
        let index = try JSONDecoder().decode(ProfileIndex.self, from: indexData)

        // Assert
        #expect(persisted.schemaVersion == 2)
        #expect(persisted.den.desks[0].boards[1].currentSheetURL == nil)
        #expect(persisted.den.desks[0].boards[0].firstSheetURL == nil)
        #expect(persisted.den.desks[0].boards.allSatisfy { !$0.sheetNavigationPaused })
        #expect(persisted.deskPresets[0].boards[1].initialSheetURL == nil)
        #expect(index == ProfileIndex(profileIDs: [persisted.profile.id]))

        let migrated = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(persisted)) as? [String: Any])
        #expect(migrated["schemaVersion"] as? Int == 2)
        #expect(try jsonObject(JSONEncoder().encode(index)).isEqual(jsonObject(indexData)))

        // Extra fields are preserved
        var futureObject = try #require(JSONSerialization.jsonObject(with: profileData) as? [String: Any])
        futureObject["futureField"] = true
        #expect(
            try JSONDecoder().decode(
                PersistedProfile.self,
                from: JSONSerialization.data(withJSONObject: futureObject)) == persisted)

        // Missing required field fails
        futureObject.removeValue(forKey: "profile")
        #expect(
            throws: DecodingError.self,
            performing: {
                try JSONDecoder().decode(
                    PersistedProfile.self,
                    from: JSONSerialization.data(withJSONObject: futureObject))
            })
    }

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

    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(
            Bundle(for: PersistenceFixtureBundleToken.self)
                .url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func jsonObject(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}

private final class PersistenceFixtureBundleToken {}
