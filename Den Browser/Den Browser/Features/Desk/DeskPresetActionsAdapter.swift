import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

@MainActor
final class DeskPresetActionsAdapter {
    private let context: WindowNativeContext
    private let facings: DeskFacings
    private var storage: DenProfileResources { context.storage }
    private var focusedDesk: DeskState? { context.focusedDesk }
    private var deskPresets: [PersonalDeskPreset] { context.storage.deskPresets }
    private var onWindowEffect: ((DenWindowEffect) -> Void)? { context.connection.onWindowEffect }

    init(context: WindowNativeContext, facings: DeskFacings) {
        self.context = context
        self.facings = facings
    }

    func saveFocusedDeskAsPreset(label: String) -> DeskPresetSaveResult {
        switch storage.deskPresetOperations.save(label: label, desk: focusedDesk) {
        case .invalidLabel: return .invalidLabel
        case .emptyDesk: return .emptyDesk
        case .reservedLabel: return .reservedLabel
        case .replacementRequired(let replacement):
            onWindowEffect?(.requestConfirmation(.replaceDeskPreset(replacement)))
            return .replacementPending
        case .created(let persisted):
            if persisted, let preset = storage.deskPresets.first(where: { $0.label == label }),
                let boards = focusedDesk?.boards
            {
                facings.savePresetFacings(for: preset.id, boards: boards)
            }
            onWindowEffect?(.exitDenMode)
            reportPresetSave(persisted)
            return .created
        }
    }

    @discardableResult
    func replaceDeskPreset(_ replacement: PersonalDeskPreset) -> Bool {
        switch storage.deskPresetOperations.replace(replacement) {
        case .unavailable: return false
        case .replaced(let persisted):
            if persisted, let boards = focusedDesk?.boards {
                facings.savePresetFacings(for: replacement.id, boards: boards)
            }
            onWindowEffect?(.exitDenMode)
            reportPresetSave(persisted)
            return true
        }
    }

    func requestDeskPresetDeletion(_ id: UUID) {
        guard let preset = deskPresets.first(where: { $0.id == id }) else { return }
        onWindowEffect?(.requestConfirmation(.deleteDeskPreset(preset)))
    }

    func renameDeskPreset(_ id: UUID, to label: String) -> DeskPresetRenameResult {
        switch storage.deskPresetOperations.rename(id, to: label) {
        case .invalidLabel: return .invalidLabel
        case .reservedLabel: return .reservedLabel
        case .duplicateLabel: return .duplicateLabel
        case .unavailable: return .unavailable
        case .unchanged: return .unchanged
        case .renamed(let persisted):
            if !persisted { context.feedback.publish("Could not rename Desk Preset.", severity: .error) }
            return .renamed
        }
    }

    func deleteDeskPreset(_ id: UUID) {
        if !storage.deskPresetOperations.delete(id) {
            context.feedback.publish("Could not delete Desk Preset.", severity: .error)
        } else {
            facings.removePresetFacings(for: id)
        }
    }

    private func reportPresetSave(_ persisted: Bool) {
        context.feedback.publish(
            persisted ? "Saved Desk Preset." : "Could not save Desk Preset.",
            severity: persisted ? .success : .error)
    }
}
