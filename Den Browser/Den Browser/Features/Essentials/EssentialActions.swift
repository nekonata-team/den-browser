import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

@MainActor
final class EssentialActions {
    private let context: WindowNativeContext
    private let boardOpening: BoardOpeningActions
    private let input: InputOpeningActions
    private var storage: DenProfileResources { context.storage }
    private var essentials: [Essential] { context.configuration.preferences.essentials }
    private var onWindowEffect: ((DenWindowEffect) -> Void)? { context.connection.onWindowEffect }
    private var essentialEditing: EssentialEditing { context.essentialEditing }

    init(context: WindowNativeContext, boardOpening: BoardOpeningActions, input: InputOpeningActions) {
        self.context = context
        self.boardOpening = boardOpening
        self.input = input
    }

    func launchEssential(id: UUID, preferredWidth: Double? = nil, inDrawer: Bool = false) {
        guard let essential = essentials.first(where: { $0.id == id }) else { return }
        if case .rejected(let message) = storage.inputOpening.launch(
            essential, context: boardOpening.inputOpeningContext(preferredWidth: preferredWidth), inDrawer: inDrawer,
            notify: input.inputOpeningNotifications())
        {
            if let message { context.feedback.publish(message, severity: .warning) }
        }
    }

    @discardableResult
    func saveEssential(name: String, key: String, input: String) -> Bool {
        switch essentialEditing.save(name: name, key: key, input: input) {
        case .confirmation(let existing, let replacement):
            onWindowEffect?(.requestConfirmation(.replaceEssential(existing: existing, replacement: replacement)))
            return true
        case .saved(let essential):
            context.feedback.publish("Saved Essential '\(essential.name)'.", severity: .success)
            return true
        default: return false
        }
    }

    @discardableResult
    func replaceEssential(_ replacement: Essential) -> Bool {
        switch essentialEditing.replace(replacement) {
        case .saved(let essential):
            context.feedback.publish("Saved Essential '\(essential.name)'.", severity: .success)
            return true
        case .missing:
            context.feedback.publish("The Essential no longer exists or its key has changed.", severity: .warning)
        default:
            context.feedback.publish("Could not save Essential.", severity: .error)
        }
        return false
    }
}
