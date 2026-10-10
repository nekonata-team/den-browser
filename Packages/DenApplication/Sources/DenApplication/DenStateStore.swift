import Foundation
import Observation

/// The Profile's source of truth.
///
/// Readers receive this object without its write capability.
@MainActor
@Observable
public final class DenStateStore {
    public private(set) var snapshot: DenSharedState

    private init(snapshot: DenSharedState) {
        self.snapshot = snapshot
    }

    public static func make(initialState: DenSharedState) -> (store: DenStateStore, writer: DenStateWriter) {
        let store = DenStateStore(snapshot: initialState)
        return (store, DenStateWriter(store: store))
    }

    fileprivate func commit(_ snapshot: DenSharedState) {
        guard snapshot != self.snapshot else { return }
        self.snapshot = snapshot
    }
}

/// Retained only by the Application adapter that performs shared-data operations.
@MainActor
public final class DenStateWriter {
    private let store: DenStateStore

    fileprivate init(store: DenStateStore) {
        self.store = store
    }

    public func update(_ mutation: (inout DenSharedState) -> Void) {
        var snapshot = store.snapshot
        mutation(&snapshot)
        store.commit(snapshot)
    }
}
