import DenApplication
public import DenDomain

@MainActor
public struct BoardSurfaceModel {
    public enum Action {
        case focus
        case duplicate
        case moveLeft
        case moveRight
        case remove
        case copyID
        case copyLocation
        case inspect
        case moveToDrawer
        case goToFirst
        case toggleNavigation
        case screenshot
        case increaseSize
        case decreaseSize
        case resetSize
        case moveToDesk(Int)
    }

    private let readDesks: () -> [DeskState]
    public var desks: [DeskState] { readDesks() }
    public func canMoveToDrawer(_ board: BoardState) -> Bool {
        guard let desk = desks.first(where: { $0.boards.contains(where: { $0.id == board.id }) }) else { return false }
        return DrawerTransfer.canMove(board, among: desk.boards)
    }
    private let readBoardDeskID: () -> DeskID?
    public var boardDeskID: DeskID? { readBoardDeskID() }
    private let readCanMoveLeft: () -> Bool
    public var canMoveLeft: Bool { readCanMoveLeft() }
    private let readCanMoveRight: () -> Bool
    public var canMoveRight: Bool { readCanMoveRight() }
    private let readInputSourceLabel: () -> String?
    public var inputSourceLabel: String? { readInputSourceLabel() }
    private let readSheetNavigationEnabled: () -> Bool
    public var sheetNavigationEnabled: Bool { readSheetNavigationEnabled() }
    private let readDrawerStyle: () -> DrawerStyle
    public var drawerStyle: DrawerStyle { readDrawerStyle() }
    private let readMotionPreference: () -> MotionPreference
    public var motionPreference: MotionPreference { readMotionPreference() }
    public let perform: (Action) -> Void

    public init(
        desks: @escaping () -> [DeskState], boardDeskID: @escaping () -> DeskID?, canMoveLeft: @escaping () -> Bool,
        canMoveRight: @escaping () -> Bool, inputSourceLabel: @escaping () -> String?,
        sheetNavigationEnabled: @escaping () -> Bool, drawerStyle: @escaping () -> DrawerStyle,
        motionPreference: @escaping () -> MotionPreference,
        perform: @escaping (Action) -> Void
    ) {
        self.readDesks = desks
        self.readBoardDeskID = boardDeskID
        self.readCanMoveLeft = canMoveLeft
        self.readCanMoveRight = canMoveRight
        self.readInputSourceLabel = inputSourceLabel
        self.readSheetNavigationEnabled = sheetNavigationEnabled
        self.readDrawerStyle = drawerStyle
        self.readMotionPreference = motionPreference
        self.perform = perform
    }
}
