import DenDomain
import Foundation

@MainActor
public struct DeskPresetOperations {
    public enum SaveResult {
        case created(persisted: Bool)
        case replacementRequired(PersonalDeskPreset)
        case invalidLabel
        case emptyDesk
        case reservedLabel
    }

    public enum RenameResult {
        case renamed(persisted: Bool)
        case unchanged
        case invalidLabel
        case reservedLabel
        case duplicateLabel
        case unavailable
    }

    public enum ReplacementResult {
        case replaced(persisted: Bool)
        case unavailable
    }

    private let state: DenStateStore
    private let writer: DenStateWriter
    private let persist: ([PersonalDeskPreset]) -> Bool

    public init(state: DenStateStore, writer: DenStateWriter, persist: @escaping ([PersonalDeskPreset]) -> Bool) {
        self.state = state
        self.writer = writer
        self.persist = persist
    }

    public func save(label: String, desk: DeskState?) -> SaveResult {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return .invalidLabel }
        guard let desk, desk.boards.contains(where: { !$0.isTutorial }) else { return .emptyDesk }
        guard !isReserved(label) else { return .reservedLabel }
        if let existing = state.snapshot.deskPresets.first(where: { sameLabel($0.label, label) }) {
            return .replacementRequired(PersonalDeskPreset(id: existing.id, label: existing.label, desk: desk))
        }
        writer.update { $0.deskPresets.insert(PersonalDeskPreset(label: label, desk: desk), at: 0) }
        return .created(persisted: persist(state.snapshot.deskPresets))
    }

    public func replace(_ replacement: PersonalDeskPreset) -> ReplacementResult {
        guard let index = state.snapshot.deskPresets.firstIndex(where: { $0.id == replacement.id }) else {
            return .unavailable
        }
        writer.update { $0.deskPresets[index] = replacement }
        return .replaced(persisted: persist(state.snapshot.deskPresets))
    }

    public func rename(_ id: UUID, to rawLabel: String) -> RenameResult {
        let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return .invalidLabel }
        guard !isReserved(label) else { return .reservedLabel }
        let presets = state.snapshot.deskPresets
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return .unavailable }
        guard !presets.contains(where: { $0.id != id && sameLabel($0.label, label) }) else { return .duplicateLabel }
        guard presets[index].label != label else { return .unchanged }
        writer.update { $0.deskPresets[index].label = label }
        return .renamed(persisted: persist(state.snapshot.deskPresets))
    }

    public func delete(_ id: UUID) -> Bool {
        writer.update { $0.deskPresets.removeAll { $0.id == id } }
        return persist(state.snapshot.deskPresets)
    }

    private func isReserved(_ label: String) -> Bool {
        BuiltInDeskPreset.allCases.contains { sameLabel($0.label, label) }
    }

    private func sameLabel(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
    }
}
