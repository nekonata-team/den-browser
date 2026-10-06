import Foundation

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
