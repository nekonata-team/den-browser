import AppKit
import DenDomain
import Foundation
import Observation

@MainActor
@Observable
final class DenStorage {
    var state: DenState
    var deskPresets: [PersonalDeskPreset]
    var recentItems: [RecentItem]
    var notifications: [DenNotification] = []
    var activeDrag: ActiveDrag?
    var recentlyRemovedBoards: [RecentlyRemovedBoard] = []
    var recentlyDiscardedDrawerItems: [DrawerItem] = []

    var webRuntimes: [UUID: WebBoardRuntime] = [:]
    @ObservationIgnored var terminalRuntimes: [UUID: TerminalRuntime] = [:]
    @ObservationIgnored let drawerPresentations = NSHashTable<DenStore>.weakObjects()
    @ObservationIgnored let onRuntimeOwnerChange: ((UUID, DenStore?) -> Void)?
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
        onRuntimeOwnerChange: ((UUID, DenStore?) -> Void)? = nil
    ) {
        self.state = state
        self.deskPresets = deskPresets
        self.recentItems = recentItems
        self.onSave = onSave
        self.onDeferredSave = onDeferredSave
        self.onDeskPresetsSave = onDeskPresetsSave
        self.onRecentItemsSave = onRecentItemsSave
        self.onRuntimeOwnerChange = onRuntimeOwnerChange
    }
}
