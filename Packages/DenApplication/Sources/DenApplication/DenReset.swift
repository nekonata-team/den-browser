public import DenDomain

public struct DenReset {
    public enum Notice {
        case prepare
        case cancelDrag(ActiveDrag)
        case stateReplaced(DeskID)
        case clearInputRequests
        case clearWindowReferences
        case finished
    }

    private let store: DenStateReader
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?

    public init(store: DenStateReader, writer: DenStateWriter, persist: ((DenState) -> Bool)? = nil) {
        self.store = store
        self.writer = writer
        self.persist = persist
    }

    public func perform(notify: (Notice) -> Void) {
        notify(.prepare)
        if let drag = store.snapshot.activeDrag { notify(.cancelDrag(drag)) }
        writer.update { $0.den = .sample }
        notify(.stateReplaced(store.snapshot.den.focusedDeskID))
        writer.update { $0.activeDrag = nil }
        notify(.clearInputRequests)
        writer.update {
            $0.recentlyRemovedBoards.removeAll()
            $0.recentlyDiscardedDrawerItems.removeAll()
            $0.notifications.removeAll()
        }
        notify(.clearWindowReferences)
        if store.snapshot.activeDrag == nil { _ = persist?(store.snapshot.den) }
        notify(.finished)
    }
}
