import AppKit
import DenDomain
import Foundation

enum DeskReplacementResult: Equatable {
    case applied
    case confirmationPending
    case unavailable
}

extension DenStore {
    func createDesk(label: String, preset: BuiltInDeskPreset) {
        createDesk(label: label, boards: preset.boards, focusedBoardIndex: preset.focusedBoardIndex)
    }

    func createDesk(label: String, personalPresetID: UUID) {
        guard let preset = deskPresets.first(where: { $0.id == personalPresetID }) else { return }
        createDesk(label: label, boards: preset.boards, focusedBoardIndex: preset.focusedBoardIndex)
    }

    private func createDesk(label: String, boards: [DeskPresetBoard], focusedBoardIndex: Int?) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, canCreateDesk, let focusedDeskIndex else { return }

        guard let boards = DeskPresetBoard.makeBoards(from: boards) else { return }
        let focusedBoardID = focusedBoardIndex.flatMap { boards.indices.contains($0) ? boards[$0].id : nil }
        let desk = DeskState(label: trimmedLabel, boards: boards, focusedBoardID: focusedBoardID)
        state.desks.insert(desk, at: focusedDeskIndex + 1)
        setFocusedDesk(desk.id)
        onWindowEffect?(.dismissTemporaryPresentation)
        onWindowEffect?(.exitDenMode)
        save()
        dispatchDenOperationEvent(.deskCreated)
    }

    func replaceFocusedDesk(label: String, preset: BuiltInDeskPreset) -> DeskReplacementResult {
        requestFocusedDeskReplacement(
            label: label,
            presetLabel: preset.label,
            boards: preset.boards,
            focusedBoardIndex: preset.focusedBoardIndex)
    }

    func replaceFocusedDesk(label: String, personalPresetID: UUID) -> DeskReplacementResult? {
        guard let preset = deskPresets.first(where: { $0.id == personalPresetID }) else { return nil }
        return requestFocusedDeskReplacement(
            label: label,
            presetLabel: preset.label,
            boards: preset.boards,
            focusedBoardIndex: preset.focusedBoardIndex)
    }

    func confirmDeskReplacement(_ replacement: PendingDeskReplacement) {
        applyDeskReplacement(replacement)
    }

    private func requestFocusedDeskReplacement(
        label: String,
        presetLabel: String,
        boards: [DeskPresetBoard],
        focusedBoardIndex: Int?
    ) -> DeskReplacementResult {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !label.isEmpty,
            !boards.isEmpty,
            let desk = focusedDesk
        else { return .unavailable }

        let replacement = PendingDeskReplacement(
            deskID: desk.id,
            originalLabel: desk.label,
            originalBoardCount: desk.boards.count,
            presetLabel: presetLabel,
            label: label,
            boards: boards,
            focusedBoardIndex: focusedBoardIndex)
        guard !desk.boards.isEmpty else {
            applyDeskReplacement(replacement)
            return .applied
        }
        onWindowEffect?(.requestConfirmation(.replaceDesk(replacement)))
        return .confirmationPending
    }

    private func applyDeskReplacement(_ replacement: PendingDeskReplacement) {
        guard
            let deskIndex = state.desks.firstIndex(where: { $0.id == replacement.deskID }),
            let boards = DeskPresetBoard.makeBoards(from: replacement.boards)
        else { return }

        let removedBoardIDs = Set(state.desks[deskIndex].boards.map(\.id))
        for board in state.desks[deskIndex].boards {
            disposeRuntime(for: board.id)
        }
        state.desks[deskIndex].label = replacement.label
        state.desks[deskIndex].boards = boards
        state.desks[deskIndex].focusedBoardID =
            replacement.focusedBoardIndex.flatMap { boards.indices.contains($0) ? boards[$0].id : nil }
            ?? boards.first?.id
        state.desks[deskIndex].anchorBoardID = nil
        anchorJumpOriginBoardIDByDesk.removeValue(forKey: replacement.deskID)
        invalidateReferences(toRemovedBoardIDs: removedBoardIDs)
        onWindowEffect?(.dismissTemporaryPresentation)
        onWindowEffect?(.exitDenMode)
        save()
        reportFeedback("Replaced Desk with Preset.", severity: .success)
    }

    func deleteFocusedDesk() {
        guard canDeleteFocusedDesk else {
            reportFeedback("The last desk cannot be deleted.", severity: .warning)
            return
        }
        guard let focusedDesk else { return }

        if focusedDesk.boards.isEmpty {
            deleteDesk(focusedDesk.id)
        } else {
            onWindowEffect?(.requestConfirmation(.deleteDesk(focusedDesk)))
        }
    }

    func confirmDeskDeletion(_ deskID: UUID) { deleteDesk(deskID) }

    private func deleteDesk(_ deskID: UUID) {
        guard
            state.desks.count > 1,
            let deskIndex = state.desks.firstIndex(where: { $0.id == deskID })
        else { return }
        let replacementCandidates = state.desks.prefix(deskIndex).reversed() + state.desks.dropFirst(deskIndex + 1)
        guard
            let replacementDeskID = replacementCandidates.first(where: {
                $0.id != deskID && (canPresentDesk?($0.id) ?? true)
            })?.id
        else { return }

        let desk = state.desks[deskIndex]
        for board in desk.boards {
            disposeRuntime(for: board.id)
        }

        state.desks.remove(at: deskIndex)
        if presentedDeskID == deskID {
            setFocusedDesk(replacementDeskID)
        }
        invalidateReferences(toRemovedBoardIDs: Set(desk.boards.map(\.id)))
        invalidateReferences(toRemovedDeskID: deskID)
        onWindowEffect?(.exitDenMode)
        save()
    }

    func renameFocusedDesk(to newLabel: String) {
        guard let deskIndex = focusedDeskIndex else { return }
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            state.desks[deskIndex].label = trimmed
        }
        onWindowEffect?(.dismissTemporaryPresentation)
        onWindowEffect?(.exitDenMode)
        save()
    }

    func deskScrollOffset(for deskID: UUID) -> CGFloat? {
        guard let desk = state.desks.first(where: { $0.id == deskID }) else { return nil }
        return desk.scrollOffsetX.map { CGFloat($0) }
    }

    func saveDeskScrollOffset(_ offset: CGFloat?, for deskID: UUID) {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }) else { return }
        let current = state.desks[deskIndex].scrollOffsetX
        let newDouble = offset.map { Double($0) }
        guard current != newDouble else { return }
        state.desks[deskIndex].scrollOffsetX = newDouble
        save()
    }

    func copyDeskID(_ deskID: UUID, pasteboard: NSPasteboard? = nil) {
        let pasteboard = pasteboard ?? self.pasteboard
        guard state.desks.contains(where: { $0.id == deskID }) else { return }
        pasteboard.clearContents()
        pasteboard.setString(deskID.uuidString.lowercased(), forType: .string)
        reportFeedback("Copied Desk ID.", severity: .success)
    }
}
