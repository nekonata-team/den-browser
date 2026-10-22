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
    @ObservationIgnored let notificationOperations: NotificationOperations
    @ObservationIgnored let boardCreation: BoardCreation
    @ObservationIgnored let boardRemoval: BoardRemoval
    @ObservationIgnored let boardSizing: BoardSizing
    @ObservationIgnored let deskLifecycle: DeskLifecycle
    @ObservationIgnored let deskUpdates: DeskUpdates
    @ObservationIgnored let deskMovement: DeskMovement
    @ObservationIgnored let denReset: DenReset

    @ObservationIgnored let boardMovement: BoardMovement

    var deskPresetOperations: DeskPresetOperations {
        DeskPresetOperations(state: data, writer: writer, persist: onDeskPresetsSave ?? { _ in false })
    }

    var state: DenState {
        get { data.snapshot.den }
        set { writer.update { $0.den = newValue } }
    }

    var deskPresets: [PersonalDeskPreset] {
        data.snapshot.deskPresets
    }

    var recentItems: [RecentItem] {
        get { data.snapshot.recentItems }
        set { writer.update { $0.recentItems = newValue } }
    }

    var notifications: [DenNotification] {
        data.snapshot.notifications
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

    let boardRuntimes: DenBoardRuntimes

    var webRuntimes: [BoardID: WebRuntime] {
        get { boardRuntimes.web }
        set { boardRuntimes.web = newValue }
    }

    var terminalRuntimes: [BoardID: TerminalRuntime] {
        get { boardRuntimes.terminal }
        set { boardRuntimes.terminal = newValue }
    }
    @ObservationIgnored let facingCache: BoardFacingCache
    @ObservationIgnored let facingCapture: BoardFacingCapture
    @ObservationIgnored let presetFacingStore: PresetFacingStore

    @ObservationIgnored let drawerPresentations = NSHashTable<DenController>.weakObjects()
    @ObservationIgnored let onRuntimeOwnerChange: ((BoardID, DenController?) -> Void)?
    @ObservationIgnored let onSave: ((DenState) -> Bool)?
    @ObservationIgnored let onDeferredSave: (() -> Void)?
    @ObservationIgnored let onDeskPresetsSave: (([PersonalDeskPreset]) -> Bool)?
    @ObservationIgnored let onRecentItemsSave: (([RecentItem]) -> Bool)?
    @ObservationIgnored var onDenOperationEvent: (DenOperationEvent) -> Void = { _ in }

    init(
        state: DenState,
        facingDisk: BoardFacingDiskCache? = nil,
        presetFacingDisk: PresetFacingDiskStore? = nil,
        deskPresets: [PersonalDeskPreset] = [],
        recentItems: [RecentItem] = [],
        onSave: ((DenState) -> Bool)? = nil,
        onDeferredSave: (() -> Void)? = nil,
        onDeskPresetsSave: (([PersonalDeskPreset]) -> Bool)? = nil,
        onRecentItemsSave: (([RecentItem]) -> Bool)? = nil,
        onRuntimeOwnerChange: ((BoardID, DenController?) -> Void)? = nil
    ) {
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: state, deskPresets: deskPresets, recentItems: recentItems))
        let persistState: ((DenState) -> Bool)? = onSave.map { persist in
            { persist(DenController.normalizedPersistedState($0)) }
        }
        boardRuntimes = DenBoardRuntimes { boardID in onRuntimeOwnerChange?(boardID, nil) }
        data = shared.store
        writer = shared.writer
        notificationOperations = NotificationOperations(store: shared.store, writer: shared.writer)
        deskLifecycle = DeskLifecycle(store: shared.store, writer: shared.writer, persist: persistState)
        deskUpdates = DeskUpdates(store: shared.store, writer: shared.writer, persist: persistState)
        deskMovement = DeskMovement(store: shared.store, writer: shared.writer, persist: persistState)
        denReset = DenReset(store: shared.store, writer: shared.writer, persist: persistState)
        boardMovement = BoardMovement(
            state: shared.store, writer: shared.writer,
            persist: persistState)
        boardSizing = BoardSizing(
            store: shared.store, writer: shared.writer,
            persist: persistState, deferredSave: onDeferredSave)
        boardRemoval = BoardRemoval(
            store: shared.store, writer: shared.writer,
            persist: persistState)
        boardCreation = BoardCreation(
            store: shared.store, writer: shared.writer,
            persist: persistState,
            persistRecent: onRecentItemsSave,
            directoryExists: { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            })
        self.onSave = onSave
        self.onDeferredSave = onDeferredSave
        self.onDeskPresetsSave = onDeskPresetsSave
        self.onRecentItemsSave = onRecentItemsSave
        self.onRuntimeOwnerChange = onRuntimeOwnerChange
        let cache = BoardFacingCache(disk: facingDisk)
        facingCache = cache
        facingCapture = BoardFacingCapture(cache: cache)
        presetFacingStore = PresetFacingStore(disk: presetFacingDisk)
    }
}
