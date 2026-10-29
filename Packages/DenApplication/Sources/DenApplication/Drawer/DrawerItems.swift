public import DenDomain
import Foundation

public struct DrawerItems {
    public static let maximumDiscardHistoryCount = 10

    public enum Notice {
        case willKeep
        case didKeep(UUID)
        case willRestore
        case didRestore(UUID)
        case didDiscard(UUID, previousItems: [DrawerItem], advancesPeek: Bool, focusNext: Bool)
        case didClear
    }

    private let store: DenStateReader
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?

    public init(store: DenStateReader, writer: DenStateWriter, persist: ((DenState) -> Bool)? = nil) {
        self.store = store
        self.writer = writer
        self.persist = persist
    }

    @discardableResult
    public func keep(_ url: URL, title: String? = nil, notify: (Notice) -> Void) -> UUID? {
        guard WebURLPolicy.isSupported(url) else { return nil }
        return keep(DrawerItem(url: url, title: title), notify: notify)
    }

    @discardableResult
    public func keep(terminal: TerminalBoardState, title: String? = nil, notify: (Notice) -> Void) -> UUID {
        keep(DrawerItem(terminal: terminal, title: title), notify: notify)
    }

    private func keep(_ item: DrawerItem, notify: (Notice) -> Void) -> UUID {
        notify(.willKeep)
        writer.update { $0.den.drawerItems.insert(item, at: 0) }
        notify(.didKeep(item.id))
        save()
        return item.id
    }

    @discardableResult
    public func discard(_ id: UUID, focusNext: Bool = true, notify: (Notice) -> Void) -> Bool {
        remove(id, recordsHistory: true, advancesPeek: true, focusNext: focusNext, notify: notify)
    }

    @discardableResult
    func consume(_ id: UUID, notify: (Notice) -> Void) -> Bool {
        remove(id, recordsHistory: false, advancesPeek: false, focusNext: true, notify: notify)
    }

    private func remove(
        _ id: UUID, recordsHistory: Bool, advancesPeek: Bool, focusNext: Bool, notify: (Notice) -> Void
    ) -> Bool {
        guard let index = store.snapshot.den.drawerItems.firstIndex(where: { $0.id == id }) else { return false }
        let previousItems = store.snapshot.den.drawerItems
        if recordsHistory { remember([previousItems[index]]) }
        writer.update { $0.den.drawerItems.remove(at: index) }
        notify(.didDiscard(id, previousItems: previousItems, advancesPeek: advancesPeek, focusNext: focusNext))
        save()
        return true
    }

    @discardableResult
    public func restore(notify: (Notice) -> Void) -> UUID? {
        guard let item = store.snapshot.recentlyDiscardedDrawerItems.first else { return nil }
        notify(.willRestore)
        writer.update {
            $0.den.drawerItems.insert(item, at: 0)
            $0.recentlyDiscardedDrawerItems.removeFirst()
        }
        notify(.didRestore(item.id))
        save()
        return item.id
    }

    public func update(_ id: UUID, url: URL?, title: String?) {
        guard let index = store.snapshot.den.drawerItems.firstIndex(where: { $0.id == id }) else { return }
        var item = store.snapshot.den.drawerItems[index]
        guard case .web = item.content else { return }
        if let url, WebURLPolicy.isSupported(url) { item.content = .web(url) }
        if let title, !title.isEmpty { item.title = title }
        guard item != store.snapshot.den.drawerItems[index] else { return }
        writer.update { $0.den.drawerItems[index] = item }
        save()
    }

    public func updateTerminal(_ id: UUID, workingDirectory: String? = nil, title: String? = nil) {
        guard let index = store.snapshot.den.drawerItems.firstIndex(where: { $0.id == id }) else { return }
        var item = store.snapshot.den.drawerItems[index]
        guard case .terminal(let session) = item.content else { return }
        if let workingDirectory {
            switch session {
            case .shell: item.content = .terminal(.shell(workingDirectory: workingDirectory))
            case .zmx(var zmx):
                zmx.workingDirectory = workingDirectory
                item.content = .terminal(.zmx(zmx))
            case .zellij: break
            }
        }
        if let title, !title.isEmpty { item.title = title }
        guard item != store.snapshot.den.drawerItems[index] else { return }
        writer.update { $0.den.drawerItems[index] = item }
        save()
    }

    public func clear(notify: (Notice) -> Void) {
        remember(store.snapshot.den.drawerItems)
        writer.update { $0.den.drawerItems = [] }
        notify(.didClear)
        save()
    }

    private func remember(_ items: [DrawerItem]) {
        writer.update {
            $0.recentlyDiscardedDrawerItems.insert(contentsOf: items, at: 0)
            let overflow = $0.recentlyDiscardedDrawerItems.count - Self.maximumDiscardHistoryCount
            if overflow > 0 { $0.recentlyDiscardedDrawerItems.removeLast(overflow) }
        }
    }

    private func save() {
        guard store.snapshot.activeDrag == nil else { return }
        _ = persist?(store.snapshot.den)
    }
}
