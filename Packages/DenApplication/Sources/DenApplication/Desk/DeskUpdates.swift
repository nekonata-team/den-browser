public import DenDomain
import Foundation

public struct DeskUpdates {
    private let store: DenStateReader
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?

    public init(store: DenStateReader, writer: DenStateWriter, persist: ((DenState) -> Bool)? = nil) {
        self.store = store
        self.writer = writer
        self.persist = persist
    }

    public func recordPresentedDesk(_ id: DeskID) {
        guard store.snapshot.den.desks.contains(where: { $0.id == id }) else { return }
        writer.update { $0.den.focusedDeskID = id }
    }

    public func rename(_ id: DeskID, to label: String, notify: () -> Void) {
        guard let index = store.snapshot.den.desks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { writer.update { $0.den.desks[index].label = trimmed } }
        notify()
        save()
    }

    public func saveScrollOffset(_ offset: Double?, for id: DeskID) {
        guard let index = store.snapshot.den.desks.firstIndex(where: { $0.id == id }),
            store.snapshot.den.desks[index].scrollOffsetX != offset
        else { return }
        writer.update { $0.den.desks[index].scrollOffsetX = offset }
        save()
    }

    private func save() {
        guard store.snapshot.activeDrag == nil else { return }
        _ = persist?(store.snapshot.den)
    }
}
