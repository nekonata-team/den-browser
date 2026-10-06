import DenDomain
import Foundation

extension DenViewModel {
    var deskPresetPendingReplacement: PersonalDeskPreset? {
        guard case .replaceDeskPreset(let replacement)? = pendingConfirmation else { return nil }
        return replacement
    }

    var deskPresetPendingDeletion: PersonalDeskPreset? {
        guard case .deleteDeskPreset(let preset)? = pendingConfirmation else { return nil }
        return preset
    }

    func confirmDeskPresetReplacement() {
        guard let replacement = deskPresetPendingReplacement,
            store.replaceDeskPreset(replacement)
        else { return }
        pendingConfirmation = nil
    }

    func cancelDeskPresetReplacement() {
        if deskPresetPendingReplacement != nil { pendingConfirmation = nil }
    }

    func confirmDeskPresetDeletion() {
        guard let preset = deskPresetPendingDeletion else { return }
        pendingConfirmation = nil
        store.deleteDeskPreset(preset.id)
    }

    func cancelDeskPresetDeletion() {
        if deskPresetPendingDeletion != nil { pendingConfirmation = nil }
    }
}
