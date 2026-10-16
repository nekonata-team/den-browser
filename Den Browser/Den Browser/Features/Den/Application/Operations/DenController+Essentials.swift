import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

extension DenController {
    func launchEssential(id: UUID, preferredWidth: Double? = nil, inDrawer: Bool = false) {
        guard let essential = essentials.first(where: { $0.id == id }) else { return }
        if inDrawer {
            if let message = openInDrawer(input: essential.input) {
                reportFeedback(message, severity: .warning)
            }
            return
        }
        onWindowEffect?(.openBoardResult(nil))
        if case .rejected(let message) = requestOpenBoard(input: essential.input, preferredWidth: preferredWidth) {
            reportFeedback(message ?? "Could not open Essential '\(essential.name)'.", severity: .warning)
        }
    }

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
