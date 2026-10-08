import DenApplication
import DenDomain
import Foundation
import Observation
import Synchronization
import Testing

@MainActor
struct DenStateStoreTests {
    @Test func metadataChangesPublishEvenWhenRecentItemIdentityIsUnchanged() {
        // Arrange
        let url = URL(string: "https://shared.example/")!
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample, recentItems: [.url(url)]))
        let changed = Mutex(false)
        withObservationTracking {
            _ = shared.store.snapshot.recentItems
        } onChange: {
            changed.withLock { $0 = true }
        }

        // Act
        shared.writer.update { $0.recentItems[0] = .url(url, title: "Page title") }

        // Assert
        #expect(shared.store.snapshot.recentItems.first?.title == "Page title")
        #expect(changed.withLock { $0 })
    }

    @Test func readersShareOneSourceAndSnapshotsAreValues() {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let firstReader = shared.store
        let secondReader = shared.store
        var detachedSnapshot = firstReader.snapshot
        detachedSnapshot.den.drawerItems.append(DrawerItem(url: URL(string: "https://detached.example/")!))
        let item = DrawerItem(url: URL(string: "https://shared.example/")!)

        // Act
        shared.writer.update { $0.den.drawerItems.append(item) }

        // Assert
        #expect(firstReader === secondReader)
        #expect(firstReader.snapshot.den.drawerItems == [item])
        #expect(secondReader.snapshot.den.drawerItems == [item])
        #expect(detachedSnapshot.den.drawerItems != firstReader.snapshot.den.drawerItems)
    }

    @Test func updatingSharedStateInvalidatesReadsAndCommitsTheCompleteValue() {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let item = DrawerItem(url: URL(string: "https://shared.example/")!)
        let changed = Mutex(false)
        withObservationTracking {
            _ = shared.store.snapshot
        } onChange: {
            changed.withLock { $0 = true }
        }

        // Act
        shared.writer.update {
            $0.den.drawerItems.append(item)
            $0.recentlyDiscardedDrawerItems.append(item)
        }

        // Assert
        #expect(changed.withLock { $0 })
        #expect(shared.store.snapshot.den.drawerItems == [item])
        #expect(shared.store.snapshot.recentlyDiscardedDrawerItems == [item])
    }

    @Test func unchangedUpdateDoesNotInvalidateReads() {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let changed = Mutex(false)
        withObservationTracking {
            _ = shared.store.snapshot
        } onChange: {
            changed.withLock { $0 = true }
        }

        // Act
        shared.writer.update { _ in }

        // Assert
        #expect(!changed.withLock { $0 })
    }
}
