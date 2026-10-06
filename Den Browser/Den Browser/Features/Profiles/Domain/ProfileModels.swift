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

enum BrowsingDataCategory: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case cookies
    case cache
    case localData

    var id: Self { self }

}
