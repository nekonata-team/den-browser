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
    @ObservationIgnored let boardUpdates: BoardUpdates
    @ObservationIgnored let boardCreation: BoardCreation
    @ObservationIgnored let inputOpening: InputOpening
    @ObservationIgnored let tutorialProgress: TutorialProgress
    @ObservationIgnored let recents: Recents
    @ObservationIgnored let boardRemoval: BoardRemoval
    @ObservationIgnored let boardSizing: BoardSizing
    @ObservationIgnored let deskLifecycle: DeskLifecycle
    @ObservationIgnored let deskUpdates: DeskUpdates
    @ObservationIgnored let deskMovement: DeskMovement
    @ObservationIgnored let denReset: DenReset
    @ObservationIgnored let drawerItems: DrawerItems
    @ObservationIgnored let drawerPlacement: DrawerPlacement

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

    var recentItems: [RecentItem] { data.snapshot.recentItems }

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

    @ObservationIgnored let windowConnections = NSHashTable<RuntimeWindowConnection>.weakObjects()
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
        onRecentItemsSave: (([RecentItem]) -> Bool)? = nil
    ) {
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: state, deskPresets: deskPresets, recentItems: recentItems))
        let persistState: ((DenState) -> Bool)? = onSave.map { persist in
            { persist(DenStateNormalization.normalize($0)) }
        }
        boardRuntimes = DenBoardRuntimes()
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
        boardUpdates = BoardUpdates(store: shared.store, writer: shared.writer, persist: persistState)
        recents = Recents(
            store: shared.store, writer: shared.writer, persist: persistState, persistRecent: onRecentItemsSave)
        boardCreation = BoardCreation(
            store: shared.store, writer: shared.writer, recents: recents,
            persist: persistState,
            directoryExists: TerminalWorkingDirectory.exists)
        drawerItems = DrawerItems(store: shared.store, writer: shared.writer, persist: persistState)
        drawerPlacement = DrawerPlacement(store: shared.store, creation: boardCreation, items: drawerItems)
        inputOpening = InputOpening(creation: boardCreation, drawer: drawerItems)
        tutorialProgress = TutorialProgress(store: shared.store, writer: shared.writer)
        self.onSave = onSave
        self.onDeferredSave = onDeferredSave
        self.onDeskPresetsSave = onDeskPresetsSave
        self.onRecentItemsSave = onRecentItemsSave
        let cache = BoardFacingCache(disk: facingDisk)
        facingCache = cache
        facingCapture = BoardFacingCapture(cache: cache)
        presetFacingStore = PresetFacingStore(disk: presetFacingDisk)
    }
}
