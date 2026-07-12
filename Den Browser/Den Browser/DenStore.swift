import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class DenStore {
    var state: DenState
    var isOpenBoardPanelPresented = false
    var isNewDeskPanelPresented = false
    var isOverviewPresented = false
    var overviewSelectionDeskID: UUID?
    var overviewSelectionBoardID: UUID?
    var heldBoardID: UUID?

    @ObservationIgnored private var runtimes: [UUID: BoardRuntime] = [:]
    @ObservationIgnored private let persistenceURL: URL

    var focusedDesk: DeskState? {
        state.desks.first { $0.id == state.focusedDeskID }
    }

    init() {
        let persistenceURL = Self.makePersistenceURL()
        self.persistenceURL = persistenceURL
        state = Self.loadState(from: persistenceURL) ?? .sample
        ensureFocusedObjects()
    }

    init(persistenceURL: URL) {
        self.persistenceURL = persistenceURL
        state = Self.loadState(from: persistenceURL) ?? .sample
        ensureFocusedObjects()
    }

    init(state: DenState, persistenceURL: URL) {
        self.persistenceURL = persistenceURL
        self.state = state
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

    func showOpenBoardPanel() {
        isNewDeskPanelPresented = false
        hideOverview()
        isOpenBoardPanelPresented = true
    }

    func hideOpenBoardPanel() {
        isOpenBoardPanelPresented = false
    }

    func showNewDeskPanel() {
        isOpenBoardPanelPresented = false
        hideOverview()
        isNewDeskPanelPresented = true
    }

    func hideNewDeskPanel() {
        isNewDeskPanelPresented = false
    }

    func createDesk(label: String, template: DeskTemplate) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, let focusedDeskIndex else { return }

        let desk = DeskState(label: trimmedLabel, boards: template.makeBoards())
        state.desks.insert(desk, at: focusedDeskIndex + 1)
        state.focusedDeskID = desk.id
        isNewDeskPanelPresented = false
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
           state.desks[deskIndex].boards.contains(where: { $0.id == boardID }) {
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
        runtimes.removeAll()
        state = .sample
        isOpenBoardPanelPresented = false
        isNewDeskPanelPresented = false
        isOverviewPresented = false
        overviewSelectionDeskID = nil
        overviewSelectionBoardID = nil
        heldBoardID = nil
        save()
    }

    func addBoard(urlString: String, preferredWidth: Double? = nil) {
        guard let url = normalizedURL(from: urlString) else { return }
        let label = url.host(percentEncoded: false) ?? url.absoluteString
        let width = preferredWidth.map { min(max($0, 360), 980) } ?? 520
        let board = BoardState(label: label, width: width, currentURLString: url.absoluteString)

        guard let deskIndex = focusedDeskIndex else { return }
        let focusedBoardID = state.desks[deskIndex].focusedBoardID
        let insertIndex: Int
        if let focusedBoardID,
           let currentIndex = state.desks[deskIndex].boards.firstIndex(where: { $0.id == focusedBoardID }) {
            insertIndex = currentIndex + 1
        } else {
            insertIndex = state.desks[deskIndex].boards.endIndex
        }

        state.desks[deskIndex].boards.insert(board, at: insertIndex)
        state.desks[deskIndex].focusedBoardID = board.id
        isOpenBoardPanelPresented = false
        save()
    }

    func adjustFocusedBoardWidth(by delta: Double) {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        let width = state.desks[deskIndex].boards[boardIndex].width + delta
        state.desks[deskIndex].boards[boardIndex].width = min(max(width, 280), 1400)
        save()
    }

    func closeFocusedBoard() {
        guard heldBoardID == nil else { return }

        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        let closedBoard = removeBoard(at: (desk: deskIndex, board: boardIndex))
        runtimes.removeValue(forKey: closedBoard.id)

        save()
    }

    func duplicateFocusedBoard() {
        guard
            heldBoardID == nil,
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
        save()
    }

    func holdFocusedBoard() {
        guard heldBoardID == nil else { return }
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex),
            let focusedBoardID = state.desks[deskIndex].focusedBoardID,
            state.desks[deskIndex].boards.contains(where: { $0.id == focusedBoardID })
        else { return }

        heldBoardID = focusedBoardID

        let boards = state.desks[deskIndex].boards
        if boards.count > 1 {
            let targetIndex = boardIndex < boards.count - 1 ? boardIndex + 1 : boardIndex - 1
            state.desks[deskIndex].focusedBoardID = boards[targetIndex].id
        }
    }

    func placeHeldBoard() {
        guard
            let heldBoardID,
            let source = boardIndices(for: heldBoardID),
            let targetDeskIndex = focusedDeskIndex
        else { return }

        let targetBoardID = state.desks[targetDeskIndex].focusedBoardID
        let board = removeBoard(at: source)

        let insertIndex: Int
        if let targetBoardID,
           targetBoardID != heldBoardID,
           let targetIndex = state.desks[targetDeskIndex].boards.firstIndex(where: { $0.id == targetBoardID }) {
            insertIndex = targetIndex + 1
        } else {
            insertIndex = state.desks[targetDeskIndex].boards.endIndex
        }

        state.desks[targetDeskIndex].boards.insert(board, at: insertIndex)
        state.desks[targetDeskIndex].focusedBoardID = heldBoardID
        state.focusedDeskID = state.desks[targetDeskIndex].id
        self.heldBoardID = nil
        save()
    }

    func cancelHeldBoard() {
        heldBoardID = nil
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

        let runtime = BoardRuntime(board: board) { [weak self] boardID, url, title in
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

        let nextIndex = nextFocusableBoardIndex(from: currentIndex, by: delta, in: boards)
        state.desks[deskIndex].focusedBoardID = boards[nextIndex].id
        save()
    }

    private func moveFocusedBoard(by delta: Int) {
        guard
            heldBoardID == nil,
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
            heldBoardID == nil,
            state.desks.count > 1,
            let sourceDeskIndex = focusedDeskIndex,
            let sourceBoardIndex = focusedBoardIndex(in: sourceDeskIndex)
        else { return }

        let board = removeBoard(at: (desk: sourceDeskIndex, board: sourceBoardIndex))

        let targetDeskIndex = wrappedIndex(sourceDeskIndex + delta, count: state.desks.count)
        let insertIndex: Int
        if let focusedBoardID = state.desks[targetDeskIndex].focusedBoardID,
           let focusedIndex = state.desks[targetDeskIndex].boards.firstIndex(where: { $0.id == focusedBoardID }) {
            insertIndex = focusedIndex + 1
        } else {
            insertIndex = state.desks[targetDeskIndex].boards.endIndex
        }

        state.desks[targetDeskIndex].boards.insert(board, at: insertIndex)
        state.desks[targetDeskIndex].focusedBoardID = board.id
        state.focusedDeskID = state.desks[targetDeskIndex].id
        save()
    }

    private func nextFocusableBoardIndex(from currentIndex: Int, by delta: Int, in boards: [BoardState]) -> Int {
        guard let heldBoardID, boards.count > 1 else {
            return wrappedIndex(currentIndex + delta, count: boards.count)
        }

        var nextIndex = currentIndex
        repeat {
            nextIndex = wrappedIndex(nextIndex + delta, count: boards.count)
        } while boards[nextIndex].id == heldBoardID

        return nextIndex
    }

    private func moveOverviewBoardSelection(by delta: Int) {
        guard
            let deskIndex = overviewSelectionDeskIndex,
            !state.desks[deskIndex].boards.isEmpty
        else { return }

        let boards = state.desks[deskIndex].boards
        let currentIndex = overviewSelectionBoardID
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
           let targetIndex = state.desks[targetDeskIndex].boards.firstIndex(where: { $0.id == targetBoardID }) {
            insertIndex = targetIndex + 1
        } else if let focusedBoardID = state.desks[targetDeskIndex].focusedBoardID,
                  let focusedIndex = state.desks[targetDeskIndex].boards.firstIndex(where: { $0.id == focusedBoardID }) {
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

        state.desks[indices.desk].focusedBoardID = boards.indices.contains(indices.board)
            ? boards[indices.board].id
            : boards.last?.id
        return board
    }

    private func ensureFocusedObjects() {
        if !state.desks.contains(where: { $0.id == state.focusedDeskID }),
           let firstDeskID = state.desks.first?.id {
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
        do {
            let directory = persistenceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.denEncoder.encode(state)
            try data.write(to: persistenceURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save Den state: \(error)")
        }
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
        return directory
            .appending(path: "Den Browser", directoryHint: .isDirectory)
            .appending(path: "den-state.json")
    }

    private static func loadState(from url: URL) -> DenState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DenState.self, from: data)
    }
}

private extension JSONEncoder {
    static var denEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
