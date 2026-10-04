import Foundation

enum DeskPresetSaveResult: Equatable {
    case created
    case replacementPending
    case invalidLabel
    case emptyDesk
    case reservedLabel
}

enum DeskPresetRenameResult: Equatable {
    case renamed
    case unchanged
    case invalidLabel
    case reservedLabel
    case duplicateLabel
    case unavailable
}

extension DenStore {
    func saveFocusedDeskAsPreset(label: String) -> DeskPresetSaveResult {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return .invalidLabel }
        guard let desk = focusedDesk, desk.boards.contains(where: { !$0.isTutorial }) else { return .emptyDesk }
        guard !BuiltInDeskPreset.allCases.contains(where: { samePresetLabel($0.label, label) }) else {
            return .reservedLabel
        }

        if let existing = deskPresets.first(where: { samePresetLabel($0.label, label) }) {
            pendingConfirmation = .replaceDeskPreset(
                PersonalDeskPreset(id: existing.id, label: existing.label, desk: desk))
            return .replacementPending
        }

        deskPresets.insert(PersonalDeskPreset(label: label, desk: desk), at: 0)
        isDenMode = false
        if saveDeskPresets() {
            showToast("Saved Desk Preset.", style: .success)
        } else {
            showToast("Could not save Desk Preset.", style: .error)
        }
        return .created
    }

    func confirmDeskPresetReplacement() {
        guard
            let replacement = deskPresetPendingReplacement,
            let index = deskPresets.firstIndex(where: { $0.id == replacement.id })
        else { return }
        deskPresets[index] = replacement
        pendingConfirmation = nil
        isDenMode = false
        if saveDeskPresets() {
            showToast("Saved Desk Preset.", style: .success)
        } else {
            showToast("Could not save Desk Preset.", style: .error)
        }
    }

    func cancelDeskPresetReplacement() {
        if deskPresetPendingReplacement != nil {
            pendingConfirmation = nil
        }
    }

    func requestDeskPresetDeletion(_ id: UUID) {
        guard let preset = deskPresets.first(where: { $0.id == id }) else { return }
        pendingConfirmation = .deleteDeskPreset(preset)
    }

    func renameDeskPreset(_ id: UUID, to rawLabel: String) -> DeskPresetRenameResult {
        let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return .invalidLabel }
        guard !BuiltInDeskPreset.allCases.contains(where: { samePresetLabel($0.label, label) }) else {
            return .reservedLabel
        }
        guard let index = deskPresets.firstIndex(where: { $0.id == id }) else { return .unavailable }
        guard !deskPresets.contains(where: { $0.id != id && samePresetLabel($0.label, label) }) else {
            return .duplicateLabel
        }
        guard deskPresets[index].label != label else { return .unchanged }

        deskPresets[index].label = label
        if !saveDeskPresets() {
            showToast("Could not rename Desk Preset.", style: .error)
        }
        return .renamed
    }

    func confirmDeskPresetDeletion() {
        guard let id = deskPresetPendingDeletion?.id else { return }
        pendingConfirmation = nil
        deskPresets.removeAll { $0.id == id }
        if !saveDeskPresets() {
            showToast("Could not delete Desk Preset.", style: .error)
        }
    }

    func cancelDeskPresetDeletion() {
        if deskPresetPendingDeletion != nil {
            pendingConfirmation = nil
        }
    }

    private func samePresetLabel(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
    }
}
