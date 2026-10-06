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
            onWindowEffect?(
                .requestConfirmation(
                    .replaceDeskPreset(
                        PersonalDeskPreset(id: existing.id, label: existing.label, desk: desk))))
            return .replacementPending
        }

        deskPresets.insert(PersonalDeskPreset(label: label, desk: desk), at: 0)
        onWindowEffect?(.exitDenMode)
        if saveDeskPresets() {
            reportFeedback("Saved Desk Preset.", severity: .success)
        } else {
            reportFeedback("Could not save Desk Preset.", severity: .error)
        }
        return .created
    }

    @discardableResult
    func replaceDeskPreset(_ replacement: PersonalDeskPreset) -> Bool {
        guard let index = deskPresets.firstIndex(where: { $0.id == replacement.id }) else { return false }
        deskPresets[index] = replacement
        onWindowEffect?(.exitDenMode)
        if saveDeskPresets() {
            reportFeedback("Saved Desk Preset.", severity: .success)
        } else {
            reportFeedback("Could not save Desk Preset.", severity: .error)
        }
        return true
    }

    func requestDeskPresetDeletion(_ id: UUID) {
        guard let preset = deskPresets.first(where: { $0.id == id }) else { return }
        onWindowEffect?(.requestConfirmation(.deleteDeskPreset(preset)))
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
            reportFeedback("Could not rename Desk Preset.", severity: .error)
        }
        return .renamed
    }

    func deleteDeskPreset(_ id: UUID) {
        deskPresets.removeAll { $0.id == id }
        if !saveDeskPresets() {
            reportFeedback("Could not delete Desk Preset.", severity: .error)
        }
    }

    private func samePresetLabel(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
    }
}
