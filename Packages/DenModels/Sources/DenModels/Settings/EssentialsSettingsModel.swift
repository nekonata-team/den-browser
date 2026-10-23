import DenDomain
import Foundation
import Observation

@MainActor
@Observable
public final class EssentialsSettingsModel {
    @ObservationIgnored private let read: () -> [Essential]
    @ObservationIgnored private let persist: ([Essential]) -> Bool

    public init(read: @escaping () -> [Essential], persist: @escaping ([Essential]) -> Bool) {
        self.read = read
        self.persist = persist
    }

    public var essentials: [Essential] { read() }

    public func save(id: UUID?, name: String, key: String, input: String) -> String? {
        let essential = Essential(id: id ?? UUID(), name: name, key: key, input: input)
        guard essential.isValid else { return "Enter a name, one key, and an input." }
        var updated = essentials
        if let id {
            guard let index = updated.firstIndex(where: { $0.id == id }) else {
                return "The Essential no longer exists."
            }
            updated[index] = essential
        } else {
            updated.append(essential)
        }
        guard !updated.contains(where: { $0.id != essential.id && $0.key == essential.key }) else {
            return "That key is already assigned to another Essential."
        }
        return persist(updated) ? nil : "Could not save the Essential."
    }

    public func delete(_ essential: Essential) -> String? {
        let updated = essentials.filter { $0.id != essential.id }
        return persist(updated) ? nil : "Could not delete the Essential."
    }
}
