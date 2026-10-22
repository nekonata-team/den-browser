public import DenApplication
public import DenDomain

/// M0's construction and visibility probe; not connected to a product screen.
@MainActor
public final class BoardOrderProbeModel {
    private let state: DenStateStore
    private let movement: BoardMovement
    private let deskID: DeskID

    public init(state: DenStateStore, movement: BoardMovement, deskID: DeskID) {
        self.state = state
        self.movement = movement
        self.deskID = deskID
    }

    public var boards: [BoardState] {
        state.snapshot.den.desks.first { $0.id == deskID }?.boards ?? []
    }

    public func reorder(_ boardID: BoardID, to index: BoardIndex) {
        movement.reorder(boardID, to: index, in: deskID)
    }
}
