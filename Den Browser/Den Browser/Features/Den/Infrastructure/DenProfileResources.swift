import AppKit
import DenApplication
import DenDomain
import Foundation
import Observation

@MainActor
@Observable
final class DenProfileResources {
    let data: DenStateStore
    @ObservationIgnored private let writer: DenStateWriter

    var state: DenState {
        get { data.snapshot.den }
        set { writer.update { $0.den = newValue } }
    }

    var deskPresets: [PersonalDeskPreset] {
        get { data.snapshot.deskPresets }
        set { writer.update { $0.deskPresets = newValue } }
    }

    var recentItems: [RecentItem] {
        get { data.snapshot.recentItems }
        set { writer.update { $0.recentItems = newValue } }
    }

    var notifications: [DenNotification] {
        get { data.snapshot.notifications }
        set { writer.update { $0.notifications = newValue } }
    }

    var activeDrag: ActiveDrag? {
        get { data.snapshot.activeDrag }
        set { writer.update { $0.activeDrag = newValue } }
    }

    var recentlyRemovedBoards: [RecentlyRemovedBoard] {
        get { data.snapshot.recentlyRemovedBoards }
        set { writer.update { $0.recentlyRemovedBoards = newValue } }
    }

    var recentlyDiscardedDrawerItems: [DrawerItem] {
        get { data.snapshot.recentlyDiscardedDrawerItems }
        set { writer.update { $0.recentlyDiscardedDrawerItems = newValue } }
    }

    var webRuntimes: [BoardID: WebBoardRuntime] = [:]
    @ObservationIgnored var terminalRuntimes: [BoardID: TerminalRuntime] = [:]
    @ObservationIgnored let drawerPresentations = NSHashTable<DenStore>.weakObjects()
    @ObservationIgnored let onRuntimeOwnerChange: ((BoardID, DenStore?) -> Void)?
    @ObservationIgnored let onSave: ((DenState) -> Bool)?
    @ObservationIgnored let onDeferredSave: (() -> Void)?
    @ObservationIgnored let onDeskPresetsSave: (([PersonalDeskPreset]) -> Bool)?
    @ObservationIgnored let onRecentItemsSave: (([RecentItem]) -> Bool)?
    @ObservationIgnored var onDenOperationEvent: (DenOperationEvent) -> Void = { _ in }

    init(
        state: DenState,
        deskPresets: [PersonalDeskPreset] = [],
        recentItems: [RecentItem] = [],
        onSave: ((DenState) -> Bool)? = nil,
        onDeferredSave: (() -> Void)? = nil,
        onDeskPresetsSave: (([PersonalDeskPreset]) -> Bool)? = nil,
        onRecentItemsSave: (([RecentItem]) -> Bool)? = nil,
        onRuntimeOwnerChange: ((BoardID, DenStore?) -> Void)? = nil
    ) {
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: state, deskPresets: deskPresets, recentItems: recentItems))
        data = shared.store
        writer = shared.writer
        self.onSave = onSave
        self.onDeferredSave = onDeferredSave
        self.onDeskPresetsSave = onDeskPresetsSave
        self.onRecentItemsSave = onRecentItemsSave
        self.onRuntimeOwnerChange = onRuntimeOwnerChange
    }
}
