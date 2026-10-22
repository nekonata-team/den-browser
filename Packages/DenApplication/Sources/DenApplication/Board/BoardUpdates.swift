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
