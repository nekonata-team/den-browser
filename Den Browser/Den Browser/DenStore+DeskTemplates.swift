import Foundation

enum DeskTemplateSaveResult: Equatable {
    case created
    case replacementPending
    case invalidLabel
    case emptyDesk
    case reservedLabel
}

extension DenStore {
    func saveFocusedDeskAsTemplate(label: String) -> DeskTemplateSaveResult {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return .invalidLabel }
        guard let desk = focusedDesk, !desk.boards.isEmpty else { return .emptyDesk }
        guard !BuiltInDeskTemplate.allCases.contains(where: { sameTemplateLabel($0.label, label) }) else {
            return .reservedLabel
        }

        if let existing = deskTemplates.first(where: { sameTemplateLabel($0.label, label) }) {
            deskTemplatePendingReplacement = PersonalDeskTemplate(id: existing.id, label: existing.label, desk: desk)
            return .replacementPending
        }

        deskTemplates.insert(PersonalDeskTemplate(label: label, desk: desk), at: 0)
        saveDeskTemplates()
        return .created
    }

    func confirmDeskTemplateReplacement() {
        guard
            let replacement = deskTemplatePendingReplacement,
            let index = deskTemplates.firstIndex(where: { $0.id == replacement.id })
        else { return }
        deskTemplates[index] = replacement
        deskTemplatePendingReplacement = nil
        saveDeskTemplates()
    }

    func cancelDeskTemplateReplacement() {
        deskTemplatePendingReplacement = nil
    }

    func requestDeskTemplateDeletion(_ id: UUID) {
        deskTemplatePendingDeletion = deskTemplates.first { $0.id == id }
    }

    func confirmDeskTemplateDeletion() {
        guard let id = deskTemplatePendingDeletion?.id else { return }
        deskTemplatePendingDeletion = nil
        deskTemplates.removeAll { $0.id == id }
        saveDeskTemplates()
    }

    func cancelDeskTemplateDeletion() {
        deskTemplatePendingDeletion = nil
    }

    private func sameTemplateLabel(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
    }
}
