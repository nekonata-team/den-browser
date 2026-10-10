import DenDomain
import Foundation

public enum ActiveDrag: Equatable {
    case board(BoardID)
    case desk(DeskID)
}

public struct RecentlyRemovedBoard: Equatable {
    public let board: BoardState
    public var sideBoard: BoardState?
    public let sourceDeskID: DeskID
    public let sourceBoardIndex: Int

    public init(board: BoardState, sideBoard: BoardState? = nil, sourceDeskID: DeskID, sourceBoardIndex: Int) {
        self.board = board
        self.sideBoard = sideBoard
        self.sourceDeskID = sourceDeskID
        self.sourceBoardIndex = sourceBoardIndex
    }
}

/// Profile-shared data.
///
/// Runtime resources and window presentation state are kept outside this value.
public struct DenSharedState: Equatable {
    public var den: DenState
    public var deskPresets: [PersonalDeskPreset]
    public var recentItems: [RecentItem]
    public var notifications: [DenNotification] = []
    public var activeDrag: ActiveDrag?
    public var recentlyRemovedBoards: [RecentlyRemovedBoard] = []
    public var recentlyDiscardedDrawerItems: [DrawerItem] = []

    public init(den: DenState, deskPresets: [PersonalDeskPreset] = [], recentItems: [RecentItem] = []) {
        self.den = den
        self.deskPresets = deskPresets
        self.recentItems = recentItems
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.den == rhs.den
            && lhs.deskPresets == rhs.deskPresets
            && equalRecentData(lhs.recentItems, rhs.recentItems)
            && lhs.notifications == rhs.notifications
            && lhs.activeDrag == rhs.activeDrag
            && lhs.recentlyRemovedBoards == rhs.recentlyRemovedBoards
            && lhs.recentlyDiscardedDrawerItems == rhs.recentlyDiscardedDrawerItems
    }

    // RecentItem equality identifies a work target; snapshot equality also includes its saved metadata.
    private static func equalRecentData(_ lhs: [RecentItem], _ rhs: [RecentItem]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { first, second in
            switch (first, second) {
            case (.url(let firstURL, let firstTitle), .url(let secondURL, let secondTitle)):
                return firstURL == secondURL && firstTitle == secondTitle
            case (.search(let first), .search(let second)),
                (.terminal(let first), .terminal(let second)),
                (.zmx(let first), .zmx(let second)):
                return first == second
            case (.zellij(let first), .zellij(let second)):
                return first == second
            default:
                return false
            }
        }
    }
}
