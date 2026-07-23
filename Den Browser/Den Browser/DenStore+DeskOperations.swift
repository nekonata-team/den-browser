import Foundation

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
        state.focusedDeskID = desk.id
        setTemporaryContext(nil)
        isDenMode = false
        save()
    }

    func deleteFocusedDesk() {
        guard canDeleteFocusedDesk, let focusedDesk else { return }

        if focusedDesk.boards.isEmpty {
            deleteDesk(focusedDesk.id)
        } else {
            deskPendingDeletion = focusedDesk
        }
    }

    func confirmDeskDeletion() {
        guard let deskID = deskPendingDeletion?.id else { return }
        deskPendingDeletion = nil
        deleteDesk(deskID)
    }

    func cancelDeskDeletion() {
        deskPendingDeletion = nil
    }

    private func deleteDesk(_ deskID: UUID) {
        guard
            state.desks.count > 1,
            let deskIndex = state.desks.firstIndex(where: { $0.id == deskID })
        else { return }

        let desk = state.desks[deskIndex]
        for board in desk.boards {
            if maximizedBoardID == board.id {
                maximizedBoardID = nil
            }
            if let runtime = runtimes.removeValue(forKey: board.id) {
                sheetNavigation.didClose(runtime.webView)
            }
        }

        state.desks.remove(at: deskIndex)
        if state.focusedDeskID == deskID {
            state.focusedDeskID = state.desks[min(deskIndex, state.desks.count - 1)].id
        }
        if isOverviewPresented {
            overviewSelectionDeskID = state.focusedDeskID
            overviewSelectionBoardID = focusedDesk?.focusedBoardID
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
