import AppKit
import Foundation
import SFSafeSymbols
import SwiftUI
import WebKit

struct ProfileRGB: Codable, Equatable, Hashable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var color: Color {
        Color(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1)
    }

    init?(color: Color) {
        guard let color = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: Self.component(color.redComponent),
            green: Self.component(color.greenComponent),
            blue: Self.component(color.blueComponent))
    }

    private static func component(_ value: CGFloat) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }
}

enum ProfileColor: Codable, Equatable, Hashable, Identifiable {
    case blue, purple, pink, green, yellow, gray
    case custom(ProfileRGB)

    static let presets: [ProfileColor] = [.blue, .purple, .pink, .green, .yellow, .gray]

    var id: Self { self }

    var rgb: ProfileRGB {
        switch self {
        case .custom(let rgb): rgb
        default: ProfileRGB(color: color) ?? ProfileRGB(red: 0, green: 0, blue: 0)
        }
    }

    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .green: .green
        case .yellow: .yellow
        case .gray: .gray
        case .custom(let rgb): rgb.color
        }
    }

    var label: String {
        switch self {
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .green: "Green"
        case .yellow: "Yellow"
        case .gray: "Gray"
        case .custom: "Custom"
        }
    }

    init?(color: Color) {
        guard let rgb = ProfileRGB(color: color) else { return nil }
        self = .custom(rgb)
    }

    private enum CodingKeys: String, CodingKey { case kind, red, green, blue }
    private enum Kind: String, Codable { case sRGB }

    init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        if let preset = try? singleValue.decode(String.self) {
            switch preset {
            case "blue": self = .blue
            case "purple": self = .purple
            case "pink": self = .pink
            case "green": self = .green
            case "yellow": self = .yellow
            case "gray": self = .gray
            default:
                throw DecodingError.dataCorruptedError(
                    in: singleValue, debugDescription: "Unknown ProfileColor preset")
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Kind.self, forKey: .kind) == .sRGB else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "Unsupported ProfileColor kind")
        }
        self = .custom(
            ProfileRGB(
                red: try container.decode(UInt8.self, forKey: .red),
                green: try container.decode(UInt8.self, forKey: .green),
                blue: try container.decode(UInt8.self, forKey: .blue)))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .blue:
            var container = encoder.singleValueContainer()
            try container.encode("blue")
        case .purple:
            var container = encoder.singleValueContainer()
            try container.encode("purple")
        case .pink:
            var container = encoder.singleValueContainer()
            try container.encode("pink")
        case .green:
            var container = encoder.singleValueContainer()
            try container.encode("green")
        case .yellow:
            var container = encoder.singleValueContainer()
            try container.encode("yellow")
        case .gray:
            var container = encoder.singleValueContainer()
            try container.encode("gray")
        case .custom(let rgb):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Kind.sRGB, forKey: .kind)
            try container.encode(rgb.red, forKey: .red)
            try container.encode(rgb.green, forKey: .green)
            try container.encode(rgb.blue, forKey: .blue)
        }
    }
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

struct ProfileWindowRoute: Codable, Hashable {
    let windowID: UUID
    let profileID: UUID
    let deskID: UUID?

    init(windowID: UUID = UUID(), profileID: UUID, deskID: UUID? = nil) {
        self.windowID = windowID
        self.profileID = profileID
        self.deskID = deskID
    }
}

enum RecentItem: Codable, Equatable, Hashable, Identifiable {
    case url(URL)
    case search(String)
    case terminal(workingDirectory: String)
    case zellij(sessionName: String?)
    case zmx(sessionName: String)

    private enum CodingKeys: String, CodingKey {
        case kind, url, query, workingDirectory, sessionName
    }
    private enum Kind: String, Codable { case url, search, terminal, zellij, zmx }

    var id: Self { self }

    var displayText: String {
        switch self {
        case .url(let url): return url.absoluteString
        case .search(let query): return query
        case .terminal(let workingDirectory):
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            return workingDirectory == homeDirectory ? ":terminal" : ":terminal \(workingDirectory)"
        case .zellij(let sessionName):
            return sessionName.map { ":zellij \($0)" } ?? ":zellij"
        case .zmx(let sessionName):
            return sessionName.isEmpty ? ":zmx" : ":zmx \(sessionName)"
        }
    }

    var defaultEssentialName: String {
        switch self {
        case .url(let url):
            return url.host ?? url.absoluteString
        case .search(let query):
            return query
        case .terminal(let workingDirectory):
            let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            if workingDirectory == home {
                return "Terminal"
            }
            return URL(fileURLWithPath: workingDirectory).lastPathComponent
        case .zellij(let sessionName):
            return sessionName ?? "Zellij"
        case .zmx(let sessionName):
            return sessionName.isEmpty ? "zmx" : sessionName
        }
    }

    func matches(essential: Essential) -> Bool {
        if displayText == essential.input { return true }
        if case .url(let itemURL) = self {
            if let essentialURL = URL(string: essential.input) {
                return itemURL.standardized == essentialURL.standardized
                    || itemURL.absoluteString.trimmingCharacters(in: ["/"])
                        == essentialURL.absoluteString.trimmingCharacters(in: ["/"])
            }
        }
        return false
    }

    var systemSymbol: SFSymbol {
        switch self {
        case .url: .link
        case .search: .magnifyingglass
        case .terminal: .appleTerminal
        case .zellij: .rectangleSplit3x1
        case .zmx: .appleTerminal
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
        case .terminal(let workingDirectory):
            return URL(fileURLWithPath: workingDirectory, isDirectory: true).standardizedFileURL.path
        case .zellij(let sessionName):
            return sessionName ?? ""
        case .zmx(let sessionName):
            return sessionName
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.url, .url), (.search, .search), (.terminal, .terminal), (.zellij, .zellij), (.zmx, .zmx):
            lhs.normalizedValue == rhs.normalizedValue
        default:
            false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .url: hasher.combine(0)
        case .search: hasher.combine(1)
        case .terminal: hasher.combine(2)
        case .zellij: hasher.combine(3)
        case .zmx: hasher.combine(4)
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
        case .terminal:
            self = .terminal(
                workingDirectory: try container.decode(String.self, forKey: .workingDirectory))
        case .zellij:
            self = .zellij(sessionName: try container.decodeIfPresent(String.self, forKey: .sessionName))
        case .zmx:
            self = .zmx(sessionName: try container.decode(String.self, forKey: .sessionName))
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
        case .terminal(let workingDirectory):
            try container.encode(Kind.terminal, forKey: .kind)
            try container.encode(workingDirectory, forKey: .workingDirectory)
        case .zellij(let sessionName):
            try container.encode(Kind.zellij, forKey: .kind)
            try container.encodeIfPresent(sessionName, forKey: .sessionName)
        case .zmx(let sessionName):
            try container.encode(Kind.zmx, forKey: .kind)
            try container.encode(sessionName, forKey: .sessionName)
        }
    }
}

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
    static let currentSchemaVersion = 2
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
        guard (1...Self.currentSchemaVersion).contains(decodedSchemaVersion) else {
            throw ProfilePersistenceError.unsupportedPersistedProfileSchema(decodedSchemaVersion)
        }
        schemaVersion = Self.currentSchemaVersion
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
