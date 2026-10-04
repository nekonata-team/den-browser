import Foundation

struct ProfileRGB: Codable, Equatable, Hashable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

}

enum ProfileColor: Codable, Equatable, Hashable, Identifiable {
    case blue, purple, pink, green, yellow, gray
    case custom(ProfileRGB)

    static let presets: [ProfileColor] = [.blue, .purple, .pink, .green, .yellow, .gray]

    var id: Self { self }

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

enum BrowsingDataCategory: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case cookies
    case cache
    case localData

    var id: Self { self }

}
