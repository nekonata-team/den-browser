public import DenApplication
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

    public static func make(initialState: DenSharedState) -> (
        store: DenStateStore, reader: DenStateReader, writer: DenStateWriter
    ) {
        let store = DenStateStore(snapshot: initialState)
        let reader = DenStateReader { store.snapshot }
        let writer = DenStateWriter { mutation in
            var snapshot = store.snapshot
            mutation(&snapshot)
            store.commit(snapshot)
        }
        return (store, reader, writer)
    }

    fileprivate func commit(_ snapshot: DenSharedState) {
        guard snapshot != self.snapshot else { return }
        self.snapshot = snapshot
    }
}
