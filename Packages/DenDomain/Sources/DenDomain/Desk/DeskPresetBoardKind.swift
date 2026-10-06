import Foundation

public enum DeskPresetBoardKind: Codable, Equatable {
    case web(URL?)
    case inspection
    case terminal(DeskPresetTerminalSession)

    private enum CodingKeys: String, CodingKey { case kind, session, initialSheetURL }
    private enum Kind: String, Codable { case web, inspection, terminal }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .web:
            self = .web(try container.decodeIfPresent(URL.self, forKey: .initialSheetURL))
        case .inspection:
            self = .inspection
        case .terminal:
            self = .terminal(try container.decode(DeskPresetTerminalSession.self, forKey: .session))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .web(let url):
            try container.encode(Kind.web, forKey: .kind)
            try container.encodeIfPresent(url, forKey: .initialSheetURL)
        case .inspection:
            try container.encode(Kind.inspection, forKey: .kind)
        case .terminal(let session):
            try container.encode(Kind.terminal, forKey: .kind)
            try container.encode(session, forKey: .session)
        }
    }
}
