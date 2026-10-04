import Foundation

struct Essential: Codable, Equatable, Hashable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case id, name, key, input
    }

    let id: UUID
    var name: String
    var key: String
    var input: String

    init(id: UUID = UUID(), name: String, key: String, input: String) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = key == " " ? key : key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.input = input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            key: try container.decode(String.self, forKey: .key),
            input: try container.decode(String.self, forKey: .input))
    }

    var displayKey: String {
        key == " " ? "Space" : key
    }

    var isValid: Bool {
        !name.isEmpty
            && key.count == 1
            && key.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
            && !input.isEmpty
    }
}
