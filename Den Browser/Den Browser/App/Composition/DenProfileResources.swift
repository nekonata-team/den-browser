import AppKit
import DenApplication
import DenDomain
import DenInfrastructure
import DenModels
import Foundation
import Observation

@MainActor
@Observable
final class DenProfileResources {
    let store: DenStateStore
    @ObservationIgnored private let reader: DenStateReader
    @ObservationIgnored private let writer: DenStateWriter
    @ObservationIgnored let notificationOperations: NotificationOperations
    @ObservationIgnored let boardUpdates: BoardUpdates
    @ObservationIgnored let boardCreation: BoardCreation
    @ObservationIgnored let inputOpening: InputOpening
    @ObservationIgnored let tutorialProgress: TutorialProgress
    @ObservationIgnored let recents: Recents
    @ObservationIgnored let boardRemoval: BoardRemoval
    @ObservationIgnored let boardUndo: BoardUndo
    @ObservationIgnored let boardSizing: BoardSizing
    @ObservationIgnored let deskLifecycle: DeskLifecycle
    @ObservationIgnored let deskUpdates: DeskUpdates
    @ObservationIgnored let deskMovement: DeskMovement
    @ObservationIgnored let denReset: DenReset
    @ObservationIgnored let drawerItems: DrawerItems
    @ObservationIgnored let drawerPlacement: DrawerPlacement
    @ObservationIgnored let drawerTransfer: DrawerTransfer

    @ObservationIgnored let boardMovement: BoardMovement

    var deskPresetOperations: DeskPresetOperations {
        DeskPresetOperations(reader: reader, writer: writer, persist: onDeskPresetsSave ?? { _ in false })
    }

    var snapshot: DenSharedState { store.snapshot }

    var state: DenState {
        get { store.snapshot.den }
        set { writer.update { $0.den = newValue } }
    }

    var deskPresets: [PersonalDeskPreset] {
        store.snapshot.deskPresets
    }

    var recentItems: [RecentItem] { store.snapshot.recentItems }

    var notifications: [DenNotification] {
        store.snapshot.notifications
    }

    var activeDrag: ActiveDrag? {
        get { store.snapshot.activeDrag }
        set { writer.update { $0.activeDrag = newValue } }
    }

    var recentlyRemovedBoards: [RecentlyRemovedBoard] {
        get { store.snapshot.recentlyRemovedBoards }
        set { writer.update { $0.recentlyRemovedBoards = newValue } }
    }

    var recentlyDiscardedDrawerItems: [DrawerItem] {
        get { store.snapshot.recentlyDiscardedDrawerItems }
        set { writer.update { $0.recentlyDiscardedDrawerItems = newValue } }
    }

    let boardRuntimes: DenBoardRuntimes
    let drawerRuntimes = DenDrawerRuntimes()

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
            initialState: DenSharedState(den: state, deskPresets: deskPresets, recentItems: recentItems)
        )
        let persistState: ((DenState) -> Bool)? = onSave.map { persist in
            { persist(DenStateNormalization.normalize($0)) }
        }
        boardRuntimes = DenBoardRuntimes()
        store = shared.store
        reader = shared.reader
        writer = shared.writer
        notificationOperations = NotificationOperations(reader: shared.reader, writer: shared.writer)
        deskLifecycle = DeskLifecycle(reader: shared.reader, writer: shared.writer, persist: persistState)
        deskUpdates = DeskUpdates(reader: shared.reader, writer: shared.writer, persist: persistState)
        deskMovement = DeskMovement(reader: shared.reader, writer: shared.writer, persist: persistState)
        denReset = DenReset(reader: shared.reader, writer: shared.writer, persist: persistState)
        boardMovement = BoardMovement(
            reader: shared.reader,
            writer: shared.writer,
            persist: persistState
        )
        boardSizing = BoardSizing(
            reader: shared.reader,
            writer: shared.writer,
            persist: persistState,
            deferredSave: onDeferredSave
        )
        boardRemoval = BoardRemoval(
            reader: shared.reader,
            writer: shared.writer,
            persist: persistState
        )
        boardUndo = BoardUndo(reader: shared.reader, writer: shared.writer, persist: persistState)
        boardUpdates = BoardUpdates(reader: shared.reader, writer: shared.writer, persist: persistState)
        recents = Recents(
            reader: shared.reader,
            writer: shared.writer,
            persist: persistState,
            persistRecent: onRecentItemsSave
        )
        boardCreation = BoardCreation(
            reader: shared.reader,
            writer: shared.writer,
            recents: recents,
            persist: persistState,
            directoryExists: TerminalWorkingDirectory.exists
        )
        drawerItems = DrawerItems(reader: shared.reader, writer: shared.writer, persist: persistState)
        drawerPlacement = DrawerPlacement(
            reader: shared.reader,
            writer: shared.writer,
            creation: boardCreation,
            items: drawerItems
        )
        drawerTransfer = DrawerTransfer(reader: shared.reader, writer: shared.writer, persist: persistState)
        inputOpening = InputOpening(creation: boardCreation, drawer: drawerItems)
        tutorialProgress = TutorialProgress(reader: shared.reader, writer: shared.writer)
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
