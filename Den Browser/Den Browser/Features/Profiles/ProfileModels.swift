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

enum RecentItem: Codable, Equatable, Hashable, Identifiable {
    case url(URL)
    case search(String)

    private enum CodingKeys: String, CodingKey { case kind, url, query }
    private enum Kind: String, Codable { case url, search }

    var id: Self { self }

    var displayText: String {
        switch self {
        case .url(let url): url.absoluteString
        case .search(let query): query
        }
    }

    var systemImage: String {
        switch self {
        case .url: "link"
        case .search: "magnifyingglass"
        }
    }

    private var normalizedValue: String {
        switch self {
        case .url(let url):
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url.absoluteString
            }
            components.scheme = components.scheme?.lowercased()
            components.host = components.host?.lowercased()
            if (components.scheme == "https" && components.port == 443)
                || (components.scheme == "http" && components.port == 80)
            {
                components.port = nil
            }
            if components.path.isEmpty { components.path = "/" }
            return components.string ?? url.absoluteString
        case .search(let query):
            return query.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.url, .url), (.search, .search):
            lhs.normalizedValue == rhs.normalizedValue
        default:
            false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .url: hasher.combine(0)
        case .search: hasher.combine(1)
        }
        hasher.combine(normalizedValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .url:
            self = .url(try container.decode(URL.self, forKey: .url))
        case .search:
            self = .search(try container.decode(String.self, forKey: .query))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .url(let url):
            try container.encode(Kind.url, forKey: .kind)
            try container.encode(url, forKey: .url)
        case .search(let query):
            try container.encode(Kind.search, forKey: .kind)
            try container.encode(query, forKey: .query)
        }
    }
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
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container, debugDescription: "Unsupported PersistedProfile schema")
        }
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

enum BrowsingDataCategory: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case cookies
    case cache
    case localData

    var id: Self { self }

    var label: String {
        switch self {
        case .cookies: "Cookies and Site Data"
        case .cache: "Cached Images and Files"
        case .localData: "Local Storage and Databases"
        }
    }

    var description: String {
        switch self {
        case .cookies: "Signs you out of most web sites."
        case .cache: "Frees up disk space and forces fresh site resources to load."
        case .localData: "Clears offline site data and saved web application states."
        }
    }

    var websiteDataTypes: Set<String> {
        switch self {
        case .cookies:
            [WKWebsiteDataTypeCookies]
        case .cache:
            [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
        case .localData:
            [
                WKWebsiteDataTypeLocalStorage,
                WKWebsiteDataTypeIndexedDBDatabases,
                WKWebsiteDataTypeWebSQLDatabases,
            ]
        }
    }
}

extension Collection where Element == BrowsingDataCategory {
    var websiteDataTypes: Set<String> {
        Set(flatMap(\.websiteDataTypes))
    }
}
