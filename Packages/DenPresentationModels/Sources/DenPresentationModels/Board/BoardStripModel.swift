public import DenApplication
public import DenDomain
public import Foundation

@MainActor
public struct BoardStripModel {
    private let state: DenStateStore
    private let movement: BoardMovement
    private let sizing: BoardSizing
    private let deskUpdates: DeskUpdates
    private let readPresentedDeskID: () -> DeskID
    private let prepareDrag: () -> Void
    public let focus: (BoardID) -> Void
    public let remove: (BoardID) -> Void
    public let hasWebRuntime: (BoardID) -> Bool
    public let activateWebRuntime: (BoardState) -> Void
    private let readCentering: () -> FocusedBoardCentering
    private let readMotion: () -> MotionPreference

    public init(
        state: DenStateStore, movement: BoardMovement, sizing: BoardSizing, deskUpdates: DeskUpdates,
        presentedDeskID: @escaping () -> DeskID, prepareDrag: @escaping () -> Void,
        focus: @escaping (BoardID) -> Void, remove: @escaping (BoardID) -> Void,
        hasWebRuntime: @escaping (BoardID) -> Bool, activateWebRuntime: @escaping (BoardState) -> Void,
        centering: @escaping () -> FocusedBoardCentering, motion: @escaping () -> MotionPreference
    ) {
        self.state = state
        self.movement = movement
        self.sizing = sizing
        self.deskUpdates = deskUpdates
        self.readPresentedDeskID = presentedDeskID
        self.prepareDrag = prepareDrag
        self.focus = focus
        self.remove = remove
        self.hasWebRuntime = hasWebRuntime
        self.activateWebRuntime = activateWebRuntime
        self.readCentering = centering
        self.readMotion = motion
    }
    public var presentedDeskID: DeskID { readPresentedDeskID() }
    public var focusedDesk: DeskState? { state.snapshot.den.desks.first { $0.id == presentedDeskID } }
    public var boardCentering: FocusedBoardCentering { readCentering() }
    public var motionPreference: MotionPreference { readMotion() }
    public func beginBoardDrag(_ id: BoardID) -> Bool {
        movement.beginDrag(id, in: presentedDeskID, prepare: prepareDrag)
    }
    public func finishBoardDrag() { movement.finishDrag() }
    public func previewBoardMove(_ id: BoardID, to index: BoardIndex) {
        movement.preview(id, to: index, in: presentedDeskID)
    }
    public func restoreBoardOrder(_ ids: [BoardID], in deskID: DeskID) { movement.restoreOrder(ids, in: deskID) }
    public func resizeBoard(_ id: BoardID, to width: Double) { sizing.resizeBoard(id, to: width) }
    public func resizeBoardPair(_ id: BoardID, to width: Double) { sizing.resizePair(id, to: width) }
    public func saveBoardWidths() { sizing.saveWidths() }
    public func deskScrollOffset(for id: DeskID) -> CGFloat? {
        state.snapshot.den.desks.first { $0.id == id }?.scrollOffsetX.map { CGFloat($0) }
    }
    public func saveDeskScrollOffset(_ offset: CGFloat?, for id: DeskID) {
        deskUpdates.saveScrollOffset(offset.map(Double.init), for: id)
    }
}
