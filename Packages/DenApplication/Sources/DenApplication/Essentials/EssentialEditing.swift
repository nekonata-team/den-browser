public import DenDomain
import Foundation

public struct EssentialEditing {
    public enum Result {
        case invalid
        case confirmation(existing: Essential, replacement: Essential)
        case saved(Essential)
        case missing
        case persistenceFailed
    }

    private let read: () -> [Essential]
    private let persist: ([Essential]) -> Bool

    public init(read: @escaping () -> [Essential], persist: @escaping ([Essential]) -> Bool) {
        self.read = read
        self.persist = persist
    }

    public func save(name: String, key: String, input: String) -> Result {
        let essential = Essential(name: name, key: key, input: input)
        guard !essential.name.isEmpty, essential.key.count == 1, !essential.input.isEmpty else { return .invalid }
        let current = read()
        if let existing = current.first(where: { $0.key == essential.key }) {
            let replacement = Essential(
                id: existing.id, name: essential.name, key: essential.key, input: essential.input)
            return .confirmation(existing: existing, replacement: replacement)
        }
        return persist(current + [essential]) ? .saved(essential) : .persistenceFailed
    }

    public func replace(_ replacement: Essential) -> Result {
        var current = read()
        guard let index = current.firstIndex(where: { $0.id == replacement.id && $0.key == replacement.key }) else {
            return .missing
        }
        current[index] = replacement
        return persist(current) ? .saved(replacement) : .persistenceFailed
    }
}
