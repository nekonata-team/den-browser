import Foundation

public enum BoardRole: Codable, Equatable {
    case primary
    case sideBoard(targetBoardID: UUID)

    private enum CodingKeys: String, CodingKey {
        case kind, targetBoardID
    }

    private enum Kind: String, Codable {
        case primary, sideBoard
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .primary:
            self = .primary
        case .sideBoard:
            self = .sideBoard(targetBoardID: try container.decode(UUID.self, forKey: .targetBoardID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .primary:
            try container.encode(Kind.primary, forKey: .kind)
        case .sideBoard(let targetBoardID):
            try container.encode(Kind.sideBoard, forKey: .kind)
            try container.encode(targetBoardID, forKey: .targetBoardID)
        }
    }
}
