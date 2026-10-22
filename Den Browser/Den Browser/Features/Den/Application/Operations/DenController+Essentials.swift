import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

extension DenController {
    func launchEssential(id: UUID, preferredWidth: Double? = nil, inDrawer: Bool = false) {
        guard let essential = essentials.first(where: { $0.id == id }) else { return }
        if case .rejected(let message) = storage.inputOpening.launch(
            essential, context: inputOpeningContext(preferredWidth: preferredWidth), inDrawer: inDrawer,
            notify: inputOpeningNotifications())
        {
            if let message { reportFeedback(message, severity: .warning) }
        }
    }

    @discardableResult
    func saveEssential(name: String, key: String, input: String) -> Bool {
        switch essentialEditing.save(name: name, key: key, input: input) {
        case .confirmation(let existing, let replacement):
            onWindowEffect?(.requestConfirmation(.replaceEssential(existing: existing, replacement: replacement)))
            return true
        case .saved(let essential):
            reportFeedback("Saved Essential '\(essential.name)'.", severity: .success)
            return true
        default: return false
        }
    }

    @discardableResult
    func replaceEssential(_ replacement: Essential) -> Bool {
        switch essentialEditing.replace(replacement) {
        case .saved(let essential):
            reportFeedback("Saved Essential '\(essential.name)'.", severity: .success)
            return true
        case .missing:
            reportFeedback("The Essential no longer exists or its key has changed.", severity: .warning)
        default:
            reportFeedback("Could not save Essential.", severity: .error)
        }
        return false
    }
}
