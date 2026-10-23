public import DenApplication
import DenDomain
import Observation

@MainActor
@Observable
public final class WindowNavigationModel {
    public private(set) var presentedDeskID: DeskID
    @ObservationIgnored public var previousFocusedDeskID: DeskID?
    @ObservationIgnored public var anchorJumpOriginBoardIDByDesk: [DeskID: BoardID] = [:]

    @ObservationIgnored private let state: DenStateStore

    public init(state: DenStateStore, presentedDeskID: DeskID) {
        self.state = state
        self.presentedDeskID = presentedDeskID
    }

    public var focusedDesk: DeskState? {
        state.snapshot.den.desks.first { $0.id == presentedDeskID }
    }

    public var focusedBoard: BoardState? {
        guard let desk = focusedDesk else { return nil }
        return desk.boards.first { $0.id == desk.focusedBoardID }
    }

    public func board(for id: BoardID) -> BoardState? {
        state.snapshot.den.board(for: id)
    }

    public func present(_ deskID: DeskID) {
        guard presentedDeskID != deskID else { return }
        previousFocusedDeskID = presentedDeskID
        presentedDeskID = deskID
    }

    public func replacePresentedDesk(_ deskID: DeskID) {
        presentedDeskID = deskID
    }

    public func clearHistory() {
        previousFocusedDeskID = nil
        anchorJumpOriginBoardIDByDesk.removeAll()
    }

    public func invalidateBoards(_ ids: Set<BoardID>) {
        anchorJumpOriginBoardIDByDesk = anchorJumpOriginBoardIDByDesk.filter { !ids.contains($0.value) }
    }

    public func invalidateDesk(_ id: DeskID) {
        if previousFocusedDeskID == id { previousFocusedDeskID = nil }
        anchorJumpOriginBoardIDByDesk.removeValue(forKey: id)
    }
}
