import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@MainActor
struct RecentsTests {
    enum Mutation: CaseIterable { case record, remove, clear, title }

    @Test func recordingReusesTitlesDeduplicatesAndCapsNewestFirst() throws {
        // Arrange
        let url = try #require(URL(string: "https://example.com/titled"))
        var original = (0..<(Recents.maximumItemCount - 1)).map { RecentItem.search("Query \($0)") }
        original.append(.url(url, title: "Known title"))
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample, recentItems: original))
        let recents = Recents(store: shared.reader, writer: shared.writer)

        // Act
        recents.record(.url(url))
        let promoted = shared.store.snapshot.recentItems
        recents.record(.search("New query"))
        recents.record(.search("NEW   QUERY"))

        // Assert
        #expect(promoted.count == Recents.maximumItemCount)
        #expect(promoted.first?.title == "Known title")
        #expect(shared.store.snapshot.recentItems.count == Recents.maximumItemCount)
        #expect(shared.store.snapshot.recentItems[0] == .search("new query"))
        #expect(shared.store.snapshot.recentItems[1].title == "Known title")
        #expect(!shared.store.snapshot.recentItems.contains(original[original.count - 2]))
    }

    @Test(arguments: [
        RecentItem.url(URL(string: "https://example.com/")!, title: "Example"),
        .search("swift observation"), .terminal(workingDirectory: "/tmp"),
        .zellij(sessionName: "project"), .zmx(sessionName: "project"),
    ])
    func removePersistsOnlyRemainingItems(_ item: RecentItem) {
        // Arrange
        let remaining: [RecentItem] = [.search("first"), .search("last")]
        let initial = DenSharedState(den: .sample, recentItems: [remaining[0], item, remaining[1]])
        let shared = DenStateStore.make(initialState: initial)
        var saved: [RecentItem] = []
        let recents = Recents(
            store: shared.reader, writer: shared.writer,
            persistRecent: {
                saved = $0
                return true
            })

        // Act
        recents.remove(item)

        // Assert
        #expect(shared.store.snapshot.recentItems == remaining)
        #expect(saved == remaining)
        #expect(shared.store.snapshot.den == initial.den)
    }

    @Test(arguments: Mutation.allCases, [false, true])
    func failedWritesRestoreItemsMetadataAndOrder(mutation: Mutation, savesProfile: Bool) throws {
        // Arrange
        let url = try #require(URL(string: "https://example.com/"))
        let original: [RecentItem] = [.url(url), .search("keep")]
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample, recentItems: original))
        var profileSaves = 0
        var recentSaves = 0
        let recents = Recents(
            store: shared.reader, writer: shared.writer,
            persist: savesProfile
                ? { _ in
                    profileSaves += 1
                    return false
                } : nil,
            persistRecent: { _ in
                recentSaves += 1
                return false
            })

        // Act
        switch mutation {
        case .record: recents.record(.search("new"))
        case .remove: recents.remove(original[0])
        case .clear: recents.clear()
        case .title: recents.updateTitle(for: url, title: "New title")
        }

        // Assert
        #expect(shared.store.snapshot.recentItems == original)
        #expect(shared.store.snapshot.recentItems[0].title == nil)
        #expect(profileSaves == (savesProfile ? 1 : 0))
        #expect(recentSaves == (savesProfile ? 0 : 1))
    }

    @Test func titleIsTrimmedAndFilledOnlyOnceWithoutReordering() throws {
        // Arrange
        let url = try #require(URL(string: "https://example.com/"))
        let original: [RecentItem] = [.search("first"), .url(url), .search("last")]
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample, recentItems: original))
        var saves = 0
        let recents = Recents(
            store: shared.reader, writer: shared.writer,
            persistRecent: { _ in
                saves += 1
                return true
            })

        // Act
        recents.updateTitle(for: url, title: "   ")
        recents.updateTitle(for: url, title: "  First title  ")
        recents.updateTitle(for: url, title: "Later title")
        recents.updateTitle(for: try #require(URL(string: "https://missing.example/")), title: "Missing")

        // Assert
        #expect(shared.store.snapshot.recentItems == original)
        #expect(shared.store.snapshot.recentItems[1].title == "First title")
        #expect(saves == 1)
    }

    @Test func emptyClearAndMissingRemovalDoNotSave() {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let recents = Recents(
            store: shared.reader, writer: shared.writer,
            persistRecent: { _ in
                Issue.record("No-op must not save")
                return false
            })

        // Act
        recents.remove(.search("missing"))
        recents.clear()

        // Assert
        #expect(shared.store.snapshot.recentItems.isEmpty)
    }

    @Test(arguments: [false, true])
    func dragPreservesPrimaryAndRecentOnlyPersistencePolicies(savesProfile: Bool) {
        // Arrange
        let original: [RecentItem] = [.search("old")]
        var initial = DenSharedState(den: .sample, recentItems: original)
        initial.activeDrag = .desk(initial.den.focusedDeskID)
        let shared = DenStateStore.make(initialState: initial)
        var recentSaves = 0
        let recents = Recents(
            store: shared.reader, writer: shared.writer,
            persist: savesProfile
                ? { _ in
                    Issue.record("Drag must not save Profile")
                    return true
                } : nil,
            persistRecent: { _ in
                recentSaves += 1
                return true
            })

        // Act
        recents.clear()

        // Assert
        #expect(shared.store.snapshot.recentItems == (savesProfile ? original : []))
        #expect(recentSaves == (savesProfile ? 0 : 1))
        #expect(shared.store.snapshot.activeDrag == initial.activeDrag)
    }
}
