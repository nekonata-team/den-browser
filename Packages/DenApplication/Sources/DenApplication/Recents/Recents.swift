public import DenDomain
import Foundation

public struct Recents {
    public static let maximumItemCount = 500

    private let store: DenStateReader
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?
    private let persistRecent: (([RecentItem]) -> Bool)?

    public init(
        store: DenStateReader, writer: DenStateWriter,
        persist: ((DenState) -> Bool)? = nil, persistRecent: (([RecentItem]) -> Bool)? = nil
    ) {
        self.store = store
        self.writer = writer
        self.persist = persist
        self.persistRecent = persistRecent
    }

    public func record(_ item: RecentItem) {
        let original = store.snapshot.recentItems
        let itemToSave: RecentItem
        if case .url(let url, nil) = item, let title = original.first(where: { $0 == item })?.title {
            itemToSave = .url(url, title: title)
        } else {
            itemToSave = item
        }
        writer.update {
            $0.recentItems.removeAll { $0 == itemToSave }
            $0.recentItems.insert(itemToSave, at: 0)
            if $0.recentItems.count > Self.maximumItemCount {
                $0.recentItems.removeLast($0.recentItems.count - Self.maximumItemCount)
            }
        }
        saveOrRestore(original)
    }

    public func remove(_ item: RecentItem) {
        let original = store.snapshot.recentItems
        guard original.contains(item) else { return }
        writer.update { $0.recentItems.removeAll { $0 == item } }
        saveOrRestore(original)
    }

    public func clear() {
        let original = store.snapshot.recentItems
        guard !original.isEmpty else { return }
        writer.update { $0.recentItems = [] }
        saveOrRestore(original)
    }

    public func updateTitle(for url: URL, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = store.snapshot.recentItems
        guard !trimmed.isEmpty, let index = original.firstIndex(of: .url(url)),
            case .url(let recentURL, nil) = original[index]
        else { return }
        writer.update { $0.recentItems[index] = .url(recentURL, title: trimmed) }
        saveOrRestore(original)
    }

    private func saveOrRestore(_ original: [RecentItem]) {
        let saved: Bool
        if let persist {
            saved = store.snapshot.activeDrag == nil && persist(store.snapshot.den)
        } else {
            saved = persistRecent?(store.snapshot.recentItems) ?? true
        }
        if !saved { writer.update { $0.recentItems = original } }
    }
}
