import DenDomain

public enum DenStateNormalization {
    public static func normalize(_ state: DenState) -> DenState {
        if state.desks.isEmpty {
            return .sample
        }
        var copy = state
        if !copy.desks.contains(where: { $0.id == copy.focusedDeskID }),
            let firstDeskID = copy.desks.first?.id
        {
            copy.focusedDeskID = firstDeskID
        }
        for deskIndex in copy.desks.indices {
            let boardCount = copy.desks[deskIndex].boards.count
            copy.desks[deskIndex].boards.removeAll(where: \.isTutorial)
            if copy.desks[deskIndex].boards.count != boardCount {
                copy.desks[deskIndex].scrollOffsetX = nil
            }
            for boardIndex in copy.desks[deskIndex].boards.indices {
                copy.desks[deskIndex].boards[boardIndex].currentSheetURL =
                    copy.desks[deskIndex].boards[boardIndex].currentSheetURL.map(WebURLPolicy.canonicalSheetURL)
                copy.desks[deskIndex].boards[boardIndex].firstSheetURL =
                    copy.desks[deskIndex].boards[boardIndex].firstSheetURL.map(WebURLPolicy.canonicalSheetURL)
            }
            let boards = copy.desks[deskIndex].boards
            if !boards.contains(where: { $0.id == copy.desks[deskIndex].focusedBoardID }) {
                copy.desks[deskIndex].focusedBoardID = boards.first?.id
            }
            if let anchorBoardID = copy.desks[deskIndex].anchorBoardID,
                !boards.contains(where: { $0.id == anchorBoardID })
            {
                copy.desks[deskIndex].anchorBoardID = nil
            }
        }
        return copy
    }
}
