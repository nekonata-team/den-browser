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

        let boards = boards.map { $0.makeBoard() }
        let focusedBoardID = focusedBoardIndex.flatMap { boards.indices.contains($0) ? boards[$0].id : nil }
        let desk = DeskState(label: trimmedLabel, boards: boards, focusedBoardID: focusedBoardID)
        state.desks.insert(desk, at: focusedDeskIndex + 1)
        setFocusedDesk(desk.id)
        setTemporaryContext(nil)
        isDenMode = false
        save()
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

    func confirmDeskReplacement() {
        guard let replacement = deskPendingReplacement else { return }
        pendingConfirmation = nil
        applyDeskReplacement(replacement)
    }

    func cancelDeskReplacement() {
        if deskPendingReplacement != nil {
            pendingConfirmation = nil
        }
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
        pendingConfirmation = .replaceDesk(replacement)
        return .confirmationPending
    }

    private func applyDeskReplacement(_ replacement: PendingDeskReplacement) {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == replacement.deskID }) else { return }

        for board in state.desks[deskIndex].boards {
            disposeRuntime(for: board.id)
        }
        let boards = replacement.boards.map { $0.makeBoard() }
        state.desks[deskIndex].label = replacement.label
        state.desks[deskIndex].boards = boards
        state.desks[deskIndex].focusedBoardID =
            replacement.focusedBoardIndex.flatMap { boards.indices.contains($0) ? boards[$0].id : nil }
            ?? boards.first?.id
        maximizedBoardID = nil
        setTemporaryContext(nil)
        isDenMode = false
        save()
        showToast("Replaced Desk with Preset.", style: .success)
    }

    func deleteFocusedDesk() {
        guard canDeleteFocusedDesk else {
            showToast("The last desk cannot be deleted.", style: .warning)
            return
        }
        guard let focusedDesk else { return }

        if focusedDesk.boards.isEmpty {
            deleteDesk(focusedDesk.id)
        } else {
            pendingConfirmation = .deleteDesk(focusedDesk)
        }
    }

    func confirmDeskDeletion() {
        guard let deskID = deskPendingDeletion?.id else { return }
        pendingConfirmation = nil
        deleteDesk(deskID)
    }

    func cancelDeskDeletion() {
        if deskPendingDeletion != nil {
            pendingConfirmation = nil
        }
    }

    private func deleteDesk(_ deskID: UUID) {
        guard
            state.desks.count > 1,
            let deskIndex = state.desks.firstIndex(where: { $0.id == deskID })
        else { return }
        let replacementCandidates = state.desks.dropFirst(deskIndex + 1) + state.desks.prefix(deskIndex).reversed()
        guard
            let replacementDeskID = replacementCandidates.first(where: {
                $0.id != deskID && (canPresentDesk?($0.id) ?? true)
            })?.id
        else { return }

        let desk = state.desks[deskIndex]
        for board in desk.boards {
            if maximizedBoardID == board.id {
                maximizedBoardID = nil
            }
            disposeRuntime(for: board.id)
        }

        state.desks.remove(at: deskIndex)
        if presentedDeskID == deskID {
            setFocusedDesk(replacementDeskID)
        }
        if isOverviewPresented {
            overviewSelection = OverviewSelection(
                deskID: presentedDeskID,
                boardID: focusedDesk?.focusedBoardID)
        }
        save()
    }

    func renameFocusedDesk(to newLabel: String) {
        guard let deskIndex = focusedDeskIndex else { return }
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            state.desks[deskIndex].label = trimmed
        }
        setTemporaryContext(nil)
        isDenMode = false
        save()
    }
}
