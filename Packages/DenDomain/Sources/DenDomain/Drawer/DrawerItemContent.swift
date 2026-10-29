import Foundation

public enum DrawerItemContent: Codable, Equatable {
    case web(URL)
    case terminal(TerminalBoardState)

    private enum CodingKeys: String, CodingKey { case kind, url, session }
    private enum Kind: String, Codable { case web, terminal }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .web: self = .web(try container.decode(URL.self, forKey: .url))
        case .terminal: self = .terminal(try container.decode(TerminalBoardState.self, forKey: .session))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .web(let url):
            try container.encode(Kind.web, forKey: .kind)
            try container.encode(url, forKey: .url)
        case .terminal(let session):
            try container.encode(Kind.terminal, forKey: .kind)
            try container.encode(session, forKey: .session)
        }
    }
}
