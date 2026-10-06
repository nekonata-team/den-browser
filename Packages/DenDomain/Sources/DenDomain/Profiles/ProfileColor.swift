import Foundation

public enum ProfileColor: Codable, Equatable, Hashable, Identifiable {
    case blue, purple, pink, green, yellow, gray
    case custom(ProfileRGB)

    public static let presets: [ProfileColor] = [.blue, .purple, .pink, .green, .yellow, .gray]

    public var id: Self { self }

    private enum CodingKeys: String, CodingKey { case kind, red, green, blue }
    private enum Kind: String, Codable { case sRGB }

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
