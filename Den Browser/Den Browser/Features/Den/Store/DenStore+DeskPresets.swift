import Foundation

enum DeskPresetSaveResult: Equatable {
    case created
    case replacementPending
    case invalidLabel
    case emptyDesk
    case reservedLabel
}

extension DenStore {
    func saveFocusedDeskAsPreset(label: String) -> DeskPresetSaveResult {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return .invalidLabel }
        guard let desk = focusedDesk, !desk.boards.isEmpty else { return .emptyDesk }
        guard !BuiltInDeskPreset.allCases.contains(where: { samePresetLabel($0.label, label) }) else {
            return .reservedLabel
        }

        if let existing = deskPresets.first(where: { samePresetLabel($0.label, label) }) {
            deskPresetPendingReplacement = PersonalDeskPreset(id: existing.id, label: existing.label, desk: desk)
            return .replacementPending
        }

        deskPresets.insert(PersonalDeskPreset(label: label, desk: desk), at: 0)
        saveDeskPresets()
        return .created
    }

    func confirmDeskPresetReplacement() {
        guard
            let replacement = deskPresetPendingReplacement,
            let index = deskPresets.firstIndex(where: { $0.id == replacement.id })
        else { return }
        deskPresets[index] = replacement
        deskPresetPendingReplacement = nil
        saveDeskPresets()
    }

    func cancelDeskPresetReplacement() {
        deskPresetPendingReplacement = nil
    }

    func requestDeskPresetDeletion(_ id: UUID) {
        deskPresetPendingDeletion = deskPresets.first { $0.id == id }
    }

    func confirmDeskPresetDeletion() {
        guard let id = deskPresetPendingDeletion?.id else { return }
        deskPresetPendingDeletion = nil
        deskPresets.removeAll { $0.id == id }
        saveDeskPresets()
    }

    func cancelDeskPresetDeletion() {
        deskPresetPendingDeletion = nil
    }

    private func samePresetLabel(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
    }
}
