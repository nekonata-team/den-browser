import DenDomain
import Foundation

extension DenStore {
    @discardableResult
    func saveEssential(name: String, key: String, input: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = key == " " ? key : key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, trimmedKey.count == 1, !trimmedInput.isEmpty else {
            return false
        }

        if essentials.contains(where: { $0.key == trimmedKey }) {
            return false
        }

        var updated = preferences.essentials
        updated.append(Essential(name: trimmedName, key: trimmedKey, input: trimmedInput))
        guard preferences.setEssentials(updated) else { return false }

        reportFeedback("Saved Essential '\(trimmedName)'.", severity: .success)
        return true
    }
}
