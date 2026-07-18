import Foundation
import SwiftUI
import WebKit

enum ProfileColor: String, CaseIterable, Codable, Identifiable {
    case blue, purple, pink, green, yellow, gray

    var id: Self { self }

    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .green: .green
        case .yellow: .yellow
        case .gray: .gray
        }
    }

    var label: String { rawValue.capitalized }
}

enum WebProfileStore: Equatable, Sendable {
    case `default`
    case identified(UUID)

    var websiteDataStore: WKWebsiteDataStore {
        switch self {
        case .default:
            .default()
        case .identified(let identifier):
            WKWebsiteDataStore(forIdentifier: identifier)
        }
    }
}

extension WebProfileStore: Codable {
    private enum CodingKeys: String, CodingKey { case kind, identifier }
    private enum Kind: String, Codable { case `default`, identified }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .default:
            guard !container.contains(.identifier) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .identifier, in: container, debugDescription: "Default store cannot have an identifier")
            }
            self = .default
        case .identified:
            self = .identified(try container.decode(UUID.self, forKey: .identifier))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .default:
            try container.encode(Kind.default, forKey: .kind)
        case .identified(let identifier):
            try container.encode(Kind.identified, forKey: .kind)
            try container.encode(identifier, forKey: .identifier)
        }
    }
}

struct ProfileState: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var color: ProfileColor
    var webProfileStore: WebProfileStore
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
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container, debugDescription: "Unsupported ProfileIndex schema")
        }
        profileIDs = try container.decode([UUID].self, forKey: .profileIDs)
    }
}

struct PersistedProfile: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var profile: ProfileState
    var den: DenState
    var deskPresets: [PersonalDeskPreset]

    init(profile: ProfileState, den: DenState, deskPresets: [PersonalDeskPreset] = []) {
        self.profile = profile
        self.den = den
        self.deskPresets = deskPresets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container, debugDescription: "Unsupported PersistedProfile schema")
        }
        profile = try container.decode(ProfileState.self, forKey: .profile)
        den = try container.decode(DenState.self, forKey: .den)
        deskPresets = try container.decodeIfPresent([PersonalDeskPreset].self, forKey: .deskPresets) ?? []
    }
}
