import DenDomain
import Foundation

@MainActor
public struct BoardUpdates {
    private let store: DenStateStore
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?

    public init(store: DenStateStore, writer: DenStateWriter, persist: ((DenState) -> Bool)? = nil) {
        self.store = store
        self.writer = writer
        self.persist = persist
    }

    public func recordZmxRoot(_ root: String?, for id: BoardID) {
        guard let root, let indices = indices(for: id),
            store.snapshot.den.desks[indices.desk].boards[indices.board].zmxRootSessionName != root
        else { return }
        writer.update { $0.den.desks[indices.desk].boards[indices.board].zmxRootSessionName = root }
        save()
    }

    public func rename(_ id: BoardID, to name: String, beforeSave: () -> Void) {
        guard let indices = indices(for: id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        writer.update { $0.den.desks[indices.desk].boards[indices.board].customLabel = trimmed.isEmpty ? nil : trimmed }
        beforeSave()
        save()
    }

    public func navigate(_ id: BoardID, to text: String, searchEngine: SearchEngine, beforeSave: () -> Void) -> URL? {
        guard let url = BoardInputResolver.normalizedURL(from: text, searchEngine: searchEngine),
            let indices = indices(for: id)
        else { return nil }
        writer.update { $0.den.desks[indices.desk].boards[indices.board].currentSheetURL = url }
        beforeSave()
        save()
        return url
    }

    public func updateWeb(_ id: BoardID, url: URL?, title: String?, recents: Recents, onURLChange: () -> Void) {
        guard let location = indices(for: id) else { return }
        let board = store.snapshot.den.desks[location.desk].boards[location.board]
        var changed = false
        if let url, WebURLPolicy.isSupported(url) {
            let canonical = WebURLPolicy.canonicalSheetURL(url)
            if board.currentSheetURL != canonical {
                writer.update { $0.den.desks[location.desk].boards[location.board].currentSheetURL = canonical }
                onURLChange()
                changed = true
            }
        }
        if let title, !title.isEmpty, board.label != title {
            writer.update { $0.den.desks[location.desk].boards[location.board].label = title }
        }
        if let title, let firstURL = board.firstSheetURL { recents.updateTitle(for: firstURL, title: title) }
        if changed { save() }
    }

    public func updateTerminal(_ id: BoardID, workingDirectory: String? = nil, title: String? = nil) {
        guard let location = indices(for: id), store.snapshot.den.desks[location.desk].boards[location.board].isTerminal
        else { return }
        let board = store.snapshot.den.desks[location.desk].boards[location.board]
        var changed = false
        if let workingDirectory, !workingDirectory.isEmpty, board.terminalWorkingDirectory != workingDirectory {
            writer.update {
                $0.den.desks[location.desk].boards[location.board].terminalWorkingDirectory = workingDirectory
            }
            changed = true
        }
        if let title, !title.isEmpty, board.label != title {
            writer.update { $0.den.desks[location.desk].boards[location.board].label = title }
        }
        if changed { save() }
    }

    private func indices(for id: BoardID) -> (desk: Int, board: Int)? {
        for desk in store.snapshot.den.desks.indices {
            if let board = store.snapshot.den.desks[desk].boards.firstIndex(where: { $0.id == id }) {
                return (desk, board)
            }
        }
        return nil
    }

    private func save() {
        guard store.snapshot.activeDrag == nil else { return }
        _ = persist?(store.snapshot.den)
    }
}
