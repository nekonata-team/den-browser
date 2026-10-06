import DenDomain
import Foundation

enum ProfilePersistenceError: Error {
    case unsupportedProfileIndexSchema(Int)
    case unsupportedPersistedProfileSchema(Int)
    case duplicateProfileIDs
}

struct ProfileIndex: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var profileIDs: [UUID]

    init(profileIDs: [UUID]) {
        self.profileIDs = profileIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ProfilePersistenceError.unsupportedProfileIndexSchema(schemaVersion)
        }
        profileIDs = try container.decode([UUID].self, forKey: .profileIDs)
        guard Set(profileIDs).count == profileIDs.count else {
            throw ProfilePersistenceError.duplicateProfileIDs
        }
    }
}

struct PersistedProfile: Codable, Equatable {
    static let currentSchemaVersion = 3
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, profile, den, deskPresets, recentItems
    }

    var schemaVersion = currentSchemaVersion
    var profile: ProfileState
    var den: DenState
    var deskPresets: [PersonalDeskPreset]
    var recentItems: [RecentItem]

    init(
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

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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
