import Foundation

public enum WebProfileStore: Equatable, Sendable {
    case `default`
    case identified(UUID)
}

extension WebProfileStore: Codable {
    private enum CodingKeys: String, CodingKey { case kind, identifier }
    private enum Kind: String, Codable { case `default`, identified }

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
