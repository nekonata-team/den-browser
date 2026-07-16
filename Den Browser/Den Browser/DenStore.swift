import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class DenStore {
    static let maximumDeskCount = 10

    var state: DenState
    private(set) var temporaryContext: TemporaryContext?
    var isZenViewPresented = false
    var isDenMode = false
    private(set) var boardWidthPanelMessage: String?
    private(set) var deskPendingDeletion: DeskState?
    var maximizedBoardID: UUID?
    var centerFocusedBoardRequest = 0
    var overviewSelectionDeskID: UUID?
    var overviewSelectionBoardID: UUID?
    private(set) var heldBoard: HeldBoard?
    let sheetNavigation: SheetNavigationManager
    let websiteDataStore: WKWebsiteDataStore

    @ObservationIgnored var runtimes: [UUID: BoardRuntime] = [:]
    @ObservationIgnored private let onSave: ((DenState) -> Void)?
    private var availableBoardWidth = 0.0
    private var boardSpacing = 0.0

    var focusedDesk: DeskState? {
        state.desks.first { $0.id == state.focusedDeskID }
    }

    var canCreateDesk: Bool {
        state.desks.count < Self.maximumDeskCount
    }

    var canDeleteFocusedDesk: Bool {
        state.desks.count > 1
            && focusedDesk?.id != heldBoard?.sourceDeskID
    }

    var heldBoardLabel: String? {
        heldBoard?.board.label
    }

    var isOpenBoardPanelPresented: Bool { temporaryContext == .openBoard }
    var isNewDeskPanelPresented: Bool { temporaryContext == .newDesk }
    var isOverviewPresented: Bool { temporaryContext == .overview }
    var isKeyboardShortcutsPresented: Bool { temporaryContext == .keyboardShortcuts }
    var isBoardWidthPanelPresented: Bool { temporaryContext == .boardWidth }

    convenience init() {
        self.init(state: .sample)
    }

    convenience init(state: DenState) {
        self.init(state: state, sheetNavigation: SheetNavigationManager())
    }

    convenience init(state: DenState, sheetNavigation: SheetNavigationManager) {
        self.init(
            state: state,
            websiteDataStore: .default(),
            sheetNavigation: sheetNavigation,
            onSave: nil
        )
    }

    convenience init(state: DenState, onSave: @escaping (DenState) -> Void) {
        self.init(
            state: state,
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            onSave: onSave
        )
    }

    init(
        state: DenState,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        onSave: ((DenState) -> Void)?
    ) {
        self.state = state
        self.websiteDataStore = websiteDataStore
        self.sheetNavigation = sheetNavigation
        self.onSave = onSave
        ensureFocusedObjects()
    }

    func createDesk(label: String, template: DeskTemplate) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, canCreateDesk, let focusedDeskIndex else { return }

        let desk = DeskState(label: trimmedLabel, boards: template.makeBoards())
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
            deskID != heldBoard?.sourceDeskID,
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

    func resetDen() {
        for runtime in runtimes.values {
            sheetNavigation.didClose(runtime.webView)
        }
        runtimes.removeAll()
        state = .sample
        setTemporaryContext(nil)
        isZenViewPresented = false
        boardWidthPanelMessage = nil
        overviewSelectionDeskID = nil
        overviewSelectionBoardID = nil
        heldBoard = nil
        isDenMode = false
        save()
    }

    func addBoard(urlString: String, preferredWidth: Double? = nil, afterBoardID: UUID? = nil) {
        guard let url = normalizedURL(from: urlString) else { return }
        let label = url.host(percentEncoded: false) ?? url.absoluteString
        let width = preferredWidth.map { min(max($0, 360), 980) } ?? 520
        let board = BoardState(label: label, width: width, currentURLString: url.absoluteString)

        let deskIndex: Int
        let insertIndex: Int
        if let afterBoardID {
            guard let indices = boardIndices(for: afterBoardID) else { return }
            deskIndex = indices.desk
            insertIndex = indices.board + 1
        } else {
            guard let focusedDeskIndex else { return }
            deskIndex = focusedDeskIndex
            if let focusedBoardIndex = focusedBoardIndex(in: deskIndex) {
                insertIndex = focusedBoardIndex + 1
            } else {
                insertIndex = state.desks[deskIndex].boards.endIndex
            }
        }

        state.desks[deskIndex].boards.insert(board, at: insertIndex)
        state.desks[deskIndex].focusedBoardID = board.id
        state.focusedDeskID = state.desks[deskIndex].id
        setTemporaryContext(nil)
        isDenMode = false
        save()
    }

    func adjustFocusedBoardWidth(by delta: Double) {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        maximizedBoardID = nil
        let width = state.desks[deskIndex].boards[boardIndex].width + delta
        state.desks[deskIndex].boards[boardIndex].width = min(max(width, 280), 1400)
        save()
    }

    func updateBoardLayout(availableWidth: Double, spacing: Double) {
        self.availableBoardWidth = availableWidth
        boardSpacing = spacing
    }

    func boardWidth(toFit count: Int) -> Double? {
        guard (1...9).contains(count), availableBoardWidth > 0 else { return nil }
        let width = (availableBoardWidth - boardSpacing * Double(count - 1)) / Double(count)
        guard width >= 280 else { return nil }
        return width
    }

    func canResizeFocusedDeskBoards(toFit count: Int) -> Bool {
        heldBoard == nil
            && focusedDesk?.boards.isEmpty == false
            && boardWidth(toFit: count) != nil
    }

    func showBoardWidthPanel() {
        guard focusedDesk?.boards.isEmpty == false else { return }
        boardWidthPanelMessage =
            heldBoard == nil ? nil : "Place or restore the Held Board first"
        setTemporaryContext(.boardWidth)
    }

    func hideBoardWidthPanel() {
        if temporaryContext == .boardWidth {
            setTemporaryContext(nil)
        }
    }

    @discardableResult
    func resizeFocusedDeskBoards(toFit count: Int) -> Bool {
        guard heldBoard == nil else {
            boardWidthPanelMessage = "Place or restore the Held Board first"
            return false
        }
        guard let deskIndex = focusedDeskIndex, let width = boardWidth(toFit: count) else {
            boardWidthPanelMessage = "\(count) Boards cannot fit at this window width"
            return false
        }

        for boardIndex in state.desks[deskIndex].boards.indices {
            state.desks[deskIndex].boards[boardIndex].width = width
        }
        maximizedBoardID = nil
        hideBoardWidthPanel()
        centerFocusedBoard()
        save()
        return true
    }

    func resizeBoard(_ boardID: UUID, to width: Double) {
        guard let indices = boardIndices(for: boardID) else { return }
        state.desks[indices.desk].boards[indices.board].width = min(max(width, 280), 1400)
    }

    func saveBoardWidths() {
        save()
    }

    func closeFocusedBoard() {
        guard let boardID = focusedDesk?.focusedBoardID else { return }
        closeBoard(boardID)
    }

    func closeBoard(_ boardID: UUID) {
        guard let indices = boardIndices(for: boardID) else { return }
        let closedBoard = removeBoard(at: indices)
        if maximizedBoardID == closedBoard.id {
            maximizedBoardID = nil
        }
        if let runtime = runtimes.removeValue(forKey: closedBoard.id) {
            sheetNavigation.didClose(runtime.webView)
        }

        save()
    }

    func duplicateFocusedBoard() {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        let source = state.desks[deskIndex].boards[boardIndex]
        let board = BoardState(
            label: source.label,
            width: source.width,
            currentURLString: source.currentURLString
        )
        state.desks[deskIndex].boards.insert(board, at: boardIndex + 1)
        state.desks[deskIndex].focusedBoardID = board.id
        isDenMode = false
        save()
    }

    func holdFocusedBoard() {
        guard heldBoard == nil else { return }
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        let board = removeBoard(at: (desk: deskIndex, board: boardIndex))
        if maximizedBoardID == board.id {
            maximizedBoardID = nil
        }
        heldBoard = HeldBoard(board: board, sourceDeskID: state.desks[deskIndex].id, sourceBoardIndex: boardIndex)
        save()
    }

    func placeHeldBoard(beforeFocusedBoard: Bool = false) {
        guard
            let heldBoard,
            let targetDeskIndex = focusedDeskIndex
        else { return }

        let targetBoardID = state.desks[targetDeskIndex].focusedBoardID

        let insertIndex: Int
        if let targetBoardID,
            let targetIndex = state.desks[targetDeskIndex].boards.firstIndex(where: { $0.id == targetBoardID })
        {
            insertIndex = targetIndex + (beforeFocusedBoard ? 0 : 1)
        } else {
            insertIndex = state.desks[targetDeskIndex].boards.endIndex
        }

        state.desks[targetDeskIndex].boards.insert(heldBoard.board, at: insertIndex)
        state.desks[targetDeskIndex].focusedBoardID = heldBoard.board.id
        state.focusedDeskID = state.desks[targetDeskIndex].id
        self.heldBoard = nil
        save()
    }

    func restoreHeldBoard() {
        guard
            let heldBoard,
            let deskIndex = state.desks.firstIndex(where: { $0.id == heldBoard.sourceDeskID })
        else { return }

        let insertIndex = min(heldBoard.sourceBoardIndex, state.desks[deskIndex].boards.endIndex)
        state.desks[deskIndex].boards.insert(heldBoard.board, at: insertIndex)
        state.desks[deskIndex].focusedBoardID = heldBoard.board.id
        state.focusedDeskID = state.desks[deskIndex].id
        self.heldBoard = nil
        save()
    }

    func goBackInFocusedBoard() {
        focusedRuntime?.webView.goBack()
    }

    func goForwardInFocusedBoard() {
        focusedRuntime?.webView.goForward()
    }

    func goBackInBoard(_ boardID: UUID) {
        guard boardIndices(for: boardID) != nil else { return }
        focusBoard(boardID)
        focusedRuntime?.webView.goBack()
    }

    func goForwardInBoard(_ boardID: UUID) {
        guard boardIndices(for: boardID) != nil else { return }
        focusBoard(boardID)
        focusedRuntime?.webView.goForward()
    }

    func reloadFocusedBoard() {
        focusedRuntime?.reload()
    }

    var focusedDeskIndex: Int? {
        state.desks.firstIndex { $0.id == state.focusedDeskID }
    }

    func boardIndices(for boardID: UUID) -> (desk: Int, board: Int)? {
        for deskIndex in state.desks.indices {
            if let boardIndex = state.desks[deskIndex].boards.firstIndex(where: { $0.id == boardID }) {
                return (deskIndex, boardIndex)
            }
        }
        return nil
    }

    @discardableResult
    func removeBoard(at indices: (desk: Int, board: Int)) -> BoardState {
        let board = state.desks[indices.desk].boards.remove(at: indices.board)
        let boards = state.desks[indices.desk].boards
        guard state.desks[indices.desk].focusedBoardID == board.id else { return board }

        state.desks[indices.desk].focusedBoardID =
            boards.indices.contains(indices.board)
            ? boards[indices.board].id
            : boards.last?.id
        return board
    }

    func ensureFocusedObjects() {
        if !state.desks.contains(where: { $0.id == state.focusedDeskID }),
            let firstDeskID = state.desks.first?.id
        {
            state.focusedDeskID = firstDeskID
        }

        for deskIndex in state.desks.indices {
            let boards = state.desks[deskIndex].boards
            if !boards.contains(where: { $0.id == state.desks[deskIndex].focusedBoardID }) {
                state.desks[deskIndex].focusedBoardID = boards.first?.id
            }
        }
    }

    func save() {
        onSave?(stateForPersistence)
    }

    private var stateForPersistence: DenState {
        guard
            let heldBoard,
            let deskIndex = state.desks.firstIndex(where: { $0.id == heldBoard.sourceDeskID })
        else { return state }

        var restoredState = state
        let insertIndex = min(heldBoard.sourceBoardIndex, restoredState.desks[deskIndex].boards.endIndex)
        restoredState.desks[deskIndex].boards.insert(heldBoard.board, at: insertIndex)
        restoredState.desks[deskIndex].focusedBoardID = heldBoard.board.id
        restoredState.focusedDeskID = heldBoard.sourceDeskID
        return restoredState
    }

    private func normalizedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        if trimmed.contains(".") {
            return URL(string: "https://\(trimmed)")
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }

    func wrappedIndex(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }

    func setTemporaryContext(_ context: TemporaryContext?) {
        if temporaryContext == .overview, context != .overview {
            overviewSelectionDeskID = nil
            overviewSelectionBoardID = nil
        }
        if temporaryContext == .boardWidth, context != .boardWidth {
            boardWidthPanelMessage = nil
        }
        temporaryContext = context
    }
}

enum TemporaryContext {
    case openBoard
    case newDesk
    case overview
    case keyboardShortcuts
    case boardWidth
}

struct HeldBoard {
    let board: BoardState
    let sourceDeskID: UUID
    let sourceBoardIndex: Int
}

extension JSONEncoder {
    static var denEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
