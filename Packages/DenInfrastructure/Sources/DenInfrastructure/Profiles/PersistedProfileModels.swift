import DenDomain
import Foundation

public enum ProfilePersistenceError: Error {
    case unsupportedProfileIndexSchema(Int)
    case unsupportedPersistedProfileSchema(Int)
    case duplicateProfileIDs
}

public struct ProfileIndex: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = currentSchemaVersion
    public var profileIDs: [ProfileID]

    public init(profileIDs: [ProfileID]) {
        self.profileIDs = profileIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ProfilePersistenceError.unsupportedProfileIndexSchema(schemaVersion)
        }
        profileIDs = try container.decode([ProfileID].self, forKey: .profileIDs)
        guard Set(profileIDs).count == profileIDs.count else {
            throw ProfilePersistenceError.duplicateProfileIDs
        }
    }
}

public struct PersistedProfile: Codable, Equatable {
    public static let currentSchemaVersion = 3
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, profile, den, deskPresets, recentItems
    }

    public var schemaVersion = currentSchemaVersion
    public var profile: ProfileState
    public var den: DenState
    public var deskPresets: [PersonalDeskPreset]
    public var recentItems: [RecentItem]

    public init(
        profile: ProfileState,
        den: DenState,
        deskPresets: [PersonalDeskPreset] = [],
        recentItems: [RecentItem] = []
    ) {
        self.profile = profile
        self.den = den
        self.deskPresets = deskPresets
        self.recentItems = recentItems
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw ProfilePersistenceError.unsupportedPersistedProfileSchema(decodedSchemaVersion)
        }
        schemaVersion = decodedSchemaVersion
        profile = try container.decode(ProfileState.self, forKey: .profile)
        den = try container.decode(DenState.self, forKey: .den)
        deskPresets = try container.decodeIfPresent([PersonalDeskPreset].self, forKey: .deskPresets) ?? []
        recentItems = try container.decodeIfPresent([RecentItem].self, forKey: .recentItems) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(profile, forKey: .profile)
        try container.encode(den, forKey: .den)
        try container.encode(deskPresets, forKey: .deskPresets)
        if !recentItems.isEmpty {
            try container.encode(recentItems, forKey: .recentItems)
        }
    }
}
