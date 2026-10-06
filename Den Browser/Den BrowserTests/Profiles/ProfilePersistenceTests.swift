import DenDomain
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
        let invalidData = Data("{\"schemaVersion\":4,\"profile\":{},\"den\":{}}".utf8)

        // Act
        let performDecode = {
            try JSONDecoder().decode(PersistedProfile.self, from: invalidData)
        }

        // Assert
        #expect(throws: ProfilePersistenceError.self, performing: performDecode)
    }

    @Test func profileIndexRejectsUnknownSchemaVersion() {
        // Arrange
        let invalidData = Data("{\"schemaVersion\":2,\"profileIDs\":[]}".utf8)

        // Act
        let performDecode = {
            try JSONDecoder().decode(ProfileIndex.self, from: invalidData)
        }

        // Assert
        #expect(throws: ProfilePersistenceError.self, performing: performDecode)
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
        #expect(decoded.schemaVersion == 3)
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

    @Test func versionOneFixturesMigrateToVersionThree() throws {
        // Arrange
        var profileObject = try #require(
            JSONSerialization.jsonObject(with: fixtureData("persisted-profile-v1")) as? [String: Any])
        var den = try #require(profileObject["den"] as? [String: Any])
        var desks = try #require(den["desks"] as? [[String: Any]])
        var boards = try #require(desks[0]["boards"] as? [[String: Any]])
        boards[0]["currentSheetURL"] = "https://example.com"
        desks[0]["boards"] = boards
        den["desks"] = desks
        profileObject["den"] = den
        let profileData = try JSONSerialization.data(withJSONObject: profileObject)
        let indexData = try fixtureData("profile-index-v1")

        // Act
        let persisted = try PersistedProfileDocumentDecoder.decode(profileData)
        let index = try JSONDecoder().decode(ProfileIndex.self, from: indexData)

        // Assert
        #expect(persisted.schemaVersion == 3)
        #expect(persisted.den.desks[0].boards[0].currentSheetURL?.absoluteString == "https://example.com/")
        #expect(persisted.den.desks[0].boards[1].currentSheetURL == nil)
        #expect(persisted.den.desks[0].boards[0].firstSheetURL == nil)
        #expect(persisted.den.desks[0].boards.allSatisfy { !$0.sheetNavigationPaused })
        #expect(persisted.deskPresets[0].boards[1].initialSheetURL == nil)
        #expect(index == ProfileIndex(profileIDs: [persisted.profile.id]))

        let migrated = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(persisted)) as? [String: Any])
        #expect(migrated["schemaVersion"] as? Int == 3)
        #expect(try jsonObject(JSONEncoder().encode(index)).isEqual(jsonObject(indexData)))

        // Extra fields are preserved
        var futureObject = try #require(JSONSerialization.jsonObject(with: profileData) as? [String: Any])
        futureObject["futureField"] = true
        #expect(
            try PersistedProfileDocumentDecoder.decode(JSONSerialization.data(withJSONObject: futureObject))
                == persisted)

        // Missing required field fails
        futureObject.removeValue(forKey: "profile")
        #expect(
            throws: DecodingError.self,
            performing: {
                try PersistedProfileDocumentDecoder.decode(JSONSerialization.data(withJSONObject: futureObject))
            })
    }

    @Test func versionTwoBoardContentMigratesToCanonicalVersionThree() throws {
        let persisted = try PersistedProfileDocumentDecoder.decode(fixtureData("persisted-profile-v2"))
        let boards = persisted.den.desks[0].boards
        #expect(persisted.schemaVersion == 3)
        #expect(boards.count == 5)
        #expect(boards[0].currentSheetURL?.absoluteString == "https://example.com/current")
        #expect(boards[0].firstSheetURL?.absoluteString == "https://example.com/first")
        #expect(boards[0].sheetNavigationPaused)
        #expect(boards[1].sideBoardTargetBoardID == boards[0].id)
        #expect(boards[2].terminalWorkingDirectory == "/work")
        #expect(boards[3].zellijSessionName == "project")
        #expect(boards[4].zmxSessionName == "project-zmx")
        #expect(boards[4].terminalWorkingDirectory == "/work/zmx")
        #expect(persisted.deskPresets[0].boards.map(\.targetBoardIndex) == [nil, 0, nil, nil, nil])
        #expect(persisted.deskPresets[0].boards[1].kind == .inspection)
        #expect(persisted.deskPresets[0].boards[2].terminalWorkingDirectory == "/preset")
        #expect(persisted.deskPresets[0].boards[3].zellijSessionName == "preset-zellij")
        #expect(persisted.deskPresets[0].boards[4].zmxSessionName == "preset-zmx")
        #expect(
            persisted.deskPresets[0].boards[4].kind
                == .terminal(.zmx(sessionName: "preset-zmx", rootSessionName: nil)))

        let encoded = try JSONEncoder().encode(persisted)
        let object = try jsonObject(encoded)
        #expect((object["schemaVersion"] as? NSNumber)?.intValue == 3)
        let den = try #require(object["den"] as? NSDictionary)
        let desks = try #require(den["desks"] as? [NSDictionary])
        let encodedBoards = try #require(desks[0]["boards"] as? [NSDictionary])
        let encodedRole = try #require(encodedBoards[1]["role"] as? NSDictionary)
        #expect(encodedRole["targetBoardID"] as? String == boards[0].id.uuidString)
        let webContent = try #require(encodedBoards[0]["content"] as? NSDictionary)
        #expect(webContent["kind"] as? String == "web")
        #expect(webContent["sheetNavigationPaused"] as? Bool == true)
        #expect(encodedBoards[0]["sheetNavigationPaused"] == nil)
        let shellSession = try #require(
            (encodedBoards[2]["content"] as? NSDictionary)?["session"] as? NSDictionary)
        #expect(shellSession["kind"] as? String == "shell")
        let zellijSession = try #require(
            (encodedBoards[3]["content"] as? NSDictionary)?["session"] as? NSDictionary)
        #expect(zellijSession["kind"] as? String == "zellij")
        let zmxSession = try #require(
            (encodedBoards[4]["content"] as? NSDictionary)?["session"] as? NSDictionary)
        #expect(zmxSession["kind"] as? String == "zmx")
        let presets = try #require(object["deskPresets"] as? [NSDictionary])
        let presetBoards = try #require(presets[0]["boards"] as? [NSDictionary])
        #expect(presetBoards[1]["targetBoardIndex"] as? Int == 0)
        let presetShell = try #require(
            (presetBoards[2]["content"] as? NSDictionary)?["session"] as? NSDictionary)
        #expect(presetShell["kind"] as? String == "shell")
        let presetZellij = try #require(
            (presetBoards[3]["content"] as? NSDictionary)?["session"] as? NSDictionary)
        #expect(presetZellij["kind"] as? String == "zellij")
        let presetZmx = try #require(
            (presetBoards[4]["content"] as? NSDictionary)?["session"] as? NSDictionary)
        #expect(presetZmx["kind"] as? String == "zmx")
        #expect(try JSONDecoder().decode(PersistedProfile.self, from: encoded) == persisted)
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
