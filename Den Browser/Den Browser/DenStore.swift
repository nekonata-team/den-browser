import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class DenStore {
    static let maximumDeskCount = 10

    var state: DenState
    var isOpenBoardPanelPresented = false
    var isNewDeskPanelPresented = false
    var isOverviewPresented = false
    var isKeyboardShortcutsPresented = false
    var isBoardWidthPanelPresented = false
    var isZenViewPresented = false
    var isDenMode = false
    private(set) var boardWidthPanelMessage: String?
    private(set) var deskPendingDeletion: DeskState?
    private(set) var maximizedBoardID: UUID?
    private(set) var centerFocusedBoardRequest = 0
    var overviewSelectionDeskID: UUID?
    var overviewSelectionBoardID: UUID?
    private(set) var heldBoard: HeldBoard?
    let sheetNavigation: SheetNavigationManager
    let websiteDataStore: WKWebsiteDataStore

    @ObservationIgnored private var runtimes: [UUID: BoardRuntime] = [:]
    @ObservationIgnored private let persistenceURL: URL?
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

    convenience init() {
        self.init(sheetNavigation: SheetNavigationManager())
    }

    init(sheetNavigation: SheetNavigationManager) {
        let persistenceURL = Self.makePersistenceURL()
        self.sheetNavigation = sheetNavigation
        websiteDataStore = .default()
        self.persistenceURL = persistenceURL
        onSave = nil
        state = Self.loadState(from: persistenceURL) ?? .sample
        ensureFocusedObjects()
    }

    convenience init(persistenceURL: URL) {
        self.init(persistenceURL: persistenceURL, sheetNavigation: SheetNavigationManager())
    }

    init(persistenceURL: URL, sheetNavigation: SheetNavigationManager) {
        self.sheetNavigation = sheetNavigation
        websiteDataStore = .default()
        self.persistenceURL = persistenceURL
        onSave = nil
        state = Self.loadState(from: persistenceURL) ?? .sample
        ensureFocusedObjects()
    }

    convenience init(state: DenState, persistenceURL: URL) {
        self.init(
            state: state,
            persistenceURL: persistenceURL,
            sheetNavigation: SheetNavigationManager()
        )
    }

    init(state: DenState, persistenceURL: URL, sheetNavigation: SheetNavigationManager) {
        self.sheetNavigation = sheetNavigation
        websiteDataStore = .default()
        self.persistenceURL = persistenceURL
        onSave = nil
        self.state = state
        ensureFocusedObjects()
    }

    init(
        state: DenState,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        onSave: @escaping (DenState) -> Void
    ) {
        self.state = state
        self.websiteDataStore = websiteDataStore
        self.sheetNavigation = sheetNavigation
        persistenceURL = nil
        self.onSave = onSave
        ensureFocusedObjects()
    }

    func focusDesk(_ deskID: UUID) {
        guard state.desks.contains(where: { $0.id == deskID }) else { return }
        state.focusedDeskID = deskID
        save()
    }

    func focusBoard(_ boardID: UUID) {
        guard let indices = boardIndices(for: boardID) else { return }
        state.focusedDeskID = state.desks[indices.desk].id
        state.desks[indices.desk].focusedBoardID = boardID
        save()
    }

    func focusPreviousDesk() {
        moveDeskFocus(by: -1)
    }

    func focusNextDesk() {
        moveDeskFocus(by: 1)
    }

    func focusPreviousBoard() {
        moveBoardFocus(by: -1)
    }

    func focusNextBoard() {
        moveBoardFocus(by: 1)
    }

    func moveFocusedBoardLeft() {
        moveFocusedBoard(by: -1)
    }

    func moveFocusedBoardRight() {
        moveFocusedBoard(by: 1)
    }

    func moveFocusedBoardToPreviousDesk() {
        moveFocusedBoardToDesk(by: -1)
    }

    func moveFocusedBoardToNextDesk() {
        moveFocusedBoardToDesk(by: 1)
    }

    func toggleFocusedBoardMaximized() {
        guard let focusedBoardID = focusedDesk?.focusedBoardID else { return }
        maximizedBoardID = maximizedBoardID == focusedBoardID ? nil : focusedBoardID
        centerFocusedBoard()
    }

    func centerFocusedBoard() {
        guard focusedDesk?.focusedBoardID != nil else { return }
        centerFocusedBoardRequest &+= 1
    }

    func focusDesk(number: Int) {
        guard (1...Self.maximumDeskCount).contains(number), state.desks.indices.contains(number - 1) else { return }
        state.focusedDeskID = state.desks[number - 1].id
        ensureFocusedObjects()
        save()
    }

    func moveFocusedBoard(toDeskNumber number: Int) {
        guard (1...Self.maximumDeskCount).contains(number), state.desks.indices.contains(number - 1) else { return }
        moveFocusedBoard(toDeskAt: number - 1)
    }

    func toggleDenMode() {
        guard
            !isOpenBoardPanelPresented,
            !isNewDeskPanelPresented,
            !isOverviewPresented,
            !isKeyboardShortcutsPresented,
            !isBoardWidthPanelPresented
        else { return }
        isDenMode.toggle()
    }

    func exitDenMode() {
        guard
            !isOpenBoardPanelPresented,
            !isNewDeskPanelPresented,
            !isOverviewPresented,
            !isKeyboardShortcutsPresented,
            !isBoardWidthPanelPresented
        else { return }
        isDenMode = false
    }

    func toggleZenView() {
        isZenViewPresented.toggle()
    }

    func showKeyboardShortcuts() {
        isOpenBoardPanelPresented = false
        isNewDeskPanelPresented = false
        hideBoardWidthPanel()
        hideOverview()
        isKeyboardShortcutsPresented = true
    }

    func hideKeyboardShortcuts() {
        isKeyboardShortcutsPresented = false
    }

    func showOpenBoardPanel() {
        isNewDeskPanelPresented = false
        isKeyboardShortcutsPresented = false
        hideBoardWidthPanel()
        hideOverview()
        isOpenBoardPanelPresented = true
    }

    func hideOpenBoardPanel() {
        isOpenBoardPanelPresented = false
    }

    func showNewDeskPanel() {
        guard canCreateDesk else { return }
        isOpenBoardPanelPresented = false
        isKeyboardShortcutsPresented = false
        hideBoardWidthPanel()
        hideOverview()
        isNewDeskPanelPresented = true
    }

    func hideNewDeskPanel() {
        isNewDeskPanelPresented = false
    }

    func createDesk(label: String, template: DeskTemplate) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, canCreateDesk, let focusedDeskIndex else { return }

        let desk = DeskState(label: trimmedLabel, boards: template.makeBoards())
        state.desks.insert(desk, at: focusedDeskIndex + 1)
        state.focusedDeskID = desk.id
        isNewDeskPanelPresented = false
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

    func toggleOverview() {
        if isOverviewPresented {
            hideOverview()
        } else {
            showOverview()
        }
    }

    func showOverview() {
        isOverviewPresented = true
        isOpenBoardPanelPresented = false
        isNewDeskPanelPresented = false
        isKeyboardShortcutsPresented = false
        hideBoardWidthPanel()
        overviewSelectionDeskID = state.focusedDeskID
        overviewSelectionBoardID = focusedDesk?.focusedBoardID
    }

    func hideOverview() {
        isOverviewPresented = false
        overviewSelectionDeskID = nil
        overviewSelectionBoardID = nil
    }

    func enterOverviewSelection() {
        guard
            let deskID = overviewSelectionDeskID,
            let deskIndex = state.desks.firstIndex(where: { $0.id == deskID })
        else {
            hideOverview()
            return
        }

        state.focusedDeskID = deskID
        if let boardID = overviewSelectionBoardID,
            state.desks[deskIndex].boards.contains(where: { $0.id == boardID })
        {
            state.desks[deskIndex].focusedBoardID = boardID
        }
        hideOverview()
        save()
    }

    func selectBoardInOverview(_ boardID: UUID) {
        guard let indices = boardIndices(for: boardID) else { return }
        overviewSelectionDeskID = state.desks[indices.desk].id
        overviewSelectionBoardID = boardID
    }

    func selectPreviousBoardInOverview() {
        moveOverviewBoardSelection(by: -1)
    }

    func selectNextBoardInOverview() {
        moveOverviewBoardSelection(by: 1)
    }

    func selectPreviousDeskInOverview() {
        moveOverviewDeskSelection(by: -1)
    }

    func selectNextDeskInOverview() {
        moveOverviewDeskSelection(by: 1)
    }

    func moveOverviewSelectionBoardLeft() {
        moveOverviewSelectionBoard(by: -1)
    }

    func moveOverviewSelectionBoardRight() {
        moveOverviewSelectionBoard(by: 1)
    }

    func moveOverviewSelectionBoardToPreviousDesk() {
        moveOverviewSelectionBoardToDesk(by: -1)
    }

    func moveOverviewSelectionBoardToNextDesk() {
        moveOverviewSelectionBoardToDesk(by: 1)
    }

    func resetDen() {
        for runtime in runtimes.values {
            sheetNavigation.didClose(runtime.webView)
        }
        runtimes.removeAll()
        state = .sample
        isOpenBoardPanelPresented = false
        isNewDeskPanelPresented = false
        isOverviewPresented = false
        isKeyboardShortcutsPresented = false
        isBoardWidthPanelPresented = false
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
        isOpenBoardPanelPresented = false
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
        isBoardWidthPanelPresented = true
    }

    func hideBoardWidthPanel() {
        isBoardWidthPanelPresented = false
        boardWidthPanelMessage = nil
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

    func runtime(for board: BoardState) -> BoardRuntime {
        if let runtime = runtimes[board.id] {
            return runtime
        }

        let runtime = BoardRuntime(
            board: board,
            websiteDataStore: websiteDataStore,
            sheetNavigation: sheetNavigation
        ) {
            [weak self] url in
            self?.addBoard(urlString: url.absoluteString, afterBoardID: board.id)
        } onChange: {
            [weak self] boardID, url, title in
            self?.updateBoard(boardID: boardID, url: url, title: title)
        }
        runtimes[board.id] = runtime
        return runtime
    }

    private var focusedDeskIndex: Int? {
        state.desks.firstIndex { $0.id == state.focusedDeskID }
    }

    private var focusedRuntime: BoardRuntime? {
        guard
            let desk = focusedDesk,
            let focusedBoardID = desk.focusedBoardID,
            let board = desk.boards.first(where: { $0.id == focusedBoardID })
        else { return nil }
        return runtime(for: board)
    }

    private func focusedBoardIndex(in deskIndex: Int) -> Int? {
        guard let focusedBoardID = state.desks[deskIndex].focusedBoardID else { return nil }
        return state.desks[deskIndex].boards.firstIndex { $0.id == focusedBoardID }
    }

    private func moveDeskFocus(by delta: Int) {
        guard let currentIndex = focusedDeskIndex, !state.desks.isEmpty else { return }
        let nextIndex = wrappedIndex(currentIndex + delta, count: state.desks.count)
        state.focusedDeskID = state.desks[nextIndex].id
        ensureFocusedObjects()
        save()
    }

    private func moveBoardFocus(by delta: Int) {
        guard
            let deskIndex = focusedDeskIndex,
            let currentIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        let boards = state.desks[deskIndex].boards
        guard !boards.isEmpty else { return }

        let nextIndex = wrappedIndex(currentIndex + delta, count: boards.count)
        state.desks[deskIndex].focusedBoardID = boards[nextIndex].id
        save()
    }

    private func moveFocusedBoard(by delta: Int) {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        var boards = state.desks[deskIndex].boards
        guard boards.count > 1 else { return }

        let board = boards.remove(at: boardIndex)
        let targetIndex = min(max(boardIndex + delta, 0), boards.count)
        boards.insert(board, at: targetIndex)

        state.desks[deskIndex].boards = boards
        state.desks[deskIndex].focusedBoardID = board.id
        save()
    }

    private func moveFocusedBoardToDesk(by delta: Int) {
        guard
            state.desks.count > 1,
            let sourceDeskIndex = focusedDeskIndex
        else { return }

        moveFocusedBoard(toDeskAt: wrappedIndex(sourceDeskIndex + delta, count: state.desks.count))
    }

    private func moveFocusedBoard(toDeskAt targetDeskIndex: Int) {
        guard
            state.desks.indices.contains(targetDeskIndex),
            let sourceDeskIndex = focusedDeskIndex,
            sourceDeskIndex != targetDeskIndex,
            let sourceBoardIndex = focusedBoardIndex(in: sourceDeskIndex)
        else { return }

        let board = removeBoard(at: (desk: sourceDeskIndex, board: sourceBoardIndex))
        let insertIndex: Int
        if let focusedBoardID = state.desks[targetDeskIndex].focusedBoardID,
            let focusedIndex = state.desks[targetDeskIndex].boards.firstIndex(where: { $0.id == focusedBoardID })
        {
            insertIndex = focusedIndex + 1
        } else {
            insertIndex = state.desks[targetDeskIndex].boards.endIndex
        }

        state.desks[targetDeskIndex].boards.insert(board, at: insertIndex)
        state.desks[targetDeskIndex].focusedBoardID = board.id
        state.focusedDeskID = state.desks[targetDeskIndex].id
        save()
    }

    private func moveOverviewBoardSelection(by delta: Int) {
        guard
            let deskIndex = overviewSelectionDeskIndex,
            !state.desks[deskIndex].boards.isEmpty
        else { return }

        let boards = state.desks[deskIndex].boards
        let currentIndex =
            overviewSelectionBoardID
            .flatMap { boardID in boards.firstIndex { $0.id == boardID } } ?? 0
        let nextIndex = wrappedIndex(currentIndex + delta, count: boards.count)
        overviewSelectionBoardID = boards[nextIndex].id
    }

    private func moveOverviewDeskSelection(by delta: Int) {
        guard !state.desks.isEmpty else { return }
        let currentIndex = overviewSelectionDeskIndex ?? focusedDeskIndex ?? 0
        let nextIndex = wrappedIndex(currentIndex + delta, count: state.desks.count)
        overviewSelectionDeskID = state.desks[nextIndex].id
        overviewSelectionBoardID = state.desks[nextIndex].focusedBoardID ?? state.desks[nextIndex].boards.first?.id
    }

    private func moveOverviewSelectionBoard(by delta: Int) {
        guard
            let boardID = overviewSelectionBoardID,
            let indices = boardIndices(for: boardID)
        else { return }

        var boards = state.desks[indices.desk].boards
        guard boards.count > 1 else { return }

        let board = boards.remove(at: indices.board)
        let targetIndex = min(max(indices.board + delta, 0), boards.count)
        boards.insert(board, at: targetIndex)
        state.desks[indices.desk].boards = boards
        overviewSelectionDeskID = state.desks[indices.desk].id
        overviewSelectionBoardID = board.id
        save()
    }

    private func moveOverviewSelectionBoardToDesk(by delta: Int) {
        guard
            let boardID = overviewSelectionBoardID,
            state.desks.count > 1,
            let source = boardIndices(for: boardID)
        else { return }

        let board = removeBoard(at: source)

        let targetDeskIndex = wrappedIndex(source.desk + delta, count: state.desks.count)
        let insertIndex: Int
        if let targetBoardID = overviewSelectionBoardID,
            let targetIndex = state.desks[targetDeskIndex].boards.firstIndex(where: { $0.id == targetBoardID })
        {
            insertIndex = targetIndex + 1
        } else if let focusedBoardID = state.desks[targetDeskIndex].focusedBoardID,
            let focusedIndex = state.desks[targetDeskIndex].boards.firstIndex(where: { $0.id == focusedBoardID })
        {
            insertIndex = focusedIndex + 1
        } else {
            insertIndex = state.desks[targetDeskIndex].boards.endIndex
        }

        state.desks[targetDeskIndex].boards.insert(board, at: insertIndex)
        overviewSelectionDeskID = state.desks[targetDeskIndex].id
        overviewSelectionBoardID = board.id
        save()
    }

    private var overviewSelectionDeskIndex: Int? {
        guard let overviewSelectionDeskID else { return nil }
        return state.desks.firstIndex { $0.id == overviewSelectionDeskID }
    }

    private func updateBoard(boardID: UUID, url: URL?, title: String?) {
        guard let indices = boardIndices(for: boardID) else { return }
        if let url {
            state.desks[indices.desk].boards[indices.board].currentURLString = url.absoluteString
        }
        if let title, !title.isEmpty {
            state.desks[indices.desk].boards[indices.board].label = title
        }
        save()
    }

    private func boardIndices(for boardID: UUID) -> (desk: Int, board: Int)? {
        for deskIndex in state.desks.indices {
            if let boardIndex = state.desks[deskIndex].boards.firstIndex(where: { $0.id == boardID }) {
                return (deskIndex, boardIndex)
            }
        }
        return nil
    }

    @discardableResult
    private func removeBoard(at indices: (desk: Int, board: Int)) -> BoardState {
        let board = state.desks[indices.desk].boards.remove(at: indices.board)
        let boards = state.desks[indices.desk].boards
        guard state.desks[indices.desk].focusedBoardID == board.id else { return board }

        state.desks[indices.desk].focusedBoardID =
            boards.indices.contains(indices.board)
            ? boards[indices.board].id
            : boards.last?.id
        return board
    }

    private func ensureFocusedObjects() {
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

    private func save() {
        if let onSave {
            onSave(stateForPersistence)
            return
        }
        guard let persistenceURL else { return }
        do {
            let directory = persistenceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.denEncoder.encode(stateForPersistence)
            try data.write(to: persistenceURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save Den state: \(error)")
        }
    }

    func releaseRuntimes() {
        for runtime in runtimes.values {
            sheetNavigation.didClose(runtime.webView)
            runtime.webView.stopLoading()
            runtime.webView.navigationDelegate = nil
        }
        runtimes.removeAll()
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

    private func wrappedIndex(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }

    private static func makePersistenceURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return
            directory
            .appending(path: "Den Browser", directoryHint: .isDirectory)
            .appending(path: "den-state.json")
    }

    private static func loadState(from url: URL) -> DenState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DenState.self, from: data)
    }
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
