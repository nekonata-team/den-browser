import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

enum DeskReplacementResult: Equatable {
    case applied
    case confirmationPending
    case unavailable
}

extension DenController {
    func createDesk(label: String, preset: BuiltInDeskPreset) {
        createDesk(label: label, boards: preset.boards, focusedBoardIndex: preset.focusedBoardIndex)
    }

    func createDesk(label: String, personalPresetID: UUID) {
        guard let preset = deskPresets.first(where: { $0.id == personalPresetID }) else { return }
        createDesk(label: label, boards: preset.boards, focusedBoardIndex: preset.focusedBoardIndex)
    }

    func duplicateDesk(_ deskID: DeskID) {
        guard let source = state.desks.first(where: { $0.id == deskID }) else { return }
        let preset = PersonalDeskPreset(label: source.label, desk: source)
        guard
            let copy = createDesk(
                label: source.label, boards: preset.boards, focusedBoardIndex: preset.focusedBoardIndex,
                after: source.id)
        else { return }
        for (original, duplicate) in zip(source.boards.filter { !$0.isTutorial }, copy.boards) {
            if let image = facingCache.image(for: original.id) {
                facingCache.setFacing(image, for: duplicate.id, at: nil)
            }
        }
    }

    @discardableResult
    private func createDesk(
        label: String, boards: [DeskPresetBoard], focusedBoardIndex: BoardIndex?, after deskID: DeskID? = nil
    ) -> DeskState? {
        guard
            let creation = DeskCreation.create(
                label: label, presetBoards: boards, focusedBoardIndex: focusedBoardIndex,
                in: state.desks, presentedDeskID: deskID ?? presentedDeskID)
        else { return nil }
        storage.state.desks = creation.desks
        setFocusedDesk(creation.createdDesk.id)
        onWindowEffect?(.dismissTemporaryPresentation)
        onWindowEffect?(.exitDenMode)
        save()
        dispatchDenOperationEvent(.deskCreated)
        return creation.createdDesk
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
        focusedBoardIndex: BoardIndex?
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
            let result = DeskReplacement.replace(
                replacement.deskID, label: replacement.label, presetBoards: replacement.boards,
                focusedBoardIndex: replacement.focusedBoardIndex, in: state.desks)
        else { return }

        let removedBoardIDs = Set(result.removedBoards.map(\.id))
        for board in result.removedBoards {
            disposeRuntime(for: board.id)
        }
        storage.state.desks[result.deskIndex.rawValue] = result.desk
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

    func confirmDeskDeletion(_ deskID: DeskID) { deleteDesk(deskID) }

    private func deleteDesk(_ deskID: DeskID) {
        guard
            let deletion = DeskDeletion.delete(
                deskID, from: state.desks,
                isAvailable: { canPresentDesk?($0) ?? true })
        else { return }
        let desk = deletion.removedDesk
        for board in desk.boards {
            disposeRuntime(for: board.id)
        }

        storage.state.desks = deletion.desks
        if presentedDeskID == deskID {
            setFocusedDesk(deletion.replacementDeskID)
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
            storage.state.desks[deskIndex.rawValue].label = trimmed
        }
        onWindowEffect?(.dismissTemporaryPresentation)
        onWindowEffect?(.exitDenMode)
        save()
    }

    func deskScrollOffset(for deskID: DeskID) -> CGFloat? {
        guard let desk = state.desks.first(where: { $0.id == deskID }) else { return nil }
        return desk.scrollOffsetX.map { CGFloat($0) }
    }

    func saveDeskScrollOffset(_ offset: CGFloat?, for deskID: DeskID) {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }) else { return }
        let current = state.desks[deskIndex].scrollOffsetX
        let newDouble = offset.map { Double($0) }
        guard current != newDouble else { return }
        storage.state.desks[deskIndex].scrollOffsetX = newDouble
        save()
    }

    func copyDeskID(_ deskID: DeskID, pasteboard: NSPasteboard? = nil) {
        let pasteboard = pasteboard ?? self.pasteboard
        guard state.desks.contains(where: { $0.id == deskID }) else { return }
        pasteboard.clearContents()
        pasteboard.setString(deskID.rawValue.uuidString.lowercased(), forType: .string)
        reportFeedback("Copied Desk ID.", severity: .success)
    }
}
