public import DenApplication
import DenDomain
import Foundation
import Observation

@MainActor
@Observable
public final class BoardEditingModel {
    @ObservationIgnored private let state: DenStateStore
    @ObservationIgnored private let updates: BoardUpdates
    @ObservationIgnored private let recents: Recents
    @ObservationIgnored private let movement: BoardMovement
    @ObservationIgnored private let readFocusedBoard: () -> BoardState?
    @ObservationIgnored private let readEssentials: () -> [Essential]
    @ObservationIgnored private let searchEngine: () -> SearchEngine
    @ObservationIgnored private let finishEditing: () -> Void
    @ObservationIgnored private let loadURL: (BoardID, URL) -> Void
    @ObservationIgnored private let restoreInput: () -> Void
    @ObservationIgnored private let duplicateZmx: (String) -> Void
    @ObservationIgnored private let focus: (BoardID) -> Void
    @ObservationIgnored private let center: () -> Void

    public init(
        state: DenStateStore, updates: BoardUpdates, recents: Recents, movement: BoardMovement,
        focusedBoard: @escaping () -> BoardState?, essentials: @escaping () -> [Essential],
        searchEngine: @escaping () -> SearchEngine, finishEditing: @escaping () -> Void,
        loadURL: @escaping (BoardID, URL) -> Void, restoreInput: @escaping () -> Void,
        duplicateZmx: @escaping (String) -> Void, focus: @escaping (BoardID) -> Void,
        center: @escaping () -> Void
    ) {
        self.state = state
        self.updates = updates
        self.recents = recents
        self.movement = movement
        self.readFocusedBoard = focusedBoard
        self.readEssentials = essentials
        self.searchEngine = searchEngine
        self.finishEditing = finishEditing
        self.loadURL = loadURL
        self.restoreInput = restoreInput
        self.duplicateZmx = duplicateZmx
        self.focus = focus
        self.center = center
    }

    public static func normalizedZmxSuffix(_ text: String) -> String { ZmxSessionNameGenerator.normalizedSuffix(text) }

    public var focusedBoard: BoardState? { readFocusedBoard() }
    public var essentials: [Essential] { readEssentials() }
    public var recentItems: [RecentItem] { state.snapshot.recentItems }

    public func removeRecentItem(_ item: RecentItem) { recents.remove(item) }
    public func clearRecent() { recents.clear() }
    public func restoreFocusedFirstResponder() { restoreInput() }
    public func duplicateFocusedZmxBoard(suffix: String) { duplicateZmx(suffix) }

    public func renameFocusedBoard(to name: String) {
        guard let id = focusedBoard?.id else { return }
        updates.rename(id, to: name, beforeSave: finishEditing)
    }

    @discardableResult
    public func navigateFocusedBoard(urlString: String) -> Bool {
        guard let id = focusedBoard?.id,
            let url = updates.navigate(id, to: urlString, searchEngine: searchEngine(), beforeSave: finishEditing)
        else { return false }
        loadURL(id, url)
        return true
    }

    public func moveBoard(_ id: BoardID, by delta: Int) {
        focus(id)
        guard let focusedBoard else { return }
        movement.shiftAndCenter(focusedBoard.id, by: delta, center: center)
    }
}
