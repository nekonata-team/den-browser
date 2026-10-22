import DenApplication
import DenDomain
import Foundation
import Testing

@MainActor
struct DrawerItemsTests {
    @Test func keepValidatesBeforeNotificationAndPreservesDistinctDuplicates() throws {
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let original = shared.store.snapshot
        var events: [String] = []
        let items = DrawerItems(
            store: shared.store, writer: shared.writer,
            persist: { _ in
                events.append("save")
                return false
            })
        let notify: (DrawerItems.Notice) -> Void = { notice in
            switch notice {
            case .willKeep: events.append("prepare")
            case .didKeep(let id):
                #expect(shared.store.snapshot.den.drawerItems.first?.id == id)
                events.append("present")
            default: Issue.record("Unexpected keep notice")
            }
        }
        #expect(items.keep(try #require(URL(string: "ftp://example.com/")), notify: notify) == nil)
        #expect(events.isEmpty)
        #expect(shared.store.snapshot == original)

        let url = try #require(URL(string: "https://example.com/"))
        let first = try #require(items.keep(url, notify: notify))
        let second = try #require(items.keep(url, notify: notify))

        #expect(first != second)
        #expect(shared.store.snapshot.den.drawerItems.map(\.id) == [second, first])
        #expect(events == ["prepare", "present", "save", "prepare", "present", "save"])
    }

    @Test func discardNotifiesAfterMutationBeforeSaveAndMissingTargetsDoNothing() throws {
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        var initial = DenSharedState(den: .sample)
        initial.den.drawerItems = [item]
        let shared = DenStateStore.make(initialState: initial)
        var events: [String] = []
        let items = DrawerItems(
            store: shared.store, writer: shared.writer,
            persist: { _ in
                events.append("save")
                return false
            })
        #expect(!items.discard(UUID(), notify: { _ in Issue.record("Missing item must not notify") }))
        #expect(shared.store.snapshot == initial)
        #expect(events.isEmpty)

        let discarded = items.discard(item.id, focusNext: false) { notice in
            guard case .didDiscard(let id, let previous, let advancesPeek, let focusNext) = notice else {
                Issue.record("Unexpected discard notice")
                return
            }
            #expect(id == item.id)
            #expect(previous == [item])
            #expect(advancesPeek)
            #expect(!focusNext)
            #expect(shared.store.snapshot.den.drawerItems.isEmpty)
            #expect(shared.store.snapshot.recentlyDiscardedDrawerItems == [item])
            events.append("repair")
        }
        #expect(discarded)
        #expect(events == ["repair", "save"])
        #expect(shared.store.snapshot.recentlyDiscardedDrawerItems == [item])
    }

    @Test func clearCapsHistoryAndRestoreConsumesNewestAfterPreparation() throws {
        let url = try #require(URL(string: "https://example.com/"))
        let originals = (0..<(DrawerItems.maximumDiscardHistoryCount + 2)).map {
            DrawerItem(url: url, title: "Item \($0)")
        }
        var initial = DenSharedState(den: .sample)
        initial.den.drawerItems = originals
        let shared = DenStateStore.make(initialState: initial)
        var events: [String] = []
        let items = DrawerItems(
            store: shared.store, writer: shared.writer,
            persist: { _ in
                events.append("save")
                return true
            })
        #expect(items.restore(notify: { _ in Issue.record("Empty history must not notify") }) == nil)
        #expect(events.isEmpty)
        items.clear { notice in
            guard case .didClear = notice else {
                Issue.record("Unexpected clear notice")
                return
            }
            #expect(shared.store.snapshot.den.drawerItems.isEmpty)
            events.append("clear")
        }
        #expect(
            shared.store.snapshot.recentlyDiscardedDrawerItems
                == Array(originals.prefix(DrawerItems.maximumDiscardHistoryCount)))

        let restored = items.restore { notice in
            switch notice {
            case .willRestore:
                #expect(shared.store.snapshot.den.drawerItems.isEmpty)
                #expect(shared.store.snapshot.recentlyDiscardedDrawerItems.first == originals.first)
                events.append("prepare")
            case .didRestore(let id):
                #expect(id == originals[0].id)
                #expect(shared.store.snapshot.den.drawerItems == [originals[0]])
                #expect(shared.store.snapshot.recentlyDiscardedDrawerItems.first == originals[1])
                events.append("present")
            default: Issue.record("Unexpected restore notice")
            }
        }
        #expect(restored == originals[0].id)
        #expect(events == ["clear", "save", "prepare", "present", "save"])
    }

    @Test func metadataSavesOnlySupportedChangesAndDragDefersPersistence() throws {
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")), title: "Original")
        var initial = DenSharedState(den: .sample)
        initial.den.drawerItems = [item]
        let shared = DenStateStore.make(initialState: initial)
        var saves = 0
        let items = DrawerItems(
            store: shared.store, writer: shared.writer,
            persist: { _ in
                saves += 1
                return true
            })
        items.update(UUID(), url: item.url, title: "Missing")
        items.update(item.id, url: URL(string: "ftp://example.com/"), title: "")
        items.update(item.id, url: item.url, title: item.title)
        #expect(saves == 0)
        #expect(shared.store.snapshot == initial)

        let nextURL = try #require(URL(string: "https://next.example/"))
        items.update(item.id, url: nextURL, title: "Next")
        #expect(saves == 1)
        #expect(shared.store.snapshot.den.drawerItems[0].url == nextURL)
        shared.writer.update { $0.activeDrag = .desk($0.den.focusedDeskID) }
        items.update(item.id, url: nil, title: "During drag")
        #expect(saves == 1)
        #expect(shared.store.snapshot.den.drawerItems[0].title == "During drag")
    }
}
