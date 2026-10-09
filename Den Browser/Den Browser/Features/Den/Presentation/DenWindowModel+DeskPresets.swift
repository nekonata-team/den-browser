import DenApplication
import DenDomain
import DenPresentation
import Foundation

extension DenWindowModel {
    var deskPresetPendingReplacement: PersonalDeskPreset? {
        guard case .replaceDeskPreset(let replacement)? = pendingConfirmation else { return nil }
        return replacement
    }

    var deskPresetPendingDeletion: PersonalDeskPreset? {
        guard case .deleteDeskPreset(let preset)? = pendingConfirmation else { return nil }
        return preset
    }

    func confirmDeskPresetReplacement() {
        guard let request = pendingConfirmation, case .replaceDeskPreset = request,
            onConfirmOperation(request)
        else { return }
        pendingConfirmation = nil
    }

    func cancelDeskPresetReplacement() {
        if deskPresetPendingReplacement != nil { pendingConfirmation = nil }
    }

    func confirmDeskPresetDeletion() {
        guard let request = pendingConfirmation, case .deleteDeskPreset = request else { return }
        pendingConfirmation = nil
        _ = onConfirmOperation(request)
    }

    func cancelDeskPresetDeletion() {
        if deskPresetPendingDeletion != nil { pendingConfirmation = nil }
    }
}
